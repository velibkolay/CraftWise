// The craft log (#266): uploaded with the private upload, read at /api/me/crafted. All data is invented.
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { PAGE_HEADERS } from "../src/pages";
import { access, accessJwt, accessKey, bearer, call, clearData, makeToken, serveAccessKeys, type AccessKey } from "./helpers";

let key: AccessKey;
beforeAll(async () => {
	key = await accessKey("k1");
});
beforeEach(async () => {
	await clearData();
	serveAccessKeys([key]);
});
afterEach(() => {
	vi.restoreAllMocks();
});

const A = "Example Realm-Aria Stonehide";
const B = "Example Realm-Bram";
const up = (token: string, body: unknown) => call("POST", "/api/private/upload", { body, headers: bearer(token) });
const row = (c: string, r: number, d: number, n: number, extra: Record<string, unknown> = {}) => ({ c, r, d, n, ...extra });
type Row = [string, number, number, number, number | null, number | null, number | null, number | null];
async function read(query = ""): Promise<{ rows: Row[]; more: boolean }> {
	const res = await call("GET", `/api/me/crafted${query}`, { headers: access(await accessJwt(key)) });
	expect(res.status).toBe(200);
	expect(res.headers.get("cache-control")).toBe("private, no-store");
	return res.json();
}

describe("craft log upload and read", () => {
	it("needs an Access login to read", async () => {
		expect((await call("GET", "/api/me/crafted")).status).toBe(403);
	});

	it("stores one row per character, recipe and day, oldest day first, with what was recorded", async () => {
		const token = await makeToken("private");
		const res = await up(token, {
			v: 1,
			crafted: [
				row(A, 2549, 20261115, 4, { i: 4, p: -120, k: 3 }),
				row(A, 2549, 20261114, 10, { i: 10, p: 2500, k: 10, a: 31.5 }),
				row(B, 3000, 20261114, 2), // nothing recorded but the count
			],
		});
		expect(res.status).toBe(200);
		expect((await res.json<{ received: { crafted: number } }>()).received.crafted).toBe(3);
		expect((await read()).rows).toEqual([
			[A, 2549, 20261114, 10, 10, 2500, 10, 31.5],
			[B, 3000, 20261114, 2, null, null, null, null],
			[A, 2549, 20261115, 4, 4, -120, 3, null],
		]);
	});

	it("registers the character and filters by character and day", async () => {
		const token = await makeToken("private");
		await up(token, { v: 1, crafted: [row(A, 1, 20261110, 1), row(A, 1, 20261112, 2), row(B, 1, 20261112, 3)] });
		expect((await read(`?char=${encodeURIComponent(B)}`)).rows.map((r) => r[3])).toEqual([3]);
		expect((await read("?since=20261112")).rows.map((r) => r[3])).toEqual([2, 3]);
		expect((await read("?since=20261113")).rows).toEqual([]);
		const chars = await (await call("GET", "/api/me/characters", { headers: access(await accessJwt(key)) })).json<{ characters: { key: string }[] }>();
		expect(chars.characters.map((c) => c.key)).toEqual([B, A].sort());
	});

	it("takes a day again idempotently: same data writes nothing, more crafts update it, fewer never do", async () => {
		const token = await makeToken("private");
		const body = { v: 1, crafted: [row(A, 2549, 20261114, 10, { p: 2500, k: 10 })] };
		const first = await (await up(token, body)).json<{ rowsWritten: number }>();
		expect(first.rowsWritten).toBeGreaterThanOrEqual(2); // the day, the character, the usage row
		const again = await (await up(token, body)).json<{ rowsWritten: number }>();
		expect(again.rowsWritten).toBe(1); // only the usage row
		expect((await read()).rows).toHaveLength(1);
		await up(token, { v: 1, crafted: [row(A, 2549, 20261114, 12, { p: 3100, k: 12, a: 40 })] });
		expect((await read()).rows).toEqual([[A, 2549, 20261114, 12, null, 3100, 12, 40]]);
		await up(token, { v: 1, crafted: [row(A, 2549, 20261114, 11, { p: 9 })] }); // an older copy of the file
		expect((await read()).rows).toEqual([[A, 2549, 20261114, 12, null, 3100, 12, 40]]);
	});

	it("keeps days the addon has folded away: later uploads never delete", async () => {
		const token = await makeToken("private");
		await up(token, { v: 1, crafted: [row(A, 1, 20260101, 5)] });
		await up(token, { v: 1, crafted: [row(A, 1, 20261114, 1)] });
		expect((await read()).rows.map((r) => r[2])).toEqual([20260101, 20261114]);
	});

	it("rejects what doesn't fit, with the field named", async () => {
		const token = await makeToken("private");
		const bad = async (r: unknown, field: string) => {
			const res = await up(token, { v: 1, crafted: [r] });
			expect(res.status).toBe(400);
			expect((await res.json<{ message: string }>()).message).toContain(field);
		};
		await bad(row("nobody", 1, 20261114, 1), "crafted[0].c");
		await bad(row(A, 0, 20261114, 1), "crafted[0].r");
		await bad(row(A, 1, 20261314, 1), "crafted[0].d");
		await bad(row(A, 1, 1114, 1), "crafted[0].d");
		await bad(row(A, 1, 20261114, 0), "crafted[0].n");
		await bad(row(A, 1, 20261114, 3, { k: 4 }), "crafted[0].k");
		await bad(row(A, 1, 20261114, 3, { p: 1.5 }), "crafted[0].p");
		await bad(row(A, 1, 20261114, 3, { a: -1 }), "crafted[0].a");
		await bad(row(A, 1, 20261114, 3, { a: 90_000 }), "crafted[0].a");
		const res = await up(token, { v: 1, crafted: Array.from({ length: 5001 }, () => row(A, 1, 20261114, 1)) });
		expect(res.status).toBe(400);
	});

	it("needs the private scope", async () => {
		const token = await makeToken("public");
		expect((await up(token, { v: 1, crafted: [row(A, 1, 20261114, 1)] })).status).toBe(403);
	});
});

describe("route /me/crafted", () => {
	it("serves the page only with Access, with the page headers", async () => {
		expect((await call("GET", "/me/crafted")).status).toBe(403);
		const jwt = await accessJwt(key);
		for (const path of ["/me/crafted", "/me/crafted/", "/me/crafted/index.html"]) {
			const res = await call("GET", path, { headers: access(jwt) });
			expect(res.status).toBe(200);
			expect(res.headers.get("cache-control")).toBe("private, no-store");
			for (const [k, v] of Object.entries(PAGE_HEADERS)) expect(res.headers.get(k)).toBe(v);
			expect(await res.text()).toContain('<script type="module" src="/assets/crafted.js"></script>');
		}
		expect((await call("GET", "/me/crafted/more", { headers: access(jwt) })).status).toBe(404);
	});
});
