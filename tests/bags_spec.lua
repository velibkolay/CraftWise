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
	eq(rows[100].ahValue, 50 * 0.95 * 25)
	eq(rows[100].best, "auction")
	eq(rows[100].margin, 50 * 0.95 * 25 - 13 * 25)
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

it("bags view renders, sorts by best value and shows tooltips", function()
	local ns, stub = setup()
	ns.db.settings.view = "bags"
	ns.ToggleProfitFrame()
	local shown = {}
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false then
			shown[#shown + 1] = f.data
			f.scripts.OnEnter(f)
		end
	end
	eq(#shown, 4)
	eq(shown[1].itemID, 100) -- highest best value first
	stub.Fire("BAG_UPDATE_DELAYED")
end)

it("kept items leave the advice and totals, sort last, and can be hidden", function()
	local ns, stub = setup()
	ns.ToggleKeep(100)
	local rows = byID(ns.BagRows())
	eq(rows[100].kept, true); eq(rows[100].best, nil); eq(rows[100].bestValue, nil)
	ns.db.settings.view = "bags"
	ns.ToggleProfitFrame()
	local shown = {}
	for _, f in ipairs(stub.frames) do if f.data and f.shown ~= false then shown[#shown + 1] = f.data end end
	eq(shown[#shown].itemID, 100) -- kept last
	-- clicking the row opens Keep / Junk / Normal; Normal sells it again
	local target
	for _, f in ipairs(stub.frames) do
		if f.data and f.data.itemID == 100 and f.shown ~= false then target = f end
	end
	target.scripts.OnClick(target, "LeftButton")
	eq(CraftWiseItemMenu.buttons.keep.selected, true)
	CraftWiseItemMenu.buttons.normal.scripts.OnClick(CraftWiseItemMenu.buttons.normal)
	eq(ns.db.keep[100], nil)
	eq(CraftWiseItemMenu.shown, false)
	ns.ToggleKeep(100)
	ns.db.settings.showKept = false
	ns.RefreshProfitFrame()
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false then assert(not f.data.kept, "kept item shown") end
	end
end)

it("quest items are always kept", function()
	local ns, stub = setup()
	stub.items[500] = { name = "Dal Bloodclaw's Skull", sellPrice = 0 }
	stub.itemClass[500] = 12
	table.insert(stub.bags[1], { itemID = 500, stackCount = 1, quality = 1 })
	local q = byID(ns.BagRows())[500]
	eq(q.questItem, true); eq(q.kept, true); eq(q.best, nil)
end)
