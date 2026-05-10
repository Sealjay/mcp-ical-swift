---
paths:
  - "src/index.ts"
---

# MCP Tool Description Quality (Glama.ai)

When writing or updating MCP tool descriptions in `src/index.ts`, follow these guidelines to score well on Glama.ai's quality dimensions:

## Required in every description

1. **Purpose with specific verb and resource** — "Create a new calendar event in EventKit" not "Make an event"
2. **Side effects** — state what changes: "Writes a new event to the chosen EventKit calendar; visible in Apple Calendar.app and synced via iCloud if the calendar is iCloud-backed"
3. **Reversibility** — how to undo: "Reversible via ical__delete_event using the returned event UID"
4. **Return shape** — "Returns a text block containing the event UID and confirmation, or an error string"
5. **When to use vs alternatives** — "Use ical__list_events for a date range; use ical__search_events when matching by keyword across upcoming events"
6. **Prerequisites** — call out gating env vars or permissions: "Requires ICAL_ALLOW_WRITE=true; the host process must also have macOS Calendar access granted to the parent application"

## Required in parameter descriptions

1. **Which identifier and where it comes from** — for `event_id`, say "Event UID as returned by ical__list_events or ical__search_events" rather than just "Event UID". For `calendar`, clarify it is the human-readable calendar name (as shown by ical__list_calendars), not an EventKit calendar identifier — name collisions across accounts are possible.
2. **Date and time format constraints** — `start_date` / `end_date` are `YYYY-MM-DD` (date-only). `start` / `end` are ISO 8601 datetimes (e.g. `2026-05-01T10:00:00Z`). State the timezone behaviour: naive datetimes are interpreted in the system's local timezone by EventKit; pass an explicit offset or `Z` to be unambiguous.
3. **All-day semantics** — when `all_day` is true, the time component of `start`/`end` is ignored and the event spans whole days in the calendar's local timezone.
4. **Constraints** — mention valid ranges, max lengths, and enum values (e.g. `days_ahead` is 1–365, defaults to 30).
5. **Defaults** — state default values for optional params (e.g. `include_notes` defaults to false to avoid leaking meeting PINs from event notes).

## Style

- Front-load the purpose (first sentence = what it does)
- Keep total description under 3 sentences when possible
- Don't repeat what the Zod schema already says
- Use consistent terminology: "calendar event" not "event" or "appointment" or "meeting"; "calendar name" when referring to the user-facing label

## Avoid

- Descriptions that only restate the function name
- Missing side-effect disclosure (especially for destructive actions like ical__delete_event and mutating ones like ical__update_event)
- Missing identifier guidance (agents need to know that `event_id` is an EventKit UID sourced from a prior list/search call, not a free-form string)
- Missing reversibility info (agents need to know whether an action can be undone, and via which tool)
- Omitting the ICAL_ALLOW_WRITE prerequisite on write tools
