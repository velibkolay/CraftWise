// Favourites: item IDs in this browser's localStorage (no account, no cookie), merged with the
// watch list of the CraftWise addon (#165) when the private API answers. Since #244 the list is two-way:
// for a visitor with an Access login, starring or unstarring writes the watch list on the site
// (POST /api/me/watch), the companion hands it to the addon of every machine, and the addon's changes
// come back here. localStorage keeps a copy of the last list that came (a cache for the next page view)
// and stays the only store for visitors without a login.
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

// Has the private API answered before (so there is a watch list to write to)?
function hasWatchList(): boolean {
	try {
		return localStorage.getItem(ADDON_KEY) !== null;
	} catch {
		return false;
	}
}

function writeIds(key: string, ids: number[]): boolean {
	try {
		localStorage.setItem(key, JSON.stringify(ids));
		return true;
	} catch {
		return false;
	}
}

// Tells the site about a change of the watch list. Fire and forget: when it fails the next page view
// reads the site's list again (syncAddonWatch) and shows what is really stored.
function sendWatch(item: number, on: boolean, fetchFn: typeof fetch): void {
	try {
		void fetchFn("/api/me/watch", {
			method: "POST",
			headers: { "content-type": "application/json", accept: "application/json" },
			body: JSON.stringify({ item, on }),
			credentials: "same-origin",
			redirect: "manual",
			signal: AbortSignal.timeout(8000),
		}).catch(() => undefined);
	} catch {
		// no network API: nothing to send
	}
}

// Returns whether the item is a favourite afterwards. With a watch list (an Access login) the change goes
// to the site and shows at once; without one it stays in this browser.
export function toggleFavourite(id: number, fetchFn: typeof fetch = fetch): boolean {
	const addon = readIds(ADDON_KEY);
	const local = readIds(KEY);
	const on = !addon.includes(id) && !local.includes(id);
	if (!on) {
		if (local.includes(id)) writeIds(KEY, local.filter((n) => n !== id));
		if (addon.includes(id)) {
			writeIds(ADDON_KEY, addon.filter((n) => n !== id));
			sendWatch(id, false, fetchFn);
		}
		return false;
	}
	if (hasWatchList()) {
		if (!writeIds(ADDON_KEY, [id, ...addon].slice(0, MAX))) return false;
		sendWatch(id, true, fetchFn);
		return true;
	}
	return writeIds(KEY, [id, ...local].slice(0, MAX));
}

// What the button of a favourite says: "Add to" / "Remove from Favourites".
export function favouriteLabel(id: number, what = ""): string {
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
