import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const BINARY = resolve(import.meta.dir, "../bin/calendar-reader");

function run(command: string, ...args: string[]): string {
  try {
    return execFileSync(BINARY, [command, ...args], {
      encoding: "utf8",
      timeout: 15000,
    }).trim();
  } catch (e: any) {
    throw new Error(e.stderr || e.message);
  }
}

const server = new McpServer({
  name: "ical",
  version: "1.0.0",
});

server.tool(
  "ical__list_calendars",
  "List all Apple Calendar calendars",
  {},
  async () => ({ content: [{ type: "text", text: run("list-calendars") }] })
);

server.tool(
  "ical__list_events",
  "List calendar events within a date range",
  {
    start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe("Start date (YYYY-MM-DD)"),
    end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional().describe("End date (YYYY-MM-DD, defaults to start_date)"),
    calendar: z.string().optional().describe("Calendar name to filter (default: all calendars)"),
  },
  async ({ start_date, end_date, calendar }) => ({
    content: [{ type: "text", text: run("list-events", start_date, end_date ?? "", calendar ?? "") }],
  })
);

server.tool(
  "ical__search_events",
  "Search calendar events by keyword",
  {
    query: z.string().describe("Search keyword"),
    days_ahead: z.number().int().min(1).max(365).optional().describe("Number of days ahead to search (default 30, max 365)"),
    calendar: z.string().optional().describe("Calendar name to filter (default: all calendars)"),
  },
  async ({ query, days_ahead, calendar }) => ({
    content: [{ type: "text", text: run("search", query, String(days_ahead ?? 30), calendar ?? "") }],
  })
);

server.tool(
  "ical__create_event",
  "Create a new calendar event",
  {
    title: z.string().describe("Event title"),
    start: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/).describe("Start datetime (ISO 8601, e.g. 2026-05-01T10:00:00Z)"),
    end: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/).describe("End datetime (ISO 8601)"),
    calendar: z.string().optional().describe("Calendar name (default: default calendar)"),
    location: z.string().optional().describe("Event location"),
    notes: z.string().optional().describe("Event notes"),
    all_day: z.boolean().optional().describe("All-day event"),
  },
  async ({ title, start, end, calendar, location, notes, all_day }) => ({
    content: [{
      type: "text",
      text: run("create-event", title, start, end, calendar ?? "", location ?? "", notes ?? "", all_day ? "true" : ""),
    }],
  })
);

server.tool(
  "ical__update_event",
  "Update an existing calendar event",
  {
    event_id: z.string().describe("Event UID"),
    title: z.string().optional().describe("New title"),
    start: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/).optional().describe("New start datetime (ISO 8601)"),
    end: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/).optional().describe("New end datetime (ISO 8601)"),
    location: z.string().optional().describe("New location"),
    notes: z.string().optional().describe("New notes"),
  },
  async ({ event_id, title, start, end, location, notes }) => ({
    content: [{
      type: "text",
      text: run("update-event", event_id, title ?? "", start ?? "", end ?? "", location ?? "", notes ?? ""),
    }],
  })
);

server.tool(
  "ical__get_event",
  "Get full details of a calendar event by UID",
  {
    event_id: z.string().describe("Event UID"),
  },
  async ({ event_id }) => ({
    content: [{ type: "text", text: run("get-event", event_id) }],
  })
);

server.tool(
  "ical__delete_event",
  "Delete a calendar event",
  {
    event_id: z.string().describe("Event UID"),
  },
  async ({ event_id }) => ({
    content: [{ type: "text", text: run("delete-event", event_id) }],
  })
);

const transport = new StdioServerTransport();
await server.connect(transport);
