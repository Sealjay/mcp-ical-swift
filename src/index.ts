import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const BINARY = resolve(import.meta.dir, "../bin/calendar-reader");

if (!existsSync(BINARY)) {
	throw new Error(
		`Calendar binary not found at ${BINARY}. Run 'bun run build' first.`,
	);
}

export const WRITE_ENABLED = process.env.ICAL_ALLOW_WRITE === "true";

export function assertWriteEnabled(): void {
	if (!WRITE_ENABLED) {
		throw new Error(
			"Write operations are disabled. Set the ICAL_ALLOW_WRITE=true environment variable to enable create, update, and delete.",
		);
	}
}

function run(command: string, ...args: string[]): string {
	try {
		return execFileSync(BINARY, [command, ...args], {
			encoding: "utf8",
			timeout: 15000,
		}).trim();
	} catch (e: unknown) {
		const err = e as { stderr?: string; message?: string };
		const msg = (
			err.stderr ||
			err.message ||
			"calendar operation failed"
		).replace(/\/[\w/.-]+/g, "[path]");
		throw new Error(msg);
	}
}

const server = new McpServer({
	name: "ical",
	version: "1.1.0",
});

server.registerTool(
	"ical__list_calendars",
	{
		title: "List Calendars",
		description:
			"List all Apple Calendar calendars accessible to the host process. Returns a JSON array of `{name, uid, type}` objects; `name` is the human-readable label other tools accept as their `calendar` parameter (collisions across accounts are possible — first match wins). Read-only; requires macOS Calendar access for the parent process.",
		annotations: { readOnlyHint: true, openWorldHint: false },
	},
	async () => ({ content: [{ type: "text", text: run("list-calendars") }] }),
);

server.registerTool(
	"ical__list_events",
	{
		title: "List Calendar Events",
		description:
			"List calendar events within an inclusive date range (capped at 90 days). Returns a JSON array of `{title, start, end, allDay, calendar, uid, location?, notes?}`; use `ical__search_events` for keyword queries and `ical__get_event` for full details on one event. Read-only; requires macOS Calendar access.",
		inputSchema: {
			start_date: z
				.string()
				.max(30)
				.date()
				.describe(
					"Inclusive start date in YYYY-MM-DD; interpreted in the system's local timezone.",
				),
			end_date: z
				.string()
				.max(30)
				.date()
				.optional()
				.describe(
					"Inclusive end date in YYYY-MM-DD; defaults to start_date. The full range is capped at 90 days.",
				),
			calendar: z
				.string()
				.max(200)
				.optional()
				.describe(
					"Calendar name from `ical__list_calendars` (human-readable label, not the UID; first match wins on collisions). Default: search all calendars.",
				),
			include_notes: z
				.boolean()
				.optional()
				.default(false)
				.describe(
					"Include event notes in output (default: false, to avoid exposing meeting PINs)",
				),
		},
		annotations: { readOnlyHint: true, openWorldHint: false },
	},
	async ({ start_date, end_date, calendar, include_notes }) => ({
		content: [
			{
				type: "text",
				text: run(
					"list-events",
					start_date,
					end_date ?? "",
					calendar ?? "",
					include_notes ? "true" : "",
				),
			},
		],
	}),
);

server.registerTool(
	"ical__search_events",
	{
		title: "Search Calendar Events",
		description:
			"Find upcoming calendar events whose title, location, or notes contain a case-insensitive substring. Returns a JSON array of `{title, start, end, calendar, uid, location?, notes?}`; use `ical__list_events` when you have a specific date range. Read-only; requires macOS Calendar access.",
		inputSchema: {
			query: z
				.string()
				.max(500)
				.describe(
					"Case-insensitive substring matched against event title, location, and notes.",
				),
			days_ahead: z
				.number()
				.int()
				.min(1)
				.max(365)
				.optional()
				.default(30)
				.describe("Number of days from today to search (1–365, default 30)."),
			calendar: z
				.string()
				.max(200)
				.optional()
				.describe(
					"Calendar name from `ical__list_calendars` (human-readable label, not the UID; first match wins on collisions). Default: search all calendars.",
				),
			include_notes: z
				.boolean()
				.optional()
				.default(false)
				.describe(
					"Include event notes in output (default: false, to avoid exposing meeting PINs)",
				),
		},
		annotations: { readOnlyHint: true, openWorldHint: false },
	},
	async ({ query, days_ahead, calendar, include_notes }) => ({
		content: [
			{
				type: "text",
				text: run(
					"search",
					query,
					String(days_ahead),
					calendar ?? "",
					include_notes ? "true" : "",
				),
			},
		],
	}),
);

server.registerTool(
	"ical__create_event",
	{
		title: "Create Calendar Event",
		description:
			"Create a new calendar event in EventKit; visible in Apple Calendar.app and synced via iCloud if the chosen calendar is iCloud-backed. Returns `{uid, title, status: 'created'}`; reversible via `ical__delete_event` using the returned UID. Requires `ICAL_ALLOW_WRITE=true` and macOS Calendar access for the parent process.",
		inputSchema: {
			title: z.string().max(500).describe("Event title."),
			start: z
				.string()
				.max(30)
				.datetime({ offset: true, local: true })
				.describe(
					"Start datetime in ISO 8601 (e.g. `2026-05-01T10:00:00Z`); naive datetimes without an offset are interpreted in the system's local timezone.",
				),
			end: z
				.string()
				.max(30)
				.datetime({ offset: true, local: true })
				.describe(
					"End datetime in ISO 8601; same timezone semantics as `start`.",
				),
			calendar: z
				.string()
				.max(200)
				.optional()
				.describe(
					"Calendar name from `ical__list_calendars` (first match wins on collisions). Default: the system's default calendar for new events.",
				),
			location: z.string().max(500).optional().describe("Event location."),
			notes: z
				.string()
				.max(5000)
				.optional()
				.describe(
					"Event notes; stored in plaintext and visible to anyone with read access to this calendar.",
				),
			all_day: z
				.boolean()
				.optional()
				.default(false)
				.describe(
					"If true, the time component of `start`/`end` is ignored and the event spans whole days in the calendar's local timezone. Default: false.",
				),
		},
		annotations: {
			readOnlyHint: false,
			destructiveHint: false,
			idempotentHint: false,
			openWorldHint: false,
		},
	},
	async ({ title, start, end, calendar, location, notes, all_day }) => {
		assertWriteEnabled();
		return {
			content: [
				{
					type: "text",
					text: run(
						"create-event",
						title,
						start,
						end,
						calendar ?? "",
						location ?? "",
						notes ?? "",
						all_day ? "true" : "",
					),
				},
			],
		};
	},
);

server.registerTool(
	"ical__update_event",
	{
		title: "Update Calendar Event",
		description:
			"Update fields on a single existing calendar event; only fields you provide are changed. For recurring events this modifies the single occurrence only (EventKit `.thisEvent` span), not the series. Returns `{uid, title, status: 'updated'}`; not automatically reversible — capture prior values via `ical__get_event` first. Requires `ICAL_ALLOW_WRITE=true` and macOS Calendar access. The event's calendar and all-day status cannot be changed by this tool.",
		inputSchema: {
			event_id: z
				.string()
				.max(200)
				.describe(
					"Event UID as returned by `ical__list_events`, `ical__search_events`, or `ical__get_event`.",
				),
			title: z
				.string()
				.max(500)
				.optional()
				.describe("New title; omit to leave unchanged."),
			start: z
				.string()
				.max(30)
				.datetime({ offset: true, local: true })
				.optional()
				.describe(
					"New start datetime in ISO 8601; naive datetimes are interpreted in the system's local timezone. Omit to leave unchanged.",
				),
			end: z
				.string()
				.max(30)
				.datetime({ offset: true, local: true })
				.optional()
				.describe(
					"New end datetime in ISO 8601; same timezone semantics as `start`. Omit to leave unchanged.",
				),
			location: z
				.string()
				.max(500)
				.optional()
				.describe("New location; omit to leave unchanged."),
			notes: z
				.string()
				.max(5000)
				.optional()
				.describe("New notes; omit to leave unchanged."),
		},
		annotations: {
			readOnlyHint: false,
			destructiveHint: true,
			idempotentHint: true,
			openWorldHint: false,
		},
	},
	async ({ event_id, title, start, end, location, notes }) => {
		assertWriteEnabled();
		return {
			content: [
				{
					type: "text",
					text: run(
						"update-event",
						event_id,
						title ?? "",
						start ?? "",
						end ?? "",
						location ?? "",
						notes ?? "",
					),
				},
			],
		};
	},
);

server.registerTool(
	"ical__get_event",
	{
		title: "Get Calendar Event",
		description:
			"Get full details of a single calendar event by UID. Returns `{uid, title, start, end, allDay, calendar, location?, notes?, url?, hasRecurrence?}`; use `ical__list_events` or `ical__search_events` for bulk queries. Read-only; requires macOS Calendar access.",
		inputSchema: {
			event_id: z
				.string()
				.max(200)
				.describe(
					"Event UID as returned by `ical__list_events` or `ical__search_events`.",
				),
			include_notes: z
				.boolean()
				.optional()
				.default(false)
				.describe(
					"Include event notes in output (default: false, to avoid exposing meeting PINs)",
				),
		},
		annotations: { readOnlyHint: true, openWorldHint: false },
	},
	async ({ event_id, include_notes }) => ({
		content: [
			{
				type: "text",
				text: run("get-event", event_id, include_notes ? "true" : ""),
			},
		],
	}),
);

server.registerTool(
	"ical__delete_event",
	{
		title: "Delete Calendar Event",
		description:
			"Delete a single calendar event by UID; for recurring events this removes the single occurrence only (EventKit `.thisEvent` span), not the series. Destructive: removal propagates to iCloud if the calendar is iCloud-backed and is not reversible from this server (capture details with `ical__get_event` first if you may need to restore via `ical__create_event`). Returns `{status: 'deleted', uid}`; requires `ICAL_ALLOW_WRITE=true` and macOS Calendar access.",
		inputSchema: {
			event_id: z
				.string()
				.max(200)
				.describe(
					"Event UID as returned by `ical__list_events`, `ical__search_events`, or `ical__get_event`.",
				),
		},
		annotations: {
			readOnlyHint: false,
			destructiveHint: true,
			idempotentHint: true,
			openWorldHint: false,
		},
	},
	async ({ event_id }) => {
		assertWriteEnabled();
		return {
			content: [{ type: "text", text: run("delete-event", event_id) }],
		};
	},
);

const transport = new StdioServerTransport();
await server.connect(transport);
