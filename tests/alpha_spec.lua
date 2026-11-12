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

it("defaults: main 0.96, farm 0.86, toast 0.70, in the saved variables", function()
	local ns = Load()
	local a = ns.db.settings.alpha
	near(a.main, 0.96); near(a.farm, 0.86); near(a.toast, 0.70)
	near(ns.Style.WindowAlpha("main"), 0.96); near(ns.Style.WindowAlpha("farm"), 0.86); near(ns.Style.WindowAlpha("toast"), 0.70)
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
	near(ns.db.settings.alpha.main, 0.5); near(ns.db.settings.alpha.farm, 0.86); near(ns.db.settings.alpha.toast, 0.70)
	Drag(Row(M, "look", "bgFarm"), 0.6)
	near(ns.db.settings.alpha.farm, 0.6); near(ns.db.settings.alpha.main, 0.5)
	Drag(Row(M, "look", "bgToast"), 0.4)
	near(ns.db.settings.alpha.toast, 0.4)
	eq(Row(M, "look", "bgMain").holder.value.text, "50 %")
	-- the Loot toast group has its own slider on the same value
	local r = Row(M, "toast", "background")
	r.update()
	eq(r.holder.value.text, "40 %")
	Drag(r, 0.9)
	near(ns.db.settings.alpha.toast, 0.9)
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

it("loot toast: the slider redraws the strips (fill and shadow) on screen", function()
	local ns, stub = Load()
	stub.items[2770] = { name = "Copper Ore", icon = 135232, sellPrice = 5 }
	LOOT_ITEM_SELF = "You receive loot: %s."
	stub.now = 100
	stub.Fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format("|cffffffff|Hitem:2770::::::::20:::::|h[Copper Ore]|h|r"), "", "", "", "", "", 0, 0, "", 0, 1, "Player-1-SELF")
	local row
	for _, fr in ipairs(stub.frames) do if fr.sheet and fr.name and fr.count then row = fr end end
	assert(row, "a toast line")
	near(row.sheet.alpha, 0.70)
	ns.Main.Open("settings")
	Drag(Row(ns.Main, "toast", "background"), 0.3)
	near(ns.db.settings.alpha.toast, 0.3)
	near(row.sheet.alpha, 0.3)
	near(row.sheet.pieces.a.vertexColor[4], 0.3)
	eq(row.sheet.pieces.c.vertexColor[4], 1, "the newest line's turkuaz flap stays at 1")
	eq(row.alpha, 1, "the line itself stays at its step alpha")
end)

it("unreadable values fall back to the defaults and out-of-range values clamp", function()
	local ns = Load()
	ns.db.settings.alpha = { main = "x", farm = 7, toast = -1 }
	near(ns.Style.WindowAlpha("main"), 0.96); near(ns.Style.WindowAlpha("farm"), 1); near(ns.Style.WindowAlpha("toast"), 0)
	ns.db.settings.alpha = nil
	near(ns.Style.WindowAlpha("farm"), 0.86)
end)

it("loot toast: dragging the slider with no line on screen shows the test lines, so the preview has something to show", function()
	local ns, _, M = Load()
	M.Open("settings")
	eq(#ns.LootToast.Lines(), 0)
	Drag(Row(M, "toast", "background"), 0.5)
	assert(#ns.LootToast.Lines() > 0, "test lines")
	local n = #ns.LootToast.Lines()
	Drag(Row(M, "toast", "background"), 0.6)
	eq(#ns.LootToast.Lines(), n, "not added again while they are on screen")
end)
