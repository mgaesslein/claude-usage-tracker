import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Text(store.accounts.map { account in
            let initial = String(account.label.prefix(1))
            if let pct = store.statuses[account.id]?.windows.first?.utilization {
                return "\(initial):\(pct)%"
            } else {
                return "\(initial):–"
            }
        }.joined(separator: " "))
    }
}

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore
    var openAccounts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Usage")
                .font(.headline)

            if store.accounts.isEmpty {
                Text("No accounts configured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(account: account, status: store.statuses[account.id] ?? AccountStatus())
                if index < store.accounts.count - 1 {
                    Divider()
                }
            }

            Divider()

            HStack {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(store.isRefreshing)

                Button("Accounts…") {
                    openAccounts()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct AccountRow: View {
    let account: AccountConfig
    let status: AccountStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account.label).bold()
                Text(account.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !status.plan.isEmpty {
                    Text(status.plan.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !status.email.isEmpty {
                Text(status.email)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = status.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if status.windows.isEmpty {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.windows) { window in
                    UsageBar(window: window)
                }
            }
        }
    }
}

struct UsageBar: View {
    let window: UsageWindowInfo

    private var color: Color {
        guard let pct = window.utilization else { return .gray }
        if pct >= 80 { return .red }
        if pct >= 50 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(window.title)
                    .font(.caption)
                    .frame(width: 36, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(window.utilization ?? 0, 100)) / 100)
                    }
                }
                .frame(height: 8)

                Text(window.utilization.map { "\($0)%" } ?? "–")
                    .font(.caption)
                    .frame(width: 34, alignment: .trailing)
            }

            if let resetsAt = window.resetsAt {
                Text("resets \(relativeString(resetsAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }
        }
    }
}

private func relativeString(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
