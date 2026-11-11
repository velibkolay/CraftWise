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
