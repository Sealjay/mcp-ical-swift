#!/usr/bin/env bash
# Establish the macOS Calendar (TCC) grant for calendar-reader.
#
# The prompt cannot be answered from inside an MCP client: under Cowork the request is
# attributed to Claude.app, which ships no calendar usage-description string, so macOS
# denies it without asking — and the Calendars pane has no "+" button to add it by hand.
# So it gets granted here, from a terminal. One-off: TCC re-pins the ad-hoc binary's
# cdhash across rebuilds by itself.
#
# ponytail: never `tccutil reset` here — it destroys a working grant and forces a reprompt.
# Exit 0 always: a build must not fail because a consent dialog went unanswered.
BINARY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/calendar-reader"

if "$BINARY" list-calendars >/dev/null 2>&1; then
	echo "grant: Calendar access OK." >&2
else
	echo "grant: Calendar access NOT granted. Approve the macOS prompt for 'calendar-reader', then rerun 'bun run grant' (run 'bun run build' first if the binary is missing). If no prompt appears, clear a stale entry with: tccutil reset Calendar com.sealjay.mcp-ical-swift.calendar-reader" >&2
fi
