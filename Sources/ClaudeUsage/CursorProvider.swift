import Foundation
import SQLite3

// Cursor keeps its session JWT in the VS Code-style global state database
// (state.vscdb, key "cursorAuth/accessToken"). The web API authenticates via
// the WorkosCursorSessionToken cookie built from "<userId>::<JWT>".
enum CursorProvider {
    static func fetch(path: String) async -> Result<FetchedUsage, UsageFetchError> {
        let dbPath = path + "/state.vscdb"
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return .failure(UsageFetchError(message: "No state.vscdb at \(path)"))
        }

        let state = await Task.detached { readState(dbPath: dbPath) }.value
        guard let token = state.token else {
            return .failure(UsageFetchError(message: "No Cursor session found — sign in to Cursor"))
        }
        guard let sub = decodeJWTClaims(token)?["sub"] as? String,
              let userId = sub.split(separator: "|").last else {
            return .failure(UsageFetchError(message: "Could not parse Cursor session token"))
        }

        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.addValue("WorkosCursorSessionToken=\(userId)%3A%3A\(token)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 10

        switch await httpJSON(request) {
        case .failure(let error):
            if error.statusCode == 401 || error.statusCode == 403 {
                return .failure(UsageFetchError(message: "Not authorized (session expired — open Cursor and sign in)"))
            }
            return .failure(error)
        case .success(let obj):
            var usage = FetchedUsage()
            usage.email = state.email
            usage.plan = (obj["membershipType"] as? String)?.replacingOccurrences(of: "_", with: " ")
            let cycleEnd = (obj["billingCycleEnd"] as? String).flatMap(parseISODate)
            if let plan = (obj["individualUsage"] as? [String: Any])?["plan"] as? [String: Any] {
                if let total = percent(plan["totalPercentUsed"]) {
                    usage.windows.append(UsageWindowInfo(title: "Total", utilization: total, resetsAt: cycleEnd))
                }
                if let api = percent(plan["apiPercentUsed"]) {
                    usage.windows.append(UsageWindowInfo(title: "API", utilization: api, resetsAt: nil))
                }
            }
            if obj["isUnlimited"] as? Bool == true && usage.windows.isEmpty {
                usage.windows.append(UsageWindowInfo(title: "Plan", utilization: 0, resetsAt: cycleEnd))
            }
            if usage.windows.isEmpty {
                return .failure(UsageFetchError(message: "No usage data in response"))
            }
            return .success(usage)
        }
    }

    private static func percent(_ value: Any?) -> Int? {
        if let d = value as? Double { return Int(d.rounded()) }
        if let i = value as? Int { return i }
        return nil
    }

    private static func readState(dbPath: String) -> (token: String?, email: String?) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return (nil, nil)
        }
        defer { sqlite3_close(db) }

        func value(forKey key: String) -> String? {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, key, -1, transient)
            guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
            var result = String(cString: text)
            // Some entries are stored JSON-encoded ("\"value\"").
            if result.hasPrefix("\""), let data = result.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(String.self, from: data) {
                result = decoded
            }
            return result
        }

        return (value(forKey: "cursorAuth/accessToken"), value(forKey: "cursorAuth/cachedEmail"))
    }
}
