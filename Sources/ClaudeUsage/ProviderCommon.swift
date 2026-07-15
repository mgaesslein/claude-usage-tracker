import Foundation

func parseISODate(_ s: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: s) { return d }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: s)
}

func readJSONFile(_ path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func httpJSON(_ request: URLRequest) async -> Result<[String: Any], UsageFetchError> {
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .failure(UsageFetchError(message: "No response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                return .failure(UsageFetchError(message: "Rate limited, will retry", statusCode: 429))
            }
            let bodyObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (bodyObj?["error"] as? [String: Any])?["message"] as? String
            return .failure(UsageFetchError(message: message ?? "HTTP \(http.statusCode)", statusCode: http.statusCode))
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(UsageFetchError(message: "Unexpected response format"))
        }
        return .success(obj)
    } catch {
        return .failure(UsageFetchError(message: error.localizedDescription))
    }
}

func decodeJWTClaims(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var b64 = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func fetchUsage(for account: AccountConfig) async -> Result<FetchedUsage, UsageFetchError> {
    switch account.provider {
    case .claude: return await ClaudeProvider.fetch(path: account.path)
    case .codex: return await CodexProvider.fetch(path: account.path)
    case .cursor: return await CursorProvider.fetch(path: account.path)
    case .gemini: return await GeminiProvider.fetch(path: account.path)
    }
}
