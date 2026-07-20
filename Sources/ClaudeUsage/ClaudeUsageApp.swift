import SwiftUI
import AppKit
import Combine

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No real scenes: the status item and its popover/windows are all
        // managed by AppDelegate via plain AppKit, so MenuBarExtra's
        // (buggy) auto-positioning is never involved.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var accountsWindowController: NSWindowController?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = titleText()
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: UsageMenuView(store: store, openAccounts: { [weak self] in self?.showAccountsWindow() })
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover

        // Keep the status bar text (e.g. "P:4% W:0%") in sync as usage refreshes.
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.statusItem.button?.title = self?.titleText() ?? ""
            }
        }
    }

    private func titleText() -> String {
        store.accounts.map { account in
            let initial = String(account.label.prefix(1))
            if let pct = store.statuses[account.id]?.windows.first?.utilization {
                return "\(initial):\(pct)%"
            } else {
                return "\(initial):–"
            }
        }.joined(separator: " ")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Anchored explicitly to the status item's button, so it always
            // appears right below it — unlike MenuBarExtra's .window style,
            // which can drift to the center of the screen.
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showAccountsWindow() {
        popover.performClose(nil)
        if accountsWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "Accounts"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            accountsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        accountsWindowController?.showWindow(nil)
        accountsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
