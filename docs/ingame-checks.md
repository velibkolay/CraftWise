# In-game checks

Things the headless tests cannot prove. Run after installing, in the Forever beta.

## Setup
1. Install CraftWise and Auctionator, `/reload`.
2. Auction house: Auctionator tab, **Full Scan**.

## Recipe capture (#1, #3)
- [ ] Open a profession window. `/cw debug` shows the profession with a recipe count that includes unlearned recipes.
- [ ] Count matches the window with the "Unlearned" filter on. If it only counts learned recipes, `GetAllRecipeIDs` respects the filter: report it.
- [ ] `/cw`: unlearned recipes show reagents (tooltip). If they show "Reagents unknown", `GetRecipeSchematic` returns nothing for unlearned recipes.

## Prices (#2)
- [ ] Rows show cost and sells-for after the Auctionator scan.
- [ ] Visit a trade goods vendor (thread, dye) and reopen `/cw`: those reagents show "vendor" in the tooltip.
- [ ] Without Auctionator: orange warning line, no Lua error.

## Trainer (#3)
- [ ] Open the profession window first (recipe names are matched against it), then your profession trainer, then `/cw`: trainer recipes show Trainable / Trainable at N, a learn cost and break-even.

## UI (#5)
- [ ] Window drags, closes with Esc and the X button.
- [ ] Profession buttons switch tables; "Show unlearned" toggles rows.
- [ ] Header click sorts, second click flips direction.
- [ ] Mouse wheel scrolls; Shift+wheel scrolls a page.
- [ ] Row hover: reagent breakdown with source; clicking a row with the profession open selects the recipe.

Report Lua errors with BugSack + BugGrabber.

## Skill-up recorder (#15)
- Craft a few recipes (orange and yellow). `/cw debug` shows "skill-up log: N crafts recorded" = number of crafts.
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
- Key / `/cw party` / "Party!" button: character dances, Party song + video start. Same key stops; walking stops. Check DoEmote works from an addon in Forever.

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
- AH rule: Bags view top right "AH rule: +20%, min 10c" opens a panel: "At least this % more" (5% steps) and "And at least this much more" (0, 1c, 2c, 5c, 10c ... 1g); example line updates; "Defaults" resets. Items under the rule show "Vendor  AH +Xc, too little". Also `/cw ahmin <percent> [copper]`.
- First AH sale of a single cheap item: check the mail amount to learn how the 5% cut rounds (single 8c item -> 7c or 8c).

## Level view (#15)
- New file: full game restart. "Level" button between Learn and Upgrades; profession tabs at the top.
- Rows: known recipes that still give points (grey hidden), best "per skill-up" first. Chance shows % and where it comes from (orange: always / your crafts x/y / all your crafts x/y).
- Hover: thresholds, chance source, reagents, sale (AH after cut or vendor), net, crafts per point, per skill-up.
- Craft a recipe: the view updates (skill and chances) without reopening.
- Check: the skill in the summary matches the profession window; soulbound outputs use vendor price.

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
- Gear button (top right of the CraftWise window) or `/cw settings`: on/off, Always / Only with Shift (tooltip redraws when Shift is pressed), each line on/off.
- Check: TooltipDataProcessor post-call works for bag items in Forever; GameTooltip:RefreshData redraws on Shift.

## Baganator
- Baganator settings > junk: "CraftWise" listed (auto-selected if no other plugin is active); marked items show Baganator's junk coin; marking/unmarking refreshes at once.
- Baganator settings > sorting: "CraftWise" mode; Baganator's sort button sorts the backpack like Sort bags (bank untouched).
