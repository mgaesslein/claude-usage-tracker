import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts")
                .font(.headline)

            if store.accounts.isEmpty {
                Text("No accounts yet — add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($store.accounts) { $account in
                AccountEditor(account: $account) {
                    store.removeAccount(account.id)
                }
            }

            HStack {
                Button("Add Account") {
                    store.addAccount()
                }
                Spacer()
                Button("Refresh Now") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isRefreshing)
            }

            Text("Credentials are read locally from each tool's own login (keychain or config dir) and sent only to that tool's usage API. Nothing is stored by this app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 560)
    }
}

private struct AccountEditor: View {
    @Binding var account: AccountConfig
    var onDelete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Label", text: $account.label)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    Picker("", selection: $account.provider) {
                        ForEach(Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .onChange(of: account.provider) { newProvider in
                        // Swap in the new provider's default path unless the
                        // user customized it.
                        if account.path.isEmpty || Provider.allCases.map(\.defaultPath).contains(account.path) {
                            account.path = newProvider.defaultPath
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                TextField(account.provider.pathHint, text: $account.path)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding(4)
        }
    }
}
