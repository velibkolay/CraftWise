-- Merchant recorder (issue #66): full inventories, re-visits, standing, limited stock, lookup.
local NIGHTCRAWLERS, POLE, RECIPE, SHIRT = 6530, 6365, 6369, 2575
local TB = 81 -- Thunder Bluff faction

local function npc(id) return ("Creature-0-3-1-1-%d-000012345A"):format(id) end

-- stub.mf = { { itemID, name, price, stack, available, usable, extended, costs } }
local function setup()
	local ns, stub = LoadAddon()
	stub.items[NIGHTCRAWLERS] = { name = "Nightcrawlers" }
	stub.items[POLE] = { name = "Strong Fishing Pole" }
	stub.items[RECIPE] = { name = "Recipe: Mithril Head Trout" }
	stub.itemClass[RECIPE] = 9
	stub.mf = {}
	stub.filter = 0
	LE_LOOT_FILTER_ALL = 0
	ITEM_SPELL_KNOWN = "Already known"
	stub.known = {}
	GetMerchantNumItems = function() return #stub.mf end
	GetMerchantItemID = function(i) return stub.mf[i].itemID end
	GetMerchantFilter = function() return stub.filter end
	GetMerchantItemCostInfo = function(i) return #(stub.mf[i].costs or {}) end
	GetMerchantItemCostItem = function(i, n)
		local c = stub.mf[i].costs[n]
		return "tex", c[1], c[2], c[3]
	end
	C_MerchantFrame = { GetItemInfo = function(i)
		local m = stub.mf[i]
		return { name = m.name, price = m.price or 0, stackCount = m.stack or 1, numAvailable = m.available or -1,
			isUsable = m.usable ~= false, hasExtendedCost = m.extended or false, currencyID = m.currency }
	end }
	C_TooltipInfo.GetMerchantItem = function(i)
		return { lines = { { leftText = stub.mf[i].name }, stub.known[stub.mf[i].itemID] and { leftText = "Already known" } or nil } }
	end
	-- NPC tooltip lines; reputation list (one collapsed-away faction only reachable by ID).
	stub.npcLines = {}
	C_TooltipInfo.GetUnit = function(unit)
		if unit ~= "npc" then return nil end
		local lines = {}
		for _, t in ipairs(stub.npcLines) do lines[#lines + 1] = { leftText = t } end
		return { lines = lines }
	end
	stub.reps = { { factionID = 0, name = "Horde", isHeader = true },
		{ factionID = TB, name = "Thunder Bluff", reaction = 6 }, { factionID = 76, name = "Orgrimmar", reaction = 4 } }
	C_Reputation = {
		GetNumFactions = function() return #stub.reps end,
		GetFactionDataByIndex = function(i) return stub.reps[i] end,
		GetFactionDataByID = function(id)
			for _, f in ipairs(stub.reps) do if f.factionID == id then return f end end
		end,
	}
	stub.reaction = nil
	UnitReaction = function(a, b) if a == "npc" and b == "player" then return stub.reaction end end
	stub.map, stub.pos = 1456, { x = 0.4721, y = 0.5809 }
	C_Map = { GetBestMapForUnit = function() return stub.map end,
		GetPlayerMapPosition = function() return stub.pos end }
	UnitFactionGroup = function(unit) if unit == "npc" then return stub.npcGroup end return "Horde" end
	stub.zone, stub.subzone = "Thunder Bluff", "Lower Rise"
	return ns, stub
end

local function open(stub, id, name)
	stub.guids.npc, stub.names.npc = npc(id), name
	stub.Fire("MERCHANT_SHOW")
end

it("records the whole inventory with NPC, place, price, stack, stock and usable", function()
	local ns, stub = setup()
	stub.npcGroup = "Horde"
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 },
		{ itemID = POLE, name = "Strong Fishing Pole", price = 900, available = 1 },
		{ itemID = SHIRT, name = "Red Linen Shirt", price = 50, stack = 5, usable = false } }
	open(stub, 3027, "Sewa Mistrunner")
	local m = ns.db.merchants[3027]
	eq(m.name, "Sewa Mistrunner"); eq(m.zone, "Thunder Bluff"); eq(m.sub, "Lower Rise"); eq(m.group, "H")
	eq(m.map, 1456); eq(m.x, 47.2); eq(m.y, 58.1); eq(m.full, true); eq(m.filter, 0)
	eq(type(m.t), "number"); eq(m.first, m.t)
	eq(m.items[NIGHTCRAWLERS].p, 90); eq(m.items[NIGHTCRAWLERS].n, -1); eq(m.items[NIGHTCRAWLERS].log, nil)
	eq(m.items[POLE].n, 1); eq(#m.items[POLE].log, 1)
	eq(m.items[SHIRT].s, 5); eq(m.items[SHIRT].unusable, true); eq(m.items[NIGHTCRAWLERS].unusable, nil)
	eq(m.items[POLE].name, "Strong Fishing Pole")
end)

it("records currency and item costs with their IDs, and skips currencies for sale", function()
	local ns, stub = setup()
	stub.mf = { { itemID = RECIPE, name = "Recipe", price = 0, extended = true,
		costs = { { 10, "|cff|Hcurrency:1234:0|h[Merchant's Favor]|h|r", "Merchant's Favor" }, { 2, "|cff|Hitem:4306:0|h[Silk Cloth]|h|r" } } },
		{ itemID = 999, name = "Some Currency", price = 100, currency = 77 } }
	open(stub, 1, "Vendor")
	local item = ns.db.merchants[1].items[RECIPE]
	eq(item.p, 0); eq(#item.c, 2)
	eq(item.c[1].name, "Merchant's Favor"); eq(item.c[1].amount, 10); eq(item.c[1].currency, 1234)
	eq(item.c[2].name, "Silk Cloth"); eq(item.c[2].item, 4306)
	eq(ns.db.merchants[1].items[999], nil)
	eq(ns.Merchant.PriceText(item, true), "10 Merchant's Favor + 2 Silk Cloth")
end)

it("marks recipes the tooltip calls already known", function()
	local ns, stub = setup()
	stub.known[RECIPE] = true
	stub.mf = { { itemID = RECIPE, name = "Recipe: Mithril Head Trout", price = 2200 } }
	open(stub, 2, "Vendor")
	eq(ns.db.merchants[2].items[RECIPE].known, true)
	stub.known[RECIPE] = nil
	stub.Fire("MERCHANT_UPDATE")
	eq(ns.db.merchants[2].items[RECIPE].known, nil)
end)

it("stores the player's standing with the faction the NPC's tooltip names", function()
	local ns, stub = setup()
	stub.npcLines = { "Sewa Mistrunner", "Fishing Supplies", "Level 30", "Thunder Bluff" }
	stub.reaction = 6
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	local m = ns.db.merchants[3027]
	eq(m.faction.id, TB); eq(m.faction.name, "Thunder Bluff"); eq(m.standing, 6); eq(m.reaction, 6)
	eq(m.items[NIGHTCRAWLERS].ps[6], 90)
	eq(ns.Merchant.StandingText(m), "Honored with Thunder Bluff")
end)

it("without a faction line stores only the reaction the client reports and says so", function()
	local ns, stub = setup()
	stub.npcLines = { "Vendor", "Level 30" }
	stub.reaction = 5
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 5, "Vendor")
	local m = ns.db.merchants[5]
	eq(m.faction, nil); eq(m.standing, nil); eq(m.reaction, 5); eq(m.items[NIGHTCRAWLERS].ps, nil)
	eq(ns.Merchant.StandingText(m), "reaction Friendly, faction not reported")
end)

it("finds a faction under a collapsed header by the ID seen on an earlier visit", function()
	local ns, stub = setup()
	stub.npcLines = { "Sewa Mistrunner", "Thunder Bluff" }
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	local tb = stub.reps[2]
	stub.reps = { { factionID = 0, name = "Horde", isHeader = true, isCollapsed = true } }
	local byID = C_Reputation.GetFactionDataByID
	C_Reputation.GetFactionDataByID = function(id) if id == TB then return tb end return byID(id) end
	open(stub, 3027, "Sewa Mistrunner")
	eq(ns.db.merchants[3027].standing, 6)
end)

it("a re-visit overwrites the NPC's record; an unfiltered view drops items no longer sold", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 }, { itemID = POLE, name = "Pole", price = 900 } }
	open(stub, 7, "Vendor")
	local first = ns.db.merchants[7].first
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 95 } }
	open(stub, 7, "Vendor")
	local m = ns.db.merchants[7]
	eq(m.items[NIGHTCRAWLERS].p, 95); eq(m.items[POLE], nil); eq(m.first, first)
	local n = 0
	for _ in pairs(ns.db.merchants) do n = n + 1 end
	eq(n, 1)
end)

it("a filtered view keeps items it does not show", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 }, { itemID = POLE, name = "Pole", price = 900 } }
	open(stub, 7, "Vendor")
	stub.filter = 2
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 7, "Vendor")
	local m = ns.db.merchants[7]
	eq(m.full, nil); eq(m.filter, 2); eq(m.items[POLE].p, 900)
end)

it("a list the client has not fully loaded drops nothing", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 }, { itemID = POLE, name = "Pole", price = 900 } }
	open(stub, 7, "Vendor")
	stub.mf[1].itemID = nil -- not loaded yet
	stub.Fire("MERCHANT_UPDATE")
	eq(ns.db.merchants[7].items[NIGHTCRAWLERS].p, 100)
end)

it("an empty list (not loaded yet) keeps the recording", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 7, "Vendor")
	stub.mf = {}
	eq(ns.Merchant.Record(), 0)
	eq(ns.db.merchants[7].items[NIGHTCRAWLERS].p, 100)
end)

it("ignores merchants without a creature GUID", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 7, "Vendor")
	stub.guids.npc = "Player-1-SELF"
	stub.Fire("MERCHANT_SHOW")
	eq(ns.Merchant.Count(), 1)
end)

it("limited stock keeps each count with first and last seen, and shows a measured restock", function()
	local ns, stub = setup()
	local now = 1000000
	time = function() return now end
	stub.mf = { { itemID = POLE, name = "Strong Fishing Pole", price = 900, available = 1 } }
	open(stub, 3027, "Sewa")
	now = now + 60
	stub.Fire("MERCHANT_UPDATE") -- same count: last seen moves
	local item = ns.db.merchants[3027].items[POLE]
	eq(#item.log, 1); eq(item.log[1].first, 1000000); eq(item.log[1].last, 1000060)
	stub.mf[1].available = 0 -- bought
	now = now + 10
	stub.Fire("MERCHANT_UPDATE")
	now = now + 3600
	open(stub, 3027, "Sewa")
	eq(#item.log, 2); eq(item.log[2].n, 0); eq(item.log[2].last, 1003670)
	stub.mf[1].available = 1
	now = now + 3600
	open(stub, 3027, "Sewa")
	eq(item.n, 1); eq(#item.log, 3)
	local r = ns.Merchant.Restocks(item)
	eq(#r, 1); eq(r[1].from, 0); eq(r[1].to, 1); eq(r[1].after, 1003670); eq(r[1].before, 1007270)
	eq(item.restock, nil) -- no interval is assumed or stored
	local text = table.concat(ns.Merchant.SellerLines(POLE, now), "\n")
	assert(text:find("count rose 0 %-> 1 between .* %(within 1h 0m, may be another layer%)"), text)
end)

it("stock seen on another realm is not taken as a restock", function()
	local ns, stub = setup()
	stub.mf = { { itemID = POLE, name = "Pole", price = 900, available = 0 } }
	open(stub, 3027, "Sewa")
	stub.realm = "Other"
	stub.mf[1].available = 1
	open(stub, 3027, "Sewa")
	local item = ns.db.merchants[3027].items[POLE]
	eq(#item.log, 2); eq(#ns.Merchant.Restocks(item), 0)
end)

it("the stock log is capped", function()
	local ns, stub = setup()
	stub.mf = { { itemID = POLE, name = "Pole", price = 900, available = 0 } }
	for i = 1, ns.Merchant.LOG_MAX + 5 do
		stub.mf[1].available = i % 2
		open(stub, 3027, "Sewa")
	end
	eq(#ns.db.merchants[3027].items[POLE].log, ns.Merchant.LOG_MAX)
end)

it("who sells X: cheapest first, by item ID, link or name", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	stub.npcLines = { "x", "Orgrimmar" }
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 }, { itemID = POLE, name = "Strong Fishing Pole", price = 900, available = 1 } }
	stub.zone, stub.subzone = "Orgrimmar", "Valley of Honor"
	open(stub, 3333, "Lumak")
	local s = ns.Merchant.Sellers(NIGHTCRAWLERS)
	eq(#s, 2); eq(s[1].npcID, 3027); eq(s[2].npcID, 3333)
	eq(#ns.Merchant.Sellers(SHIRT), 0)
	local found = ns.Merchant.FindItems("fishing")
	eq(#found, 1); eq(found[1], POLE)
	local printed = {}
	local realPrint = print
	print = function(t) printed[#printed + 1] = tostring(t) end
	ns.Merchant.Slash("strong fishing pole")
	ns.Merchant.Slash("|cff|hitem:" .. NIGHTCRAWLERS .. ":0|h[nightcrawlers]|h|r")
	ns.Merchant.Slash(tostring(SHIRT))
	ns.Merchant.Slash("no such thing")
	print = realPrint
	local text = table.concat(printed, "\n")
	assert(text:find("Lumak %- Orgrimmar, Valley of Honor %(47.2, 58.1%)"), text)
	assert(text:find("1 in stock"), text)
	assert(text:find("Honored with Thunder Bluff"), text)
	assert(text:find("Neutral with Orgrimmar"), text)
	assert(text:find("no merchant you opened sells it"), text)
	assert(text:find("no merchant you opened sells an item named \"no such thing\""), text)
	-- Sewa (90c) is listed before Lumak (1s).
	assert(text:find("Sewa Mistrunner"), text)
	assert(text:find("Sewa Mistrunner") < text:find("Lumak %- Orgrimmar, Valley of Honor %(47.2, 58.1%) · 1"), text)
end)

it("/craftwise where routes to the lookup", function()
	local ns, stub = setup()
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	local printed = {}
	local realPrint = print
	print = function(t) printed[#printed + 1] = tostring(t) end
	SlashCmdList.CRAFTWISE("where Nightcrawlers")
	print = realPrint
	assert(table.concat(printed, "\n"):find("Sewa Mistrunner"), table.concat(printed, "\n"))
end)

it("base price only from a Neutral observation; discounts are measured, not assumed", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	eq(ns.Merchant.BasePrice(NIGHTCRAWLERS), nil) -- only seen at Honored: no base price
	eq(next(ns.Merchant.Discounts()), nil)
	stub.npcLines = { "x" } -- no faction: does not count as Neutral
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 4000, "Somebody")
	eq(ns.Merchant.BasePrice(NIGHTCRAWLERS), nil)
	stub.npcLines = { "x", "Orgrimmar" }
	open(stub, 3333, "Lumak")
	eq(ns.Merchant.BasePrice(NIGHTCRAWLERS), 100)
	local d = ns.Merchant.Discounts()
	eq(d[6].n, 1); eq(d[6].items, 1); eq(d[6].min, 0.9); eq(d[6].max, 0.9); eq(d[5], nil)
end)

it("price per standing is kept when the standing changes", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	stub.reps[2].reaction = 4
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 3027, "Sewa")
	stub.reps[2].reaction = 6
	stub.mf[1].price = 90
	open(stub, 3027, "Sewa")
	local item = ns.db.merchants[3027].items[NIGHTCRAWLERS]
	eq(item.ps[4], 100); eq(item.ps[6], 90); eq(item.p, 90)
	eq(ns.Merchant.BasePrice(NIGHTCRAWLERS), 100)
	eq(ns.Merchant.Discounts()[6].min, 0.9)
end)

it("item tooltip shows Sold by with the cheapest merchants, and the line can be turned off", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	stub.mf = { { itemID = POLE, name = "Strong Fishing Pole", price = 900, available = 1 } }
	open(stub, 3027, "Sewa Mistrunner")
	stub.npcLines = {}
	stub.mf = { { itemID = POLE, name = "Strong Fishing Pole", price = 1000 } }
	open(stub, 1, "B"); open(stub, 2, "C")
	local tip = CreateFrame("GameTooltip")
	tip.lines = {}
	function tip:AddLine(t) table.insert(self.lines, t) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function tip:Show() end
	ns.db.tooltip.lines.market = false
	assert(ns.AddTooltipLines(tip, POLE))
	local text = table.concat(tip.lines, "\n")
	assert(text:find("Sold by | Sewa Mistrunner · .* · Honored · 1 in stock · just now"), text)
	assert(text:find("%+1 more: /craftwise where"), text)
	tip.lines = {}
	ns.db.tooltip.lines.soldBy = false
	ns.db.tooltip.lines.advice = false
	ns.AddTooltipLines(tip, POLE)
	assert(not table.concat(tip.lines, "\n"):find("Sold by"), table.concat(tip.lines, "\n"))
end)

-- #75: which character buys cheaper. Forever characters have a surname (#77): UnitName("player")
-- returns name, surname; the key is "<realm>-<name> <surname>".
local function asChar(stub, full, tbReaction)
	local name, surname = full:match("^(%S+) (%S+)$")
	stub.names.player, stub.surname = name or full, surname
	stub.reps[2].reaction = tbReaction
	UnitName = function(unit)
		if unit == "player" then return stub.names.player, stub.surname end
		return stub.names[unit]
	end
end

-- Money icons as letters: "90c", "1s 2c".
local function plain(text)
	return (text:gsub("|T[^|]*Gold[^|]*|t", "g"):gsub("|T[^|]*Silver[^|]*|t", "s"):gsub("|T[^|]*Copper[^|]*|t", "c"))
end

local function whereText(ns, query)
	local printed = {}
	local realPrint = print
	print = function(t) printed[#printed + 1] = tostring(t) end
	ns.Merchant.Slash(query)
	print = realPrint
	return plain(table.concat(printed, "\n"))
end

local TANNER, WRIGHT = "PvP-Velikopter Tanner", "PvP-Velikopter Wright"

it("the character key has the surname, from ns.CharKey (Core.lua)", function()
	local ns, stub = setup()
	asChar(stub, "Velikopter Tanner", 6)
	eq(ns.Merchant.CharKey(), TANNER)
	Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "_" } }
	eq(ns.Merchant.CharKey(), "PvP-Velikopter_Tanner")
	Constants = nil
	asChar(stub, "Solo", 6)
	eq(ns.Merchant.CharKey(), "PvP-Solo")
	local coreKey = ns.CharKey
	ns.CharKey = function() return "Core-Key" end
	eq(ns.Merchant.CharKey(), "Core-Key")
	ns.CharKey = coreKey
	eq(ns.Merchant.CharDisplay(TANNER), "Velikopter Tanner")
	eq(ns.Merchant.CharDisplay("Forever-EU-Velikopter Tanner"), "Velikopter Tanner-Forever-EU")
end)

it("stores the character with each price, the standing price and the last visit", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	local m = ns.db.merchants[3027]
	local item = m.items[NIGHTCRAWLERS]
	eq(m.char, TANNER)
	eq(item.pc[TANNER].p, 90); eq(item.pc[TANNER].st, 6); eq(type(item.pc[TANNER].t), "number")
	eq(item.pk[6], TANNER)
	asChar(stub, "Velikopter Wright", 4)
	stub.mf[1].price = 100
	open(stub, 3027, "Sewa Mistrunner")
	eq(m.char, WRIGHT)
	eq(item.pc[TANNER].p, 90); eq(item.pc[WRIGHT].p, 100); eq(item.pc[WRIGHT].st, 4)
	eq(item.pk[6], TANNER); eq(item.pk[4], WRIGHT)
	eq(item.ps[6], 90); eq(item.ps[4], 100)
end)

it("a price without a matched faction is stored per character without a standing", function()
	local ns, stub = setup()
	stub.npcLines = { "x" }
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 },
		{ itemID = RECIPE, name = "Recipe", price = 0, extended = true, costs = { { 10, nil, "Merchant's Favor" } } } }
	open(stub, 5, "Vendor")
	local m = ns.db.merchants[5]
	eq(m.items[NIGHTCRAWLERS].pc[TANNER].p, 100); eq(m.items[NIGHTCRAWLERS].pc[TANNER].st, nil)
	eq(m.items[NIGHTCRAWLERS].pk, nil)
	eq(m.items[RECIPE].pc, nil) -- no copper price: nothing per character
	local text = whereText(ns, tostring(NIGHTCRAWLERS))
	assert(text:find("Vendor %- .* · 1s with Velikopter Tanner · standing not reported"), text)
end)

it("two characters at different standings: the lookup lists both, cheaper first", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	asChar(stub, "Velikopter Wright", 4)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 3027, "Sewa Mistrunner")
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf[1].price = 90
	open(stub, 3027, "Sewa Mistrunner")
	local chars = ns.Merchant.Sellers(NIGHTCRAWLERS)[1].chars
	eq(#chars, 2); eq(chars[1].key, TANNER); eq(chars[2].key, WRIGHT); eq(chars[1].seen, nil)
	local text = whereText(ns, "nightcrawlers")
	assert(text:find("Sewa Mistrunner %- Thunder Bluff, Lower Rise %(47.2, 58.1%) · 90c with Velikopter Tanner %(Honored%), 1s with Velikopter Wright %(Neutral%) · faction Thunder Bluff"), text)
	assert(text:find("base price seen at Neutral: 1s"), text)
	local lines = ns.Merchant.TooltipLines(NIGHTCRAWLERS)
	eq(lines[1][1], "Sold by")
	assert(plain(lines[1][2]):find("^Sewa Mistrunner · 90c Velikopter Tanner %(Honored%), 1s Velikopter Wright %(Neutral%) · "), lines[1][2])
	-- Logged in on another realm (now "Other-Velikopter Tanner", Honored, never opened Sewa there): the
	-- realm is shown for the others, and the live standing gives the Honored price seen here.
	stub.realm = "Other"
	local off = plain(ns.Merchant.TooltipLines(NIGHTCRAWLERS)[1][2])
	assert(off:find("90c Velikopter Tanner%-PvP %(Honored%), 90c Velikopter Tanner %(seen at Honored%), 1s Velikopter Wright%-PvP %(Neutral%)"), off)
end)

it("the merchant where one character buys cheaper is listed first", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Orgrimmar" }
	asChar(stub, "Velikopter Wright", 4)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 95 } }
	open(stub, 3333, "Lumak")
	stub.npcLines = { "x", "Thunder Bluff" }
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 3027, "Sewa Mistrunner")
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf[1].price = 90
	open(stub, 3027, "Sewa Mistrunner") -- visit at Honored: 90c
	asChar(stub, "Velikopter Wright", 4)
	stub.mf[1].price = 100
	open(stub, 3027, "Sewa Mistrunner") -- last visit at Neutral again: item.p = 100
	local s = ns.Merchant.Sellers(NIGHTCRAWLERS)
	eq(s[1].npcID, 3027); eq(s[1].unit, 90); eq(s[2].npcID, 3333)
end)

it("a character that never opened the merchant shows the price seen at its snapshot standing", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	-- Alts known only from their #63 snapshots.
	ns.db.snapshots = {
		["PvP-Alt Honored"] = { t = 1, reputations = { list = { { id = TB, name = "Thunder Bluff", reaction = 6 } } } },
		["PvP-Alt Friendly"] = { t = 1, reputations = { list = { { id = TB, name = "Thunder Bluff", reaction = 5 } } } }, -- no Friendly price seen
		["PvP-Alt Collapsed"] = { t = 1, reputations = { list = {}, collapsedHeaders = { "Horde" } } }, -- faction not listed
		["PvP-Velikopter"] = { t = 1, legacy = true, reputations = { list = { { id = TB, reaction = 6 } } } }, -- pre-#77, owner unknown
		[TANNER] = { t = 1, reputations = { list = { { id = TB, reaction = 4 } } } }, -- observed beats snapshot
	}
	local chars = ns.Merchant.Sellers(NIGHTCRAWLERS)[1].chars
	eq(#chars, 2)
	eq(chars[1].key, TANNER); eq(chars[1].seen, nil) -- same price: observed by that character first
	eq(chars[2].key, "PvP-Alt Honored"); eq(chars[2].seen, true); eq(chars[2].p, 90); eq(chars[2].st, 6)
	local text = whereText(ns, "nightcrawlers")
	assert(text:find("90c with Velikopter Tanner %(Honored%), 90c with Alt Honored %(seen at Honored%)"), text)
	assert(not text:find("Alt Friendly") and not text:find("Alt Collapsed") and not text:find("with Velikopter %("), text)
	-- Once a Friendly price is observed (any character), the Friendly alt shows it.
	asChar(stub, "Someone Else", 5)
	stub.mf[1].price = 95
	open(stub, 3027, "Sewa Mistrunner")
	text = whereText(ns, "nightcrawlers")
	assert(text:find("95c with Alt Friendly %(seen at Friendly%)"), text)
end)

it("the character logged in uses its live standing, not an older snapshot", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	asChar(stub, "Velikopter Tanner", 6)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 3027, "Sewa Mistrunner")
	ns.db.snapshots = { ["PvP-New Alt"] = { t = 1, reputations = { list = { { id = TB, reaction = 4 } } } } }
	asChar(stub, "New Alt", 6) -- logged in, reached Honored since its snapshot, never opened Sewa
	local chars = ns.Merchant.Sellers(NIGHTCRAWLERS)[1].chars
	eq(#chars, 2); eq(chars[2].key, "PvP-New Alt"); eq(chars[2].st, 6); eq(chars[2].seen, true)
end)

it("old records without a character key still show as before", function()
	local ns, stub = setup()
	ns.db.merchants = { [3027] = { name = "Sewa Mistrunner", zone = "Thunder Bluff", t = time(), realm = "PvP",
		faction = { id = TB, name = "Thunder Bluff" }, standing = 6,
		items = { [NIGHTCRAWLERS] = { name = "Nightcrawlers", p = 90, s = 1, n = -1, ps = { [6] = 90 }, t = time() } } } }
	local s = ns.Merchant.Sellers(NIGHTCRAWLERS)
	eq(#s, 1); eq(#s[1].chars, 0); eq(s[1].unit, 90)
	local text = whereText(ns, "nightcrawlers")
	assert(text:find("Sewa Mistrunner %- Thunder Bluff · 90c · Honored with Thunder Bluff"), text)
	assert(plain(ns.Merchant.TooltipLines(NIGHTCRAWLERS)[1][2]):find("^Sewa Mistrunner · 90c · Honored · "), "old tooltip")
	-- A snapshot standing still finds the price seen at it.
	ns.db.snapshots = { ["PvP-Alt Honored"] = { t = 1, reputations = { list = { { id = TB, reaction = 6 } } } } }
	text = whereText(ns, "nightcrawlers")
	assert(text:find("90c with Alt Honored %(seen at Honored%) · faction Thunder Bluff"), text)
	-- A new visit adds the character next to the old data.
	stub.npcLines = { "x", "Thunder Bluff" }
	asChar(stub, "Velikopter Wright", 4)
	stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 } }
	open(stub, 3027, "Sewa Mistrunner")
	text = whereText(ns, "nightcrawlers")
	assert(text:find("90c with Alt Honored %(seen at Honored%), 1s with Velikopter Wright %(Neutral%)"), text)
end)

it("the tooltip lists at most three characters per merchant", function()
	local ns, stub = setup()
	stub.npcLines = { "x", "Thunder Bluff" }
	for i, name in ipairs({ "A", "B", "C", "D", "E" }) do
		asChar(stub, "Alt " .. name, 4)
		stub.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 100 + i } }
		open(stub, 3027, "Sewa Mistrunner")
	end
	local text = plain(ns.Merchant.TooltipLines(NIGHTCRAWLERS)[1][2])
	assert(text:find("1s 1c Alt A %(Neutral%), 1s 2c Alt B %(Neutral%), 1s 3c Alt C %(Neutral%), %+2"), text)
end)

it("stores the reputation requirement a Favor item's tooltip states, as the client formats it (#91)", function()
	local ns, stub = setup()
	ITEM_REQ_REPUTATION = "Requires %s - %s"
	FACTION_STANDING_LABEL6 = "Honored"
	local lines = {
		[1] = { "Pattern: Defender's Leather Hood", "|cffff2020Requires Durotar Supply and Logistics - Honored|r" },
		[2] = { "Pattern: Totemic Leather Hood" },
		[3] = { "Nightcrawlers", "Requires Thunder Bluff - Honored" },
	}
	C_TooltipInfo.GetMerchantItem = function(i)
		local out = {}
		for _, t in ipairs(lines[i]) do out[#out + 1] = { leftText = t } end
		return { lines = out }
	end
	stub.mf = { { itemID = 252800, name = "Pattern: Defender's Leather Hood", price = 0, extended = true,
		costs = { { 30, "|cff|Hcurrency:3402:0|h[Merchant's Favor]|h|r", "Merchant's Favor" } } },
		{ itemID = 252801, name = "Pattern: Totemic Leather Hood", price = 0, extended = true,
		costs = { { 30, "|cff|Hcurrency:3402:0|h[Merchant's Favor]|h|r", "Merchant's Favor" } } },
		{ itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub, 248201, "Pawani")
	local items = ns.db.merchants[248201].items
	eq(items[252800].req.faction, "Durotar Supply and Logistics"); eq(items[252800].req.standing, 6)
	eq(items[252800].req.text, "Requires Durotar Supply and Logistics - Honored")
	eq(items[252801].req, nil)
	-- Gold-only items that aren't recipes keep no tooltip read (as before).
	eq(items[NIGHTCRAWLERS].req, nil)
	-- The requirement is gone from the tooltip on the next visit: gone from the record too.
	lines[1] = { "Pattern: Defender's Leather Hood" }
	stub.Fire("MERCHANT_UPDATE")
	eq(items[252800].req, nil)
	ITEM_REQ_REPUTATION, FACTION_STANDING_LABEL6 = nil, nil
end)
