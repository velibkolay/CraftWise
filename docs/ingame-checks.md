# In-game checks

Things the headless tests cannot prove. Run after installing to `World of Warcraft/_forever_/Interface/AddOns/`, on the live Forever client.

## Setup
1. Install CraftWise and Auctionator, `/reload`.
2. Auction house: Auctionator tab, **Full Scan**.

## Recipe capture (#1, #3)
- [ ] Open a profession window. `/craftwise debug` shows the profession with a recipe count that includes unlearned recipes.
- [ ] Count matches the window with the "Unlearned" filter on. If it only counts learned recipes, `GetAllRecipeIDs` respects the filter: report it.
- [ ] `/craftwise`: unlearned recipes show reagents (tooltip). If they show "Reagents unknown", `GetRecipeSchematic` returns nothing for unlearned recipes.

## Prices (#2)
- [ ] Rows show cost and sells-for after the Auctionator scan.
- [ ] Visit a trade goods vendor (thread, dye) and reopen `/craftwise`: those reagents show "vendor" in the tooltip.
- [ ] Without Auctionator and before any AH visit: orange "No auction prices yet" line, no Lua error. With CraftWise's own recorded prices it goes away even without Auctionator.

## Trainer (#3)
- [ ] Open the profession window first (recipe names are matched against it), then your profession trainer, then `/craftwise`: trainer recipes show Trainable / Trainable at N, a learn cost and break-even.

## UI (#5)
- [ ] Window drags, closes with Esc and the X button.
- [ ] Profession buttons switch tables; "Show unlearned" toggles rows.
- [ ] Header click sorts, second click flips direction.
- [ ] Mouse wheel scrolls; Shift+wheel scrolls a page.
- [ ] Row hover: reagent breakdown with source; clicking a row with the profession open selects the recipe.

Report Lua errors with BugSack + BugGrabber.

## Skill-up recorder (#15)
- Craft a few recipes (orange and yellow). `/craftwise debug` shows "skill-up log: N crafts recorded" = number of crafts.
- Recipe tooltip shows `Skill-ups  yellow X  grey Y` and `Your crafts  a skill-ups in b crafts`.
- Orange crafts must all count as skill-ups. After `/reload`, `CraftWiseDB.skillups[recipeID][skill]` holds `{ n, ups, d }`.
- Batch crafting (craft all): every craft counted once.

## Upgrades view (#16)
- Upgrades tab lists known recipes whose item has a higher item level (or same level, more armour) than what you wear, or fills an empty slot.
- Items you can't wear (red line in the item tooltip) or are too low level for are not listed.
- Tooltip: stat differences vs the equipped item, reagents with "have N". Right-click dismisses; "Show dismissed" shows them greyed at the bottom; right-click again restores.
- Equip something from the list: the row disappears (PLAYER_EQUIPMENT_CHANGED).
- Check: `C_Item.GetItemStats` returns armour under `RESISTANCE0_NAME` in the Forever client (else the armour gain shows 0).
- Check: ranged items (bow/gun) compare against the ranged slot.

### Craftable section: learnable recipes, total cost, main stats (#16 scope extension)
`/reload` is enough (no new file).
- Summary starts with "Craftable" and counts rows from known recipes and rows to "learn first".
- A recipe you don't know, whose item would upgrade a slot, shows with "learn first (Trainer)" / "(Vendor: Name (Zone) - price)" / "(Drop: ...)" / "(AH: price)" when its required skill is known and met. Recipes above your skill, with an unknown requirement, sold only by the other faction's vendor, quest-only, or without any source are not listed.
- TOTAL COST column = reagents + learn cost (trainer fee, vendor price or the recipe item's AH price at the profit house). A drop recipe without an AH price shows "+?". No profit anywhere in the view.
- Hover: "Main stats  +3 AGI +2 STA  vs  +1 STR", "Learn first (skill N)" with the sources, "Cost to obtain" with reagents, learn and total.
- Check: `C_Item.GetItemStats` uses the keys `ITEM_MOD_STRENGTH_SHORT`, `ITEM_MOD_AGILITY_SHORT`, `ITEM_MOD_INTELLECT_SHORT`, `ITEM_MOD_SPIRIT_SHORT`, `ITEM_MOD_STAMINA_SHORT` in the Forever client (else the inline stats stay empty). Spirit is shown because it is a base attribute in Forever; say if it should go.
- Check: `C_PlayerInfo.CanUseItem(itemID)` returns false for armour/weapon types the class can't use (e.g. plate on a hunter) and true otherwise, also for items not cached yet. If it returns false for usable items, every row disappears: report it.
- Items the client hasn't loaded are requested and appear about half a second later (GET_ITEM_INFO_RECEIVED).

### General / AH section (#50)
New file `UpgradeSearch.lua`: **full game restart** needed, `/reload` is not enough.
- Upgrades view: "Craftable" / "General / AH" buttons next to the search box. General / AH shows a "Search AH" button on the right (dimmed while the AH is closed; clicking it then only prints "Open the auction house first").
- At an auctioneer, click Search AH once. The summary counts "Searching the AH: n/15 <slot>..." through Head, Neck, Shoulder, Back, Chest (incl. robes), Wrist, Hands, Waist, Legs, Feet, Ring, Trinket, Off hand (shields, held in off-hand), Weapon (one-hand, two-hand, main/off hand), Ranged (bow, gun, crossbow, wand, thrown). It ends with "AH gear search done." Nothing more is sent after that, and nothing is sent without the click.
- Check: no error and no "action blocked" for the searches after the first (they are sent from AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / AUCTION_HOUSE_THROTTLED_SYSTEM_READY, not from the click). If the client blocks them, report it: the search would have to become one click per slot.
- Check: the server honours `itemClassFilters` with `classID` + `inventoryType` and no `subClassID` (e.g. the Back search returns cloaks only). It doesn't matter for correctness, because rows are filtered by equip slot anyway, but without it the results are mostly other gear.
- Check: `maxLevel` = your level keeps out items you can't wear yet. Sort "Level" descending puts the highest item levels first. Up to 3 extra result pages per slot are requested (`RequestMoreBrowseResults`).
- Check: `itemKey.itemLevel` in browse results is the item level (rows show "ilvl N"), and random-enchant items ("of the Monkey") come with a non-zero `itemSuffix` (row says "random enchant"; its inline stats are left out because only the base item's stats are known).
- Rows: item, slot, ilvl, main stats, "N listed · 2h ago", REPLACES with the equipped item and its stats, gain, TOTAL COST = lowest buyout at the profit house. Plate on a class that can't wear it, or lower item level than what you wear, is not listed. Searched at a neutral house while the profit house is your faction's: "not seen at Horde AH".
- `/craftwise market <itemID>` on an AH gear item found this way shows only "last" (no cheapest tiers, no typical). In `CraftWiseMarketDB.scans` the run shows as kind "gear".
- Closing the AH mid-search stops it: "AH gear search stopped ... (n of 15 slots searched)", with the rows found so far kept. The summary says "(stopped)".
- Right-click dismisses / restores, as in Craftable. While our search runs, Blizzard's browse list shows our results; that is expected.

## Music (#17)
- `CraftWise_Music` made with `tools/music_split.py`, game restarted: Music tab shows the songs count.
- Click a profession: a picker lists "No music" and every song with Play/Stop preview, plus Resume / From the beginning. Escape or X closes it and stops the preview.
- Skinning: music starts with the cast and stops when the cast ends (also when interrupted by moving). Next skin continues from the same part (resume) or from the start (restart).
- Pressing another ability during a cast doesn't stop the music.
- Resume plays 1-2 s chunks (small gaps possible); start over and Party play `full.ogg` continuously and loop.
- Channel is Master: master volume applies, game music keeps playing underneath (turn it down in Sound settings if needed).

## Learning a recipe (#3)
- Buy a recipe at the trainer with the CraftWise window open: it leaves the Learn view right away (no profession reopen). Which event fired is not logged; if it does not update, report it.
- Song file by name: put `x.mp3` in `AddOns/CraftWise_Music/Songs/`, restart, picker -> type `x.mp3` -> Add. A wrong name says "Not found". Check that the existence probe is silent (it is stopped at once) and that PlaySoundFile returns false for a missing file in Forever.

## Video window (#19)
- After `tools/video_frames.py` and a restart: picker shows the video under "Video"; Play opens a small window that animates; Stop / closing the picker hides it.
- Choose it for a profession, cast: window shows and animates, hides when the cast ends, continues from the same frame next cast. Drag to move; position is kept.
- Check: TGA sheets load (no green/black squares), no stutter when switching sheets.
- Volume (picker, - / +): songs play on the Dialog channel; its volume is set while a song plays and put back after. Check Sound settings > Dialog volume is unchanged after fishing/skinning, and after /reload during a song. NPC voices play at the profession volume while a song plays.

## Party key (#20)
- Esc > Options > Key Bindings > AddOns > CraftWise: "Party: music, video and dance" listed; bind a key (needs a game restart once for Bindings.xml).
- Key / `/craftwise party` / "Party!" button: character dances, Party song + video start. Same key stops; walking stops. Check DoEmote works from an addon in Forever.

## Bag sort (#12)
- Bags view > "Sort bags": kept items, quest items and reagents first (by item type, then item ID - the same order every time), free slots, items to sell last (best value first, junk at the very end). Right after login it first loads item data ("Loading item info..."); a second click must say "already in order", also after a restart. Chat says "Bags sorted (N moves)". Click again: "already in order".
- Profession bags / quivers untouched. Stacks of the same item are not swapped (they would merge).
- Entering combat during the sort stops it; holding an item on the cursor stops it.
- Check: dropping onto an occupied slot swaps the two items (no item left on the cursor).

## Junk (#12)
- Bags view: click a row -> menu Keep / Junk / Normal (current one highlighted). Junk shows red "Junk".
- In the game bags / Bagnon / Baganator: middle-click an item (default) -> same menu at the cursor; nothing else happens (bag buttons only listen to left/right). Settings: Middle click / Alt + right / Off. Click elsewhere or Esc closes the menu.
- Merchant window: "Sell junk (N)" button left of Blizzard's sell-all-junk button. One click sells every marked stack, ~5 per second; chat prints count and money. Closing the merchant stops it.
- Loot the same item again: it is junk right away. Sort bags puts junk at the very end.
- Check: button position on the Forever merchant frame; UseContainerItem sells (doesn't equip/use) while the merchant is open.
- AH rule: Bags view top right "AH rule: +20%, min 10c" opens a panel: "At least this % more" (5% steps) and "And at least this much more" (0, 1c, 2c, 5c, 10c ... 1g); example line updates; "Defaults" resets. Items under the rule show "Vendor  AH +Xc, too little". Also `/craftwise ahmin <percent> [copper]`. Since #157 the panel is gone: Settings › AH rule (gear in the main window header), same steps, example and Defaults; `/craftwise ahmin` opens it.
- First AH sale of a single cheap item: check the mail amount to learn how the 5% cut rounds (single 8c item -> 7c or 8c).

## Level view (#15)
- New file: full game restart. "Level" button between Learn and Upgrades; profession tabs at the top.
- Rows: known recipes that still give points (grey hidden), best "per skill-up" first. Chance shows % and where it comes from (orange: always / your crafts x/y / all your crafts of this profession x/y / ~% estimate from the community formula when fewer than 5 crafts are recorded for that stage).
- Hover: thresholds, chance source, reagents, sale (AH after cut or vendor), net, crafts per point, per skill-up.
- Craft a recipe: the view updates (skill and chances) without reopening.
- Check: the skill in the summary matches the profession window; soulbound outputs use vendor price.

## Chance in the profession window (#15)
- New file: full restart. Open a crafting profession: learned yellow/green/orange recipes show a % at the right of the row (green = measured / orange 100%, light orange "~" = formula estimate). Grey and unlearned rows show nothing.
- Hover a recipe: "CraftWise: skill-up chance" line with where it comes from.
- Craft: the % updates after the skill-up settles. Long recipe names don't run under the %.
- Check: no Lua errors / taint when crafting from the window, scrolling, switching professions.

## Sell on AH mark (#12)
- [ ] Middle-click an item in the bags > "Sell on AH": Bags view shows "Auction  marked", tooltip shows "Marked: Sell on AH".
- [ ] Junk shows a red X (not the coin), so it differs from the AH icon. Small auctioneer icon in the top-left corner of the item in Blizzard bags, Bagnon and Baganator (Baganator: Settings > Icons, if the corner is taken).
- [ ] Sort bags: AH-marked items come first in the selling part, junk last.
- [ ] Keep or Junk on the same item removes the AH mark; quest items can't be marked.

## Used in (crafting materials)
- Bags view: "USED IN" column (e.g. "Leatherworking 72 · Tailoring 6"): green = you know a recipe with it, white = your profession, grey = other profession. Disenchant column replaced (values still need #11; "can be disenchanted" stays in the row note).
- Tooltip: "Used in N recipes" grouped by profession: known / learn at X / other profession, up to 4 per profession.
- "My crafting materials" filter: only items used by your professions.
- Item menu > "Recipes using this": Profit view of that profession, unlearned shown, search = item name (search also matches reagent names now).
- Junk icon: items marked Junk show the coin icon in the Blizzard bags and in Bagnon (needs a restart once: BagIcons.lua). Unmarking removes it. With Scrap disabled, only CraftWise junk (and Bagnon's own grey-item coin, if "glowPoor" is on) shows it.

## Item tooltip section
- Any item tooltip (bags, Bagnon, links, merchant): a "CraftWise" header (blue) with: Marked (Junk/Keep), Sell xN (Vendor · AH · advice), Used in, Your crafts (skill-ups for items you craft). Not added twice inside the CraftWise window.
- Gear button (top right of the CraftWise window) or `/craftwise settings`: on/off, Always / Only with Shift (tooltip redraws when Shift is pressed), each line on/off. Since #157: Settings › Tooltips (the gear in the main window header).
- Check: TooltipDataProcessor post-call works for bag items in Forever; GameTooltip:RefreshData redraws on Shift.

## Market recorder (#26 phase 1)
New file and new SavedVariables: full game restart. Nothing changes in the profit numbers yet; `/craftwise market <itemID or link>` is the only output. Saved data is `CraftWiseMarketDB` in `WTF/Account/<account>/SavedVariables/CraftWise.lua` (copy it only with the game closed).

House detection:
- [ ] At the AH in Orgrimmar and Thunder Bluff, search an item you carry: `/craftwise market <id>` lists it under "Horde AH".
- [ ] Same at Booty Bay, Gadgetzan and Everlook: it lists under that town, and the Horde AH line is unchanged. If it lands under "Horde AH", the zone text differs from `NEUTRAL_ZONES` in `Market.lua`: run `/dump GetRealZoneText(), GetSubZoneText()` there and report it.
- [ ] `/dump GetRealmName()` still returns the ruleset name ("PvP"), and `CraftWiseMarketDB.houses` has `PvP|H` and `PvP|N:BootyBay` style keys.

What can be seen from other addons' scans:
- [ ] Auctionator Full Scan: `/craftwise market <id>` for a reagent shows "cheapest: 3 @ ... · 25 @ ..." and `CraftWiseMarketDB.scans[<house>]` ends with `kind = "full"`, `source = "auctionator"`. This proves a second addon receives `REPLICATE_ITEM_LIST_UPDATE` and can read the list.
- [ ] The game doesn't stutter during or after the scan. The scan log's `items` is about the number of scope items on sale.
- [ ] Close the AH during a full scan: no new `kind = "full"` entry and no "disappeared" count from it.
- [ ] One scan is one log entry (the event doesn't fire twice in a way that stores it twice).
- [ ] Auctionator shopping search and Blizzard's own search, for a commodity and for gear: one new point each, not one per event.
- [ ] Blizzard browse list: only `last` changes (no tiers line change) for items in scope.

Prices:
- [ ] A stack of gear or other non-commodity with quantity above 1: compare the Blizzard list with `/craftwise market`. `buyoutAmount` is treated as per unit in searches, and the full scan divides by stack. Both must give the same unit price. If not, report it: searches would then need dividing too.
- [ ] Random-suffix gear ("of the Bear"): `/craftwise market <link>` lists `item <id>:<suffix>`, and two suffixes of one item stay apart. Check the same key from a search and from a full scan.
- [ ] Gear not yet in the item cache right after login, full scan: it appears after the scan (links load within 5 s) or stays out, never under a wrong key.

Scope:
- [ ] Loot something new, buy from a vendor, take something from the bank: `CraftWiseMarketDB.scope.items[id]` is true after `/reload`.
- [ ] Bank: `Enum.BagIndex` covers the bank on this client (bank items enter the scope when the window opens).
- [ ] Items from your professions, known or not, are in scope after login. Engineering and Mining items too, without an alt logged in.
- [ ] Loot during combat raises no Lua error (chat payloads can be secret values on 12.x).

History and size:
- [ ] Three days after the first scan, `/craftwise market` shows `typical: ...` instead of "too little history". Today's scans count once the AH has closed.
- [ ] Check an item with many small listings (a popular herb): the typical is near where most units sit, not at the 8th tier.
- [ ] After a week of use: size of `CraftWise.lua`, and login and `/reload` time compared with before. The test budget is 5 MB at the expected load.
- [ ] Open and close the AH several times: no stutter on close. Right after login a prune runs over about 3 seconds (20 entries per frame).

## Market display (#26 phase 2)
`/reload` is enough (no new file). Needs a few recorded scans first (phase 1 above).

Settings (gear button or `/craftwise settings`), "Profit prices": Since #157: Settings › Prices on the Settings page.
- [ ] Basis Typical / Current lowest and the four house buttons render without overlapping; the first house button says "Horde AH". Houses with nothing recorded are greyed, don't select, and are listed after "No data yet:".
- [ ] Switching basis or house updates the open CraftWise window at once; the second summary line says "Auction prices: typical · Horde AH, else Auctionator (house unknown)" with the chosen basis and house.

Profit view:
- [ ] Row tooltip, Reagents: each AH price is labelled "typical · Horde AH", "current lowest, too little history · Horde AH" (until 3 days of history) or "Auctionator (house unknown)" for items CraftWise hasn't recorded.
- [ ] Row tooltip, "Auction houses" section: one line per reagent at the profit house with "best for N" (N = one craft), then the crafted item with its figures, Best to sell and the other houses.
- [ ] Select Booty Bay: crafted items sold at the AH show "cut unverified" in the PROFIT column and "gross, cut unverified" in the tooltip; the summary counts them separately. Back on Horde AH, profit after 5% returns.
- [ ] "thin market" (orange) appears in a row's status line when a reagent or the crafted item has a thin cheapest tier at the profit house. Compare with the AH list: the cheapest tier holds under one stack or under 10% of the units within +10% of min.
- [ ] Level view: the sale line names the house and cut ("AH after 5% cut" plus the label); at Booty Bay it says the AH sale is not counted because the cut is unverified.

Item tooltip (bags, links):
- [ ] Line "Auction prices per house" (on by default, can be turned off in Settings): profit house with typical or "too little history (n of 3 days)", Current (min, units, price levels for commodities / listings for gear, seen ... ago), Cheapest tiers, Within +10% of min, Last 7 days, thin warning, Best to buy, Best to sell (gross, cut unverified) and each other house in one line.
- [ ] `C_Item.GetItemMaxStackSizeByID` returns the stack size for a reagent (e.g. Light Leather) so "price levels" and the stack part of the thin rule show. Right after login, items not cached yet show no count until hovered again.
- [ ] Items never seen at an AH add no market lines. Alliance AH data from an Alliance alt never shows on a Horde character.
- [ ] Memory: open the CraftWise window on a big profession, then `/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("CraftWise"))` before and after. Reading prices unpacks the entries it touches until the next prune (AH close or login).

## Profit house for every AH value, cut source (#40)
`/reload` is enough (no new file). Needs recorded prices for a few items (see Market display above).

- [ ] Bags view, AUCTION column: with Settings "Auction house for profit" = Horde AH and basis Typical, the value matches the profit view's price for the same item after 5%. Switch basis to Current lowest: the column changes at once. Row tooltip: "Auction, after cut" and a line like "typical · Horde AH · 5% cut (confirmed)".
- [ ] Select Booty Bay: Bags items priced there show "cut ?" in the AUCTION column (not counted, vendor advised); the row tooltip says "<gross> gross, cut unverified". Items CraftWise never saw show the Auctionator value labelled "Auctionator (house unknown)" with "5% cut (house unknown)"; items with nothing show "-".
- [ ] Item tooltip (bags, links): "Sell: Vendor X · AH Y" is followed by a line "AH price | typical · Horde AH · 5% cut (confirmed)", or "no price data". At Booty Bay: "AH ?" with "gross ... · cut unverified". The advice (Vendor / Auction) follows the AH rule on the net price at that house.
- [ ] AH rule panel: change the percent or copper, then compare two items near the threshold: the advice flips on the profit house's net price, not Auctionator's. Since #157: Settings › AH rule.
- [ ] Learn view, a recipe sold on the AH (no trainer or vendor): "To learn" shows the AH price and a second line with its label ("typical · Horde AH"); "Where to get it" lists "AH: ..." with the same label instead of "Auctionator". Switch house or basis: the price follows.
- [ ] Profit row tooltip "Sells for" and the Level view sale line show "5% cut (confirmed)" in grey, no orange.
- [ ] Disenchant value: still hidden until the disenchant data exists (#11); when it does, the Bags row tooltip lists each material's price label and cut text.
- [ ] Phase 3 (#26) once a cut is measured: "N% cut measured (n sales)" replaces "(confirmed)"; a measurement that differs from 5% shows both ("..., differs from 5% confirmed") in orange.

## Baganator
- Baganator settings > junk: "CraftWise" listed (auto-selected if no other plugin is active); marked items show Baganator's junk coin; marking/unmarking refreshes at once.
- Baganator settings > sorting: "CraftWise" mode; Baganator's sort button sorts the backpack like Sort bags (bank untouched).

## Source recorder (#37)
Needs a full game restart after the update (new file in the TOC). Data is `CraftWiseDB.sources[<recipe item ID>]` in `CraftWise.lua`.
- [ ] Recipe vendor (e.g. a cooking or leatherworking supply vendor): open the merchant. `sources[<item>].vendors[<npcID>]` has the NPC name, zone, subzone, price and (if the item is limited) `limited`. The Learn view shows the line with "seen by you just now"; the "Source not known yet" status for that recipe is gone.
- [ ] Same vendor again with a changed price (or reopen): one entry, `t` updated, no duplicate.
- [ ] `faction` on the vendor and the quest NPC: set only when `UnitFactionGroup("npc")` / `("questnpc")` returns Horde or Alliance for an NPC. If it is nil for NPCs, that is fine; if it returns your own faction for a neutral NPC, report it (wrong data).
- [ ] Vendor selling for tokens/currency or items: `costs` lists name and amount.
- [ ] Looted recipe: kill a mob that drops a recipe, open the loot window. `loot["Creature:<id>"]` has `n = 1`, zone, and the name (target or mouseover). Close and reopen the same corpse: `n` stays 1. Another corpse: `n = 2`. No drop chance anywhere.
- [ ] **`GetLootSourceInfo` exists in Forever and returns the corpse GUID** (`/dump GetLootSourceInfo(1)` with a loot window open). If it is nil, nothing is recorded; report it.
- [ ] A recipe from a chest or object: `loot["GameObject:<id>"]` is recorded, name stays empty (no unit to read it from) and the Learn view shows "Drop: GameObject #<id>".
- [ ] Quest reward: open a quest (and then the turn-in) with a recipe as reward or choice. `quests[<questID>]` has the title, zone, `choice = true` for a choice; one entry for both dialogs.
- [ ] Looting during combat raises no Lua error (GUIDs can be secret values).
- [ ] Hover the recipe in the Learn view: every line in "Where to get it" ends with `[seen by you 2h ago]` or `[bundled data]`/`[QuestieDB]`.

## Profession filing (#44)
`/reload` is enough (no new file). Back up `WTF/.../CraftWise.lua` first if the "?" tab or Cooking-under-Leatherworking is currently there, to see the clean-up work on real data.
- [ ] After `/reload`: the "?" 0/0 tab is gone, and Leatherworking's Level, Profit and Learn views list no Cooking recipes (Roasted Kodo Meat, Coyote Steak, Longjaw Mud Snapper). `/craftwise debug` shows sane recipe counts per profession.
- [ ] Open Cooking, then Leatherworking, then switch back and forth a few times (also with the window open while switching): Leatherworking's Level view shows only Leatherworking recipes, Cooking's only Cooking recipes, and no "?" tab appears.
- [ ] First Aid (if learned): the tab keeps its recipes after opening and closing the window; nothing moves to another tab.
- [ ] Level view tooltip of a yellow/green recipe: "crafts of all recipes of this profession in the ..." counts only crafts from that profession (craft a few Cooking items and check a Leatherworking row's n does not change).

## Fast auto-loot (#41)
Needs a full game restart (new file in the TOC). Settings, "Fast auto-loot" (default on).
- [ ] Solo mob with auto-loot on in the game options: right-click the corpse, everything is taken at once, no loot window.
- [ ] Recipe drop: `sources[<item>].loot["Creature:<id>"]` is recorded even though the window never shows. `/dump GetLootSourceInfo(1)` at a hand-opened window tells whether the function exists (see Source recorder).
- [ ] Source fallback: if `GetLootSourceInfo` is nil, the same record appears with the corpse as source (dead mouseover or target at `LOOT_READY`). Report if the creature ID is wrong.
- [ ] Hold the auto-loot toggle key (Shift by default): the window stays open and nothing is taken. With auto-loot off in the options, the same key makes CraftWise loot.
- [ ] #57 (`/reload` is enough for this fix): Shift + right-click and let go of Shift right away (before the window would appear): the window still stays open and nothing is taken. CraftWise now follows the `autoloot` payload of `LOOT_READY` (the client's decision at click time). To see the payload: `/run local f=CreateFrame("Frame") f:RegisterEvent("LOOT_READY") f:SetScript("OnEvent",function(_,_,a) print("LOOT_READY autoloot", a) end)`, then loot with and without Shift: it prints `true`/`false`. Report if it prints `nil` (then the fallback below decides).
- [ ] `/dump C_CVar.GetCVarBool("autoLootDefault"), IsModifiedClick("AUTOLOOTTOGGLE")` return a boolean each (the fallback rule uses them when the payload is missing).
- [ ] Full bags: coins are taken, items stay in the window, one message "Bags are full. Left in the loot window: ...". Also try with only a partial stack of the dropped item left in the bags (CraftWise leaves it when no slot is free).
- [ ] A bind-on-pickup item asks Blizzard's confirmation; nothing is confirmed for you.
- [ ] Group (loot method group/need before greed): rolls and locked slots are untouched. Master loot: CraftWise does nothing. `Enum.LootMethod.Masterlooter` exists (UNVERIFIED name): `/dump Enum.LootMethod`.
- [ ] Fishing and chests loot too.
- [ ] SpeedyAutoLoot enabled: CraftWise prints its one-time note and does not loot; Settings shows the checkbox dimmed. Without it, no double looting.

## Sale options in the profit view (#48)
`/reload` is enough (no new file).
- Profit view: the "Sells for" cell shows the value plus `vendor` or `AH` (orange `AH gross` where the house's cut is unverified). Light Leather Pants with a vendor price above the AH net shows `5s 99c  vendor`.
- Hover a row: under "Sells for" two lines, "Vendor  5s 99c (no cut)" and "AH net  x (gross y, 5% cut (confirmed), typical · Horde AH)"; the one "Sells for" uses is green with "(used)". Items without AH data say "no price data"; items vendors don't buy say so.
- The cell fits in its column with gold amounts (e.g. `12g 34s 56c  AH`); if it is cut off, report the width.

## Reagent balance and buy list (#49)
New files (`Holdings.lua`, `Balance.lua`): **full game restart** needed, `/reload` is not enough.
- Profit view, hover Light Leather Pants with 60 Cured Light Hide and leather for 8 pants: "Your reagents" lists each reagent with "hold N  X crafts", "Crafts possible 8", the orange line "Light Leather limits you to 8 crafts; you hold Cured Light Hide for 60.", then "To buy for 60 crafts" with quantity, cost and vendor / AH (house) per reagent, and a total.
- Ruined Leather Scraps in the bags count toward Light Leather ("made from what you hold"), Light Hide + Salt toward Cured Light Hide, only when you know those recipes.
- Same section in the Level view tooltip.
- Track the recipe in the profession window, then hover Cured Light Hide or Light Leather in the bags: "Tracked  Light Leather Pants" with the same lines. Settings > tooltip lines has "Tracked recipe: reagents you hold" to turn it off.
- Counted places: open the bank once, then the mailbox; the tooltip line "Counted" lists bank and mail with their age. Check that the bank count matches what is in the bank: CraftWise reads the containers named `CharacterBankTab_N` (or `Bank` / `BankBag_N`) in `Enum.BagIndex`. If the bank shows up as counted but items in it are missing, report `/dump Enum.BagIndex`.
- Mail: items in letters count (`GetInboxItem`); taking an item out of a letter moves it to the bags count without doubling.
- Account bank tabs, when the client has them, show as "Not counted: account bank (not read)".
- The result is cached until the bags change (`BAG_UPDATE_DELAYED`), the bank or mailbox is scanned, or recipes change: loot an item while hovering, hover again, the counts follow. Hovering the same items repeatedly should not stutter.

## Ledger (#46)
Needs a full game restart (new file `Ledger.lua` in the TOC). Saved in `CraftWiseMarketDB.ledger` (`entries`, `chars["<realm>-<name>"]`).
- [ ] Vendor, right-click buy (e.g. 5 Salt): one `entries` row `k = "vbuy"`, `q = 5`, `m` = the merchant's price, `w` = the merchant's name. Same with a split stack (Shift-click, enter 3) and with a drag from the merchant onto a bag slot (that path calls no `BuyMerchantItem`).
- [ ] Vendor sale by right-click and by dragging an item onto the merchant: one `k = "vsell"` row each, `m` = the money received. "Sell junk" with several stacks: one row per item, and their sum equals the money change.
- [ ] Buyback: sell something, buy it back from the buyback tab: one `k = "buyback"` row; `/craftwise ledger` shows the item with sold 0 and received 0. `/dump GetNumBuybackItems()` returns a number at a merchant (legacy function, allowlisted from Blizzard's MerchantFrame.lua).
- [ ] Repair All (and repairing a single item): no row; `/craftwise ledger` lists the repair under "not from logged trades".
- [ ] A slow server: buy at a vendor with high latency; the row still appears (money and bag events are paired within 1.5 s). Report any purchase that was missed.
- [ ] AH commodity (e.g. 10 Light Hide): one `k = "ahbuy"` row, `q = 10`, `m` = the total shown in Blizzard's buy dialog, `w` = the house key (e.g. `<realm>|H`). Let a purchase fail (price changed): no row. Same with Auctionator's buy screen (it calls the same functions).
- [ ] AH item buyout (gear or a recipe): one row with `q` from the auction and `m` = the buyout. A bid without buyout: no row.
- [ ] Where AH purchases land (bags at once, or the mailbox): either way `/dump CraftWiseMarketDB.ledger.chars["<realm>-<name>"].pos[<itemID>]` shows `transit` back at 0 once the units are in the bags, and `known` = the units bought.
- [ ] `pos[<itemID>].held` matches bags + bank right after login, with the bank closed (`C_Item.GetItemCount(id, true, false, true)` must count the bank from the cache). If it drops at login and comes back when the bank opens, report it: the paid cost would turn partial (`N of M units`).
- [ ] `/craftwise ledger login`, `/craftwise ledger today` (per-day rows), `/craftwise ledger all` (since last reset), `/craftwise ledger reset`: start money, spent/received per item, net. With only trades in the session the line says "net matches the money change"; a quest reward or loot money shows as "not from logged trades". `/craftwise ledger` alone repeats the last view.
- [ ] `/reload` keeps "since login"; a relog starts it again. A session over midnight: the new day's start money is the money held at midnight (taken at the first money change after it).

## Reagent cost basis, craft or buy (#47)
`/reload` is enough on top of #46 (no new file; #46 itself needs a restart).
- [ ] Leatherworking with Cured Light Hide learned: hover Light Leather Pants in the Profit view. The Cured Light Hide line says `crafted` when Light Hide + Salt are cheaper than Cured Light Hide at the AH, and the line under it shows both values: `each: crafted 1s 55c · bought 2s typical · Horde AH`. When the AH is cheaper it says `bought: ...` with the same two values.
- [ ] The Cost column of rows using an intermediate drops accordingly; the Cured Light Hide row itself still prices Light Hide and Salt as bought.
- [ ] An intermediate whose recipe you have not learned (or that only an alt knows) is always bought.
- [ ] Settings (gear), "Reagent cost": switch Profit to "Paid cost". The summary line says `reagents: paid cost, else AH (N rows with reagents at AH)`; the reagent tooltip header says the same. Buy a reagent at a vendor: its line now shows `paid cost, <n> held` and the row updates without reopening the window. Reagents you never bought show their AH/vendor price with `no paid cost`. Since #157: Settings › Prices, "Reagent cost · Craft / Learn / Level up / Upgrades".
- [ ] Partial paid cost: hold a few units of a reagent from before the log, buy more at a vendor. The line shows `paid cost, <bought> of <held> units` at the average of the bought units, and under it `average of the <n> units you bought; <m> held have no recorded price`.
- [ ] Intermediate with a paid cost (Paid cost basis): buy Cured Light Hide, then hover Light Leather Pants. Its line shows `paid cost, <n> held` even if crafting it would be cheaper, and no `each: crafted ... · bought ...` line. Without a paid cost it is craft-or-buy as above; a crafted line whose reagents partly lack a paid cost says `some of its reagents have no paid cost (AH)`.
- [ ] The other views (Learn, Level, Upgrades) keep their own setting.
- [ ] Opening the Profit view of a large profession (all recipes, "include unlearned") with craft-or-buy is not noticeably slower than before. Report a stutter.

## Item names in chat (#59)
`/reload` is enough (no new file).
- [ ] Buy and sell something at a vendor, then `/craftwise ledger login`: every item is a clickable link (click opens the item tooltip). `/dump CraftWiseMarketDB.ledger.entries[#CraftWiseMarketDB.ledger.entries]` shows `n` (name) and `l` (link).
- [ ] An item not in the client's cache (e.g. Salt or a grey sold in an earlier session, after a full restart, before hovering it anywhere): `/craftwise ledger` prints within a moment with the item's name or link, never `item <id>`. Old entries from before #59 (no `n`) get their name after the first such print.
- [ ] If the ledger takes noticeably long to print (it waits up to 2 s for item data), report it.
- [ ] `/craftwise market <itemID>` of an item you haven't seen this session: the header is the item's link; a suffix variant shows `<link> (item <id>:<suffix>)`.
- [ ] Item menu "Recipes using this" on an item none of your professions uses: "<item> is not used by your professions." shows the item as a link.

## Buy list: craft or buy for intermediates (#60)
No new files: `/reload` is enough.
- [ ] Profit view, Light Leather Pants with leather and thread for 2 crafts and no Cured Light Hide, Cured Light Hide on the AH above Light Hide + Salt (cost line says "crafted"): "To buy for 2 crafts" shows "Craft 2 × Cured Light Hide  each: crafted 1s50 · bought 1s80 ...", then "2 × Light Hide" (AH, house) and "2 × Salt" (vendor), no "2 × Cured Light Hide" line, and a total of 2 × the crafted cost (when the AH tiers match the price the cost line uses).
- [ ] Light Hide or Salt in the bags: the held units are used first, only the rest is on the list.
- [ ] Cured Light Hide cheaper on the AH than crafting (cost line "bought"), or the Cured Light Hide recipe not known: the list buys Cured Light Hide as before.
- [ ] Settings, cost basis "Paid cost" for a view, holding 1 Cured Light Hide with a recorded paid cost and short of 1: the cost line shows the paid cost, but the buy list still crafts the missing one at market prices (Scout decision on #60: the buy list always decides on the AH basis).
- [ ] Tracked recipe tooltip (hover a reagent in the bags): same buy list as the Profit view.

## Character snapshot for Claude (#63)
New file `Snapshot.lua` in the TOC: **full game restart** needed (not `/reload`). Field reference: `docs/snapshot.md`.
- [ ] `/craftwise snapshot` prints `snapshot saved, /reload to write it to disk` and no second line. A second line `not in this snapshot: ...` names sections the client didn't give: report which and why (`/dump CraftWiseDB.snapshots["<realm>-<name>"].skipped` and `.errors`).
- [ ] `/reload`, then open `WTF/Account/<account>/SavedVariables/CraftWise.lua`: `["snapshots"]` has `["<realm>-<name>"]` with `t` = now. Log out instead of `/reload`: `t` moves to the logout time (refresh on `PLAYER_LOGOUT`).
- [ ] `char`: level, XP, rested XP, money and guild match the character frame and XP bar tooltip. `guild` is `false` on a character without a guild.
- [ ] `location`: zone, subzone and map name are right; `x`/`y` × 100 match the world map coordinates (a coordinates addon, or `/dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")`). In a dungeon `x`/`y` are missing, no error.
- [ ] `equipment`: every worn slot has `link`, `ilvl`, `armor`, `stats` like the item tooltip, `dur`/`durMax` like the tooltip's Durability line. Check whether Tabard and Ranged are listed (a slot the client doesn't know is skipped).
- [ ] `professions`: primary and secondary professions with the skill shown in the spellbook. A gathering profession without a window (Herbalism, Skinning) shows with `cached = false`.
- [ ] `quests`: every quest of the log with title, level, zone header, objectives and counts as in the quest log; a quest ready to turn in has `complete = true`. Collapse one zone header in the quest log, snapshot again: that zone's quests are missing, the header is in `collapsedHeaders`, `read` < `inLog`, and the header is still collapsed afterwards (the snapshot must not expand it).
- [ ] `reputations`: factions with the standing label and value as in the reputation pane; collapse a header: its factions are missing, the header is listed and stays collapsed.
- [ ] Hunter with pet out: `pet` has name, family, level, happiness (1-3, as the happiness icon) and loyalty text. Pet dismissed: `pet` missing, `skipped.pet = "no hunter pet out"`. Report if `C_PetInfo.GetPetLoyalty` returns nothing.
- [ ] `holdings`: bag counts match the bags; `bank`/`mail` appear after opening the bank/mailbox once, with their `t`.
- [ ] `ledger.today` / `ledger.reset` totals match `/craftwise ledger today` / `/craftwise ledger all`.
- [ ] Logout and `/reload` don't take noticeably longer than before; no Lua error on logout (BugSack keeps it for the next login).
- [ ] The file has nothing about other players (party members, whisper partners, guild members).

## Profession skill refresh without the window (#65)
No new file: `/reload` is enough.
- [ ] After `/reload`, without opening any profession window: `/craftwise debug` lists every profession of the spellbook, Fishing and gathering ones included, with the skill and max shown there (Fishing and gathering professions with 0 recipes cached).
- [ ] Learn Expert (or Journeyman) of a profession at a trainer, then open `/craftwise` without opening the profession window: the tab shows the new cap (e.g. `Cooking 150/225`). Same at once if the CraftWise window was already open.
- [ ] Catch a fish that gives a skill point: `/craftwise debug` shows the new Fishing skill; `/craftwise snapshot` then `/reload`: `professions` has Fishing with that skill, `cached = false`.
- [ ] Fishing, Herbalism, Mining and Skinning get no tab. A profession whose window was never opened (e.g. First Aid) gets its tab only after opening the window once, as before.
- [ ] Open a profession window afterwards: `/craftwise debug` lists that profession once, not twice, with its recipes.
- [ ] Weapon skill-ups in combat (they also send `SKILL_LINES_CHANGED`) cause no stutter.

## Merchant recorder and "who sells X" (#66)
New file `Merchant.lua` in the TOC: **full game restart** needed (not `/reload`).
- [ ] Open any vendor (e.g. a fishing supplier), then `/dump CraftWiseDB.merchants[<npcID>]` (NPC ID from the GUID, `/dump UnitGUID("npc")` while the window is open): `name`, `zone`, `sub`, `map`, `x`/`y` (match the world map coordinates within a few tenths), `group`, `t`, and `items` with every item of every page: `p` = price in copper as shown, `s` = stack size, `n` = -1 for unlimited items.
- [ ] **Faction (unverified):** at Sewa Mistrunner (Thunder Bluff) `faction` = `{ id, name = "Thunder Bluff" }` and `standing` = your standing (6 = Honored). This relies on the NPC's tooltip showing the faction name as a line; if `faction` is missing, hover the NPC and report the tooltip lines (`/dump C_TooltipInfo.GetUnit("npc")` while the window is open). `reaction` is `UnitReaction("npc", "player")`: report whether it equals your standing with the vendor's faction (e.g. 6 at Honored) or stays at 4/5.
- [ ] `items[<itemID>].ps` holds the price per standing: Nightcrawlers at Sewa should show `ps[6] = 90`. A vendor of a faction where you are Neutral (e.g. Orgrimmar at Neutral) selling Nightcrawlers for 1s: `/craftwise where nightcrawlers` ends with "base price seen at Neutral: 1s". If you see the same item at a Friendly vendor, report its price next to the Neutral one (a Friendly discount is not assumed).
- [ ] Limited stock (e.g. Strong Fishing Pole): `n` = the count on the button; `log` has `{ n, first, last, realm }`. Buy one: a new log entry with the lower count. Come back after it restocked: `/craftwise where strong fishing pole` shows "count rose 0 -> 1 between <time> and <time> (within ..., may be another layer)". Forever layers may have separate stock, so a rise is not proven to be a restock: report if counts jump between visits minutes apart.
- [ ] Merchant filter: the window opens on your class filter. `filter`/`full`: switch the filter dropdown to "All": `full = true`, and items hidden by the class filter appear. With the class filter, items not shown are kept (not deleted).
- [ ] A recipe you know: `known = true` (tooltip "Already known"). An item shown in red: `unusable = true`.
- [ ] A currency/token vendor: `c` lists the costs with `currency` or `item` IDs; `p = 0` when only currency is asked.
- [ ] `/craftwise where <shift-clicked item link>`, `/craftwise where 6530`, `/craftwise where nightcrawl`: vendors cheapest first with place, price, standing, stock and age. An unknown item: "no merchant you opened sells ...".
- [ ] Item tooltip (bags or link): "Sold by" with up to 2 merchants and "+N more: /craftwise where". Settings: the "Sold by (merchants you opened)" checkbox turns it off; the Settings panel still fits. Since #157: Settings › Tooltips.
- [ ] Buying several items in a row at a vendor (each fires `MERCHANT_UPDATE`): no stutter.

## Merchant prices per character (#75)
No new file: `/reload` is enough. Needs two characters on the account with different standings with one merchant's faction (e.g. Thunder Bluff: Velikopter Tanner Honored, Velikopter Wright Neutral). Keys include the surname (#77): `"<realm>-Velikopter Tanner"`.
- [ ] On Tanner, open Sewa Mistrunner (Thunder Bluff). `/dump CraftWiseDB.merchants[3027].char` = `"<realm>-Velikopter Tanner"` (with the surname; if it is only `"<realm>-Velikopter"`, report it); `items[6530].pc["<realm>-Velikopter Tanner"]` = `{ p = 90, st = 6, t = ... }`; `items[6530].pk[6]` = the same key.
- [ ] Log Wright in, open the same merchant: `pc` now has both characters with their own price and standing; `char` is Wright's key. `/craftwise where nightcrawlers`: "90c with Velikopter Tanner (Honored), 1s with Velikopter Wright (Neutral) · faction Thunder Bluff", cheaper first. Item tooltip "Sold by": "Sewa Mistrunner · 90c Velikopter Tanner (Honored), 1s Velikopter Wright (Neutral) · ...". A character on another realm shows as "Name Surname-Realm".
- [ ] A third character that never opened Sewa: `/craftwise snapshot` on it (or log out once), then on any character `/craftwise where nightcrawlers`: it shows with "(seen at <its standing>)" only when a price at exactly that standing was seen at Sewa; otherwise it is not listed. Log that character in: its live standing is used (no new snapshot needed). A snapshot kept under an old key without surname (`legacy = true`, #77) is not used.
- [ ] Merchants recorded before this change (no `pc`): `/craftwise where` and the tooltip look as before until a character opens them again.

## Known flight paths in the snapshot (#68)
New file `FlightPaths.lua` in the TOC: **full game restart** needed (not `/reload`). Field reference: `docs/snapshot.md`, `flightPaths`.
- [ ] Talk to a flight master (e.g. Crossroads). Then `/dump CraftWiseDB.debug.taxi`: `nodes` = the number of flight points the map shows, no `why`. If `why` is set, report it (`no taxi map ID`, `flight master listed no nodes`: the client's flight map works differently than Blizzard's Forever UI code suggests).
- [ ] Note which window opened: the newer zoomable flight map or the old flat "Flight Map" frame. Both should record.
- [ ] `/craftwise snapshot`, `/reload`: `flightPaths.maps` has the continent (`mapID` 1414 Kalimdor / 1415 Eastern Kingdoms, `map` name) with `t` = now, and one node per flight point on the map with its name. The one you stand at has `state = "current"`, `current = true`.
- [ ] Compare with the map: are flight points you have **not** discovered missing from `nodes`? (Expected: the flight master lists only known ones.) Each listed node should have `known = true`; report any `known = false` or a missing `known`.
- [ ] `x`/`y` × 100 roughly match the flight point's place on the continent map.
- [ ] Discover a new flight point, open that flight master: the continent's entry has the new node and a new `t`; the other continent's entry is unchanged.
- [ ] Another character: its own `flightPaths` (per character), no mix-up.

## Market scope: recipe items and profession books (#67)
No new files: `/reload` is enough.
- [ ] Auctionator full scan at the Horde AH, then `/craftwise market <itemID>` of Recipe: Mithril Head Trout (link it from the AH or bags): it has a price at the Horde AH, not "not a recorded item".
- [ ] Same for the Expert Cookbook (and Expert First Aid, if listed). If it shows "not a recorded item" after a full scan: `/dump C_Item.GetItemInfoInstant(<itemID>)` and report the 6th and 7th values (class, subclass). CraftWise takes a book only when the client files it as Recipe (9) with the profession's subclass (Cooking 5, First Aid 7, Fishing 9); a "Book" (0) subclass is not recorded and the book IDs then need verified data.
- [ ] A Tailoring pattern (or any profession neither you nor the alt has) is still "not a recorded item" after the scan.
- [ ] Profit view, Learn: a not-yet-learned recipe taught by an item that was on the AH shows "To learn" with the AH price and its label (e.g. "typical · Horde AH", or "current lowest, too little history" in the first days).
- [ ] The full scan still finishes without a noticeable stall (each item outside the scope is checked once per session).

## Fishing log (#69)
New file `Fishing.lua` in the TOC: **full game restart** needed (not `/reload`).
- [ ] Fish a few times with fast auto-loot on (default), then `/craftwise fishing`: the zone and subzone are listed with the number of casts, each caught item with its count and value ("vendor", an AH label, or "no price data"). `/dump CraftWiseDB.fishing` shows one entry per cast with `t`, `zone`, `sub`, `map` and `items`.
- [ ] Same with Shift held (or fast auto-loot off in Settings, or the loot window open by hand): still recorded once per cast, nothing twice.
- [ ] Loot a mob or a chest: no catch is recorded (IsFishingLoot is false).
- [ ] Fish in a pool and in open water and compare `obj` in `/dump CraftWiseDB.fishing`: report whether `obj` is set and whether it differs between the two (the GameObject the client names as the loot source; CraftWise doesn't interpret it yet). If `obj` is always missing, `GetLootSourceInfo` gives nothing for fishing loot.
- [ ] Catch a container (trunk, crate, bloated fish), open it from the bags: `/dump CraftWiseDB.fishing["<realm>-<name>"].opened` has an entry with the container's item ID and its contents. `/craftwise fishing` then values the container by its contents ("contents of 1 opened") if it has no price itself. Coins from a container are not recorded.
- [ ] `/craftwise fishing <zone>` (zone or subzone name, any case) lists only that zone.
- [ ] `/craftwise snapshot`, `/reload`: the snapshot has `fishing` with the per-zone summary (`docs/snapshot.md`).

## Character key with surname (#77)
No new files: `/reload` is enough. Make a backup of `WTF/Account/<account>/SavedVariables/CraftWise.lua` first.
- [ ] Log in with Velikopter Tanner. If the old snapshot under `"<realm>-Velikopter"` is that character's class and race, chat says the ledger, snapshot and fishing log now belong to Velikopter Tanner. Otherwise it says they were kept under the old key, marked legacy (once; not again after `/reload`).
- [ ] `/reload`, then check the file: `CraftWiseDB.snapshots` has `"<realm>-Velikopter Tanner"` with `char.name = "Velikopter"`, `char.surname = "Tanner"`; `CraftWiseMarketDB.ledger.chars` and `CraftWiseDB.fishing` use the same key. Report the exact key (it shows which separator the client's `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR` gives; expected a space).
- [ ] Log in with Velikopter Wright, buy something at a vendor, fish once, `/reload`: Wright has its own `"<realm>-Velikopter Wright"` entries; Tanner's ledger (`/craftwise ledger`) and `/craftwise fishing` are unchanged when you switch back.
- [ ] `/craftwise where <item>` (merchants, #75) shows the standing of the character you are on.

## Subzone text and the line-0 profession (#78)
No new files: `/reload` is enough.
- [ ] Stand in a named place (e.g. Razor Hill, The Crossroads): `/craftwise snapshot`, `/reload`. `location.subzone` is that name and `location.minimapZone` matches the text over the minimap.
- [ ] Stand in the open with no subzone over the minimap: `location.subzone = ""`, `minimapZone` = the zone. If `subzone` is `""` while the minimap shows a place name, report both texts: then `GetSubZoneText` and the minimap disagree on Forever.
- [ ] Fish at a named spot and in open water: `/dump CraftWiseDB.fishing` catches have `sub` with the name, or `sub = ""`; `/craftwise fishing` lists the open-water casts as "(no subzone)".
- [ ] After login the "? 0/0" profession tab is gone, and `/dump CraftWiseCharDB.professions[0]` is `nil`. Open and close every profession window: it does not come back.

## Auction tracker (#81)
New file `Auctions.lua` in the TOC: **full game restart** needed (not `/reload`). Saved in `CraftWiseMarketDB.auctions.chars["<realm>-<name> <surname>"].list`; `/craftwise auctions` prints it.
- [ ] Post a commodity (e.g. 20 Light Leather) with Blizzard's sell tab: one `list` row with `id`, `q = 20`, `unit` = the unit price entered, `kind = "commodity"`, `dep` = the deposit Blizzard showed, `h` = the house key, `durText` ("12 Hours" / "24 Hours" / "48 Hours", whatever the client calls them) and `exp`. If no row appears, `AUCTION_HOUSE_AUCTION_CREATED` didn't fire: report it (`/etrace`, filter AUCTION) — nothing is recorded without it.
- [ ] Post one item with bid and buyout (gear): `bid` and `unit` per item, `kind = "item"`. Post 3 non-stacking items at once (multisell): three rows of `q = 1`. Post a stack of a stackable non-commodity item, if Forever has one: one row, and check `unit` is per item (Blizzard's sell frame totals quantity × buyout).
- [ ] Post with Auctionator's Selling tab too: same rows (it calls the same client functions).
- [ ] Open the AH "Auctions" tab: `ownedAt` is set; rows have `exp` from the list's time left. An auction listed before this version appears with `untracked = true`, `ownedBuyout`: compare `ownedBuyout` with the tab's Buyout column for a stack of more than 1 — is it per unit or per stack? (Untracked rows get no expected payout until that's known.)
- [ ] A sale while online: chat says "A buyer has been found for your auction of X."; the row turns `st = "sold"`, `soldVia = "message"`, and `/craftwise auctions` shows "expected ... after 5% cut (confirmed)" at the Horde AH. Note whether the auction ID came with it (`/etrace`: `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION` third value) and whether `CHAT_MSG_SYSTEM` fired as well; the row must turn sold once, not twice.
- [ ] Two auctions of one item, one sells: the older one is marked, with `uncertain = true` unless the notification carried the auction ID.
- [ ] A commodity auction partly bought: open the Auctions tab; the bought units split off as `sold` ("owned list (quantity dropped)"), the rest stays listed with the lower `q`. Report whether the tab shows a separate "Sold" entry for them.
- [ ] Cancel an auction: `st = "cancelled"`. Let one expire: `st = "expired"` from "Your auction of X has expired."
- [ ] With the AH open on the Auctions tab, an auction that sold while you were offline (or was cancelled elsewhere) and is gone from the list turns `gone` ("sold or cancelled (uncertain)"); one past its expiry turns `expired` with `why` saying it was inferred.
- [ ] Mailbox: take the money of a sale mail (click, Shift-click, Open All): the row turns `settled` with `received` = the money, `sale`, `cut` (house cut), `saleDeposit` as the invoice shows them; `/craftwise ledger` lists it as sold (kind `ahsell`, `w` = the house). `/dump CraftWiseMarketDB.cutSamples[#CraftWiseMarketDB.cutSamples]` has `house`, `listed`, `received`, `cut`, `deposit`. Check `received = listed + deposit - cut` (Blizzard's invoice maths), and report the cut ÷ listed you see.
- [ ] Take a returned item from an "Auction expired: X" mail and from an "Auction cancelled: X" mail: the row turns `returned`. If not, report the mail subjects exactly: the patterns come from `AUCTION_EXPIRED_MAIL_SUBJECT` and `AUCTION_REMOVED_MAIL_SUBJECT`, which Blizzard's Forever UI code doesn't use (`/dump AUCTION_EXPIRED_MAIL_SUBJECT`).
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].auctions` has `active`, `sold` with `expectedTotal`, `returning`, `uncertain`, matching `/craftwise auctions`.
- [ ] Nothing in `CraftWiseMarketDB.auctions` names a buyer.
- [ ] #116: with auctions listed at the Horde AH, `/craftwise auctions` prints "if all listed sell: ... after 5% cut (confirmed)" right after "on its way"; the amount is the sum of the Auctions tab's buyouts minus 5% each. A bid-only listing shows as "not counted: 1 without buyout", one at Booty Bay as "1 with cut unverified". The snapshot has the same numbers in `listedTotal`, `listedNoBuyout`, `listedUnknownCut`.

## Trainer recipes and vendor floor (#83)
No new files: `/reload` is enough.
- [ ] Open the Leatherworking window once, then the Expert Leatherworking trainer (Tarn, Thunder Bluff). `/craftwise debug`: "last trainer: N services, M recorded (K with output and reagents)". K = 0 means `C_TradeSkillUI.GetRecipeSchematic` returns nothing for trainer recipes with the profession window closed: report it with `/dump C_TradeSkillUI.GetRecipeSchematic(1255075, false)` (Mender's Leather Belt).
- [ ] `/reload`, then check `CraftWiseDB.trainer[1255075]`: `fee` (18s = 1800), `required = 150`, `skill = "Leatherworking"`, `line = 165`, `output.itemID` one of 252459-252461 / 252520-252523, `reagents` with counts matching the trainer's recipe tooltip, `at`. Same for the other belts (1255076-1255081). If an entry is missing, `CraftWiseDB.debug.trainer.samples` shows the tooltip ID of the first services.
- [ ] `/craftwise`, Learn view: the seven belts are listed with Trainable at 150 and the fee; the tooltip ends with "Recorded in game at a trainer" and shows "Skill-ups: thresholds unknown" (never yellow/grey numbers).
- [ ] At the AH, run a full scan or search a belt: its price is recorded (`/craftwise market <belt link>` shows data, not "(not a recorded item)").
- [ ] Vendor floor: `/dump CraftWiseDB.sellPrices` has entries after login (scope items). Log out, log back in and hover a scope item in the Bags view before its tooltip loaded: the vendor value shows at once.

## Fishing loot tables (#86)
New file `FishingTables.lua` in the TOC: **full game restart** needed (not `/reload`). Report `/dump` output where asked; everything below depends on what the client shows, nothing is filled in from lists.
- [ ] Loot source: fish once in open water and once from a pool. `/dump CraftWiseDB.fishing["<key>"].catches[#CraftWiseDB.fishing["<key>"].catches]` after each: `obj` and `spawn` set (else `GetLootSourceInfo` gives nothing for fishing loot), and `obj` differs between pool and open water. Report both `obj` values.
- [ ] Clicked object: the same catches have `clk`, and `same = true` for the open-water one (the bobber was both clicked and the loot source). If `clk` is missing with a mouse click: report `/dump UnitGUID("mouseover")` while the cursor is on the bobber, and `/dump C_TooltipInfo.GetWorldCursor()` (does it have a `guid` field?). Repeat with the interact key if you use one (`softinteract`).
- [ ] After one open-water catch with `same = true`, fish a pool: `/craftwise fishing` lists the pool row as "<name> (pool)" or "pool object N (name not seen)", the open-water casts as "open water", and nothing as "water type not known" except catches without a loot source.
- [ ] Pool name: hover a pool before fishing it; after the first catch from it `/dump CraftWiseDB.fishObjects` has its object ID with the name as the tooltip showed it. If the pool stays "name not seen", report the `C_TooltipInfo.GetWorldCursor()` dump while hovering it. Hovering a mailbox or herb stores nothing there.
- [ ] Position: catches have `x`/`y` matching the world map coordinates (percent) within a few tenths.
- [ ] Pool visits: fish one pool until it vanishes, then fish elsewhere: `/craftwise fishing pools` ends with "<pool>: 1 visits ended, N catches per visit (n = 1, ...)", N = the casts that pool gave. Leaving a pool early counts as a short visit (the client doesn't say why a pool is gone).
- [ ] Sightings: after fishing a pool type once, hover another pool of that type without fishing it: `/dump CraftWiseDB.fishing["<key>"].seen` gets an entry with `obj`, `spawn`, `name`, `zone`, `x`/`y`, `how = "tooltip"` (once per pool per 10 minutes). `/craftwise fishing pools` shows "seen N times, K not fished".
- [ ] Find Fish: `/craftwise fishing` second line. Not learned: "not known by this character". Learned (report where it is learned on Forever) and tracking switched on in the minimap tracking menu: "known, tracking on"; off: "tracking off" (updates on `MINIMAP_UPDATE_TRACKING`). Catches made while it is on have `ff = true`.
- [ ] Value per hour: fish for a few minutes; `/craftwise fishing` shows "... per hour (n = <timed>, <minutes> min)" per row. `/craftwise fishing gap 10` changes the session gap (catches further apart start a new session; the first catch of a session is untimed).
- [ ] Filters: `/craftwise fishing pools`, `/craftwise fishing open`, `/craftwise fishing pools <zone or subzone>`, `/craftwise fishing <zone>`.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].fishing` has `spots` (ranked, with `perCatch`, `perHour`, `top`), `pools` and `findFish` (`docs/snapshot.md`). The per-zone item lists of #69 are gone from the snapshot.

## Fishing tab with the local reference (#88)
New files `FishingZones.lua` and `UI\ProfitFrame\Fishing.lua` in the TOC: **full game restart** needed (not `/reload`). Build the reference first (`docs/fishing-reference.md`); the new addon also needs a restart the first time.
Since #156 the Fishing view is Gather › Fishing in the main window (`UI\ProfitFrame\Fishing.lua` is gone): the items below about the profit window's Fishing button and tab are checked in "Gather: Farm, Fishing, Crates (#156)"; the reference and slash command items still hold.
- [ ] Character select > AddOns lists "CraftWise Fishing Reference (local)", enabled, no "missing dependency" or "out of date" warning.
- [ ] `/craftwise`: the header has a **Fishing** button; the view buttons don't overlap the subtitle "Profit, gear, loot, fishing".
- [ ] Fishing: one row per zone (fishing icon), best value per catch first, each with "reference · n = ..." or "own catches · n = ...". The summary says "reference: loaded (<date>)". Zone names from the pages match the client's names (a reference zone and your own catches in the same zone are **one** row; two rows with the same zone in different spelling or language means the pages don't match the client language).
- [ ] Items only in the reference show their name and icon once the client has loaded them (the list refreshes by itself); report items that stay "item <id>" or without icon.
- [ ] Values: a fish sold at the AH shows the AH value at the profit house after the cut, others the vendor value; containers (Iron Bound Trunk etc.) show "contents" and the contents per opening in the row tooltip. Stack ranges show "low - high".
- [ ] Click a zone: its loot table (chance, count / recorded, unit value, per catch). "All zones" and right-click on a row go back; "Show own catches" / "Show reference" switches the source when the zone has both. Headers sort in both lists.
- [ ] After fishing a few minutes in a zone: its row gets a value per hour (own catches per hour x value per catch).
- [ ] `/craftwise fishing zones`, `/craftwise fishing zones <part of a zone name>`, `/craftwise fishing ownmin 20` (the zone's row switches to own catches once it has 20); `/craftwise fishing` still prints the #86 tables.
- [ ] Without the reference addon (disable it, restart): the tab shows own zones only and "reference: not loaded", no Lua error.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].fishingZones` has up to 5 zones (`docs/snapshot.md`).

## Fishing page on the site (#128)
`/reload` is enough (no new file, no TOC change). Then rebuild and restart the companion (its snapshot structs carry the new fields; an old companion drops them and the page shows the snapshot's figures).
- [ ] `/craftwise snapshot`, `/reload`, open `CraftWise.lua`: `snapshots[...].fishing.spots[1].items`, `.waters` and `.pools[1].items` look like `"<itemID> <count> <value> v<vendor>; ..."`; `fishingZones.zones[1].items` holds units per catch; `fishingZones.compare` has your fished zones with `own` (`"<itemID> <hits> <units> <value> ..."`) and, where the reference has the zone, `ref`/`refN`.
- [ ] A container you caught (trunk, crate) ends in ` c` in the lists; an item vendors don't buy ends in ` v0`.
- [ ] After the next upload, `/me/fishing`: values say "with today's Horde AH prices"; a zone with 50+ own catches ranks by your catches with the reference under Compared; the Catch pane lists your share of each item with its interval next to the reference's.

## Every item of a full scan, Auctionator export (#90)
`/reload` is enough (no new file, no TOC change).
- [ ] Auctionator Full Scan at the Horde AH, wait until it says it finished, then wait about 10 seconds more: no stutter while CraftWise stores it. `/dump CraftWiseMarketDB.scans["<realm>|H"][#CraftWiseMarketDB.scans["<realm>|H"]]` shows `kind = "full"` with `items` (scope items) and `lastOnly` (all other items) roughly adding up to the number of items Auctionator reports.
- [ ] An item outside your professions that was on sale (e.g. Silverleaf, a Glimmering Shard, a Waylaid Crate): `/craftwise market <id>` shows "Horde AH: last ..." and "history: none (outside the market scope, latest price only)".
- [ ] `/reload`, then open `WTF/Account/<account>/SavedVariables/CraftWise.lua` (copy it with the game closed): `CraftWiseMarketDB.names` has names for most scanned items (the client names a row only once it has loaded the item). Report how many items have no name.
- [ ] Size of `CraftWise.lua` before and after the first full scan, and `/reload` time. Headless: 10,000 items at one house are about 1 MB, at four houses about 2.6 MB.
- [ ] Run a second full scan an hour later: an item sold out in between shows ", none in the latest full scan" in `/craftwise market`.
- [ ] With Auctionator loaded, hover a reagent CraftWise has no AH price for at the profit house: its tooltip says "Auctionator (house unknown)" and `/craftwise market <id>` ends with "Auctionator (house unknown): <price>, read ... ago". `CraftWiseMarketDB.auctionator.items` fills with the scope items about 5 seconds after login.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].market.houses` lists each house with `lastFullScan` and counts.

## Waylaid crates and Merchant's Favor (#91)
New file `Crates.lua` in the TOC: **full game restart** needed (not `/reload`). Crates are recognised by the name prefix "Waylaid " (English client).
- [ ] Carry a Waylaid crate: `/dump CraftWiseDB.crates` has it with `name`, `tier`, `lines` (the tooltip lines as the client gave them) and `fill` (one entry per "- <count> <item>" line). Report the `lines` of one crate: does any line state the Favor reward? If yes, `reward` and `rewardText` are set; if no, report what the tooltip shows besides the bundle list.
- [ ] Fill a crate (Use, pick a bundle) and report what happens to the item: same item ID, a new "filled" item (`/dump` its link), or does it go away? If a filled item appears, `/dump CraftWiseDB.crates` should list it too when its name starts with "Waylaid ".
- [ ] Turn a filled crate in at Dokimi (Durotar Supply and Logistics, The Barrens). Afterwards the crate that left your bags has `got = { { n = <Favor gained>, t } }`. Report if `got` stays empty: then the crate and the Favor gain were more than 3 seconds apart, or several crate types left the bags at once, or the item turned in is not one CraftWise recognised as a crate.
- [ ] `/craftwise crates`: first line "Merchant's Favor: <n> on this character" (matches the currency tab), then one line per crate: price per Favor (once crate price, a bundle price and the reward are known), crate price with its label, the cheapest bundle with its label ("crafted" when a recipe you know makes it cheaper), the reward with "(tooltip)" or "(seen at N turn-ins)", "you hold N: fill only ... per Favor". Ends with "best to buy and fill" / "best of the crates you hold" when there is one.
- [ ] After an AH full scan (with #90 storing every scanned item): crates on the AH appear in `/craftwise crates` with a crate price, also ones you never carried (their names must be in the client cache; report crates that are on the AH but missing).
- [ ] Bundle names that match no item: shown as "(item not identified)". Report any (e.g. "Handful of Copper Bolts", "Copper Modulator"); they resolve once the item is in the client cache (bags, AH, merchant).
- [ ] Open Pawani (Durotar Supply and Logistics vendor) with the filter on "All": `/dump CraftWiseDB.merchants[248201].items[<itemID>].req` for an item that shows "Requires Durotar Supply and Logistics - <standing>" on its tooltip has `faction`, `standing` (1..8) and `text`; items without that line have no `req`.
- [ ] `/craftwise snapshot`, `/reload`: `snapshots[...].crates` and `.favor` as in `docs/snapshot.md`; `favor.balance` matches the currency tab, `favor.vendors` lists Pawani with all items, Favor costs and requirements.

## Item info for every priced item (#92)
`/reload` is enough (no new file, no TOC change).
- [ ] After a full scan and about 10 seconds more: no extra stutter. `/reload`, then in `CraftWise.lua` (copy it with the game closed) `CraftWiseMarketDB.itemInfo` has an entry for (nearly) every item with a record. Report how many records have no `itemInfo` entry.
- [ ] Pick three entries and compare with the game: `/dump C_Item.GetItemInfoInstant(<id>)` (icon is the 5th value, class 6th, subclass 7th) and `/dump C_Item.GetItemQualityByID(<id>)` must match the decoded `q,i,c,s` (base 36: in Lua `tonumber("2vji", 36)` = 134190).
- [ ] An item searched or browsed only (no full scan) has an entry after closing the AH.
- [ ] A Waylaid Crate or an item you never saw before the scan: present after the scan or after the next login (the client loads it on request).
- [ ] With a non-English client (if available): `names` are in that language; `itemInfo` is the same numbers.

## Class names and vendor sell prices (#120)
`/reload` is enough (no new file, no TOC change). The first full scan or login after the update loads every priced item the client hasn't cached, 100 every 0.2 s (about 35 s for 18,000 items) to read its sell price.
- [ ] After a full scan, about a minute and a `/reload`: in `CraftWise.lua` (copy it with the game closed) `CraftWiseMarketDB.itemInfoV = 2` and the `itemInfo` strings have 6 fields (`q,i,c,s,t,p`). Report how many still end in a comma (sell price unknown).
- [ ] Pick three items and compare `p` (base 36) with the sell price in the game tooltip at a vendor, and with `/dump select(11, C_Item.GetItemInfo(<id>))`. An item the vendor doesn't buy (quest item, some bind-on-pickup items) has `p` = `0`.
- [ ] `CraftWiseMarketDB.classNames` and `subclassNames` hold the names the auction house's category list shows (Trade Goods / Herb, Cloth, ...), the same as `/dump C_Item.GetItemClassInfo(7)` and `/dump C_Item.GetItemSubClassInfo(7, 9)`. No empty names.
- [ ] No stutter after the scan beyond what #92 had; BugSack shows no CraftWise error.
- [ ] After the companion uploaded (rebuilt with #120): wow.velikopter.com's category tree shows those names instead of "Tradegoods" / "Subclass 9"; the list has a Vendor column, "Better sold to a vendor" filters it; an item page shows "Sell Price" in the tooltip and the "Auction House or Vendor" block, in both skins.

## Market entries packed at logout (#105)
`/reload` is enough (no new file, no TOC change).
- [ ] Have a fishing log with catches that have an AH price at the profit house (the snapshot values them at logout), then `/reload`. In `CraftWise.lua` (copy it with the game closed) every value under `CraftWiseMarketDB.items[<id>]["<realm>|H"]` is a string; report any `{ ["days"] = ..., ["last"] = ..., ["raw"] = ... }` table.
- [ ] Logout and `/reload` take no longer than before, and BugSack shows no CraftWise error at logout.

## Companion app (#94)
Not part of the addon: build `companion/` (see `docs/companion.md`), create an upload token on wow.velikopter.com/me. Headless tests cover the delta, the request shapes (also checked against the Worker's validator), the watcher and retries; the tray and the real file system are untested.
- [ ] Windows: start `craftwise-companion.exe` (built with `-H=windowsgui`): a gold coin appears in the notification area, no console window. Right and left click open the menu; "Open settings" opens `config.json` in Notepad. Put the token in, save, then "Upload now": the first menu line says "Checked HH:MM: sent ..." and wow.velikopter.com shows the houses and prices.
- [ ] Auto-detect: with WoW in `C:\Program Files (x86)\World of Warcraft`, `craftwise-companion -status` (console build) prints the right `CraftWise.lua` without setting `wowPath`. With several account folders it picks the one written last; `account` in the settings overrides it.
- [ ] In game `/reload`: within about 10 seconds the log (`Open log`) shows "upload (file changed)" and only the new data (a few prices, not the whole file). Logout: the same.
- [ ] While the game is writing (logout with a large market DB) the log never shows a parse error that stays; "still being written" is followed by a successful read.
- [ ] Nothing is created or changed in the `_forever_` folder by the companion (the game's own `CraftWise.lua.bak` is from WoW).
- [ ] A second start says "another CraftWise Companion is already running" in the log and exits.
- [ ] Explorer restart (Task Manager > Windows Explorer > Restart): the icon comes back.
- [ ] Quit from the menu removes the icon; no process left in Task Manager.
- [ ] macOS (MacBook): `./craftwise-companion-macos -once` uploads from `/Applications/World of Warcraft/_forever_`; without `-once` it keeps running in the terminal and uploads after `/reload`.

## Recently learned recipes and known recipe IDs (#107)
`/reload` is enough (no new file, no TOC change).
- [ ] Learn a recipe from a pattern (e.g. a Pawani pattern) with the profession window closed: `/dump CraftWiseCharDB.learned` ends with `{ id = <recipe>, how = "event", t = <now>, line = 165 }`. If the entry is missing, Forever doesn't fire `NEW_RECIPE_LEARNED` for patterns: open the profession window, the next scan adds it with `how = "scan"` and `after` = the previous scan's time. Report which of the two happened.
- [ ] Same at a trainer: buy a recipe, check `CraftWiseCharDB.learned` the same way and report `how`.
- [ ] The profit window shows the newly learned recipe as learned right away (before opening the profession window).
- [ ] `/craftwise snapshot`, `/reload`: in `snapshots[...]`, each scanned profession has `known` (ascending recipe IDs, comma-separated; the count equals `recipesKnown`), and `recipesLearned` lists the recipe with name, profession and time.

## Loot toast (#114)
Needs a full game restart (new file `LootToast.lua` in the TOC). On by default; Settings, "Loot toast".
- [ ] Autoloot a mob: one line per item (icon, name in its quality colour, `xN` for stacks) appears at the anchor, stays about 4 s, then fades over 1 s. Same with a hand-opened loot window (Shift + right-click), clicking the items.
- [ ] A mob with several items and coin: one line per item plus one coin line with the exact amount. Each line fades on its own timer (loot a second mob 2 s later: the first lines go first).
- [ ] Area loot of several corpses (or two kills of the same mob quickly): the same item adds to its line (`x` count goes up) instead of a second line; coins add to one coin line.
- [ ] Value text: an item with an AH price (Auctionator or a CraftWise scan) shows `<money> AH`, a vendor-only item `<money> vendor`, both for the whole stack and matching the item tooltip's "Sells for" times the count. An item without any price shows no value. `/craftwise loottoast value off` hides it.
- [ ] Coin: selling to a vendor, taking money from mail and a quest reward do **not** show a coin line. In a group, "Your share of the loot is ..." shows the coin line with your share. If looted coin never shows, `CHAT_MSG_MONEY` and `PLAYER_MONEY` are more than 2 s apart (or the first never fires) on Forever: report it.
- [ ] Another player's loot in a group never shows; quest reward items (pushed, "You receive item:") don't either.
- [ ] Inside a dungeon in combat: if `CHAT_MSG_LOOT` text is a secret value there, lines are skipped without a Lua error. Report whether loot during combat in an instance shows.
- [ ] `/craftwise loottoast unlock`: the white handle and outline appear (#159); drag the handle, `/craftwise loottoast lock` hides them. `/craftwise loottoast test` shows two bag items and a coin line there, each labelled "test". `/reload` (and a relog) keeps the position. `/craftwise loottoast reset` puts it back.
- [ ] `/craftwise loottoast duration 8`: lines stay 8 s. `duration 0` and `duration 50` are refused with a usage line. `/craftwise loottoast off`: nothing shows on loot; `on` again.
- [ ] Non-English client (if available): lines still appear (the client's own `LOOT_ITEM_SELF` / `LOOT_ITEM_SELF_MULTIPLE` strings are used).
- [ ] Fast auto-loot (#41) on and off, and with another loot addon: the toast shows the same either way (it reads what arrived, not who looted).

## Money and XP in the logout snapshot (#123)
`/reload` is enough (no new file, no TOC change). Read the snapshot in `CraftWise.lua` (copy it with the game closed, or read it after logging out) under `CraftWiseDB.snapshots["<realm>-<name> <surname>"]`.
- [ ] Note gold, XP (`xp / xpMax` on the XP bar tooltip), rested XP and level, then `/reload`. `char.money`, `char.xp`, `char.xpMax`, `char.rested` and `char.level` match what you noted (not 0), and `ledger.today.money` equals `char.money`.
- [ ] Earn or spend some copper and gain some XP (kill a mob), then log out to the character screen. The snapshot has the new money and XP. Do the same with a quit (`/quit`).
- [ ] `/craftwise snapshot` then `/reload`: the values are the live ones as well (the manual snapshot is overwritten by the logout one, which must agree).
- [ ] Level up, then `/reload`: `char.level` is the new level and `xp`/`xpMax` are the new level's.
- [ ] `ledger.today.change` and `other` are plausible: `money - startMoney`, not `-startMoney`. `/craftwise ledger today` after logging back in shows no day starting at 0.
- [ ] While there, compare `holdings.bags` and `favor.balance` in the logout snapshot with the bags and the Favor shown in game. If either is empty or 0 at logout, the client clears more than money and XP by then: report it on #123.

## Farm tracker (#126)
Needs a **full game restart**: three new files in the TOC (`LootFeed.lua`, `Farm.lua`, `UI/FarmFrame.lua`). Compare with MoneyLooter side by side before uninstalling it.
- [ ] Kill and loot a mob: the CraftWise Farm window opens on its own (Start on first loot is on), state "running", Time counts up once a second. The loot toast still shows the same loot (both read one feed now).
- [ ] Coin equals MoneyLooter's Gold to the copper after a few mobs. Selling to a vendor, taking mail money or a quest reward does **not** add coin.
- [ ] Item list: count, name in quality colour, stack value with `AH` or `vendor` (`AH!` in orange = AH price over a day old). Hover a row: item tooltip plus "Looted this session", value, each, price source. A bind-on-pickup drop says "vendor only" and is valued at vendor. An item without any price shows `?` and is counted under Unpriced, not in Items.
- [ ] Items / Vendor only / AH part (with "stale" part) add up as the hover texts say; Items is at least Vendor only. Gold / hour and Coin / hour appear after the first minute and match (coin + items) and coin per hour of Time.
- [ ] Priciest names the drop with the highest value per unit (hover shows its unit value).
- [ ] x on a row removes it from the totals; looting that item again in the same session doesn't bring it back; after Reset it counts again.
- [ ] Pause: state "paused", Time stops, loot is not counted; Resume goes on. `/craftwise farm pause` does the same.
- [ ] Stop looting for 5 minutes: state "paused (idle)", Time stays at the last loot (the idle minutes don't count); the next loot resumes. `/craftwise farm idle 2` makes it 2 minutes, `idle 0` never pauses.
- [ ] Ride into another zone and loot there: the Zones lines show both zones with their time and gold per hour, the time split at the zone border (`ZONE_CHANGED_NEW_AREA`).
- [ ] `/reload` mid-session: same session, Time continues from where it was (the loading screen is not counted). Log out for a few minutes and back in: Time didn't count the time offline.
- [ ] Reset: the session goes to the history; `/craftwise farm history` lists it (start, time, zone, coin, items, gold per hour, best item). Then `/reload` and read `CraftWiseDB.snapshots[...].farm` in `CraftWise.lua`: `current` / `sessions` as in `docs/snapshot.md`.
- [ ] Drag the window by its title or a free spot; `/reload` keeps the position. `/craftwise farm lock`: it no longer moves ("locked" shown at the top right); `unlock` again. `/craftwise farm scale 0.8` shrinks it, `scale 3` is refused.
- [ ] X button or `/craftwise farm hide`: the window hides, loot is still counted; `/craftwise farm` (or `show`) brings it back with the totals.
- [ ] Settings: "Farm tracker" off pauses the session, hides the window and nothing is counted; on again and Resume. "Start on first loot" off: loot doesn't open a session until Start.
- [ ] In a group: your share of the coin counts, other players' loot doesn't. In a dungeon in combat, if loot lines are secret values they are skipped without a Lua error (same as the loot toast).

## Farm tracker: fishing, loot log, Farm button, key binding (#130)
No new files in the TOC; `Bindings.xml` changed (it is not in the TOC, the client reads it from the addon folder). Restart the game once for this update: whether `/reload` re-reads `Bindings.xml` is not verified.
- [ ] Before fishing: farm a few mobs. The window has no Fishing panel.
- [ ] Fish 10+ casts in a row (pool and open water). A Fishing panel appears under the window with the first catch. Catches = the number of catches (compare `/craftwise fishing`, same count for this stretch); after a minute of fishing `x/h` appears and is plausible (a catch every 15-25 s = 140-240/h).
- [ ] Per catch = (fishing coin + caught items) / catches; caught items valued as in the loot list (hover a fish row there for its value). A catch with coin adds its coin to fishing (hover Per catch: "Coin from fishing"); coin from a mob looted right after does not. An item without a price shows `+N ?` next to Per catch and is not in it.
- [ ] Gold / hour is per hour of fishing time: stand still for 3+ minutes between two casts, the next catch adds no time (the gap is over 2 minutes).
- [ ] Best catch names the caught item with the highest value per unit.
- [ ] Open a container you caught this session (crate, chest): Containers goes to 1, the container leaves the fishing value and its contents (and coin) join it. A container caught in an earlier session is not counted.
- [ ] Fish in a second zone: the right side lists both zones with catches, per catch and gold per hour.
- [ ] Reset: `/craftwise farm history` prints a "fishing:" line under that session; `/reload`, then `CraftWiseDB.snapshots[...].farm.sessions[1].fish` has the block (`docs/snapshot.md`).
- [ ] (Since #156 the loot log is on Gather › Farm, see that section.) Loot panel: the "Log" button switches to the loot log: one line per drop, newest on top, time (your clock, HH:MM:SS), icon, count, name in quality colour, value (`?` for unknown), zone; coin drops are their own lines with a coin icon; catches and their coin have the fishing icon. Hover a line: time, zone, count, value, "From a fishing catch.". Scroll with the mouse wheel. "List" switches back; `/reload` keeps the chosen view.
- [ ] `/reload` mid-session: the log is still there. x on a list row removes that item's lines from the log too.
- [ ] Profit window (`/craftwise`): a "Farm" button left of "Profit" opens and closes the farm window; it doesn't overlap the subtitle.
- [ ] Esc > Options > Key Bindings > AddOns > CraftWise: "Toggle CraftWise farm tracker" is listed under the CraftWise header next to Party; bind a key, it opens and closes the farm window (also in combat).
- [ ] Settings (gear) > Farm tracker: the "Farm window" button opens and closes it. Since #157 that button is gone: Gather › Farm "Open tracker", the minimap right-click and the key binding open it.

## Containers opened from the bags (#135)
`/reload` is enough (no new file, no TOC change). Turn on the chat's loot messages (the "Loot" filter of the General tab is on by default).
- [ ] **Note the exact chat lines** when you open each of these from the bags: a bloated fish (e.g. Bloated Redgill), a crate, a trunk, a junkbox (or lockbox). Write on #135, per container: the line for each item (copy the wording, e.g. "You receive loot: [Star Ruby]." or "You receive item: [Star Ruby]." or no line at all), and the coin line if it had coin ("You loot 1 Silver ..." or none). CraftWise counts the contents without any of these lines, but the wording tells which path counted them.
- [ ] Open a container that dropped this farm session (a mob's crate or junkbox): in the Farm window the container's row goes down by one and the contents appear (and the toast shows them), each once. Hover the totals: Items went up by the contents' value minus the container's (if it had one). The loot log still has the container's line plus a line per item it gave.
- [ ] Fish up a bloated fish or a crate, then open it (Veli's case: Bloated Redgill with a Star Ruby): the list and the Fishing panel both lose the container and gain the contents; Containers goes to 1; the contents' log lines have the fishing icon. `/dump CraftWiseDB.fishing["<realm>-<name> <surname>"].opened` has the opening.
- [ ] Open a container you already had before the session (Reset first): the contents count as loot of the session, nothing else in the list changes, Containers stays 0.
- [ ] Open a container with full bags: what stays in the window is not counted. Free a slot and open it again: the rest counts, and the container isn't taken off the list a second time.
- [ ] Hand in a quest that rewards an item ("You receive item: ..."): it is not counted and not toasted, also right after opening a container.
- [ ] Loot a mob right after opening a container that gave the same item (e.g. a fish): both count.
- [ ] Fast auto-loot on and off (Settings, "Fast auto-loot"), and opening by hand clicking each item: the same counts.
- [ ] If the contents of a container never count: `/dump C_Container.GetContainerItemInfo(<bag>, <slot>)` on an unopened container shows `hasLoot = true`, and report whether the Farm window's container row went down (then only the contents were missed) on #135.

## Farm tracker: your catch rate (#136)
`/reload` is enough (no new file).
- [ ] Fish with a farm session running: the Fishing panel has a "Your rate" line under Catches. With fewer timed catches in the fishing log than `/craftwise fishing zones` uses as its own-data minimum (50): grey "N timed catches, too few (50)". From 50 on: "141/h", then in grey the water types with 50 timed catches each ("open 163 · pools 88"). The line fits the panel (no overlap with the Zones column, nothing below the panel's edge).
- [ ] Hover it: the explanation, then "All water", "Open water", "Pools" (and "Water not known yet" when there is such a catch) with the rate or "too few", the timed catches and minutes. `/craftwise fishing ownmin 10` lowers the minimum and the line shows a rate at once; set it back with `ownmin 50`.

## Every feature in the UI: Records window, Settings, farm history (#137)
Since #157 (part 2) the Records window and the old Settings panel are gone: Snapshot is Settings › Snapshot, every switch below is on the Settings page, the item views are on Look up › Items. The farm history and slash items still hold.
Needs a **full game restart**: ten new files in the TOC (`UI/Records/*.lua`, `UI/FarmHistory.lua`); `/reload` is not enough.
- [ ] Profit window (`/craftwise`): a "Records" button left of "Farm"; the subtitle now sits under the title; nothing overlaps (title, subtitle, Records, Farm, Profit ... Music, gear, x). Records opens and closes the Records window.
- [ ] Records window: title row, three tabs (Market, Where to buy, Snapshot; Ledger and Auctions moved to Sell in #155, Crates and Fishing log to Gather in #156), toolbar, two summary lines, column headers, rows with icon, name (quality colour) and second line, scroll bar, footer. Drag it by a free spot; Esc closes it; it opens on the tab last used (also after `/reload`).
- [ ] Ledger: the same numbers as `/craftwise ledger` for Since reset, Today and Since login (each button sets what `/craftwise ledger` shows next). Per day matches the "per day" lines of `/craftwise ledger today`. Reset: the first click turns the button orange "Click again"; after 5 s it goes back by itself; two clicks within 5 s reset ("since reset" is empty, Today keeps its rows).
- [ ] Auctions: post 2 items, let one sell: rows "listed" (buyout each, ends in ...), "sold, awaiting mail" (expected gold); the summary's On its way and If all listed sell match `/craftwise auctions`. Hover a row: item tooltip plus posted time, deposit, expected note.
- [ ] (Moved to Gather › Crates in #156.) Crates: opening the tab with a Waylaid crate in the bags lists it like `/craftwise crates` (per Favor, crate price, cheapest fill, reward, held); best to buy and fill marked green; your Favor balance in the summary. Hover: every bundle with its price.
- [ ] (Moved to Gather › Fishing › Log in #156.) Fishing log: rows match `/craftwise fishing` (zone · subzone, water type on the second line, catches, per catch, per hour, top catches); Pools / Open water filter like `/craftwise fishing pools|open`; typing a zone in the box filters like `/craftwise fishing <zone>`; Pool visits lists the pool lines of the slash command; Find Fish state in the summary.
- [ ] Market: without a search the reagents/products of your recipes; typing "linen" finds every recorded item with that name (also items outside the scope: "latest only"); an item ID works. Columns: house, latest lowest, typical (days), units/listings on the AH, seen. Hover: cheapest tiers, 7-day range, disappeared units, as `/craftwise market <id>` prints. Summary: last full scan per house. With hundreds of recorded items, typing stays smooth (no hitch per key); report a hitch on #137.
- [ ] Where to buy: typing "nightcrawler" lists the merchants you opened that sell it, cheapest first, with zone and coordinates, price per character standing, stock, seen; restocks in the tooltip, base price in the summary. Same as `/craftwise where nightcrawler`.
- [ ] Snapshot: "Save snapshot" shows "Snapshot saved." and every section as saved/skipped/error with the time of the save; "Reload UI" reloads the interface (then `CraftWise.lua` on disk has the new `t`).
- [ ] Click an item row in Ledger, Auctions or Market: the item menu opens at the cursor (#159). Item menu (middle-click an item in the bags): "Where to buy" and "Price history" open the Records window on that item. Since #157 the Records window is gone: Look up › Items (see #157 below).
- [ ] Settings (gear): two columns, fits the screen (clamped), nothing overlaps. Right column: Loot toast "Show what you loot", "With value", Move (unlocks: drag the white handle; the button says Lock, click to lock), Test (three sample lines labelled "test"), Reset position, Lines stay - / + (1-30 s). Farm tracker: on/off, Start on first loot, Lock window (the window stops moving, "locked" shown), Pause when idle - / + (never at 0), Window scale - / + (0.5-2.0, the window scales at once), Farm window, Farm history (opens Gather › Farm since #156). Fishing: Session gap - / + (Gather › Fishing › Log's per hour changes), Own catches count from - / + (Gather › Fishing › Spots switches zones between own and reference). Other: Minimap button (hides and shows it), Records. Since #157 the panel is gone: every switch is on the Settings page (Loot toast, Farm tracker, Fishing groups; Minimap button under Look); the Records button went with the Records window.
- [ ] (Since #156 History opens Gather › Farm; see that section.) Farm window: a "History" button left of List/Log. It lays the history over the whole window: one line per finished session (started, time, zone with "+n" for more zones, coin, items, gold per hour, fishing catches); mouse wheel scrolls. Click a session: its stats, zones, top items and fishing on the left, its loot log on the right (newest first, hover for time and zone); a session older than the newest 10 says its log wasn't kept. Back returns to the list; "Session" returns to the live session. The panel (360 px high) is not cut off at the bottom and covers the list completely.
- [ ] All slash commands still do what they did (`ledger`, `auctions`, `crates`, `fishing ...`, `market <item>`, `where <item>`, `snapshot`, `loottoast ...`, `farm ...`, `ahmin`, `minimap`, `party`, `settings`, `debug`).

## Style and Media (#151)
Needs a **full game restart**: new files under `CraftWise/Media/` (fonts and textures) are only found after a restart; no TOC change, no new Lua file. `/craftwise debug style` opens a sample sheet with every font, shape and control (debug only; again to close, or Esc).
- [ ] The sheet has a folded top-right corner (22) in the flap colour with a hard 3 px shadow to the lower right, no soft edge; the card below has its own 14 corner. Nothing is round.
- [ ] Header: gold key block in two tones with a diagonal right edge, two dark planes, the top-right corner left open so the sheet's corner shows; the W key (30) sharp on the gold; "CraftWise" in ExtraBold, dark.
- [ ] Twelve font lines, each in its own face: Brand/Hero ExtraBold, Section/BodyBold/Label Bold, Body/Small/Caption Regular, the Figure lines in the monospaced cut (digits line up). None falls back to the client's default font (that would mean a path or a file is wrong). Glyph line: ▲ red, ▼ turkuaz, → grey drawn as small shapes in line with the digits; · − × come from the font; coin digits gold, silver, copper.
- [ ] Line button and chip: 1 px border; hover turns border and text white. The chip toggles on click. Segmented: "Window" filled white with dark text, the borders between the three buttons are single lines (not doubled). Checkbox: 14 square, filled white with a dark tick. Slider: thin track, white part up to a 12 x 14 thumb, drags in steps.
- [ ] End session (red): the corner lifts from 10 to 14 on hover and settles back; pressing moves it 2 down and back, quickly (80 ms), no fade. Start (white) with a white corner.
- [ ] Rails: four rows on one scale, the first fills its rail to the right end; the loss (Barbaric Shoulders) runs left of the zero line in red; the zero line is a short vertical line, the axis a hairline. Click a row: the nokta hops to it (grows from its middle in about 0.16 s), the bar of the clicked row turns white. Hover a row: the light tooltip with dark text, corner 6 and a hard shadow, under the row.
- [ ] 1 px lines at other scales: `/console uiScale 0.64` (and back to your own), `/reload`, `/craftwise debug style`: borders, hairlines, the axis and the zero line are still exactly one screen pixel, not blurred into two or gone. Change the UI scale in the options with the sheet open: they stay one pixel.
- [ ] W key at 20 (right column) and the gold W key as a whole: edges clean, no dark fringe around the gold sheet or the shapes (texture edges).
- [ ] Report `/dump UIParent:GetEffectiveScale()` on #150 if not done yet.

## Marks on Blizzard frames (#160)
No new Lua file, no TOC change. The corner and key textures are from #151, so a full game restart is only needed if you have not restarted since that one.
- [ ] Item tooltip: a blank line, then the small gold W key and "CraftWise" in gold. Labels grey, values white. "Sell" (or "Sell ×20" for a stack) shows "AH …" and "Vendor …" with the better way white and the other grey. The "AH price" line shows the price source, then the age ("3h old", "today", "2d old"), then the cut. An age over 24 hours is red-orange (a scan older than a day, or Auctionator more than a day old). The W key is sharp at 12 px; if it looks muddy, report on #150 (the 64 px texture is used, see the W key size question in #168).
- [ ] Setting "Only with Shift": nothing of CraftWise (not even the header) until Shift is held; pressing and releasing Shift over an open tooltip adds and removes the section.
- [ ] Profession window: one figure at the right end of each recipe row, 4 units from the edge, in the monospaced font. Measured chances are white ("58%"), formula estimates grey with "~" ("~41%"). Grey (trivial) recipes show nothing. No green and no orange anywhere; the figure does not collide with the recipe name, the skill-up count or the crafts count. Hovering a recipe still adds the "CraftWise: skill-up chance" source line.
- [ ] Merchant frame with marked junk in the bags: a red "Sell junk · 35s" button (folded corner, 28 tall) at the bottom left of the merchant frame, above the tabs. Check it does not cover Blizzard's own buttons (repair, sell all junk) or the buyback slot; if it does, say where it should sit on #160. It lifts its corner on hover. The amount is at most two units (12g 40s). With nothing marked the button is not there.
- [ ] Click Sell junk: the stacks are sold one by one, an orange diamond and "Selling 3 of 5" show to the right of the button, the button waits and is dimmed until done; the chat line gives the total.
- [ ] Combat: with the merchant open, get into combat (a training dummy works): the button is dimmed and does not react; hovering it shows the light tooltip with "Unavailable in combat. It works again when combat ends." Leaving combat re-enables it. Starting a sale and then entering combat stops the sale; what is left stays marked.
- [ ] Bag slots, game bags (combined and single): a mark in Sell on AH shows a gold folded corner (13) on the slot's top right; a junk mark shows a grey corner and the item icon greyed and dimmed to about half. Keep and unmarked items show nothing. Marking and unmarking from the item menu updates the slot at once; closing and reopening the bags keeps it. The old red X and the auctioneer icon are gone. Check the corner does not hide the item level or quality border.
- [ ] Baganator (if installed): Settings > Icons lists the corner widget "CraftWise: marks" (new id, so an earlier placement of "CraftWise: sell on AH" is gone): put it in the top right. Gold corner for Sell on AH, grey corner and a dimmed icon for junk. Baganator still draws its own junk coin on junk while the "CraftWise" junk plugin is selected; report whether the coin and the corner together look wrong (#160 question).
- [ ] Bagnon (if installed): same marks as the game bags.

## Loot toast, item menu, minimap button, compartment, W key icon (#159, #166)
Needs a **full game restart**: the TOC's `IconTexture` changed (no new Lua file). Use a character with a few items in the bags and an AH price for at least one of them. Report your UI scale with any finding.
- [ ] Addon list (character select › AddOns) and the addon compartment (the button next to the minimap): CraftWise shows the gold W key, not the gold coin. Clicking the compartment entry opens the CraftWise window (again closes it).
- [ ] Minimap button: a round button of the same size as the client's tracking button, the client's ring, the W key centred inside the ring with nothing cut off or spilling over the ring. Hover: the light tooltip with dark text, "CraftWise", then "Click: open", "Right-click: farm tracker", "Drag: move" (no Shift-click line until the docked layout, #161). Click: the CraftWise window opens on the page it was on. Right-click: the farm tracker shows; again: it hides. Shift-click: same as a click for now. Drag: it moves around the minimap rim and stays there after `/reload`. Settings › "Minimap button" and `/craftwise minimap` hide and show it.
- [ ] With MinimapButtonButton (or a similar collector) installed: the CraftWise button is collected and all clicks still work there.
- [ ] Loot toast: loot three different things (one with an AH price, one vendor-only, some coin). Each line is a dark strip 28 tall with a small folded corner and a hard shadow to the lower right; 6 apart; newest on top. Only the newest line's corner is turkuaz, the older ones grey. The second line is a bit faded (75 %), the third and older ones more (50 %); the dark fill shows the world behind it (70 %), while icon and text of the newest line are fully solid. Each strip is as wide as its text plus a little room at the right for the corner.
- [ ] Line content: 18 icon, the item name in its quality colour (grey, white, green, blue, purple; no brackets), "×count" in grey monospaced digits, the value in gold/silver/copper digits with at most two units and a small grey "AH" or "vendor". The coin line reads "Coin" and the coins. Settings "With value" off: no value and no source word.
- [ ] Lines leave after "Lines stay" (Settings) with the short fade-out; looting the same item while its line is fully shown adds to that line, which moves to the top and becomes the turkuaz one.
- [ ] Settings › Loot toast › Move: a white handle "Loot toast · drag to move" with a thin white outline below it where three lines go; drag the handle, Lock hides both. Test: two bag items and a coin line, each with a grey "test" at the end. Reset position puts it back.
- [ ] Item menu (middle-click an item in the bags, or click a row in the Bags view or a Records row): opens at the mouse cursor; a dark sheet 200 wide with a folded corner and hard shadow; the item name in bold; Keep, Junk, Sell on AH, Normal; the current mark has the turkuaz diamond and a lighter row behind it and is bold. A hairline, then Where to buy, Price history, Recipes using this. Hover a row: it lights and the light tooltip explains it. A choice closes the menu; so do Escape and a click elsewhere. Since #157 there are no Records rows: any row of the main window.
- [ ] Item menu on a quest item: "Quest items can't be sold" (grey, not clickable) in place of Junk and Sell on AH; Keep has the diamond.
- [ ] Item menu › Where to buy and Price history open the Records window on the item (Look up › Items replaces this with #157). Done in #157: Look up › Items.

## Farm tracker in the Origami look (#158)
No new Lua file and no TOC change: `/reload` is enough. The tracker uses #151's fonts and textures, so a game that hasn't been restarted since #151 needs that restart first. Compare with the board "Farm tracker states, mini mode, loot toast" (canvas page Screens).
- [ ] No session (`/craftwise farm reset`, then `/craftwise farm show`): a 260 wide sheet with a dark grey dog-ear (22) and a hard shadow; "Farm" in ExtraBold, "no session" in grey; "Press Start, then loot." and, with Start on first loot on, the grey line under it; buttons Start (white, folded) and History (line). Nothing overlaps; the bottom padding equals the sides roughly (14).
- [ ] Start: the dog-ear turns orange, "running" orange, the timer at the top right counts "0:00:01", "0:00:02" … once a second and stays clear of the dog-ear. Gold per hour shows "—" for the first minute, then big monospaced digits in coin colours (gold and silver only, never three units). Caption: "per hour · total … · <zone>".
- [ ] Loot a few mobs: the split bar (6 tall) shows coin gold, white (items at AH) and grey (vendor only) parts with 2 unit gaps, as wide as their shares; the three figures under it line up with their labels. With AH prices over a day old the "Items at AH" label is red. Hover each column, the gold per hour and a loot row: our cells show the light tooltip under them, a loot row the item tooltip with the session lines.
- [ ] Loot list: at most 5 rows of 24, icon 16 with trimmed edges, name in its quality colour (grey, white, green, blue, purple), "×N" grey, value in coin colours; an unpriced item says "no price". With more items or unpriced ones the footer says "+ N more · M unpriced"; Log · History sit right. The tracker's height follows its content (no empty band at the bottom, nothing cut off).
- [ ] Pause: the dog-ear turns grey (rule-strong), "paused" and the timer grey, the timer stops; buttons Resume (white) and End session (line). Resume goes on. Stop looting 5 minutes: "paused · idle 5 min", caption "per hour · resumes with your next loot"; the next loot resumes.
- [ ] End session (red, its corner lifts on hover): the session goes to the history; the tracker shows "no session".
- [ ] Fish with a session running: the Fishing card (folded card, corner 14) appears under the split bar with Catches, Per catch, Per hour (catches per hour) and "Best catch: <name in quality colour> · your usual rate N/h" (or "your usual rate: N of M timed catches" below the minimum); long lines wrap inside the card and the card grows with them. Hover the card: the light tooltip with gold per hour of fishing, zones and your rate per water type. Not shown without catches.
- [ ] Log, "+ N more" and History open Gather › Farm in the main window (#156; the loot panel and the history beside the tracker are gone): see "Gather: Farm, Fishing, Crates (#156)".
- [ ] Drag the tracker by any free spot, its rows, hero or split: it moves (unless locked in Settings › Farm tracker); `/reload` keeps the position. Settings scale 0.5 to 2: it scales at once and its hairlines stay one pixel.
- [ ] The tracker hides with the profit window's Farm button, the key binding, Settings › "Farm window" or `/craftwise farm hide` (it has no close button of its own, as on the board). Since #157: the key binding, the minimap right-click, Gather › Farm or `/craftwise farm hide`.

## Farm tracker: mini mode and fade (#164, #163)
No new Lua file and no TOC change: `/reload` is enough. Compare with the board "Farm tracker states, mini mode, loot toast" (canvas page Screens).
- [ ] Full tracker: the – button (a short grey bar, white on hover with the light tip "Mini mode") sits between the timer and the dog-ear. With "paused · idle 5 min" showing, the state word and the timer don't touch, and the timer stays clear of the – button.
- [ ] Click –: the tracker becomes a strip 30 tall with a 12 corner in the state colour (orange running) and the hard shadow; its top left corner stays where the full tracker's was. Running: timer grey, gold per hour in coin colours (mono SemiBold), "/ h" grey; padding 12 left, 26 right, 12 between the parts; the strip is as wide as its text and the text is centred vertically.
- [ ] Right-click the strip: grey corner, "Paused" and the session total; right-click again resumes (orange, timer counts on). Stop looting 5 minutes: "Paused" as well. `/craftwise farm reset`: "no session" in grey with the dark corner; right-click does nothing.
- [ ] Hover the strip: the light tip "Farm" with Click / Right-click / Drag lines. Drag the strip: it moves and does not open the full tracker on release (unless locked in Settings, then it doesn't move). Click without dragging: the full tracker opens at the strip's top left corner, at full width.
- [ ] In mini mode, Settings › "Farm window" hides and shows the strip.
- [ ] `/reload` in mini mode: the strip comes back where it was. Settings › Farm tracker › "Mini mode" switches both ways and shows the current mode. Scale 0.5 and 2 in Settings scale the strip too.
- [ ] Settings › Farm tracker › "Fade farm tracker to 40 % away from the mouse" is off on a fresh install. Turn it on and move the mouse away: the whole tracker (sheet and text) fades to 40 % in about 0.14 s; move onto it: back to 100 % as fast. Moving between rows, buttons, the hero and the split never flickers; leaving through a row or a button at the edge fades it.
- [ ] The same with the mini strip. Hide the tracker and show it again with the mouse elsewhere: it appears at 40 % without a flash at 100 %. Turn the setting off: 100 % at once and it stays there.

## Main window shell (#153)
Needs a **full game restart**: five new files in the TOC (`UI/Main/Shell.lua`, `States.lua`, `List.lua`, `Frame.lua`, `Pages/Bridges.lua`) and three new textures (`cw-gear`, `cw-dock`, `cw-close`); `/reload` is not enough. Until the pages move (#154–#157) every sub-page is a "bridge": it says it has not moved yet and its button opens the old window there.
- [ ] `/craftwise`, the minimap button, the addon compartment and the new key binding (Key Bindings › AddOns › CraftWise › "Toggle CraftWise", listed beside "Toggle CraftWise farm tracker") all open and close the same window. Fresh profile (or `/run CraftWiseDB.settings.ui = nil` + `/reload`): it opens as a window, centred 40 above the middle of the screen, on Make › Craft.
- [ ] Window: 880 × 600, folded top-right corner (22) with the hard shadow; header 56 tall: the gold key block with the W key (30) and "CraftWise" sharp, five tabs (Make, Sell, Gather, Look up, Music) starting right of the key block, the active one white with a 3 unit bar under it. Right side, 30 from the edge: gear and × (no dock button yet: it appears with #161). Hover each: the light tooltip ("Settings", "Close").
- [ ] Sub bar 46 tall under a hairline: the sub-pages in Bold 13, the active one white with the turkuaz nokta before it. Click another: the nokta hops to it (grows in about 0.16 s, no fade). Music has no sub bar.
- [ ] Gear: Settings shows, the gear is filled white with a dark icon and no tab is active; the gear again goes back to the section you came from.
- [ ] No sub-page is a bridge any more (Make since #154, Sell #155, Gather #156, Look up, Music and Settings #157): none says "has not moved here yet".
- [ ] Drag the window by the header: it moves; close and reopen (and `/reload`): same place, same section and sub-page. Esc closes it. The window works in combat (open, switch tabs, close).
- [ ] UI scale 0.64 (`/console uiScale 0.64`, `/reload`): hairlines under the sub bar stay one pixel; nothing overlaps in the header. Report `/dump UIParent:GetEffectiveScale()` on #150 if not done yet.
- [ ] Texture edges: gear, dock (once shown) and × are crisp at 14 / 11 units, no dark fringe.
- [ ] AH status, Scanning, Stale, the list, hero card and the other states only show on pages that use them; they are checked with the first real page (#154).

## Sell: Bags, Auctions, Ledger (#155)
Needs a **full game restart**: four new files in the TOC (`UI/Main/Pages/Sell.lua`, `Bags.lua`, `Auctions.lua`, `Ledger.lua`); `/reload` is not enough. The profit window has no Bags button any more, the Records window no Ledger or Auctions tab.
- [ ] Sell › Bags with a mix of items (something to auction, something for a vendor, a grey you marked Junk, an item marked Keep, a quest item): groups in this order: Sell at the AH, Sell to a vendor, (No price), Keep, Junk. Each group row: Bold title, "N items · reason" in grey, the group total right, a 2 unit white rule under it; no column header row. Item rows 36 tall: icon 22, name in its quality colour, "×count", the grey note line ("22s each · vendor 1s 50c · used in 9 of your recipes"), your mark as a small outlined tag (Keep / Junk / AH), the value in coin colours on the right.
- [ ] Hero "What your bags would bring": the total in big mono digits under the label, the three parts on the right (AH after cut with a white square, vendor gold, junk grey) and the 6 unit split bar along the bottom of the card, parts in the same order. With an item without any price: "1 item without a price not counted" under the total. The bar's widths look right against the figures.
- [ ] Chips in the sub bar: My crafting materials and Show kept turn white when on and filter the list (the footer right counts what is hidden); Sort bags sorts the bags and reads "Sorting" in orange while it runs. Hover Sort bags: the light tooltip.
- [ ] Click an item: the item menu at the cursor (Keep, Junk, Sell on AH, Normal, Where to buy, Price history); choosing Junk moves the row to Junk with a Junk tag at once. Right-click and middle-click open the menu too; Shift-click puts the link into chat; hover shows the item tooltip with the CraftWise lines. Footer: "Click an item: … In your bags: middle-click." (or Alt + right-click, as set in Settings).
- [ ] An item with no price: value "—", hover it for the reason; note "no price" in grey. After `/run CraftWiseMarketDB.scans = {}` (or a fresh house): the No prices state with Show vendor-only profits. With the newest scan over 24 h old: the Stale card, and the AH figures in the notes carry "3 d" in red.
- [ ] Sell › Auctions with something listed, sold and expired (post with Blizzard's auction house): three folded cards side by side (no card behind them): "On its way · in the mail" (sold, after cut and deposit back), "If all listed sell" ("N listed · 1 without a buyout not counted" with a bid-only listing), "Returning" ("1 item", "expired, deposit lost 15s"). Sub bar right: "<name> · owned list read 12 min ago" (open the Auctions tab of the auction house once to read it).
- [ ] The list: Sold first (newest sale first), then Listed (ending soonest first) with an orange diamond before "Listed", then Returning in grey. When: "ends in 11 h", "sold 19 min ago", "expired · 2 min ago". You get: buyout less the cut plus the deposit back; compare it with the sale mail's money (`received` in `CraftWiseMarketDB.auctions`). Hover a "—": why it is not counted.
- [ ] Mail delay for #155: note how long after "A buyer has been found" the sale mail arrives, and how long after expiry the returned item arrives. With those verified the When column can say "mail in 41 min" as the board shows.
- [ ] Sell › Ledger opens on Per day: one row per recorded day, newest first, Today with the turkuaz nokta and the selected background; Start, Spent (−), Received (+), the money change rail (zero at 30 %, losses red to the left, all rows on one scale, today's bar white) and the signed figure. Hero "Last N days": the money change over those days, Spent, Received, Not from logged trades ("loot, quests, mail").
- [ ] Chips Since reset, Today, Since login: the item list (Item, Bought at, Bought, Sold, Net) and that period's hero; the chip you pick stays after a `/reload`. `/craftwise ledger today` opens the page on Today (and still prints to chat); `/craftwise auctions` opens Sell › Auctions.
- [ ] Reset ledger (footer, right): the first click turns it red "Click again"; wait 3 s: back to "Reset ledger", nothing reset. Click twice quickly: the page switches to Since reset and its list is empty.

## Gather: Farm, Fishing, Crates (#156)
Needs a **full game restart**: three new files in the TOC (`UI/Main/Pages/Farm.lua`, `Fishing.lua`, `Crates.lua`), and three left it (`UI/ProfitFrame/Fishing.lua`, `UI/Records/Crates.lua`, `UI/Records/FishingLog.lua`); `/reload` is not enough. Compare with the boards "Gather › Farm", "Gather › Fishing" and "Gather › Crates" (canvas page Screens).
- [ ] Gather has three real pages (Farm, Fishing, Crates); none says "has not moved here yet". The profit window has no Fishing button any more and its view buttons don't overlap; the Records window has three tabs (Market, Where to buy, Snapshot).
- [ ] Farm, no session: the hero card reads "Farm tracker" / "No session running" with the hint under it and a white Start button right; no Coin / Items at AH / Vendor only columns. Start: the session starts, the card's dog-ear and label turn orange ("Running now · 0:00:01"), the timer counts once a second while the page shows, and gold per hour appears in big mono digits after the first minute. The three columns line up under their labels, "Open tracker" (line button) and "Pause · End in the tracker" sit right and don't touch the columns. Pause in the tracker: label "Paused · …" grey, grey dog-ear.
- [ ] Farm list: "Finished sessions" + note; the open session on top (Started and Time orange while it runs), then finished sessions newest first: Started "Wed 11 · 21:04", Zone (+N more zones, "· fishing"), Time "1:48", the gold-per-hour rail (all bars on one scale, the opened row's bar white), Total, Per hour (bold). Headers sort; the open session stays on top. Empty history: the grey line "No finished session yet. End one in the farm tracker and it shows here."
- [ ] Click a finished session: the card opens under it (nokta on the row): Top items (quality colours, ×N), Zones (time), Split (coin, AH · vendor, unpriced, stale AH part in red, fishing line), "N loot lines kept" and Loot log right. Hover lines: item tooltip, or the light tooltip for zones and the split. Loot log: the log in the same place, newest first (time, icon, name ×N, value with AH/vendor, zone; catches with the fishing icon), "Show 50 more" for long logs, Summary goes back. A session older than the newest 10: "loot log not kept" with the reason on hover. The card's height fits its content (nothing cut off, no empty band) at UI scale 1 and 0.64.
- [ ] Click the open session: Zones, Split, Loot log, then "Items · N" with every looted item, its value and ×. Hover ×: the light tip "Remove from this session". Click ×: the item leaves the list, the tracker and the log; it is ignored until the session ends. Right-click an item line: the item menu; Shift-click: the link in chat.
- [ ] Farm tracker: Log opens the main window on Gather › Farm with the open session's loot log; "+ N more" with its items; History (link, and the no-session button) on Gather › Farm. Settings › Farm history does the same.
- [ ] Fishing › Spots: chips Spots / Log | All water / Pools / Open water at the sub bar's right, the chosen ones white; no hero card. "Where to fish" with the rate line: "gold per hour = value per catch × your catch rate (N catches/h, your last 90 days) · Fishing <skill>"; below the own-catch minimum "~N catches/h from n of m timed catches" and the Per hour figures carry "~"; without any timed catch "no catch rate yet". Zone, Your data (grey under the minimum; hover says which side the zone shows), Gold per hour as a tick with a thin grey range line (stack range), Per catch ("no price" when nothing is priced; hover: source, range, unpriced), Per hour (bold). Footer: the minimum and "reference: loaded (date)".
- [ ] Click a zone: "Reference · n = …" or "Own catches · n = …", then per fish: icon, name in quality colour, Share of catches (grey bar + %), Share of money (gold bar + %), Each (coin colours with AH/vendor/contents); junk (grey items) as one line "Junk: …" with "vendor". "Show own catches" / "Show reference" switches the side when the zone has both. Items the client hadn't loaded get their name and icon by themselves.
- [ ] Pools / Open water: Your data counts only that water's own catches and the rate line names that water's rate ("in pools"); the choice stays after `/reload`.
- [ ] Fishing › Log: "Fishing log · last 90 days · N catches · sessions: …"; one row per zone · subzone and water (open water, pool name, not known yet) with catches, per catch, per hour (bold, "not timed" grey); pools only seen have a row with "—". Click a pool row: "Visits: …" and the items caught there with share and value. Footer: the Find Fish state. Same numbers as `/craftwise fishing`, `/craftwise fishing pools|open`.
- [ ] Crates: the sub bar says "Merchant's Favor on this character: N". Two folded cards side by side (Best of the crates you hold / Best to buy and fill) with name and the line under it; "None priced" when there is none. Rows: icon, crate name with "10 Favor · measured" (or "· tooltip", or "reward not seen yet") under it in grey, Crate, Fill ("no price" grey when no bundle has a price), the cost-per-Favor rail (shorter = cheaper), You hold, Per Favor (bold). Carry a crate and open the page: it shows up within a few seconds. Click a row: crate price, every bundle with its price (cheapest marked), the reward and how it was measured, what is missing in red.
- [ ] Every Gather page in combat: open, switch chips and rows, no error. Hairlines and rails stay one pixel at UI scale 0.64.

## Crate Favor guide (#176)
Needs a **full game restart**: `Data/CrateFavorGuide.lua` is a new file in the TOC; `/reload` is not enough.
- [ ] Gather › Crates: a crate you never turned in and whose tooltip states no reward (Apprentice/Journeyman/Expert, not Artisan) shows "5 Favor · guide" (value by rank and kind) under its name, and is ranked by cost per Favor. Opened, the Reward line says "guide (Forever Mastery, Forever Changes), not measured". An Artisan crate still says "reward not seen yet".
- [ ] After one turn-in of that crate the note changes to "N Favor · measured" and the guide value is no longer used; a crate whose tooltip states the reward says "· tooltip".

## Look up, Music, Settings (#157, part 1)
Needs a **full game restart**: four new files in the TOC (`UI/Main/Pages/Items.lua`, `Upgrades.lua`, `Music.lua`, `Settings.lua`), and three left it (`UI/ProfitFrame/SongPicker.lua`, `UI/Records/Market.lua`, `UI/Records/Where.lua`); `/reload` is not enough. Compare with the boards "Look up · Items", "Look up · Upgrades", "Music" and "Settings" (canvas page Screens).
- [ ] Look up, Music and the gear open real pages; none says "has not moved here yet". The profit window has no Upgrades or Music button and its view buttons don't overlap; the Records window has only Snapshot left.
- [ ] Items: the search box (300 wide, white border) sits right in the sub bar with its grey hint. Type a name: the left list shows recorded items (AH and merchants), exact name first; an item ID or a link works too. Click into the box, then Shift-click an item in the bags: its link lands in the box (not in chat) and the list shows it. Enter picks the first row.
- [ ] Items left list: chips Your recipes / Recent (Watched only once #165 is in). Rows: icon, name in quality colour, "214 listed" / "3 listed · thin" / "vendor only" under it, typical price in coin colours, the 7-day change under it (▲ +4 % red, ▼ −12 % turkuaz, "latest only", "vendor"). The chosen row is on the selected tint. Right-click: item menu; Shift-click: link in chat; hover: item tooltip. Recent keeps the last items you looked at across `/reload`.
- [ ] Items card: 40 icon, name (quality colour), "Trade Goods · stacks of 20 · you have 6 in bags, 40 in the bank" (hover: which places were counted); the four figures (Typical big, Lowest now, On the AH, 7 days) line up; hover each: its reason (median of n days, cheapest tiers, 7-day range, disappeared units, other houses, Auctionator).
- [ ] Items chart (**Line objects**): the typical price is a solid white line, the lowest a dashed grey one, the nokta sits on today's point, the top and bottom prices and "Thu 6" / "Today" read clearly; lines are crisp at UI scale 1 and 0.64. If `CreateLine` fails in this client the page errors on drawing the chart: report it (the fallback, seven 4 unit bars, is covered by the specs only).
- [ ] An item outside the market scope (e.g. a grey item seen in a full scan): "latest only" on the row and the Typical figure, no chart, the line saying why.
- [ ] Items "Used in" (profession · recipes · known, then the known recipes ×N) and "Where to buy" (merchants with prices, hover: the full `/craftwise where` lines), vendor sell price, your last purchase from the ledger.
- [ ] Item menu (bags, any row): Where to buy and Price history open Look up › Items on that item. On gear: "Don't suggest as upgrade" / "Suggest as upgrade again"; not on other items.
- [ ] Upgrades: no column header row; group rows "You can craft" (your professions and skill) and "From the auction house" (when you last searched) with the 2 unit white rule. Rows 40 tall: icon, name in quality colour with "known · reagents in bags" / "learn: trainer 45s" / "4 listed · 2 h ago" under it, Slot, "replaces …", Gain ("+6 AGI +4 STA · +31 armor"), Cost (coin colours; "~" when a reagent has no price). Hover Gain: every stat difference; Cost: reagents and what you hold / the listing.
- [ ] Upgrades AH group: with the AH closed, "open the auction house to search" right in the group row and the "Search AH for these" chip grey and not clickable. Open the AH: the chip works; click it: it reads "Searching 3 of 15 · Shoulder" in orange while it runs, rows appear as slots answer. Dismiss a row from the item menu: it goes; Settings › Bags and loot › Show dismissed upgrades lists it again, desaturated with "dismissed".
- [ ] Music: rows for Party and every profession: name and skill, Song and Video dropdowns (white border on hover, ▾), Next cast Resume / From start (Party has none), the volume slider. Song dropdown: "No song" and every song; Play previews, Stop stops, a song added by name has ×; choosing closes it; a click elsewhere or Escape closes it and stops a preview. Same for Video.
- [ ] Music: cast a profession with a song: the orange Playing card appears within a second ("Playing · while you cast Leatherworking", song, "chunk 7 of 22 · resumes here next cast", the time bar moving), with Music on and Party! on the card; they move back to the list bar when nothing plays. Party! starts the party (card "Playing · Party", button "Stop party"). Add a song by file name under the rows: message under the box.
- [ ] Settings: gear filled; group list 170 wide on the darker ground, the nokta on the open group; rows label left, control right, hairlines between. Every group: Look, Prices, Tooltips, Bags and loot, Loot toast, Farm tracker, Fishing, AH rule, Snapshot. Each control changes what it says (see the spec in `tests/settings_page_spec.lua`); nothing overlaps at UI scale 1 and 0.64, the Snapshot grid (18 sections, two columns) fits.
- [ ] Settings › Look: Scale slider applies when you let go (70–130 %), the window resizes in place; Lock position stops dragging the header; Close with Escape off: Escape no longer closes the window; Minimap button hides/shows it; Reset window positions puts the main window, the farm tracker and the loot toast back in their default places.
- [ ] Settings › Bags and loot › Bag slot marks off: the gold and grey corners leave the bag slots (open bags refresh), on brings them back.
- [ ] `/craftwise settings` opens the Settings page. Every page above in combat: no error.

## Background alpha per window (#162)
No new file in the TOC, so `/reload` is enough. Compare with the Colours paragraph of #150.
- [ ] Settings › Look: three sliders, Background · Main window / Farm tracker / Loot toast, 20–100 %, defaults 96 / 86 / 70 %. Drag the main one: the window's sheet, its cards (hero card, list cards, Crates, Auctions) and the header planes get see-through while you drag; text, icons, rails and the nokta stay fully opaque. Compare the shadow: it fades with the sheet.
- [ ] The header's baked planes carry the gold key block too (one texture): check that it fading with the planes looks right at 20 % (open question in the PR).
- [ ] Farm tracker slider: the tracker's sheet and its fishing card follow while dragging, also in mini mode. With "Fade to 40 %" on, away from the mouse it ends at about alpha x 0.4 (the two multiply); hovering brings it back to the slider's value, not to 100 %.
- [ ] Loot toast slider (Look and Settings › Loot toast, same value): with no toast on screen the three test lines appear and follow the slider; with real loot on screen those strips follow. The newest line's turkuaz flap stays solid.
- [ ] The values survive `/reload`. Item menu, the Music dropdown and tooltips are not affected (always solid).
- [ ] Every window at UI scale 1 and 0.64: sliders do not overlap other rows.

## Items watch list (#165, part 1)
Needs a **full game restart**: new file `ItemWatch.lua` in the TOC (before `UI/Style.lua`); `/reload` is not enough.
- [ ] Item menu (right/middle click in the bags, any row): a "Watch" line after Price history; click it and the menu closes. Open the menu again: the line reads "Stop watching"; click it and the item is no longer watched. Quest items can be watched too.
- [ ] Look up › Items: chips Watched / Your recipes / Recent (a fresh install opens on Your recipes). The Watched chip lists the watched items by name; empty it says "Watch an item from its card and it shows here."
- [ ] Items card: the Watched toggle (top right) is white when on. Click it: the item joins or leaves the Watched chip at once. Watch an item from the item menu while the Items page is open on it: the card's toggle follows without reopening the page.
- [ ] `/reload`: the watched items are still there. `SavedVariables/CraftWise.lua` has `["watch"] = { [itemID] = <Unix time>, ... }` (account wide, the same file for every character).

## Make: Craft, Learn, Level up (#154)
Needs a **full game restart**: five new files in the TOC (`UI/Main/Pages/Make.lua`, `MakeTooltips.lua`, `Craft.lua`, `Learn.lua`, `LevelUp.lua`), and nine left it (the whole `UI/ProfitFrame/` and `UI/Main/Pages/Bridges.lua`); `/reload` is not enough. The old profit window is gone: Profit, Learn and Level were its last views. Compare with the boards "Window layout · Make › Craft" (page One design), "Make › Learn", "Make › Level up" and "States" (page Screens).
- [ ] Make has three real pages (Craft, Learn, Level up); no page anywhere says "has not moved here yet". The Records window's "Main window" button (it said "Profit window") opens the main window. Since #157 the Records window is gone, and with it that button.
- [ ] Sub bar right: the profession chip "Leatherworking 191 ▾" (name white, skill grey, caret) left of the 160 wide filter box ("Filter recipes" in grey until you type), 18 apart. Click the chip: a folded menu under it with your crafting professions (no gathering ones), the current one with the nokta and the dark background; pick another: all three pages switch, and it is still chosen after `/reload`. Click elsewhere or Esc closes the menu; the chip again closes it too.
- [ ] Type in the filter: the rows filter by recipe or reagent name ("light leather" lists the recipes using it) on all three pages; Esc / Enter leave the box. Raise a skill (or `SKILL_LINES_CHANGED`): the chip shows the new skill without reopening.
- [ ] Craft: hero "Best craft right now": name, "Yellow · skill-up 58% · short 4 Heavy Leather" (colour word in the skill colour; "~41%" for the formula; nothing short: no short part), the bar in the middle (grey cost, then the white profit, 6 tall, along the sale) with "cost …" / "sells … · AH" under it, the profit in big mono coin digits on the right. No priced recipe: "—" and the reason.
- [ ] Craft list: "N recipes" + "by profit"; chips Unlearned and Hide unpriced right, white when on. Rows 38: output icon, name in the profession window's colour (unlearned: white), the profit rail (zero line at 18 % of the column, all bars on one scale, losses red to the left, the opened row's bar white), "1g 50s → 2g 70s AH" grey (the → is a small texture in line with the digits; "vendor", "AH gross", "· thin", stale "3 d" in red), the profit bold right ("+" coin colours, "−…" red, "—" grey without a price; hover the "—" for the reason). Footer: "Prices: typical · Horde AH · reagents: AH" left; hidden and cut-unverified counts right.
- [ ] Click a Craft row: the folded card under it (nokta on the row): up to four reagents per line, each "10 Heavy Leather", the total in coin colours, "AH · have 6" grey; Price history (line button) right opens Records › Market on the crafted item (Look up › Items once #157 lands). Hover a reagent: its item tooltip; right-click: its item menu. Click again closes; one row open at a time.
- [ ] Hover a Craft row: the crafted item's tooltip, then one CraftWise section (W key header): skill-up thresholds, reagents with their source, the buy list, Sells for with Vendor / AH net (used one marked), auction houses. The item tooltip's own CraftWise lines do not appear a second time. Right-click: the item menu of the crafted item; Shift-click: its link in chat.
- [ ] Learn: hero "Best recipe to learn": name, "Trainer · <name> · you meet skill 190", "Learn cost" with the fee in the middle, "Pays off after" over "3 crafts" right. List "N recipes you don't know" by profit; columns Recipe (white), Skill (orange above yours, "unknown" grey), Where to get it (grey, "+N" more), To learn ("unknown" grey), Profit/craft, Pays off ("8 crafts", "—"). Chips Fits my skill and Hide unpriced; the footer right counts what they hide. Click a row: where to get it (up to six lines) above the reagents.
- [ ] Level up: hero "Best skill-up right now": "Yellow · earns +1g 20s per craft after selling it", "Skill-up chance" with "58%" and an 8 tall bar, "measured · 12 of your crafts" (or "estimate · community formula"), "Per skill-up" over the figure. List "Known recipes that still give skill" + "best value per skill-up first: earning, then cheapest", right "Sale: AH after cut …". Chance: 60 unit bar (white measured, grey estimate) and the percent ("~41%" grey). Net/craft and Per skill-up: "+" earns, "−" red costs. Footer: "Chance: … Grey recipes are left out." and the reagent basis and crafts recorded. Hover: the chance maths.
- [ ] States on each Make page: a profession whose window you never opened: the W key, "Open your <profession> window once." (the chip stays to pick another). Fresh market data (`/run CraftWiseMarketDB.scans = {}`): "No auction house visited yet." and Show vendor-only profits. A scan running at the AH: orange header status and progress line, rows keep their figures, rows without a profit show a skeleton bar stepping between two greys. Newest scan over 24 h old: the Stale card, "3 d" in red after AH figures.
- [ ] Item menu › Recipes using this (on a reagent in your bags): the main window on Make › Craft with that profession, Unlearned on and the reagent's name in the filter box.
- [ ] All three pages in combat: switch pages, chips and rows, no error. Hairlines and rails stay one pixel at UI scale 0.64; long recipe and reagent names are cut, not overlapping.

## Old windows retired, gaps closed (#157 part 2)
Needs a **full game restart**: five files left the TOC (`UI/Records/State.lua`, `Snapshot.lua`, `Frame.lua`, `UI/Settings.lua`, `UI/AHRule.lua`); `/reload` is not enough.
- [ ] No old window is left: no Records window, no old Settings or AH rule panel. The gear in the main window header opens the Settings page; nothing else opens a separate settings panel.
- [ ] Header AH status (on Make, Sell › Bags and the other price pages): hover it. A light tooltip "Auction houses" lists every house CraftWise recorded at, your faction's first, the profit house marked "(profit)": "Horde AH (profit): full scan 2 h ago · 1 240 items, 980 with history", a neutral house you only browsed "no full scan"; then "Auctionator (house unknown): N items read" when CraftWise read Auctionator prices. Compare the counts with what Records › Market's summary line showed before.
- [ ] With Auctionator installed and its prices loaded, on a character or house where CraftWise has recorded nothing (e.g. set Auction house for profit to your faction on a fresh character): Make › Craft shows the list, not "No auction house visited yet."; the header says "Horde AH · Auctionator prices"; AH figures say "Auctionator (house unknown)" on hover. Disable Auctionator and `/reload`: the page says "No auction house visited yet." again.
- [ ] Make › Craft, Learn and Level up: open a row. Right of the reagents: Price history, and under it "Open in profession window". Click it: the profession window opens on that recipe (with the profession window closed, and with it open on another recipe). On Learn, for a recipe you don't know yet: report what the client does (opens it greyed, or nothing). Nothing overlaps the reagents with four reagents on a line or with where-lines on Learn.
- [ ] Slash commands open their page: `/craftwise market <link>` and `/craftwise where <link>` (Shift-click an item into the chat box) open Look up › Items on that item; `/craftwise where <name>` puts the name in the search box as typed (capitals kept); `/craftwise ledger`, `auctions` (Sell); `crates`, `fishing`, `fishing pools`, `fishing zones`, `farm history` (Gather); `settings`, `snapshot`, `ahmin`, `loottoast …`, `minimap`, `farm lock`, `fishing gap 5` (the matching Settings group). `/craftwise farm` still only toggles the tracker, `/craftwise party` (the party key's macro) only toggles the party, `/craftwise debug` only prints.
- [ ] The video clip window (Music, a profession with a video): a dark sheet with a thin rule round the clip (the old flat panel is gone); it still drags and remembers its place.
- [ ] Recipe tooltips with reagents you hold ("Your reagents", "Crafts possible", "To buy for N crafts"): the same colours as before (grey notes, yellow warnings, green crafts possible).
- [ ] An old `CraftWise.lua` from before this change: after login the saved `settings` no longer has `view`, `sortKey`, `bagSortKey`, `recordsTab` and the other keys only the old windows used; everything else (AH rule, prices, costs) is unchanged.

## Docked layout (#161)
Needs a **full game restart**: new file `UI/Main/Docked.lua` in the TOC (after `UI/Main/Frame.lua`) and a new texture `Media/cw-undock.tga`; `/reload` is not enough. Compare with the board "Docked layout, on your screen" (canvas page One design). Items, Settings, Music and the multi-card heroes have no docked board yet: what they do docked is provisional (#161 Q1–Q4 in the PR) and may change.
- [ ] Fresh profile (`/run CraftWiseDB.settings.ui = nil` + `/reload`): the window opens as Window. The dock button (left of ×) docks it to the left edge; with `/run CraftWiseDB.settings.ui.lastDocked = "dockRight"` it docks right. The sheet slides in from its edge in about 0.2 s, without fading or bouncing. The undock button (frame with a title bar line, tooltip "Undock to a window") puts the window back where it was.
- [ ] Docked: 380 wide, 20 from the screen edge, 20 from the top and the bottom of the screen at UI scale 1 and 0.64 (resize the game window too: the sheet follows the screen height). Not draggable; Lock position makes no difference. Background alpha (Settings › Look) applies to the sheet as in the window.
- [ ] Shift-click on the minimap button docks and undocks; with the window closed it opens docked. Its tooltip lists "Shift-click: dock / undock". Settings › Look › Layout: Window / Docked left / Docked right swaps in place from either layout (the docked Settings page has the same control across the row).
- [ ] Docked header 64: the narrow gold key block with the W key (34) sharp, "CraftWise" white on the dark plane at x 128 with the AH status under it (Scanning orange with the nokta before it, Stale red bold), gear, undock, × right; the five section tabs on their own row under it (gap 20, active white with its 3 unit bar on the hairline). The tabs, gear and buttons click; the status never runs under the gear.
- [ ] Sub bar 40, padding 18. Make, Sell and Gather: the page tools (profession chip and filter box, Bags chips, Ledger periods, Fishing chips, the Crates / Auctions / Upgrades / Farm lines) sit in their own row above the list, the list title over its note in the list header with the chips right. Nothing overlaps at UI scale 0.64 (Fishing's five chips are the widest).
- [ ] Hero cards stacked: label, name left and the figure right on one line, the rail or bar under, the sub-line last (Craft: cost and sells under the bar; Learn: "Pays off after" top right; Level up: the chance bar and how it was found). Bags: the total, the three-part bar, one line per part with its square; Ledger: the change, then Spent / Received / Not from logged trades; Farm: gold per hour, Coin / Items at AH / Vendor only, Open tracker (Start without a session). Auctions and Crates: their cards one under the other (provisional Q4).
- [ ] Rows 44 in two lines: icon, the name over its rail (or a grey note line), the result right in bold with the sub-figure under it; all rails of a list on one axis. Bags and Upgrades group headers with the 2 unit rule; the Bags mark as a small tag under the value; Auctions' orange diamond before "Listed"; Ledger's today with the nokta and the selected tint. Click opens a row in place (card 18 from both edges; Make: two reagents per line, Price history and Open in profession window side by side under them; Farm: Top items, Zones and Split one under the other; Fishing: the share bars under each fish); right-click item menu, Shift-click link, hover tooltip and the "—" reasons work as in the window. Mouse wheel scrolls.
- [ ] Look up › Items docked (provisional Q1): the list across the sheet with the chips at its top and the search box (170) in the sub bar; click an item: its card across the sheet (figures two by two, the chart, Used in over Where to buy; wheel scrolls it) and Back in the sub bar in place of the search box; Back returns to the list. Item menu › Price history opens the card.
- [ ] Settings docked (provisional Q2): one list with every group under its header and 2 unit rule, each label over its control, segmented controls across the row; the wheel scrolls it; every control still writes its setting. Music docked (provisional Q3): the Playing card stacked (time bar across, Music on and Party! under it), each profession row with Song, Video, Next cast and Volume one under the other; the dropdown menus open next to them.
- [ ] States docked: First run (the profession chip stays above it), No prices, Stale card, Scanning skeletons in the result spot, Error with Reload UI and Show error text all fit 380 without running over the edge.
- [ ] Switch layouts on every page, with a row open: the same row stays open; nothing from one layout stays drawn in the other. In combat: dock, undock, switch pages, no error.

### Make › Craft › Vendor check (#185)

- Open Make › Craft on a profession with known recipes, turn on the Vendor check chip: the list holds only crafts with a vendor profit above 0, best first, each sale tagged "vendor"; with Unlearned on/off the list changes accordingly. Hero label reads "Best vendor craft right now".
- A craft whose reagents are all sold by vendors (thread, vials, flux, dyes; visit the merchants once so prices are recorded) and whose product a vendor buys for more than that shows "· loop" after the sale. Buy the reagents, craft once, sell to a vendor: the gold gained matches the vendor profit shown.
- Hover a row: the "Vendor check" section lists each reagent with AH price, vendor price and which was used, then the vendor sale and profit. A product no vendor buys never shows up with the chip on; a reagent without a vendor price shows "not sold by a vendor".
- Chip off: nothing changes except the loop tag on loop rows. After a client patch changing sell prices, the vendor sale follows the client's price.
- No new file: `/reload` is enough.

### Vendor loop alert and basket (#186)

- **New files (Loops.lua, Basket.lua, Pages/Basket.lua): restart the game completely, `/reload` is not enough.**
- Settings › Vendor loops: Loop alert on, Smallest profit per craft at 0. Visit the AH with a full scan (or a merchant once) while a known craft has a vendor profit: one toast "N vendor loops / M vendor profits" with the best craft and its profit per craft, about 10 s. Browsing more AH pages right after gives no second toast; a new or clearly better (+50 %) find does. Click the toast: Make › Craft opens with Vendor check on. Shift-click: the best craft goes into the basket and Make › Basket opens.
- Raise Smallest profit per craft above the best find: no toast. Loop alert off: no toast.
- Make › Craft, open a row: "− +" and "Add N to basket" under the reagents. Make › Basket lists the crafts (open one: − + +10 Remove), then AH lines, vendor lines, items without a price, and what is already in the bags; the hero shows the AH and vendor totals and the expected vendor profit.
- Put some of the reagents into your bags: those lines move to "in bags" (BAGS_CHANGED), no reload.
- With Auctionator: the Auctionator list chip creates/replaces the shopping list "CraftWise basket" (check it in Auctionator\x27s Shopping tab: exact names with quantities). Without Auctionator: an AH line opens to a search string to copy.
- Open a merchant that sells a vendor line (plain gold, sold one at a time): open the line, Buy N is enabled; one click buys exactly that quantity (more than a stack = several BuyMerchantItem calls in that click, check the bags). Sold in lots, with a currency cost, sold out, or not enough gold: the button stays off and says why. Closing the merchant disables it. Nothing is bought without the click.
- Item menu: Open basket opens Make › Basket. Clear basket empties it.

### Disenchant values and Disenchant check (#190)

- **TOC changed (OptionalDeps: Disenchantry, new Data/DisenchantGuide.lua and Disenchant.lua): restart the game completely.**
- Without Disenchantry, or before any disenchant: Make › Craft › Disenchant check lists crafts of uncommon or better armour and weapons with the sale tag "disenchant · guide"; the tooltip says "Classic table (guide)" and "not measured on Forever". Settings › Disenchant says the guide is used.
- With Disenchantry loaded: disenchant an uncommon or better armour or weapon (Enchanting open), `/reload`. The same item now shows "disenchant · N samples" (or "few samples" below Settings › Disenchant › Few samples below), the tooltip lists the materials with chance, quantity, unit price and "measured, N disenchants". Another item of the same quality, type and item-level bracket shows "pooled N".
- Check the sample key in `WTF/Account/<account>/SavedVariables/Disenchantry.lua` (`disenchantSamples`): `<version>:<build>:<itemID>:<quality>:<baseItemLevel>:<classID>:<normal|salvager>`; CraftWise reads it as is and never writes it. After a client patch (new build) the old samples are ignored until new ones exist.
- With the Arcane Salvager buff (1283701) active the tooltip says so and only salvager samples count; without the buff the normal ones. Without salvager samples the guide answers.
- Sell › Bags: a disenchantable item with a value shows in the Disenchant group when that pays most; its value matches the Craft tooltip per item. Vendor check and Disenchant check cannot both be on (turning one on turns the other off).
- Enchanter wands (Lesser Magic Wand etc.) get no value.

## Performance recorder: stutter when opening bags or a vendor (#194)

- **TOC changed (new Perf.lua): restart the game completely.**
- Settings › Debug. Press **Record**, then do the thing that stutters: open the bags (all of them, or the combined bag), close, open a vendor, close it. Press **Stop**. The report appears under the buttons; **Copy report** opens it in a box with the text selected (Ctrl+C, paste it into the issue).
- While Record is on the button says Stop and is lit. With Record off CraftWise times nothing (the recorder is a single `nil` check in the event dispatch).
- Report, top to bottom: frame count and worst frame; the slowest frames with how much of each was CraftWise handlers and which handler was slowest; CraftWise events, handlers (`EVENT File.lua:line`), module callbacks and the BagIcons hooks, each with total ms, count and longest run; the other addons' slow ticks (over 5 / 10 / 50 / 100 ms) during the recording from `C_AddOnProfiler`, and the top addons by recent average and by peak since login.
- Check that a slow frame (over 30 ms) shows up in the list when you open the bags, and that "CraftWise inside it" tells whether CraftWise or another addon (Auctionator, Bagnon, Disenchantry, ShortestPathForever) holds the time. If every handler shows ~0 ms while the frame is long, the cost is outside CraftWise handlers: read the addon table.
- If the handler labels read `#12` instead of `Bags.lua:40`, `debugstack` returned an unexpected format: report the line.
- No Lua error from `C_AddOnProfiler` calls (all wrapped; a missing function only leaves its lines out).

### After the first recording: vendor price news and item loads (#194)

- Open the same vendor twice, and flip its pages: with unchanged prices CraftWise does no price work after the first visit (`PRICES_CHANGED` fires only for a vendor price that is new or different, and Crates no longer rescan the auction house items for it). Record once more: `MERCHANT_SHOW` should be a few ms at most and `Crates.lua` should not show under Module callbacks. The bag-frame and vendor hitches that remain are listed in the report under "Addons".
- The report now ends its CraftWise section with "CraftWise asked the client to load N items (M more skipped)" and the callers. Every load the client answers is an event that every addon with a `GET_ITEM_INFO_RECEIVED` handler runs; compare N with the event counts (`GET_ITEM_INFO_RECEIVED`, `ITEM_DATA_LOAD_RESULT`) of the same recording.
- **Hitches from Baganator or Syndicator are outside CraftWise.** If the slowest frames show "CraftWise inside it" at a few ms and the Addons table lists Baganator / Syndicator (or GearQuestForever, ShortestPathForever) with ticks over 50 or 100 ms, the time is in those addons. CraftWise cannot fix it; report it to them, or try bags with only one of them enabled.

