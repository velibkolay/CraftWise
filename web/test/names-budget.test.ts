// Measures the rows written when the client's class and subclass names and the vendor sell prices
// (#120) arrive, at a real-like volume (invented data): 18,000 items, 18 classes with 10 subclasses
// each. Uploaded the way the companion does (upload/delta.go): requests of at most 8,000 estimated
// rows, i.e. about 1,700 items each. The numbers are printed and documented in web/docs/api.md
// ("Budget").
import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { call, clearData, houses, makeToken } from "./helpers";

const ITEMS = 18_000;
const PER_REQUEST = 1_700;
const CLASSES = 18;
const SUBCLASSES = 10;
const BASE_ID = 200_000;

let token: string;

function name(i: number): string {
	const words = ["Silver", "Copper", "Bolt", "Linen", "Elixir", "Potion", "Greater", "Minor", "Leather", "Essence", "Shard", "Lotus"];
	const a = words[i % 12]!, b = words[(i >> 3) % 12]!, c = words[(i >> 6) % 12]!;
	return i % 3 === 0 ? `${a} of ${b} ${c}` : `${a} ${b}`;
}

function info(i: number, sell: boolean) {
	const out: Record<string, number> = { q: i % 5, i: 130000 + i, c: i % CLASSES, s: i % SUBCLASSES };
	if (sell) out.p = i % 7 === 0 ? 0 : 5 + ((i * 37) % 25000); // every 7th: vendors don't buy it
	return out;
}

function classNames() {
	const classes: Record<string, string> = {};
	const subs: Record<string, Record<string, string>> = {};
	for (let c = 0; c < CLASSES; c++) {
		classes[c] = `Class Name ${c}`;
		subs[c] = {};
		for (let s = 0; s < SUBCLASSES; s++) subs[c]![s] = `Subclass Name ${c}.${s}`;
	}
	return { classNames: classes, subclassNames: subs };
}

// Uploads every item's info (and name when `names`), PER_REQUEST items per request; `extra` goes into
// the first request. Returns the rows D1 reported and the number of requests.
async function send(opts: { sell: boolean; names: boolean; extra?: Record<string, unknown> }) {
	let rows = 0;
	let requests = 0;
	for (let from = 0; from < ITEMS; from += PER_REQUEST) {
		const body: Record<string, unknown> = { v: 1, houses: houses(), itemInfo: {} as Record<string, unknown> };
		if (opts.names) body.names = {};
		for (let i = from; i < Math.min(ITEMS, from + PER_REQUEST); i++) {
			(body.itemInfo as Record<string, unknown>)[BASE_ID + i] = info(i, opts.sell);
			if (opts.names) (body.names as Record<string, string>)[BASE_ID + i] = name(i);
		}
		if (from === 0 && opts.extra) Object.assign(body, opts.extra);
		const res = await call("POST", "/api/upload", { body, headers: { authorization: `Bearer ${token}` } });
		expect(res.status, await res.clone().text()).toBe(200);
		rows += (await res.json<{ rowsWritten: number }>()).rowsWritten;
		requests++;
	}
	await env.DB.exec("DELETE FROM usage; UPDATE tokens SET rl_count = 0;");
	return { rows, requests };
}

beforeAll(async () => {
	await clearData();
	token = await makeToken("public");
});

describe("write budget of class names and sell prices (#120, measurement)", () => {
	it("costs one row per known item once, nothing for a new item, nothing after that", async () => {
		// Before #120: 18,000 items with names and info (houses written here too).
		const before = await send({ sell: false, names: true });
		// 1. The first upload after the update: sell prices for every known item, all class names.
		const first = await send({ sell: true, names: true, extra: classNames() });
		// 2. The same again (another upload with nothing new): only the rate-limit rows.
		const again = await send({ sell: true, names: true, extra: classNames() });
		// 3. A fresh install: info, names and sell prices arrive together.
		await env.DB.exec("DELETE FROM items; DELETE FROM item_words; DELETE FROM item_classes; DELETE FROM item_subclasses;");
		const freshWithout = await send({ sell: false, names: true });
		await env.DB.exec("DELETE FROM items; DELETE FROM item_words;");
		const freshWith = await send({ sell: true, names: true, extra: classNames() });
		const counts = await env.DB.prepare(
			"SELECT (SELECT count(*) FROM items WHERE sell_price IS NOT NULL) priced, (SELECT count(*) FROM item_classes) classes, (SELECT count(*) FROM item_subclasses) subclasses",
		).first<{ priced: number; classes: number; subclasses: number }>();
		console.log(JSON.stringify({ before, first, again, freshWithout, freshWith, counts }, null, 1));
		expect(counts).toEqual({ priced: ITEMS, classes: CLASSES, subclasses: CLASSES * SUBCLASSES });
		// one row per item plus one per name, plus the token's rate-limit row per request
		expect(first.rows).toBe(ITEMS + CLASSES + CLASSES * SUBCLASSES + first.requests);
		expect(again.rows).toBe(again.requests);
		// a sell price that comes with the item's first info costs nothing extra
		expect(freshWith.rows).toBe(freshWithout.rows + CLASSES + CLASSES * SUBCLASSES);
	});
});
