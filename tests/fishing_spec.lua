-- Issue #69: fishing log (catch recording inside the #41 loot flow, container contents, per-zone value
-- summary, /craftwise fishing, snapshot section, 90-day retention). Item IDs are stub data, not real ones.
local NOW = 1794000000
local DAY = 86400
local FISH, OIL, BOOT, CRATE, RING, GEM = 9001, 9002, 9003, 9004, 9005, 9006

local function setup(opts)
	opts = opts or {}
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function() return stub.clock end
	stub.names.player, stub.realm = "Veli", "Forever-EU"
	stub.zone, stub.subzone = "Stranglethorn Vale", "Nek'mani Wellspring"
	stub.mapID = 1434
	C_Map = { GetBestMapForUnit = function(unit) return unit == "player" and stub.mapID or nil end }
	stub.fishing = true
	IsFishingLoot = function() return stub.fishing end
	-- Fast auto-loot (#41) on: auto-loot setting on, no modifier, free bag slots.
	C_CVar.GetCVarBool = function(k) return k == "autoLootDefault" end
	IsModifiedClick = function() return false end
	C_AddOns = { IsAddOnLoaded = function() return false end }
	C_PartyInfo = { GetLootMethod = function() return 0 end }
	C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 10 or 0, 0 end
	-- stub.loot = { { link, qty, coin, sources } }
	GetLootSlotInfo = function(i)
		local s = stub.loot[i]
		if not s or not s.link and not s.coin then return nil end
		return "tex", "name", s.qty or 1, nil, 1, false, false, nil, nil, s.coin
	end
	stub.looted = {}
	LootSlot = function(i)
		stub.looted[#stub.looted + 1] = i
		stub.loot[i].link, stub.loot[i].coin = nil, nil
	end
	stub.items[FISH] = { name = "Test Fish", sellPrice = 6 }
	stub.items[OIL] = { name = "Test Oil", sellPrice = 20 }
	stub.items[BOOT] = { name = "Test Boot" }
	stub.items[CRATE] = { name = "Test Crate" }
	stub.items[RING] = { name = "Test Ring", sellPrice = 300 }
	stub.items[GEM] = { name = "Test Gem" }
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	return ns, stub
end

local function cast(stub, loot, isFromItem)
	stub.loot = loot
	stub.Fire("LOOT_READY", true)
	stub.Fire("LOOT_OPENED", true, isFromItem or false)
	stub.Fire("LOOT_CLOSED")
end

local function log(ns) return ns.db.fishing["Forever-EU-Veli"] end

local function printed(stub)
	return table.concat(stub.printed, "\n")
end

local function has(text, s) assert(text:find(s, 1, true), ("missing %q in:\n%s"):format(s, text)) end

it("records a catch before fast auto-loot takes it: zone, subzone, map, item, count, time, source object", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. FISH, qty = 2, sources = { "GameObject-0-1-2-3-180582-0000AB", 2 } }, { coin = true } })
	eq(#stub.looted, 2, "fast auto-loot still looted the window")
	local c = log(ns).catches[1]
	assert(c, "catch recorded")
	eq(c.items[FISH], 2); eq(c.zone, "Stranglethorn Vale"); eq(c.sub, "Nek'mani Wellspring"); eq(c.map, 1434)
	eq(c.t, NOW); eq(c.obj, 180582, "GameObject of the loot source, stored as the client gives it")
	eq(#log(ns).catches, 1, "LOOT_READY twice or LOOT_OPENED does not count it again")
end)

it("records with fast auto-loot off, and not loot that isn't fishing", function()
	local ns, stub = setup()
	ns.db.settings.fastLoot = false
	cast(stub, { { link = "item:" .. FISH } })
	eq(#stub.looted, 0)
	eq(log(ns).catches[1].items[FISH], 1)
	stub.fishing = false
	cast(stub, { { link = "item:" .. OIL } })
	eq(#log(ns).catches, 1, "a mob's loot is not a catch")
end)

it("logs the contents of a caught container against it when it is opened", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. CRATE } })
	stub.fishing = false
	stub.bags[0] = { { itemID = FISH }, { itemID = CRATE, isLocked = true, hasLoot = true } }
	cast(stub, { { link = "item:" .. RING }, { link = "item:" .. OIL, qty = 3 }, { coin = true } }, true)
	local o = log(ns).opened[1]
	assert(o, "opening logged")
	eq(o.item, CRATE); eq(o.items[RING], 1); eq(o.items[OIL], 3); eq(o.t, NOW)
	-- Loot from an item that wasn't caught (or not from an item) is not logged.
	stub.bags[0] = { { itemID = GEM, isLocked = true, hasLoot = true } }
	cast(stub, { { link = "item:" .. RING } }, true)
	stub.bags[0] = { { itemID = CRATE, isLocked = true, hasLoot = true } }
	cast(stub, { { link = "item:" .. RING } }, false)
	eq(#log(ns).opened, 1)
end)

it("per-zone summary: count per item and value per catch, AH or vendor, containers by their contents", function()
	local ns, stub = setup({ auctionator = true })
	stub.ah[OIL] = 100 -- 95 after the 5% cut, beats the vendor's 20
	for _ = 1, 3 do cast(stub, { { link = "item:" .. FISH } }) end
	cast(stub, { { link = "item:" .. OIL } })
	cast(stub, { { link = "item:" .. BOOT } }) -- no price anywhere
	stub.subzone = "Jaguero Isle"
	cast(stub, { { link = "item:" .. CRATE } })
	stub.zone, stub.subzone, stub.mapID = "Tanaris", "", 1446
	cast(stub, { { link = "item:" .. FISH } })
	-- Open the crate: a 300c ring.
	stub.fishing = false
	stub.bags[0] = { { itemID = CRATE, isLocked = true, hasLoot = true } }
	cast(stub, { { link = "item:" .. RING } }, true)

	local s = ns.Fishing.Summary()
	eq(s.catches, 7); eq(#s.zones, 2)
	local stv = s.zones[1]
	eq(stv.zone, "Stranglethorn Vale"); eq(stv.catches, 6)
	local nek = stv.subzones[1]
	eq(nek.sub, "Nek'mani Wellspring"); eq(nek.catches, 5); eq(nek.maps[1], 1434)
	eq(nek.items[1].itemID, FISH); eq(nek.items[1].count, 3); eq(nek.items[1].unit.copper, 6); eq(nek.items[1].unit.label, "vendor")
	local oil, boot
	for _, item in ipairs(nek.items) do
		if item.itemID == OIL then oil = item elseif item.itemID == BOOT then boot = item end
	end
	eq(oil.unit.copper, 95); eq(oil.unit.label, "Auctionator (house unknown)")
	eq(boot.unit, nil, "no price data")
	eq(nek.value, 3 * 6 + 95); eq(nek.unpriced, 1); eq(nek.perCatch, math.floor((3 * 6 + 95) / 5))
	local jag = stv.subzones[2]
	eq(jag.items[1].unit.copper, 300); eq(jag.items[1].unit.label, "contents of 1 opened")
	eq(stv.perCatch, math.floor((3 * 6 + 95 + 300) / 6))
	-- Zone filter, by zone or subzone, any case.
	eq(ns.Fishing.Summary("tanaris").catches, 1)
	eq(ns.Fishing.Summary("jaguero isle").catches, 1)
	eq(ns.Fishing.Summary("Elwynn Forest").catches, 0)
end)

it("/craftwise fishing [zone] prints zones, subzones, items with labelled values", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. FISH, qty = 2 } })
	cast(stub, { { link = "item:" .. BOOT } })
	SlashCmdList.CRAFTWISE("fishing")
	local text = printed(stub)
	has(text, "Fishing, last 90 days: 2 catches.")
	local m = ns.FormatMoney
	has(text, "Stranglethorn Vale: 2 catches, " .. m(6) .. " per catch")
	has(text, "  Nek'mani Wellspring: 2 catches, " .. m(6) .. " per catch (total " .. m(12) .. " + 1 without price)")
	has(text, "Test Fish x2 - " .. m(6) .. " each (vendor)")
	has(text, "Test Boot x1 - no price data")
	stub.printed = {}
	SlashCmdList.CRAFTWISE("fishing Tanaris")
	has(printed(stub), "No catches in tanaris in the last 90 days.")
	stub.printed = {}
	stub.zone, stub.subzone = "Tanaris", ""
	cast(stub, { { link = "item:" .. BOOT } })
	SlashCmdList.CRAFTWISE("fishing tanaris")
	text = printed(stub)
	has(text, "Tanaris: 1 catches, no price data per catch")
	has(text, "(no subzone)")
	assert(not text:find("Stranglethorn", 1, true), "only the asked zone")
end)

it("keeps 90 days, per character, account-wide", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. FISH } })
	stub.clock = NOW + 91 * DAY
	cast(stub, { { link = "item:" .. OIL } })
	ns.db.fishing["Forever-EU-Alt"] = { catches = { { t = NOW, items = { [FISH] = 1 } } }, opened = { { t = NOW, item = CRATE, items = {} } } }
	stub.Fire("PLAYER_LOGIN")
	eq(#log(ns).catches, 1); eq(log(ns).catches[1].items[OIL], 1)
	eq(#ns.db.fishing["Forever-EU-Alt"].catches, 0); eq(#ns.db.fishing["Forever-EU-Alt"].opened, 0)
	eq(ns.Fishing.Summary().catches, 1)
end)

it("the character snapshot has the per-zone fishing summary", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. FISH, qty = 2 } })
	local snap = ns.Snapshot.Build()
	local f = snap.fishing
	assert(f, "fishing section")
	eq(f.days, 90); eq(f.catches, 1)
	local z = f.zones[1]
	eq(z.zone, "Stranglethorn Vale"); eq(z.catches, 1); eq(z.valuePerCatch, 12)
	local sub = z.subzones[1]
	eq(sub.subzone, "Nek'mani Wellspring"); eq(sub.maps[1], 1434)
	eq(sub.items[1].itemID, FISH); eq(sub.items[1].count, 2); eq(sub.items[1].unitValue, 6); eq(sub.items[1].valueSource, "vendor")
	eq(sub.items[1].name, "Test Fish")
end)

it("Fishing.lua is in the TOC after Loot.lua", function()
	local f = assert(io.open("CraftWise/CraftWise.toc"))
	local toc = f:read("*a")
	f:close()
	assert(toc:find("Loot.lua\nFishing.lua\n", 1, true), "Fishing.lua right after Loot.lua")
end)

it("#78: the subzone is stored on every catch; no subzone is stored as \"\"", function()
	local ns, stub = setup()
	cast(stub, { { link = "item:" .. FISH } })
	stub.zone, stub.subzone = "Tanaris", ""
	cast(stub, { { link = "item:" .. FISH } })
	local catches = log(ns).catches
	eq(catches[1].sub, "Nek'mani Wellspring")
	eq(catches[2].sub, "", "empty subzone kept, not dropped")
	-- Old catches without the field and new ones with "" are one "(no subzone)" row.
	catches[3] = { t = NOW, zone = "Tanaris", map = 1446, items = { [FISH] = 1 } }
	local tanaris
	for _, z in ipairs(ns.Fishing.Summary().zones) do if z.zone == "Tanaris" then tanaris = z end end
	eq(#tanaris.subzones, 1); eq(tanaris.subzones[1].sub, ""); eq(tanaris.subzones[1].catches, 2)
	stub.printed = {}
	ns.Fishing.Slash("tanaris")
	has(printed(stub), "(no subzone)")
	eq(ns.Fishing.SnapshotSummary().zones[1].subzones[1].subzone ~= nil, true)
end)
