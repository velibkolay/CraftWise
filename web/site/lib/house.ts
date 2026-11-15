// Which auction house the site shows (#282). Pure: no DOM, no fetch; the Worker tests import it.

// An auction house as /api/houses lists it.
export interface House {
	key: string;
	realm: string;
	kind: "faction" | "neutral";
	faction: string | null;
	label: string;
	lastScan: number | null;
}

export const HOUSE_KEY = "cw-house"; // the remembered choice in this browser's localStorage

export interface HouseChoice {
	wanted?: string | null; // a house key: ?house= or the remembered pick
	realms?: Iterable<string | null | undefined>; // the realms of the account's characters (private snapshots)
}

const norm = (s: string): string => s.toLowerCase().replace(/[^a-z0-9]+/g, "");

// A house sits on a character's realm when the names match ignoring case and punctuation, or one contains the
// other ("CAMWOW EU4 Realm 8" and "CAMWOW EU4 Realm 8 PvP" are the same realm).
export function onRealm(h: House, realms: Iterable<string | null | undefined>): boolean {
	const hr = norm(h.realm);
	if (!hr) return false;
	for (const r of realms) {
		const n = r ? norm(r) : "";
		if (n && (n === hr || n.includes(hr) || hr.includes(n))) return true;
	}
	return false;
}

const newest = (list: House[]): House | null => list.reduce<House | null>((best, h) => (best === null || (h.lastScan ?? -1) > (best.lastScan ?? -1) ? h : best), null);

// The house to show: the one asked for; else the Horde house on a realm one of the account's characters is on;
// else the most recently scanned Horde house; else the same for any faction house; else the first house.
export function pickHouse(houses: House[], choice: HouseChoice = {}): House | null {
	const wanted = choice.wanted ? houses.find((h) => h.key === choice.wanted) : undefined;
	if (wanted) return wanted;
	const horde = houses.filter((h) => h.kind === "faction" && h.faction === "Horde");
	const faction = houses.filter((h) => h.kind === "faction");
	const realms = choice.realms ? [...choice.realms] : [];
	for (const pool of [horde, faction]) {
		const own = realms.length ? pool.filter((h) => onRealm(h, realms)) : [];
		const pick = newest(own) ?? newest(pool);
		if (pick) return pick;
	}
	return houses[0] ?? null;
}

// The houses the picker offers: faction houses (the neutral house is not one the site is about), by realm and label.
export function pickable(houses: House[]): House[] {
	return houses.filter((h) => h.kind === "faction").sort((a, b) => a.realm.localeCompare(b.realm) || a.label.localeCompare(b.label));
}

// The house key asked for: ?house= first, else the remembered one.
export function wantedKey(search: string, stored: string | null): string | null {
	return new URLSearchParams(search).get("house") || stored || null;
}
