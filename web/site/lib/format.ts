// Pure formatting and data shaping for the price site (#97). No DOM here: the Worker tests import it.
import { ITEM_CLASS, ITEM_QUALITY, ITEM_SUBCLASS } from "./enums";

export const DAY = 86400;

// ---- Money (copper) ------------------------------------------------------------------------

export type CoinKind = "mg" | "ms" | "mc";
export interface Money {
	parts: { v: string; k: CoinKind }[];
	label: string; // spoken text: "1 gold 12 silver 75 copper"
	short: string; // plain text: "1g 12s 75c"
}

// As the client's money frames: no zero padding, empty coins left out, 0 is "0 copper".
export function money(copper: number): Money {
	const c = Math.max(0, Math.round(copper));
	const g = Math.floor(c / 10000);
	const s = Math.floor(c / 100) % 100;
	const k = c % 100;
	const parts: Money["parts"] = [];
	const words: string[] = [];
	const short: string[] = [];
	if (g) {
		parts.push({ v: g.toLocaleString("en-US"), k: "mg" });
		words.push(`${g.toLocaleString("en-US")} gold`);
		short.push(`${g.toLocaleString("en-US")}g`);
	}
	if (s) {
		parts.push({ v: String(s), k: "ms" });
		words.push(`${s} silver`);
		short.push(`${s}s`);
	}
	if (k || (!g && !s)) {
		parts.push({ v: String(k), k: "mc" });
		words.push(`${k} copper`);
		short.push(`${k}c`);
	}
	return { parts, label: words.join(" "), short: short.join(" ") };
}

// Axis labels: the two largest coins, "1g 40s", "90s", "45c".
export function moneyAxis(copper: number): string {
	return money(copper).short.split(" ").slice(0, 2).join(" ");
}

// ---- Change ---------------------------------------------------------------------------------

export type ChangeClass = "up" | "dn" | "flat";

// A fraction (0.039 = +3.9 %) as the table shows it; below 0.05 % is "0.0%".
export function pct(change: number | null): string {
	if (change === null || !Number.isFinite(change)) return "–";
	const p = change * 100;
	if (Math.abs(p) < 0.05) return "0.0%";
	return `${p > 0 ? "+" : "-"}${Math.abs(p).toFixed(1)}%`;
}

export function changeClass(change: number | null): ChangeClass {
	if (change === null || !Number.isFinite(change) || Math.abs(change * 100) < 0.05) return "flat";
	return change > 0 ? "up" : "dn";
}

export function pctSpoken(change: number | null): string {
	if (change === null || !Number.isFinite(change)) return "no data";
	const p = change * 100;
	if (Math.abs(p) < 0.05) return "unchanged";
	return `${p > 0 ? "up" : "down"} ${Math.abs(p).toFixed(1)} percent`;
}

// ---- Daily rows ------------------------------------------------------------------------------

export interface DayRow {
	day: number;
	lo: number | null;
	typ: number | null;
	hi: number | null;
	qtyMax: number | null;
}

// Change from day a to day b. Like with like: the typical prices when both days have one (CraftWise
// history), otherwise the lowest prices (items outside the scope only have those).
export function changeBetween(a: DayRow | undefined, b: DayRow | undefined): number | null {
	if (!a || !b) return null;
	if (a.typ !== null && b.typ !== null && a.typ > 0) return (b.typ - a.typ) / a.typ;
	if (a.lo !== null && b.lo !== null && a.lo > 0) return (b.lo - a.lo) / a.lo;
	return null;
}

// 24 h and 7 d change: the latest day with a price against the day before and the same day a week
// earlier. Nothing when the latest day is older than yesterday or a day is missing.
export function changes(days: DayRow[], today: number): { c24: number | null; c7: number | null } {
	const byDay = new Map(days.filter((d) => d.lo !== null || d.typ !== null).map((d) => [d.day, d]));
	const latest = Math.max(-Infinity, ...byDay.keys());
	if (latest < today - 1) return { c24: null, c7: null };
	const last = byDay.get(latest);
	return { c24: changeBetween(byDay.get(latest - 1), last), c7: changeBetween(byDay.get(latest - 7), last) };
}

// One value per day of the last `n` days (today last), null where there is no row. The typical
// price when at least two of the days have one, else the lowest price, so one line never mixes both.
export function sparkValues(days: DayRow[], today: number, n = 7): (number | null)[] {
	const byDay = new Map(days.map((d) => [d.day, d]));
	const slots = Array.from({ length: n }, (_, i) => byDay.get(today - (n - 1) + i));
	const useTyp = slots.filter((d) => d && d.typ !== null).length >= 2;
	return slots.map((d) => (d ? (useTyp ? d.typ : d.lo) : null));
}

// SVG path for a sparkline in a w x h box with `pad` px inside: one slot per value, gaps break the
// line, a lone point becomes a short tick, a flat series sits in the middle.
export function sparkPath(values: (number | null)[], w: number, h: number, pad = 2): string {
	const nums = values.filter((v): v is number => v !== null);
	if (!nums.length) return "";
	const lo = Math.min(...nums);
	const hi = Math.max(...nums);
	const step = values.length > 1 ? (w - 2 * pad) / (values.length - 1) : 0;
	const x = (i: number) => pad + i * step;
	const y = (v: number) => (hi === lo ? h / 2 : h - pad - ((v - lo) / (hi - lo)) * (h - 2 * pad));
	const f = (n: number) => String(Math.round(n * 10) / 10);
	let d = "";
	let run: [number, number][] = [];
	const flush = () => {
		if (run.length === 1) {
			const [px, py] = run[0]!;
			d += `M${f(Math.max(0, px - 1.5))},${f(py)}L${f(Math.min(w, px + 1.5))},${f(py)}`;
		} else if (run.length > 1) {
			d += run.map(([px, py], i) => `${i ? "L" : "M"}${f(px)},${f(py)}`).join("");
		}
		run = [];
	};
	values.forEach((v, i) => {
		if (v === null) flush();
		else run.push([x(i), y(v)]);
	});
	flush();
	return d;
}

// ---- Time --------------------------------------------------------------------------------------

export function age(seconds: number): string {
	const s = Math.max(0, seconds);
	if (s < 90) return "just now";
	if (s < 3600) return `${Math.round(s / 60)} min ago`;
	if (s < 48 * 3600) return `${Math.round(s / 3600)} h ago`;
	return `${Math.round(s / DAY)} days ago`;
}

// Status bar fill: full right after a scan, empty at `staleAfter`.
export function freshness(seconds: number, staleAfter = DAY): number {
	return Math.min(1, Math.max(0, 1 - seconds / staleAfter));
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export function dayLabel(day: number, long = false): string {
	const d = new Date(day * DAY * 1000);
	const m = MONTHS[d.getUTCMonth()]!;
	return `${long ? m : m.slice(0, 3)} ${d.getUTCDate()}`;
}

export function timeLabel(t: number): string {
	const d = new Date(t * 1000);
	return `${dayLabel(Math.floor(t / DAY))}, ${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")} UTC`;
}

// ---- Item classes and qualities (client enums, see enums.ts) -------------------------------------

// "ItemEnhancement" -> "Item Enhancement", "WoWToken" -> "WoW Token".
export function humanize(id: string): string {
	return id.replace(/([a-z])([A-Z][a-z])/g, "$1 $2").replace(/([A-Z])([A-Z][a-z])/g, "$1 $2");
}

export function className(cls: number | null): string {
	if (cls === null) return "No item info yet";
	const n = ITEM_CLASS[cls];
	return n ? humanize(n) : `Class ${cls}`;
}

export function subclassName(cls: number | null, sub: number | null): string {
	if (cls === null || sub === null) return "No item info yet";
	const n = ITEM_SUBCLASS[cls]?.[sub];
	return n ? humanize(n) : `Subclass ${sub}`;
}

export function qualityName(q: number | null): string | null {
	return q === null ? null : (ITEM_QUALITY[q] ?? null);
}

// CSS class for the item name colour.
export function qualityClass(q: number | null): string {
	const n = qualityName(q);
	return n ? `q-${n.toLowerCase()}` : "q-common";
}

// ---- Listings --------------------------------------------------------------------------------

export interface Tier {
	price: number;
	qty: number;
}

// Average unit price of buying `n` units from the cheapest tiers; null when the tiers hold fewer.
export function buyCost(tiers: Tier[], n: number): number | null {
	let left = n;
	let cost = 0;
	for (const t of tiers) {
		const take = Math.min(left, t.qty);
		cost += take * t.price;
		left -= take;
		if (left === 0) return cost / n;
	}
	return null;
}

// Chart axis: about `count` round steps (1, 2, 5 x 10^k copper) covering lo..hi.
export function ticks(lo: number, hi: number, count = 5): number[] {
	if (!(hi > lo)) {
		const v = Math.max(0, lo);
		return [v];
	}
	const range = hi - lo;
	const mag = 10 ** Math.floor(Math.log10(range / count));
	// The finest round step that gives at most count + 1 intervals.
	const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => range / s <= count + 1) ?? 10 * mag;
	const out: number[] = [];
	for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(Math.round(v));
	return out;
}
