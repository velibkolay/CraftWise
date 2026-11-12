-- Item menu, minimap button, addon compartment and the TOC icon in the Origami look (#159, #166).
-- Invented items only.
local QUEST, CLOTH = 990001, 990002

local function setup()
	local ns, stub = LoadAddon()
	stub.items[CLOTH] = { name = "Bolt of Test Cloth" }
	stub.items[QUEST] = { name = "Sealed Test Letter" }
	C_Item.GetItemNameByID = function(id) return stub.items[id] and stub.items[id].name end
	C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, id == QUEST and 12 or 7 end
	return ns, stub
end

local function visible(menu)
	local list = {}
	for _, opt in ipairs(menu.options) do
		local b = menu.buttons[opt.key]
		if b and b.shown ~= false then
			list[#list + 1] = { key = opt.key, y = b.lastPoint[5] }
		end
	end
	table.sort(list, function(a, b) return a.y > b.y end)
	local keys = {}
	for _, e in ipairs(list) do keys[#keys + 1] = e.key end
	return table.concat(keys, ",")
end

it("item menu: folded sheet 200 wide, cut 10, hard shadow; title in BodyBold; rows 24 in the spec's order", function()
	local ns = setup()
	local C = ns.Style.C
	ns.ShowItemMenu(CLOTH)
	local menu = CraftWiseItemMenu
	menu.options = ns.ItemMenuOptions
	eq(menu.width, 200)
	eq(menu.sheet.cut, 10); assert(menu.sheet.shadow, "hard shadow")
	eq(menu.sheet.fill, C.sheet); eq(menu.sheet.flap, C.flap)
	eq(menu.title.text, "Bolt of Test Cloth")
	eq(menu.title.fontObject, ns.Style.Fonts.BodyBold)
	eq(visible(menu), "keep,junk,auction,normal,where,history,recipes")
	eq(menu.buttons.keep.height, 24)
	eq(menu.buttons.keep.lastPoint[5], -28, "8 padding + the 20 unit title")
	eq(menu.buttons.junk.lastPoint[5], -52)
	eq(menu.buttons.where.lastPoint[5], -28 - 4 * 24 - 13, "a 1 unit rule with 6 either side before Where to buy")
	eq(menu.rule.lastPoint[5], -28 - 4 * 24 - 6)
	eq(menu.height, 28 + 7 * 24 + 13 + 8, "8 padding at the bottom")
	eq(menu.buttons.quest.shown, false, "no quest line for other items")
end)

it("item menu: the current mark has the nokta and C.selected behind it", function()
	local ns = setup()
	local C = ns.Style.C
	ns.SetItemState(CLOTH, "auction")
	ns.ShowItemMenu(CLOTH)
	local menu = CraftWiseItemMenu
	local ah = menu.buttons.auction
	eq(ah.current, true)
	eq(ah.bg.shown, true); eq(ah.bg.vertexColor[1], C.selected[1])
	eq(ah.label.fontObject, ns.Style.Fonts.BodyBold)
	eq(menu.buttons.normal.bg.shown, false)
	eq(menu.buttons.normal.label.fontObject, ns.Style.Fonts.Body)
	eq(menu.nokta.lastPoint[2], ah, "the nokta sits on the current row")
	eq(menu.nokta.lastPoint[4], 16, "in the 8 unit slot after the 12 padding")
	eq(menu.nokta.texture, ns.Style.Media.nokta)
	-- hover lights a row and shows its note in the inverse tooltip
	local keep = menu.buttons.keep
	keep.scripts.OnEnter(keep)
	eq(keep.bg.shown, true)
	eq(CraftWiseInverseTip.title.text, "Keep")
	keep.scripts.OnLeave(keep)
	eq(keep.bg.shown, false); eq(CraftWiseInverseTip.shown, false)
	-- a choice sets the mark and closes the menu
	keep.scripts.OnClick(keep)
	eq(ns.db.keep[CLOTH], true); eq(ns.db.sellAH[CLOTH], nil)
	eq(menu.shown, false)
end)

it("item menu: quest items show \"Quest items can't be sold\" in place of Junk and Sell on AH", function()
	local ns = setup()
	local C = ns.Style.C
	ns.ShowItemMenu(QUEST)
	local menu = CraftWiseItemMenu
	menu.options = ns.ItemMenuOptions
	eq(visible(menu), "keep,quest,normal,where,history,recipes")
	local q = menu.buttons.quest
	eq(q.label.text, "Quest items can't be sold")
	eq(q.label.textColor[1], C.text3[1])
	eq(q.scripts.OnClick, nil, "the quest line is not a choice")
	eq(menu.buttons.quest.lastPoint[5], -52, "where Junk would be")
	eq(menu.height, 28 + 6 * 24 + 13 + 8)
	eq(menu.buttons.keep.current, true, "quest items count as kept")
	ns.ShowItemMenu(CLOTH)
	eq(menu.buttons.quest.shown, false); eq(menu.buttons.junk.shown, true)
end)

it("item menu opens at the cursor, also when a row asked for it, and closes on a click elsewhere and with Escape", function()
	local ns, stub = setup()
	ns.ShowItemMenu(CLOTH, UIParent)
	local p = CraftWiseItemMenu.lastPoint
	eq(p[1], "TOPLEFT"); eq(p[2], UIParent); eq(p[3], "BOTTOMLEFT")
	eq(p[4], 150 + 8); eq(p[5], 100 + 8)
	local found = false
	for _, name in ipairs(UISpecialFrames) do found = found or name == "CraftWiseItemMenu" end
	assert(found, "Escape closes it")
	CraftWiseItemMenu.IsMouseOver = function() return false end
	stub.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
	eq(CraftWiseItemMenu.shown, false)
end)

it("item menu: Where to buy and Price history open Look up › Items when it exists, else the Records views", function()
	local ns = setup()
	local calls = {}
	ns.ShowWhereToBuy = function(id) calls[#calls + 1] = "where " .. id end
	ns.ShowMarketPrices = function(id) calls[#calls + 1] = "market " .. id end
	local menu
	for _, key in ipairs({ "where", "history" }) do
		ns.ShowItemMenu(CLOTH)
		menu = CraftWiseItemMenu
		menu.buttons[key].scripts.OnClick(menu.buttons[key])
	end
	eq(table.concat(calls, ","), "where " .. CLOTH .. ",market " .. CLOTH)
	ns.ShowItemLookup = function(id, focus) calls[#calls + 1] = "lookup " .. id .. " " .. focus end
	for _, key in ipairs({ "where", "history" }) do
		ns.ShowItemMenu(CLOTH)
		menu.buttons[key].scripts.OnClick(menu.buttons[key])
	end
	eq(calls[3], "lookup " .. CLOTH .. " where"); eq(calls[4], "lookup " .. CLOTH .. " history")
	eq(menu.shown, false)
end)

it("minimap button: 34 round, the client's ring, the W key at 20 inside", function()
	local ns = setup()
	local btn = CraftWiseMinimapButton
	eq(btn.width, 34); eq(btn.height, 34)
	eq(btn.icon.texture, ns.Style.Media.keyW)
	eq(btn.icon.width, 20); eq(btn.icon.height, 20)
	eq(btn.border.texture, "Interface\\Minimap\\MiniMap-TrackingBorder")
	local ring = btn.border.width
	assert(math.abs(ring - 53 * 34 / 31) < 1e-9, "ring art scaled with the button: " .. ring)
	eq(btn.icon.lastPoint[1], "CENTER", "centred in the ring")
end)

it("minimap button: click opens CraftWise, right-click the farm tracker, Shift-click docks once #161 exists", function()
	local ns = setup()
	local opened, docked = 0, 0
	eq(ns.ToggleDock, nil, "no docked layout registered yet (#161)")
	ns.ToggleMainWindow = function() opened = opened + 1 end
	eq(ns.MinimapClick("LeftButton", false), "open")
	eq(ns.MinimapClick("LeftButton", true), "open", "no docked layout yet: Shift-click opens too")
	eq(opened, 2)
	eq(ns.MinimapClick("RightButton", false), "farm")
	eq(ns.FarmFrame.IsShown(), true)
	ns.MinimapClick("RightButton", false)
	eq(ns.FarmFrame.IsShown(), false, "right-click again hides it")
	-- the docked layout (#161) plugs in
	ns.ToggleDock = function() docked = docked + 1 end
	eq(ns.MinimapClick("LeftButton", true), "dock")
	eq(docked, 1)
	eq(ns.MinimapClick("LeftButton", false), "open")
	eq(opened, 3)
	IsShiftKeyDown = function() return true end
	CraftWiseMinimapButton.scripts.OnClick(CraftWiseMinimapButton, "LeftButton")
	eq(docked, 2, "the button reads Shift from the client")
end)

it("minimap button: hover shows the inverse tooltip with one line per action", function()
	local ns = setup()
	local btn = CraftWiseMinimapButton
	btn.scripts.OnEnter(btn)
	local tip = CraftWiseInverseTip
	eq(tip.shown, true); eq(tip.owner, btn)
	eq(tip.title.text, "CraftWise")
	eq(tip.body.text, "Click: open\nRight-click: farm tracker\nDrag: move")
	eq(tip.sheet.fill, ns.Style.C.text, "inverse: light sheet")
	btn.scripts.OnLeave(btn)
	eq(tip.shown, false)
	ns.ToggleDock = function() end
	btn.scripts.OnEnter(btn)
	eq(tip.body.text, "Click: open\nRight-click: farm tracker\nShift-click: dock / undock\nDrag: move")
	btn.scripts.OnDragStart(btn)
	eq(tip.shown, false, "dragging hides it")
end)

it("addon compartment opens the main window (#153); the profit window only without it", function()
	local ns = setup()
	CraftWise_OnAddonCompartmentClick("CraftWise", "LeftButton")
	eq(CraftWiseMainFrame:IsShown(), true, "the main window")
	CraftWise_OnAddonCompartmentClick("CraftWise", "LeftButton")
	eq(CraftWiseMainFrame:IsShown(), false, "toggles")
	local which
	ns.ToggleProfitFrame = function() which = "profit" end
	ns.ToggleMainWindow = nil
	CraftWise_OnAddonCompartmentClick("CraftWise", "LeftButton")
	eq(which, "profit")
end)

it("the TOC icon is the W key (#166), the compartment function is named there", function()
	local icon, func
	for line in io.lines("CraftWise/CraftWise.toc") do
		icon = icon or line:match("^## IconTexture:%s*(.-)%s*$")
		func = func or line:match("^## AddonCompartmentFunc:%s*(.-)%s*$")
	end
	eq(icon, "Interface\\AddOns\\CraftWise\\Media\\cw-key-w")
	eq(func, "CraftWise_OnAddonCompartmentClick")
	local f = assert(io.open("CraftWise/Media/cw-key-w.tga", "rb"), "the texture the TOC names is bundled")
	f:close()
end)
