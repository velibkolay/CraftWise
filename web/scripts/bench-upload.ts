// CPU time of the Worker's part of an upload (parse, validate, build rows, serialize for D1), in
// Node: npm run bench. The free plan allows 10 ms CPU per request; D1 work does not count.
import { priceRows } from "../src/upload";
import { validatePublic } from "../src/validate";

const now = Math.floor(Date.now() / 1000);
const today = Math.floor(now / 86400);
const house = "Realm|H";

// Worst case per request: scope items only (7 days, 7 raw points of 8 tiers), up to the 500 KB limit.
function body(scope: boolean): string {
	const prices: unknown[] = [];
	const items: Record<string, unknown> = {};
	let size = 0;
	for (let i = 0; size < 470_000 && prices.length < 2000; i++) {
		const id = String(100000 + i);
		const min = 100 + i;
		const entry: Record<string, unknown> = { item: id, house, last: { t: now, min, qty: 50, listings: 4 } };
		if (scope) {
			entry.raw = Array.from({ length: 7 }, (_, k) => ({
				t: now - k * 8 * 3600,
				total: 300,
				listings: 30,
				m: min + 20,
				tiers: Array.from({ length: 16 }, (_, j) => (j % 2 ? 5 : min + j * 7)),
			}));
			entry.days = Array.from({ length: 7 }, (_, d) => ({ day: today - d, lo: min, typ: min + 10, hi: min + 60, qtyMax: 400, listMax: 40, n: 6 }));
		}
		items[id] = { n: `Item number ${i}`, q: 1, i: 130000 + i, c: 7, s: 5 };
		size += JSON.stringify(entry).length + 60;
		prices.push(entry);
	}
	return JSON.stringify({ v: 1, houses: { [house]: { realm: "Realm", kind: "faction", faction: "Horde", label: "Horde AH" } }, items, prices });
}

for (const scope of [true, false]) {
	const text = body(scope);
	const times: number[] = [];
	for (let run = 0; run < 101; run++) {
		const start = performance.now();
		const data = validatePublic(JSON.parse(text), now);
		const rows = priceRows(data, () => 1);
		for (const list of Object.values(rows)) JSON.stringify(list);
		times.push(performance.now() - start);
	}
	times.sort((a, b) => a - b);
	const entries = (JSON.parse(text) as { prices: unknown[] }).prices.length;
	console.log(
		`${scope ? "scope items " : "last only   "} ${(text.length / 1000).toFixed(0)} KB, ${entries} entries: median ${times[50]!.toFixed(1)} ms, 90th ${times[90]!.toFixed(1)} ms, min ${times[0]!.toFixed(1)} ms`,
	);
}
