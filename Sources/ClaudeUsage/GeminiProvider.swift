import Foundation

// Gemini CLI stores OAuth tokens in ~/.gemini/oauth_creds.json. Quota comes
// from the Code Assist API. Access tokens expire hourly; refreshing requires
// the CLI's OAuth client credentials, which we only take from the environment
// (GEMINI_OAUTH_CLIENT_ID / GEMINI_OAUTH_CLIENT_SECRET) rather than shipping
// them in this repo — without them, open the Gemini CLI to refresh the token.
enum GeminiProvider {
    static func fetch(path: String) async -> Result<FetchedUsage, UsageFetchError> {
        guard let creds = readJSONFile(path + "/oauth_creds.json"),
              var token = creds["access_token"] as? String else {
            return .failure(UsageFetchError(message: "No credentials at \(path)/oauth_creds.json — sign in with `gemini`"))
        }

        let expiryMs = (creds["expiry_date"] as? Double) ?? 0
        if expiryMs > 0, Date(timeIntervalSince1970: expiryMs / 1000) < Date().addingTimeInterval(60) {
            switch await refreshToken(creds: creds) {
            case .success(let refreshed): token = refreshed
            case .failure(let error): return .failure(error)
            }
        }

        var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 10

        switch await httpJSON(request) {
        case .failure(let error):
            if error.statusCode == 401 || error.statusCode == 403 {
                return .failure(UsageFetchError(message: "Not authorized (token expired — run `gemini` once to refresh)"))
            }
            return .failure(error)
        case .success(let obj):
            var usage = FetchedUsage()
            usage.email = readJSONFile(path + "/google_accounts.json")?["active"] as? String

            var buckets: [[String: Any]] = []
            collectBuckets(obj, into: &buckets)
            usage.windows = buckets.compactMap { bucket in
                guard let remaining = bucket["remainingFraction"] as? Double else { return nil }
                var w = UsageWindowInfo(title: bucketTitle(bucket["modelId"] as? String))
                w.utilization = Int(((1 - remaining) * 100).rounded())
                if let reset = bucket["resetTime"] as? String { w.resetsAt = parseISODate(reset) }
                return w
            }
            .sorted { ($0.utilization ?? 0) > ($1.utilization ?? 0) }
            usage.windows = dedupeTitles(Array(usage.windows.prefix(3)))

            if usage.windows.isEmpty {
                return .failure(UsageFetchError(message: "No quota data in response"))
            }
            return .success(usage)
        }
    }

    private static func refreshToken(creds: [String: Any]) async -> Result<String, UsageFetchError> {
        let env = ProcessInfo.processInfo.environment
        guard let refreshToken = creds["refresh_token"] as? String,
              let clientID = env["GEMINI_OAUTH_CLIENT_ID"],
              let clientSecret = env["GEMINI_OAUTH_CLIENT_SECRET"] else {
            return .failure(UsageFetchError(message: "Token expired — run `gemini` once to refresh (or set GEMINI_OAUTH_CLIENT_ID/SECRET)"))
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 10

        switch await httpJSON(request) {
        case .failure(let error):
            return .failure(UsageFetchError(message: "Token refresh failed: \(error.message)"))
        case .success(let obj):
            guard let token = obj["access_token"] as? String else {
                return .failure(UsageFetchError(message: "Token refresh returned no access token"))
            }
            return .success(token)
        }
    }

    private static func collectBuckets(_ value: Any, into buckets: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if dict["remainingFraction"] != nil { buckets.append(dict) }
            for v in dict.values { collectBuckets(v, into: &buckets) }
        } else if let array = value as? [Any] {
            for v in array { collectBuckets(v, into: &buckets) }
        }
    }

    private static func bucketTitle(_ modelId: String?) -> String {
        guard let modelId, !modelId.isEmpty else { return "Quota" }
        if modelId.localizedCaseInsensitiveContains("pro") { return "Pro" }
        if modelId.localizedCaseInsensitiveContains("flash") { return "Flash" }
        return modelId
    }

    private static func dedupeTitles(_ windows: [UsageWindowInfo]) -> [UsageWindowInfo] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.title).inserted }
    }
}
