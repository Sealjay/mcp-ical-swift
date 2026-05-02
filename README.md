# mcp-ical-swift

[![Sealjay/mcp-ical-swift MCP server](https://glama.ai/mcp/servers/Sealjay/mcp-ical-swift/badges/score.svg)](https://glama.ai/mcp/servers/Sealjay/mcp-ical-swift)
[![Bun](https://img.shields.io/badge/Bun-1.1+-000000?logo=bun&logoColor=ffffff)](https://bun.sh)
[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?logo=swift&logoColor=ffffff)](https://swift.org)
[![MCP](https://img.shields.io/badge/MCP-Model_Context_Protocol-6E44FF)](https://modelcontextprotocol.io/)
[![License: MIT](https://img.shields.io/github/license/Sealjay/mcp-ical-swift)](LICENCE)
[![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=ffffff)](https://www.apple.com/macos/)
[![GitHub issues](https://img.shields.io/github/issues/Sealjay/mcp-ical-swift)](https://github.com/Sealjay/mcp-ical-swift/issues)
[![GitHub stars](https://img.shields.io/github/stars/Sealjay/mcp-ical-swift?style=social)](https://github.com/Sealjay/mcp-ical-swift)

> A local MCP server for Apple Calendar that uses a compiled Swift binary to bypass macOS TCC restrictions blocking headless processes from accessing calendars.

mcp-ical-swift has two parts: a Bun/TypeScript MCP server that exposes calendar tools over stdio, and a compiled Swift binary that accesses EventKit directly. The Swift binary works because `swiftc`-compiled executables are Apple-signed and inherit Calendar TCC from the system toolchain — bypassing the restrictions that block Node, Bun, Python, and AppleScript in headless contexts. Everything runs locally — no network, no API keys, no cloud.

## Features

- List all calendars
- List events within a date range
- Search events by keyword
- Get full event details by UID
- Create, update, and delete events (opt-in via `ICAL_ALLOW_WRITE=true`)
- Runs entirely locally over stdio — no network, no API keys, no cloud

## Setup

### Prerequisites

- macOS with Xcode Command Line Tools (`xcode-select --install`) for `swiftc`
- [Bun](https://bun.sh) 1.1+
- Calendar data in Apple Calendar (iCloud, Exchange, or local calendars)

### Installation

1. **Clone this repository**

   ```bash
   git clone https://github.com/Sealjay/mcp-ical-swift.git
   cd mcp-ical-swift
   ```

2. **Install dependencies and build**

   ```bash
   bun install
   bun run build
   ```

   The build step compiles `src/calendar-reader.swift` into `bin/calendar-reader`.

## MCP client configuration

All clients use the same `command`/`args` shape. On macOS, you may need the absolute path to `bun` — see [macOS: `bun` PATH](#macos-bun-path) below.

### Claude Code

The quickest route is the CLI:

```bash
claude mcp add --transport stdio ical --scope user -- bun run /absolute/path/to/mcp-ical-swift/src/index.ts
```

With write operations enabled:

```bash
claude mcp add --transport stdio ical --scope user -e ICAL_ALLOW_WRITE=true -- bun run /absolute/path/to/mcp-ical-swift/src/index.ts
```

Alternatively, add to `.mcp.json` at your project root (or `~/.claude.json` for user scope):

```json
{
  "mcpServers": {
    "ical": {
      "type": "stdio",
      "command": "bun",
      "args": ["run", "/absolute/path/to/mcp-ical-swift/src/index.ts"]
    }
  }
}
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "ical": {
      "command": "bun",
      "args": ["run", "/absolute/path/to/mcp-ical-swift/src/index.ts"]
    }
  }
}
```

Restart Claude Desktop. You should see `ical` listed as an available integration.

### Cursor

Add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "ical": {
      "command": "bun",
      "args": ["run", "/absolute/path/to/mcp-ical-swift/src/index.ts"]
    }
  }
}
```

Restart Cursor.

### macOS: `bun` PATH

GUI apps (Claude Desktop, Cursor) don't always inherit PATH from your interactive terminal, so `bun` may fail with `spawn bun ENOENT`. Fix by using the absolute path in `command`:

- **Apple Silicon Homebrew** — `/opt/homebrew/bin/bun`
- **Intel Homebrew** — `/usr/local/bin/bun`
- **Manual install** — run `which bun` in your terminal

### Write operations

Write tools (`ical__create_event`, `ical__update_event`, `ical__delete_event`) are disabled by default. Set `ICAL_ALLOW_WRITE=true` to enable them:

```bash
ICAL_ALLOW_WRITE=true bun run start
```

Or in your MCP client config:

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

## Architecture

| Component | Description |
|-----------|-------------|
| MCP server | Bun/TypeScript, stdio transport, Zod input validation |
| Swift binary | Compiled with `swiftc`, accesses EventKit framework |
| Communication | `execFileSync` with array args (no shell interpolation) |
| Output | JSON via `JSONSerialization` (prevents injection from user strings) |

### Data flow

```
MCP Client (Claude, Cursor, etc.)
  → stdio → Bun MCP server (src/index.ts)
    → execFileSync → compiled Swift binary (bin/calendar-reader)
      → EventKit → Apple Calendar
```

The Swift binary is compiled once (`bun run build`) and called synchronously for each tool invocation. It outputs JSON to stdout, which the MCP server wraps in tool results.

### Project structure

```
mcp-ical-swift/
  src/
    index.ts              # MCP server entry point, tool definitions, Zod schemas
    calendar-reader.swift # Swift EventKit binary source
  bin/
    calendar-reader       # Compiled binary (gitignored)
  package.json
```

### Why a compiled Swift binary?

On macOS Sequoia and later, headless processes cannot obtain Calendar access through TCC (Transparency, Consent, and Control):

- **EventKit from Python** (PyObjC) requires `kTCCServiceCalendar`, which needs a system dialog that headless processes cannot trigger.
- **AppleScript via `osascript`** requires `kTCCServiceAppleEvents`, attributed to the calling binary (`node`/`bun`). Direct TCC database edits are silently ignored.
- **icalBuddy** and similar Homebrew tools use EventKit internally and hit the same wall.

A `swiftc`-compiled binary produces an Apple-signed Mach-O executable that inherits Calendar TCC from the system Swift toolchain. When spawned via `execFileSync`, EventKit reports `authorizationStatus = .fullAccess`.

## Tools

7 tools in two groups.

### Read

| Tool | Purpose |
|---|---|
| `ical__list_calendars` | List all Apple Calendar calendars |
| `ical__list_events` | List events within a date range (YYYY-MM-DD); optional `calendar` filter and `include_notes` |
| `ical__search_events` | Search events by keyword (default: 30 days ahead); optional `calendar` filter and `include_notes` |
| `ical__get_event` | Get full details of an event by UID; optional `include_notes` |

### Write (requires `ICAL_ALLOW_WRITE=true`)

| Tool | Purpose |
|---|---|
| `ical__create_event` | Create a new event (title, start, end, calendar, location, notes, all-day) |
| `ical__update_event` | Update an existing event by UID |
| `ical__delete_event` | Delete an event by UID |

## Privacy and security

- This server accesses **all calendars** on the system by default (iCloud, Exchange, local, shared, subscribed). Filter by calendar name per-request using the optional `calendar` parameter on `list_events` and `search_events`.
- Event notes are **not included** by default — set `include_notes: true` per-request to opt in. Notes may contain sensitive data (meeting PINs, passwords, personal details).
- Write operations are gated behind `ICAL_ALLOW_WRITE=true` (off by default). Even when enabled, there is no per-operation confirmation step — an MCP client (or a prompt injection within one) could modify your calendar data.
- All communication is local over stdio — no data leaves your machine.

See [`SECURITY.md`](SECURITY.md) for how to report vulnerabilities.

## Limitations

- **Prompt-injection risk:** as with many MCP servers, this one is subject to [the lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/). Event titles and notes from shared or subscribed calendars could contain adversarial content. Review risky actions before approving them in your MCP client.
- **macOS only** — requires EventKit and the Swift toolchain.
- **Synchronous execution** — the Swift binary is called once per tool invocation, not suited for high-throughput use.
- **Single-instance recurring events** — modifications apply to the individual occurrence only (`.thisEvent` span), not the series.
- **TCC dependency** — Calendar access depends on macOS granting permission to the compiled binary.

## Troubleshooting

### "Calendar access is not granted"

The compiled binary needs to be run at least once from a context that has Calendar TCC. Build and test:

```bash
bun run build
bin/calendar-reader list-events $(date +%Y-%m-%d)
```

If this returns events, the binary has Calendar access. If not, try running from Terminal.app (which typically has Calendar TCC granted).

### Events are empty

Check that you have calendars configured in Apple Calendar:

```bash
bin/calendar-reader list-calendars
```

### Compilation fails

Ensure Xcode Command Line Tools are installed:

```bash
xcode-select --install
```

### MCP client can't launch the server

`args` must use an absolute path, not relative. If `bun` itself fails with `spawn bun ENOENT`, see [macOS: `bun` PATH](#macos-bun-path).

## Contributing

Contributions welcome via pull request. Please:

- Use conventional commits (`feat`, `fix`, `docs`, `refactor`, `test`).
- Ensure `bun test` passes.

## Licence

[MIT](LICENCE)
