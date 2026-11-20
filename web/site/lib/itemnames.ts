// Item names for the crafting data (#379). The order is: the AH's name (an upload named it), else the client's own name
// from the bundled public/data/itemnames.json (tools/gen_item_names.py), else "Item <id>". Never a bare ID when a name is
// known. Pure apart from the one fetch in loadItemNames.
export const ITEM_NAMES_URL = "/data/itemnames.json";

let bundled: Record<string, string> = {};

export function setBundledNames(names: Record<string, string>): void {
	bundled = names;
}

export function bundledName(id: number): string | null {
	return bundled[String(id)] ?? null;
}

// `ah` is the name an AH upload gave the item (null or absent when none did).
export function itemName(id: number, ah?: string | null, names: Record<string, string> = bundled): string {
	return ah || names[String(id)] || `Item ${id}`;
}

let loading: Promise<void> | null = null;

// Fetches the bundled names once; a failure leaves the old fallback ("Item <id>") and is not retried.
export function loadItemNames(get: <T>(url: string) => Promise<T>): Promise<void> {
	loading ??= get<{ names?: Record<string, string> }>(ITEM_NAMES_URL).then(
		(d) => setBundledNames(d.names ?? {}),
		() => undefined,
	);
	return loading;
}
