// Merchant's Favor per Waylaid Crate from published guides (#129). Third-party values from the WoW: Forever
// beta, not confirmed by Blizzard; the two sources below agree. Veli approved them as an exception to the
// "no guessed data" rule: the page shows them only where the snapshot has no measured reward (`rewardFrom`
// "tooltip" or "seen" always wins), and always labelled as guide values, never as measured.
//
// Sources:
//   https://forevermastery.com/en/guides/wow-forever-merchants-favor (updated 2026-11-04, beta values)
//   https://foreverchanges.pro/merchants-favor (updated 2026-09-23)
//
// Keyed by the crate's rank and kind as its name states them ("Waylaid Crate: Earthly Expert Herbs" is rank
// Expert, kind Herbs); no item IDs are assumed. "listed" = the guides list the crate itself; "rule" = only the
// guides' rank rule covers it (raw-material crates 15, crafted-goods crates 30 at Expert). Artisan crates are
// in no source: no value. The 15% "Performance Bonus" chance of double Favor is not counted.

export const GUIDE_SOURCES: { label: string; url: string; updated: string }[] = [
	{ label: "Forever Mastery", url: "https://forevermastery.com/en/guides/wow-forever-merchants-favor", updated: "2026-11-04" },
	{ label: "Forever Changes", url: "https://foreverchanges.pro/merchants-favor", updated: "2026-09-23" },
];

export const RANKS = ["Apprentice", "Journeyman", "Expert", "Artisan"] as const;
export type Rank = (typeof RANKS)[number];
export const KINDS = ["Herbs", "Textiles", "Ore", "Curiosities", "Fabrics", "Ingots", "Parts"] as const;
export type Kind = (typeof KINDS)[number];

export interface GuideValue {
	favor: number;
	basis: "listed" | "rule";
}

const L = (favor: number): GuideValue => ({ favor, basis: "listed" });
const R = (favor: number): GuideValue => ({ favor, basis: "rule" });

const TABLE: Partial<Record<Rank, Partial<Record<Kind, GuideValue>>>> = {
	Apprentice: { Herbs: L(5), Textiles: L(5), Ore: L(5), Curiosities: L(5), Fabrics: L(10), Ingots: L(10), Parts: L(10) },
	Journeyman: { Herbs: L(10), Textiles: L(10), Ore: L(10), Curiosities: L(10), Fabrics: L(20), Ingots: L(20), Parts: L(20) },
	Expert: { Textiles: L(15), Ore: L(15), Fabrics: L(30), Ingots: L(30), Herbs: R(15), Curiosities: R(15), Parts: R(30) },
};

// Rank and kind from the crate's name: the rank is any word of the part after the colon (the snapshot's
// `tier` is only its first word, "Earthly" for "Earthly Expert Herbs"), the kind is its last word.
export function crateParts(name: string | null): { rank: Rank | null; kind: Kind | null } {
	const label = (name ?? "").includes(":") ? (name ?? "").slice((name ?? "").indexOf(":") + 1) : (name ?? "");
	const words = label.trim().split(/\s+/);
	const rank = (RANKS as readonly string[]).find((r) => words.includes(r)) as Rank | undefined;
	const last = words[words.length - 1] ?? "";
	const kind = (KINDS as readonly string[]).includes(last) ? (last as Kind) : null;
	return { rank: rank ?? null, kind };
}

export function guideFavor(name: string | null): GuideValue | null {
	const { rank, kind } = crateParts(name);
	if (!rank || !kind) return null;
	return TABLE[rank]?.[kind] ?? null;
}
