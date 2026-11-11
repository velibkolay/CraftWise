// Measures rows written and database size for a realistic full browse of one auction house,
// uploaded the way the companion does: in requests of at most 2,000 price entries. The mix follows
// the first real upload (#118: 21,117 entries, 16,465 of them random-suffix variants of 1,333
// items): 5,000 items without a suffix (500 of them scope items with history) and 15,000 variants
// of 1,250 items. The numbers are printed and documented in web/docs/api.md ("Budget").
import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { MAX_PUBLIC_BYTES } from "../src/limits";
import { body as shape, call, clearData, HORDE, makeToken, now, type Short } from "./helpers";

const DAY = 86400;
const PLAIN = 5_000; // items without a random suffix
const SCOPE = 500; // of them with CraftWise history (own professions' reagents, products, recipes)
const VARIANTS = 15_000; // random-suffix variants ("<item>:<suffix>"), `last` only
const PER_ITEM = 12; // variants per item
const ENTRIES = PLAIN + VARIANTS;
const CHUNK = 1_000;
const BASE_ID = 100_000;

let token: string;
const t0 = now() - 3 * 3600;
const today = Math.floor(t0 / DAY);

// Names like the client's: two words, every third one "<word> of <word> <word>".
function name(i: number): string {
	const words = ["Silver", "Copper", "Bolt", "Linen", "Elixir", "Potion", "Greater", "Minor", "Leather", "Essence", "Shard", "Lotus"];
	const a = words[i % 12]!, b = words[(i >> 3) % 12]!, c = words[(i >> 6) % 12]!;
	return i % 3 === 0 ? `${a} of ${b} ${c}` : `${a} ${b}`;
}

// One scan of every item at `t`. Scope items carry their 30 days and the raw points of 48 h, the
// way the SavedVariables hold them (`history` days, a point every 8 h).
function chunk(from: number, to: number, t: number, opts: { info: boolean; history: number; shift: number; day?: number }) {
	const prices = [];
	const items: Record<string, unknown> = {};
	for (let i = from; i < to; i++) {
		const v = i - PLAIN; // variant number, negative for plain items
		const id = v < 0 ? BASE_ID + i : BASE_ID + PLAIN + Math.floor(v / PER_ITEM);
		const key = v < 0 ? String(id) : `${id}:${1 + (v % PER_ITEM)}`;
		if (opts.info && (v < 0 || v % PER_ITEM === 0)) items[id] = { n: name(i), q: i % 5, i: 130000 + i, c: 7, s: i % 12 };
		const base = 100 + (i % 977);
		const min = base + (i % 2 ? opts.shift : 0); // half the items moved
		const last = v < 0 ? { t, min, qty: 20 + (i % 300), listings: 1 + (i % 40) } : { t, min, qty: 1 + (i % 3) }; // browse rows: no listings
		const entry: Record<string, unknown> = { item: key, house: HORDE, last };
		if (i < SCOPE) {
			// points every 8 h before the first scan, plus this scan when it is a later one
			const times = Array.from({ length: 6 }, (_, k) => t0 - k * 8 * 3600);
			if (t > t0) times.unshift(t);
			entry.raw = times.map((pt, k) => {
				const tiers = [];
				const m0 = pt === t ? min : base;
				for (let l = 0; l < 8; l++) tiers.push(m0 + l * 7, 5 + l);
				return { t: pt, total: 300 + k, listings: 30, m: m0 + 20, tiers };
			});
			entry.days = Array.from({ length: opts.history }, (_, d) => ({
				day: (opts.day ?? today) - d,
				gone: ((opts.day ?? today) - d) % 3 ? 12 : undefined,
				lo: base - 3,
				typ: base + 10 + (d === 0 ? opts.shift : 0),
				hi: base + 60,
				qtyMax: 400,
				listMax: 40,
				n: 6,
			}));
		}
		prices.push(entry);
	}
	return { items: opts.info ? items : undefined, prices };
}

async function fullScan(t: number, opts: { info: boolean; history: number; shift: number; day?: number }) {
	let rows = 0;
	let maxBytes = 0;
	// Packs entries into bodies of at most 450 KB, as the companion should.
	const all = chunk(0, ENTRIES, t, opts);
	const bodies: { prices: unknown[]; items: Record<string, unknown> }[] = [];
	let cur = { prices: [] as unknown[], items: {} as Record<string, unknown> };
	let bytes = 0;
	for (const p of all.prices) {
		const id = (p as { item: string }).item.split(":")[0]!;
		const info = all.items && !cur.items[id] ? all.items[id] : undefined;
		const size = JSON.stringify(shape({ houses: {}, prices: [p] as Short["prices"] }).items).length + (info ? JSON.stringify(info).length + 12 : 0);
		if (cur.prices.length >= CHUNK || bytes + size > 450_000) {
			bodies.push(cur);
			cur = { prices: [], items: {} };
			bytes = 0;
		}
		cur.prices.push(p);
		if (all.items && all.items[id]) cur.items[id] = all.items[id];
		bytes += size;
	}
	bodies.push(cur);
	for (const [n, b] of bodies.entries()) {
		const short: Short = { prices: b.prices as Short["prices"] };
		if (all.items) short.items = b.items as Short["items"];
		if (n === 0) short.scans = [{ house: HORDE, t, kind: "full", items: SCOPE, lastOnly: ENTRIES - SCOPE, source: "auctionator" }];
		const text = JSON.stringify(shape(short));
		maxBytes = Math.max(maxBytes, text.length);
		const res = await call("POST", "/api/upload", { raw: text, headers: { authorization: `Bearer ${token}` } });
		expect(res.status, await res.clone().text()).toBe(200);
		rows += (await res.json<{ rowsWritten: number }>()).rowsWritten;
	}
	return { rows, maxBytes, requests: bodies.length };
}

async function size(): Promise<number> {
	const r = await env.DB.prepare("SELECT 1").run();
	return (r.meta as { size_after?: number }).size_after ?? NaN;
}

beforeAll(async () => {
	await clearData();
	token = await makeToken("public");
});

describe("write budget of a full scan (measurement)", () => {
	it("stays inside the free plan and the size limit", async () => {
		const empty = await size();
		await env.DB.exec("DELETE FROM usage"); // each pass below is measured on its own day budget
		// 1. First sync: item info, 7 days of history for the scope items (a fresh install), 6 raw points.
		const first = await fullScan(t0, { info: true, history: 7, shift: 0 });
		const afterFirst = await size();
		await env.DB.exec("DELETE FROM usage; UPDATE tokens SET rl_count = 0;");
		// 2. A second full scan the same day: every `last` is new, scope items gain one raw point
		//    and an updated day; half the other items moved their price.
		const second = await fullScan(t0 + 3600, { info: false, history: 7, shift: 5 });
		const afterSecond = await size();
		await env.DB.exec("DELETE FROM usage; UPDATE tokens SET rl_count = 0;");
		// 3. The next day's first full scan: a new daily row for every item.
		const nextDay = await fullScan(t0 + DAY, { info: false, history: 7, shift: 9, day: today + 1 });
		const afterNextDay = await size();
		const counts = await env.DB.prepare(
			"SELECT (SELECT count(*) FROM prices) prices, (SELECT count(*) FROM points) points, (SELECT count(*) FROM daily) daily, (SELECT count(*) FROM item_words) words, (SELECT count(*) FROM variants) variants, (SELECT count(*) FROM variant_days) variant_days",
		).first();
		console.log(
			JSON.stringify({ first, second, nextDay, bytes: { empty, afterFirst, afterSecond, afterNextDay }, counts, maxBody: MAX_PUBLIC_BYTES }, null, 1),
		);
		// #118: a day with a full browse, a second one and the reloads in between stays under ~40,000
		expect(first.rows).toBeLessThan(50_000);
		expect(second.rows).toBeLessThan(15_000);
		expect(nextDay.rows).toBeLessThan(20_000);
		expect(first.maxBytes).toBeLessThan(MAX_PUBLIC_BYTES);
	});
});
