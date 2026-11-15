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

it("Sell › Bags: clicking a row opens Keep / Junk / Normal", function()
	local ns, stub = setup()
	ns.Main.state.vendorOnly.bags = true
	ns.Main.Open("bags")
	local row
	for _, f in ipairs(ns.Main.ListOf("bags").box.frames) do
		if f.elementData.row.itemID == 100 then row = f end
	end
	row.scripts.OnEnter(row)
	row.scripts.OnClick(row, "LeftButton")
	local menu = CraftWiseItemMenu
	eq(menu.buttons.normal.current, true)
	menu.buttons.junk.scripts.OnClick(menu.buttons.junk)
	eq(ns.db.junk[100], true)
	ns.ShowItemMenu(100)
	eq(menu.buttons.junk.current, true)
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

it("marks junk in Blizzard bags and Bagnon with a grey corner and a dimmed icon", function()
	local ns, stub = setup()
	local hooks = {}
	hooksecurefunc = function(t, name, fn)
		if type(t) == "string" then return end
		hooks[t] = hooks[t] or {}
		hooks[t][name] = fn
	end
	local function button(bag, slot)
		local b = CreateFrame("Button")
		b.icon = CreateFrame("Frame")
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
	local boots, linen = ContainerFrameCombinedBags.Items[2], ContainerFrameCombinedBags.Items[1]
	eq(ns.SlotCorners[boots].shown, true)
	eq(ns.SlotCorners[boots].vertexColor[1], ns.Style.C.text3[1])
	eq(boots.icon.desaturated, true); eq(boots.icon.alpha, 0.55)
	eq(ns.SlotCorners[linen], nil)
	eq(linen.icon.desaturated, nil)
	local item = CreateFrame("Button")
	item.icon, item.info, item.IsCached = CreateFrame("Frame"), { itemID = 400 }, function() return false end
	hooks[Bagnon.Item].UpdateBorder(item)
	eq(ns.SlotCorners[item].shown, true)
	eq(item.icon.alpha, 0.55)
	ns.SetItemState(400, "normal")
	eq(ns.SlotCorners[boots].shown, false)
	eq(boots.icon.desaturated, false); eq(boots.icon.alpha, 1)
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
	eq(menu.buttons.auction.current, true)
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
	b.icon = CreateFrame("Frame")
	b.GetBagID = function() return 0 end
	b.GetID = function() return 1 end
	ContainerFrameCombinedBags = CreateFrame("Frame")
	ContainerFrameCombinedBags.Update = function() end
	ContainerFrameCombinedBags.Items = { b }
	stub.Fire("PLAYER_LOGIN")
	ns.SetItemState(100, "auction")
	eq(refreshed, true)
	eq(ns.SlotCorners[b].shown, true)
	eq(ns.SlotCorners[b].vertexColor[1], ns.Style.C.coinGold[1])
	eq(b.icon.desaturated, nil) -- AH marks don't dim
	eq(widget.pos.corner, "top_right"); eq(widget.fast, true)
	local corner = widget.onInit(CreateFrame("Button"))
	assert(corner)
	eq(corner.width, 13); eq(corner.texture, ns.Style.Media.fold)
	corner.GetParent = function() return b end
	eq(widget.onUpdate(corner, { itemID = 100 }), true)
	eq(corner.vertexColor[1], ns.Style.C.coinGold[1])
	eq(widget.onUpdate(corner, { itemID = 400 }), false)
	local lines = {}
	local tip = { AddLine = function() end, AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end, Show = function() end }
	ns.AddTooltipLines(tip, 100)
	assert(table.concat(lines, ";"):find("Marked=.*Sell on AH"), table.concat(lines, ";"))
	ns.SetItemState(100, "normal")
	eq(ns.SlotCorners[b].shown, false)
end)

it("covers the reagent bag (bag 5): listed in the Bags view, menu opens, junk there is sold", function()
	local ns, stub = setup()
	stub.items[3730] = { name = "Big Bear Meat", sellPrice = 12 }
	stub.bags[5] = { { itemID = 3730, stackCount = 1, quality = 1 } }
	local row
	for _, r in ipairs(ns.BagRows()) do if r.itemID == 3730 then row = r end end
	assert(row, "reagent bag item in the Bags view")
	local b = CreateFrame("Button")
	b.GetBagID = function() return 5 end
	b.GetID = function() return 1 end
	GetMouseFoci = function() return { b } end
	stub.Fire("GLOBAL_MOUSE_DOWN", "MiddleButton")
	eq(CraftWiseItemMenu.itemID, 3730)
	ns.SetItemState(3730, "junk")
	local found = false
	for _, s in ipairs(ns.Junk.Slots()) do if s.bag == 5 then found = true end end
	eq(found, true)
	-- the sort leaves the reagent bag alone
	for _, s in ipairs(ns.BagSort.Slots()) do assert(s.bag ~= 5) end
end)

-- #308: one symbol per concept. A junk-marked item shows the fold and the dim and never a coin;
-- unmarked grey items keep the client's coin.
local function withCoin(button)
	button.JunkIcon = CreateFrame("Frame")
	button.JunkIcon:Show()
	return button
end

it("Blizzard bag button: marked junk shows the fold, no coin, even when the client shows it again", function()
	local ns, stub = setup()
	local function button(bag, slot)
		local b = withCoin(CreateFrame("Button"))
		b.icon = CreateFrame("Frame")
		b.GetBagID = function() return bag end
		b.GetID = function() return slot end
		return b
	end
	ContainerFrameCombinedBags = CreateFrame("Frame")
	ContainerFrameCombinedBags.Update = function() end
	ContainerFrameCombinedBags.Items = { button(0, 1), button(0, 2) }
	stub.Fire("PLAYER_LOGIN")
	local linen, boots = ContainerFrameCombinedBags.Items[1], ContainerFrameCombinedBags.Items[2]
	ns.SetItemState(400, "junk")
	eq(ns.SlotCorners[boots].shown, true)
	eq(boots.JunkIcon.shown, false)
	boots.JunkIcon:Show() -- the client re-shows the coin at a merchant
	eq(boots.JunkIcon.shown, false)
	boots.JunkIcon:SetShown(true)
	eq(boots.JunkIcon.shown, false)
	eq(linen.JunkIcon.shown, true) -- unmarked items keep the client's coin
	ns.SetItemState(400, "normal")
	boots.JunkIcon:Show()
	eq(boots.JunkIcon.shown, true) -- unmarked again: the coin is the client's
end)

it("Bagnon item: marked junk shows the fold, no coin", function()
	local ns, stub = setup()
	Bagnon = { Item = { UpdateBorder = function() end }, Frames = { Update = function() end } }
	stub.Fire("PLAYER_LOGIN")
	local item = withCoin(CreateFrame("Button"))
	item.icon, item.info, item.IsCached = CreateFrame("Frame"), { itemID = 400 }, function() return false end
	ns.SetItemState(400, "junk")
	Bagnon.Item.UpdateBorder(item)
	eq(ns.SlotCorners[item].shown, true)
	eq(item.JunkIcon.shown, false)
	eq(item.icon.alpha, 0.55)
end)

it("Baganator corner widget: marked junk shows the fold and dim on the item button, no coin", function()
	local ns, stub = setup()
	local widget, junk
	Baganator = { API = {
		RegisterJunkPlugin = function(_, _, fn) junk = fn end,
		RegisterCornerWidget = function(_, _, onUpdate, onInit) widget = { onUpdate = onUpdate, onInit = onInit } end,
		RequestItemButtonsRefresh = function() end,
	} }
	stub.Fire("PLAYER_LOGIN")
	local button = withCoin(CreateFrame("Button"))
	button.icon = CreateFrame("Frame")
	local corner = widget.onInit(button)
	corner.GetParent = function() return CreateFrame("Frame") end -- Baganator re-parents it to its container
	ns.SetItemState(400, "junk")
	eq(widget.onUpdate(corner, { itemID = 400 }), true)
	eq(corner.vertexColor[1], ns.Style.C.text3[1])
	eq(button.icon.alpha, 0.55); eq(button.icon.desaturated, true)
	eq(button.JunkIcon.shown, false)
	button.JunkIcon:Show() -- Baganator's own junk widget shows it afterwards
	eq(button.JunkIcon.shown, false)
	ns.SetItemState(400, "normal")
	eq(widget.onUpdate(corner, { itemID = 400 }), false)
	eq(button.icon.alpha, 1)
end)

it("Baganator junk plugin: marked items are junk, unmarked sellable grey items stay junk, others not", function()
	local ns, stub = setup()
	stub.items[700] = { name = "Torn Rag", sellPrice = 3, quality = 0 }
	stub.items[701] = { name = "Odd Rag", sellPrice = 0, quality = 0 }
	local junk
	Baganator = { API = { RegisterJunkPlugin = function(_, _, fn) junk = fn end } }
	stub.Fire("PLAYER_LOGIN")
	ns.SetItemState(400, "junk")
	eq(junk(0, 1, 400), true)  -- marked
	eq(junk(0, 1, 700), true)  -- unmarked grey, sellable: the client's coin rule
	eq(junk(0, 1, 701), false) -- no sell value
	eq(junk(0, 1, 100), false) -- white item
end)

it("Bags page: a junk row's icon is dimmed like the slot, a kept row only greyed", function()
	local ns = setup()
	local P = ns.Main.Page("bags")
	local junk = P.DockedRow({ junk = true, name = "Old Boots", itemID = 400 })
	eq(junk.desaturate, true); eq(junk.dim, ns.JUNK_DIM)
	local kept = P.DockedRow({ kept = true, name = "Linen", itemID = 100 })
	eq(kept.desaturate, true); eq(kept.dim, nil)
end)
