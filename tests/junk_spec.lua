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

it("the chosen click on an item in the bags (Blizzard/Baganator or Bagnon button) opens the menu", function()
	local ns, stub = setup()
	-- default: middle click, no modifier
	local blizzard0 = CreateFrame("Button")
	blizzard0.GetBagID = function() return 0 end
	blizzard0.GetID = function() return 2 end
	GetMouseFoci = function() return { blizzard0 } end
	stub.Fire("GLOBAL_MOUSE_DOWN", "MiddleButton")
	eq(CraftWiseItemMenu.itemID, 400)
	CraftWiseItemMenu:Hide()
	stub.Fire("GLOBAL_MOUSE_DOWN", "RightButton") -- plain right-click: the game's own action only
	eq(CraftWiseItemMenu.shown, false)
	ns.db.settings.menuClick = "altright"
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

it("registers a CraftWise junk plugin and sort mode with Baganator", function()
	local ns, stub = setup()
	local junk, sort, refreshed
	Baganator = { API = {
		RegisterJunkPlugin = function(label, id, fn) junk = fn end,
		RegisterContainerSort = function(label, id, fn) sort = fn end,
		RequestItemButtonsRefresh = function() refreshed = true end,
		Constants = { ContainerType = { Backpack = 0, Bank = 1 } },
	} }
	stub.Fire("PLAYER_LOGIN")
	ns.SetItemState(400, "junk")
	eq(junk(0, 2, 400), true); eq(junk(0, 1, 100), false)
	eq(refreshed, true)
	sort(false, 1) -- bank: not ours
	eq(ns.BagSort.Running(), false)
	sort(false, 0)
end)

it("marks items to sell on the AH: advised as Auction, exclusive with keep/junk, grouped first when sorting", function()
	local ns, stub = setup()
	stub.items[600] = { name = "Grouper", sellPrice = 14 }
	stub.ah[600] = 15 -- AH barely above vendor: the rule alone would say vendor
	stub.bags[0][5] = { itemID = 600, stackCount = 1, quality = 1 }
	eq(byID(ns.BagRows())[600].best, "vendor")
	ns.ShowItemMenu(600)
	local menu = CraftWiseItemMenu
	menu.buttons.auction.scripts.OnClick(menu.buttons.auction)
	eq(ns.db.sellAH[600], true)
	local row = byID(ns.BagRows())[600]
	eq(row.markedAH, true); eq(row.best, "auction"); eq(row.bestValue, math.floor(15 * 0.95))
	ns.ShowItemMenu(600)
	eq(menu.buttons.auction.selected, true)
	ns.ToggleJunk(600)
	eq(ns.db.sellAH[600], nil)
	ns.SetItemState(600, "auction")
	eq(ns.db.junk[600], nil)
	ns.ToggleKeep(600)
	eq(ns.db.sellAH[600], nil); eq(ns.db.keep[600], true)
	ns.ShowItemMenu(500) -- quest item can't be marked for the AH
	menu.buttons.auction.scripts.OnClick(menu.buttons.auction)
	eq(ns.db.sellAH[500], nil)
	-- sort: AH-marked items lead the selling part, junk last
	ns.SetItemState(600, "auction")
	ns.SetItemState(400, "junk")
	local target = ns.BagSort.Target(ns.BagSort.Slots())
	local sells = {}
	for _, s in ipairs(target) do
		if s and not s.keep then sells[#sells + 1] = s.itemID end
	end
	eq(sells[1], 600); eq(sells[#sells], 400)
end)

it("shows the AH mark in tooltips, Blizzard bags and as a Baganator corner widget", function()
	local ns, stub = setup()
	local widget, refreshed
	Baganator = { API = {
		RegisterCornerWidget = function(label, id, onUpdate, onInit, pos, fast)
			widget = { onUpdate = onUpdate, onInit = onInit, pos = pos, fast = fast }
		end,
		RequestItemButtonsRefresh = function() refreshed = true end,
	} }
	hooksecurefunc = function() end
	local b = CreateFrame("Button")
	b.JunkIcon = CreateFrame("Frame")
	b.GetBagID = function() return 0 end
	b.GetID = function() return 1 end
	ContainerFrameCombinedBags = CreateFrame("Frame")
	ContainerFrameCombinedBags.Update = function() end
	ContainerFrameCombinedBags.Items = { b }
	stub.Fire("PLAYER_LOGIN")
	ns.SetItemState(100, "auction")
	eq(refreshed, true)
	eq(ns.AHIcons[b].shown, true)
	eq(widget.pos.corner, "top_left"); eq(widget.fast, true)
	assert(widget.onInit(CreateFrame("Button")))
	eq(widget.onUpdate(nil, { itemID = 100 }), true)
	eq(widget.onUpdate(nil, { itemID = 400 }), false)
	local lines = {}
	local tip = { AddLine = function() end, AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end, Show = function() end }
	ns.AddTooltipLines(tip, 100)
	assert(table.concat(lines, ";"):find("Marked=.*Sell on AH"), table.concat(lines, ";"))
	ns.SetItemState(100, "normal")
	eq(ns.AHIcons[b].shown, false)
end)
