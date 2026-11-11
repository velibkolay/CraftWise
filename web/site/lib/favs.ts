// Favourites: item IDs in this browser's localStorage (no account, no cookie).
const KEY = "cw-favourites";
const MAX = 100; // /api/browse takes at most 100 ids

export function favourites(): number[] {
	try {
		const list = JSON.parse(localStorage.getItem(KEY) ?? "[]") as unknown;
		return Array.isArray(list) ? list.filter((n): n is number => Number.isInteger(n) && n > 0).slice(0, MAX) : [];
	} catch {
		return [];
	}
}

export function isFavourite(id: number): boolean {
	return favourites().includes(id);
}

// Returns whether the item is a favourite afterwards.
export function toggleFavourite(id: number): boolean {
	const list = favourites();
	const on = !list.includes(id);
	const next = on ? [id, ...list].slice(0, MAX) : list.filter((n) => n !== id);
	try {
		localStorage.setItem(KEY, JSON.stringify(next));
	} catch {
		return !on;
	}
	return on;
}
