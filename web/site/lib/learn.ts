// "Where to learn" a recipe (#379), from the bundled data only. Vendors come from What's Training?'s tables (not seen in
// game); their names and spots from Polestar data (public/data/vendornpcs.json, tools/gen_vendor_npcs.py), the zone
// from the client's AreaTable. Both are labelled. Never a bare NPC ID: an NPC without a name shows only its zone. Trainer
// fees are recorded by the addon but not uploaded, so none is shown here. Pure apart from the one fetch.
import type { RecipeData } from "./recipes";

export const VENDOR_NPCS_URL = "/data/vendornpcs.json";
export const LEARN_LABEL = "Polestar data, What's Training?, not seen in game";

// npc ID -> [name, zone?, x?, y?]
export type VendorNpcs = Record<string, [string, string?, number?, number?]>;

const FACTION: Record<string, string> = { H: "Horde", A: "Alliance" };

let npcs: VendorNpcs = {};
let loading: Promise<void> | null = null;

export function setVendorNpcs(n: VendorNpcs): void {
	npcs = n;
}

// Fetches the vendor NPCs once; a failure leaves vendors without names (their zone still shows).
export function loadVendorNpcs(get: <T>(url: string) => Promise<T>): Promise<void> {
	loading ??= get<{ npcs?: VendorNpcs }>(VENDOR_NPCS_URL).then(
		(d) => setVendorNpcs(d.npcs ?? {}),
		() => undefined,
	);
	return loading;
}

function coord(n: number): string {
	return n.toFixed(1);
}

// One line per vendor: "Vendor: Jangdor Swiftstrider, Feralas 74.4, 42.9 (Horde; <label>)".
export function learnLines(data: RecipeData, recipeItem: number, known: VendorNpcs = npcs): string[] {
	const vendors = data.learn?.[String(recipeItem)] ?? [];
	if (!vendors.length) return ["Where to learn: a trainer, a drop or a quest; the bundled data does not say which."];
	return vendors.map(([area, faction, npc]) => {
		const n = known[String(npc)];
		const zone = n?.[1] ?? data.areas?.[String(area)] ?? null;
		const spot = zone && n?.[2] !== undefined && n[3] !== undefined ? `${zone} ${coord(n[2])}, ${coord(n[3])}` : zone;
		const who = n?.[0] ?? "a vendor";
		const side = FACTION[faction];
		return `${n ? "Vendor" : "Sold by"}: ${[who, spot].filter(Boolean).join(", ")} (${side ? `${side}; ` : ""}${LEARN_LABEL})`;
	});
}
