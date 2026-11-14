-- Settings page (#157, spec in #150 "Look up, Music, Settings", board "Settings"): the gear opens it; a left
-- list of groups; every control writes the value it stands for, the old settings panel's and AH rule
-- panel's options included. Invented data only.
local NOW = 1794000000

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	time = function(t)
		if t then return os.time(t) end
		return stub.clock or NOW
	end
	stub.clock = NOW
	stub.names.player, stub.surnames.player = "Testperson", "Tanner"
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub, ns.Main
end

-- Opens a group and returns a function that finds a row's frame by key.
local function Group(M, key)
	M.Settings.SelectGroup(key)
	return function(rowKey)
		local r = M.Settings.RowOf(key, rowKey)
		assert(r, key .. "." .. rowKey .. " row")
		return r
	end
end

local function Seg(r, index)
	local b = r.holder.control.buttons[index]
	b.scripts.OnClick(b)
end

local function Check(box)
	box.scripts.OnClick(box)
end

it("Settings: the gear opens the page; the groups of the spec in its order; the nokta on the open one", function()
	local ns, _, M = Load()
	M.Open()
	local f = M.Frame()
	f.head.gear.scripts.OnClick(f.head.gear)
	eq(M.shown.page, "settings"); eq(M.shown.state, "custom")
	local labels = {}
	for _, g in ipairs(M.Settings.Groups()) do labels[#labels + 1] = g.label end
	eq(table.concat(labels, ","), "Look,Prices,Tooltips,Bags and loot,Loot toast,Vendor loops,Disenchant,Farm tracker,Fishing,AH rule,Snapshot,Debug")
	local body = M.SlotsOf("settings").body
	eq(body.nav.width, 170)
	local C = ns.Style.C
	eq(body.nav.buttons.look.label.textColor[1], C.text[1], "the open group in C.text")
	eq(body.nav.buttons.prices.label.textColor[1], C.text3[1])
	body.nav.buttons.prices.scripts.OnClick(body.nav.buttons.prices)
	eq(M.UI().settingsGroup, "prices")
	eq(body.groups.prices.shown, true); eq(body.groups.look.shown, false)
	eq(body.nav.nokta.shown, true)
	-- /craftwise settings opens the page
	M.ShowPage("craft")
	SlashCmdList.CRAFTWISE("settings")
	eq(M.shown.page, "settings")
end)

it("Settings › Look: layout, scale (on release), fade, lock, Escape, minimap button, reset positions", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "look")
	-- Layout lists the registered layouts: Window, Docked left, Docked right (#161)
	local seg = row("layout").holder.control
	eq(#seg.buttons, 3); eq(seg.buttons[1].label.text, "Window"); eq(seg.selected, 1)
	eq(seg.buttons[2].label.text, "Docked left"); eq(seg.buttons[3].label.text, "Docked right")
	Seg(row("layout"), 2)
	eq(M.UI().layout, "dockLeft")
	Seg(M.Settings.DockedRowOf("look", "layout"), 1) -- the docked Settings page swaps back
	eq(M.UI().layout, "window")
	-- Scale: 70-130 %, applied when the drag ends
	local s = row("scale").holder.control
	s.scripts.OnValueChanged(s, 1.2)
	eq(M.UI().scale, 1, "not while dragging")
	eq(row("scale").holder.value.text, "120 %")
	s.scripts.OnMouseUp(s)
	eq(M.UI().scale, 1.2)
	M.Settings.SetScale(2); eq(M.UI().scale, 1.3)
	M.Settings.SetScale(0.1); eq(M.UI().scale, 0.7)
	-- Fade (#163)
	Check(row("fade").holder.control)
	eq(ns.db.farm.fade, true)
	-- Windows: Lock position, Close with Escape
	local boxes = row("windows").holder.boxes
	Check(boxes[1]); eq(M.UI().locked, true)
	Check(boxes[2]); eq(M.UI().escape, false)
	local listed = false
	for _, n in ipairs(UISpecialFrames) do listed = listed or n == "CraftWiseMainFrame" end
	eq(listed, false, "Escape no longer closes it")
	Check(boxes[2]); eq(M.UI().escape, true)
	-- Minimap button
	Check(row("minimap").holder.control); eq(ns.db.minimap.hide, true)
	Check(row("minimap").holder.control); eq(ns.db.minimap.hide, false)
	-- Reset window positions
	M.UI().pos = { "TOPLEFT", "TOPLEFT", 5, -5 }
	ns.db.farm.pos = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 1, y = 1 }
	ns.db.lootToast.pos = { "TOP", "TOP", 0, -100 }
	local b = row("reset").holder.buttons[1]
	eq(b.label.text, "Reset window positions")
	b.scripts.OnClick(b)
	eq(M.UI().pos, nil); eq(ns.db.farm.pos, nil); eq(ns.db.lootToast.pos, nil)
	-- the Background sliders: tests/alpha_spec.lua
	assert(M.Settings.RowOf("look", "bgMain") and M.Settings.RowOf("look", "bgFarm") and M.Settings.RowOf("look", "bgToast"))
end)

it("Settings › Prices: basis, house (only with data), reagent cost per view", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "prices")
	local changed = 0
	ns.Listen("PRICES_CHANGED", function() changed = changed + 1 end)
	Seg(row("basis"), 2); eq(ns.db.settings.priceBasis, "current")
	Seg(row("basis"), 1); eq(ns.db.settings.priceBasis, "typical")
	assert(changed >= 2, "prices refresh")
	-- Booty Bay has no data: can't be picked, the sub-line says so
	Seg(row("house"), 2)
	eq(ns.db.settings.priceHouse, "faction")
	assert(row("house").sub.text:find("No data yet:", 1, true) and row("house").sub.text:find("Booty Bay", 1, true), row("house").sub.text)
	eq(row("house").holder.control.buttons[2].alpha, 0.4)
	CraftWiseMarketDB.scans["PvP|N:BootyBay"] = { { t = NOW, kind = "full", items = 1 } }
	CraftWiseMarketDB.houses["PvP|N:BootyBay"] = { realm = "PvP", kind = "neutral", label = "Booty Bay" }
	Seg(row("house"), 2)
	eq(ns.db.settings.priceHouse, "BootyBay")
	for i, view in ipairs(ns.COST_BASIS_VIEWS) do
		local r = row("cost_" .. view)
		Seg(r, 2); eq(ns.db.settings.costBasis[view], "paid", view)
		Seg(r, 1); eq(ns.db.settings.costBasis[view], "ah", view)
	end
	eq(row("cost_profit").label.text, "Reagent cost · Craft")
end)

it("Settings › Tooltips: Always / Only with Shift / Off and every line", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "tooltips")
	Seg(row("tooltip"), 2); eq(ns.db.tooltip.enabled, true); eq(ns.db.tooltip.mode, "shift")
	Seg(row("tooltip"), 3); eq(ns.db.tooltip.enabled, false); eq(ns.db.tooltip.mode, "shift")
	eq(row("line_usedIn").holder.alpha, 0.4, "lines dim while the section is off")
	Seg(row("tooltip"), 1); eq(ns.db.tooltip.enabled, true); eq(ns.db.tooltip.mode, "always")
	for _, line in ipairs(ns.TOOLTIP_LINES) do
		local box = row("line_" .. line.key).holder.control
		eq(box.checked, true, line.key)
		Check(box); eq(ns.db.tooltip.lines[line.key], false, line.key)
	end
end)

it("Settings › Bags and loot: menu click, slot marks, dismissed upgrades, fast auto-loot", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "bags")
	Seg(row("menuClick"), 2); eq(ns.db.settings.menuClick, "altright")
	Seg(row("menuClick"), 3); eq(ns.db.settings.menuClick, "off")
	ns.db.junk[990001] = true
	eq(ns.SlotMark(990001), "junk")
	Check(row("slotMarks").holder.control); eq(ns.db.settings.slotMarks, false)
	eq(ns.SlotMark(990001), nil, "no marks while they are off")
	Check(row("slotMarks").holder.control); eq(ns.db.settings.slotMarks, true)
	Check(row("showDismissed").holder.control); eq(ns.db.settings.showDismissed, true)
	local before = ns.Loot.Enabled()
	Check(row("fastLoot").holder.control); eq(ns.Loot.Enabled(), not before)
	assert(row("fastLoot").sub.text ~= "", "says what fast auto-loot does")
end)

it("Settings › Loot toast: Off / Lines / With value, lines stay, Move, Test, Reset position", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "toast")
	eq(row("mode").holder.control.selected, 3, "With value by default")
	Seg(row("mode"), 2); eq(ns.db.lootToast.enabled, true); eq(ns.db.lootToast.value, false)
	Seg(row("mode"), 1); eq(ns.db.lootToast.enabled, false)
	Seg(row("mode"), 3); eq(ns.db.lootToast.enabled, true); eq(ns.db.lootToast.value, true)
	local s = row("duration").holder.control
	s.scripts.OnValueChanged(s, 7); eq(ns.db.lootToast.duration, 7)
	eq(row("duration").holder.value.text, "7 s")
	local b = row("position").holder.buttons
	eq(b[1].label.text, "Move")
	b[1].scripts.OnClick(b[1]); eq(ns.db.lootToast.locked, false)
	eq(b[1].label.text, "Lock")
	b[1].scripts.OnClick(b[1]); eq(ns.db.lootToast.locked, true)
	b[2].scripts.OnClick(b[2])
	assert(#ns.LootToast.Lines() > 0, "Test shows lines")
	ns.db.lootToast.pos = { "TOP", "TOP", 0, -50 }
	b[3].scripts.OnClick(b[3]); eq(ns.db.lootToast.pos, nil)
end)

it("Settings › Farm tracker: on, start on first loot, pause when idle, lock, mini mode, scale", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "farm")
	Check(row("autoStart").holder.control); eq(ns.db.farm.autoStart, false)
	local s = row("idle").holder.control
	s.scripts.OnValueChanged(s, 12); eq(ns.db.farm.idleMinutes, 12)
	eq(row("idle").holder.value.text, "12 min")
	s.scripts.OnValueChanged(s, 0); eq(row("idle").holder.value.text, "never")
	Check(row("lock").holder.control); eq(ns.db.farm.locked, true)
	Check(row("mini").holder.control); eq(ns.db.farm.mini, true)
	Check(row("mini").holder.control); eq(ns.db.farm.mini, false)
	s = row("scale").holder.control
	s.scripts.OnValueChanged(s, 1.4); eq(ns.db.farm.scale, 1.4)
	Check(row("on").holder.control); eq(ns.db.farm.enabled, false)
	eq(row("autoStart").holder.alpha, 0.4, "dim while the tracker is off")
end)

it("Settings › Fishing: session gap and own catches count from", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "fishing")
	local s = row("gap").holder.control
	s.scripts.OnValueChanged(s, 9); eq(ns.db.settings.fishingSessionGap, 9)
	local r = row("ownMin")
	eq(r.holder.value.text, "50")
	r.holder.up.scripts.OnClick(r.holder.up); eq(ns.db.settings.fishingOwnMin, 60)
	r.holder.down.scripts.OnClick(r.holder.down); eq(ns.db.settings.fishingOwnMin, 50)
	ns.db.settings.fishingOwnMin = 5
	r.holder.up.scripts.OnClick(r.holder.up); eq(ns.db.settings.fishingOwnMin, 6)
end)

it("Settings › AH rule: percent and copper steps, the example, Defaults (the old AH rule panel)", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "ahrule")
	local p, c = row("percent").holder, row("copper").holder
	eq(p.value.text, "+20 %")
	p.up.scripts.OnClick(p.up); eq(ns.db.settings.ahMinPercent, 25)
	p.down.scripts.OnClick(p.down); p.down.scripts.OnClick(p.down); eq(ns.db.settings.ahMinPercent, 15)
	c.up.scripts.OnClick(c.up); eq(ns.db.settings.ahMinCopper, 20)
	c.down.scripts.OnClick(c.down); c.down.scripts.OnClick(c.down); eq(ns.db.settings.ahMinCopper, 5)
	assert(row("example").holder.text.text:find("after the 5% cut", 1, true), row("example").holder.text.text)
	local d = row("defaults").holder.buttons[1]
	d.scripts.OnClick(d)
	eq(ns.db.settings.ahMinPercent, 20); eq(ns.db.settings.ahMinCopper, 10)
end)

it("Settings › Snapshot: Save, Reload UI, when it was saved and what it holds", function()
	local ns, stub, M = Load()
	M.Open("settings")
	local row = Group(M, "snapshot")
	assert(row("last").holder.text.text:find("Not saved yet", 1, true), row("last").holder.text.text)
	local b = row("buttons").holder.buttons
	b[1].scripts.OnClick(b[1])
	assert(ns.db.snapshots[ns.Snapshot.Key()], "snapshot saved")
	local text = row("last").holder.text.text
	assert(text:find("Last saved", 1, true) and text:find("Snapshot saved.", 1, true), text)
	local cells = row("holds").holder.cells
	eq(#cells, #ns.Snapshot.SECTIONS)
	eq(cells[1].left.text, "char"); eq(cells[1].right.text, "saved")
	local reloaded = false
	C_UI = { Reload = function() reloaded = true end }
	b[2].scripts.OnClick(b[2])
	eq(reloaded, true)
end)
