import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { resolve } from "node:path";

// Spawns the real server over stdio and speaks both MCP eras to it. The
// handshakes never call the Swift binary, but index.ts refuses to start
// without one, so a stub stands in when bin/ is empty (Linux CI).
const ENTRY = resolve(import.meta.dir, "index.ts");
const BIN = resolve(import.meta.dir, "../bin/calendar-reader");
const stubbed = !existsSync(BIN);
const META = {
	"io.modelcontextprotocol/protocolVersion": "2026-07-28",
	"io.modelcontextprotocol/clientCapabilities": {},
	"io.modelcontextprotocol/clientInfo": { name: "test", version: "0" },
};
const INIT = {
	jsonrpc: "2.0",
	id: 1,
	method: "initialize",
	params: {
		protocolVersion: "2025-06-18",
		capabilities: {},
		clientInfo: { name: "test", version: "0" },
	},
};

beforeAll(() => {
	if (!stubbed) return;
	mkdirSync(resolve(BIN, ".."), { recursive: true });
	writeFileSync(BIN, '#!/bin/sh\necho "[]"\n');
	chmodSync(BIN, 0o755);
});
afterAll(() => {
	if (stubbed) rmSync(BIN);
});

// biome-ignore lint/suspicious/noExplicitAny: JSON-RPC replies are untyped
async function exchange(messages: object[], replies: number): Promise<any[]> {
	const proc = Bun.spawn(["bun", "run", ENTRY], {
		stdin: "pipe",
		stdout: "pipe",
		stderr: "ignore",
	});
	const out: object[] = [];
	const reader = proc.stdout.getReader();
	let buf = "";
	for (const m of messages) proc.stdin.write(`${JSON.stringify(m)}\n`);
	proc.stdin.flush();
	while (out.length < replies) {
		const { value, done } = await reader.read();
		if (done) break;
		buf += new TextDecoder().decode(value);
		let nl = buf.indexOf("\n");
		while (nl >= 0) {
			const line = buf.slice(0, nl).trim();
			buf = buf.slice(nl + 1);
			if (line) out.push(JSON.parse(line));
			nl = buf.indexOf("\n");
		}
	}
	proc.stdin.end();
	await proc.exited;
	return out;
}

describe("stdio protocol eras", () => {
	test("2025 initialize then tools/list", async () => {
		const [init, list] = await exchange(
			[
				INIT,
				{ jsonrpc: "2.0", method: "notifications/initialized" },
				{ jsonrpc: "2.0", id: 2, method: "tools/list" },
			],
			2,
		);
		expect(init.result.protocolVersion).toBe("2025-06-18");
		expect(list.result.tools).toHaveLength(7);
	}, 15000);

	test("2026-07-28 server/discover then tools/list, no initialize", async () => {
		const [discover, list] = await exchange(
			[
				{
					jsonrpc: "2.0",
					id: 1,
					method: "server/discover",
					params: { _meta: META },
				},
				{
					jsonrpc: "2.0",
					id: 2,
					method: "tools/list",
					params: { _meta: META },
				},
			],
			2,
		);
		expect(discover.result.supportedVersions).toContain("2026-07-28");
		expect(list.result.resultType).toBe("complete");
		expect(list.result.tools).toHaveLength(7);
	}, 15000);

	test("probe with server/discover, then fall back to initialize", async () => {
		const [, init] = await exchange(
			[
				{
					jsonrpc: "2.0",
					id: 0,
					method: "server/discover",
					params: { _meta: META },
				},
				INIT,
			],
			2,
		);
		expect(init.result.protocolVersion).toBe("2025-06-18");
	}, 15000);
});
