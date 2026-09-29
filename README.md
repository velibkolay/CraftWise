# CraftWise

WoW: Forever addon: crafting profit for every recipe you know **or can learn**.

Type `/cw` to open the profit table. `/cw debug` prints what is cached.

## What it does (MVP)
- Reads every recipe of a profession (learned and unlearned) when you open the profession window, and caches it per character.
- Prices reagents at the cheaper of the AH (Auctionator) and the vendor price you last saw at a merchant.
- Sells-for is the AH price after the 5% cut, or the vendor sell price when that is higher.
- Unlearned recipes show how to get them (trainer, vendor recipe, drop, quest), the skill they need, the learn cost and how many crafts it takes to pay off.
- A missing price is never counted as 0: the row shows `?` instead of a fake profit.

## Bundled data
`CraftWise/Data/*.lua` comes unchanged from [cjber/skillup-forever](https://github.com/cjber/skillup-forever) (GPL-3.0), generated there from the WoW: Forever client's DB2 tables (via wago.tools), CMaNGOS classic-db (GPL-3.0) and LibPeriodicTable (LGPL-2.1). It supplies vendor reagent prices, trainer fees, recipe sources, skill-up thresholds (`Thresholds.lua`, partly derived from Skillet-Classic, GPL-3.0-or-later) and reagents for recipes the client hasn't shown yet. Data seen in game (merchant prices, trainer fees) always wins.

## License
GPL-3.0, see [LICENSE](LICENSE).

## Requirements
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (optional but needed for AH prices). Run a full scan at the auction house.

## Install (beta)
Copy the `CraftWise/` folder to `World of Warcraft/_classic_beta_/Interface/AddOns/`.

## Development
```sh
lua5.1 tests/run.lua
```
Tests run headless against a stubbed client (`tests/wowstub.lua`). Anything the stub cannot reach (frames, tooltips, real API shapes) is listed in [docs/ingame-checks.md](docs/ingame-checks.md).

## Later
- Own AH scan (#6)
- Price export to velikopter.com (#7)
