import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Text(store.usages.map { usage in
            let initial = String(usage.label.prefix(1))
            if let pct = usage.fiveHour.utilization {
                return "\(initial):\(pct)%"
            } else {
                return "\(initial):–"
            }
        }.joined(separator: " "))
    }
}

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            ForEach(Array(store.usages.enumerated()), id: \.element.id) { index, usage in
                AccountRow(usage: usage)
                if index < store.usages.count - 1 {
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
    let usage: AccountUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.label).bold()
                Spacer()
                if !usage.subscriptionType.isEmpty {
                    Text(usage.subscriptionType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !usage.email.isEmpty {
                Text(usage.email)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = usage.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                UsageBar(title: "5h", window: usage.fiveHour)
                UsageBar(title: "7d", window: usage.sevenDay)
            }
        }
    }
}

struct UsageBar: View {
    let title: String
    let window: UsageWindow

    private var color: Color {
        guard let pct = window.utilization else { return .gray }
        if pct >= 80 { return .red }
        if pct >= 50 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .frame(width: 22, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(window.utilization ?? 0) / 100)
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
                    .padding(.leading, 28)
            }
        }
    }
}

private func relativeString(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
