import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { bearer, call, clearData, makeToken, now } from "./helpers";

const A = "CAMWOW EU4 Realm 8 PvP-Velikopter Tanner";
const B = "CAMWOW EU4 Realm 8 PvP-Mage Alt";
const DAY = 86400;

let token: string;
beforeEach(async () => {
	await clearData();
	token = await makeToken("public private", "Companion PC");
});

function snapshot(t: number, name: string, level = 20) {
	return { v: 1, t, char: { name, realm: "CAMWOW EU4 Realm 8 PvP", faction: "Horde", race: "Orc", class: "Hunter", level }, bags: { items: { "2589": 20 } } };
}

async function up(body: unknown, tok = token, machine?: string): Promise<Response> {
	const headers = bearer(tok);
	if (machine !== undefined) headers["x-craftwise-machine"] = machine;
	return call("POST", "/api/private/upload", { body, headers });
}

async function get(path: string, tok = token): Promise<Response> {
	return call("GET", path, { headers: bearer(tok) });
}

interface Char {
	machine: string | null;
	uploaded: number;
	info: Record<string, unknown>;
	snapshot?: { t: number; data: Record<string, unknown> };
	auctions?: { t: number; data: unknown };
	fishing?: { t: number; data: unknown };
	ledger: Record<string, unknown>[];
	crafted: Record<string, unknown>[];
}
interface Page {
	v: number;
	characters: Record<string, Char>;
	next: string | null;
	until: number;
}

async function page(path: string): Promise<Page> {
	const res = await get(path);
	expect(res.status).toBe(200);
	return (await res.json()) as Page;
}

async function all(since = 0, extra = ""): Promise<Page[]> {
	const pages: Page[] = [];
	let cursor: string | null = null;
	do {
		const p: Page = await page(`/api/sync/characters?since=${since}&limit=1${extra}${cursor ? `&cursor=${cursor}` : ""}`);
		pages.push(p);
		cursor = p.next;
	} while (cursor && pages.length < 20);
	return pages;
}

describe("GET /api/sync/characters (#242)", () => {
	it("needs a token with the private scope", async () => {
		expect((await call("GET", "/api/sync/characters")).status).toBe(401);
		const pub = await makeToken("public", "pub");
		expect((await get("/api/sync/characters", pub)).status).toBe(403);
		expect((await get("/api/sync/characters")).status).toBe(200);
		expect((await call("POST", "/api/sync/characters", { body: {}, headers: bearer(token) })).status).toBe(405);
	});

	it("gives a character as it was uploaded, with the machine and the upload time", async () => {
		const t = now();
		const res = await up(
			{
				v: 1,
				snapshots: { [A]: { t: t - 100, data: snapshot(t - 100, "Velikopter") } },
				auctions: { [A]: { t: t - 50, data: { active: [{ item: 1 }], sold: [] } } },
				fishing: { [A]: { t: t - 40, data: { days: 90, catches: 12 } } },
				ledger: [{ t: t - 1000, c: A, k: "ahbuy", i: 2589, q: 20, m: 2000, w: "H", n: "Linen Cloth" }, { t: t - 60 * DAY, c: A, k: "ahbuy", i: 1, q: 1, m: 5 }, { t: t - 200 * DAY, c: A, k: "ahbuy", i: 2, q: 1, m: 5 }],
				crafted: [{ c: A, r: 2575, d: Number(new Date((t - DAY) * 1000).toISOString().slice(0, 10).replace(/-/g, "")), n: 3, i: 3, p: -50, k: 2, a: 12.5 }],
			},
			token,
			"PC",
		);
		expect(res.status).toBe(200);

		const body = await page("/api/sync/characters");
		expect(body.v).toBe(1);
		expect(body.next).toBeNull();
		expect(body.until).toBeLessThanOrEqual(now() - 59);
		expect(Object.keys(body.characters)).toEqual([A]);
		const c = body.characters[A]!;
		expect(c.machine).toBe("PC");
		expect(c.uploaded).toBeGreaterThanOrEqual(t);
		expect(c.info).toMatchObject({ name: "Velikopter", realm: "CAMWOW EU4 Realm 8 PvP", faction: "Horde", race: "Orc", class: "Hunter", level: 20, t: t - 100 });
		expect(c.snapshot).toEqual({ t: t - 100, data: snapshot(t - 100, "Velikopter") });
		expect(c.auctions).toEqual({ t: t - 50, data: { active: [{ item: 1 }], sold: [] } });
		expect(c.fishing).toEqual({ t: t - 40, data: { days: 90, catches: 12 } });
		// the ledger window is 30 days: the old entry stays out; entries are oldest first
		expect(c.ledger).toEqual([{ t: t - 1000, k: "ahbuy", i: 2589, q: 20, m: 2000, w: "H", n: "Linen Cloth" }]);
		expect(c.crafted).toHaveLength(1);
		expect(c.crafted[0]).toMatchObject({ r: 2575, n: 3, i: 3, p: -50, k: 2, a: 12.5 });
		expect(body.characters[A]).not.toHaveProperty("data");

		// ledgerSince widens the window
		const wide = await page(`/api/sync/characters?ledgerSince=${t - 300 * DAY}`);
		expect(wide.characters[A]!.ledger.map((e) => e.i)).toEqual([1, 2589]); // clamped to 90 days: the 200 day old entry stays out
	});

	it("labels the machine with the header, else the token name", async () => {
		const t = now();
		await up({ v: 1, snapshots: { [A]: { t, data: snapshot(t, "Velikopter") } } }, token); // no header
		expect((await page("/api/sync/characters")).characters[A]!.machine).toBe("Companion PC");
		await up({ v: 1, snapshots: { [A]: { t: t + 1, data: snapshot(t + 1, "Velikopter") } } }, token, "  Mac  ");
		expect((await page("/api/sync/characters")).characters[A]!.machine).toBe("Mac");
		await up({ v: 1, snapshots: { [A]: { t: t + 2, data: snapshot(t + 2, "Velikopter") } } }, token, "x".repeat(65));
		expect((await page("/api/sync/characters")).characters[A]!.machine).toBe("Companion PC");
	});

	it("walks the characters in pages and returns only what was uploaded since", async () => {
		const t = now();
		await up({ v: 1, snapshots: { [A]: { t, data: snapshot(t, "Velikopter") }, [B]: { t, data: snapshot(t, "Mage", 5) } } }, token, "PC");
		const pages = await all();
		expect(pages).toHaveLength(2);
		expect(pages.every((p) => Object.keys(p.characters).length === 1)).toBe(true);
		expect(pages[0]!.next).not.toBeNull();
		expect(pages[1]!.next).toBeNull();
		expect(pages.flatMap((p) => Object.keys(p.characters)).sort()).toEqual([B, A].sort());

		// B changes later on the other machine; a download since just before that has only B
		await env.DB.prepare("UPDATE characters SET uploaded = uploaded - 1000").run();
		const mark = now() - 500;
		await up({ v: 1, snapshots: { [B]: { t: t + 5, data: snapshot(t + 5, "Mage", 6) } } }, token, "Mac");
		const delta = await all(mark);
		expect(delta.flatMap((p) => Object.keys(p.characters))).toEqual([B]);
		expect(delta[0]!.characters[B]).toMatchObject({ machine: "Mac", info: { level: 6 } });
		// the machine filter leaves the caller's own out
		const others = await all(0, "&notMachine=Mac");
		expect(others.flatMap((p) => Object.keys(p.characters))).toEqual([A]);
	});

	it("moves `uploaded` only when the data changed", async () => {
		const t = now();
		const body = { v: 1, snapshots: { [A]: { t, data: snapshot(t, "Velikopter") } }, ledger: [{ t: t - 10, c: A, k: "ahbuy", i: 1, q: 1, m: 5 }] };
		await up(body, token, "PC");
		await env.DB.prepare("UPDATE characters SET uploaded = 1700000000").run();
		const res = await up(body, token, "PC"); // the same again
		expect((await res.json<{ rowsWritten: number }>()).rowsWritten).toBe(1); // only the rate-limit row
		expect((await page("/api/sync/characters")).characters[A]!.uploaded).toBe(1700000000);
		// a new ledger entry is a change
		await up({ v: 1, ledger: [{ t: t - 5, c: A, k: "ahsell", i: 1, q: 1, m: 9 }] }, token, "PC");
		expect((await page("/api/sync/characters")).characters[A]!.uploaded).toBeGreaterThanOrEqual(t);
	});

	it("caps the ledger per character, so a busy one doesn't starve the next", async () => {
		const t = now();
		await up({ v: 1, snapshots: { [A]: { t, data: snapshot(t, "Velikopter") }, [B]: { t, data: snapshot(t, "Mage") } } }, token, "PC");
		await env.DB.prepare(
			`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 2100)
			INSERT INTO ledger (uid, char, t, kind, item, qty, money) SELECT 'a' || i, ?1, ?2 - i, 'ahbuy', i, 1, 1 FROM n`,
		).bind(A, t - 10).run();
		await env.DB.prepare("INSERT INTO ledger (uid, char, t, kind, item, qty, money) VALUES ('b1', ?1, ?2, 'ahsell', 7, 1, 1), ('b2', ?1, ?3, 'ahsell', 8, 1, 1)")
			.bind(B, t - 5, t - 4).run();
		const body = await page("/api/sync/characters?limit=2");
		expect(Object.keys(body.characters).sort()).toEqual([A, B].sort());
		const a = body.characters[A]!.ledger;
		expect(a).toHaveLength(2000);
		expect(a[a.length - 1]!.i).toBe(1); // the newest entry is last (oldest first)
		expect(body.characters[B]!.ledger.map((e) => e.i)).toEqual([7, 8]);
	});

	it("keeps a key with dots and spaces through the cursor", async () => {
		const dotted = "CAMWOW EU4 Realm 8 PvP-Dr. Who";
		const t = now();
		await up({ v: 1, snapshots: { [dotted]: { t, data: snapshot(t, "Dr. Who") }, [A]: { t, data: snapshot(t, "Velikopter") } } }, token, "PC");
		await env.DB.prepare("UPDATE characters SET uploaded = ?1").bind(t).run();
		const pages = await all();
		expect(pages.flatMap((p) => Object.keys(p.characters)).sort()).toEqual([A, dotted].sort());
	});

	it("serves a character uploaded before the machine columns existed", async () => {
		const t = now();
		await env.DB.prepare("INSERT INTO characters (key, realm, name, updated) VALUES (?1, 'R', 'Old', ?2)").bind(A, t - 10).run();
		await env.DB.prepare("INSERT INTO snapshots (char, t, data) VALUES (?1, ?2, ?3)").bind(A, t - 10, JSON.stringify(snapshot(t - 10, "Old"))).run();
		await env.DB.prepare("UPDATE characters SET uploaded = NULL").run(); // as the migration leaves a never-stamped row
		const c = (await page("/api/sync/characters")).characters[A]!;
		expect(c.machine).toBeNull();
		expect(c.uploaded).toBe(t - 10);
		expect(c.snapshot!.t).toBe(t - 10);
		expect(c.auctions).toBeUndefined();
		expect(c.ledger).toEqual([]);
	});

	it("refuses a bad query", async () => {
		expect((await get("/api/sync/characters?since=abc")).status).toBe(400);
		expect((await get("/api/sync/characters?cursor=zzz")).status).toBe(400);
		expect((await get(`/api/sync/characters?notMachine=${"x".repeat(65)}`)).status).toBe(400);
	});
});
