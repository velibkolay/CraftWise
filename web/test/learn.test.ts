// Item names and "where to learn" on the site (#379): names fall back AH > bundled > "Item <id>", and the learn line
// names a zone and faction, never an NPC, and says where the data comes from.
import { describe, expect, it } from "vitest";
import itemNamesJson from "../public/data/itemnames.json?raw";
import recipesJson from "../public/data/recipes.json?raw";
import { bundledName, itemName, setBundledNames } from "../site/lib/itemnames";
import vendorNpcsJson from "../public/data/vendornpcs.json?raw";
import { LEARN_LABEL, learnLines, type VendorNpcs } from "../site/lib/learn";
import type { RecipeData } from "../site/lib/recipes";

const real = JSON.parse(recipesJson) as RecipeData;
const bundled = (JSON.parse(itemNamesJson) as { names: Record<string, string> }).names;

describe("item name fallback", () => {
	it("prefers the AH name, then the bundled one, then Item <id>", () => {
		const names = { "8385": "Pattern: Turtle Scale Gloves" };
		expect(itemName(8385, "Pattern: Turtle Scale Gloves (AH)", names)).toBe("Pattern: Turtle Scale Gloves (AH)");
		expect(itemName(8385, null, names)).toBe("Pattern: Turtle Scale Gloves");
		expect(itemName(8385, undefined, names)).toBe("Pattern: Turtle Scale Gloves");
		expect(itemName(1, null, names)).toBe("Item 1");
		expect(itemName(1, "", names)).toBe("Item 1");
	});

	it("uses the loaded bundled names by default", () => {
		setBundledNames(bundled);
		expect(bundledName(8385)).toBe("Pattern: Turtle Scale Gloves");
		expect(itemName(8385, null)).toBe("Pattern: Turtle Scale Gloves");
		setBundledNames({});
		expect(itemName(8385, null)).toBe("Item 8385");
	});

	it("names every recipe item (teach) in the bundled data", () => {
		for (const item of Object.keys(real.teach)) expect(bundled[item], `item ${item}`).toBeTruthy();
	});
});

describe("where to learn", () => {
	const npcs: VendorNpcs = { "7854": ["Jangdor Swiftstrider", "Feralas", 74.4, 42.9], "7": ["Zone Less"] };
	const data = {
		learn: { "100": [[357, "H", 7854], [357, "A", 12345]], "101": [[999, "", 7]] },
		areas: { "357": "Feralas" },
	} as unknown as RecipeData;

	it("names the vendor, zone and spot, and labels the source", () => {
		const [horde] = learnLines(data, 100, npcs);
		expect(horde).toBe(`Vendor: Jangdor Swiftstrider, Feralas 74.4, 42.9 (Horde; ${LEARN_LABEL})`);
	});

	it("an NPC without a name shows its zone and faction, never its ID", () => {
		const alliance = learnLines(data, 100, npcs)[1]!;
		expect(alliance).toBe(`Sold by: a vendor, Feralas (Alliance; ${LEARN_LABEL})`);
		expect(alliance).not.toContain("12345");
	});

	it("a named NPC without a zone anywhere shows just the name", () => {
		expect(learnLines(data, 101, npcs)).toEqual([`Vendor: Zone Less (${LEARN_LABEL})`]);
	});

	it("says the source is not known when no vendor is listed", () => {
		const [text] = learnLines(data, 5, npcs);
		expect(text).toMatch(/trainer, a drop or a quest/);
		expect(text).not.toContain(LEARN_LABEL);
	});

	it("knows where the Turtle Scale Gloves pattern is sold, by name", () => {
		const real2 = JSON.parse(vendorNpcsJson) as { npcs: VendorNpcs };
		const lines = learnLines(real, 8385, real2.npcs);
		expect(lines.join(" | ")).toContain("Jangdor Swiftstrider, Feralas 74.4, 42.9");
		expect(lines.join(" | ")).not.toMatch(/78[0-9]{2}/);
	});
});
