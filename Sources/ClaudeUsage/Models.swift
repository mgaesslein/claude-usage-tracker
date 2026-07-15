import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, cursor, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini CLI"
        }
    }

    var defaultPath: String {
        let home = NSHomeDirectory()
        switch self {
        case .claude: return home + "/.claude"
        case .codex: return home + "/.codex"
        case .cursor: return home + "/Library/Application Support/Cursor/User/globalStorage"
        case .gemini: return home + "/.gemini"
        }
    }

    var pathHint: String {
        switch self {
        case .claude: return "CLAUDE_CONFIG_DIR of the login"
        case .codex: return "CODEX_HOME (contains auth.json)"
        case .cursor: return "Cursor globalStorage dir (contains state.vscdb)"
        case .gemini: return "Gemini config dir (contains oauth_creds.json)"
        }
    }
}

struct AccountConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var provider: Provider
    var path: String
}

struct UsageWindowInfo: Identifiable {
    var id: String { title }
    let title: String
    var utilization: Int?
    var resetsAt: Date?
}

struct FetchedUsage {
    var email: String?
    var plan: String?
    var windows: [UsageWindowInfo] = []
}

struct AccountStatus {
    var email = ""
    var plan = ""
    var windows: [UsageWindowInfo] = []
    var error: String?
    var lastUpdated: Date?
}

struct UsageFetchError: Error {
    let message: String
    var statusCode: Int?
}

enum AccountStorage {
    private static let key = "accounts.v1"

    static func load() -> [AccountConfig]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let accounts = try? JSONDecoder().decode([AccountConfig].self, from: data) else { return nil }
        return accounts
    }

    static func save(_ accounts: [AccountConfig]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// First-launch defaults: one account per tool that has credentials on this machine.
    static func detectDefaults() -> [AccountConfig] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var result: [AccountConfig] = []

        // Claude Code: every CLAUDE_CONFIG_DIR-style ~/.claude-* dir with a login,
        // falling back to the default ~/.claude login.
        var foundClaude = false
        if let entries = try? fm.contentsOfDirectory(atPath: home) {
            for name in entries.sorted() where name.hasPrefix(".claude-") {
                let dir = home + "/" + name
                if fm.fileExists(atPath: dir + "/.claude.json") {
                    let label = String(name.dropFirst(".claude-".count)).capitalized
                    result.append(AccountConfig(label: label, provider: .claude, path: dir))
                    foundClaude = true
                }
            }
        }
        if !foundClaude, fm.fileExists(atPath: home + "/.claude.json") {
            result.append(AccountConfig(label: "Claude", provider: .claude, path: Provider.claude.defaultPath))
        }

        if fm.fileExists(atPath: Provider.codex.defaultPath + "/auth.json") {
            result.append(AccountConfig(label: "Codex", provider: .codex, path: Provider.codex.defaultPath))
        }
        if fm.fileExists(atPath: Provider.cursor.defaultPath + "/state.vscdb") {
            result.append(AccountConfig(label: "Cursor", provider: .cursor, path: Provider.cursor.defaultPath))
        }
        if fm.fileExists(atPath: Provider.gemini.defaultPath + "/oauth_creds.json") {
            result.append(AccountConfig(label: "Gemini", provider: .gemini, path: Provider.gemini.defaultPath))
        }
        return result
    }
}
