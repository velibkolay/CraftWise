local function setup()
	local ns, stub = LoadAddon()
	stub.items[1001] = { name = "Old Cloak", level = 10, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 10 } }
	stub.items[2001] = { name = "Crafted Cloak", level = 15, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 15, ITEM_MOD_STAMINA_SHORT = 1 } }
	stub.items[2002] = { name = "Worse Cloak", level = 8, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 20 } }
	stub.items[2003] = { name = "Leather Belt", level = 5, equipLoc = "INVTYPE_WAIST", stats = { RESISTANCE0_NAME = 5 } }
	stub.items[2004] = { name = "Mail Gloves", level = 20, equipLoc = "INVTYPE_HAND" }
	stub.items[2005] = { name = "High Boots", level = 30, minLevel = 30, equipLoc = "INVTYPE_FEET" }
	stub.items[2006] = { name = "Same-level Cloak", level = 10, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 12 } }
	stub.items[2318] = { name = "Light Leather" }
	stub.equipped.BACKSLOT = 1001
	stub.cantUse[2004] = true
	local function r(id, name, out, learned)
		return { info = { name = name, learned = learned ~= false }, schematic = stub.Schematic({ { 2318, 2 } }, out) }
	end
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[1] = r(1, "Crafted Cloak", 2001), [2] = r(2, "Worse Cloak", 2002), [3] = r(3, "Leather Belt", 2003),
		[4] = r(4, "Mail Gloves", 2004), [5] = r(5, "High Boots", 2005), [6] = r(6, "Same-level Cloak", 2006),
		[7] = r(7, "Unlearned Cloak", 2001, false),
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	return ns, stub
end

local function byItem(rows)
	local t = {}
	for _, row in ipairs(rows) do t[row.itemID] = row end
	return t
end

it("suggests higher item level, same level with more armour, and empty slots", function()
	local ns = setup()
	local rows = byItem(ns.UpgradeRows())
	eq(rows[2001].ilvlGain, 5); eq(rows[2001].armorGain, 5); eq(rows[2001].slotLabel, "Back")
	eq(rows[2006].ilvlGain, 0); eq(rows[2006].armorGain, 2)
	eq(rows[2003].emptySlot, true)
	eq(rows[2002], nil) -- lower item level, even with more armour
end)

it("leaves out items you can't use or are too low level for", function()
	local ns = setup()
	local rows = byItem(ns.UpgradeRows())
	eq(rows[2004], nil) -- red tooltip line
	eq(rows[2005], nil) -- requires level 30
end)

it("marks when the reagents are in your bags", function()
	local ns, stub = setup()
	eq(byItem(ns.UpgradeRows())[2001].haveReagents, false)
	stub.counts[2318] = 2
	eq(byItem(ns.UpgradeRows())[2001].haveReagents, true)
end)

it("compares rings with the weaker of the two ring slots", function()
	local ns, stub = setup()
	stub.items[3001] = { name = "Good Ring", level = 20, equipLoc = "INVTYPE_FINGER" }
	stub.items[3002] = { name = "Bad Ring", level = 5, equipLoc = "INVTYPE_FINGER" }
	stub.items[3003] = { name = "Crafted Ring", level = 10, equipLoc = "INVTYPE_FINGER" }
	stub.equipped.FINGER0SLOT, stub.equipped.FINGER1SLOT = 3001, 3002
	stub.profession.recipes[8] = { info = { name = "Crafted Ring", learned = true }, schematic = stub.Schematic({ { 2318, 1 } }, 3003) }
	stub.Fire("TRADE_SKILL_SHOW")
	local row = byItem(ns.UpgradeRows())[3003]
	eq(row.current.itemID, 3002); eq(row.ilvlGain, 5)
end)

-- Rows of a main window list page that are items (not group headers or the search row).
local function pageItems(M, key)
	local out = {}
	for _, fr in ipairs(M.ListOf(key).box.frames) do
		local r = fr.element and fr.element.row
		if r and r.itemID and not r.header then out[#out + 1] = r end
	end
	return out
end

it("Look up › Upgrades lists what you can craft; the item menu dismisses and restores a suggestion", function()
	local ns = setup()
	local M = ns.Main
	M.Open("upgrades")
	eq(M.shown.page, "upgrades"); eq(M.shown.state, "list")
	local rows = pageItems(M, "upgrades")
	eq(#rows, 3)
	eq(rows[1].itemID, 2003) -- empty slot first, then biggest gain
	eq(rows[1].gainText, "fills the slot")
	ns.ShowItemMenu(2001)
	local dismiss = CraftWiseItemMenu.buttons.dismiss
	eq(dismiss.shown, true); eq(dismiss.label.text, "Don't suggest as upgrade")
	dismiss.scripts.OnClick(dismiss)
	eq(ns.db.dismissed[2001], true)
	eq(#pageItems(M, "upgrades"), 2)
	ns.db.settings.showDismissed = true
	ns.Notify("UPGRADES_CHANGED")
	rows = pageItems(M, "upgrades")
	eq(#rows, 3); eq(rows[3].itemID, 2001); eq(rows[3].dismissed, true) -- dismissed last
	ns.ShowItemMenu(2001)
	eq(dismiss.label.text, "Suggest as upgrade again")
	dismiss.scripts.OnClick(dismiss)
	eq(ns.db.dismissed[2001], nil)
	ns.ShowItemMenu(2318) -- not gear: no upgrade line
	eq(dismiss.shown, false)
	stub = nil
end)
it("main stats inline: primary stats and stamina, for the item and the equipped one", function()
	local ns, stub = setup()
	eq(ns.Upgrades.MainStatsText({ ITEM_MOD_STAMINA_SHORT = 2, ITEM_MOD_AGILITY_SHORT = 3, RESISTANCE0_NAME = 9 }), "+3 AGI +2 STA")
	eq(ns.Upgrades.MainStatsText({ RESISTANCE0_NAME = 9 }), "")
	eq(ns.Upgrades.MainStatsText(nil), nil)
	stub.items[1001].stats.ITEM_MOD_STRENGTH_SHORT = 1
	local row = byItem(ns.UpgradeRows())[2001]
	eq(row.mainStats, "+1 STA"); eq(row.currentStats, "+1 STR")
	eq(byItem(ns.UpgradeRows())[2003].currentStats, nil) -- empty slot
end)

it("rows show the total cost to obtain, never a profit", function()
	local ns, stub = setup()
	stub.items[2318].sellPrice = 5
	ns.db.vendor[2318] = 10
	local row = byItem(ns.UpgradeRows())[2001]
	eq(row.cost, 20); eq(row.costComplete, true); eq(row.learnFirst, false); eq(row.section, "craft")
	eq(row.profit, nil); eq(row.sellsFor, nil)
end)

it("items the client hasn't loaded yet are requested, not guessed", function()
	local ns, stub = setup()
	local requested = {}
	C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
	stub.items[2010] = nil
	stub.profession.recipes[10] = { info = { name = "Unknown Boots", learned = true }, schematic = stub.Schematic({ { 2318, 1 } }, 2010) }
	C_Item.GetItemInfoInstant = function(id) return id, nil, nil, id == 2010 and "INVTYPE_FEET" or (stub.items[id] and stub.items[id].equipLoc or ""), nil end
	stub.Fire("TRADE_SKILL_SHOW")
	eq(byItem(ns.UpgradeRows())[2010], nil)
	eq(requested[2010], true)
	local notified = false
	ns.Listen("UPGRADES_CHANGED", function() notified = true end)
	stub.items[2010] = { name = "Unknown Boots", level = 12, equipLoc = "INVTYPE_FEET" }
	stub.Fire("GET_ITEM_INFO_RECEIVED", 2010, true)
	eq(notified, true)
	eq(byItem(ns.UpgradeRows())[2010].emptySlot, true)
end)

it("leaves out items the client says this class can't wear", function()
	local ns, stub = setup()
	stub.noProficiency[2001] = true
	eq(byItem(ns.UpgradeRows())[2001], nil)
end)

-- Learnable recipes (#16 scope extension, decision 2026-11-09).
local function learnSetup(opts)
	local ns, stub = LoadAddon(opts)
	stub.items[1001] = { name = "Old Cloak", level = 10, equipLoc = "INVTYPE_CLOAK", stats = { RESISTANCE0_NAME = 10 } }
	stub.items[2318] = { name = "Light Leather" }
	stub.equipped.BACKSLOT = 1001
	local slots = { [4001] = "INVTYPE_HEAD", [4002] = "INVTYPE_CHEST", [4003] = "INVTYPE_LEGS", [4004] = "INVTYPE_FEET",
		[4005] = "INVTYPE_HAND", [4006] = "INVTYPE_WRIST", [4007] = "INVTYPE_WAIST", [4008] = "INVTYPE_SHOULDER" }
	for id, loc in pairs(slots) do
		stub.items[id] = { name = "Gear " .. id, level = 12, equipLoc = loc }
	end
	local recipes = {}
	for i = 1, 8 do
		recipes[100 + i] = { info = { name = "Recipe " .. i, learned = false }, schematic = stub.Schematic({ { 2318, 1 } }, 4000 + i) }
	end
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = recipes }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.vendor[2318] = 10
	return ns, stub
end

it("learnable from a trainer: marked learn first, cost = reagents + trainer fee", function()
	local ns = learnSetup()
	ns.db.trainer[101] = { fee = 500, required = 80 }
	local row = byItem(ns.UpgradeRows())[4001]
	eq(row.learnFirst, true); eq(row.learnKind, "trainer"); eq(row.learnText, "Trainer")
	eq(row.learnCost, 500); eq(row.reagentCost, 10); eq(row.cost, 510); eq(row.costComplete, true)
end)

it("learnable from a vendor of your faction, not from the other faction's", function()
	local ns = learnSetup()
	ns.SourceData = {
		[102] = { skill = 90, vendors = { { name = "Tamar", zone = "Orgrimmar", faction = "H", price = 1200 } } },
		[103] = { skill = 90, vendors = { { name = "Alliance Guy", zone = "Stormwind", faction = "A", price = 1200 } } },
	}
	local rows = byItem(ns.UpgradeRows())
	eq(rows[4002].learnKind, "vendor"); eq(rows[4002].cost, 1210)
	eq(rows[4002].learnText, "Vendor: Tamar (Orgrimmar) - " .. ns.FormatMoney(1200))
	eq(rows[4003], nil)
end)

it("learnable as a drop (cost incomplete without a price) or from the AH", function()
	local ns, stub = learnSetup({ auctionator = true })
	ns.SourceData = {
		[104] = { skill = 60, item = 5004, drops = { { name = "Kobold", zone = "Elwynn" } } },
		[105] = { skill = 60, item = 5005 },
	}
	stub.ah[5005] = 3000
	local rows = byItem(ns.UpgradeRows())
	eq(rows[4004].learnKind, "drop"); eq(rows[4004].learnCost, nil); eq(rows[4004].costComplete, false)
	eq(rows[4004].cost, 10)
	eq(rows[4005].learnKind, "auction"); eq(rows[4005].learnCost, 3000); eq(rows[4005].cost, 3010)
end)

it("leaves out recipes above your skill, with an unknown requirement, quest-only or without a source", function()
	local ns = learnSetup()
	ns.db.trainer[101] = { fee = 500, required = 120 } -- skill 100
	ns.SourceData = {
		[102] = { vendors = { { name = "Tamar", faction = "H", price = 1200 } } }, -- requirement unknown
		[106] = { skill = 50, quests = { { name = "Some Quest" } } },
	}
	local rows = byItem(ns.UpgradeRows())
	eq(rows[4001], nil); eq(rows[4002], nil); eq(rows[4006], nil)
	eq(rows[4007], nil) -- no source at all
end)

it("a known recipe wins over a learnable one for the same item; cheaper learnable wins otherwise", function()
	local ns, stub = learnSetup()
	stub.profession.recipes[201] = { info = { name = "Known Head", learned = true }, schematic = stub.Schematic({ { 2318, 3 } }, 4001) }
	stub.profession.recipes[202] = { info = { name = "Pricey Chest", learned = false }, schematic = stub.Schematic({ { 2318, 1 } }, 4002) }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.db.trainer[101] = { fee = 1, required = 1 }
	ns.db.trainer[102] = { fee = 100, required = 1 }
	ns.db.trainer[202] = { fee = 900, required = 1 }
	local rows = byItem(ns.UpgradeRows())
	eq(rows[4001].learnFirst, false); eq(rows[4001].recipeID, 201); eq(rows[4001].cost, 30)
	eq(rows[4002].recipeID, 102); eq(rows[4002].cost, 110)
end)

it("Look up › Upgrades shows learn-first rows with how to learn and the total cost", function()
	local ns = learnSetup()
	ns.db.trainer[101] = { fee = 500, required = 80 }
	local M = ns.Main
	M.Open("upgrades")
	local row
	for _, fr in ipairs(M.ListOf("upgrades").box.frames) do
		local r = fr.element and fr.element.row
		if r and r.itemID == 4001 then row = fr end
	end
	assert(row, "row 4001")
	eq(row.element.row.how, "learn: trainer " .. ns.FormatMoney(500, true))
	eq(row.cwUp.how.text, row.element.row.how)
	eq(row.element.row.costText, ns.FormatCoins(510))
	local tip = M.Upgrades.CostTip(row.element.row)
	eq(tip[1], "Cost"); eq(tip[#tip], "Learn: Trainer")
end)