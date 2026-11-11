// Market rules shared with CraftWise/Market.lua (pure).
import { DAY, MIN_HISTORY_DAYS, TYPICAL_DAYS } from "./limits";

export function dayNumber(t: number): number {
	return Math.floor(t / DAY);
}

export type Typical =
	| { status: "ok"; price: number; days: number }
	| { status: "too_little_history"; days: number }
	| { status: "no_data"; days: 0 };

// Market.lua M.Typical / MedianOfDays: median of the daily `typ` values of the last 7 days
// (today included), rounded down; "too_little_history" below 3 such days.
export function typical(days: { day: number; typ: number | null }[], today: number, anyData: boolean): Typical {
	if (!anyData) return { status: "no_data", days: 0 };
	const list = days
		.filter((d) => d.typ !== null && d.day > today - TYPICAL_DAYS && d.day <= today)
		.map((d) => d.typ as number)
		.sort((a, b) => a - b);
	const n = list.length;
	if (n < MIN_HISTORY_DAYS) return { status: "too_little_history", days: n };
	return { status: "ok", price: medianFloor(list), days: n };
}

// Median of a sorted list, the mean of the middle two rounded down for an even count.
export function medianFloor(sorted: number[]): number {
	const n = sorted.length;
	return n % 2 === 1 ? sorted[(n - 1) / 2]! : Math.floor((sorted[n / 2 - 1]! + sorted[n / 2]!) / 2);
}

// Market.lua M.Current: not listed when the latest raw point has no units (and is not older than
// `last`), or a later full scan didn't list the item (`off`).
export function listed(row: { t: number; off: number | null; depth_t: number | null; depth_total: number | null }): boolean {
	if (row.off !== null && row.off >= row.t) return false;
	if (row.depth_t !== null && row.depth_total === 0 && row.depth_t >= row.t) return false;
	return true;
}

// [price, qty, price, qty, ...] -> [{ price, qty }, ...]
export function tierList(text: string | null): { price: number; qty: number }[] | null {
	if (text === null) return null;
	const flat = JSON.parse(text) as number[];
	const out: { price: number; qty: number }[] = [];
	for (let i = 0; i + 1 < flat.length; i += 2) out.push({ price: flat[i]!, qty: flat[i + 1]! });
	return out;
}
