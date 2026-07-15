import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published var usages: [AccountUsage]
    @Published var isRefreshing = false
    private var timer: Timer?

    init() {
        usages = accounts.map { AccountUsage(id: $0.label, label: $0.label) }
        Task { await refreshAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    func refreshAll() async {
        isRefreshing = true
        for (index, config) in accounts.enumerated() {
            await refresh(index: index, config: config)
        }
        isRefreshing = false
    }

    private func refresh(index: Int, config: AccountConfig) async {
        let configDir = config.configDir
        let service = keychainServiceName(for: configDir)

        let (token, subscriptionType, email) = await Task.detached {
            (
                readAccessToken(service: service),
                readSubscriptionType(service: service),
                readEmail(configDir: configDir)
            )
        }.value

        usages[index].email = email ?? ""
        usages[index].subscriptionType = subscriptionType ?? ""

        guard let token else {
            usages[index].error = "No credentials found for \(config.label)"
            return
        }

        switch await fetchUsage(token: token) {
        case .success(let result):
            usages[index].fiveHour = result.five
            usages[index].sevenDay = result.seven
            usages[index].error = nil
            usages[index].lastUpdated = Date()
        case .failure(let error):
            usages[index].error = error.message
        }
    }
}
