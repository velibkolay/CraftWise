-- Issue #93: the companion's Go port of Market.lua's packed entries is golden-tested against
-- companion/market/testdata/golden.lua, which tests/companion_fixtures.lua writes from this Lua code.
-- This spec fails when Market.lua's format changes without the golden file being regenerated
-- (`lua5.1 tests/companion_fixtures.lua`, then `go test ./...` in companion/).
local G = dofile("tests/companion_fixtures.lua")

local function Read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

it("#93: the golden market entries match what Market.lua writes now", function()
	local ns = LoadAddon()
	local now = G.Golden(ns.Market)
	local saved = Read(G.GOLDEN)
	assert(saved, G.GOLDEN .. " missing: run lua5.1 tests/companion_fixtures.lua")
	assert(saved == now, G.GOLDEN .. " is out of date: run lua5.1 tests/companion_fixtures.lua and the Go tests in companion/")
end)

it("#93: the golden file covers last-only, history, days and the edge cases", function()
	local ns = LoadAddon()
	local text = G.Golden(ns.Market)
	for _, needle in ipairs({ '["packed"] = "to3n9c,28,q,3||"', "negative numbers are written as 0", "random 80" }) do
		assert(text:find(needle, 1, true), needle)
	end
	local M = ns.Market
	eq(M.EncodeEntry(M.DecodeEntry("to3n9c,qglj,1,||")), "to3n9c,qglj,1,||", "browse row round trip")
end)

it("#93: the synthetic SavedVariables fixture is written as the game writes them", function()
	local text = Read(G.SAVED)
	assert(text, G.SAVED .. " missing: run lua5.1 tests/companion_fixtures.lua")
	assert(text:find('CraftWiseMarketDB = {\n\t["auctionator"] = {', 1, true), "layout")
	assert(text:find(', -- [1]\n', 1, true), "list items")
	assert(not text:find("Velikopter", 1, true), "no real character in the fixture")
end)
