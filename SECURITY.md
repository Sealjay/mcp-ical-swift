# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in this project, please report it privately via
[GitHub Security Advisories](https://github.com/Sealjay/mcp-ical-swift/security/advisories/new).

Do not open a public issue for security reports. We aim to acknowledge reports within 48 hours
and will work with you on a fix before any public disclosure.

## Scope

The following areas are in scope for security reports against this project:

- Tool input validation (date strings, event IDs, calendar names passed to the Swift binary)
- JSON output construction in the Swift binary
- EventKit data access and exposure (calendar data, event notes)
- MCP transport security (stdio)

## Out of Scope / Upstream

The following should be reported to their respective maintainers:

- **EventKit or Apple Calendar vulnerabilities** — report to Apple
- **macOS TCC (Transparency, Consent, and Control) issues** — report to Apple
- **MCP SDK vulnerabilities** — report to [modelcontextprotocol/typescript-sdk](https://github.com/modelcontextprotocol/typescript-sdk)
- **Bun runtime issues** — report to [oven-sh/bun](https://github.com/oven-sh/bun)

## Data Handling

This server accesses **all calendars** on the host system by default. Event notes are included
in responses and may contain sensitive information. Write operations (create, update, delete)
are available through the MCP tools.

Users should be mindful of this when granting calendar access and when connecting the server
to an MCP client.
