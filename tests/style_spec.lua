-- UI/Style.lua (#151): colours, fonts, the folded sheet, rails, motion and controls against the spec in #150.

-- The spec's Colours table, as written there.
local SPEC = {
	ground = "121314", sheet = "1B1C1F", card = "26282C", cardFlap = "3C3E44", flap = "34363B",
	planeA = "202125", planeB = "25262A", selected = "212226", rule = "2E3034", ruleStrong = "6F7378",
	text = "ECEDEA", text2 = "A7AAA6", text3 = "8E918D", nokta = "2CC9BC",
	action = "E5432F", actionFlap = "F07A68", onAction = "141517", danger = "FF7A63", live = "FF8A2A",
	keyGold = "E8B94B", keyGoldDark = "D9A93A", keyGoldLight = "F8DD9E",
	coinGold = "F2C14E", coinSilver = "C3C9D2", coinCopper = "DB8A5C",
	qPoor = "9D9D9D", qCommon = "ECEDEA", qUncommon = "3BD45A", qRare = "4EA2FF", qEpic = "B86CF5",
	["skill.orange"] = "FF8040", ["skill.yellow"] = "FFFF00", ["skill.green"] = "40BF40", ["skill.grey"] = "808080",
	shadow = "000000",
}

local function byte(x) return math.floor(x * 255 + 0.5) end

it("Style: every colour constant matches the spec's hex value, and nothing else is in C", function()
	local ns = LoadAddon()
	local S = ns.Style
	local n = 0
	for name, hex in pairs(SPEC) do
		local c = S.Color(name)
		eq(c.hex, hex, name)
		eq(("%02X%02X%02X"):format(byte(c[1]), byte(c[2]), byte(c[3])), hex, name .. " rgb")
		eq(c[4], name == "shadow" and 0.5 or 1, name .. " alpha")
		n = n + 1
	end
	local count = 0
	for k, v in pairs(S.C) do
		if k == "skill" then
			for _ in pairs(v) do count = count + 1 end
		else
			count = count + 1
		end
	end
	eq(count, n, "constants in C")
end)

it("Style.Hex gives the |cff escape; unknown names fail loudly", function()
	local S = LoadAddon().Style
	eq(S.Hex("text"), "|cffECEDEA")
	eq(S.Hex("skill.orange"), "|cffFF8040")
	eq(S.Hex("coinCopper"), "|cffDB8A5C")
	eq(S.Hex(S.C.danger), "|cffFF7A63")
	assert(not pcall(S.Hex, "accent"), "unknown colour must error")
	assert(not pcall(S.Hex, "skill.purple"), "unknown skill colour must error")
end)

it("the old names and widgets are gone with the old windows (#157)", function()
	local S = LoadAddon().Style
	eq(S.colors, nil); eq(S.Panel, nil); eq(S.Button, nil); eq(S.Check, nil); eq(S.CloseButton, nil)
end)

it("Style: twelve font objects with the spec's file, size and no flags", function()
	LoadAddon()
	local F = "Interface\\AddOns\\CraftWise\\Media\\Fonts\\AtkinsonHyperlegible"
	local want = {
		CraftWiseFontBrand = { "Next-ExtraBold", 16 }, CraftWiseFontHero = { "Next-ExtraBold", 20 },
		CraftWiseFontSection = { "Next-Bold", 13 }, CraftWiseFontBody = { "Next-Regular", 12 },
		CraftWiseFontBodyBold = { "Next-Bold", 12 }, CraftWiseFontSmall = { "Next-Regular", 11 },
		CraftWiseFontLabel = { "Next-Bold", 10 }, CraftWiseFontCaption = { "Next-Regular", 10 },
		CraftWiseFontFigure = { "Mono-Regular", 12 }, CraftWiseFontFigureBold = { "Mono-SemiBold", 13 },
		CraftWiseFontFigureL = { "Mono-SemiBold", 24 }, CraftWiseFontFigureXL = { "Mono-SemiBold", 34 },
	}
	local n = 0
	for name, w in pairs(want) do
		local font = _G[name]
		assert(font, name .. " not created")
		local path, size, flags = font:GetFont()
		eq(path, F .. w[1] .. ".ttf", name)
		eq(size, w[2], name .. " size")
		eq(flags, "", name .. " flags")
		assert(size >= 10, "nothing smaller than 10")
		n = n + 1
	end
	eq(n, 12)
end)

-- Where a region sits inside a w x h frame: left, top, width, height (y down from the frame's top).
local function rect(tex, frame, w, h)
	local function pos(point)
		local x = point:find("LEFT") and 0 or point:find("RIGHT") and w or w / 2
		local y = point:find("TOP") and 0 or point:find("BOTTOM") and h or h / 2
		return x, y
	end
	local left, right, top, bottom
	for _, p in ipairs(tex.points) do
		local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
		assert(rel == frame, "anchored to the frame")
		local ax, ay = pos(relPoint)
		ax, ay = ax + x, ay - y
		if point:find("LEFT") then left = ax end
		if point:find("RIGHT") then right = ax end
		if point:find("TOP") then top = ay end
		if point:find("BOTTOM") then bottom = ay end
	end
	left = left or (right - tex.width)
	right = right or (left + tex.width)
	top = top or (bottom - tex.height)
	bottom = bottom or (top + tex.height)
	return left, top, right - left, bottom - top
end

local function same(actual, expected, what)
	for i, v in ipairs(expected) do
		eq(actual[i], v, what .. " [" .. i .. "]")
	end
end

it("Style.Sheet: piece sizes for the window, card and button cuts, shadow offset (3, -3) one sublevel lower", function()
	local S = LoadAddon().Style
	for _, case in ipairs({ { 880, 600, 22 }, { 260, 180, 22 }, { 400, 90, 14 }, { 120, 28, 10 }, { 300, 28, 8 } }) do
		local w, h, cut = case[1], case[2], case[3]
		local f = CreateFrame("Frame")
		local created = {}
		f.CreateTexture = function(self, name, layer, inherits, sublevel)
			local t = getmetatable(self).CreateTexture(self)
			t.layer, t.sublevel = layer, sublevel
			table.insert(created, t)
			return t
		end
		local s = S.Sheet(f, S.C.sheet, S.C.flap, cut, true)
		eq(#created, 6, "three pieces and their shadow")
		local p, sh = s.pieces, s.shadow
		same({ rect(p.a, f, w, h) }, { 0, 0, w - cut, h }, "A")
		same({ rect(p.b, f, w, h) }, { w - cut, cut, cut, h - cut }, "B")
		same({ rect(p.c, f, w, h) }, { w - cut, 0, cut, cut }, "C")
		same({ rect(sh.a, f, w, h) }, { 3, 3, w - cut, h }, "shadow A")
		same({ rect(sh.b, f, w, h) }, { w - cut + 3, cut + 3, cut, h - cut }, "shadow B")
		same({ rect(sh.c, f, w, h) }, { w - cut + 3, 3, cut, cut }, "shadow C")
		eq(p.c.texture, "Interface\\AddOns\\CraftWise\\Media\\cw-fold")
		eq(p.a.texture, "Interface\\Buttons\\WHITE8x8")
		eq(sh.a.sublevel, p.a.sublevel - 1, "shadow one sublevel lower")
		same(p.a.vertexColor, { S.C.sheet[1], S.C.sheet[2], S.C.sheet[3], 1 }, "fill colour")
		same(p.c.vertexColor, { S.C.flap[1], S.C.flap[2], S.C.flap[3], 1 }, "flap colour")
		same(sh.c.vertexColor, { 0, 0, 0, 0.5 }, "shadow colour")
	end
end)

it("Style.Sheet: flap, cut and background alpha change in place; alpha leaves nothing but the sheet", function()
	local S = LoadAddon().Style
	local f = CreateFrame("Frame")
	local s = S.Sheet(f, "sheet", "flap", 22, true)
	s:SetFlap("live")
	same(s.pieces.c.vertexColor, { S.C.live[1], S.C.live[2], S.C.live[3], 1 }, "live flap")
	s:SetAlpha(0.86)
	eq(s.pieces.a.vertexColor[4], 0.86)
	eq(s.shadow.a.vertexColor[4], 0.5 * 0.86)
	s:SetCut(12)
	same({ rect(s.pieces.c, f, 200, 30) }, { 188, 0, 12, 12 }, "mini strip corner")
end)

it("Style.Pixel and rules: one physical pixel at any scale, re-snapped when the UI scale changes", function()
	local ns, stub = LoadAddon()
	local S = ns.Style
	local parent = CreateFrame("Frame")
	parent.GetEffectiveScale = function() return 0.64 end
	-- Without PixelUtil: 1 / effective scale.
	local line = S.Rule(parent, "H", S.C.rule)
	eq(line.height, 1 / 0.64)
	local v = S.Rule(parent, "V")
	eq(v.width, 1 / 0.64)
	-- With PixelUtil (the client's): its pixel-to-UI factor / effective scale; 1440p at 768 / 1440.
	PixelUtil = { GetPixelToUIUnitFactor = function() return 768 / 1440 end }
	eq(S.Pixel(parent), (768 / 1440) / 0.64)
	parent.GetEffectiveScale = function() return 1 end
	for _, f in ipairs(stub.frames) do
		if f.events.UI_SCALE_CHANGED then f.scripts.OnEvent(f, "UI_SCALE_CHANGED") end
	end
	eq(line.height, 768 / 1440)
	eq(v.width, 768 / 1440)
	PixelUtil = nil
end)

it("Style rails: one shared scale per list, zero line position, losses left in red", function()
	local S = LoadAddon().Style
	eq(S.SharedScale({ 1200, -300, 50 }), 1200)
	eq(S.SharedScale({ -900, 300 }), 900)
	eq(S.SharedScale({}), 0)
	-- 200 wide, zero at 20 %: the largest value fills from 40 to the end.
	local x, w = S.RailGeometry(1000, 1000, 200, 0.2)
	eq(x, 40); eq(w, 160)
	x, w = S.RailGeometry(500, 1000, 200, 0.2)
	eq(x, 40); eq(w, 80)
	x, w = S.RailGeometry(-100, 1000, 200, 0.2) -- same unit, left of zero
	eq(x, 24); eq(w, 16)
	x, w = S.RailGeometry(-5000, 1000, 200, 0.2) -- clamped at the rail's left end
	eq(x, 0); eq(w, 40)
	x, w = S.RailGeometry(0, 1000, 200, 0.2)
	eq(w, 0)
	x, w = S.RailGeometry(1, 100000, 200, 0) -- tiny but not zero: still one unit
	eq(x, 0); eq(w, 1)
	-- A rail in a row: colours by role.
	local row = CreateFrame("Frame")
	local rail = S.Rail(row, 0.2)
	rail.GetWidth = function() return 200 end
	rail:SetValue(500, 1000, true)
	same(rail.bar.vertexColor, { S.C.text[1], S.C.text[2], S.C.text[3], 1 }, "selected bar")
	eq(rail.bar.width, 80); eq(rail.bar.height, 4)
	eq(rail.zero.points[1][4], 40, "zero line at 20 %")
	eq(rail.zero.height, 16)
	rail:SetValue(500, 1000, false)
	same(rail.bar.vertexColor, { S.C.text2[1], S.C.text2[2], S.C.text2[3], 1 }, "other bar")
	rail:SetValue(-100, 1000, false)
	same(rail.bar.vertexColor, { S.C.danger[1], S.C.danger[2], S.C.danger[3], 1 }, "loss bar")
	eq(rail.bar.points[1][4], 24, "loss ends at the zero line")
	rail:SetValue(0, 1000)
	eq(rail.bar.shown, false)
end)

local function run(S, seconds)
	local step = S.TweenDriver.scripts.OnUpdate
	if step then step(S.TweenDriver, seconds) end
end

it("Style.Nokta hops: 160 ms scale 0 -> 11, anchored by its centre, colour from C", function()
	local S = LoadAddon().Style
	local parent = CreateFrame("Frame")
	local n = S.Nokta(parent)
	eq(n.texture, "Interface\\AddOns\\CraftWise\\Media\\cw-nokta")
	same(n.vertexColor, { S.C.nokta[1], S.C.nokta[2], S.C.nokta[3], 1 }, "turkuaz")
	local row = CreateFrame("Frame")
	n:MoveTo(row, "LEFT", 7, 0)
	eq(n.points[1][1], "CENTER")
	assert(n.width < 0.1, "starts at scale 0")
	run(S, 0.08)
	assert(n.width > 0 and n.width < 11, "half way")
	run(S, 0.08)
	eq(n.width, 11); eq(n.height, 11)
	eq(S.TweenDriver.scripts.OnUpdate, nil, "driver stops when nothing moves")
	n:SetColor("live")
	same(n.vertexColor, { S.C.live[1], S.C.live[2], S.C.live[3], 1 }, "orange")
	n:MoveTo(row, "LEFT", 7, 0, true)
	eq(n.width, 11)
end)

it("Style easing: the kit's curves start at 0, end at 1, rise monotonically", function()
	local S = LoadAddon().Style
	for name, e in pairs(S.Easing) do
		eq(e(0), 0, name); eq(e(1), 1, name)
		local last = 0
		for i = 1, 20 do
			local v = e(i / 20)
			assert(v >= last - 1e-9, name .. " not monotonic")
			last = v
		end
	end
	assert(S.Easing.fold(0.25) > 0.5, "fold rises fast")
end)

it("Style.ActionButton: action colours, dog-ear lifts 10 -> 14 on hover (140 ms), 2 units down while pressed", function()
	local S = LoadAddon().Style
	local b = S.ActionButton(UIParent, "End session")
	same(b.sheet.pieces.a.vertexColor, { S.C.action[1], S.C.action[2], S.C.action[3], 1 }, "fill")
	same(b.sheet.pieces.c.vertexColor, { S.C.actionFlap[1], S.C.actionFlap[2], S.C.actionFlap[3], 1 }, "flap")
	same(b.label.textColor, { S.C.onAction[1], S.C.onAction[2], S.C.onAction[3], 1 }, "text")
	eq(b.sheet.cut, 10); eq(b.height, 28)
	b.scripts.OnEnter(b)
	run(S, 0.07)
	assert(b.sheet.cut > 10 and b.sheet.cut < 14)
	run(S, 0.07)
	eq(b.sheet.cut, 14)
	b.scripts.OnLeave(b)
	run(S, 0.2)
	eq(b.sheet.cut, 10)
	b.scripts.OnMouseDown(b)
	run(S, 0.08)
	eq(b.offset, -2)
	eq(b.face.points[1][5], -2)
	b.scripts.OnMouseUp(b)
	run(S, 0.08)
	eq(b.offset, 0)
	local p = S.PrimaryButton(UIParent, "Start")
	same(p.sheet.pieces.a.vertexColor, { S.C.text[1], S.C.text[2], S.C.text[3], 1 }, "primary fill")
	same(p.sheet.pieces.c.vertexColor, { 1, 1, 1, 1 }, "primary flap #FFFFFF")
	eq(p.label.textColor[1], 0x14 / 255)
	eq(p.scripts.OnEnter, nil, "primary does not lift")
end)

it("Style line controls: line button, chip, segmented control, checkbox, slider", function()
	local S = LoadAddon().Style
	local C = S.C
	local b = S.LineButton(UIParent, "Price history")
	eq(b.height, 24)
	eq(b.width, 80 + 24, "text width plus 12 each side")
	same(b.border.top.vertexColor, { C.ruleStrong[1], C.ruleStrong[2], C.ruleStrong[3], 1 }, "border")
	same(b.label.textColor, { C.text2[1], C.text2[2], C.text2[3], 1 }, "text")
	b.scripts.OnEnter(b)
	same(b.border.top.vertexColor, { C.text[1], C.text[2], C.text[3], 1 }, "hovered border")
	same(b.label.textColor, { C.text[1], C.text[2], C.text[3], 1 }, "hovered text")
	b.scripts.OnLeave(b)
	b:SetOn(true)
	same(b.label.textColor, { C.text[1], C.text[2], C.text[3], 1 }, "on")
	eq(S.LineButton(UIParent, "x", nil, 26).height, 26, "header bar")
	local chip = S.Chip(UIParent, "Unlearned")
	eq(chip.width, 80 + 20)
	local _, size = chip.label:GetFont()
	eq(size, 11, "chips: Small in Bold")
	eq(chip.label:GetFont(), S.FontFiles.nextBold)

	local picked
	local seg = S.Segmented(UIParent, { "Window", "Docked left", "Docked right" }, function(i) picked = i end)
	seg:SetSelected(1)
	eq(seg.buttons[1].bg.shown, true)
	eq(seg.buttons[2].bg.shown, false)
	eq(seg.buttons[1].label.textColor[1], 0x14 / 255, "dark text on the chosen one")
	seg.buttons[3].scripts.OnClick(seg.buttons[3])
	eq(picked, 3); eq(seg.selected, 3)
	eq(seg.buttons[1].bg.shown, false)
	eq(seg.buttons[2].points[1][4], 100 - 1, "shares the border")

	local got
	local c = S.Checkbox(UIParent, "Close with Escape", false, function(v) got = v end)
	eq(c.box.width, 14); eq(c.box.height, 14)
	eq(c.tick.texture, "Interface\\AddOns\\CraftWise\\Media\\cw-check")
	eq(c.fill.shown, false)
	c.scripts.OnClick(c)
	eq(got, true); eq(c.fill.shown, true); eq(c.tick.shown, true)

	local value
	local s = S.Slider(UIParent, 180, 70, 130, 1, function(v) value = v end)
	eq(s.track.height, 2); eq(s.thumb.width, 12); eq(s.thumb.height, 14)
	s.SetValue = function(self, v) self.scripts.OnValueChanged(self, v) end -- the client fires it inside SetValue
	s:SetValueQuietly(100)
	eq(value, nil, "quiet")
	s.scripts.OnValueChanged(s, 110)
	eq(value, 110)
end)

it("Style.ScrollBar: 4 unit thumb in rule-strong, no arrows, no track art", function()
	local S = LoadAddon().Style
	local function region() return CreateFrame("Frame") end
	local bar = CreateFrame("Frame")
	bar.Back, bar.Forward = region(), region()
	bar.Track = region()
	bar.Track.Begin, bar.Track.Middle, bar.Track.End = region(), region(), region()
	bar.Track.Thumb = region()
	bar.Track.Thumb.Begin, bar.Track.Thumb.Middle, bar.Track.Thumb.End = region(), region(), region()
	local fill = S.ScrollBar(bar)
	eq(bar.Back.shown, false); eq(bar.Forward.shown, false)
	eq(bar.Track.Middle.alpha, 0); eq(bar.Track.Thumb.Begin.alpha, 0)
	eq(fill.width, 4)
	same(fill.vertexColor, { S.C.ruleStrong[1], S.C.ruleStrong[2], S.C.ruleStrong[3], 1 }, "thumb")
end)

it("Style.ShowTip: inverse tooltip, C.text sheet cut 6 with a hard shadow and dark text", function()
	local S = LoadAddon().Style
	local owner = CreateFrame("Frame")
	local t = S.ShowTip(owner, "Not listed in the last full scan", "Vendor buys it for 47s.")
	eq(t.shown, true)
	eq(t.sheet.cut, 6)
	assert(t.sheet.shadow, "hard shadow")
	same(t.sheet.pieces.a.vertexColor, { S.C.text[1], S.C.text[2], S.C.text[3], 1 }, "fill")
	eq(t.title.textColor[1], 0x14 / 255)
	eq(t.body.text, "Vendor buys it for 47s.")
	S.HideTip(CreateFrame("Frame")) -- another owner: stays
	eq(t.shown, true)
	S.HideTip(owner)
	eq(t.shown, false)
end)

it("Style.Glyph: ▲ ▼ → as tinted inline textures", function()
	local S = LoadAddon().Style
	eq(S.Glyph("up", 11, "danger"), "|TInterface\\AddOns\\CraftWise\\Media\\cw-up:11:11:0:0:16:16:0:16:0:16:255:122:99|t")
	eq(S.Glyph("down", 12, "nokta"), "|TInterface\\AddOns\\CraftWise\\Media\\cw-down:12:12:0:0:16:16:0:16:0:16:44:201:188|t")
	assert(S.Glyph("arrow"):find("cw-arrow:12:12:", 1, true), "default size 12")
end)

it("/craftwise debug style builds the preview with every control", function()
	local ns = LoadAddon()
	SlashCmdList.CRAFTWISE("debug style")
	assert(CraftWiseStylePreview, "preview frame")
	eq(CraftWiseStylePreview.shown, true)
	SlashCmdList.CRAFTWISE("debug style")
	eq(CraftWiseStylePreview.shown, false)
	assert(ns.Style, "style")
end)

-- Media files: the textures the spec lists, 32-bit uncompressed TGA with alpha, power of two.
local function tga(path)
	local f = assert(io.open(path, "rb"), path .. " missing")
	local h = f:read(18)
	f:close()
	local function u16(i) return h:byte(i) + 256 * h:byte(i + 1) end
	return { idLength = h:byte(1), colorMap = h:byte(2), type = h:byte(3), w = u16(13), h = u16(15), bpp = h:byte(17),
		alphaBits = h:byte(18) % 16 }
end

it("Media: textures are 32-bit uncompressed TGA with alpha, power-of-two, the spec's sizes", function()
	local want = { ["cw-fold"] = { 64, 64 }, ["cw-nokta"] = { 32, 32 }, ["cw-check"] = { 16, 16 },
		["cw-header-wide"] = { 1024, 64 }, ["cw-header-narrow"] = { 512, 64 }, ["cw-key-w"] = { 64, 64 },
		["cw-up"] = { 16, 16 }, ["cw-down"] = { 16, 16 }, ["cw-arrow"] = { 16, 16 } }
	for name, size in pairs(want) do
		local t = tga("CraftWise/Media/" .. name .. ".tga")
		eq(t.type, 2, name .. " uncompressed true colour")
		eq(t.colorMap, 0, name)
		eq(t.bpp, 32, name .. " 32-bit")
		eq(t.alphaBits, 8, name .. " alpha")
		eq(t.w, size[1], name .. " width"); eq(t.h, size[2], name .. " height")
	end
end)

it("Media: the fonts and their OFL licence texts are bundled", function()
	for _, name in ipairs({ "AtkinsonHyperlegibleNext-Regular.ttf", "AtkinsonHyperlegibleNext-Bold.ttf",
		"AtkinsonHyperlegibleNext-ExtraBold.ttf", "AtkinsonHyperlegibleMono-Regular.ttf",
		"AtkinsonHyperlegibleMono-SemiBold.ttf", "OFL-Next.txt", "OFL-Mono.txt" }) do
		local f = assert(io.open("CraftWise/Media/Fonts/" .. name, "rb"), name .. " missing")
		local head = f:read(4)
		f:close()
		if name:match("%.ttf$") then
			eq(head, "\0\1\0\0", name .. " is a TrueType font")
		end
	end
	local f = io.open("CraftWise/Media/Fonts/OFL-Next.txt")
	assert(f:read("*a"):find("SIL Open Font License, Version 1.1", 1, true))
	f:close()
end)
