import Foundation
import CryptoKit

struct AccountConfig {
    let label: String
    let configDir: String
}

// Add or edit accounts here. `configDir` must match the CLAUDE_CONFIG_DIR
// each Claude Code login uses (see the shell wrapper that switches between them).
let accounts: [AccountConfig] = [
    AccountConfig(label: "Work", configDir: NSHomeDirectory() + "/.claude-work"),
    AccountConfig(label: "Personal", configDir: NSHomeDirectory() + "/.claude-personal"),
]

struct UsageWindow {
    var utilization: Int?
    var resetsAt: Date?
}

struct AccountUsage: Identifiable {
    let id: String
    let label: String
    var email: String = ""
    var subscriptionType: String = ""
    var fiveHour = UsageWindow()
    var sevenDay = UsageWindow()
    var error: String?
    var lastUpdated: Date?
}

// Claude Code stores each login's OAuth token in the macOS keychain under
// "Claude Code-credentials-<sha256(configDir) prefix>" (or no suffix for the default dir).
func keychainServiceName(for configDir: String) -> String {
    let digest = SHA256.hash(data: Data(configDir.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "Claude Code-credentials-" + String(hex.prefix(8))
}

private func runSecurity(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

private func readCredentials(service: String) -> [String: Any]? {
    guard let raw = runSecurity(["find-generic-password", "-s", service, "-w"]),
          let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
    return oauth
}

func readAccessToken(service: String) -> String? {
    readCredentials(service: service)?["accessToken"] as? String
}

func readSubscriptionType(service: String) -> String? {
    readCredentials(service: service)?["subscriptionType"] as? String
}

func readEmail(configDir: String) -> String? {
    let path = configDir + "/.claude.json"
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauthAccount = obj["oauthAccount"] as? [String: Any],
          let email = oauthAccount["emailAddress"] as? String else { return nil }
    return email
}

private func parseISODate(_ s: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: s) { return d }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: s)
}

struct UsageFetchError: Error {
    let message: String
}

func fetchUsage(token: String) async -> Result<(five: UsageWindow, seven: UsageWindow), UsageFetchError> {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    request.httpMethod = "GET"
    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 10

    func parseWindow(_ obj: [String: Any], _ key: String) -> UsageWindow {
        var w = UsageWindow()
        if let dict = obj[key] as? [String: Any] {
            if let util = dict["utilization"] as? Double {
                w.utilization = Int(util.rounded())
            } else if let util = dict["utilization"] as? Int {
                w.utilization = util
            }
            if let resets = dict["resets_at"] as? String {
                w.resetsAt = parseISODate(resets)
            }
        }
        return w
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .failure(UsageFetchError(message: "No response"))
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                return .failure(UsageFetchError(message: "Rate limited, will retry"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return .failure(UsageFetchError(message: "Not authorized (token may need a refresh — open Claude Code for this account)"))
            }
            let bodyObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (bodyObj?["error"] as? [String: Any])?["message"] as? String
            return .failure(UsageFetchError(message: message ?? "HTTP \(http.statusCode)"))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(UsageFetchError(message: "Unexpected response format"))
        }
        return .success((parseWindow(obj, "five_hour"), parseWindow(obj, "seven_day")))
    } catch {
        return .failure(UsageFetchError(message: error.localizedDescription))
    }
}
