local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[100] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[200] = { name = "Green Sword", sellPrice = 500 }
	stub.items[300] = { name = "Bound Boots", sellPrice = 300 }
	stub.items[400] = { name = "Grey Junk", sellPrice = 7 }
	stub.itemClass[200], stub.itemClass[300] = 2, 4
	stub.bags[0] = {
		{ itemID = 100, stackCount = 20, quality = 1 },
		{ itemID = 200, stackCount = 1, quality = 2 },
		{ itemID = 100, stackCount = 5, quality = 1 },
	}
	stub.bags[1] = {
		{ itemID = 300, stackCount = 1, quality = 2, isBound = true },
		{ itemID = 400, stackCount = 3, quality = 0 },
	}
	stub.ah[100], stub.ah[200], stub.ah[300] = 50, 400, 9999
	return ns, stub
end

local function byID(rows)
	local m = {}
	for _, r in ipairs(rows) do m[r.itemID] = r end
	return m
end

it("stacks add up across slots and bags", function()
	local ns = setup()
	local rows = byID(ns.BagRows())
	eq(rows[100].count, 25)
	eq(rows[100].vendorValue, 13 * 25)
	eq(rows[100].ahValue, 1187) -- 50 x 0.95 x 25 = 1187.5, rounded down
	eq(rows[100].best, "auction")
	eq(rows[100].margin, 1187 - 13 * 25)
end)

it("vendor wins when the AH pays less after the cut", function()
	local ns = setup()
	local sword = byID(ns.BagRows())[200]
	eq(sword.best, "vendor"); eq(sword.canDisenchant, true); eq(sword.deValue, nil)
end)

it("soulbound items get no AH value", function()
	local ns = setup()
	local boots = byID(ns.BagRows())[300]
	eq(boots.bound, true); eq(boots.ahValue, nil); eq(boots.best, "vendor")
end)

it("reagents for known recipes are marked", function()
	local ns, stub = setup()
	stub.profession = { id = 197, name = "Tailoring", skill = 50, max = 75, recipes = {
		[2387] = { info = { name = "Linen Cloak", learned = true }, schematic = stub.Schematic({ { 100, 3 } }, 2570) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(byID(ns.BagRows())[100].reagent, true)
	eq(byID(ns.BagRows())[200].reagent, false)
end)

-- Sell › Bags in the main window (#155): the rows of its list, groups left out.
local function pageItems(ns)
	ns.Main.state.vendorOnly.bags = true -- no AH observation in these specs
	ns.Main.Open("bags")
	local shown = {}
	for _, f in ipairs(ns.Main.ListOf("bags").box.frames) do
		if not f.elementData.row.group then
			shown[#shown + 1] = f
		end
	end
	return shown
end

it("Sell › Bags renders the items grouped by best outcome and shows tooltips", function()
	local ns, stub = setup()
	local shown = pageItems(ns)
	eq(#shown, 4)
	eq(shown[1].elementData.row.itemID, 100) -- Sell at the AH comes first
	for _, f in ipairs(shown) do f.scripts.OnEnter(f); f.scripts.OnLeave(f) end
	stub.Fire("BAG_UPDATE_DELAYED")
end)

it("kept items leave the advice and totals, sort last, and can be hidden", function()
	local ns, stub = setup()
	ns.ToggleKeep(100)
	local rows = byID(ns.BagRows())
	eq(rows[100].kept, true); eq(rows[100].best, nil); eq(rows[100].bestValue, nil)
	local shown = pageItems(ns)
	local target = shown[#shown]
	eq(target.elementData.row.itemID, 100) -- kept: the Keep group, last (no junk marked)
	eq(target.elementData.row.groupKey, "keep")
	-- clicking the row opens Keep / Junk / Normal; Normal sells it again
	target.scripts.OnClick(target, "LeftButton")
	eq(CraftWiseItemMenu.buttons.keep.current, true)
	CraftWiseItemMenu.buttons.normal.scripts.OnClick(CraftWiseItemMenu.buttons.normal)
	eq(ns.db.keep[100], nil)
	eq(CraftWiseItemMenu.shown, false)
	ns.ToggleKeep(100)
	ns.db.settings.showKept = false
	for _, f in ipairs(pageItems(ns)) do assert(f.elementData.row.itemID ~= 100, "kept item shown") end
end)

it("quest items are always kept", function()
	local ns, stub = setup()
	stub.items[500] = { name = "Dal Bloodclaw's Skull", sellPrice = 0 }
	stub.itemClass[500] = 12
	table.insert(stub.bags[1], { itemID = 500, stackCount = 1, quality = 1 })
	local q = byID(ns.BagRows())[500]
	eq(q.questItem, true); eq(q.kept, true); eq(q.best, nil)
end)

it("AH only a little above vendor: vendor it and say how much the AH would pay more", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[700] = { name = "Light Feather", sellPrice = 7 }
	stub.items[800] = { name = "Silk Cloth", sellPrice = 38 }
	stub.ah[700], stub.ah[800] = 8, 200
	stub.bags[0] = { { itemID = 700, stackCount = 20, quality = 1 }, { itemID = 800, stackCount = 20, quality = 1 } }
	local rows = byID(ns.BagRows())
	-- feathers: AH 20 x 8 x 0.95 = 152c vs vendor 140c: +12c, under 20%
	eq(rows[700].ahValue, 152); eq(rows[700].best, "vendor"); eq(rows[700].ahSmallEdge, 12)
	-- silk: AH 3800c vs vendor 760c: clearly worth it
	eq(rows[800].best, "auction"); eq(rows[800].ahSmallEdge, nil)
	-- one fish: vendor 2c, AH 16c after the cut: 8x - well over 20%
	stub.items[900] = { name = "Darkshore Grouper", sellPrice = 2 }
	stub.ah[900] = 17
	stub.bags[0][3] = { itemID = 900, stackCount = 1, quality = 1 }
	eq(byID(ns.BagRows())[900].best, "auction")
	SlashCmdList.CRAFTWISE("ahmin 5")
	eq(byID(ns.BagRows())[700].best, "auction")
	SlashCmdList.CRAFTWISE("ahmin 20")
	local found
	for _, f in ipairs(pageItems(ns)) do
		if f.elementData.row.itemID == 700 then
			found = true
			assert(f.cells[4].text:find("under your AH rule", 1, true), f.cells[4].text)
		end
	end
	assert(found, "feathers listed")
end)

it("AH rule panel: percent and minimum copper, both with - / +", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[900] = { name = "Darkshore Grouper", sellPrice = 2 }
	stub.ah[900] = 17
	stub.bags[0] = { { itemID = 900, stackCount = 1, quality = 1 } }
	local rows = byID(ns.BagRows())
	eq(rows[900].best, "auction") -- +14c, over 20% and over the 10c minimum
	ns.ToggleAHRule(UIParent)
	local panel = CraftWiseAHRule
	assert(panel.shown, "panel open")
	-- buttons: find by their labels in creation order
	local minus, plus = {}, {}
	for _, w in ipairs(stub.frames) do
		if w.label and w.label.text == "+" then plus[#plus + 1] = w end
		if w.label and w.label.text == "-" then minus[#minus + 1] = w end
	end
	plus[#plus].scripts.OnClick(plus[#plus]) -- copper: 10c -> 20c
	eq(ns.db.settings.ahMinCopper, 20)
	eq(byID(ns.BagRows())[900].best, "vendor") -- 14c is now too little
	plus[#plus - 1].scripts.OnClick(plus[#plus - 1]) -- percent: 20 -> 25
	eq(ns.db.settings.ahMinPercent, 25)
	minus[#minus].scripts.OnClick(minus[#minus]) -- copper back to 10c
	eq(ns.db.settings.ahMinCopper, 10)
	eq(ns.StepCopper(0, -1), 0); eq(ns.StepCopper(10, 1), 20); eq(ns.StepCopper(7, -1), 5)
	SlashCmdList.CRAFTWISE("ahmin 30 0")
	eq(ns.db.settings.ahMinPercent, 30); eq(ns.db.settings.ahMinCopper, 0)
end)
