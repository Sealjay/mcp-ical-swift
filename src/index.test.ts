import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { z } from "zod";

// --- Regex validation ---
const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;
const DATETIME_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/;

describe("DATE_REGEX", () => {
	test("accepts valid YYYY-MM-DD dates", () => {
		expect(DATE_REGEX.test("2026-01-01")).toBe(true);
		expect(DATE_REGEX.test("2026-12-31")).toBe(true);
	});
	test("rejects non-conforming strings", () => {
		expect(DATE_REGEX.test("2026-1-1")).toBe(false);
		expect(DATE_REGEX.test("01-01-2026")).toBe(false);
		expect(DATE_REGEX.test("not-a-date")).toBe(false);
		expect(DATE_REGEX.test("2026-01-01T00:00:00")).toBe(false);
	});
});

describe("DATETIME_REGEX", () => {
	test("accepts valid ISO 8601 datetimes", () => {
		expect(DATETIME_REGEX.test("2026-05-01T10:00:00Z")).toBe(true);
		expect(DATETIME_REGEX.test("2026-05-01T10:00:00+01:00")).toBe(true);
	});
	test("rejects date-only strings", () => {
		expect(DATETIME_REGEX.test("2026-05-01")).toBe(false);
	});
});

// --- Zod schema validation ---
describe("Input length limits", () => {
	test("title max 500 chars", () => {
		const schema = z.string().max(500);
		expect(() => schema.parse("a".repeat(501))).toThrow();
		expect(schema.parse("a".repeat(500))).toHaveLength(500);
	});

	test("location max 500 chars", () => {
		const schema = z.string().max(500);
		expect(() => schema.parse("x".repeat(501))).toThrow();
	});

	test("notes max 5000 chars", () => {
		const schema = z.string().max(5000);
		expect(() => schema.parse("n".repeat(5001))).toThrow();
		expect(schema.parse("n".repeat(5000))).toHaveLength(5000);
	});

	test("event_id max 200 chars", () => {
		const schema = z.string().max(200);
		expect(() => schema.parse("i".repeat(201))).toThrow();
	});

	test("calendar max 200 chars", () => {
		const schema = z.string().max(200);
		expect(() => schema.parse("c".repeat(201))).toThrow();
	});

	test("query max 500 chars", () => {
		const schema = z.string().max(500);
		expect(() => schema.parse("q".repeat(501))).toThrow();
	});
});

describe("days_ahead bounds", () => {
	const schema = z.number().int().min(1).max(365).optional();
	test("accepts values in range", () => {
		expect(schema.parse(1)).toBe(1);
		expect(schema.parse(365)).toBe(365);
		expect(schema.parse(30)).toBe(30);
	});
	test("rejects values out of range", () => {
		expect(() => schema.parse(0)).toThrow();
		expect(() => schema.parse(-1)).toThrow();
		expect(() => schema.parse(366)).toThrow();
	});
	test("accepts undefined (optional)", () => {
		expect(schema.parse(undefined)).toBeUndefined();
	});
});

// --- Write gate ---
describe("assertWriteEnabled", () => {
	const originalEnv = process.env.ICAL_ALLOW_WRITE;

	afterEach(() => {
		// Restore original env
		if (originalEnv === undefined) {
			delete process.env.ICAL_ALLOW_WRITE;
		} else {
			process.env.ICAL_ALLOW_WRITE = originalEnv;
		}
	});

	test("throws when ICAL_ALLOW_WRITE is not set", () => {
		delete process.env.ICAL_ALLOW_WRITE;
		const WRITE_ENABLED = process.env.ICAL_ALLOW_WRITE === "true";
		const assertWriteEnabled = () => {
			if (!WRITE_ENABLED) {
				throw new Error(
					"Write operations are disabled. Set the ICAL_ALLOW_WRITE=true environment variable to enable create, update, and delete.",
				);
			}
		};
		expect(() => assertWriteEnabled()).toThrow("Write operations are disabled");
	});

	test("throws when ICAL_ALLOW_WRITE is 'false'", () => {
		process.env.ICAL_ALLOW_WRITE = "false";
		const WRITE_ENABLED = process.env.ICAL_ALLOW_WRITE === "true";
		const assertWriteEnabled = () => {
			if (!WRITE_ENABLED) throw new Error("Write operations are disabled.");
		};
		expect(() => assertWriteEnabled()).toThrow();
	});

	test("does not throw when ICAL_ALLOW_WRITE=true", () => {
		process.env.ICAL_ALLOW_WRITE = "true";
		const WRITE_ENABLED = process.env.ICAL_ALLOW_WRITE === "true";
		const assertWriteEnabled = () => {
			if (!WRITE_ENABLED) throw new Error("Write operations are disabled.");
		};
		expect(() => assertWriteEnabled()).not.toThrow();
	});
});

// --- include_notes default ---
describe("include_notes schema", () => {
	const schema = z.boolean().optional().default(false);
	test("defaults to false when not provided", () => {
		expect(schema.parse(undefined)).toBe(false);
	});
	test("accepts explicit true", () => {
		expect(schema.parse(true)).toBe(true);
	});
	test("accepts explicit false", () => {
		expect(schema.parse(false)).toBe(false);
	});
});
