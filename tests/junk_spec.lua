local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[100] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[400] = { name = "Old Boots", sellPrice = 70 }
	stub.items[500] = { name = "Quest Thing" }
	stub.itemClass[500] = 12
	stub.ah[100] = 50
	stub.bags[0] = {
		{ itemID = 100, stackCount = 20, quality = 1 },
		{ itemID = 400, stackCount = 1, quality = 1 },
		{ itemID = 500, stackCount = 1, quality = 1 },
		{ itemID = 400, stackCount = 1, quality = 1 },
	}
	-- Selling at a merchant: using the item removes it.
	stub.sold = {}
	C_Container.UseContainerItem = function(bag, slot)
		table.insert(stub.sold, stub.bags[bag][slot].itemID)
		stub.bags[bag][slot] = false
	end
	MerchantFrame = CreateFrame("Frame", "MerchantFrame")
	return ns, stub
end

local function byID(rows)
	local m = {}
	for _, r in ipairs(rows) do m[r.itemID] = r end
	return m
end

it("marks items as junk per item ID; junk and keep exclude each other; quest items can't be junk", function()
	local ns = setup()
	ns.ToggleKeep(400)
	ns.ToggleJunk(400)
	eq(ns.db.keep[400], nil)
	local rows = byID(ns.BagRows())
	eq(rows[400].junk, true); eq(rows[400].best, "junk"); eq(rows[400].bestValue, 140)
	ns.ToggleJunk(500)
	eq(byID(ns.BagRows())[500].junk, false)
	ns.ToggleKeep(400)
	eq(ns.db.junk[400], nil)
end)

it("sells every marked stack at the merchant with one click, then remembers the mark", function()
	local ns, stub = setup()
	ns.ToggleJunk(400)
	stub.Fire("MERCHANT_SHOW")
	assert(ns.Junk.button, "button on the merchant frame")
	eq(ns.Junk.button.count, 2)
	assert(ns.Junk.Sell())
	for _ = 1, 5 do
		if not ns.Junk.Running() then break end
		ns.Junk.button.scripts.OnUpdate(ns.Junk.button, 0.3)
	end
	eq(table.concat(stub.sold, ","), "400,400")
	eq(ns.Junk.Running(), false)
	eq(stub.bags[0][1].itemID, 100) -- linen untouched
	-- loot another pair of boots: still junk
	stub.bags[0][2] = { itemID = 400, stackCount = 1, quality = 1 }
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(ns.Junk.button.count, 1)
	stub.Fire("MERCHANT_CLOSED")
	eq(ns.Junk.Sell(), false) -- no merchant
end)

it("bags view: clicking a row opens Keep / Junk / Normal", function()
	local ns, stub = setup()
	ns.db.settings.view = "bags"
	ns.ToggleProfitFrame()
	local row
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.itemID == 100 then row = f end
	end
	row.scripts.OnEnter(row)
	row.scripts.OnClick(row, "LeftButton")
	local menu = CraftWiseItemMenu
	eq(menu.buttons.normal.selected, true)
	menu.buttons.junk.scripts.OnClick(menu.buttons.junk)
	eq(ns.db.junk[100], true)
	ns.ShowItemMenu(100)
	eq(menu.buttons.junk.selected, true)
	menu.buttons.keep.scripts.OnClick(menu.buttons.keep)
	eq(ns.db.keep[100], true); eq(ns.db.junk[100], nil)
	ns.ShowItemMenu(500) -- quest item: junk not allowed
	menu.buttons.junk.scripts.OnClick(menu.buttons.junk)
	eq(ns.db.junk[500], nil)
end)

it("Alt + right-click on an item in the bags (Blizzard or Bagnon button) opens the menu", function()
	local ns, stub = setup()
	IsAltKeyDown = function() return true end
	local blizzard = CreateFrame("Button")
	blizzard.GetBagID = function() return 0 end
	blizzard.GetID = function() return 2 end
	GetMouseFoci = function() return { blizzard } end
	stub.Fire("GLOBAL_MOUSE_DOWN", "RightButton")
	eq(CraftWiseItemMenu.itemID, 400)
	assert(CraftWiseItemMenu.shown, "menu shown")
	local bagnon = CreateFrame("Button")
	bagnon.bag = 0
	bagnon.GetID = function() return 1 end
	GetMouseFoci = function() return { bagnon } end
	CraftWiseItemMenu.IsMouseOver = function() return false end
	stub.Fire("GLOBAL_MOUSE_DOWN", "RightButton")
	eq(CraftWiseItemMenu.itemID, 100)
	IsAltKeyDown = function() return false end
	stub.Fire("GLOBAL_MOUSE_DOWN", "LeftButton") -- click elsewhere closes it
	eq(CraftWiseItemMenu.shown, false)
end)

it("shows the junk icon on marked items in Blizzard bags and Bagnon", function()
	local ns, stub = setup()
	local hooks = {}
	hooksecurefunc = function(t, name, fn)
		if type(t) == "string" then return end
		hooks[t] = hooks[t] or {}
		hooks[t][name] = fn
	end
	local function button(bag, slot)
		local b = CreateFrame("Button")
		b.JunkIcon = CreateFrame("Frame")
		b.JunkIcon:Hide()
		b.GetBagID = function() return bag end
		b.GetID = function() return slot end
		return b
	end
	ContainerFrameCombinedBags = CreateFrame("Frame")
	ContainerFrameCombinedBags.Update = function() end
	ContainerFrameCombinedBags.Items = { button(0, 1), button(0, 2) }
	Bagnon = { Item = { UpdateBorder = function() end }, Frames = { Update = function() end } }
	stub.Fire("PLAYER_LOGIN")
	ns.SetItemState(400, "junk")
	eq(ContainerFrameCombinedBags.Items[2].JunkIcon.shown, true) -- boots
	eq(ContainerFrameCombinedBags.Items[1].JunkIcon.shown, false) -- linen
	local item = { JunkIcon = CreateFrame("Frame"), info = { itemID = 400 }, IsCached = function() return false end }
	item.JunkIcon:Hide()
	hooks[Bagnon.Item].UpdateBorder(item)
	eq(item.JunkIcon.shown, true)
	ns.SetItemState(400, "normal")
	eq(ContainerFrameCombinedBags.Items[2].JunkIcon.shown, false)
end)
