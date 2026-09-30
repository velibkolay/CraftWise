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

it("upgrades view renders; right-click dismisses and restores a suggestion", function()
	local ns, stub = setup()
	ns.db.settings.view = "upgrades"
	ns.ToggleProfitFrame()
	local function shown()
		local list = {}
		for _, f in ipairs(stub.frames) do
			if f.data and f.shown ~= false then list[#list + 1] = f end
		end
		return list
	end
	local rows = shown()
	eq(#rows, 3)
	eq(rows[1].data.itemID, 2003) -- empty slot first, then biggest gain
	for _, f in ipairs(rows) do f.scripts.OnEnter(f) end
	local target
	for _, f in ipairs(rows) do
		if f.data.itemID == 2001 then target = f end
	end
	target.scripts.OnClick(target, "RightButton")
	eq(ns.db.dismissed[2001], true)
	eq(#shown(), 2)
	ns.db.settings.showDismissed = true
	ns.RefreshProfitFrame()
	rows = shown()
	eq(#rows, 3); eq(rows[3].data.itemID, 2001) -- dismissed last
	rows[3].scripts.OnClick(rows[3], "RightButton")
	eq(ns.db.dismissed[2001], nil)
	stub.Fire("PLAYER_EQUIPMENT_CHANGED")
end)
