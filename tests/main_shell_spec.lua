-- Main window shell (#153, spec in #150: Main window shell, States, Where everything lands): sections,
-- page registry, saved db.settings.ui, the layout seam, the six states, the list and the bridges to the
-- old windows. Invented data only.
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"
local CRAFT_PROF = 990165 -- an invented crafting profession

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock or NOW end
	stub.clock = NOW
	stub.names.player = "Testperson"
	return ns, stub, ns.Main
end

local function Prof(ns, recipes)
	ns.charDB.professions[CRAFT_PROF] = { name = "Testcrafting", skill = 120, maxSkill = 150, recipes = recipes or {} }
end

-- A list page with invented rows; opts override fields.
local function TestPage(M, opts)
	local page = {
		key = "testlist", section = "lookup", label = "Test list", order = 9,
		columns = {
			{ key = "icon", icon = true, width = 22 },
			{ key = "name", label = "Item", sort = true },
			{ key = "value", label = "Value", width = 96, align = "RIGHT", sort = true,
				text = function(r) return r.value and tostring(r.value) or M.DASH end,
				tip = function(r) if not r.value then return { "Not listed in the last full scan" } end end },
		},
		sort = { key = "value", desc = true },
		Model = function()
			return {
				rows = {
					{ key = "a", name = "Alpha Thing", value = 30, itemID = 990001 },
					{ key = "b", name = "Beta Thing", value = 120, itemID = 990002 },
					{ key = "c", name = "Gamma Thing", value = nil },
				},
				hero = { label = "Best thing", name = "Beta Thing", sub = "invented", figure = "120" },
				listTitle = "3 things", listNote = "by value",
				footer = "Prices: invented", footerRight = "3 things",
			}
		end,
		Open = function(content, row) content.shownRow = row.key end,
		OpenHeight = function() return 40 end,
	}
	for k, v in pairs(opts or {}) do
		page[k] = v
	end
	return M.RegisterPage(page)
end

----------------------------------------------------------------------------------------------------
-- Registry and navigation
----------------------------------------------------------------------------------------------------

it("Main: five sections in the spec's order; every sub-page of #150 is a real page (the last bridges went with #154)", function()
	local _, _, M = Load()
	local labels = {}
	for _, s in ipairs(M.SECTIONS) do labels[#labels + 1] = s.label end
	eq(table.concat(labels, ","), "Make,Sell,Gather,Look up,Music")
	local want = { make = "Craft,Learn,Level up", sell = "Bags,Auctions,Ledger", gather = "Farm,Fishing,Crates",
		lookup = "Items,Upgrades", music = "Music" }
	for section, list in pairs(want) do
		local got = {}
		for _, p in ipairs(M.SectionPages(section)) do
			got[#got + 1] = p.label
			eq(p.bridge, nil, p.key .. " is a real page")
		end
		eq(table.concat(got, ","), list, section)
	end
	eq(M.Page("settings").section, nil, "settings is the gear's page, not a tab")
	eq(M.Page("settings").bridge, nil, "the Settings page (#157)")
end)

it("Main: a real page replaces its bridge (keeping its place); twice or in an unknown section fails", function()
	local _, _, M = Load()
	local key, section, order = "testbridge", "lookup", 3 -- a page that has not moved yet
	M.RegisterPage({ key = key, section = section, label = "Test", order = order, bridge = true, kind = "custom" })
	local page = M.RegisterPage({ key = key, section = section, label = "Test", Model = function() return {} end })
	eq(M.Page(key), page)
	eq(page.order, order, "keeps the bridge's order")
	eq(M.SectionPages(section)[order], page)
	assert(not pcall(M.RegisterPage, { key = key, section = section }), "a real page registered twice must fail")
	assert(not pcall(M.RegisterPage, { key = "craft", section = "make" }), "Make › Craft is a real page (#154)")
	assert(not pcall(M.RegisterPage, { key = "x", section = "nowhere" }), "unknown section must fail")
end)

it("Main: remembers section, sub-page, profession and layout in db.settings.ui; fresh install opens as Window", function()
	local ns, _, M = Load()
	local ui = M.UI()
	eq(ui.section, "make"); eq(ui.layout, "window"); eq(ui.escape, true); eq(ui.scale, 1)
	eq(M.CurrentPage().key, "craft", "first sub-page of Make")
	M.ShowPage("ledger")
	eq(M.CurrentSection(), "sell"); eq(M.CurrentPage().key, "ledger")
	M.SelectSection("gather")
	eq(M.CurrentPage().key, "farm")
	M.SelectSection("sell")
	eq(M.CurrentPage().key, "ledger", "a section opens on its last sub-page")
	Prof(ns, { [1] = { name = "x" } })
	M.SetProfession(CRAFT_PROF)
	ui.layout = "left" -- the docked layout, saved before #161 exists
	local saved = CraftWiseDB
	local ns2, _, M2 = Load({ savedDB = saved })
	ns2.charDB.professions[CRAFT_PROF] = { name = "Testcrafting", recipes = { [1] = { name = "x" } } }
	eq(M2.CurrentSection(), "sell"); eq(M2.CurrentPage().key, "ledger")
	eq(M2.Profession(), CRAFT_PROF)
	eq(M2.UI().layout, "left", "kept")
	eq(M2.LayoutKey(), "window", "used meanwhile")
end)

it("Main: the gear shows Settings and goes back to the section it came from", function()
	local _, _, M = Load()
	M.ShowPage("bags")
	M.Open()
	local f = M.Frame()
	f.head.gear.scripts.OnClick(f.head.gear)
	eq(M.CurrentSection(), "settings"); eq(M.shown.page, "settings")
	eq(f.head.gear.bg.shown, true, "gear filled while Settings shows")
	for _, tab in ipairs(f.head.tabs) do eq(tab.bar.shown, false, "no section tab active") end
	f.head.gear.scripts.OnClick(f.head.gear)
	eq(M.CurrentPage().key, "bags")
	eq(f.head.gear.bg.shown, false)
end)

it("Main: profession is the remembered one, else the first with recipes; gathering ones are left out", function()
	local ns, _, M = Load()
	ns.charDB.professions = {
		[990001] = { name = "Bcraft", recipes = {} },
		[990002] = { name = "Acraft", recipes = {} },
		[990003] = { name = "Ccraft", recipes = { [1] = {} } },
		[393] = { name = "Skinning", recipes = {} },
	}
	local ids = M.ProfessionIDs()
	eq(#ids, 3); eq(ids[1], 990002)
	eq(M.Profession(), 990003, "first with recipes")
	M.SetProfession(990001)
	eq(M.Profession(), 990001)
	M.UI().profession = 393
	eq(M.Profession(), 990003, "gathering is not a Make profession")
end)

----------------------------------------------------------------------------------------------------
-- The frame
----------------------------------------------------------------------------------------------------

it("Main: CraftWiseMainFrame, 880 x 600 at CENTER (0, 40), MEDIUM, toplevel, clamped, folded 22 with shadow", function()
	local ns, _, M = Load()
	eq(M.Open(), true)
	local f = CraftWiseMainFrame
	eq(f, M.Frame()); eq(f:IsShown(), true)
	eq(f.width, 880); eq(f.height, 600)
	local p = f.points[1]
	eq(p[1], "CENTER"); eq(p[3], "CENTER"); eq(p[4], 0); eq(p[5], 40)
	eq(f.sheet.cut, 22); assert(f.sheet.shadow, "hard shadow")
	eq(f.sheet.fill, ns.Style.C.sheet); eq(f.sheet.flap, ns.Style.C.flap)
	eq(f.head.height, 56)
	eq(f.head.key.width, 30); eq(f.head.key.points[1][4], 14, "W icon at x 14")
	eq(f.head.brand.text, "CraftWise")
	-- tabs from x 198 with a gap of 24 (the stub's strings are 80 wide)
	for i, tab in ipairs(f.head.tabs) do
		eq(tab.points[1][4], 198 + (i - 1) * (80 + 24), "tab " .. i)
	end
	eq(f.head.close.points[1][4], -30, "close 30 from the edge")
	eq(f.head.dock.shown, true, "the dock button (#161)")
	eq(f.sub.height, 46)
end)

it("Main: the toggle, the key binding, /craftwise and Escape", function()
	local _, _, M = Load()
	eq(BINDING_NAME_CRAFTWISE_MAIN, "Toggle CraftWise")
	local xml = io.open("CraftWise/Bindings.xml"):read("*a")
	assert(xml:find('name="CRAFTWISE_MAIN"', 1, true) and xml:find("CraftWise_MainToggle()", 1, true), "binding in Bindings.xml")
	assert(xml:find("CRAFTWISE_MAIN", 1, true) < xml:find("CRAFTWISE_FARM", 1, true), "beside the farm tracker's")
	CraftWise_MainToggle()
	eq(CraftWiseMainFrame:IsShown(), true)
	CraftWise_MainToggle()
	eq(CraftWiseMainFrame:IsShown(), false)
	SlashCmdList.CRAFTWISE("")
	eq(CraftWiseMainFrame:IsShown(), true, "/craftwise opens the main window")
	local listed = 0
	for _, name in ipairs(UISpecialFrames) do if name == "CraftWiseMainFrame" then listed = listed + 1 end end
	eq(listed, 1, "closes with Escape")
	M.UI().escape = false
	M.ApplyEscape()
	for _, name in ipairs(UISpecialFrames) do assert(name ~= "CraftWiseMainFrame", "Close with Escape off") end
	M.UI().escape = true
	M.ApplyEscape(); M.ApplyEscape()
	listed = 0
	for _, name in ipairs(UISpecialFrames) do if name == "CraftWiseMainFrame" then listed = listed + 1 end end
	eq(listed, 1, "listed once")
end)

it("Main: section tabs and sub-pages; the active one with the 3 unit bar, the nokta before the active sub-page", function()
	local ns, _, M = Load()
	M.Open()
	local f = M.Frame()
	f.head.tabs[2].scripts.OnClick(f.head.tabs[2])
	eq(M.CurrentSection(), "sell")
	eq(f.head.tabs[2].bar.shown, true); eq(f.head.tabs[2].bar.height, 3)
	eq(f.head.tabs[1].bar.shown, false)
	local tc = f.head.tabs[2].label.textColor
	eq(tc[1], ns.Style.C.text[1])
	eq(f.sub.buttons[1].label.text, "Bags")
	eq(f.sub.nokta.shown, true)
	eq(f.sub.nokta.points[1][2], f.sub.buttons[1], "nokta before the active sub-page")
	f.sub.buttons[3].scripts.OnClick(f.sub.buttons[3])
	eq(M.CurrentPage().key, "ledger")
	eq(f.sub.nokta.points[1][2], f.sub.buttons[3], "the nokta moved")
	eq(f.sub.buttons[1].points[1][4], 22, "padding 22")
	-- one sub-page: no sub bar (Music)
	M.SelectSection("music")
	eq(f.sub.shown, false)
end)

----------------------------------------------------------------------------------------------------
-- Layout seam
----------------------------------------------------------------------------------------------------

it("Main: layout seam: docked layouts register, the dock button and ns.ToggleDock swap in place", function()
	local ns, _, M = Load()
	eq(M.SetLayout("left"), false, "a layout nobody registered")
	M.Open()
	local applied = {}
	M.RegisterLayout("left", { label = "Test left", docked = true,
		metrics = setmetatable({ width = 380 }, { __index = M.WINDOW_METRICS }),
		Apply = function(frame, m) applied[#applied + 1] = m.width; frame:SetSize(m.width, 700) end })
	M.RegisterLayout("right", { label = "Test right", docked = true,
		metrics = setmetatable({ width = 380 }, { __index = M.WINDOW_METRICS }),
		Apply = function(frame, m) frame:SetSize(m.width, 700) end })
	M.UI().lastDocked = "left"
	eq(ns.ToggleDock, M.ToggleDock, "the minimap's Shift-click reaches the seam")
	eq(M.CanDock(), true)
	local f = M.Frame()
	M.Refresh()
	eq(f.head.dock.shown, true)
	f.head.dock.scripts.OnClick(f.head.dock)
	eq(M.LayoutKey(), "left"); eq(applied[1], 380); eq(f.width, 380)
	eq(M.UI().layout, "left", "saved")
	ns.ToggleDock()
	eq(M.LayoutKey(), "window"); eq(f.width, 880)
	M.SetLayout("right")
	ns.ToggleDock(); ns.ToggleDock()
	eq(M.LayoutKey(), "right", "docks to the side used last")
	eq(f:IsShown(), true, "no reload, the window stays")
end)

it("Main: a moved window reopens where it was; Lock position stops dragging", function()
	local _, _, M = Load()
	M.Open()
	local f = M.Frame()
	f.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 120, -80 end
	local moved = 0
	f.StartMoving = function() moved = moved + 1 end
	f.head.scripts.OnDragStart(f.head)
	f.head.scripts.OnDragStop(f.head)
	eq(moved, 1)
	eq(M.UI().pos[1], "TOPLEFT"); eq(M.UI().pos[3], 120); eq(M.UI().pos[4], -80)
	M.ApplyLayout()
	eq(f.points[1][1], "TOPLEFT"); eq(f.points[1][4], 120)
	M.UI().locked = true
	f.head.scripts.OnDragStart(f.head)
	eq(moved, 1, "locked")
end)

----------------------------------------------------------------------------------------------------
-- States
----------------------------------------------------------------------------------------------------

it("States: First run when the chosen profession has no recipes cached", function()
	local ns, _, M = Load()
	Prof(ns, {})
	M.ShowPage("craft") -- the real Make › Craft page (#154)
	M.Open()
	local f = M.Frame()
	eq(M.shown.state, "firstRun")
	eq(f.panel.shown, true)
	eq(f.panel.icon.shown, true, "the W key")
	eq(f.panel.title.text, "Open your Testcrafting window once.")
	eq(f.panel.body.text, "CraftWise reads your recipes from it. Profits appear here right after.")
	ns.charDB.professions[CRAFT_PROF].recipes[1] = { name = "x" }
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 3600, kind = "full" } }
	ns.Notify("RECIPES_CHANGED")
	eq(M.shown.state, "list", "recipes read: the page shows")
end)

it("States: No prices without an AH observation; Show vendor-only profits shows the page", function()
	local _, _, M = Load()
	TestPage(M, { prices = true })
	M.Open("testlist")
	local f = M.Frame()
	eq(M.shown.state, "noPrices")
	eq(f.panel.title.text, "No auction house visited yet.")
	eq(f.panel.body.text, "Open the Horde auction house and browse or run a scan. Until then, profits use vendor prices where an item has one.")
	eq(f.head.status.text, "Horde AH · no AH data")
	local b = f.panel.buttons[1]
	eq(b.label.text, "Show vendor-only profits")
	b.scripts.OnClick(b)
	eq(M.shown.state, "list")
	eq(M.Context(M.Page("testlist")).vendorOnly, true)
end)

it("States: Auctionator prices count as prices at the profit house; No prices only without either (#157)", function()
	local ns, stub, M = Load({ auctionator = true })
	TestPage(M, { prices = true })
	CraftWiseMarketDB.scope.items[990001] = true
	M.Open("testlist")
	local f = M.Frame()
	-- Auctionator loaded, but no price for anything of the scope: No prices
	eq(M.shown.state, "noPrices")
	eq(f.head.status.text, "Horde AH · no AH data")
	-- it gets a price: asked again after AUCTIONATOR_RECHECK seconds, then the page shows
	stub.ah[990001] = 250
	M.Refresh()
	eq(M.shown.state, "noPrices", "a no is kept for a few seconds")
	stub.clock = NOW + M.AUCTIONATOR_RECHECK
	M.Refresh()
	eq(M.shown.state, "list")
	eq(f.head.status.text, "Horde AH · Auctionator prices")
	local s = M.PriceStatus()
	eq(s.hasData, false); eq(s.auctionator, true); eq(s.hasPrices, true); eq(s.stale, false)
	-- a yes stays for the session
	stub.ah[990001] = nil
	M.Refresh()
	eq(M.shown.state, "list")
	-- CraftWise's own records win the header; Auctionator isn't asked then
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 3600, kind = "full" } }
	M.Refresh()
	eq(f.head.status.text, "Horde AH · " .. ns.Style.Hex("text2") .. "1 h|r ago")
	eq(M.PriceStatus().auctionator, false)
end)

it("States: an Auctionator price CraftWise read before counts; without Auctionator loaded it doesn't", function()
	local ns, stub, M = Load({ auctionator = true })
	TestPage(M, { prices = true })
	ns.Market.ExportAuctionator(990002, 300, 1)
	M.Open("testlist")
	eq(M.shown.state, "list", "Auctionator answered before")
	ns, stub, M = Load()
	TestPage(M, { prices = true })
	ns.Market.ExportAuctionator(990002, 300, 1)
	M.Open("testlist")
	eq(M.shown.state, "noPrices", "the export alone is no price: Auctionator isn't loaded")
	eq(M.AuctionatorHasPrices(), false)
end)

it("Header AH status: hover shows the scan summary per house (was Records › Market's summary line, #157)", function()
	local ns, stub, M = Load()
	TestPage(M, { prices = true })
	local db = CraftWiseMarketDB
	local BOOTY = "PvP|N:BootyBay"
	db.houses[HORDE] = { realm = "PvP", kind = "faction", faction = "Horde", label = "Horde AH" }
	db.houses[BOOTY] = { realm = "PvP", kind = "neutral", label = "Booty Bay" }
	db.scans[HORDE] = { { t = NOW - 2 * 3600, kind = "full", items = 3 }, { t = NOW - 600, kind = "search" } }
	db.scans[BOOTY] = { { t = NOW - 3 * DAY, kind = "browse" } }
	local today = math.floor(NOW / DAY)
	db.items[990001] = { [HORDE] = { raw = {}, days = { [today] = { lo = 10, typ = 10, hi = 10, n = 1 } }, last = { t = NOW - 600, min = 10, qty = 5 } },
		[BOOTY] = { raw = {}, days = {}, last = { t = NOW - 3 * DAY, min = 12, qty = 1 } } }
	db.items[990002] = { [HORDE] = { raw = {}, days = {}, last = { t = NOW - 600, min = 40, qty = 2 } } }
	db.auctionator.items[990003] = "1,1,1"
	M.Open("testlist")
	local f = M.Frame()
	local hit = f.head.statusHit
	eq(hit.shown, true, "the hover area shows with the status")
	hit.scripts.OnEnter(hit)
	local tip = CraftWiseInverseTip
	eq(tip.shown, true); eq(tip.owner, hit)
	eq(tip.title.text, "Auction houses")
	local lines = {}
	for line in (tip.body.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	eq(lines[1], "Horde AH (profit): full scan 2 h ago · 2 items, 1 with history", "faction house first")
	eq(lines[2], "Booty Bay: no full scan · 1 item, 0 with history")
	eq(lines[3], "Auctionator (house unknown): 1 item read")
	hit.scripts.OnLeave(hit)
	eq(tip.shown, false)
	-- nothing recorded yet: the line says what to do
	local title, empty = M.ScanSummary()
	eq(title, "Auction houses")
	db.houses, db.scans, db.items, db.auctionator.items = {}, {}, {}, {}
	title, empty = M.ScanSummary()
	eq(empty[1], "No auction house visited yet: open one and CraftWise records what you browse and scan.")
	-- a page without prices: no status, no hover area
	M.ShowPage("settings")
	eq(f.head.status.shown, false); eq(hit.shown, false)
end)

it("States: header status, Stale card and age, Scanning with its progress", function()
	local ns, stub, M = Load()
	TestPage(M, { prices = true })
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 2 * 3600 - 60, kind = "full" } }
	M.Open("testlist")
	local f = M.Frame()
	eq(f.head.status.text, "Horde AH · " .. ns.Style.Hex("text2") .. "2 h|r ago")
	eq(f.notice.shown, false)
	-- stale: newest scan over 24 h old
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 3 * DAY - 60, kind = "full" } }
	M.Refresh()
	eq(f.head.status.text, "Horde AH · scanned 3 days ago")
	local dc = f.head.status.textColor
	eq(dc[1], ns.Style.C.danger[1]); eq(f.head.status.fontObject, ns.Style.Fonts.Label, "bold")
	eq(f.notice.shown, true)
	eq(f.notice.title.text, "Prices are 3 days old.")
	eq(f.notice.body.text, "Profits may be off. Scan at the auction house to refresh.")
	eq(M.ShortAge(3 * DAY + 60), "3 d")
	eq(M.shown.state, "list", "stale prices still show the page")
	-- scanning: a full scan being read
	CraftWiseMarketDB.scope.items[990001] = true
	stub.zone, stub.subzone = "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.replicate = {}
	for i = 1, 1240 do stub.replicate[i] = { itemID = 990000 + i, count = 1, buyout = 100, link = "item:" .. (990000 + i) } end
	local queued
	local after = C_Timer.After
	C_Timer.After = function(_, fn) queued = fn end
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	local p = ns.Market.ScanProgress()
	eq(p.done, 500); eq(p.total, 1240); eq(p.label, "Horde AH")
	M.Refresh()
	eq(f.head.status.text, ns.Style.Hex("live") .. "Scanning Horde AH|r" .. ns.Style.Hex("text2") .. " · 500 of 1 240|r")
	eq(f.head.live.shown, true, "orange nokta")
	eq(f.progress.shown, true); eq(f.progress.height, 2)
	assert(math.abs(f.progress.fill.width - 880 * 500 / 1240) < 1e-6, "progress " .. tostring(f.progress.fill.width))
	eq(f.notice.shown, false, "no stale card while scanning")
	while queued do
		local go = queued
		queued = nil
		go()
	end
	C_Timer.After = after
	eq(ns.Market.ScanProgress(), nil, "scan done")
	M.Refresh()
	eq(f.progress.shown, false)
	eq(f.head.status.text, "Horde AH · " .. ns.Style.Hex("text2") .. "0 min|r ago")
end)

it("States: pages without prices show no AH status", function()
	local _, _, M = Load()
	TestPage(M)
	M.Open("testlist")
	eq(M.Frame().head.status.shown, false)
end)

it("States: a page model that raises shows Error; Reload UI and Show error text; other pages still work", function()
	local _, stub, M = Load()
	TestPage(M, { Model = function() error("TestPage.lua:12: attempt to index a nil value", 0) end, title = "Test list" })
	M.Open("testlist")
	local f = M.Frame()
	eq(M.shown.state, "error")
	eq(f.panel.title.text, "Test list could not be built.")
	eq(f.panel.title.textColor[1], 1, "C.danger red channel")
	eq(f.panel.title.textColor[2], 0x7A / 255)
	eq(f.panel.body.text, "TestPage.lua:12: attempt to index a nil value Your saved data is untouched; the other pages still work.")
	local reload, show = f.panel.buttons[1], f.panel.buttons[2]
	eq(reload.label.text, "Reload UI"); eq(show.label.text, "Show error text")
	reload.scripts.OnClick(reload)
	eq(stub.reloaded, 1)
	show.scripts.OnClick(show)
	eq(f.panel.errorHolder.shown, true)
	eq(f.panel.errorBox.text, "TestPage.lua:12: attempt to index a nil value")
	M.ShowPage("ledger")
	eq(M.shown.state, "list", "another page still works")
	eq(f.panel.shown, false)
end)

it("States: a row or a hero that raises shows Error too", function()
	local _, _, M = Load()
	TestPage(M, { InitRow = function() error("row boom", 0) end })
	M.Open("testlist")
	eq(M.shown.state, "error")
	eq(M.Frame().panel.body.text:sub(1, 8), "row boom")
end)

it("States: unknown price and empty list helpers; skeleton bars step between two tones every 450 ms", function()
	local ns, _, M = Load()
	eq(M.NoPriceText(), ns.Style.Hex("text3") .. "no price|r")
	eq(M.DASH, "—")
	TestPage(M, { Model = function() return { rows = {}, empty = "Nothing listed. Post one and it shows here." } end })
	M.Open("testlist")
	local list = M.ListOf("testlist")
	eq(list.empty.shown, true); eq(list.empty.text, "Nothing listed. Post one and it shows here.")
	local tc = list.empty.textColor
	eq(tc[1], ns.Style.C.text3[1])
	local sk = M.Skeleton(M.Frame(), 70)
	eq(sk.width, 70); eq(sk.height, 8)
	local first = sk.vertexColor[1]
	eq(M.SKELETON_STEP, 0.45)
	M.StepSkeletons()
	assert(sk.vertexColor[1] ~= first, "stepped to the other tone")
	M.StepSkeletons()
	eq(sk.vertexColor[1], first, "and back")
end)

----------------------------------------------------------------------------------------------------
-- List page: hero card, list bar, columns, sorting, rows that open, mouse
----------------------------------------------------------------------------------------------------

it("List: hero card, list bar, header row with the 2 unit rule, footer", function()
	local ns, _, M = Load()
	TestPage(M)
	M.Open("testlist")
	local f = M.Frame()
	eq(f.hero.shown, true)
	eq(f.hero.sheet.cut, 14); eq(f.hero.sheet.fill, ns.Style.C.card)
	eq(f.hero.name.text, "Beta Thing"); eq(f.hero.figure.text, "120"); eq(f.hero.label.text, "Best thing")
	eq(f.hero.name.fontObject, ns.Style.Fonts.Hero); eq(f.hero.figure.fontObject, ns.Style.Fonts.FigureL)
	eq(f.hero.points[1][4], 22, "margin 22")
	eq(f.listBar.shown, true); eq(f.listBar.title.text, "3 things"); eq(f.listBar.note.text, "by value")
	local list = M.ListOf("testlist")
	eq(list.head.height, 24); eq(list.headRule.height, 2)
	eq(f.foot.height, 24); eq(f.foot.left.text, "Prices: invented"); eq(f.foot.right.text, "3 things")
	eq(f.foot.left.fontObject, ns.Style.Fonts.Caption)
end)

it("List: columns on one grid (padding 22, gap 12, one column takes the rest); sorting with ▾", function()
	local ns, _, M = Load()
	local pos = M.ColumnLayout({ { width = 22 }, {}, { width = 96 } }, 880, 22)
	eq(pos[1].x, 22); eq(pos[2].x, 56); eq(pos[2].width, 880 - 44 - 24 - 22 - 96); eq(pos[3].x, 880 - 22 - 96)
	TestPage(M)
	M.Open("testlist")
	local list = M.ListOf("testlist")
	local names = {}
	for _, fr in ipairs(list.box.frames) do names[#names + 1] = fr.elementData.row.name end
	eq(table.concat(names, ","), "Beta Thing,Alpha Thing,Gamma Thing", "value, highest first, unknown last")
	local value = list.headers[3]
	eq(value.label.text, "Value " .. ns.Style.Glyph("down", 10, "text"), "▾ on the active column")
	eq(list.headers[2].label.text, "Item")
	value.scripts.OnClick(value)
	names = {}
	for _, fr in ipairs(list.box.frames) do names[#names + 1] = fr.elementData.row.name end
	eq(table.concat(names, ","), "Alpha Thing,Beta Thing,Gamma Thing", "again: reversed")
	list.headers[2].scripts.OnClick(list.headers[2])
	eq(list.headers[2].label.text, "Item " .. ns.Style.Glyph("down", 10, "text"))
	eq(list.box.retained, true, "the scroll position stays")
	eq(list.bar.cwThumb.width, 4, "4 unit thumb")
	eq(list.bar.Back.shown, false, "no arrows")
end)

it("List: rows 36 with hairlines; a click opens a row in place, one at a time, the nokta moves to it", function()
	local ns, _, M = Load()
	TestPage(M)
	M.Open("testlist")
	local list = M.ListOf("testlist")
	local first = list.box.frames[1]
	eq(first.extent, 36)
	eq(first.cells[2].text, "Beta Thing")
	eq(first.cells[3].text, "120")
	eq(list.box.frames[3].cells[3].text, "—", "unknown: the dash")
	first.scripts.OnClick(first, "LeftButton")
	eq(#list.box.frames, 4, "the opened part under it")
	local row, detail = list.box.frames[1], list.box.frames[2]
	eq(detail.elementData.open, true); eq(detail.content.shownRow, "b")
	eq(detail.extent, 40 + 20 + 8)
	eq(row.bg.shown, true, "C.selected behind the opened row")
	eq(row.nokta.shown, true)
	eq(detail.card.cwSheet.cut, 10)
	local other = list.box.frames[3]
	eq(other.elementData.row.key, "a")
	other.scripts.OnClick(other, "LeftButton")
	eq(#list.box.frames, 4)
	eq(list.box.frames[3].elementData.open, true, "now under Alpha")
	eq(list.box.frames[1].nokta.shown, false, "one open at a time")
	list.box.frames[2].scripts.OnClick(list.box.frames[2], "LeftButton")
	eq(#list.box.frames, 3, "click again closes")
	M.Refresh()
	eq(#list.box.frames, 3)
end)

it("List: right- or middle-click on an item: the item menu; Shift-click: link into chat; hover: tooltips", function()
	local ns, stub, M = Load()
	stub.items[990002] = { name = "Beta Thing", link = "|cffffffff|Hitem:990002::|h[Beta Thing]|h|r" }
	local menus = {}
	ns.ShowItemMenu = function(id, anchor) menus[#menus + 1] = id end
	TestPage(M)
	M.Open("testlist")
	local list = M.ListOf("testlist")
	local row = list.box.frames[1]
	eq(list:Click(row, "RightButton"), "menu")
	eq(list:Click(row, "MiddleButton"), "menu")
	eq(menus[1], 990002); eq(#menus, 2)
	stub.shift = true
	eq(list:Click(row, "LeftButton"), "link")
	eq(stub.chatLinks[1], "|cffffffff|Hitem:990002::|h[Beta Thing]|h|r")
	stub.shift = false
	local tipped
	GameTooltip.SetItemByID = function(_, id) tipped = id end
	row.scripts.OnEnter(row)
	eq(tipped, 990002)
	-- a cell's own tip: the inverse tooltip with the reason
	local unknown = list.box.frames[3]
	local hit = unknown.hits[3]
	hit.scripts.OnEnter(hit)
	eq(CraftWiseInverseTip.shown, true); eq(CraftWiseInverseTip.title.text, "Not listed in the last full scan")
	hit.scripts.OnLeave(hit)
	hit.scripts.OnClick(hit, "LeftButton")
	eq(list.box.frames[4] and list.box.frames[4].elementData.open, true, "a click on the cell opens the row")
end)

it("Page tools: built once into their slot, shown only while the page is current", function()
	local _, _, M = Load()
	local built = 0
	TestPage(M, { section = "make", key = "testtools", order = 0,
		Tools = function(slot) built = built + 1; slot.chip = true end,
		ListTools = function(slot) slot.chips = true end })
	M.Open("testtools")
	M.Refresh(); M.Refresh()
	eq(built, 1)
	local s = M.SlotsOf("testtools")
	eq(s.tools.shown, true); eq(s.listTools.shown, true)
	M.ShowPage("learn")
	eq(s.tools.shown, false); eq(s.listTools.shown, false)
end)

----------------------------------------------------------------------------------------------------
-- Where everything lands: the bridges
----------------------------------------------------------------------------------------------------

it("Bridges: no page is a bridge any more; Bridges.lua and the profit window are gone (#154)", function()
	local ns, _, M = Load()
	eq(M.BRIDGES, nil)
	for _, section in ipairs(M.SECTIONS) do
		for _, p in ipairs(M.SectionPages(section.key)) do
			eq(p.bridge, nil, p.key)
		end
	end
	local toc = io.open("CraftWise/CraftWise.toc"):read("*a")
	eq(toc:find("Bridges.lua", 1, true), nil)
	eq(toc:find("ProfitFrame", 1, true), nil)
	eq(ns.PF, nil); eq(ns.ToggleProfitFrame, nil); eq(CraftWiseFrame, nil)
end)

----------------------------------------------------------------------------------------------------
-- Pure helpers
----------------------------------------------------------------------------------------------------

it("Main: ages, thousands and the house name in the copy", function()
	local _, _, M = Load()
	eq(M.AgeText(41 * 60), "41 min"); eq(M.AgeText(2 * 3600 + 5), "2 h"); eq(M.AgeText(DAY + 5), "1 day")
	eq(M.AgeText(3 * DAY), "3 days")
	eq(M.Thousands(1240), "1 240"); eq(M.Thousands(3800), "3 800"); eq(M.Thousands(500), "500")
	eq(M.Thousands(1234567), "1 234 567")
	local copy = M.StateCopy("noPrices", { prices = { label = "Booty Bay" } })
	assert(copy.body:find("Open the Booty Bay auction house", 1, true), copy.body)
	eq(M.StateCopy("firstRun", {}).title, "Open your profession window once.")
end)
