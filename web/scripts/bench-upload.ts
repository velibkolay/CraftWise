// CPU time of the Worker's part of an upload (parse, validate, build rows, serialize for D1), in
// Node: npm run bench. The free plan allows 10 ms CPU per request; D1 work does not count.
import { priceRows } from "../src/upload";
import { validatePublic } from "../src/validate";

const now = Math.floor(Date.now() / 1000);
const today = Math.floor(now / 86400);
const house = "Realm|H";

// Worst case per request: scope items only (7 days, 7 raw points of 8 tiers), up to the 500 KB limit.
// kind "variants": last-only entries of random-suffix variants, 12 per item (#118).
function body(kind: "scope" | "last" | "variants"): string {
	const scope = kind === "scope";
	const items: Record<string, Record<string, unknown>> = {};
	const names: Record<string, string> = {};
	const itemInfo: Record<string, unknown> = {};
	let size = 0;
	let entries = 0;
	for (let i = 0; size < 470_000 && entries < 2000; i++) {
		const id = kind === "variants" ? `${100000 + Math.floor(i / 12)}:${1000 + (i % 12)}` : String(100000 + i);
		const min = 100 + i;
		const entry: Record<string, unknown> = { last: { t: now, min, qty: 50, listings: 4 } };
		if (scope) {
			entry.raw = Array.from({ length: 7 }, (_, k) => ({
				t: now - k * 8 * 3600,
				total: 300,
				listings: 30,
				m: min + 20,
				tiers: Array.from({ length: 8 }, (_, j) => ({ price: min + j * 7, qty: 5 })),
			}));
			entry.days = Object.fromEntries(
				Array.from({ length: 7 }, (_, d) => [String(today - d), { lo: min, typ: min + 10, hi: min + 60, qtyMax: 400, listMax: 40, n: 6 }]),
			);
		}
		items[id] = { [house]: entry };
		const base = id.split(":")[0]!;
		names[base] = `Item number ${i}`;
		itemInfo[base] = { q: 1, i: 130000 + i, c: 7, s: 5, t: now };
		size += JSON.stringify(entry).length + 90;
		entries++;
	}
	return JSON.stringify({
		v: 1,
		houses: { [house]: { realm: "Realm", kind: "faction", faction: "Horde", label: "Horde AH" } },
		names,
		itemInfo,
		items,
	});
}

for (const kind of ["scope", "last", "variants"] as const) {
	const text = body(kind);
	const times: number[] = [];
	for (let run = 0; run < 101; run++) {
		const start = performance.now();
		const data = validatePublic(JSON.parse(text), now);
		const rows = priceRows(data, () => 1, new Set());
		for (const list of Object.values(rows)) JSON.stringify(list);
		times.push(performance.now() - start);
	}
	times.sort((a, b) => a - b);
	const entries = Object.keys((JSON.parse(text) as { items: object }).items).length;
	console.log(
		`${kind.padEnd(9)} ${(text.length / 1000).toFixed(0)} KB, ${entries} entries: median ${times[50]!.toFixed(1)} ms, 90th ${times[90]!.toFixed(1)} ms, min ${times[0]!.toFixed(1)} ms`,
	);
}
