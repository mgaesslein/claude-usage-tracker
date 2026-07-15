import Foundation
import CryptoKit

// Claude Code stores each login's OAuth token in the macOS keychain under
// "Claude Code-credentials-<sha256(configDir) prefix>", or plain
// "Claude Code-credentials" for the default ~/.claude directory.
enum ClaudeProvider {
    static func fetch(path: String) async -> Result<FetchedUsage, UsageFetchError> {
        let (oauth, email) = await Task.detached {
            (readCredentials(configDir: path), readEmail(configDir: path))
        }.value

        guard let token = oauth?["accessToken"] as? String else {
            return .failure(UsageFetchError(message: "No credentials found for \(path)"))
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        switch await httpJSON(request) {
        case .failure(let error):
            if error.statusCode == 401 || error.statusCode == 403 {
                return .failure(UsageFetchError(message: "Not authorized (token may need a refresh — open Claude Code for this account)"))
            }
            return .failure(error)
        case .success(let obj):
            var usage = FetchedUsage()
            usage.email = email
            usage.plan = oauth?["subscriptionType"] as? String
            usage.windows = [
                parseWindow(obj, key: "five_hour", title: "5h"),
                parseWindow(obj, key: "seven_day", title: "7d"),
            ]
            return .success(usage)
        }
    }

    private static func parseWindow(_ obj: [String: Any], key: String, title: String) -> UsageWindowInfo {
        var w = UsageWindowInfo(title: title)
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

    private static func keychainServices(for configDir: String) -> [String] {
        let digest = SHA256.hash(data: Data(configDir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        var services = ["Claude Code-credentials-" + String(hex.prefix(8))]
        if configDir == NSHomeDirectory() + "/.claude" {
            services.append("Claude Code-credentials")
        }
        return services
    }

    private static func runSecurity(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
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

    private static func readCredentials(configDir: String) -> [String: Any]? {
        for service in keychainServices(for: configDir) {
            if let raw = runSecurity(["find-generic-password", "-s", service, "-w"]),
               let data = raw.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let oauth = obj["claudeAiOauth"] as? [String: Any] {
                return oauth
            }
        }
        return nil
    }

    private static func readEmail(configDir: String) -> String? {
        // Custom CLAUDE_CONFIG_DIR logins keep .claude.json inside the dir;
        // the default ~/.claude login keeps it at ~/.claude.json.
        for path in [configDir + "/.claude.json", NSHomeDirectory() + "/.claude.json"] {
            if let obj = readJSONFile(path),
               let oauthAccount = obj["oauthAccount"] as? [String: Any],
               let email = oauthAccount["emailAddress"] as? String {
                return email
            }
        }
        return nil
    }
}
