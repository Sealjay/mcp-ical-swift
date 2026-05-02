# CLAUDE.md

## Architecture

Two-component system:
- **TypeScript MCP server** (`src/index.ts`) -- Bun runtime, uses `@modelcontextprotocol/sdk`, communicates over stdio, validates inputs with Zod, calls Swift binary via `execFileSync` with array args (not shell)
- **Swift binary** (`src/calendar-reader.swift`) -- compiled with `swiftc`, accesses Apple Calendar via EventKit framework, outputs JSON to stdout

Data flow: MCP Client -> stdio -> Bun MCP server -> execFileSync -> compiled Swift binary -> EventKit -> Apple Calendar

## Project structure

```
src/index.ts              # MCP server, tool definitions, Zod schemas
src/calendar-reader.swift # Swift EventKit binary source
bin/calendar-reader       # Compiled binary (gitignored, built via `bun run build`)
package.json              # Bun project config
```

## Commands

| Command | Purpose |
|---|---|
| `bun install` | Install dependencies |
| `bun run build` | Compile Swift binary to `bin/calendar-reader` |
| `bun run start` | Start the MCP server |
| `bun run dev` | Start with watch mode |
| `bun test` | Run unit tests |

## Write gate

Write operations (`create-event`, `update-event`, `delete-event`) are **disabled by default**. Set `ICAL_ALLOW_WRITE=true` in the environment to enable them:

```bash
ICAL_ALLOW_WRITE=true bun run start
```

## Design decisions

- **execFileSync with array args** -- prevents command injection (no shell interpolation)
- **JSONSerialization for all JSON output** -- prevents JSON injection from user-controlled strings
- **calendars: nil default** -- queries all calendars unless a filter is specified; this is intentional for broad access but documented as a privacy consideration
- **Single .thisEvent span** -- recurring event modifications apply to the single instance only, not the series
- **No network** -- stdio transport only, no HTTP server, no API keys

## Testing

Unit tests (validation logic, write gate, schema bounds):
```bash
bun test
```

Manual integration testing against local Apple Calendar:
```bash
bun run build
bin/calendar-reader list-calendars
bin/calendar-reader list-events $(date +%Y-%m-%d)
```

## Conventions

- Bun as runtime and package manager
- British English in prose, American English in code
- Conventional commits
