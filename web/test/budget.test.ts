// Measures rows written and database size for a realistic full scan (#90: about 10,000 items per
// house), uploaded the way the companion should: in requests of at most 2,000 price entries.
// The numbers are printed and documented in web/docs/api.md ("Budget").
import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { MAX_PUBLIC_BYTES } from "../src/limits";
import { body as shape, call, clearData, HORDE, makeToken, now, type Short } from "./helpers";

const DAY = 86400;
const ITEMS = 10_000;
const SCOPE = 1_500; // items with CraftWise history (own professions' reagents, products, recipes)
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
		const id = BASE_ID + i;
		if (opts.info) items[id] = { n: name(i), q: i % 5, i: 130000 + i, c: 7, s: i % 12 };
		const base = 100 + (i % 977);
		const min = base + (i % 2 ? opts.shift : 0); // half the items moved
		const entry: Record<string, unknown> = { item: String(id), house: HORDE, last: { t, min, qty: 20 + (i % 300), listings: 1 + (i % 40) } };
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
	const all = chunk(0, ITEMS, t, opts);
	const bodies: { prices: unknown[]; items: Record<string, unknown> }[] = [];
	let cur = { prices: [] as unknown[], items: {} as Record<string, unknown> };
	let bytes = 0;
	for (const p of all.prices) {
		const id = (p as { item: string }).item;
		const size = JSON.stringify(shape({ houses: {}, prices: [p] as Short["prices"] }).items).length +
			(all.items ? JSON.stringify(all.items[id]).length + 12 : 0);
		if (cur.prices.length >= CHUNK || bytes + size > 450_000) {
			bodies.push(cur);
			cur = { prices: [], items: {} };
			bytes = 0;
		}
		cur.prices.push(p);
		if (all.items) cur.items[id] = all.items[id];
		bytes += size;
	}
	bodies.push(cur);
	for (const [n, b] of bodies.entries()) {
		const short: Short = { prices: b.prices as Short["prices"] };
		if (all.items) short.items = b.items as Short["items"];
		if (n === 0) short.scans = [{ house: HORDE, t, kind: "full", items: SCOPE, lastOnly: ITEMS - SCOPE, source: "auctionator" }];
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
			"SELECT (SELECT count(*) FROM prices) prices, (SELECT count(*) FROM points) points, (SELECT count(*) FROM daily) daily, (SELECT count(*) FROM item_words) words",
		).first();
		console.log(
			JSON.stringify({ first, second, nextDay, bytes: { empty, afterFirst, afterSecond, afterNextDay }, counts, maxBody: MAX_PUBLIC_BYTES }, null, 1),
		);
		expect(first.rows).toBeLessThan(90_000);
		expect(second.rows).toBeLessThan(30_000);
		expect(nextDay.rows).toBeLessThan(30_000);
		expect(first.maxBytes).toBeLessThan(MAX_PUBLIC_BYTES);
	});
});
