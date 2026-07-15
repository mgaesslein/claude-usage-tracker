# Claude Usage Tracker

A tiny macOS menu bar app that shows Claude Code usage (5-hour and 7-day windows) for multiple accounts.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)

## How it works

Claude Code stores each login's OAuth token in the macOS keychain under
`Claude Code-credentials-<sha256(CLAUDE_CONFIG_DIR) prefix>`. The app reads those
tokens (no credentials are stored in this repo or in the app) and queries the
`https://api.anthropic.com/api/oauth/usage` endpoint every 5 minutes.

The menu bar shows one entry per account, e.g. `W:42% P:7%` (first letter of the
account label plus the 5-hour utilization). Clicking it opens a panel with
progress bars for both the 5-hour and 7-day windows, reset times, and the
subscription type per account.

## Setup

Edit the account list in `Sources/ClaudeUsage/UsageData.swift` to match your
`CLAUDE_CONFIG_DIR` setup:

```swift
let accounts: [AccountConfig] = [
    AccountConfig(label: "Work", configDir: NSHomeDirectory() + "/.claude-work"),
    AccountConfig(label: "Personal", configDir: NSHomeDirectory() + "/.claude-personal"),
]
```

## Build

```sh
./build_app.sh
open ClaudeUsage.app
```

Requires Xcode command line tools (Swift 5.9+).

## License

[MIT](LICENSE)
