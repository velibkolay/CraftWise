-- Main window: drag to resize, and the tables reflow to the new width (#280). The window is dragged at its
-- bottom right corner, the docked sheet at its inner edge; the size is saved per layout and clamped to the
-- layout's own size and the screen; the pages are drawn again while a drag is on at most every 0.1 s and
-- once when it ends; columns that are cut get room before the recipe name does. Invented data only.
local NOW = 1794000000

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock or NOW end
	stub.clock = NOW
	stub.names.player = "Testperson"
	return ns, stub, ns.Main
end

-- A list page with invented rows, as main_shell_spec has one (name flexible, one fixed column).
local function TestPage(M)
	return M.RegisterPage({
		key = "testlist", section = "lookup", label = "Test list", order = 9,
		columns = {
			{ key = "icon", icon = true, width = 22 },
			{ key = "name", label = "Item", sort = true },
			{ key = "value", label = "Value", width = 96, align = "RIGHT", sort = true,
				text = function(r) return tostring(r.value) end },
		},
		sort = { key = "value", desc = true },
		Model = function()
			return {
				rows = { { key = "a", name = "Alpha Thing", value = 30 }, { key = "b", name = "Beta Thing", value = 120 } },
				listTitle = "2 things", footer = "invented",
			}
		end,
	})
end

-- The list the page drew (it has the column positions the rows use).
local function ListOf(stub, pageKey)
	for _, fr in ipairs(stub.frames) do
		if fr.positions and fr.page and fr.page.key == pageKey and fr:IsShown() then
			return fr
		end
	end
end

-- eq compares tables by identity: this compares what is in them.
local function same(actual, expected, msg)
	local function Show(v)
		if type(v) ~= "table" then
			return tostring(v)
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local out = {}
		for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Show(v[k]) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	if Show(actual) ~= Show(expected) then
		error((msg or "values differ") .. ": expected " .. Show(expected) .. ", got " .. Show(actual), 2)
	end
end

local function Screen(w, h)
	UIParent.GetWidth = function() return w end
	UIParent.GetHeight = function() return h end
end

local function Counting(M)
	local n = { refreshes = 0 }
	local real = M.Refresh
	M.Refresh = function(...) n.refreshes = n.refreshes + 1; return real(...) end
	return n
end

----------------------------------------------------------------------------------------------------
-- Columns
----------------------------------------------------------------------------------------------------

it("#280 columns: at the layout's own width nothing moves; dragged wider the cut columns get room first, then the name", function()
	local _, _, M = Load()
	local P = M.CraftedPage
	local m = M.WINDOW_METRICS
	local base = M.ColumnLayout(P.COLUMNS, 880, 22, nil, 880)
	local plain = M.ColumnLayout(P.COLUMNS, 880, 22)
	for i = 1, #P.COLUMNS do
		eq(base[i].x, plain[i].x); eq(base[i].width, plain[i].width, "default look: column " .. i)
	end
	eq(base[2].width, P.MIN_NAME); eq(base[6].width, 104, "Speed at its width")
	-- 80 units wider: Speed (104 -> 140), Profit/h and Profit today (84 -> 100) and Profit total (96 -> 116) first
	local wide = M.ColumnLayout(P.COLUMNS, 960, 22, nil, 880)
	eq(wide[6].width, 140, "Speed is no longer cut")
	eq(wide[7].width, 100); eq(wide[8].width, 100); eq(wide[9].width, 108, "what is left of the 80 after the others")
	eq(wide[2].width, P.MIN_NAME, "the name had no room left over yet")
	-- wider still: the columns are full, the recipe name takes the rest
	local huge = M.ColumnLayout(P.COLUMNS, 1400, 22, nil, 880)
	eq(huge[6].width, 140); eq(huge[9].width, 116)
	eq(huge[2].width, 1400 - 880 + P.MIN_NAME - (36 + 16 + 16 + 20), "the name gets 520 minus what the others took")
	-- the row still ends at the padding
	local last = huge[#huge]
	eq(last.x + last.width, 1400 - 22)
	eq(m.width, 880)
end)

it("#280 columns: a page with fixed columns gives the name the room it was dragged past; the Craft name before its rail", function()
	local _, _, M = Load()
	local cols = { { key = "icon", icon = true, width = 22 }, { key = "name", width = 200 }, { key = "qty", width = 40 } }
	local base = M.ColumnLayout(cols, 880, 22, nil, 880)
	eq(base[2].width, 200, "slack at the default width stays slack")
	local wide = M.ColumnLayout(cols, 1000, 22, nil, 880)
	eq(wide[2].width, 320); eq(wide[3].width, 40)
	eq(M.ColumnLayout(cols, 1000, 22)[2].width, 200, "without the layout's width nothing is handed out")
	-- Craft: the rail is the flexible column; the recipe name grows to 300 first
	local C = M.CraftPage.COLUMNS
	local at = M.ColumnLayout(C, 880, 22, nil, 880)
	local more = M.ColumnLayout(C, 1020, 22, nil, 880)
	eq(more[2].width, 300); eq(more[3].width, at[3].width + 140 - 90, "the rail gets what the name left")
	-- a narrow window never squeezes the flexible column below its minimum
	eq(M.ColumnLayout({ { width = 500 }, {} }, 400, 22)[2].width, 40)
end)

----------------------------------------------------------------------------------------------------
-- Size: saved, restored, clamped
----------------------------------------------------------------------------------------------------

it("#280 size: the layout's own size is the minimum, the screen the maximum; a docked sheet takes at most half the width", function()
	local _, _, M = Load()
	Screen(1920, 1080)
	local w, h = M.ClampSize(M.WINDOW_METRICS, 1100, 700, 1)
	eq(w, 1100); eq(h, 700)
	w, h = M.ClampSize(M.WINDOW_METRICS, 300, 200, 1)
	eq(w, 880); eq(h, 600, "never smaller than today's size")
	w, h = M.ClampSize(M.WINDOW_METRICS, 9000, 9000, 1)
	eq(w, 1920); eq(h, 1080, "never bigger than the screen")
	w, h = M.ClampSize(M.WINDOW_METRICS, 1920, 1080, 1.3)
	eq(w, 1476); eq(h, 830, "at scale 1.3 the screen holds fewer of its units")
	w, h = M.ClampSize(M.DOCKED_METRICS, 700, 999, 1)
	eq(w, 700); eq(h, nil, "a docked sheet has no height of its own")
	eq((M.ClampSize(M.DOCKED_METRICS, 200, nil, 1)), 380)
	eq((M.ClampSize(M.DOCKED_METRICS, 1800, nil, 1)), 960)
	local minW, minH, maxW, maxH = M.SizeBounds(M.WINDOW_METRICS, 1)
	eq(minW, 880); eq(minH, 600); eq(maxW, 1920); eq(maxH, 1080)
	-- a screen smaller than the window can't make the bounds cross
	Screen(800, 500)
	minW, minH, maxW, maxH = M.SizeBounds(M.WINDOW_METRICS, 1)
	eq(maxW, 880); eq(maxH, 600)
end)

it("#280 size: the saved size is restored at login (the frame, the metrics) and clamped to the screen", function()
	local ns, _, M = Load()
	Screen(1920, 1080)
	M.UI().size = { window = { width = 1200, height = 760 } }
	M.Open()
	local f = M.Frame()
	eq(f.width, 1200); eq(f.height, 760); eq(M.WINDOW_METRICS.width, 1200); eq(M.WINDOW_METRICS.height, 760)
	eq(M.WINDOW_METRICS.baseWidth, 880, "the own size is kept for the minimum")
	-- the saved size is bigger than the screen now (another monitor): clamped, and the saved value is kept
	Screen(1000, 700)
	M.ApplyLayout()
	eq(f.width, 1000); eq(f.height, 700)
	eq(M.UI().size.window.width, 1200, "not overwritten by a clamp")
	-- a damaged saved value falls back to the own size
	M.UI().size = { window = "big" }
	M.ApplyLayout()
	eq(f.width, 880); eq(f.height, 600)
	-- the scale change re-clamps: 1.3 on a 1000 wide screen leaves 769 units: the own size stays the minimum
	M.UI().size = { window = { width = 950, height = 650 } }
	Screen(1920, 1080)
	M.Settings.SetScale(1.3)
	eq(f.width, 950)
	eq(ns.db.settings.ui.scale, 1.3)
end)

it("#280 size: the frame is resizable between the bounds in the window layout, not in the docked ones", function()
	local _, _, M = Load()
	Screen(1920, 1080)
	M.Open()
	local f = M.Frame()
	local bounds, resizable
	f.SetResizeBounds = function(_, ...) bounds = { ... } end
	f.SetResizable = function(_, v) resizable = v end
	M.ApplyLayout()
	eq(resizable, true); same(bounds, { 880, 600, 1920, 1080 })
	eq(f.grip:IsShown(), true); eq(f.edge:IsShown(), false)
	M.SetLayout("dockLeft")
	eq(resizable, false, "docked: the width is dragged at the edge")
	eq(f.grip:IsShown(), false); eq(f.edge:IsShown(), true)
	M.SetLayout("window")
	eq(f.grip:IsShown(), true); eq(f.edge:IsShown(), false)
end)

----------------------------------------------------------------------------------------------------
-- Dragging the window's corner
----------------------------------------------------------------------------------------------------

it("#280 drag: the corner starts the client's sizing; the page is drawn again at most every 0.1 s and once at the end", function()
	local _, stub, M = Load()
	Screen(1920, 1080)
	TestPage(M)
	M.Open("testlist")
	local f = M.Frame()
	local started = {}
	f.StartSizing = function(_, corner) started[#started + 1] = corner end
	local stopped = 0
	f.StopMovingOrSizing = function() stopped = stopped + 1 end
	eq(M.Sizing(), false)
	f.grip.scripts.OnMouseDown(f.grip, "RightButton")
	eq(#started, 0, "only the left button")
	f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
	same(started, { "BOTTOMRIGHT" }); eq(M.Sizing(), true)
	local n = Counting(M)
	-- the client reports sizes, pixel by pixel
	for w = 900, 1000, 10 do
		f.scripts.OnSizeChanged(f, w, 600 + (w - 900) / 2)
	end
	eq(n.refreshes, 0, "no redraw per size change")
	eq(M.WINDOW_METRICS.width, 880, "the pages still have the old width")
	f.scripts.OnUpdate(f, 0.05)
	eq(n.refreshes, 0, "0.05 s: too soon")
	f.scripts.OnUpdate(f, 0.06)
	eq(n.refreshes, 1); eq(M.WINDOW_METRICS.width, 1000); eq(M.WINDOW_METRICS.height, 650)
	eq(ListOf(stub, "testlist").positions[2].width, 1000 - 2 * 22 - 2 * M.COLUMN_GAP - 22 - 96, "the name column follows")
	f.scripts.OnUpdate(f, 0.02)
	eq(n.refreshes, 1, "nothing changed since")
	f.scripts.OnSizeChanged(f, 1100, 700)
	f.scripts.OnUpdate(f, 0.2)
	eq(n.refreshes, 2)
	-- let go: drawn at the last size once, saved for this layout, the place saved too
	f.scripts.OnSizeChanged(f, 1120, 720)
	f.grip.scripts.OnMouseUp(f.grip)
	eq(stopped, 1); eq(M.Sizing(), false)
	eq(n.refreshes, 3)
	same(M.UI().size.window, { width = 1120, height = 720 })
	eq(M.WINDOW_METRICS.width, 1120)
	f.points = { { "TOPLEFT", UIParent, "TOPLEFT", 40, -60 } }
	-- no drag, no change: a click on the grip leaves everything as it is
	f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
	f.grip.scripts.OnMouseUp(f.grip)
	same(M.UI().size.window, { width = 1120, height = 720 })
	eq(n.refreshes, 3)
	-- sizes while no drag is on (the layout's own SetSize) change nothing
	f.scripts.OnSizeChanged(f, 500, 500)
	f.scripts.OnUpdate(f, 1)
	eq(n.refreshes, 3); eq(M.WINDOW_METRICS.width, 1120)
end)

it("#280 drag: the end saves the place the client moved the frame to, and a size outside the bounds is clamped", function()
	local _, _, M = Load()
	Screen(1920, 1080)
	M.Open()
	local f = M.Frame()
	f.StartSizing = function() end
	f.StopMovingOrSizing = function() end
	f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
	f.scripts.OnSizeChanged(f, 300, 200)
	f.points = { { "TOPLEFT", UIParent, "TOPLEFT", 40, -60 } }
	f.grip.scripts.OnMouseUp(f.grip)
	same(M.UI().size.window, { width = 880, height = 600 }, "never under the own size")
	same(M.UI().pos, { "TOPLEFT", "TOPLEFT", 40, -60 })
	f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
	f.scripts.OnSizeChanged(f, 5000, 4000)
	f.grip.scripts.OnMouseUp(f.grip)
	same(M.UI().size.window, { width = 1920, height = 1080 })
	eq(f.width, 1920); eq(f.height, 1080)
end)

it("#280 drag: a slow redraw spaces the next ones out (four times what it took)", function()
	local _, _, M = Load()
	Screen(1920, 1080)
	M.Open()
	local f = M.Frame()
	f.StartSizing = function() end
	f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
	local clock = 0
	debugprofilestop = function() return clock end
	local real = M.Refresh
	local n = 0
	M.Refresh = function(...) n = n + 1; clock = clock + 100; return real(...) end -- a 100 ms redraw
	f.scripts.OnSizeChanged(f, 1000, 650)
	f.scripts.OnUpdate(f, 0.1)
	eq(n, 1)
	f.scripts.OnSizeChanged(f, 1010, 650)
	f.scripts.OnUpdate(f, 0.3)
	eq(n, 1, "0.3 s is under 4 x 0.1 s")
	f.scripts.OnUpdate(f, 0.2)
	eq(n, 2)
end)

----------------------------------------------------------------------------------------------------
-- The docked sheet's edge
----------------------------------------------------------------------------------------------------

it("#280 docked: the width the cursor gives, left and right (pure)", function()
	local _, _, M = Load()
	local D, m = M.Docked, M.DOCKED_METRICS
	eq(D.WidthFromCursor("left", m, 400, 1, 1920), 380, "the sheet is 20 from the left edge")
	eq(D.WidthFromCursor("left", m, 700, 1, 1920), 680)
	eq(D.WidthFromCursor("right", m, 1500, 1, 1920), 400)
	eq(D.WidthFromCursor("left", m, 800, 2, 1920), 380, "at an effective scale of 2 the pixels are halved")
	eq(D.WidthFromCursor("left", m, 800, nil, 1920), 780, "no scale: 1")
end)

it("#280 docked: the inner edge drags the width, saved per side; the window keeps its own", function()
	local _, stub, M = Load()
	Screen(1920, 1080)
	TestPage(M)
	M.UI().size = { window = { width = 1000, height = 650 } }
	M.Open("testlist")
	M.SetLayout("dockLeft")
	local f = M.Frame()
	eq(f.width, 380)
	local pts = {}
	for _, p in ipairs(f.edge.points) do pts[#pts + 1] = p[1] end
	same(pts, { "TOPRIGHT", "BOTTOMRIGHT" }, "the left sheet's inner edge is its right edge")
	local cursor = 700
	GetCursorPosition = function() return cursor, 0 end
	local n = Counting(M)
	f.edge.scripts.OnMouseDown(f.edge, "LeftButton")
	eq(M.Sizing(), true)
	f.scripts.OnUpdate(f, 0.12)
	eq(f.width, 680, "the sheet follows the cursor"); eq(n.refreshes, 1)
	cursor = 760
	f.scripts.OnUpdate(f, 0.03)
	eq(f.width, 740, "the frame follows every frame ..."); eq(n.refreshes, 1, "... the pages not")
	cursor = 5000
	f.scripts.OnUpdate(f, 0.2)
	eq(f.width, 960, "at most half the screen"); eq(n.refreshes, 2)
	cursor = 740
	f.scripts.OnUpdate(f, 0.2)
	f.edge.scripts.OnMouseUp(f.edge)
	eq(M.Sizing(), false)
	same(M.UI().size.dockLeft, { width = 720 })
	eq(M.DOCKED_METRICS.width, 720); eq(f.width, 720)
	same(M.UI().size.window, { width = 1000, height = 650 }, "the window's own size is not touched")
	-- the other side keeps its own width; swapping back brings this one back
	M.SetLayout("dockRight")
	eq(f.width, 380)
	M.SetLayout("dockLeft")
	eq(f.width, 720)
	M.SetLayout("window")
	eq(f.width, 1000); eq(f.height, 650)
	-- the right sheet: the inner edge is its left edge, the cursor measured from the right
	M.SetLayout("dockRight")
	local rpts = {}
	for _, p in ipairs(f.edge.points) do rpts[#rpts + 1] = p[1] end
	same(rpts, { "TOPLEFT", "BOTTOMLEFT" })
	UIParent.GetWidth = function() return 1920 end
	cursor = 1300
	f.edge.scripts.OnMouseDown(f.edge, "LeftButton")
	f.scripts.OnUpdate(f, 0.12)
	f.edge.scripts.OnMouseUp(f.edge)
	same(M.UI().size.dockRight, { width = 600 })
	GetCursorPosition = nil
end)

it("#280 docked: pages draw at the dragged width (a docked page's width is the metrics')", function()
	local _, stub, M = Load()
	Screen(1920, 1080)
	TestPage(M)
	M.UI().size = { dockLeft = { width = 600 } }
	M.UI().layout = "dockLeft"
	M.Open("testlist")
	local f = M.Frame()
	eq(f.width, 600); eq(M.DOCKED_METRICS.width, 600)
	eq(M.shown.layout, "dockLeft"); assert(M.shown.state ~= "error", tostring(M.shown.state))
end)

----------------------------------------------------------------------------------------------------
-- Settings and the title bar
----------------------------------------------------------------------------------------------------

it("#280 Settings: 'Reset window size' next to the scale slider puts every layout back to its own size", function()
	local _, _, M = Load()
	Screen(1920, 1080)
	M.UI().size = { window = { width = 1200, height = 800 }, dockLeft = { width = 700 } }
	M.Open("settings")
	local f = M.Frame()
	eq(f.width, 1200)
	M.Settings.SelectGroup("look")
	local row = M.Settings.RowOf("look", "reset")
	assert(row, "the buttons row")
	local labels = {}
	for _, b in ipairs(row.holder.buttons) do labels[#labels + 1] = b.label.text end
	same(labels, { "Reset window positions", "Reset window size" })
	local b = row.holder.buttons[2]
	b.scripts.OnClick(b)
	same(M.UI().size, {})
	eq(f.width, 880); eq(f.height, 600)
	eq(M.DOCKED_METRICS.width, 380)
end)

it("#280 title bar: Ctrl + mouse wheel changes the scale by one slider step; without Ctrl nothing changes", function()
	local _, _, M = Load()
	M.Open()
	local f = M.Frame()
	local ctrl = false
	IsControlKeyDown = function() return ctrl end
	f.head.scripts.OnMouseWheel(f.head, 1)
	eq(M.UI().scale, 1, "no Ctrl: the wheel does nothing here")
	ctrl = true
	f.head.scripts.OnMouseWheel(f.head, 1)
	eq(M.UI().scale, 1.05)
	f.head.scripts.OnMouseWheel(f.head, -1); f.head.scripts.OnMouseWheel(f.head, -1)
	eq(M.UI().scale, 0.95)
	for _ = 1, 20 do f.head.scripts.OnMouseWheel(f.head, 1) end
	eq(M.UI().scale, 1.3, "the slider's own limit")
	IsControlKeyDown = nil
end)
