-- Background alpha per window (#162): db.settings.alpha.main / .farm / .toast on sheet, card and plane
-- textures only; sliders in Settings > Look and > Loot toast with a live preview. Invented data only.
local function Load()
	local ns, stub = LoadAddon()
	time = function() return 1794000000 end
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = tostring(m) end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub, ns.Main
end

local function near(a, b, msg)
	assert(math.abs(a - b) < 1e-9, (msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function Row(M, group, key)
	M.Settings.SelectGroup(group)
	local r = M.Settings.RowOf(group, key)
	assert(r, group .. "." .. key)
	return r
end

local function Drag(row, v)
	local s = row.holder.control
	s.scripts.OnValueChanged(s, v)
end

it("defaults: main 0.96, farm 0.86, in the saved variables", function()
	local ns = Load()
	local a = ns.db.settings.alpha
	near(a.main, 0.96); near(a.farm, 0.86); eq(a.toast, nil, "the loot toast has no background (#426)")
	near(ns.Style.WindowAlpha("main"), 0.96); near(ns.Style.WindowAlpha("farm"), 0.86)
end)

it("the main window starts at its alpha: sheet, shadow, cards and header plane", function()
	local ns, _, M = Load()
	M.Open()
	local f = M.Frame()
	near(f.sheet.pieces.a.vertexColor[4], 0.96)
	near(f.sheet.shadow.a.vertexColor[4], 0.5 * 0.96)
	near(f.hero.sheet.pieces.a.vertexColor[4], 0.96, "hero card")
	near(f.head.art.alpha, 0.96, "header planes")
end)

it("Settings > Look: each slider writes its own value and only that window's alpha", function()
	local ns, _, M = Load()
	M.Open("settings")
	Drag(Row(M, "look", "bgMain"), 0.5)
	near(ns.db.settings.alpha.main, 0.5); near(ns.db.settings.alpha.farm, 0.86)
	Drag(Row(M, "look", "bgFarm"), 0.6)
	near(ns.db.settings.alpha.farm, 0.6); near(ns.db.settings.alpha.main, 0.5)
	eq(Row(M, "look", "bgMain").holder.value.text, "50 %")
	eq(M.Settings.RowOf("look", "bgToast"), nil, "no background slider for the loot toast (#426)")
	eq(M.Settings.RowOf("toast", "background"), nil)
	-- never outside the slider's range
	Drag(Row(M, "look", "bgMain"), 0)
	near(ns.db.settings.alpha.main, M.Settings.ALPHA_MIN)
	Drag(Row(M, "look", "bgMain"), 3)
	near(ns.db.settings.alpha.main, 1)
end)

it("live preview: the main window changes while dragging; only background textures change", function()
	local ns, _, M = Load()
	M.Open()
	local f = M.Frame()
	M.ShowPage("settings")
	local before = {
		text = f.head.brand.textColor[4], nokta = f.head.key.alpha, frame = f.alpha,
		ruleCount = 0,
	}
	Drag(Row(M, "look", "bgMain"), 0.35)
	near(f.sheet.pieces.a.vertexColor[4], 0.35); near(f.sheet.pieces.b.vertexColor[4], 0.35)
	near(f.sheet.pieces.c.vertexColor[4], 0.35, "the dog-ear is part of the sheet")
	near(f.sheet.shadow.a.vertexColor[4], 0.5 * 0.35)
	near(f.hero.sheet.pieces.a.vertexColor[4], 0.35, "card")
	near(f.head.art.alpha, 0.35, "plane")
	-- untouched: text, icons, the window frame itself
	eq(f.head.brand.textColor[4], before.text, "text stays at alpha 1")
	eq(f.head.key.alpha, before.nokta, "icon stays")
	eq(f.alpha, before.frame, "the frame is not faded")
	-- the farm tracker and toast are not touched by the main slider
	near(ns.Style.WindowAlpha("farm"), 0.86)
end)

it("a card created after the change starts at the current alpha", function()
	local ns, _, M = Load()
	ns.Style.SetWindowAlpha("main", 0.5)
	M.Open()
	near(M.Frame().sheet.pieces.a.vertexColor[4], 0.5)
	near(M.Frame().hero.sheet.pieces.a.vertexColor[4], 0.5)
end)

it("farm tracker: its sheet and cards follow the farm alpha; the fade multiplies on the frame", function()
	local ns, _, M = Load()
	M.Open("settings")
	local FF = ns.FarmFrame
	FF.Show()
	local f = CraftWiseFarmFrame
	near(f.cwSheet.pieces.a.vertexColor[4], 0.86)
	Drag(Row(ns.Main, "look", "bgFarm"), 0.5)
	near(f.cwSheet.pieces.a.vertexColor[4], 0.5)
	near(f.cwSheet.shadow.a.vertexColor[4], 0.25)
	near(f.cwSheet.pieces.c.vertexColor[4], 0.5)
	-- the fade is the frame's alpha, a separate multiplier: the sheet's own alpha is unchanged by it
	FF.SetFade(true)
	FF.ApplyFade(true)
	near(f.alpha, FF.FADE_ALPHA)
	near(f.cwSheet.pieces.a.vertexColor[4], 0.5, "fade does not rewrite the sheet alpha")
	-- the main window's alpha does not reach the tracker
	ns.Style.SetWindowAlpha("main", 0.2)
	near(f.cwSheet.pieces.a.vertexColor[4], 0.5)
end)

it("unreadable values fall back to the defaults and out-of-range values clamp", function()
	local ns = Load()
	ns.db.settings.alpha = { main = "x", farm = 7 }
	near(ns.Style.WindowAlpha("main"), 0.96); near(ns.Style.WindowAlpha("farm"), 1)
	ns.db.settings.alpha = nil
	near(ns.Style.WindowAlpha("farm"), 0.86)
end)

