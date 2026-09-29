# CraftWise

WoW: Forever addon: crafting profit for every recipe you know **or can learn**.

Type `/cw` to open the profit table. `/cw debug` prints what is cached.

## What it does (MVP)
- Reads every recipe of a profession (learned and unlearned) when you open the profession window, and caches it per character.
- Prices reagents at the cheaper of the AH (Auctionator) and the vendor price you last saw at a merchant.
- Sells-for is the AH price after the 5% cut, or the vendor sell price when that is higher.
- Records trainer fees and required skill when you open a profession trainer, so unlearned recipes show learn cost and how many crafts it takes to pay off.
- A missing price is never counted as 0: the row shows `?` instead of a fake profit.

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
