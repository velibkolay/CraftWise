// The fishing page's data shaping (web/site/lib/fishing.ts, #128): item lists, unit values with today's prices,
// own catches against the reference, value per hour, ranking. All zones, items, counts and prices are invented.
import { describe, expect, it } from "vitest";
import {
	type AhQuote,
	ahQuote,
	compareOf,
	fishingItems,
	fishingPage,
	parseItems,
	parseRef,
	parseShares,
	quotesOf,
	sortPools,
	sortRows,
	unitNow,
	unitsText,
	valueLines,
	wilson,
	type ZoneRow,
} from "../site/lib/fishing";

const T = 1_800_000_000;
const SNAPPER = 9101;
const EEL = 9102;
const TRUNK = 9103;
const PEARL = 9104;

const q = (entries: [number, AhQuote][]) => new Map(entries);

describe("item lists", () => {
	it("reads units, ranges, exponents, unpriced, containers and vendor prices", () => {
		expect(parseItems(`${EEL} 0.3-0.9 100; ${TRUNK} 0.1 140-180 c; ${SNAPPER} 1e-05 ? v2; broken; 0 1 1`)).toEqual([
			{ id: EEL, units: 0.3, unitsHigh: 0.9, value: 100, valueHigh: 100, contents: false, vendor: null },
			{ id: TRUNK, units: 0.1, unitsHigh: 0.1, value: 140, valueHigh: 180, contents: true, vendor: null },
			{ id: SNAPPER, units: 0.00001, unitsHigh: 0.00001, value: null, valueHigh: null, contents: false, vendor: 2 },
		]);
		expect(parseItems(undefined)).toBeNull();
		expect(parseItems("")).toEqual([]);
	});

	it("reads share lists (hits and units) and reference lists (count, own outof, stack)", () => {
		expect(parseShares(`${SNAPPER} 13 13 10 v2; ${EEL} 7 10 100`)).toEqual([
			{ id: SNAPPER, hits: 13, units: 13, value: 10, valueHigh: 10, contents: false, vendor: 2 },
			{ id: EEL, hits: 7, units: 10, value: 100, valueHigh: 100, contents: false, vendor: null },
		]);
		expect(parseRef(`${EEL} 60 1-3 100; ${PEARL} 4/20 1 ?`)).toEqual([
			{ id: EEL, count: 60, outof: null, stack: [1, 3], value: 100, valueHigh: 100, contents: false, vendor: null },
			{ id: PEARL, count: 4, outof: 20, stack: [1, 1], value: null, valueHigh: null, contents: false, vendor: null },
		]);
	});
});

describe("unit values now", () => {
	const line = { id: EEL, units: 1, unitsHigh: 1, value: 100, valueHigh: 100, contents: false, vendor: 30 };

	it("takes the typical price, else the current lowest while listed", () => {
		expect(ahQuote({ typical: { status: "ok", price: 200, days: 5 }, current: null })).toEqual({ copper: 200, basis: "typical" });
		expect(ahQuote({ typical: { status: "too_little_history", days: 1 }, current: { t: T, min: 80, qty: 5, listings: 1, off: null, listed: true } })).toEqual({ copper: 80, basis: "current" });
		expect(ahQuote({ typical: { status: "too_little_history", days: 1 }, current: { t: T, min: 80, qty: 5, listings: 1, off: null, listed: false } })).toBeNull();
	});

	it("picks like ns.GetSellValue: AH after the 5% cut unless the vendor pays more", () => {
		expect(unitNow(line, { copper: 200, basis: "typical" })).toEqual({ copper: 190, high: 190, source: "ah", basis: "typical" });
		expect(unitNow(line, { copper: 20, basis: "current" })).toEqual({ copper: 30, high: 30, source: "vendor", basis: null });
	});

	it("keeps containers and, without a Horde AH price today, the snapshot's value", () => {
		expect(unitNow({ ...line, contents: true, value: 140, valueHigh: 180 }, { copper: 999, basis: "typical" })).toEqual({ copper: 140, high: 180, source: "contents", basis: null });
		expect(unitNow(line, null)).toEqual({ copper: 100, high: 100, source: "snapshot", basis: null });
		expect(unitNow({ ...line, value: null }, null)).toEqual({ copper: 30, high: 30, source: "vendor", basis: null });
		expect(unitNow({ ...line, value: null, vendor: 0 }, null)).toBeNull();
	});

	it("values a list per catch: counts over the catches, units per catch as they are", () => {
		const quotes = q([[EEL, { copper: 200, basis: "typical" }]]);
		const counts = valueLines(parseItems(`${EEL} 3 100; ${PEARL} 1 ?`)!, quotes, 4);
		expect(counts.perCatch).toBe(Math.round((3 * 190) / 4));
		expect(counts.unpriced).toBe(1);
		expect(counts.lines[0]!.id).toBe(EEL);
		const perCatch = valueLines(parseItems(`${EEL} 0.3-0.9 100`)!, quotes, 1);
		expect([perCatch.perCatch, perCatch.perCatchHigh]).toEqual([57, 171]);
	});

	it("reads quotes from the browse answer", () => {
		const m = quotesOf([
			{ id: EEL, typical: { status: "ok", price: 200, days: 5 }, current: null },
			{ id: PEARL, typical: { status: "no_data", days: 0 }, current: null },
		]);
		expect([...m.keys()]).toEqual([EEL]);
	});
});

describe("own catches against the reference", () => {
	it("gives a 95% Wilson interval", () => {
		const [lo, hi] = wilson(7, 17);
		expect(lo).toBeCloseTo(0.2161, 3);
		expect(hi).toBeCloseTo(0.6397, 3);
		expect(wilson(0, 100)[0]).toBe(0);
		expect(wilson(0, 0)).toEqual([0, 1]);
	});

	it("flags an item when the reference's share lies outside the own interval", () => {
		const c = compareOf(parseShares(`${SNAPPER} 90 90 10; ${EEL} 10 10 100`), 100, parseRef(`${SNAPPER} 120 1 10; ${EEL} 60 1-3 100; ${TRUNK} 20 1 140-180 c`), 200, new Map());
		const by = new Map(c.lines.map((l) => [l.id, l]));
		expect(by.get(SNAPPER)!.share).toBe(0.9);
		expect(by.get(SNAPPER)!.refShare).toBe(0.6);
		expect(by.get(SNAPPER)!.outside).toBe(true);
		expect(by.get(EEL)!.diff).toBeCloseTo(-0.2);
		expect(by.get(TRUNK)!.hits).toBe(0); // never caught: 0 of 100, the reference's 10% is outside
		expect(by.get(TRUNK)!.outside).toBe(true);
		expect(c.outside).toBe(3);
		// value per catch from each side, with the snapshot's unit values (no prices today)
		expect(c.own!.perCatch).toBe(Math.round((90 * 10 + 10 * 100) / 100));
		expect([c.ref!.perCatch, c.ref!.perCatchHigh]).toEqual([Math.round(0.6 * 10 + 0.3 * 100 + 0.1 * 140), Math.round(0.6 * 10 + 0.9 * 100 + 0.1 * 180)]);
	});

	it("doesn't flag what the own interval still covers", () => {
		const c = compareOf(parseShares(`${SNAPPER} 7 7 10`), 10, parseRef(`${SNAPPER} 60 1 10`), 100, new Map());
		expect(c.lines[0]!.outside).toBe(false);
	});
});

function doc(data: unknown) {
	return { t: T, data };
}

// An invented fishing document as the companion uploads it (snapshot.fishing with fishingZones).
function fishingDoc(extra: Record<string, unknown> = {}) {
	return doc({
		days: 90,
		catches: 260,
		sessionGapMinutes: 5,
		findFish: { spellID: 43308, known: true, tracking: false },
		spots: [
			{ zone: "Testwater Bay", sub: "Shoal", water: "open", n: 200, perCatch: 50, perHour: 9000, timed: 190, minutes: 60, items: `${SNAPPER} 150 10 v2; ${EEL} 60 100`, top: `${SNAPPER} Test Snapper 150/210` },
			{ zone: "Dull Pond", sub: "", water: "pool", pool: "Test School", obj: 7001, n: 6, perCatch: 300, perHour: 60000, timed: 5, minutes: 1, items: `${EEL} 18 100` },
		],
		waters: [{ water: "open", n: 200, perCatch: 50, timed: 190, minutes: 60, items: `${SNAPPER} 150 10 v2; ${EEL} 60 100` }],
		pools: [{ obj: 7001, name: "Test School", visits: 2, perVisit: "2-4, avg 3", catches: 6, perCatch: 300, items: `${EEL} 18 100` }],
		fishingZones: {
			reference: true,
			ownMin: 50,
			zones: [
				{ zone: "Far Lagoon", source: "ref", n: 5000, perCatch: 80, items: `${EEL} 0.8 100` },
				{ zone: "Testwater Bay", source: "own", n: 200, perCatch: 50, perHour: 10000, timed: 190, minutes: 60, items: `${SNAPPER} 0.75 10 v2; ${EEL} 0.3 100` },
				{ zone: "Dull Pond", source: "ref", n: 1000, perCatch: 20, items: `${SNAPPER} 0.99 10 v2` },
			],
			compare: [
				{ zone: "Testwater Bay", n: 200, timed: 190, minutes: 60, own: `${SNAPPER} 150 150 10 v2; ${EEL} 50 60 100`, refN: 400, ref: `${SNAPPER} 300 1 10 v2; ${EEL} 100 1 100` },
				{ zone: "Dull Pond", n: 6, timed: 5, minutes: 1, own: `${EEL} 6 18 100`, refN: 1000, ref: `${SNAPPER} 990 1 10 v2`, waters: [{ water: "pool", obj: 7001, name: "Test School", n: 6, own: `${EEL} 6 18 100` }] },
			],
			...extra,
		},
	});
}

const snapshot = doc({ professions: [{ name: "Fishing", kind: "secondary", skill: 210, max: 225 }] });

describe("the page", () => {
	const eel = (copper: number): [number, AhQuote] => [EEL, { copper, basis: "typical" }];

	it("ranks own data first from ownMin catches on, the reference as comparison", () => {
		const page = fishingPage(fishingDoc(), snapshot, q([eel(200)]))!;
		expect(page.skill).toEqual({ skill: 210, max: 225 });
		expect(page.zones.map((z) => z.zone)).toEqual(["Far Lagoon", "Testwater Bay", "Dull Pond"]);
		const bay = page.zones[1] as ZoneRow;
		expect(bay.source).toBe("own");
		expect(bay.n).toBe(200);
		// own: (150 x 10 + 60 x 190) / 200; the reference: 0.75 x 10 + 0.25 x 190
		expect(bay.perCatch).toBe(Math.round((150 * 10 + 60 * 190) / 200));
		expect(bay.other!.source).toBe("ref");
		expect(bay.other!.perCatch).toBe(Math.round(0.75 * 10 + 0.25 * 190));
		// per hour: 190 timed catches in 60 minutes x the value per catch now
		expect(bay.perHour).toBe(Math.round(190 * bay.perCatch!));
		expect(bay.snap.perCatch).toBe(50);
		expect(bay.compare!.outside).toBe(0); // 150 and 50 of 200 match the reference's 75% and 25%
	});

	it("takes a zone's sides from the comparison when the ranking leaves its item list out", () => {
		const full = fishingPage(fishingDoc(), snapshot, q([eel(200)]))!;
		const d = fishingDoc();
		const zones = ((d.data as { fishingZones: { zones: Record<string, unknown>[] } }).fishingZones.zones);
		for (const z of zones) if (z.zone !== "Far Lagoon") delete z.items;
		const page = fishingPage(d, snapshot, q([eel(200)]))!;
		for (const name of ["Testwater Bay", "Dull Pond"]) {
			const a = full.zones.find((z) => z.zone === name)!;
			const b = page.zones.find((z) => z.zone === name)!;
			expect([b.source, b.perCatch, b.perHour, b.other?.perCatch]).toEqual([a.source, a.perCatch, a.perHour, a.other?.perCatch]);
			expect(b.revalued).toBe(true);
		}
	});

	it("keeps the reference primary below ownMin and shows no value per hour from a few timed catches", () => {
		const page = fishingPage(fishingDoc(), snapshot, q([eel(200)]))!;
		const pond = page.zones[2] as ZoneRow;
		expect(pond.source).toBe("ref");
		expect(pond.perCatch).toBe(Math.round(0.99 * 10));
		expect(pond.other!.source).toBe("own");
		expect(pond.other!.n).toBe(6);
		expect(pond.perHour).toBeNull();
		expect(pond.timedTooFew).toBe(true);
		expect(pond.waters).toHaveLength(1);
		expect(pond.waters[0]!.small).toBe(true);
		const spot = page.spots[1]!;
		expect(spot.small).toBe(true);
		expect(spot.perHour).toBeNull();
		expect(spot.timedTooFew).toBe(true);
	});

	it("ranks by value per hour or per catch, small samples last", () => {
		const page = fishingPage(fishingDoc(), snapshot, q([eel(200)]))!;
		expect(sortRows(page.zones, "hour").map((z) => z.zone)).toEqual(["Testwater Bay", "Far Lagoon", "Dull Pond"]);
		expect(sortRows(page.zones, "catch").map((z) => z.zone)).toEqual(["Far Lagoon", "Testwater Bay", "Dull Pond"]);
		expect(sortRows(page.spots, "catch").map((s) => s.zone)).toEqual(["Testwater Bay", "Dull Pond"]);
	});

	it("values pools per visit: catches per visit x value per catch now", () => {
		const page = fishingPage(fishingDoc(), snapshot, q([eel(200)]))!;
		const pool = sortPools(page.pools)[0]!;
		expect([pool.min, pool.max, pool.avg]).toEqual([2, 4, 3]);
		expect(pool.perCatch).toBe(Math.round((18 * 190) / 6));
		expect(pool.perVisit).toBe(3 * pool.perCatch!);
		expect(pool.small).toBe(true);
	});

	it("lists the items to price and the names the spots carry", () => {
		const { ids, names } = fishingItems(fishingDoc(), snapshot);
		expect(ids).toEqual([SNAPPER, EEL]);
		expect(names.get(SNAPPER)).toBe("Test Snapper");
	});

	it("falls back to the snapshot's figures when the upload has no item lists", () => {
		const old = doc({
			days: 90,
			spots: [{ zone: "Testwater Bay", sub: "", water: "open", n: 80, perCatch: 50, perHour: 9000 }],
			fishingZones: { ownMin: 50, zones: [{ zone: "Testwater Bay", source: "own", n: 80, perCatch: 50, perHour: 9000 }] },
		});
		const page = fishingPage(old, null, q([eel(200)]))!;
		expect(page.itemLists).toBe(false);
		expect(page.zones[0]!.perCatch).toBe(50);
		expect(page.zones[0]!.perHour).toBe(9000);
		expect(page.zones[0]!.revalued).toBe(false);
		expect(page.spots[0]!.perHour).toBe(9000);
		expect(fishingPage(null, null, new Map())).toBeNull();
	});

	it("says how many of an item a catch brings", () => {
		expect(unitsText({ id: 1, units: 0.3, unitsHigh: 0.3, value: 1, valueHigh: 1, contents: false, vendor: null }, { perCountUnits: false, n: 1 })).toBe("30% of catches");
		expect(unitsText({ id: 1, units: 0.3, unitsHigh: 0.9, value: 1, valueHigh: 1, contents: false, vendor: null }, { perCountUnits: false, n: 1 })).toBe("0.3–0.9 per catch");
		expect(unitsText({ id: 1, units: 150, unitsHigh: 150, value: 1, valueHigh: 1, contents: false, vendor: null }, { perCountUnits: true, n: 200 })).toBe("150 of 200 catches");
	});
});
