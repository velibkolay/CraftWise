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

	it("without a watch list (no login) a star stays in this browser and sends nothing", () => {
		const sent: unknown[] = [];
		const f = (async (...a: unknown[]) => void sent.push(a)) as unknown as typeof fetch;
		expect(toggleFavourite(7, f)).toBe(true);
		expect(favourites()).toEqual([7]);
		expect(toggleFavourite(7, f)).toBe(false);
		expect(favourites()).toEqual([]);
		expect(sent).toEqual([]);
	});

	it("with a watch list, starring and unstarring are sent to the site", async () => {
		await syncAddonWatch(answer({ watch: [{ item: 5, added: 9 }] }));
		const sent: { item: number; on: boolean }[] = [];
		const f = (async (url: string, init: RequestInit) => {
			expect(url).toBe("/api/me/watch");
			expect(init.method).toBe("POST");
			sent.push(JSON.parse(init.body as string));
			return new Response("{}");
		}) as unknown as typeof fetch;
		expect(isFromAddon(5)).toBe(true);
		expect(toggleFavourite(5, f)).toBe(false); // an addon item can be removed now
		expect(favourites()).toEqual([]);
		expect(favouriteLabel(5)).toBe("Add to Favourites");
		expect(toggleFavourite(8, f)).toBe(true);
		expect(favourites()).toEqual([8]);
		expect(addonFavourites()).toEqual([8]);
		expect(favouriteLabel(8, "Bundle")).toBe("Remove Bundle from Favourites");
		expect(sent).toEqual([{ item: 5, on: false }, { item: 8, on: true }]);
	});

	it("a failed send changes nothing for now; the next sync shows what the site stores", async () => {
		await syncAddonWatch(answer({ watch: [] }));
		const f = (async () => { throw new TypeError("network"); }) as unknown as typeof fetch;
		expect(toggleFavourite(8, f)).toBe(true);
		expect(await syncAddonWatch(answer({ watch: [] }))).toBe(true);
		expect(favourites()).toEqual([]);
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
