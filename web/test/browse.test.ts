// /api/categories and /api/browse (#97), and the pages the Worker serves.
import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import headersFile from "../public/_headers?raw";
import indexHtml from "../public/index.html?raw";
import itemHtml from "../public/item.html?raw";
import notFoundHtml from "../public/404.html?raw";
import meHtml from "../public/me/index.html?raw";
import fishingHtml from "../public/me/fishing/index.html?raw";
import { PAGE_HEADERS } from "../src/pages";
import { BOOTY, call, clearData, HORDE, houses, makeToken, now, upload } from "./helpers";

const DAY = 86400;
const t0 = now();
const today = Math.floor(t0 / DAY);
const H = encodeURIComponent(HORDE);

interface BrowseBody {
	today: number;
	more: boolean;
	items: { id: number; name: string | null; class: number | null; current: { min: number } | null; typical: { status: string }; days: { day: number; src: string; typ: number | null }[] }[];
}

beforeAll(async () => {
	await clearData();
	const token = await makeToken("public");
	const day = (d: number, typ: number) => ({ day: today - d, lo: typ - 5, typ, hi: typ + 20, qtyMax: 100, listMax: 5, n: 2 });
	const res = await upload(token, {
		v: 1,
		houses: houses(),
		scans: [{ house: HORDE, t: t0, kind: "full", items: 2, lastOnly: 2, source: "ui" }],
		items: {
			"2589": { n: "Linen Cloth", q: 1, i: 132889, c: 7, s: 5 },
			"4306": { n: "Silk Cloth", q: 1, i: 132905, c: 7, s: 5 },
			"2447": { n: "Peacebloom", q: 1, i: 133939, c: 7, s: 9 },
			"858": { n: "Lesser Healing Potion", q: 1, i: 134830, c: 0, s: 1 },
		},
		prices: [
			{
				item: "2589",
				house: HORDE,
				last: { t: t0, min: 150, qty: 300, listings: 4 },
				days: [day(10, 90), day(7, 100), day(1, 110), day(0, 120)],
			},
			{ item: "4306", house: HORDE, last: { t: t0, min: 900, qty: 20, listings: 2 } },
			{ item: "2447", house: HORDE, last: { t: t0, min: 30, qty: 50, listings: 3 } },
			{ item: "2447", house: BOOTY, last: { t: t0, min: 40, qty: 5, listings: 1 } },
			{ item: "858", house: BOOTY, last: { t: t0, min: 70, qty: 5, listings: 1 } },
			// A price without item info yet.
			{ item: "999", house: HORDE, last: { t: t0, min: 5, qty: 1, listings: 1 } },
		],
	});
	expect(res.status).toBe(200);
});

describe("categories", () => {
	it("counts the items priced at a house per class and subclass, and caches the index", async () => {
		const res = await call("GET", `/api/categories?house=${H}`);
		expect(res.status).toBe(200);
		const body = await res.json<{ categories: unknown[]; label: string }>();
		expect(body.label).toBe("Horde AH");
		expect(body.categories).toEqual([
			{ class: null, subclass: null, items: 1 },
			{ class: 7, subclass: 5, items: 2 },
			{ class: 7, subclass: 9, items: 1 },
		]);
		const cached = await env.DB.prepare("SELECT count(*) AS n FROM cache WHERE key LIKE 'categories:%'").first<{ n: number }>();
		expect(cached!.n).toBe(1);
		expect((await call("GET", "/api/categories")).status).toBe(400);
		expect((await call("GET", "/api/categories?house=nope")).status).toBe(404);
	});
});

describe("browse", () => {
	it("lists a subclass with prices, typical price and the daily rows of the last 9 days", async () => {
		const body = await (await call("GET", `/api/browse?house=${H}&class=7&subclass=5`)).json<BrowseBody>();
		expect(body.today).toBe(today);
		expect(body.more).toBe(false);
		expect(body.items.map((i) => i.name)).toEqual(["Linen Cloth", "Silk Cloth"]);
		const linen = body.items[0]!;
		expect(linen.current).toMatchObject({ min: 150, qty: 300, listings: 4, listed: true });
		expect(linen.typical).toEqual({ status: "too_little_history", days: 2 });
		expect(linen.days.map((d) => d.day)).toEqual([today - 7, today - 1, today]);
		expect(linen.days[0]).toEqual({ day: today - 7, src: "craftwise", lo: 95, typ: 100, hi: 120, qtyMax: 100 });
		expect(body.items[1]!.days).toEqual([{ day: today, src: "last", lo: 900, typ: null, hi: 900, qtyMax: 20 }]);
	});

	it("lists a whole class, items without info, a search and favourites", async () => {
		let body = await (await call("GET", `/api/browse?house=${H}&class=7`)).json<BrowseBody>();
		expect(body.items.map((i) => i.id).sort()).toEqual([2447, 2589, 4306]);
		body = await (await call("GET", `/api/browse?house=${H}&class=none`)).json<BrowseBody>();
		expect(body.items).toMatchObject([{ id: 999, name: null, class: null, current: { min: 5 } }]);
		body = await (await call("GET", `/api/browse?house=${H}&q=cloth`)).json<BrowseBody>();
		expect(body.items.map((i) => i.name)).toEqual(["Linen Cloth", "Silk Cloth"]);
		body = await (await call("GET", `/api/browse?house=${H}&ids=858,2447,2447`)).json<BrowseBody>();
		expect(body.items.map((i) => [i.id, i.current?.min ?? null])).toEqual([
			[858, null], // only priced at Booty Bay
			[2447, 30],
		]);
		expect(body.items[0]!.typical).toEqual({ status: "no_data", days: 0 });
	});

	it("refuses unclear or oversized queries", async () => {
		expect((await call("GET", `/api/browse?house=${H}`)).status).toBe(400);
		expect((await call("GET", `/api/browse?house=${H}&class=7&q=cloth`)).status).toBe(400);
		expect((await call("GET", `/api/browse?house=${H}&class=x`)).status).toBe(400);
		expect((await call("GET", `/api/browse?house=${H}&ids=1,abc`)).status).toBe(400);
		const many = Array.from({ length: 101 }, (_, i) => i + 1).join(",");
		expect((await call("GET", `/api/browse?house=${H}&ids=${many}`)).status).toBe(400);
		expect((await call("GET", `/api/browse?house=${H}&q=a`)).status).toBe(400);
		expect((await call("GET", "/api/browse?class=7")).status).toBe(400);
	});
});

describe("pages", () => {
	it("serves the list page and the item page for /item/<id>, with the security headers", async () => {
		const list = await call("GET", "/");
		expect(list.status).toBe(200);
		expect(await list.text()).toContain('<script type="module" src="/assets/list.js"></script>');
		const item = await call("GET", "/item/2589");
		expect(item.status).toBe(200);
		expect(item.headers.get("content-type")).toContain("text/html");
		expect(await item.text()).toContain('<script type="module" src="/assets/item.js"></script>');
		for (const [k, v] of Object.entries(PAGE_HEADERS)) expect(item.headers.get(k)).toBe(v);
	});

	it("answers 404 with the not-found page for a bad item path", async () => {
		for (const path of ["/item/abc", "/item/0", "/item/12/x"]) {
			const res = await call("GET", path);
			expect(res.status).toBe(404);
			expect(await res.text()).toContain("This page does not exist");
		}
		expect((await call("POST", "/item/2589")).status).toBe(405);
	});

	it("allows exactly the inline skin script, the same in _headers and in the Worker", async () => {
		const hashes = new Set<string>();
		for (const html of [indexHtml, itemHtml, notFoundHtml, meHtml, fishingHtml]) {
			const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]!);
			expect(scripts).toHaveLength(1);
			const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(scripts[0]!)));
			hashes.add(btoa(String.fromCharCode(...digest)));
		}
		expect(hashes.size).toBe(1);
		const csp = PAGE_HEADERS["content-security-policy"]!;
		expect(csp).toContain(`'sha256-${[...hashes][0]}'`);
		const fromFile = Object.fromEntries(
			headersFile
				.split("\n")
				.filter((l) => /^\s+\S/.test(l))
				.map((l) => {
					const i = l.indexOf(":");
					return [l.slice(0, i).trim().toLowerCase(), l.slice(i + 1).trim()];
				}),
		);
		expect(fromFile).toEqual(PAGE_HEADERS);
	});
});
