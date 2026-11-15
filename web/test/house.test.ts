// Which auction house the site shows (#282): site/lib/house.ts.
import { describe, expect, it } from "vitest";
import type { House } from "../site/lib/api";
import { onRealm, pickable, pickHouse, wantedKey } from "../site/lib/house";

const house = (key: string, realm: string, faction: string | null, lastScan: number | null, kind: "faction" | "neutral" = "faction"): House => ({ key, realm, kind, faction, label: `${realm} ${faction ?? "Neutral"} AH`, lastScan });

const R6H = house("r6h", "CAMWOW EU4 Realm 6", "Horde", 100);
const R6A = house("r6a", "CAMWOW EU4 Realm 6", "Alliance", 900);
const R8H = house("r8h", "CAMWOW EU4 Realm 8 PvP", "Horde", 50);
const NEU = house("neu", "CAMWOW EU4 Realm 8 PvP", null, 999, "neutral");
const ALL = [R6A, R6H, NEU, R8H];

describe("pickHouse (#282)", () => {
	it("takes the house that was asked for", () => {
		expect(pickHouse(ALL, { wanted: "r8h" })?.key).toBe("r8h");
		expect(pickHouse(ALL, { wanted: "r6a" })?.key).toBe("r6a");
	});
	it("ignores a key that is not a house", () => {
		expect(pickHouse(ALL, { wanted: "nope" })?.key).toBe("r6h");
	});
	it("defaults to the Horde house on the characters' realm, even if another Horde house was scanned later", () => {
		expect(pickHouse(ALL, { realms: ["CAMWOW EU4 Realm 8"] })?.key).toBe("r8h");
		expect(pickHouse(ALL, { realms: [null, "camwow eu4 realm 6"] })?.key).toBe("r6h");
	});
	it("a realm with no house falls back to the most recently scanned Horde house", () => {
		expect(pickHouse(ALL, { realms: ["Elsewhere"] })?.key).toBe("r6h");
		expect(pickHouse(ALL)?.key).toBe("r6h");
		expect(pickHouse([R8H, house("r1h", "Realm 1", "Horde", 500), R6H])?.key).toBe("r1h");
	});
	it("a never-scanned house loses to a scanned one", () => {
		expect(pickHouse([house("a", "A", "Horde", null), house("b", "B", "Horde", 1)])?.key).toBe("b");
	});
	it("uses another faction, then any house, when there is no Horde house", () => {
		expect(pickHouse([R6A, NEU])?.key).toBe("r6a");
		expect(pickHouse([NEU])?.key).toBe("neu");
		expect(pickHouse([])).toBeNull();
	});
	it("the wanted house wins over the realm", () => {
		expect(pickHouse(ALL, { wanted: "r6h", realms: ["CAMWOW EU4 Realm 8"] })?.key).toBe("r6h");
	});
});

describe("realm match and picker list", () => {
	it("matches ignoring case and punctuation, one name containing the other", () => {
		expect(onRealm(R8H, ["CAMWOW EU4 Realm 8"])).toBe(true);
		expect(onRealm(R6H, ["CAMWOW EU4 Realm 8"])).toBe(false);
		expect(onRealm(R6H, ["camwow-eu4 realm_6"])).toBe(true);
		expect(onRealm(R6H, [null, undefined, ""])).toBe(false);
	});
	it("offers the faction houses only, by realm", () => {
		expect(pickable(ALL).map((h) => h.key)).toEqual(["r6a", "r6h", "r8h"]);
	});
	it("?house= beats the remembered house", () => {
		expect(wantedKey("?house=r6a", "r8h")).toBe("r6a");
		expect(wantedKey("", "r8h")).toBe("r8h");
		expect(wantedKey("?x=1", null)).toBeNull();
	});
});
