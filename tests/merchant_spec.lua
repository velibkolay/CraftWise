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

-- #107: a Favor vendor's names always belong to their own item IDs, in the record and in the snapshot's
-- favor list, when the list changes length or order between visits, is filtered, or names load late.
it("#107: names stay with their item IDs across reordered, shorter, filtered and late-loading lists", function()
	local ns, stub = setup()
	local NAMES = { [252805] = "Pattern: Brawler's Leather Tunic", [252778] = "Pattern: Trapper's Leather Gloves",
		[252777] = "Pattern: Brawler's Leather Gloves", [252806] = "Pattern: Trapper's Leather Tunic" }
	local function row(id, named)
		return { itemID = id, name = named ~= false and NAMES[id] or nil, extended = true,
			costs = { { 30, "|cffffffff|Hcurrency:3402:0|h[Merchant's Favor]|h|r", "Merchant's Favor" } } }
	end
	local function check(where)
		local m = ns.db.merchants[248201]
		for id, item in pairs(m.items) do
			eq(item.name, NAMES[id], where .. ": record " .. id)
		end
		local f = ns.Crates.SnapshotFavor()
		local v = f.vendors[1]
		eq(v.npc, 248201, where)
		for _, it in ipairs(v.items) do
			eq(it.name, NAMES[it.id], where .. ": snapshot " .. it.id)
		end
		return v
	end
	-- First visit: names not loaded yet for two items, MERCHANT_UPDATE brings them in another order.
	stub.mf = { row(252777), row(252778, false), row(252805, false), row(252806) }
	open(stub, 248201, "Pawani")
	eq(ns.db.merchants[248201].items[252805].name, nil, "a name not loaded yet is missing, not borrowed")
	stub.mf = { row(252805), row(252777), row(252806), row(252778) }
	stub.Fire("MERCHANT_UPDATE")
	eq(#check("late names").items, 4)
	-- Re-visit with a shorter list in another order, one name not loaded: the old name stays with its ID.
	stub.mf = { row(252806), row(252805, false), row(252778) }
	open(stub, 248201, "Pawani")
	eq(#check("shorter").items, 3, "an unfiltered list drops what it no longer shows")
	-- A filtered view (one item at index 1) keeps the others with their own names.
	stub.filter = 1
	stub.mf = { row(252778) }
	open(stub, 248201, "Pawani")
	eq(#check("filtered").items, 3)
end)

-- Where to buy (#276) ---------------------------------------------------------------------------------------

local NOIR = 8000 -- a reagent only recorded vendors sell

local function Seed(ns, stub)
	stub.items[NOIR] = { name = "Bottle of Noir" }
	UnitFactionGroup = function() return "Horde" end
	stub.zone = "Durotar"
	ns.db.merchants = {
		[5611] = { name = "Barkeep Morag", zone = "Orgrimmar", sub = "Valley of Strength", x = 54.4, y = 67.9, group = "H", t = 100,
			items = { [NOIR] = { name = "Bottle of Noir", p = 50, s = 1, n = -1, t = 100 } } },
		[5612] = { name = "Cheap Keg", zone = "Durotar", x = 40.2, y = 10.6, t = 50,
			items = { [NOIR] = { name = "Bottle of Noir", p = 80, s = 1, n = 3, t = 50 } } },
		[5613] = { name = "Alliance Barman", zone = "Stormwind City", x = 10, y = 10, group = "A", t = 300,
			items = { [NOIR] = { name = "Bottle of Noir", p = 10, s = 1, n = -1, t = 300 } } },
		[5614] = { name = "Old Barman", zone = "Undercity", group = "H", t = 20,
			items = { [NOIR] = { name = "Bottle of Noir", p = 50, s = 1, n = -1, t = 20 } } },
	}
end

it("buy at: the vendor, zone, subzone, rounded coordinates and price; the player's faction only", function()
	local ns, stub = setup()
	Seed(ns, stub)
	stub.zone = "Orgrimmar"
	local w = ns.Merchant.BuyAt(NOIR)
	eq(w.lines[1].text, "Barkeep Morag, Orgrimmar · Valley of Strength 54, 68 · 50c")
	local all = ""
	for _, l in ipairs(w.lines) do all = all .. l.text end
	eq(all:find("Alliance", 1, true), nil, "the other faction's vendor is left out")
	-- An Alliance character sees the Alliance vendor and the neutral ones, not the Horde ones.
	UnitFactionGroup = function() return "Alliance" end
	w = ns.Merchant.BuyAt(NOIR)
	eq(w.lines[1].npcID, 5613); eq(w.lines[2].npcID, 5612); eq(w.more, 0)
end)

it("buy at: the current zone first, then the cheapest, then the most recently seen; two lines and '+N more'", function()
	local ns, stub = setup()
	Seed(ns, stub)
	stub.zone = "Durotar"
	local w = ns.Merchant.BuyAt(NOIR)
	eq(w.lines[1].npcID, 5612, "in this zone, though dearer")
	eq(w.lines[2].npcID, 5611, "then the cheaper of the rest (ties go to the one seen last)")
	eq(w.more, 1)
	eq(w.lines[1].text, "Cheap Keg, Durotar · 40, 11 · 80c · limited stock, 3 seen", "limited stock is said, with the count seen")
end)

it("buy at: no record says nothing, or the bundled-price wording; never a location", function()
	local ns, stub = setup()
	stub.items[NOIR] = { name = "Bottle of Noir" }
	eq(ns.Merchant.BuyAt(NOIR), nil)
	ns.VendorPrices = ns.VendorPrices or {}
	ns.VendorPrices[NOIR] = 50
	local w = ns.Merchant.BuyAt(NOIR)
	eq(w.bundled, true); eq(#w.lines, 0)
	-- Only another faction's vendor recorded: nothing to show, not the bundled wording either.
	UnitFactionGroup = function() return "Alliance" end
	ns.db.merchants = { [1] = { name = "Orc", zone = "Orgrimmar", group = "H", items = { [NOIR] = { p = 50, s = 1, n = -1, t = 1 } } } }
	eq(ns.Merchant.BuyAt(NOIR), nil)
end)

it("buy at in the tooltips: marked for a missing reagent, plain when held, bundled wording only when missing", function()
	local ns, stub = setup()
	Seed(ns, stub)
	stub.zone = "Orgrimmar"
	local lines = {}
	GameTooltip = GameTooltip or {}
	GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
	local MK = ns.Main.Make
	local held = function() return 0 end
	MK.AddBuyAt({ itemID = NOIR, quantity = 1 }, held)
	assert(lines[1]:find("Buy at: Barkeep Morag, Orgrimmar", 1, true), lines[1])
	assert(lines[1]:find("you hold 0 of 1", 1, true), "a missing reagent says so: " .. lines[1])
	eq(#lines, 3, "two vendors and the more line")
	lines = {}
	MK.AddBuyAt({ itemID = NOIR, quantity = 1 }, function() return 2 end)
	eq(lines[1]:find("you hold", 1, true), nil, "held: no mark")
	lines = {}
	MK.AddBuyAt({ itemID = THREAD or 99999, quantity = 1 }, held)
	eq(#lines, 0, "no vendor known, no line")
end)

-- Nearest vendor, the panel and waypoints (#276 scope change) ------------------------------------------------

local function Maps(stub)
	-- 1411 Durotar and 1454 Orgrimmar are on continent 12 (Kalimdor); 1429 Elwynn is on 13.
	local info = { [1411] = { mapType = 3, parentMapID = 12 }, [1454] = { mapType = 3, parentMapID = 12 },
		[1429] = { mapType = 3, parentMapID = 13 }, [12] = { mapType = 2, parentMapID = 946 }, [13] = { mapType = 2, parentMapID = 946 } }
	Enum.UIMapType = { Continent = 2 }
	local set = {}
	C_Map = { GetBestMapForUnit = function() return stub.map end,
		GetPlayerMapPosition = function() return stub.pos end,
		GetMapInfo = function(id) return info[id] end,
		CanSetUserWaypointOnMap = function(id) return id ~= 99 end,
		SetUserWaypoint = function(point) set[#set + 1] = point; return true end }
	UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
	local tracked
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) tracked = v end }
	return set, function() return tracked end
end

local function Seed2(ns, stub)
	stub.items[NOIR] = { name = "Bottle of Noir" }
	UnitFactionGroup = function() return "Horde" end
	stub.zone = "Orgrimmar"
	stub.map, stub.pos = 1454, { x = 0.50, y = 0.50 }
	ns.db.merchants = {
		[1] = { name = "Far Barman", zone = "Orgrimmar", map = 1454, x = 80, y = 80, group = "H", t = 1,
			items = { [NOIR] = { p = 50, s = 1, n = -1, t = 1 } } },
		[2] = { name = "Near Barman", zone = "Orgrimmar", map = 1454, x = 52, y = 49, group = "H", t = 1,
			items = { [NOIR] = { p = 90, s = 1, n = -1, t = 1 } } },
		[3] = { name = "Durotar Barman", zone = "Durotar", map = 1411, x = 40, y = 40, t = 1,
			items = { [NOIR] = { p = 10, s = 1, n = -1, t = 1 } } },
		[4] = { name = "Elwynn Barman", zone = "Elwynn Forest", map = 1429, x = 30, y = 30, t = 1,
			items = { [NOIR] = { p = 5, s = 1, n = -1, t = 1 } } },
		[5] = { name = "Unplaced Barman", zone = "Silithus", t = 1,
			items = { [NOIR] = { p = 1, s = 1, n = -1, t = 1 } } },
	}
end

it("nearest vendor: same map by distance, then the same zone, then the continent; never across continents", function()
	local ns, stub = setup()
	Maps(stub)
	Seed2(ns, stub)
	local all = ns.Merchant.BuyAtAll(NOIR)
	local order = {}
	for _, e in ipairs(all.entries) do order[#order + 1] = e.merchant.name .. ":" .. tostring(e.scope) end
	eq(table.concat(order, ","), "Near Barman:map,Far Barman:map,Durotar Barman:continent,Unplaced Barman:nil,Elwynn Barman:nil", "no scope: the cheapest first")
	eq(all.nearest.merchant.name, "Near Barman")
	-- Standing in a zone with no recorded vendor on a map the vendors share only by name: the zone ranks next.
	stub.map, stub.pos = 1411, { x = 0.1, y = 0.1 }
	stub.zone = "Durotar"
	all = ns.Merchant.BuyAtAll(NOIR)
	eq(all.entries[1].merchant.name, "Durotar Barman"); eq(all.entries[1].scope, "map")
	-- No position (instance or unknown map): the zone, then the continent, no distances.
	stub.map, stub.pos = nil, nil
	stub.zone = "Orgrimmar"
	all = ns.Merchant.BuyAtAll(NOIR)
	eq(all.entries[1].scope, "zone"); eq(all.entries[1].distance, nil)
	-- Nothing comparable: no nearest is claimed.
	stub.zone = "Stormwind City"
	stub.map = 1429
	ns.db.merchants = { [4] = ns.db.merchants[1] }
	ns.db.merchants[4].zone = "Orgrimmar"; ns.db.merchants[4].map = 1454
	all = ns.Merchant.BuyAtAll(NOIR)
	eq(all.entries[1].scope, nil); eq(all.nearest, nil)
end)

it("waypoint: UiMapPoint at the recorded map and position as fractions, super-tracked; refuses without a location", function()
	local ns, stub = setup()
	local set, tracked = Maps(stub)
	Seed2(ns, stub)
	local all = ns.Merchant.BuyAtAll(NOIR)
	local ok = ns.Merchant.Waypoint(all.nearest)
	eq(ok, true); eq(#set, 1); eq(set[1].uiMapID, 1454); eq(set[1].x, 0.52); eq(set[1].y, 0.49); eq(tracked(), true)
	local unplaced
	for _, e in ipairs(all.entries) do if e.merchant.name == "Unplaced Barman" then unplaced = e end end
	local bad, why = ns.Merchant.Waypoint(unplaced)
	eq(bad, false); eq(why, "No location was recorded for this vendor"); eq(#set, 1)
	-- A map that doesn't take waypoints.
	all.entries[1].merchant.map = 99
	bad, why = ns.Merchant.Waypoint(all.entries[1])
	eq(bad, false); eq(why, "A waypoint can't be set on that map")
	-- TomTom, when loaded, gets it too.
	local tt = {}
	TomTom = { AddWaypoint = function(_, map, x, y, opts) tt[#tt + 1] = { map, x, y, opts.title } end }
	ns.Merchant.Waypoint(all.nearest)
	TomTom = nil
	eq(#tt, 0, "the near vendor's map was changed to 99 above: refused before TomTom")
	all.entries[1].merchant.map = 1454
	TomTom = { AddWaypoint = function(_, map, x, y, opts) tt[#tt + 1] = { map, x, y, opts.title } end }
	ns.Merchant.Waypoint(all.entries[1])
	TomTom = nil
	eq(#tt, 1); eq(tt[1][1], 1454); eq(tt[1][4], "Near Barman")
end)

it("the panel: every vendor listed, the nearest marked, buttons set waypoints only when clicked", function()
	local ns, stub = setup()
	local set = Maps(stub)
	Seed2(ns, stub)
	local owner = CreateFrame("Frame", nil, UIParent)
	local P = ns.BuyAtPanel
	local panel = P.Toggle(NOIR, owner)
	assert(panel and panel:IsShown(), "opens")
	eq(#set, 0, "opening sets no waypoint")
	assert(panel.rows[1].text:GetText():find("Near Barman", 1, true), panel.rows[1].text:GetText())
	assert(panel.rows[1].text:GetText():find("nearest on this map", 1, true), "the nearest is marked")
	assert(panel.rows[2].text:GetText():find("Far Barman", 1, true))
	eq(panel.rows[4].text:GetText():find("Unplaced Barman", 1, true) ~= nil, true)
	eq(panel.rows[4].go.enabled, false, "no location: no waypoint button")
	panel.nearest.scripts.OnClick(panel.nearest)
	eq(#set, 1); eq(set[1].uiMapID, 1454); eq(set[1].x, 0.52)
	panel.rows[2].go.scripts.OnClick(panel.rows[2].go)
	eq(#set, 2); eq(set[2].x, 0.8)
	P.Toggle(NOIR, owner)
	eq(panel:IsShown(), false, "the same reagent again closes it")
	eq(P.Toggle(99999, owner), nil, "nothing known: no panel")
end)

-- Restock reminders and learned restock times (#289) ------------------------------------------------

local HARNESS = 15001

local function visit(stub, items, id, name)
	stub.mf = items
	open(stub, id or 2819, name or "Tunkk")
	stub.Fire("MERCHANT_CLOSED")
end

it("a vendor that never listed an item says not sold here with its complete visits, not out of stock", function()
	local ns, stub = setup()
	visit(stub, { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } })
	visit(stub, { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } })
	local m = ns.db.merchants[2819]
	eq(m.visits, 2); eq(m.fullVisits, 2)
	local st = ns.Merchant.ListingStatus(2819, HARNESS)
	eq(st.state, "never"); eq(st.visits, 2)
	eq(ns.Merchant.ListingText(st), "not sold here (seen 2 visits)")
	eq(ns.Merchant.ListingStatus(2819, NIGHTCRAWLERS).state, "listed")
	eq(ns.Merchant.ListingStatus(555, HARNESS).state, "unknown", "an unrecorded vendor says nothing")
	-- A filtered view is not a complete one: no claim from it.
	local ns2, stub2 = setup()
	stub2.filter = 1
	visit(stub2, { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } })
	eq(ns2.Merchant.ListingStatus(2819, HARNESS).state, "unknown")
	-- One window is one visit however many updates it sends.
	local ns3, stub3 = setup()
	stub3.mf = { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } }
	open(stub3, 7, "V"); stub3.Fire("MERCHANT_UPDATE"); stub3.Fire("MERCHANT_UPDATE")
	eq(ns3.db.merchants[7].visits, 1)
end)

it("an item that was listed and then is missing from a complete view is gone, and keeps its stock history", function()
	local ns, stub = setup()
	stub.now = 1000
	local time0 = time
	time = function() return stub.now end
	visit(stub, { { itemID = HARNESS, name = "Pattern: Raptor Hide Harness", price = 500, available = 0 } })
	eq(ns.Merchant.ListingStatus(2819, HARNESS).state, "soldout")
	eq(ns.Merchant.ListingText(ns.Merchant.ListingStatus(2819, HARNESS)), "out of stock")
	stub.now = 5000
	visit(stub, { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } })
	local st = ns.Merchant.ListingStatus(2819, HARNESS)
	eq(st.state, "gone"); eq(st.t, 5000)
	stub.now = 9000
	visit(stub, { { itemID = HARNESS, name = "Pattern: Raptor Hide Harness", price = 500, available = 1 } })
	local item = ns.db.merchants[2819].items[HARNESS]
	eq(ns.db.merchants[2819].gone[HARNESS], nil)
	local learned = ns.Merchant.Learned(item)
	eq(learned.count, 1)
	eq(learned.within, 9000 - 1000, "after the last 0 seen, before the first count above 0 seen")
	time = time0
end)

it("learned restock times come only from a 0 followed by a higher count, shown as an observation", function()
	local ns = setup()
	eq(ns.Merchant.Learned({ log = { { n = 3, first = 1, last = 2, realm = "R" }, { n = 5, first = 10, last = 11, realm = "R" } } }), nil, "a rise from 3 is not a restock from sold out")
	eq(ns.Merchant.Learned({ log = { { n = 0, first = 1, last = 100, realm = "R" }, { n = 2, first = 5000, last = 5000, realm = "S" } } }), nil, "another realm is another stock")
	eq(ns.Merchant.Learned({}), nil)
	local item = { log = { { n = 0, first = 0, last = 100, realm = "R" }, { n = 1, first = 4900, last = 4900, realm = "R" },
		{ n = 0, first = 9000, last = 9000, realm = "R" }, { n = 1, first = 9000 + 1200, last = 9000 + 1200, realm = "R" } } }
	local learned = ns.Merchant.Learned(item)
	eq(learned.count, 2); eq(learned.within, 4800); eq(learned.shortest, 1200)
	eq(ns.Merchant.LearnedText(learned), "restocked within 1h 20m, seen 2 times")
	eq(ns.Merchant.LearnedText(ns.Merchant.Learned({ log = { { n = 0, first = 0, last = 0, realm = "R" }, { n = 4, first = 4800, last = 4800, realm = "R" } } })),
		"restocked within 1h 20m, seen once")
end)

it("reminders: scheduling, choices with the learned time first, replacing, removal", function()
	local ns, stub = setup()
	stub.items[HARNESS] = { name = "Pattern: Raptor Hide Harness" }
	ns.db.merchants = { [2819] = { name = "Tunkk", zone = "Hammerfall", map = 1417, x = 73.1, y = 32.4, items = {
		[HARNESS] = { n = 0, log = { { n = 0, first = 0, last = 100, realm = "R" }, { n = 1, first = 4900, last = 4900, realm = "R" } } } } } }
	local R = ns.Restock
	local choices = R.Choices(2819, HARNESS)
	eq(choices[1].learned, true); eq(choices[1].seconds, 4800); eq(choices[1].label, "Learned: 1h 20m")
	eq(choices[2].seconds, 3600); eq(choices[5].seconds, 12 * 3600); eq(#choices, 5)
	eq(#R.Choices(2819, 99), 4, "no log: only the fixed hours")
	local rec = R.Add(2819, HARNESS, 7200, 1000)
	eq(rec.due, 8200); eq(rec.vendor, "Tunkk"); eq(rec.zone, "Hammerfall"); eq(rec.map, 1417); eq(rec.item, "Pattern: Raptor Hide Harness")
	eq(#R.List(), 1)
	eq(R.Add(2819, HARNESS, 3600, 2000).due, 5600); eq(#R.List(), 1, "the same vendor and item replaces it")
	eq(R.Add(404, HARNESS, 3600), nil, "an unrecorded vendor")
	eq(select(1, R.Add(2819, HARNESS, 5, 0)), nil, "too short")
	eq(R.Text(R.List()[1]), "Pattern: Raptor Hide Harness may be back at Tunkk (Hammerfall)")
	eq(R.Remove(R.List()[1].id), true); eq(#R.List(), 0)
end)

it("the due check fires once with a toast, a chat line and the sale sound; one that came due offline fires at login", function()
	local ns, stub = setup()
	stub.items[HARNESS] = { name = "Pattern: Raptor Hide Harness" }
	ns.db.merchants = { [2819] = { name = "Tunkk", zone = "Hammerfall", map = 1417, x = 73.1, y = 32.4, items = { [HARNESS] = { n = 0 } } } }
	local R = ns.Restock
	local shown, said, played = {}, {}, {}
	ns.LootToast = ns.LootToast or {}
	ns.LootToast.ShowCustom = function(entry) shown[#shown + 1] = entry; return entry end
	local print0 = ns.Print
	ns.Print = function(text) said[#said + 1] = text end
	SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 7 }
	PlaySound = function(id) played[#played + 1] = id end
	R.Add(2819, HARNESS, 3600, 1000)
	eq(R.Check(2000), 0, "not due yet")
	eq(#shown, 0)
	eq(R.Check(1000 + 3600), 1)
	eq(#shown, 1); eq(shown[1].text, "Pattern: Raptor Hide Harness may be back at Tunkk (Hammerfall)"); eq(shown[1].detail, "Waypoint")
	assert(said[1]:find("may be back at Tunkk", 1, true), said[1])
	eq(played[1], 7)
	eq(#R.List(), 0, "fired once")
	eq(R.Check(1000 + 7200), 0)
	-- Came due while offline: the next check (login) fires it, however late.
	R.Add(2819, HARNESS, 3600, 1000)
	eq(R.Check(1000 + 9 * 86400), 1)
	-- Sound off: still the line, no sound.
	ns.db.settings.saleSound = false
	R.Add(2819, HARNESS, 3600, 1000)
	played = {}
	R.Check(1000 + 3600)
	eq(#played, 0)
	-- Clicking the line sets the waypoint.
	local set = {}
	C_Map.CanSetUserWaypointOnMap = function() return true end
	C_Map.SetUserWaypoint = function(p) set[#set + 1] = p end
	UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
	shown[#shown].onClick()
	eq(#set, 1); eq(set[1].uiMapID, 1417)
	ns.Print = print0
end)

it("the vendor panel: Remind offers the times and sets one; active reminders list with a delete", function()
	local ns, stub = setup()
	Maps(stub)
	Seed2(ns, stub)
	local owner = CreateFrame("Frame", nil, UIParent)
	local P = ns.BuyAtPanel
	local panel = P.Toggle(NOIR, owner)
	local row = panel.rows[1]
	row.remind.scripts.OnClick(row.remind)
	assert(panel.choices[1] and panel.choices[1]:IsShown(), "the time choices appear")
	panel.choices[2].scripts.OnClick(panel.choices[2]) -- 2 h
	local list = ns.Restock.List()
	eq(#list, 1); eq(list[1].npcID, 2); eq(list[1].itemID, NOIR); eq(list[1].due - list[1].set, 7200)
	assert(panel.reminders[1] and panel.reminders[1]:IsShown(), "listed")
	assert(panel.reminders[1].text:GetText():find("Near Barman", 1, true), panel.reminders[1].text:GetText())
	local del = panel.reminders[1].del
	del.scripts.OnClick(del)
	eq(#ns.Restock.List(), 0); eq(panel.reminders[1]:IsShown(), false)
end)

it("the vendors a complete view dropped come last in the panel and are never the nearest", function()
	local ns, stub = setup()
	Maps(stub)
	Seed2(ns, stub)
	ns.db.merchants[2].items[NOIR] = nil
	ns.db.merchants[2].gone = { [NOIR] = { name = "Bottle of Noir", t = time() - 7200, n = 3 } }
	local all = ns.Merchant.BuyAtAll(NOIR)
	local last = all.entries[#all.entries]
	eq(last.merchant.name, "Near Barman"); eq(last.listed, false)
	assert(last.text:find("not listed now, last seen 2h ago", 1, true), last.text)
	assert(all.nearest.merchant.name ~= "Near Barman")
end)

it("/craftwise remind sets a reminder at the open vendor and lists and removes them", function()
	local ns, stub = setup()
	stub.items[HARNESS] = { name = "Pattern: Raptor Hide Harness" }
	visit(stub, { { itemID = NIGHTCRAWLERS, name = "Nightcrawlers", price = 90 } })
	local said = {}
	ns.Print = function(text) said[#said + 1] = text end
	MerchantFrame = { IsShown = function() return true end }
	ns.Restock.Slash("6 item:" .. HARNESS .. ":0")
	assert(said[1] and said[1]:find("not sold here (seen 1 visit)", 1, true), said[1])
	eq(#ns.Restock.List(), 1)
	eq(ns.Restock.List()[1].due - ns.Restock.List()[1].set, 6 * 3600)
	said = {}
	ns.Restock.Slash("")
	assert(said[1]:find("1. Pattern: Raptor Hide Harness at Tunkk", 1, true), said[1])
	ns.Restock.Slash("remove 1")
	eq(#ns.Restock.List(), 0)
	MerchantFrame = nil
end)
