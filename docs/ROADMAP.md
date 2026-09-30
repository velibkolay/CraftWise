# CraftWise roadmap

CraftWise is free, open source (GPL-3.0) and built for every WoW: Forever player.
Principle: **no guessed data**. What isn't verified is left out and tracked in #11.

## Now (in the beta, before the November 4 launch)
- [x] Profit view: every known and unlearned recipe with cost, sells-for, profit (#2, #4, #5)
- [x] Learn view: every recipe you don't know yet, where to get it, fits-my-skill filter (#3)
- [x] Bags view: vendor vs auction for every bag item, keep marking, quest items kept (#12)
- [ ] Verified recipe data: sources, required skill, thresholds (#11) - Wowhead permission requested, manual entry as fallback
- [ ] Disenchant values in the Bags view (#12, data via #11)
- [ ] Sort the real bags by recommendation (#12), without fighting Bagnon

## Next
- [ ] Own AH scan: automatic full scan every 15 minutes while at the auctioneer, full listings incl. seller, sell-through estimate (#6)
- [ ] Desktop companion + Supabase: upload scans and in-game source records, download merged market data (#7)
- [ ] Crowd-sourced recipe sources recorded in game: vendors, drops, quests (#10)
- [ ] Vendor prices normalised for reputation discounts (#8)

## Later
- [ ] Levelling guides for every profession; gathering tabs become guide tabs (#9)
- [ ] velikopter.com: price pages and charts from the merged data

## Rules we keep
- Addon stays free (Blizzard add-on policy); paid features, if any, live on the site.
- No anti-AFK or input automation; the companion app only reads SavedVariables.
- Supabase: no service keys in clients, uploads through an Edge Function, RLS on every table.
