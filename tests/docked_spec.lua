-- Docked layout of the main window (#161; spec in #150 "Main window shell", Docked column, "Mouse and
-- keys", Settings › Look; board "Docked layout, on your screen"): the two layouts, swapping in place both
-- ways from the dock button, the minimap's Shift-click and Settings, the left and right anchors and the
-- slide, the docked header, every page drawn docked (two-line rows, stacked hero cards, page tools in the
-- list header) and the saved layout. Invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"
local PROF = 165
local HIDE, THREAD, BELT, GLOVES = 990001, 990002, 990101, 990102
local R_BELT, R_GLOVES = 990201, 990202
local LINEN, SWORD, GREY = 990100, 990200, 990400

local function Seed(itemID, typ)
	local db = CraftWiseMarketDB
	local today = math.floor(NOW / DAY)
	db.items[itemID] = db.items[itemID] or {}
	db.items[itemID][HORDE] = { raw = { { t = NOW, total = 50, tiers = { typ, 50 } } },
		days = { [today] = { lo = typ, typ = typ, hi = typ, n = 1 }, [today - 1] = { lo = typ, typ = typ, hi = typ, n = 1 } },
		last = { t = NOW, min = typ, qty = 50 } }
	db.houses[HORDE] = db.houses[HORDE] or { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH", cut = { samples = 0 } }
	db.scans[HORDE] = { { t = NOW, kind = "search", items = 1, source = "ui" } }
end

-- An invented profession with two known recipes and priced reagents, and a few bag items.
local function Load(opts)
	opts = opts or {}
	local ns, stub = LoadAddon(opts.addon)
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player = "Testperson"
	stub.money = 90000
	if opts.data ~= false then
		local function Recipe(name, difficulty, reagents, out)
			local list = {}
			for _, r in ipairs(reagents) do list[#list + 1] = { r[1], r[2] } end
			return { info = { name = name, learned = true, relativeDifficulty = difficulty }, schematic = stub.Schematic(list, out) }
		end
		stub.items[HIDE] = { name = "Testhide" }
		stub.items[THREAD] = { name = "Testthread" }
		stub.items[BELT] = { name = "Test Belt", sellPrice = 30 }
		stub.items[GLOVES] = { name = "Test Gloves", sellPrice = 25 }
		stub.profession = { id = PROF, name = "Testworking", skill = 100, max = 150, recipes = {
			[R_BELT] = Recipe("Test Belt", 1, { { HIDE, 2 }, { THREAD, 1 } }, BELT),
			[R_GLOVES] = Recipe("Test Gloves", 2, { { HIDE, 4 } }, GLOVES),
		} }
		stub.Fire("TRADE_SKILL_SHOW")
		ns.db.vendor[THREAD] = 20
		Seed(HIDE, 10); Seed(BELT, 200); Seed(GLOVES, 20)
		stub.items[LINEN] = { name = "Test Cloth", sellPrice = 13 }
		stub.items[SWORD] = { name = "Test Sword", sellPrice = 500 }
		stub.items[GREY] = { name = "Test Scrap", sellPrice = 7 }
		stub.itemClass[SWORD] = 2
		stub.bags[0] = {
			{ itemID = LINEN, stackCount = 20, quality = 1 },
			{ itemID = SWORD, stackCount = 1, quality = 2 },
			{ itemID = GREY, stackCount = 3, quality = 0 },
		}
		stub.ah[LINEN], stub.ah[SWORD] = 50, 400
		ns.ToggleJunk(GREY)
	end
	return ns, stub, ns.Main
end

-- Runs the running tweens to their end (the slide, the nokta).
local function Settle(ns)
	local d = ns.Style.TweenDriver
	for _ = 1, 3 do
		if d.scripts.OnUpdate then d.scripts.OnUpdate(d, 1) end
	end
end

local function Point(frame, i)
	return frame.points[i or 1]
end

----------------------------------------------------------------------------------------------------
-- Layouts, swapping, saving
----------------------------------------------------------------------------------------------------

it("Docked: two layouts registered after Window; fresh install opens as Window; the layout is saved", function()
	local ns, _, M = Load({ data = false })
	eq(M.layoutOrder[1], "window"); eq(M.layoutOrder[2], "dockLeft"); eq(M.layoutOrder[3], "dockRight")
	eq(M.layouts.dockLeft.label, "Docked left"); eq(M.layouts.dockRight.label, "Docked right")
	eq(M.layouts.dockLeft.docked, true); eq(M.layouts.dockLeft.metrics.width, 380)
	eq(M.UI().layout, "window", "fresh install: Window (Veli, 12 Nov)")
	eq(ns.ToggleDock, M.ToggleDock)
	M.Open()
	eq(M.Frame().width, 880)
	M.SetLayout("dockRight")
	eq(ns.db.settings.ui.layout, "dockRight", "saved in db.settings.ui")
	eq(ns.db.settings.ui.lastDocked, "dockRight")
	-- a reload with the saved layout opens docked
	local saved = CraftWiseDB
	local ns2 = LoadAddon({ savedDB = saved })
	local M2 = ns2.Main
	eq(M2.LayoutKey(), "dockRight")
	M2.Open()
	eq(M2.Frame().width, 380); eq(M2.shown.layout, "dockRight")
end)

it("Docked: the dock button swaps in place both ways; Docked left until a side was used (provisional Q5)", function()
	local ns, _, M = Load({ data = false })
	M.Open()
	local f = M.Frame()
	eq(f.head.dock.shown, true)
	eq(f.head.dock.icon.texture, ns.Style.Media.dock)
	f.head.dock.scripts.OnClick(f.head.dock)
	eq(M.LayoutKey(), "dockLeft", "no side used yet: Docked left")
	eq(f.width, 380); eq(f:IsShown(), true, "in place, no reload")
	eq(f.head.dock.icon.texture, ns.Style.Media.undock, "undock icon (board)")
	eq(f.head.dock.cwTip, "Undock to a window")
	f.head.dock.scripts.OnClick(f.head.dock)
	eq(M.LayoutKey(), "window"); eq(f.width, 880)
	eq(f.head.dock.cwTip, "Dock to screen edge")
	M.SetLayout("dockRight"); M.SetLayout("window")
	f.head.dock.scripts.OnClick(f.head.dock)
	eq(M.LayoutKey(), "dockRight", "the side used last")
end)

it("Docked: Shift-click on the minimap docks and undocks, and opens a closed window", function()
	local ns, _, M = Load({ data = false })
	eq(ns.MinimapClick("LeftButton", true), "dock")
	eq(M.LayoutKey(), "dockLeft")
	eq(M.Frame():IsShown(), true, "a closed window opens where it docked")
	eq(ns.MinimapClick("LeftButton", true), "dock")
	eq(M.LayoutKey(), "window"); eq(M.Frame():IsShown(), true)
	eq(M.Frame().width, 880)
end)

it("Docked: Settings › Look › Layout swaps in place, from the window and from the docked Settings page", function()
	local _, _, M = Load({ data = false })
	M.Open("settings")
	local function Seg(row, i)
		local b = row.holder.control.buttons[i]
		b.scripts.OnClick(b)
	end
	Seg(M.Settings.RowOf("look", "layout"), 3)
	eq(M.LayoutKey(), "dockRight"); eq(M.shown.layout, "dockRight"); eq(M.shown.page, "settings")
	local row = M.Settings.DockedRowOf("look", "layout")
	assert(row, "the docked Settings list is built")
	eq(row.holder.control.selected, 3)
	eq(row.holder.control.stretched, 344, "provisional Q2: wide controls take the row")
	Seg(row, 2)
	eq(M.LayoutKey(), "dockLeft")
	Seg(M.Settings.DockedRowOf("look", "layout"), 1)
	eq(M.LayoutKey(), "window"); eq(M.Frame().width, 880)
	eq(M.Settings.body.dock.scroll.shown, false, "the window draws its own Settings again")
	eq(M.Settings.body.nav.shown, true)
end)

----------------------------------------------------------------------------------------------------
-- Anchors and motion
----------------------------------------------------------------------------------------------------

it("Docked: left and right anchors, 20 from the edge, top and bottom 20; the sheet slides in (200 ms)", function()
	local ns, _, M = Load({ data = false })
	M.Open()
	local f = M.Frame()
	M.SetLayout("dockLeft")
	-- the swap starts the slide: out of the screen at its edge
	local p = Point(f, 1)
	eq(p[1], "TOPLEFT"); eq(p[2], UIParent); eq(p[3], "TOPLEFT")
	eq(p[4], 20 - 400, "starts out of the screen"); eq(p[5], -20)
	Settle(ns)
	p, q = Point(f, 1), Point(f, 2)
	eq(p[1], "TOPLEFT"); eq(p[4], 20); eq(p[5], -20)
	eq(q[1], "BOTTOMLEFT"); eq(q[3], "BOTTOMLEFT"); eq(q[4], 20); eq(q[5], 20)
	eq(#f.points, 2, "two anchors: the height is the screen's less 40")
	eq(f.width, 380)
	M.SetLayout("dockRight")
	eq(Point(f, 1)[4], -20 + 400, "from the right edge")
	Settle(ns)
	p, q = Point(f, 1), Point(f, 2)
	eq(p[1], "TOPRIGHT"); eq(p[3], "TOPRIGHT"); eq(p[4], -20); eq(p[5], -20)
	eq(q[1], "BOTTOMRIGHT"); eq(q[4], -20); eq(q[5], 20)
	eq(f.movable, false, "docked: not dragged")
	-- a scale change places it, no slide
	M.UI().scale = 0.9
	M.ApplyLayout()
	eq(Point(f, 1)[4], -20, "Settings › Look › Scale: no slide")
	-- opening it docked slides it in too
	f:Hide()
	f:Show()
	eq(Point(f, 1)[4], 380)
	Settle(ns)
	eq(Point(f, 1)[4], -20)
	-- and the window goes back where it was
	M.SetLayout("window")
	p = Point(f, 1)
	eq(p[1], "CENTER"); eq(p[4], 0); eq(p[5], 40); eq(f.movable, true)
	eq(f.width, 880); eq(f.height, 600)
end)

it("Docked: the slide is 200 ms with the kit's hop curve and only moves the sheet", function()
	local ns, _, M = Load({ data = false })
	M.Open()
	local f = M.Frame()
	M.SetLayout("dockLeft")
	local d = ns.Style.TweenDriver
	d.scripts.OnUpdate(d, 0.1)
	local mid = Point(f, 1)[4]
	assert(mid > -380 and mid < 20, "half way: between out and in, got " .. tostring(mid))
	d.scripts.OnUpdate(d, 0.1)
	eq(Point(f, 1)[4], 20, "in after 200 ms")
	eq(f.alpha, nil, "nothing fades")
end)

----------------------------------------------------------------------------------------------------
-- Header, tabs, sub bar
----------------------------------------------------------------------------------------------------

it("Docked: header 64 (W icon 34, title and AH status stacked at x 128), tabs on their own row, sub bar 40", function()
	local ns, _, M = Load()
	M.UI().profession = PROF
	M.Open("craft")
	M.SetLayout("dockLeft")
	local f = M.Frame()
	eq(f.head.height, 64)
	eq(f.head.art.texture, ns.Style.Media.headerNarrow)
	eq(f.head.key.width, 34); eq(Point(f.head.key)[4], 16); eq(Point(f.head.key)[5], -14)
	eq(Point(f.head.brand)[4], 128); eq(Point(f.head.brand)[5], -13)
	eq(f.head.brand.textColor[1], ns.Style.C.text[1], "the title on the dark plane")
	eq(Point(f.head.status)[2], f.head.brand, "AH status under the title")
	eq(f.head.status.text ~= nil and f.head.status.text ~= "", true)
	eq(Point(f.head.close)[4], -28); eq(f.head.close.width, 22)
	eq(Point(f.head.gear)[2], f.head.dock, "gear, undock, close")
	-- tabs from x 18, gap 20 (the stub's strings are 80 wide), on a row of their own under the header
	for i, tab in ipairs(f.head.tabs) do
		eq(Point(tab)[2], f); eq(Point(tab)[4], 18 + (i - 1) * (80 + 20), "tab " .. i); eq(Point(tab)[5], -(64 + 14))
	end
	eq(f.tabRule.shown, true)
	eq(Point(f.sub)[5], -(64 + 40), "sub bar under the tab row"); eq(f.sub.height, 40)
	eq(f.sub.buttons[1].points[1][4], 18, "padding 18")
	-- back to the window: the window's header
	M.SetLayout("window")
	eq(f.head.height, 56); eq(f.head.key.width, 30)
	eq(Point(f.head.tabs[1])[2], f.head); eq(Point(f.head.tabs[1])[4], 198)
	eq(f.tabRule.shown, false)
	eq(Point(f.sub)[5], -56); eq(f.sub.height, 46)
	eq(f.head.art.texture, ns.Style.Media.headerWide)
end)

----------------------------------------------------------------------------------------------------
-- List pages: tools in the list header, stacked hero, two-line rows
----------------------------------------------------------------------------------------------------

it("Docked Craft (board): stacked hero, page tools in the list header, rows 44 in two lines, footer 28", function()
	local ns, _, M = Load()
	M.UI().profession = PROF
	M.SetLayout("dockLeft")
	M.Open("craft")
	local f = M.Frame()
	eq(M.shown.state, "list"); eq(M.shown.layout, "dockLeft")
	-- hero: label, then name left and figure right on one line, the rail under
	eq(f.hero.label.text, "Best craft right now")
	eq(f.hero.name.text, "Test Belt")
	eq(Point(f.hero.figure)[1], "TOPRIGHT"); eq(Point(f.hero.figure)[5], Point(f.hero.name)[5] + 2, "one line")
	eq(Point(f.hero.middle)[5] < Point(f.hero.name)[5], true, "the rail under the name")
	eq(Point(f.hero)[4], 18, "margin 18")
	-- the page's tools (profession, filter) moved from the sub bar into the list header
	local tools = M.SlotsOf("craft").tools
	eq(Point(tools)[2], f.toolsRow); eq(f.toolsRow.shown, true); eq(f.toolsRow.height, 32)
	eq(f.listBar.title.text, "2 recipes")
	eq(Point(f.listBar.note)[2], f.listBar.title, "the note under the title")
	-- the docked list, two-line rows 44
	local list = M.ListOf("craft")
	eq(list.docked, true); eq(list.shown, true)
	eq(M.SlotsOf("craft").list, nil, "the window's list is built when the window first shows it")
	eq(list.rowHeight, 44)
	local row = list.box.frames[1]
	eq(row.extent, 44)
	local d = row.dk
	eq(d.name.text, "Test Belt"); eq(d.name.shown, true)
	eq(Point(d.name)[1], "TOPLEFT"); eq(Point(d.name)[4], 18 + 22 + 10)
	eq(Point(d.result)[1], "TOPRIGHT"); eq(Point(d.result)[4], -18)
	assert(tostring(d.result.text):find("^%+"), "profit with its sign: " .. tostring(d.result.text))
	assert(tostring(d.sub.text):find("→", 1, true) or tostring(d.sub.text):find("|T", 1, true), "cost → sells under the result")
	eq(Point(d.sub)[5] < Point(d.result)[5], true, "the sub-figure under the result")
	local rail = row.rails.dock
	eq(rail.shown, true); eq(Point(rail)[5] < Point(d.name)[5], true, "the rail under the name")
	eq(rail.width, 380 - 50 - 18 - 132 - 10)
	eq(f.foot.height, 28)
	-- a click opens the row in place: the card 18 from both edges, reagents two per line
	row.scripts.OnClick(row, "LeftButton")
	local opened = list.box.frames[2]
	eq(opened.elementData.open, true)
	eq(Point(opened.card)[4], 18); eq(opened.card.points[2][4], -18)
	eq(M.Make.PerLine(M.Context(M.Page("craft"))), 2)
	eq(opened.content.history.points[1][1], "TOPLEFT", "Price history under the reagents")
	-- swapping keeps the opened row open in the window
	M.SetLayout("window")
	eq(M.ListOf("craft").openKey, R_BELT)
	eq(M.ListOf("craft").docked, false)
end)

it("Docked Learn and Level up draw: name over rail, result and sub; the Level up note joins the list note", function()
	local ns, _, M = Load()
	M.UI().profession = PROF
	ns.db.settings.includeUnlearned = true
	M.SetLayout("dockRight")
	M.Open("learn")
	eq(M.shown.state, "list")
	M.ShowPage("level")
	eq(M.shown.state, "list")
	local f = M.Frame()
	assert(f.listBar.note.text:find("Sale: AH after cut", 1, true), "the sale note in the list note")
	eq(M.SlotsOf("level").listTools.note.shown, false)
	local row = M.ListOf("level").box.frames[1]
	eq(row.dk.name.shown, true)
	eq(row.dk.sub.text ~= nil, true, "the chance under the result")
	if f.hero.name.text ~= M.DASH then
		eq(f.hero.middle.height, 42, "the chance bar's room")
	end
end)

it("Docked Bags: group headers, the mark as a line tag, the hero stacked (total, bar, one line per part)", function()
	local ns, stub, M = Load({ addon = { auctionator = true } })
	ns.db.marks = ns.db.marks or {}
	M.SetLayout("dockLeft")
	M.Open("bags")
	eq(M.shown.state, "list")
	local list = M.ListOf("bags")
	local group, item
	for _, fr in ipairs(list.box.frames) do
		if fr.elementData.row.group and not group then group = fr end
		if not fr.elementData.row.group and not item then item = fr end
	end
	assert(group and item, "a group row and an item row")
	eq(group.dk.title.shown, true); eq(group.dk.rule.shown, true); eq(group.dk.name.shown, false)
	eq(group.hair.shown, false)
	eq(item.dk.name.shown, true)
	assert(tostring(item.dk.note.text):find("×", 1, true), "count in the note line")
	local f = M.Frame()
	eq(f.hero.label.text, "What your bags would bring")
	local slot = M.SlotsOf("bags").dhero
	eq(slot.shown, true); eq(M.SlotsOf("bags").hero, nil, "the window's hero slot was never built")
	eq(#slot.cwStat, 3, "one line per part")
	eq(slot.cwStat[1].square.shown, true)
	eq(f.hero.middle.height, M.Page("bags").P.DOCKED_HERO_MIDDLE)
	-- the Bags chips in the list header
	eq(Point(M.SlotsOf("bags").tools)[2], f.toolsRow)
end)

it("Docked mappers: Auctions, Ledger, Farm, Fishing, Crates and Upgrades rows in two lines", function()
	local ns, _, M = Load({ data = false })
	local ctx = { metrics = M.DOCKED_METRICS, railMax = 100 }
	-- Auctions: item over qty, status and when (orange diamond while listed), You get over the buyout
	local a = M.Page("auctions").DockedRow({ key = "id1", itemID = SWORD, name = "Test Sword", quality = 2, qty = 3,
		status = "listed", statusText = "Listed", statusColor = "text", live = true, when = "ends in 11 h",
		buyout = 1000, youGet = 950, depositKnown = true }, ctx)
	eq(a.name, "Test Sword"); eq(a.live, true)
	assert(a.note:find("×3", 1, true) and a.note:find("ends in 11 h", 1, true), a.note)
	assert(tostring(a.result):find("|T", 1, true) or tostring(a.result):find("50", 1, true))
	-- Ledger: today with the nokta, the change rail zero-centred
	local P = M.Page("ledger").P
	local l = P.DockedRow({ key = "d", day = "2026-11-12", name = "Today", today = true, start = 1000, spent = 200,
		received = 500, change = 300 }, ctx)
	eq(l.here, true); eq(l.rail.zeroAt, P.ZERO_AT); eq(l.rail.value, 300); eq(l.rail.max, 100)
	assert(l.result:find("^%+"), l.result)
	local li = P.DockedRow({ key = 1, itemID = LINEN, name = "Test Cloth", where = "Vendor A", bought = 1, spent = 10,
		sold = 0, received = 0, net = -10 }, ctx)
	eq(li.resultColor, "danger"); eq(li.note, "Vendor A")
	-- Farm: start and zone over the gold per hour rail
	local fr = ns.GatherFarm.DockedRow({ key = 1, started = "Mon 14:02", zone = "Testzone", time = "1:00:00",
		total = 5000, gph = 5000, railMax = 5000 })
	eq(fr.rail.value, 5000); eq(fr.rail.max, 5000)
	assert(fr.name:find("Testzone", 1, true) and fr.name:find("Mon 14:02", 1, true), fr.name)
	-- Fishing: point and range on the rail
	local fs = M.Page("fishing").DockedRow({ key = "z", name = "Testlake", own = 3, ownLow = true, hasRef = true, ownMin = 20,
		gph = 900, gphHigh = 1200, perCatch = 30, railMax = 1200, n = 3, source = "ref" }, ctx)
	eq(fs.rail.point, true); eq(fs.rail.high, 1200); eq(fs.name, "Testlake")
	-- Crates: cost per Favor rail, the Favor note under the result
	local cr = M.Page("crates").DockedRow({ key = 7, name = "Test Crate", note = "10 Favor · measured", perFavor = 40,
		railMax = 80, held = 1, crate = 100 })
	eq(cr.rail.value, 40); eq(cr.sub, "10 Favor · measured")
	-- Upgrades: group header, an empty line, an item over its gain
	local up = M.Page("upgrades")
	eq(up.DockedRow({ header = true, title = "You can craft", note = "Testworking 100" }).group.title, "You can craft")
	eq(up.DockedRow({ emptyLine = "Nothing to show." }).line, "Nothing to show.")
	local u = up.DockedRow({ key = 1, name = "Test Boots", quality = 2, how = "known", slot = "Feet",
		gainText = "+3 Agi", costText = "1g", costComplete = true, reagents = {} })
	eq(u.result, "1g"); eq(u.sub, "Feet"); assert(u.note:find("+3 Agi", 1, true), u.note)
end)

it("Docked: a page's list without DockedRow draws from its columns (name, rail, result, sub, note)", function()
	local _, _, M = Load({ data = false })
	local v = M.DockedView({}, { key = "a", name = "Alpha", value = 30, extra = "note text", itemID = LINEN }, { railMax = 30 }, {
		{ key = "icon", icon = true, width = 22 },
		{ key = "name", label = "Item" },
		{ key = "extra", label = "Extra", width = 80 },
		{ key = "rail", rail = function(r) return { value = r.value, max = 30 } end },
		{ key = "sub", width = 60, align = "RIGHT", text = function() return "sub" end },
		{ key = "value", width = 90, align = "RIGHT", text = function(r) return tostring(r.value) end,
			tip = function() return { "why" } end },
	})
	eq(v.name, "Alpha"); eq(v.result, "30"); eq(v.sub, "sub"); eq(v.note, "note text")
	eq(v.rail.value, 30); eq(v.tip[1], "why")
end)

----------------------------------------------------------------------------------------------------
-- Every page draws docked
----------------------------------------------------------------------------------------------------

it("Docked: every page of every section and Settings draws without an error, both sides", function()
	local ns, _, M = Load({ addon = { auctionator = true } })
	M.UI().profession = PROF
	for _, side in ipairs({ "dockLeft", "dockRight" }) do
		M.SetLayout(side)
		M.Open()
		for _, section in ipairs(M.SECTIONS) do
			for _, page in ipairs(M.SectionPages(section.key)) do
				M.state.vendorOnly[page.key] = true
				M.ShowPage(page.key)
				eq(M.shown.page, page.key)
				eq(M.shown.layout, side)
				assert(M.shown.state ~= "error", page.key .. " docked: " .. tostring(M.Frame().lastError))
				if page.kind == "list" and M.shown.state == "list" then
					eq(M.ListOf(page.key).docked, true, page.key)
				end
			end
		end
		M.ToggleSettings()
		eq(M.shown.page, "settings")
		assert(M.shown.state ~= "error", "settings docked: " .. tostring(M.Frame().lastError))
		M.ToggleSettings()
	end
	-- and back in the window every page still draws
	M.SetLayout("window")
	for _, section in ipairs(M.SECTIONS) do
		for _, page in ipairs(M.SectionPages(section.key)) do
			M.ShowPage(page.key)
			assert(M.shown.state ~= "error", page.key .. " window: " .. tostring(M.Frame().lastError))
		end
	end
end)

it("Docked states: First run, No prices and Error fit the 380 sheet", function()
	local ns, _, M = Load({ data = false })
	M.SetLayout("dockLeft")
	ns.charDB.professions[990165] = { name = "Testcrafting", skill = 1, maxSkill = 75, recipes = {} }
	M.UI().profession = 990165
	M.Open("craft")
	eq(M.shown.state, "firstRun")
	local panel = M.Frame().panel
	eq(panel.fitWidth, 344); eq(panel.body.width, 344)
	eq(Point(panel.inner)[4], 18)
	eq(M.Frame().toolsRow.shown, true, "the profession dropdown stays reachable")
	eq(Point(M.SlotsOf("craft").tools)[2], M.Frame().toolsRow)
	eq(Point(panel)[5], -32, "the state under the tools")
	M.ShowError(M.Page("craft"), "invented failure")
	eq(panel.title.text, "Craft could not be built.")
	M.SetLayout("window")
	eq(panel.fitWidth, 420)
end)

----------------------------------------------------------------------------------------------------
-- Custom pages: Items (provisional Q1), Settings (Q2), Music (Q3); stacked cards (Q4)
----------------------------------------------------------------------------------------------------

it("Docked Items (provisional Q1): the list across the sheet; a click swaps to the card with Back in the sub bar", function()
	local ns, stub, M = Load()
	M.SetLayout("dockLeft")
	M.Open("items")
	eq(M.shown.page, "items")
	local Items = M.Items
	local body = M.SlotsOf("items").body
	eq(body.left.shown, true); eq(body.left.width, 380, "the list across the sheet")
	eq(body.card.shown, false)
	local tools = M.SlotsOf("items").tools
	eq(Items.searchBox.shown, true); eq(Items.searchBox.width, Items.DOCKED_SEARCH_WIDTH, "search in the sub bar")
	eq(tools.back.shown, false)
	eq(Point(tools)[2], M.Frame().sub.tools, "a custom page keeps its tools in the sub bar")
	-- a click on an item: the card across the sheet, Back in place of the search box
	Items.ClickRow({ itemID = BELT }, "LeftButton")
	eq(Items.state.dockedCard, true)
	eq(body.left.shown, false); eq(body.card.shown, true)
	eq(body.card.width, 380); eq(body.dscroll.shown, true)
	eq(tools.back.shown, true); eq(Items.searchBox.shown, false)
	eq(body.card.figs[3].points[1][5], -(66 + 52), "figures two by two")
	eq(body.card.where.points[1][2], body.card, "Where to buy under Used in")
	tools.back.scripts.OnClick(tools.back)
	eq(Items.state.dockedCard, false)
	eq(body.left.shown, true); eq(body.card.shown, false); eq(Items.searchBox.shown, true)
	-- the item menu's Price history opens the card
	ns.ShowItemLookup(GLOVES, "history")
	eq(body.card.shown, true)
	-- the window: list 300 and card side by side again
	M.SetLayout("window")
	eq(body.left.width, 300); eq(body.left.shown, true); eq(body.card.shown, true)
	eq(Point(body.card)[2], body); eq(Point(body.card)[4], 301)
	eq(tools.back.shown, false); eq(Items.searchBox.width, 300)
end)

it("Docked Settings (provisional Q2): one scrolling list, group headers, label over the control", function()
	local _, _, M = Load({ data = false })
	M.SetLayout("dockRight")
	M.Open("settings")
	local body = M.Settings.body
	local d = body.dock
	eq(d.scroll.shown, true); eq(body.nav.shown, false)
	eq(#d.groups, #M.Settings.Groups(), "every group in the one list")
	eq(d.groups[1].head.title.text, "Look"); eq(d.groups[1].head.rule.height, 2)
	local row = M.Settings.DockedRowOf("look", "layout")
	eq(Point(row.label)[1], "TOPLEFT")
	eq(Point(row.holder)[5] < Point(row.label)[5], true, "the control under its label")
	eq(row.holder.width, 344)
	-- groups follow one another down the list
	local prices = d.groups[2].head
	eq(Point(prices)[5] < Point(d.groups[1].head)[5], true)
	eq(d.scroll.contentHeight > 0, true)
	-- a check row still writes its setting
	local esc = M.Settings.DockedRowOf("look", "windows")
	local box = esc.holder.boxes[2]
	box.scripts.OnClick(box)
	eq(M.UI().escape, false)
	-- the mouse wheel scrolls
	d.scroll.maxScroll = 300
	d.scroll.scripts.OnMouseWheel(d.scroll, -1)
	eq(d.scroll.offset, M.Docked.WHEEL_STEP)
end)

it("Docked Music (provisional Q3): each profession row stacks Song, Video, Next cast, then volume", function()
	local ns, _, M = Load({ data = false })
	M.SetLayout("dockLeft")
	M.Open("music")
	eq(M.shown.page, "music")
	local rows = M.Music.lastRows
	local body = M.SlotsOf("music").body
	eq(body.dscroll.shown, true); eq(body.head.shown, false)
	local r = body.list.rows[1] -- Party: no Next cast
	eq(r.height, M.Music.DockedRowHeight(rows[1]))
	eq(r.dl.song.text, "Song"); eq(r.dl.volume.shown, true)
	eq(r.dl.mode, nil, "Party plays from the start")
	eq(r.song.width, 380 - 36 - M.Music.DOCKED_LABEL)
	eq(Point(r.video)[5] < Point(r.song)[5], true, "Video under Song")
	eq(Point(r.volume)[5] < Point(r.video)[5], true, "volume last")
	eq(#M.Music.DockedLines({ party = false }), 4)
	M.SetLayout("window")
	eq(body.head.shown, true); eq(r.height, M.Music.ROW_HEIGHT)
	eq(r.dl.song.shown, false)
end)

it("Docked heroes of several cards stack (provisional Q4): Auctions 3, Crates 2", function()
	local ns, _, M = Load({ data = false })
	local D = M.Docked
	eq(D.StackCardsHeight(3), 3 * D.CARD_HEIGHT + 2 * D.CARD_GAP)
	local slot = CreateFrame("Frame")
	local h = D.StackCards(slot, { { label = "On its way", figure = "1g" }, { label = "If all listed sell", figure = "2g" },
		{ label = "Returning", figure = "3", unit = "items" } })
	eq(h, D.StackCardsHeight(3))
	eq(slot.cwCards[2].points[1][5], -(D.CARD_HEIGHT + D.CARD_GAP), "one under the other")
	eq(slot.cwCards[3].unit.text, "items")
	-- the pages' docked heroes use it
	local cards = {}
	M.Page("auctions").DockedHero(nil, { cards = { { key = "way", label = "A", copper = 100 }, { key = "all", label = "B", copper = 200 },
		{ key = "back", label = "C", count = 1, unit = "item" } } }, { metrics = M.DOCKED_METRICS }, slot)
	eq(#slot.cwCards, 3); eq(slot.cwCards[3].figure.text, "1")
	local slot2 = CreateFrame("Frame")
	M.Page("crates").DockedHero(nil, { favor = "Merchant's Favor" }, {}, slot2)
	eq(#slot2.cwCards, 2); eq(slot2.cwCards[1].name.text, "None priced")
end)
