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

const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const DATETIME_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;

const server = new McpServer({
	name: "ical",
	version: "1.0.0",
});

server.tool(
	"ical__list_calendars",
	"List all Apple Calendar calendars",
	{},
	async () => ({ content: [{ type: "text", text: run("list-calendars") }] }),
);

server.tool(
	"ical__list_events",
	"List calendar events within a date range",
	{
		start_date: z
			.string()
			.max(30)
			.regex(DATE_REGEX)
			.describe("Start date (YYYY-MM-DD)"),
		end_date: z
			.string()
			.max(30)
			.regex(DATE_REGEX)
			.optional()
			.describe("End date (YYYY-MM-DD, defaults to start_date)"),
		calendar: z
			.string()
			.max(200)
			.optional()
			.describe("Calendar name to filter (default: all calendars)"),
		include_notes: z
			.boolean()
			.optional()
			.default(false)
			.describe(
				"Include event notes in output (default: false, to avoid exposing meeting PINs)",
			),
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

server.tool(
	"ical__search_events",
	"Search calendar events by keyword",
	{
		query: z.string().max(500).describe("Search keyword"),
		days_ahead: z
			.number()
			.int()
			.min(1)
			.max(365)
			.optional()
			.describe("Number of days ahead to search (default 30, max 365)"),
		calendar: z
			.string()
			.max(200)
			.optional()
			.describe("Calendar name to filter (default: all calendars)"),
		include_notes: z
			.boolean()
			.optional()
			.default(false)
			.describe(
				"Include event notes in output (default: false, to avoid exposing meeting PINs)",
			),
	},
	async ({ query, days_ahead, calendar, include_notes }) => ({
		content: [
			{
				type: "text",
				text: run(
					"search",
					query,
					String(days_ahead ?? 30),
					calendar ?? "",
					include_notes ? "true" : "",
				),
			},
		],
	}),
);

server.tool(
	"ical__create_event",
	"Create a new calendar event. Requires ICAL_ALLOW_WRITE=true environment variable.",
	{
		title: z.string().max(500).describe("Event title"),
		start: z
			.string()
			.max(30)
			.regex(DATETIME_REGEX)
			.describe("Start datetime (ISO 8601, e.g. 2026-05-01T10:00:00Z)"),
		end: z
			.string()
			.max(30)
			.regex(DATETIME_REGEX)
			.describe("End datetime (ISO 8601)"),
		calendar: z
			.string()
			.max(200)
			.optional()
			.describe("Calendar name (default: default calendar)"),
		location: z.string().max(500).optional().describe("Event location"),
		notes: z.string().max(5000).optional().describe("Event notes"),
		all_day: z.boolean().optional().describe("All-day event"),
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

server.tool(
	"ical__update_event",
	"Update an existing calendar event. Requires ICAL_ALLOW_WRITE=true environment variable.",
	{
		event_id: z.string().max(200).describe("Event UID"),
		title: z.string().max(500).optional().describe("New title"),
		start: z
			.string()
			.max(30)
			.regex(DATETIME_REGEX)
			.optional()
			.describe("New start datetime (ISO 8601)"),
		end: z
			.string()
			.max(30)
			.regex(DATETIME_REGEX)
			.optional()
			.describe("New end datetime (ISO 8601)"),
		location: z.string().max(500).optional().describe("New location"),
		notes: z.string().max(5000).optional().describe("New notes"),
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

server.tool(
	"ical__get_event",
	"Get full details of a calendar event by UID",
	{
		event_id: z.string().max(200).describe("Event UID"),
		include_notes: z
			.boolean()
			.optional()
			.default(false)
			.describe(
				"Include event notes in output (default: false, to avoid exposing meeting PINs)",
			),
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

server.tool(
	"ical__delete_event",
	"Delete a calendar event. Requires ICAL_ALLOW_WRITE=true environment variable.",
	{
		event_id: z.string().max(200).describe("Event UID"),
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
