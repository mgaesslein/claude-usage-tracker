import Foundation

// Codex CLI stores OAuth tokens in $CODEX_HOME/auth.json. Usage comes from
// the same endpoint the CLI's /status command uses.
enum CodexProvider {
    static func fetch(path: String) async -> Result<FetchedUsage, UsageFetchError> {
        guard let auth = readJSONFile(path + "/auth.json"),
              let tokens = auth["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else {
            return .failure(UsageFetchError(message: "No credentials at \(path)/auth.json — sign in with `codex`"))
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        switch await httpJSON(request) {
        case .failure(let error):
            if error.statusCode == 401 || error.statusCode == 403 {
                return .failure(UsageFetchError(message: "Not authorized (token may need a refresh — run `codex` once)"))
            }
            return .failure(error)
        case .success(let obj):
            var usage = FetchedUsage()
            usage.email = obj["email"] as? String
            usage.plan = obj["plan_type"] as? String
            if let rateLimit = obj["rate_limit"] as? [String: Any] {
                if let w = parseWindow(rateLimit["primary_window"]) { usage.windows.append(w) }
                if let w = parseWindow(rateLimit["secondary_window"]) { usage.windows.append(w) }
            }
            if usage.windows.isEmpty {
                return .failure(UsageFetchError(message: "No rate limit windows in response"))
            }
            return .success(usage)
        }
    }

    private static func parseWindow(_ value: Any?) -> UsageWindowInfo? {
        guard let dict = value as? [String: Any] else { return nil }
        let seconds = (dict["limit_window_seconds"] as? Int) ?? 0
        var w = UsageWindowInfo(title: windowTitle(seconds: seconds))
        if let used = dict["used_percent"] as? Double {
            w.utilization = Int(used.rounded())
        } else if let used = dict["used_percent"] as? Int {
            w.utilization = used
        }
        if let resetAt = dict["reset_at"] as? Double {
            w.resetsAt = Date(timeIntervalSince1970: resetAt)
        }
        return w
    }

    private static func windowTitle(seconds: Int) -> String {
        guard seconds > 0 else { return "now" }
        if seconds < 172800 { return "\(max(1, seconds / 3600))h" }
        return "\(seconds / 86400)d"
    }
}
