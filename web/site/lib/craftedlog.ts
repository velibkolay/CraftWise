// The Crafted table of /me/crafted (#266): the craft log the companion uploads (docs/api.md, GET /api/me/crafted),
// summed per recipe for today, the last 7 days and all time. Pure: no DOM, no fetch; the Worker tests import it.
// Profit is the estimate recorded at craft time, not money received; a day without profit or time stays a dash.

// One day of one recipe of one character, as the API sends it.
export interface LogRow {
	char: string;
	recipe: number;
	day: number; // YYYYMMDD, the player's local day
	n: number;
	items: number | null;
	profit: number | null; // copper, may be negative
	known: number | null; // crafts that had a profit
	active: number | null; // seconds of active crafting
}

// The API's rows: [char, recipe, day, n, items, profit, known, active]. Anything malformed is dropped.
export function parseRows(v: unknown): LogRow[] {
	const out: LogRow[] = [];
	if (!Array.isArray(v)) return out;
	const num = (x: unknown): number | null => (typeof x === "number" && Number.isFinite(x) ? x : null);
	for (const r of v) {
		if (!Array.isArray(r) || typeof r[0] !== "string") continue;
		const [, recipe, day, n] = [r[0], num(r[1]), num(r[2]), num(r[3])];
		if (recipe === null || day === null || n === null) continue;
		out.push({ char: r[0], recipe, day, n, items: num(r[4]), profit: num(r[5]), known: num(r[6]), active: num(r[7]) });
	}
	return out;
}

// A day's number of days since 1970-01-01 (for "the last 7 days"), from YYYYMMDD.
export function dayIndex(day: number): number {
	return Math.floor(Date.UTC(Math.floor(day / 10000), (Math.floor(day / 100) % 100) - 1, day % 100) / 86_400_000);
}

// Today's local day as YYYYMMDD, as the addon writes the days.
export function localDay(d: Date): number {
	return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
}

// The sums of one period. profit is null when no day of the period recorded one; partial = some crafts of those
// days had no price (the addon's "profit known for K of N crafts"), so the figure is a floor.
export interface Period {
	n: number;
	profit: number | null;
	partial: boolean;
}

export interface Line {
	recipe: number;
	name: string;
	profession: string | null;
	today: Period;
	week: Period;
	all: Period;
	active: number | null; // seconds, all time; null = no day recorded any
	perHour: number | null; // copper per active hour: profit over the days that have both, null when none
}

export interface Meta {
	name: string;
	profession: string | null;
}

function sum(rows: LogRow[]): Period {
	let n = 0;
	let profit: number | null = null;
	let unpriced = 0; // crafts the profit doesn't cover
	for (const r of rows) {
		n += r.n;
		if (r.profit !== null) {
			profit = (profit ?? 0) + r.profit;
			unpriced += r.n - Math.min(r.n, r.known ?? r.n); // a day without a known count: every craft of it was priced
		} else {
			unpriced += r.n;
		}
	}
	return { n, profit, partial: profit !== null && unpriced > 0 };
}

// One line per recipe, over the rows of `char` (null = every character). `today` is YYYYMMDD.
export function summarize(rows: LogRow[], today: number, char: string | null, meta: (recipe: number) => Meta): Line[] {
	const t = dayIndex(today);
	const by = new Map<number, LogRow[]>();
	for (const r of rows) {
		if (char !== null && r.char !== char) continue;
		const list = by.get(r.recipe);
		if (list) list.push(r);
		else by.set(r.recipe, [r]);
	}
	const lines: Line[] = [];
	for (const [recipe, list] of by) {
		const m = meta(recipe);
		const withTime = list.filter((r) => r.active !== null);
		const active = withTime.length ? withTime.reduce((a, r) => a + r.active!, 0) : null;
		const both = list.filter((r) => r.active !== null && r.active > 0 && r.profit !== null);
		const bothTime = both.reduce((a, r) => a + r.active!, 0);
		lines.push({
			recipe,
			name: m.name,
			profession: m.profession,
			today: sum(list.filter((r) => r.day === today)),
			week: sum(list.filter((r) => dayIndex(r.day) > t - 7 && dayIndex(r.day) <= t)),
			all: sum(list),
			active,
			perHour: bothTime > 0 ? Math.round((both.reduce((a, r) => a + r.profit!, 0) / bothTime) * 3600) : null,
		});
	}
	return lines;
}

export type SortKey = "name" | "profession" | "today" | "week" | "all" | "pToday" | "pWeek" | "pAll" | "active" | "perHour";
export const SORT_KEYS: SortKey[] = ["name", "profession", "today", "week", "all", "pToday", "pWeek", "pAll", "active", "perHour"];

function value(l: Line, key: Exclude<SortKey, "name" | "profession">): number | null {
	switch (key) {
		case "today":
			return l.today.n;
		case "week":
			return l.week.n;
		case "all":
			return l.all.n;
		case "pToday":
			return l.today.profit;
		case "pWeek":
			return l.week.profit;
		case "pAll":
			return l.all.profit;
		case "active":
			return l.active;
		case "perHour":
			return l.perHour;
	}
}

// Unknown figures (a dash) sort last in both directions; ties by name.
export function sortLines(lines: Line[], key: SortKey, desc: boolean): Line[] {
	const dir = desc ? -1 : 1;
	const byName = (a: Line, b: Line) => a.name.localeCompare(b.name) || a.recipe - b.recipe;
	return [...lines].sort((a, b) => {
		if (key === "name") return dir * byName(a, b);
		if (key === "profession") return dir * (a.profession ?? "").localeCompare(b.profession ?? "") || byName(a, b);
		const va = value(a, key);
		const vb = value(b, key);
		if (va === null && vb === null) return byName(a, b);
		if (va === null) return 1;
		if (vb === null) return -1;
		return dir * (va - vb) || byName(a, b);
	});
}

// "1 h 05 min", "12 min", "45 s": active crafting time.
export function durationText(seconds: number): string {
	const s = Math.round(seconds);
	if (s < 60) return `${s} s`;
	const m = Math.floor(s / 60);
	if (m < 60) return `${m} min`;
	return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")} min`;
}
