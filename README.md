# mcp-ical-swift

[![Sealjay/mcp-ical-swift MCP server](https://glama.ai/mcp/servers/Sealjay/mcp-ical-swift/badges/score.svg)](https://glama.ai/mcp/servers/Sealjay/mcp-ical-swift)
[![Bun](https://img.shields.io/badge/Bun-1.1+-000000?logo=bun&logoColor=ffffff)](https://bun.sh)
[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?logo=swift&logoColor=ffffff)](https://swift.org)
[![MCP](https://img.shields.io/badge/MCP-Model_Context_Protocol-6E44FF)](https://modelcontextprotocol.io/)
[![License: MIT](https://img.shields.io/github/license/Sealjay/mcp-ical-swift)](LICENCE)
[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=ffffff)](https://www.apple.com/macos/)
[![GitHub issues](https://img.shields.io/github/issues/Sealjay/mcp-ical-swift)](https://github.com/Sealjay/mcp-ical-swift/issues)
[![GitHub stars](https://img.shields.io/github/stars/Sealjay/mcp-ical-swift?style=social)](https://github.com/Sealjay/mcp-ical-swift)

A local MCP server for Apple Calendar. A Bun/TypeScript server exposes calendar tools over stdio and calls a compiled Swift binary that reads EventKit directly, which gets past the macOS TCC rules that block Node, Bun, Python and AppleScript from calendars in headless contexts. No network, no API keys.

## Setup

**Prerequisites:** macOS with Xcode Command Line Tools (`xcode-select --install`) and [Bun](https://bun.sh) 1.1+.

```bash
git clone https://github.com/Sealjay/mcp-ical-swift.git
cd mcp-ical-swift
bun install
bun run build   # compiles bin/calendar-reader, then asks once for Calendar access
```

## MCP client configuration

```json
{
  "mcpServers": {
    "ical": {
      "command": "bun",
      "args": ["run", "/absolute/path/to/mcp-ical-swift/src/index.ts"],
      "env": { "ICAL_ALLOW_WRITE": "true" }
    }
  }
}
```

Drop the `env` block for read-only access. Write tools are off unless `ICAL_ALLOW_WRITE=true`.

| Client | Where |
|--------|-------|
| Claude Code | `claude mcp add --transport stdio ical --scope user [-e ICAL_ALLOW_WRITE=true] -- bun run /absolute/path/to/mcp-ical-swift/src/index.ts`, or the block above in `.mcp.json` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Cursor | `~/.cursor/mcp.json` |

Use absolute paths. If a GUI app reports `spawn bun ENOENT`, set `command` to the output of `which bun` (Homebrew: `/opt/homebrew/bin/bun`).

## Tools

| Tool | Purpose |
|---|---|
| `ical__list_calendars` | List all calendars |
| `ical__list_events` | List events in a date range (YYYY-MM-DD, max 90 days); optional `calendar`, `include_notes` |
| `ical__search_events` | Keyword search over upcoming events (default 30 days); optional `calendar`, `include_notes` |
| `ical__get_event` | Full details of one event by UID |
| `ical__create_event` | Create an event (write) |
| `ical__update_event` | Update an event by UID (write) |
| `ical__delete_event` | Delete an event by UID (write) |

## Architecture

| Component | Description |
|-----------|-------------|
| MCP server | Bun/TypeScript on MCP TypeScript SDK v2 (`@modelcontextprotocol/server`), Zod 4 validation. stdio serves MCP 2026-07-28 and older revisions |
| Swift binary | `swiftc`-compiled, reads and writes EventKit, prints JSON via `JSONSerialization` |
| Bridge | `execFileSync` with array args, so no shell interpolation |

### Why a compiled Swift binary?

On macOS Sequoia and later, headless processes cannot get Calendar access: PyObjC needs a TCC dialog they cannot raise, `osascript` is attributed to `node`/`bun`, and icalBuddy hits the same wall. A `swiftc`-compiled binary spawned via `execFileSync` gets `authorizationStatus = .fullAccess`.

Under Claude Cowork, macOS attributes the prompt to Claude.app, which has no calendar usage string, so access is silently denied and cannot be granted by hand. The binary therefore re-spawns itself with the private `responsibility_spawnattrs_setdisclaim` attribute (as LLDB and Qt Creator do), becoming its own responsible process so macOS reads the binary's embedded `src/Info.plist`. The attribute must be passed as `&attr`: by value it returns `EINVAL` and silently falls back to the old behaviour. If the symbol is missing, it falls back the same way.

The ad-hoc-signed binary's grant survives rebuilds (TCC re-pins it to the new cdhash), but the first grant must come from a terminal: `bun run grant`.

## Privacy and limitations

- Reads **all calendars** by default; filter per request with `calendar`.
- Event notes are excluded unless `include_notes: true`, since they often hold meeting PINs.
- Writes have no per-operation confirmation once enabled, so a prompt injection could change your calendar. Event text from shared or subscribed calendars is untrusted ([the lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)).
- Recurring-event edits apply to the single occurrence (`.thisEvent`), not the series.
- macOS only; one synchronous binary call per tool invocation.

Report vulnerabilities via [`SECURITY.md`](SECURITY.md).

## Troubleshooting

- **"Calendar access is not granted":** run `bun run grant` in a terminal and approve **calendar-reader**. It cannot be approved from inside an MCP client. Verify with `bin/calendar-reader list-events $(date +%Y-%m-%d)`.
- **No prompt ever appears:** clear a stale entry with `tccutil reset Calendar com.sealjay.mcp-ical-swift.calendar-reader`, then `bun run grant`. Builds from before the disclaim fix need a rebuild.
- **Events are empty:** check `bin/calendar-reader list-calendars`.
- **Compilation fails:** `xcode-select --install`.

## Contributing

Conventional commits; `bun test` must pass. See [`CLAUDE.md`](CLAUDE.md).

## Licence

[MIT](LICENCE)
