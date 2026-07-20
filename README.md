# AI Usage Tracker

A tiny macOS menu bar app that shows usage/quota for AI coding tools — Claude Code,
OpenAI Codex, Cursor, and Gemini CLI — across multiple accounts.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)

The menu bar shows one entry per account, e.g. `W:42% P:7% C:5%` (first letter of the
account label plus the primary usage window). Clicking it opens a panel with progress
bars per usage window, reset times, and plan info. Accounts are managed in a settings
window ("Accounts…") — add, remove, rename, or point them at custom config paths.

On first launch the app auto-detects which tools are installed and adds an account
for each (including one per `~/.claude-*` config dir for multi-account Claude setups).

## Supported providers

| Provider | Credentials read from | Usage source |
|---|---|---|
| **Claude Code** | macOS keychain (`Claude Code-credentials[-<sha256(configDir) prefix>]`) | `api.anthropic.com/api/oauth/usage` — 5h and 7d windows |
| **Codex** | `~/.codex/auth.json` (`CODEX_HOME`) | `chatgpt.com/backend-api/wham/usage` — same data as the CLI's `/status` |
| **Cursor** | `state.vscdb` in Cursor's globalStorage (key `cursorAuth/accessToken`) | `cursor.com/api/usage-summary` — plan total and API usage per billing cycle |
| **Gemini CLI** | `~/.gemini/oauth_creds.json` | `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` — per-model quota buckets |

Credentials never leave your machine except to each tool's own usage API. Nothing is
stored by this app, and no credentials live in this repo.

Notes:
- Each tool must be signed in already; this app never performs a login itself.
- Gemini access tokens expire hourly. The app can refresh them only if you export
  `GEMINI_OAUTH_CLIENT_ID` / `GEMINI_OAUTH_CLIENT_SECRET` (the Gemini CLI's public
  installed-app OAuth client, found in its source); otherwise just run `gemini`
  occasionally to keep the token fresh.
- On first refresh, macOS may ask to allow keychain access for the Claude Code items.

## Install

### Homebrew

```sh
brew tap mgaesslein/claude-usage-tracker https://github.com/mgaesslein/claude-usage-tracker
brew install claude-usage-tracker
open /Applications/ClaudeUsage.app
```

The formula builds the app and installs it straight into `/Applications`.

Use `brew install --HEAD claude-usage-tracker` to track `main` instead of the pinned
release commit.

### From source

```sh
./build_app.sh
open ClaudeUsage.app
```

Requires Xcode command line tools (Swift 5.9+).

## Adding a provider

Providers live in `Sources/ClaudeUsage/*Provider.swift`. Each one is an enum with a
single entry point:

```swift
static func fetch(path: String) async -> Result<FetchedUsage, UsageFetchError>
```

Add a case to `Provider` in `Models.swift` (display name, default path, path hint),
wire it up in `fetchUsage(for:)` in `ProviderCommon.swift`, and return whatever
usage windows make sense for that tool.

## License

[MIT](LICENSE)
