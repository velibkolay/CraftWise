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
- Left-click a profession cycles songs, right-click switches resume / start from the beginning.
- Skinning: music starts with the cast and stops when the cast ends (also when interrupted by moving). Next skin continues from the same part (resume) or from the start (restart).
- Pressing another ability during a cast doesn't stop the music.
- Listen for gaps or clicks between 2 s chunks; if audible, try `--chunk 4`.
- Channel is Master: master volume applies, game music keeps playing underneath (turn it down in Sound settings if needed).

## Learning a recipe (#3)
- Buy a recipe at the trainer with the CraftWise window open: it leaves the Learn view right away (no profession reopen). Which event fired is not logged; if it does not update, report it.
