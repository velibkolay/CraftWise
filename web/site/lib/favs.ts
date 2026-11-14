// Favourites: item IDs in this browser's localStorage (no account, no cookie), merged with the
// watch list of the CraftWise addon (#165) when the private API answers. The addon's list is one way:
// it comes from the companion's upload, the site never writes it back, so an item watched in the addon
// can't be removed here. localStorage keeps a copy of the last list that came (a cache for the next
// page view) and stays the only source for visitors without a Cloudflare Access login.
const KEY = "cw-favourites";
const ADDON_KEY = "cw-favourites-addon";
const MAX = 100; // /api/browse takes at most 100 ids

function readIds(key: string): number[] {
	try {
		const list = JSON.parse(localStorage.getItem(key) ?? "[]") as unknown;
		return Array.isArray(list) ? list.filter((n): n is number => Number.isInteger(n) && n > 0).slice(0, MAX) : [];
	} catch {
		return [];
	}
}

// Watched in the addon (newest first), as of the last answer of /api/me/watch.
export function addonFavourites(): number[] {
	return readIds(ADDON_KEY);
}

export function isFromAddon(id: number): boolean {
	return addonFavourites().includes(id);
}

// The merged list: the addon's watched items first (newest watched first), then the ones starred here.
export function favourites(): number[] {
	return [...new Set([...addonFavourites(), ...readIds(KEY)])].slice(0, MAX);
}

export function isFavourite(id: number): boolean {
	return favourites().includes(id);
}

// Returns whether the item is a favourite afterwards. An item watched in the addon stays one.
export function toggleFavourite(id: number): boolean {
	if (isFromAddon(id)) return true;
	const list = readIds(KEY);
	const on = !list.includes(id);
	const next = on ? [id, ...list].slice(0, MAX) : list.filter((n) => n !== id);
	try {
		localStorage.setItem(KEY, JSON.stringify(next));
	} catch {
		return !on;
	}
	return on;
}

// What the button of a favourite says: "Add to"/"Remove from Favourites", or that the addon owns it.
export function favouriteLabel(id: number, what = ""): string {
	if (isFromAddon(id)) return "Watched in the addon";
	return `${isFavourite(id) ? "Remove" : "Add"} ${what ? what + " " : ""}${isFavourite(id) ? "from" : "to"} Favourites`;
}

// Parses /api/me/watch (items newest first) into IDs; anything else gives null.
export function parseWatch(body: unknown): number[] | null {
	const list = (body as { watch?: unknown } | null)?.watch;
	if (!Array.isArray(list)) return null;
	const ids: number[] = [];
	for (const w of list) {
		const item = (w as { item?: unknown } | null)?.item;
		if (typeof item === "number" && Number.isInteger(item) && item > 0) ids.push(item);
	}
	return ids.slice(0, MAX);
}

// Asks the private API for the addon's watch list once per page view and caches it. Visitors without
// an Access login get a redirect or an error: nothing changes for them (the cache is left alone, so a
// network failure doesn't drop the list). Resolves to true when the merged favourites changed, so the
// page can redraw. Never throws.
export async function syncAddonWatch(fetchFn: typeof fetch = fetch): Promise<boolean> {
	try {
		const res = await fetchFn("/api/me/watch", { headers: { accept: "application/json" }, credentials: "same-origin", redirect: "manual", signal: AbortSignal.timeout(4000) });
		if (!res.ok) return false;
		const ids = parseWatch(await res.json());
		if (!ids) return false;
		const before = JSON.stringify(favourites());
		localStorage.setItem(ADDON_KEY, JSON.stringify(ids));
		return JSON.stringify(favourites()) !== before;
	} catch {
		return false;
	}
}
