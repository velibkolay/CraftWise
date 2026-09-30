# CraftWise

WoW: Forever addon: crafting profit for every recipe you know **or can learn**.

Type `/cw` to open the profit table. `/cw debug` prints what is cached.

## What it does (MVP)
- Reads every recipe of a profession (learned and unlearned) when you open the profession window, and caches it per character.
- Prices reagents at the cheaper of the AH (Auctionator) and the vendor price you last saw at a merchant.
- Sells-for is the AH price after the 5% cut, or the vendor sell price when that is higher.
- Unlearned recipes you've seen at a trainer show the skill they need, the fee and how many crafts it takes to pay off.
- A missing price is never counted as 0: the row shows `?` instead of a fake profit.

## Bundled data
`CraftWise/Data/Recipes.lua` and `Data/Vendor.lua` come unchanged from [cjber/skillup-forever](https://github.com/cjber/skillup-forever) (GPL-3.0). Both are generated from the WoW: Forever client's own DB2 tables (via wago.tools): recipe reagents and outputs, item sell prices, and vendor buy prices (the list of vendor-sold reagents is from LibPeriodicTable, LGPL-2.1). Prices seen at a merchant in game always win.

Recipe sources, required skill to learn and skill-up thresholds are **not** bundled until reliable Forever data is available (#11). Until then only first-hand data is used: recipe colours from the client and trainer fees recorded when you open a trainer.

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

## Roadmap
Planned work lives in [GitHub issues](https://github.com/velibkolay/CraftWise/issues) grouped by [milestones](https://github.com/velibkolay/CraftWise/milestones).

