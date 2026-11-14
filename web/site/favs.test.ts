// Favourites merged with the addon's watch list (#165): site/lib/favs.ts.
import { beforeEach, describe, expect, it } from "vitest";
import { addonFavourites, favouriteLabel, favourites, isFromAddon, parseWatch, syncAddonWatch, toggleFavourite } from "./lib/favs";

const store = new Map<string, string>();
beforeEach(() => {
	store.clear();
	(globalThis as unknown as { localStorage: Storage }).localStorage = {
		getItem: (k: string) => store.get(k) ?? null,
		setItem: (k: string, v: string) => void store.set(k, v),
	} as Storage;
});

const answer = (body: unknown, init: ResponseInit = {}) => (async () => new Response(JSON.stringify(body), init)) as unknown as typeof fetch;

describe("parseWatch", () => {
	it("takes the item IDs in order and ignores anything else", () => {
		expect(parseWatch({ watch: [{ item: 5, added: 1 }, { item: 2, added: 1 }, { item: "x" }, null, { item: 0 }] })).toEqual([5, 2]);
		expect(parseWatch({})).toBeNull();
		expect(parseWatch(null)).toBeNull();
	});
});

describe("syncAddonWatch", () => {
	it("merges the addon's items first and tells when the favourites changed", async () => {
		toggleFavourite(7);
		expect(await syncAddonWatch(answer({ watch: [{ item: 5, added: 9 }, { item: 7, added: 8 }] }))).toBe(true);
		expect(favourites()).toEqual([5, 7]);
		expect(addonFavourites()).toEqual([5, 7]);
		expect(await syncAddonWatch(answer({ watch: [{ item: 5, added: 9 }, { item: 7, added: 8 }] }))).toBe(false);
	});

	it("an addon item can't be removed here, a local one can", async () => {
		toggleFavourite(7);
		await syncAddonWatch(answer({ watch: [{ item: 5, added: 9 }] }));
		expect(isFromAddon(5)).toBe(true);
		expect(toggleFavourite(5)).toBe(true);
		expect(favouriteLabel(5)).toBe("Watched in the addon");
		expect(toggleFavourite(7)).toBe(false);
		expect(favourites()).toEqual([5]);
		expect(favouriteLabel(7, "Bundle")).toBe("Add Bundle to Favourites");
	});

	it("unwatched in the addon: gone on the next sync; failures keep the cached list", async () => {
		await syncAddonWatch(answer({ watch: [{ item: 5, added: 9 }] }));
		expect(await syncAddonWatch(answer({ error: "access_denied" }, { status: 403 }))).toBe(false);
		expect(await syncAddonWatch((async () => { throw new TypeError("network"); }) as unknown as typeof fetch)).toBe(false);
		expect(favourites()).toEqual([5]);
		expect(await syncAddonWatch(answer({ watch: [] }))).toBe(true);
		expect(favourites()).toEqual([]);
	});
});
