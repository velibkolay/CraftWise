// The site's pure formatting (web/site/lib/format.ts): money, change, sparkline, listings, axis.
import { describe, expect, it } from "vitest";
import {
	age,
	buyCost,
	changeBetween,
	changeClass,
	changes,
	className,
	freshness,
	humanize,
	money,
	moneyAxis,
	moneyPadded,
	pct,
	pctMarked,
	pctSpoken,
	qualityClass,
	sparkPath,
	sparkValues,
	subclassName,
	ticks,
} from "../site/lib/format";

const day = (d: number, lo: number | null, typ: number | null = null) => ({ day: d, lo, typ, hi: lo, qtyMax: 1 });

describe("money", () => {
	it("splits copper into coins without zero padding, as the client does", () => {
		expect(money(11275).parts).toEqual([
			{ v: "1", k: "mg" },
			{ v: "12", k: "ms" },
			{ v: "75", k: "mc" },
		]);
		expect(money(10300).parts).toEqual([
			{ v: "1", k: "mg" },
			{ v: "3", k: "ms" },
		]);
		expect(money(300).parts).toEqual([{ v: "3", k: "ms" }]);
		expect(money(0).parts).toEqual([{ v: "0", k: "mc" }]);
		expect(money(12_345_678).parts[0]).toEqual({ v: "1,234", k: "mg" });
	});

	it("has spoken and short text", () => {
		expect(money(11275).label).toBe("1 gold 12 silver 75 copper");
		expect(money(10005).label).toBe("1 gold 5 copper");
		expect(money(0).label).toBe("0 copper");
		expect(money(10908.4).short).toBe("1g 9s 8c");
		expect(moneyAxis(14000)).toBe("1g 40s");
		expect(moneyAxis(9050)).toBe("90s 50c");
		expect(moneyAxis(45)).toBe("45c");
	});
});

describe("money, Velikopter skin", () => {
	it("pads silver and copper once a larger coin shows and drops empty leading coins", () => {
		expect(moneyPadded(10840).parts).toEqual([
			{ v: "1", k: "mg" },
			{ v: "08", k: "ms" },
			{ v: "40", k: "mc" },
		]);
		expect(moneyPadded(820000).short).toBe("82g 00s 00c");
		expect(moneyPadded(9805).short).toBe("98s 05c");
		expect(moneyPadded(6).short).toBe("6c");
		expect(moneyPadded(0).short).toBe("0c");
		expect(moneyPadded(12_345_678).parts[0]).toEqual({ v: "1,234", k: "mg" });
	});
	it("keeps the spoken label of the client format", () => {
		expect(moneyPadded(10840).label).toBe("1 gold 8 silver 40 copper");
		expect(moneyPadded(820000).label).toBe("82 gold");
	});
	it("pads the axis labels too", () => {
		expect(moneyAxis(10500, true)).toBe("1g 05s");
		expect(moneyAxis(10500)).toBe("1g 5s");
	});
});

describe("change", () => {
	it("formats a fraction as a signed percentage", () => {
		expect(pct(0.039)).toBe("+3.9%");
		expect(pct(-0.02)).toBe("-2.0%");
		expect(pct(0.0004)).toBe("0.0%");
		expect(pct(null)).toBe("–");
		expect(changeClass(0.039)).toBe("up");
		expect(changeClass(-0.2)).toBe("dn");
		expect(changeClass(0.0001)).toBe("flat");
		expect(changeClass(null)).toBe("flat");
		expect(pctSpoken(-0.145)).toBe("down 14.5 percent");
	});

	it("compares typical prices when both days have one, else lowest prices", () => {
		expect(changeBetween(day(1, 90, 100), day(2, 80, 110))).toBeCloseTo(0.1);
		expect(changeBetween(day(1, 90, 100), day(2, 81, null))).toBeCloseTo(-0.1);
		expect(changeBetween(day(1, null, null), day(2, 81, null))).toBeNull();
		expect(changeBetween(undefined, day(2, 81))).toBeNull();
	});

	it("takes 24 h and 7 d from the latest day, and nothing when it is old", () => {
		const today = 20768;
		const days = [day(today - 7, 100, 100), day(today - 1, 120, 120), day(today, 150, 150)];
		const c = changes(days, today);
		expect(c.c24).toBeCloseTo(0.25);
		expect(c.c7).toBeCloseTo(0.5);
		expect(changes([day(today - 1, 100), day(today - 2, 50)], today).c24).toBeCloseTo(1);
		expect(changes([day(today - 2, 100), day(today - 3, 50)], today)).toEqual({ c24: null, c7: null });
		expect(changes([day(today, 100)], today)).toEqual({ c24: null, c7: null });
	});
});

describe("change, Velikopter skin", () => {
	it("writes an arrow, a sign, a real minus and a thin space before the percent sign", () => {
		expect(pctMarked(0.039)).toBe("▲ +3.9\u2009%");
		expect(pctMarked(-0.02)).toBe("▼ \u22122.0\u2009%");
		expect(pctMarked(0.0001)).toBe("0.0\u2009%");
		expect(pctMarked(null)).toBe("–");
	});
});

describe("sparkline", () => {
	it("gives one value per day, typical prices when two days have one", () => {
		const today = 100;
		expect(sparkValues([day(94, 10, 12), day(100, 20, 22)], today)).toEqual([12, null, null, null, null, null, 22]);
		expect(sparkValues([day(94, 10, 12), day(100, 20)], today)).toEqual([10, null, null, null, null, null, 20]);
		expect(sparkValues([day(90, 10)], today)).toEqual([null, null, null, null, null, null, null]);
	});

	it("scales into the box, top is the highest value", () => {
		expect(sparkPath([0, 10], 96, 20, 2)).toBe("M2,18L94,2");
		expect(sparkPath([5, 5, 5], 96, 20, 2)).toBe("M2,10L48,10L94,10");
		expect(sparkPath([10, 20, 15], 100, 20, 0)).toBe("M0,20L50,0L100,10");
	});

	it("breaks the line at gaps and draws a lone point as a tick", () => {
		expect(sparkPath([0, null, 10, 5], 92, 20, 2)).toBe("M0.5,18L3.5,18M60.7,2L90,10");
		expect(sparkPath([null, null], 96, 20)).toBe("");
	});
});

describe("listings and axis", () => {
	it("averages the cheapest units, or says the tiers are too thin", () => {
		const tiers = [
			{ price: 100, qty: 20 },
			{ price: 200, qty: 80 },
		];
		expect(buyCost(tiers, 20)).toBe(100);
		expect(buyCost(tiers, 100)).toBe(180);
		expect(buyCost(tiers, 101)).toBeNull();
	});

	it("puts ticks on round coin values", () => {
		expect(ticks(9000, 14500, 5)).toEqual([9000, 10000, 11000, 12000, 13000, 14000]);
		expect(ticks(33, 55, 4)).toEqual([35, 40, 45, 50, 55]);
		expect(ticks(40, 40)).toEqual([40]);
	});
});

describe("names and time", () => {
	it("turns client enum identifiers into words and says when there is no name", () => {
		expect(humanize("ItemEnhancement")).toBe("Item Enhancement");
		expect(humanize("WoWToken")).toBe("WoW Token");
		expect(className(7)).toBe("Tradegoods");
		expect(className(null)).toBe("No item info yet");
		expect(subclassName(0, 1)).toBe("Potion");
		expect(subclassName(7, 9)).toBe("Subclass 9");
		expect(qualityClass(2)).toBe("q-uncommon");
		expect(qualityClass(null)).toBe("q-common");
	});

	it("says how old a scan is and how fresh it still is", () => {
		expect(age(30)).toBe("just now");
		expect(age(600)).toBe("10 min ago");
		expect(age(7200)).toBe("2 h ago");
		expect(age(4 * 86400)).toBe("4 days ago");
		expect(freshness(0)).toBe(1);
		expect(freshness(43200)).toBe(0.5);
		expect(freshness(100000)).toBe(0);
	});
});
