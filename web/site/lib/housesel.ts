// The house the page shows (#96, #282): ?house=, else the remembered pick, else the Horde house on the realm of
// the account's characters, else the most recently scanned Horde house (the rule is site/lib/house.ts). Browser only.
import { get } from "./api";
import { HOUSE_KEY, type House, pickHouse, wantedKey } from "./house";

let known: House[] = [];
// The houses the last choice was made from, for the picker.
export function knownHouses(): House[] {
	return known;
}

function remembered(): string | null {
	try {
		return localStorage.getItem(HOUSE_KEY);
	} catch {
		return null;
	}
}

// Picks from a loaded list: the choice the URL or this browser holds, else the default. `realms`: the realms of
// the account's characters, on the private pages.
export function chooseHouse(houses: House[], realms?: Iterable<string | null | undefined>): House | null {
	known = houses;
	return pickHouse(houses, { wanted: wantedKey(location.search, remembered()), realms });
}

// The picker's choice: remembered here, and in the URL so the page can be shared.
export function selectHouse(key: string): void {
	try {
		localStorage.setItem(HOUSE_KEY, key);
	} catch {
		// the URL still carries it
	}
	const url = new URL(location.href);
	url.searchParams.set("house", key);
	location.assign(url.toString());
}

export async function mainHouse(realms?: Iterable<string | null | undefined>): Promise<House | null> {
	return chooseHouse((await get<{ houses: House[] }>("/api/houses")).houses, realms);
}
