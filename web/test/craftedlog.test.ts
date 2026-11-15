// The Crafted table's logic (web/site/lib/craftedlog.ts, #266). All data is invented.
import { describe, expect, it } from "vitest";
import { dayIndex, durationText, localDay, type LogRow, parseRows, sortLines, summarize } from "../site/lib/craftedlog";

const A = "Realm-Aria";
const B = "Realm-Bram";
const r = (char: string, recipe: number, day: number, n: number, extra: Partial<LogRow> = {}): LogRow => ({ char, recipe, day, n, items: null, profit: null, known: null, active: null, ...extra });
const meta = (id: number) => ({ name: id === 1 ? "Bolt" : id === 2 ? "Blade" : `Recipe ${id}`, profession: id === 1 ? "Tailoring" : "Blacksmithing" });
const TODAY = 20261115;

describe("craft log rows", () => {
	it("reads the API's arrays and drops what is malformed", () => {
		expect(parseRows([[A, 1, 20261115, 3, 3, 120, 3, 12.5], [A, 2, 20261114, 1, null, null, null, null], [A, "x", 1, 1], "nope", [5, 1, 1, 1]])).toEqual([
			{ char: A, recipe: 1, day: 20261115, n: 3, items: 3, profit: 120, known: 3, active: 12.5 },
			{ char: A, recipe: 2, day: 20261114, n: 1, items: null, profit: null, known: null, active: null },
		]);
		expect(parseRows(null)).toEqual([]);
	});

	it("counts days the way the addon names them", () => {
		expect(localDay(new Date(2026, 10, 15, 23, 59))).toBe(20261115);
		expect(dayIndex(20261115) - dayIndex(20261108)).toBe(7);
		expect(dayIndex(20270101) - dayIndex(20261231)).toBe(1);
	});
});

describe("summaries", () => {
	const rows = [
		r(A, 1, 20261115, 4, { profit: 400, known: 4, active: 60 }), // today
		r(A, 1, 20261110, 6, { profit: 300, known: 6, active: 120 }), // within 7 days
		r(A, 1, 20261108, 10, { profit: 1000, known: 10 }), // 7 days ago: outside (today and the 6 before)
		r(B, 1, 20261115, 2, { profit: -50, known: 2, active: 30 }), // the other character
		r(A, 2, 20261114, 5), // an old day: no profit, no time
		r(A, 2, 20261115, 3, { profit: 90, known: 2 }), // one craft without a price
	];

	it("sums today, the last 7 days (today and the six before) and all time per recipe", () => {
		const lines = summarize(rows, TODAY, null, meta);
		const bolt = lines.find((l) => l.recipe === 1)!;
		expect([bolt.today.n, bolt.week.n, bolt.all.n]).toEqual([6, 12, 22]);
		expect([bolt.today.profit, bolt.week.profit, bolt.all.profit]).toEqual([350, 650, 1650]);
		expect(bolt.name).toBe("Bolt");
	});

	it("filters by character", () => {
		const bolt = summarize(rows, TODAY, A, meta).find((l) => l.recipe === 1)!;
		expect(bolt.today).toEqual({ n: 4, profit: 400, partial: false });
		expect(summarize(rows, TODAY, "Realm-Nobody", meta)).toEqual([]);
	});

	it("shows no profit for a period without one, and marks a figure that misses crafts", () => {
		const blade = summarize(rows, TODAY, null, meta).find((l) => l.recipe === 2)!;
		expect(blade.week.profit).toBe(90); // only the day that has one
		expect(blade.week.partial).toBe(true); // 8 crafts, 2 priced
		expect(summarize([r(A, 2, 20261114, 5)], TODAY, null, meta)[0]!.all).toEqual({ n: 5, profit: null, partial: false });
		expect(summarize(rows, TODAY, A, meta).find((l) => l.recipe === 2)!.today).toEqual({ n: 3, profit: 90, partial: true });
	});

	it("gives the active time and gold per active hour only where both are known", () => {
		const lines = summarize(rows, TODAY, null, meta);
		const bolt = lines.find((l) => l.recipe === 1)!;
		expect(bolt.active).toBe(210);
		// (400 + 300 - 50) copper over 210 s, per hour
		expect(bolt.perHour).toBe(Math.round((650 / 210) * 3600));
		const blade = lines.find((l) => l.recipe === 2)!;
		expect(blade.active).toBeNull();
		expect(blade.perHour).toBeNull();
		// time without profit: the time shows, the gold per hour does not
		const noProfit = summarize([r(A, 3, 20261115, 2, { active: 40 })], TODAY, null, meta)[0]!;
		expect([noProfit.active, noProfit.perHour]).toEqual([40, null]);
	});
});

describe("sorting", () => {
	const lines = summarize(
		[r(A, 1, 20261115, 4, { profit: 400, known: 4 }), r(A, 2, 20261115, 9), r(A, 3, 20261115, 1, { profit: 900, known: 1 })],
		TODAY,
		null,
		meta,
	);
	const order = (k: Parameters<typeof sortLines>[1], desc: boolean) => sortLines(lines, k, desc).map((l) => l.recipe);

	it("sorts counts and profits, unknowns last in both directions", () => {
		expect(order("today", true)).toEqual([2, 1, 3]);
		expect(order("pToday", true)).toEqual([3, 1, 2]);
		expect(order("pToday", false)).toEqual([1, 3, 2]);
		expect(order("perHour", false)).toEqual([2, 1, 3]); // nobody has a time: by name (Blade, Bolt, Recipe 3)
	});

	it("sorts by name and profession", () => {
		expect(order("name", false)).toEqual([2, 1, 3]);
		expect(order("name", true)).toEqual([3, 1, 2]);
		expect(order("profession", false)).toEqual([2, 3, 1]);
	});
});

describe("duration", () => {
	it("reads as seconds, minutes, hours", () => {
		expect([durationText(45), durationText(125), durationText(3900)]).toEqual(["45 s", "2 min", "1 h 05 min"]);
	});
});
