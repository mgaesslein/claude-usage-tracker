import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var accounts: [AccountConfig] {
        didSet {
            guard accounts != oldValue else { return }
            AccountStorage.save(accounts)
            statuses = statuses.filter { id, _ in accounts.contains { $0.id == id } }
            if accounts.count != oldValue.count {
                Task { await refreshAll() }
            }
        }
    }
    @Published var statuses: [UUID: AccountStatus] = [:]
    @Published var isRefreshing = false
    private var timer: Timer?

    init() {
        let accounts = AccountStorage.load() ?? AccountStorage.detectDefaults()
        self.accounts = accounts
        AccountStorage.save(accounts)
        Task { await refreshAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await withTaskGroup(of: (UUID, AccountStatus).self) { group in
            for account in accounts {
                let previous = statuses[account.id] ?? AccountStatus()
                group.addTask {
                    var status = previous
                    switch await fetchUsage(for: account) {
                    case .success(let usage):
                        status.email = usage.email ?? ""
                        status.plan = usage.plan ?? ""
                        status.windows = usage.windows
                        status.error = nil
                        status.lastUpdated = Date()
                    case .failure(let error):
                        status.error = error.message
                    }
                    return (account.id, status)
                }
            }
            for await (id, status) in group {
                if accounts.contains(where: { $0.id == id }) {
                    statuses[id] = status
                }
            }
        }
        isRefreshing = false
    }

    func addAccount() {
        let provider = Provider.claude
        accounts.append(AccountConfig(label: "New account", provider: provider, path: provider.defaultPath))
    }

    func removeAccount(_ id: UUID) {
        accounts.removeAll { $0.id == id }
    }
}
