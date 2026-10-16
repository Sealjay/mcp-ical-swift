# CLAUDE.md

## Architecture

- **MCP server** (`src/index.ts`): Bun, `@modelcontextprotocol/server` v2, Zod 4. `createServer()` registers the tools and `serveStdio(createServer)` picks the protocol era per connection (2026-07-28 or 2025-era `initialize`). Calls the Swift binary via `execFileSync` with array args.
- **Swift binary** (`src/calendar-reader.swift`, built to `bin/calendar-reader`, gitignored): EventKit access, JSON on stdout.

## Commands

| Command | Purpose |
|---|---|
| `bun run build` | Compile the Swift binary, then `scripts/grant.sh` for the one-off Calendar grant |
| `bun run start` / `bun run dev` | Run the server (dev = watch mode) |
| `bun test` | Unit tests: validation, write gate, schema bounds |

Manual check on a Mac: `bin/calendar-reader list-calendars`, `bin/calendar-reader list-events $(date +%Y-%m-%d)`.

## Design decisions

- Writes (`create`/`update`/`delete`) are off unless `ICAL_ALLOW_WRITE=true`.
- `execFileSync` with array args and `JSONSerialization` output: no shell or JSON injection.
- `calendars: nil` queries every calendar unless filtered; documented as a privacy trade-off.
- Recurring edits use `.thisEvent`, never the series.
- stdio only: no HTTP, no network, no API keys.

## Conventions

Bun, conventional commits, British English in prose and American English in code. Tool description rules: `.claude/rules/mcp-tool-descriptions.md`.
