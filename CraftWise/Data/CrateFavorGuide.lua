-- Merchant's Favor per Waylaid Crate from published guides (#129). Third-party values from the WoW: Forever
-- beta, not confirmed by Blizzard; the two sources below agree. Veli approved them as an exception to the
-- "no guessed data" rule: the page shows them only where the snapshot has no measured reward (`rewardFrom`
-- "tooltip" or "seen" always wins), and always labelled as guide values, never as measured.
--
-- Sources:
--   https://forevermastery.com/en/guides/wow-forever-merchants-favor (updated 2026-11-04, beta values)
--   https://foreverchanges.pro/merchants-favor (updated 2026-09-23)
--
-- Keyed by the crate's rank and kind as its name states them ("Waylaid Crate: Earthly Expert Herbs" is rank
-- Expert, kind Herbs); no item IDs are assumed. "listed" = the guides list the crate itself; "rule" = only the
-- guides' rank rule covers it (raw-material crates 15, crafted-goods crates 30 at Expert). Artisan crates are
-- in no source: no value. The 15% "Performance Bonus" chance of double Favor is not counted.
-- Generated from web/site/lib/crateFavorGuide.ts by tools/gen_crate_favor_guide.lua; do not edit.
local _, ns = ...
ns.CrateFavorGuide = {
	sources = {
		{ label = "Forever Mastery", url = "https://forevermastery.com/en/guides/wow-forever-merchants-favor", updated = "2026-11-04" },
		{ label = "Forever Changes", url = "https://foreverchanges.pro/merchants-favor", updated = "2026-09-23" },
	},
	-- [rank][kind] = { Favor per crate, basis }; basis "listed" = a guide lists the crate, "rule" = only the rank rule.
	table = {
		Apprentice = { Curiosities = { 5, "listed" }, Fabrics = { 10, "listed" }, Herbs = { 5, "listed" }, Ingots = { 10, "listed" }, Ore = { 5, "listed" }, Parts = { 10, "listed" }, Textiles = { 5, "listed" } },
		Expert = { Curiosities = { 15, "rule" }, Fabrics = { 30, "listed" }, Herbs = { 15, "rule" }, Ingots = { 30, "listed" }, Ore = { 15, "listed" }, Parts = { 30, "rule" }, Textiles = { 15, "listed" } },
		Journeyman = { Curiosities = { 10, "listed" }, Fabrics = { 20, "listed" }, Herbs = { 10, "listed" }, Ingots = { 20, "listed" }, Ore = { 10, "listed" }, Parts = { 20, "listed" }, Textiles = { 10, "listed" } },
	},
}
