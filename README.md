# mcp-ical-swift

[![Bun](https://img.shields.io/badge/Bun-1.1+-000000?logo=bun&logoColor=ffffff)](https://bun.sh)
[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?logo=swift&logoColor=ffffff)](https://swift.org)
[![MCP](https://img.shields.io/badge/MCP-Model_Context_Protocol-6E44FF)](https://modelcontextprotocol.io/)
[![License: MIT](https://img.shields.io/github/license/Sealjay/mcp-ical-swift)](LICENCE)
[![macOS](https://img.shields.io/badge/macOS-Sequoia_26+-000000?logo=apple&logoColor=ffffff)](https://www.apple.com/macos/)

> A local MCP server for Apple Calendar that uses a compiled Swift binary to bypass macOS Sequoia's TCC restrictions.

## Why this exists

On macOS Sequoia (26.x), headless processes cannot obtain Calendar access through the standard TCC (Transparency, Consent, and Control) mechanism:

- **EventKit from Python** (e.g. PyObjC) requires `kTCCServiceCalendar`, which can only be granted through a system dialog that headless processes cannot trigger. There is no `+` button in System Settings > Privacy & Security > Calendars on Sequoia.
- **AppleScript via `osascript`** requires `kTCCServiceAppleEvents` (Automation permission), which is attributed to the calling binary (typically `node` or `bun`). Direct TCC database edits are silently ignored by the TCC daemon's integrity checks.
- **icalBuddy** and other Homebrew tools use EventKit internally and hit the same wall.

The compiled Swift binary (`swiftc`) works because it produces an Apple-signed Mach-O executable that inherits Calendar TCC from the system Swift toolchain. When Node/Bun spawns this binary via `execFileSync`, EventKit reports `authorizationStatus = .fullAccess` and returns calendar data.

## Features

- List all calendars
- List events within a date range
- Search events by keyword
- Create new events (with calendar, location, notes, all-day support)
- Update existing events
- Get full event details by UID
- Delete events
- Runs entirely locally over stdio -- no network, no API keys, no cloud

## Prerequisites

- macOS Sequoia (26.x) or later
- [Bun](https://bun.sh) 1.1+
- Xcode Command Line Tools (`xcode-select --install`) for `swiftc`
- Calendar data in Apple Calendar (iCloud, Exchange, or local calendars)

## Installation

```bash
git clone https://github.com/Sealjay/mcp-ical-swift.git
cd mcp-ical-swift
bun install
bun run build
```

The `build` script compiles `src/calendar-reader.swift` into `bin/calendar-reader`.

## MCP client configuration

### Claude Code

```bash
claude mcp add --transport stdio ical --scope user -- bun run /absolute/path/to/mcp-ical-swift/src/index.ts
```

### OpenClaw

```json
{
  "mcp": {
    "servers": {
      "ical": {
        "command": "bun",
        "args": ["run", "/absolute/path/to/mcp-ical-swift/src/index.ts"]
      }
    }
  }
}
```

### Claude Desktop

Add to `claude_desktop_config.json`:

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

## Tools

| Tool | Description |
|---|---|
| `ical__list_calendars` | List all Apple Calendar calendars |
| `ical__list_events` | List events within a date range (YYYY-MM-DD) |
| `ical__search_events` | Search events by keyword (default: 30 days ahead) |
| `ical__create_event` | Create a new event (title, start, end, calendar, location, notes, all-day) |
| `ical__update_event` | Update an existing event by UID |
| `ical__get_event` | Get full details of an event by UID |
| `ical__delete_event` | Delete an event by UID |

## How it works

```
MCP Client (Claude, OpenClaw, etc.)
  --> stdio --> Bun MCP server (src/index.ts)
    --> execFileSync --> compiled Swift binary (bin/calendar-reader)
      --> EventKit framework --> Apple Calendar data
```

The Swift binary is compiled once (`bun run build`) and called synchronously for each tool invocation. It outputs JSON to stdout, which the Bun MCP server wraps in MCP tool results. The server uses `execFileSync` (not shell execution) to avoid injection risks.

The key insight: `swiftc`-compiled binaries are Apple-signed and inherit Calendar TCC from the system toolchain. This bypasses the TCC restrictions that block Node, Bun, Python, and AppleScript from accessing calendars in headless contexts.

## Troubleshooting

### "Calendar access is not granted"

The compiled binary needs to be run at least once from a context that has Calendar TCC. Run the build and test:

```bash
bun run build
bin/calendar-reader list-events $(date +%Y-%m-%d)
```

If this returns events, the binary has Calendar access. If not, try running from Terminal.app (which typically has Calendar TCC granted).

### Events are empty

Check that you have calendars configured in Apple Calendar. Run:

```bash
bin/calendar-reader list-calendars
```

### Compilation fails

Ensure Xcode Command Line Tools are installed:

```bash
xcode-select --install
```

## Licence

[MIT](LICENCE)
