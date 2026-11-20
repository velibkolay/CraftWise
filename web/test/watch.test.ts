// The watch list (#165), two-way since #244: changes uploaded with the private upload, set from the site's
// favourites, merged per item (newest wins, a tie keeps the item, removals are kept as tombstones), read at
// /api/me/watch and downloaded by the companion at /api/sync/watch.
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { access, accessJwt, accessKey, bearer, call, clearData, makeToken, now, ORIGIN, serveAccessKeys, type AccessKey } from "./helpers";

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

interface Change {
	i: number;
	t: number;
	d?: boolean;
}
const up = (token: string, watch: unknown) => call("POST", "/api/private/upload", { body: { v: 1, watch }, headers: bearer(token) });
async function stored(): Promise<{ item: number; added: number }[]> {
	const res = await call("GET", "/api/me/watch", { headers: access(await accessJwt(key)) });
	expect(res.status).toBe(200);
	expect(res.headers.get("cache-control")).toBe("private, no-store");
	return (await res.json<{ watch: { item: number; added: number }[] }>()).watch;
}
async function site(item: unknown, on: unknown): Promise<Response> {
	return call("POST", "/api/me/watch", { body: { item, on }, headers: access(await accessJwt(key), { origin: ORIGIN }) });
}
async function download(token: string, since = 0): Promise<{ v: number; watch: Change[]; until: number }> {
	const res = await call("GET", `/api/sync/watch?since=${since}`, { headers: bearer(token) });
	expect(res.status).toBe(200);
	expect(res.headers.get("cache-control")).toBe("private, no-store");
	return res.json();
}
const sorted = (l: Change[]) => [...l].sort((a, b) => a.i - b.i);

describe("watch list upload", () => {
	it("needs an Access login to read", async () => {
		expect((await call("GET", "/api/me/watch")).status).toBe(403);
	});

	it("stores changes, newest first, and never replaces the list", async () => {
		const token = await makeToken("private");
		const t = now();
		const res = await up(token, [{ i: 2589, t: t - 100 }, { i: 4306, t: t - 50 }, { i: 2589, t: t - 1 }]);
		expect(res.status).toBe(200);
		expect((await res.json<{ received: { watch: number } }>()).received.watch).toBe(2); // the older change of 2589 is dropped
		expect(await stored()).toEqual([
			{ item: 2589, added: t - 1 },
			{ item: 4306, added: t - 50 },
		]);
		// a second upload with another item adds to the list: nothing is deleted
		expect((await up(token, [{ i: 5000, t: t - 5 }])).status).toBe(200);
		expect((await stored()).map((w) => w.item)).toEqual([2589, 5000, 4306]);
	});

	it("a removal is a tombstone: older adds don't bring the item back, newer ones do", async () => {
		const token = await makeToken("private");
		const t = now();
		await up(token, [{ i: 7, t: t - 100 }]);
		await up(token, [{ i: 7, t: t - 50, d: true }]);
		expect(await stored()).toEqual([]);
		await up(token, [{ i: 7, t: t - 70 }]); // an add older than the removal arrives late
		expect(await stored()).toEqual([]);
		await up(token, [{ i: 7, t: t - 10 }]);
		expect(await stored()).toEqual([{ item: 7, added: t - 10 }]);
		await up(token, [{ i: 7, t: t - 20, d: true }]); // a removal older than the add
		expect(await stored()).toEqual([{ item: 7, added: t - 10 }]);
	});

	it("a tie keeps the item; the same change again writes nothing", async () => {
		const token = await makeToken("private");
		const t = now() - 10;
		await up(token, [{ i: 7, t, d: true }]);
		await up(token, [{ i: 7, t }]);
		expect(await stored()).toEqual([{ item: 7, added: t }]);
		await up(token, [{ i: 7, t, d: true }]); // the removal on the same second loses
		expect(await stored()).toEqual([{ item: 7, added: t }]);
		const again = await up(token, [{ i: 7, t }]);
		expect((await again.json<{ rowsWritten: number }>()).rowsWritten).toBe(1); // the rate-limit row
	});

	it("the same changes in any order end in the same list", async () => {
		const t = now();
		const changes: Change[] = [{ i: 1, t: t - 30 }, { i: 1, t: t - 20, d: true }, { i: 2, t: t - 10 }, { i: 2, t: t - 10, d: true }, { i: 3, t: t - 5, d: true }];
		const orders = [changes, [...changes].reverse(), [changes[3]!, changes[0]!, changes[4]!, changes[2]!, changes[1]!]];
		const results: string[] = [];
		for (const order of orders) {
			await clearData();
			const token = await makeToken("private");
			for (const c of order) await up(token, [c]);
			results.push(JSON.stringify(sorted((await download(token)).watch)));
		}
		expect(new Set(results).size).toBe(1);
		expect(JSON.parse(results[0]!)).toEqual([{ i: 1, t: t - 20, d: true }, { i: 2, t: t - 10 }, { i: 3, t: t - 5, d: true }]);
	});

	it("an empty list of changes, or no field, changes nothing", async () => {
		const token = await makeToken("private");
		const t = now();
		await up(token, [{ i: 2589, t }]);
		const other = { v: 1, ledger: [{ t, c: "Realm-Name Sur", k: "vsell", i: 1, q: 1, m: 1 }] };
		expect((await call("POST", "/api/private/upload", { body: other, headers: bearer(token) })).status).toBe(200);
		expect((await up(token, [])).status).toBe(200);
		expect(await stored()).toHaveLength(1);
	});

	it("refuses a malformed list", async () => {
		const token = await makeToken("private");
		const t = now();
		for (const watch of [{}, [1], [{ i: 0, t }], [{ i: 5, t: 5 }], [{ i: "5", t }], [{ i: 5 }], [{ i: 5, t, d: 1 }], Array.from({ length: 1001 }, (_, i) => ({ i: i + 1, t }))]) {
			const res = await up(token, watch);
			expect(res.status, JSON.stringify(watch).slice(0, 60)).toBe(400);
			expect((await res.json<{ error: string }>()).error).toBe("bad_shape");
		}
	});
});

describe("favourites set on the site", () => {
	it("watch and unwatch with the server's clock, merged with the uploads", async () => {
		const token = await makeToken("private");
		const t = now();
		await up(token, [{ i: 10, t: t - 1000 }]);
		let res = await site(11, true);
		expect(res.status).toBe(200);
		expect((await stored()).map((w) => w.item).sort()).toEqual([10, 11]);
		expect((await site(10, false)).status).toBe(200);
		expect((await stored()).map((w) => w.item)).toEqual([11]);
		// an older add from a machine that was offline doesn't bring 10 back
		await up(token, [{ i: 10, t: t - 500 }]);
		expect((await stored()).map((w) => w.item)).toEqual([11]);
		const d = await download(token);
		expect(sorted(d.watch).map((c) => [c.i, c.d === true])).toEqual([[10, true], [11, false]]);
		res = await site(11, false);
		expect(res.status).toBe(200);
		expect(await stored()).toEqual([]);
	});

	it("needs a login with an e-mail and the same origin, and a valid body", async () => {
		expect((await call("POST", "/api/me/watch", { body: { item: 1, on: true } })).status).toBe(403);
		const jwt = await accessJwt(key);
		expect((await call("POST", "/api/me/watch", { body: { item: 1, on: true }, headers: access(jwt, { origin: "https://evil.example" }) })).status).toBe(403);
		for (const body of [{ item: 0, on: true }, { item: 1.5, on: true }, { item: "1", on: true }, { item: 1 }, { item: 1, on: 1 }, {}]) {
			const res = await site((body as { item?: unknown }).item, (body as { on?: unknown }).on);
			expect(res.status, JSON.stringify(body)).toBe(400);
		}
		expect(await stored()).toEqual([]);
	});
});

describe("GET /api/sync/watch", () => {
	it("needs a token with the private scope", async () => {
		expect((await call("GET", "/api/sync/watch")).status).toBe(401);
		const pub = await makeToken("public");
		expect((await call("GET", "/api/sync/watch", { headers: bearer(pub) })).status).toBe(403);
		expect((await call("GET", "/api/sync/watch?since=x", { headers: bearer(await makeToken("private")) })).status).toBe(400);
	});

	it("gives the changes since a time, tombstones included", async () => {
		const token = await makeToken("private");
		const t = now();
		await up(token, [{ i: 1, t: t - 100 }, { i: 2, t: t - 90, d: true }]);
		const all = await download(token);
		expect(all.v).toBe(1);
		expect(sorted(all.watch)).toEqual([{ i: 1, t: t - 100 }, { i: 2, t: t - 90, d: true }]);
		expect(all.until).toBeLessThanOrEqual(now());
		expect((await download(token, now() + 1000)).watch).toEqual([]);
	});
});
