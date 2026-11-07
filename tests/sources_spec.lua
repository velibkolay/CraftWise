-- Source recorder (issue #37): merchants, loot, quest rewards, de-duplication, merge order.
local RECIPE_ITEM, PLAIN_ITEM = 5789, 2589

local function setup()
	local ns, stub = LoadAddon()
	stub.itemClass[RECIPE_ITEM] = 9
	stub.items[RECIPE_ITEM] = { name = "Pattern: Test Cloak" }
	stub.items[PLAIN_ITEM] = { name = "Linen Cloth" }
	ns.SourceData = { [3762] = { skill = 95, item = RECIPE_ITEM } }
	stub.zone, stub.subzone = "Orgrimmar", "Valley of Strength"
	local npcFaction = {}
	UnitFactionGroup = function(unit) if unit == "player" then return "Horde" end return npcFaction[unit] end
	return ns, stub, npcFaction
end

local function npc(id) return ("Creature-0-3-1-1-%d-000012345A"):format(id) end

it("records a recipe item sold by a merchant, not other items", function()
	local ns, stub, f = setup()
	stub.guids.npc, stub.names.npc, f.npc = npc(3490), "Hagrus", "Horde"
	stub.merchant = { { itemID = PLAIN_ITEM, price = 5 }, { itemID = RECIPE_ITEM, price = 2000, available = 3 } }
	stub.Fire("MERCHANT_SHOW")
	local v = ns.db.sources[RECIPE_ITEM].vendors[3490]
	eq(v.name, "Hagrus"); eq(v.price, 2000); eq(v.limited, 3); eq(v.faction, "H")
	eq(v.zone, "Orgrimmar"); eq(v.sub, "Valley of Strength"); eq(type(v.t), "number")
	eq(ns.db.sources[PLAIN_ITEM], nil)
end)

it("records currency and item costs, and no faction when the client gives none", function()
	local ns, stub = setup()
	stub.guids.npc, stub.names.npc = npc(1), "Vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 0, extended = true,
		costs = { { 10, nil, "Merchant's Favor" }, { 2, "|cff|Hitem:1:0|h[Silk Cloth]|h|r", nil } } } }
	stub.Fire("MERCHANT_SHOW")
	local v = ns.db.sources[RECIPE_ITEM].vendors[1]
	eq(v.price, nil); eq(v.faction, nil); eq(#v.costs, 2)
	eq(v.costs[1].name, "Merchant's Favor"); eq(v.costs[1].amount, 10); eq(v.costs[2].name, "Silk Cloth")
end)

it("merchant records de-duplicate per NPC and update the price", function()
	local ns, stub = setup()
	stub.guids.npc, stub.names.npc = npc(7), "Vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 100 } }
	stub.Fire("MERCHANT_SHOW"); stub.Fire("MERCHANT_UPDATE")
	local n = 0
	for _ in pairs(ns.db.sources[RECIPE_ITEM].vendors) do n = n + 1 end
	eq(n, 1)
	stub.merchant[1].price = 150
	stub.Fire("MERCHANT_SHOW")
	eq(ns.db.sources[RECIPE_ITEM].vendors[7].price, 150)
	stub.guids.npc = npc(8)
	stub.Fire("MERCHANT_SHOW")
	eq(ns.db.sources[RECIPE_ITEM].vendors[8].price, 150)
end)

it("ignores merchants without a creature GUID", function()
	local ns, stub = setup()
	stub.guids.npc = "Player-1-SELF"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 100 } }
	stub.Fire("MERCHANT_SHOW")
	eq(next(ns.db.sources), nil)
end)

it("records looted recipes per source with a seen count and no chance", function()
	local ns, stub = setup()
	stub.guids.target, stub.names.target = npc(46), "Defias Pillager"
	stub.loot = { { link = "item:" .. PLAIN_ITEM }, { link = "item:" .. RECIPE_ITEM, sources = { npc(46), 1 } } }
	stub.Fire("LOOT_OPENED")
	stub.Fire("LOOT_OPENED") -- same corpse, window reopened: counts once
	local l = ns.db.sources[RECIPE_ITEM].loot["Creature:46"]
	eq(l.n, 1); eq(l.name, "Defias Pillager"); eq(l.zone, "Orgrimmar"); eq(l.chance, nil)
	stub.loot[2].sources = { ("Creature-0-3-1-1-46-000099999Z"), 1 } -- another corpse
	stub.Fire("LOOT_OPENED")
	eq(ns.db.sources[RECIPE_ITEM].loot["Creature:46"].n, 2)
	stub.loot[2].sources = { "GameObject-0-3-1-1-2040-0000AAAAAA", 1 }
	stub.Fire("LOOT_OPENED")
	eq(ns.db.sources[RECIPE_ITEM].loot["GameObject:2040"].n, 1)
	eq(ns.db.sources[RECIPE_ITEM].loot["GameObject:2040"].name, nil)
end)

it("loot from items or unknown sources is not recorded", function()
	local ns, stub = setup()
	stub.loot = { { link = "item:" .. RECIPE_ITEM, sources = { "Item-1-0-ABC", 1 } } }
	stub.Fire("LOOT_OPENED")
	eq(next(ns.db.sources), nil)
end)

it("records quest reward and choice recipes once per quest", function()
	local ns, stub, f = setup()
	f.questnpc = "Alliance"
	stub.quest = { id = 1234, title = "A Test Quest", choices = { "item:" .. RECIPE_ITEM, "item:" .. PLAIN_ITEM }, rewards = {} }
	stub.Fire("QUEST_DETAIL"); stub.Fire("QUEST_COMPLETE")
	local q = ns.db.sources[RECIPE_ITEM].quests[1234]
	eq(q.name, "A Test Quest"); eq(q.faction, "A"); eq(q.choice, true); eq(q.zone, "Orgrimmar")
	eq(ns.db.sources[PLAIN_ITEM], nil)
	stub.quest = { id = 0, choices = { "item:" .. RECIPE_ITEM }, rewards = {} }
	stub.Fire("QUEST_DETAIL") -- no quest id: nothing
	local n = 0
	for _ in pairs(ns.db.sources[RECIPE_ITEM].quests) do n = n + 1 end
	eq(n, 1)
end)

it("recorded sources are keyed to the recipe via the bundled item", function()
	local ns, stub = setup()
	stub.guids.npc, stub.names.npc = npc(7), "Vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 100 } }
	stub.Fire("MERCHANT_SHOW")
	local m = ns.Sources.Merged(3762)
	eq(m.skill, 95); eq(m.vendors[1].name, "Vendor"); eq(m.vendors[1].seen ~= nil, true)
end)

it("merge order: recorded vendor replaces a bundled one of the same name, others stay labelled", function()
	local ns, stub = setup()
	ns.SourceData[3762].vendors = { { name = "Vendor", zone = "Old", price = 5000, src = "QuestieDB" },
		{ name = "Other", zone = "Far", price = 700, src = "QuestieDB" } }
	stub.guids.npc, stub.names.npc = npc(7), "vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 1200 } }
	stub.Fire("MERCHANT_SHOW")
	local where = ns.RecipeWhere(3762)
	eq(where[1].text, "Vendor: vendor (Orgrimmar) - " .. ns.FormatMoney(1200))
	eq(where[1].origin, "seen"); eq(where[1].label, "seen by you just now")
	eq(where[2].text, "Vendor: Other (Far) - " .. ns.FormatMoney(700))
	eq(where[2].origin, "static"); eq(where[2].label, "QuestieDB")
	eq(#where, 2)
	local cost, how = ns.LearnCost(3762)
	eq(cost, 1200); eq(how, "vendor")
end)

it("seen age label", function()
	local ns, stub = setup()
	stub.guids.npc, stub.names.npc = npc(7), "Vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 1 } }
	stub.Fire("MERCHANT_SHOW")
	local t = ns.db.sources[RECIPE_ITEM].vendors[7].t
	ns.db.sources[RECIPE_ITEM].vendors[7].t = t - 2 * 3600 - 5
	eq(ns.RecipeWhere(3762)[1].label, "seen by you 2h ago")
end)

it("'Source not known yet' disappears once a source is recorded", function()
	local ns, stub = setup()
	local prof = { skill = 100 }
	eq((ns.RecipeStatus(prof, 3762, { learned = false })), "unlearned")
	eq(#ns.RecipeWhere(3762), 0)
	stub.guids.target, stub.names.target = npc(46), "Defias Pillager"
	stub.loot = { { link = "item:" .. RECIPE_ITEM, sources = { npc(46), 1 } } }
	stub.Fire("LOOT_OPENED")
	local status, required = ns.RecipeStatus(prof, 3762, { learned = false })
	eq(status, "drop"); eq(required, 95)
	eq(ns.RecipeWhere(3762)[1].text, "Drop: Defias Pillager (Orgrimmar)")
end)

it("a quest line replaces a bundled quest of the same title; vendors outrank quests in status", function()
	local ns, stub = setup()
	ns.SourceData[3762].quests = { { name = "A Test Quest", faction = "H", src = "QuestieDB" } }
	stub.quest = { id = 9, title = "A test quest", choices = {}, rewards = { "item:" .. RECIPE_ITEM } }
	stub.Fire("QUEST_COMPLETE")
	local where = ns.RecipeWhere(3762)
	eq(#where, 1); eq(where[1].origin, "seen")
	eq((ns.RecipeStatus({ skill = 1 }, 3762, { learned = false })), "quest")
end)

it("a recipe with no bundled entry stays reachable through the item's spell", function()
	local ns, stub = setup()
	ns.SourceData = {}
	ns.RecipeData = { [4444] = {} }
	C_Item.GetItemSpell = function() return "Learn", 4444 end
	stub.guids.npc, stub.names.npc = npc(7), "Vendor"
	stub.merchant = { { itemID = RECIPE_ITEM, price = 100 } }
	stub.Fire("MERCHANT_SHOW")
	eq(ns.db.sources[RECIPE_ITEM].recipe, 4444)
	eq((ns.RecipeStatus({ skill = 1 }, 4444, { learned = false })), "vendor")
end)
