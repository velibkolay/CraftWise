// The site's own read API (web/docs/api.md). Nothing else is fetched at runtime.
import type { DayRow, Tier } from "./format";

export interface House {
	key: string;
	realm: string;
	kind: "faction" | "neutral";
	faction: string | null;
	label: string;
	lastScan: number | null;
}

export interface Current {
	t: number;
	min: number | null;
	qty: number | null;
	listings: number | null;
	off: number | null;
	listed: boolean;
}

export type Typical =
	| { status: "ok"; price: number; days: number }
	| { status: "too_little_history"; days: number }
	| { status: "no_data"; days: 0 };

export interface ItemInfo {
	id: number;
	name: string | null;
	quality: number | null;
	icon: number | null;
	class: number | null;
	subclass: number | null;
}

export interface BrowseItem extends ItemInfo {
	current: Current | null;
	typical: Typical;
	days: (DayRow & { src: string })[];
}

export interface Browse {
	house: string;
	label: string;
	lastScan: number | null;
	today: number;
	more: boolean;
	items: BrowseItem[];
}

export interface Categories {
	house: string;
	label: string;
	lastScan: number | null;
	categories: { class: number | null; subclass: number | null; items: number }[];
}

export interface Market {
	house: string;
	label: string;
	kind: string;
	lastScan: number | null;
	suffix: number;
	current: Current | null;
	depth: { t: number; total: number | null; tiers: Tier[] | null } | null;
	typical: Typical;
	days: (DayRow & { src: string; listMax: number | null })[];
	raw: { t: number; total: number; listings: number | null; m: number | null; tiers: Tier[] | null }[];
}

export interface ItemDetail {
	id: number;
	item: ItemInfo | null;
	markets: Market[];
}

export class ApiError extends Error {
	constructor(
		readonly status: number,
		message: string,
	) {
		super(message);
	}
}

export async function get<T>(path: string): Promise<T> {
	const res = await fetch(path, { headers: { accept: "application/json" } });
	if (!res.ok) {
		let message = `${res.status}`;
		try {
			message = ((await res.json()) as { message?: string }).message ?? message;
		} catch {
			// not JSON
		}
		throw new ApiError(res.status, message);
	}
	return (await res.json()) as T;
}

// The site is about one house: the Horde auction house (#96), else the first faction house.
export function pickHouse(houses: House[]): House | null {
	return houses.find((h) => h.kind === "faction" && h.faction === "Horde") ?? houses.find((h) => h.kind === "faction") ?? houses[0] ?? null;
}

export async function mainHouse(): Promise<House | null> {
	return pickHouse((await get<{ houses: House[] }>("/api/houses")).houses);
}
