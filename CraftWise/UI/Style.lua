-- The Velikopter Origami look for every CraftWise frame (#150, #151): colours, fonts, folded shapes,
-- the nokta, rails and controls. Pages build from these and never draw shapes by hand.
local _, ns = ...

local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\CraftWise\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8" -- client texture, referenced, never copied
Style.WHITE = WHITE
-- Own textures (tools/gen_addon_textures.py). White shapes are tinted with SetVertexColor.
Style.Media = {
	fold = MEDIA .. "cw-fold",
	nokta = MEDIA .. "cw-nokta",
	check = MEDIA .. "cw-check",
	headerWide = MEDIA .. "cw-header-wide",
	headerNarrow = MEDIA .. "cw-header-narrow",
	keyW = MEDIA .. "cw-key-w",
	up = MEDIA .. "cw-up", -- ▲, missing from the fonts
	down = MEDIA .. "cw-down", -- ▼
	arrow = MEDIA .. "cw-arrow", -- →
	gear = MEDIA .. "cw-gear", -- main window header buttons (#153)
	dock = MEDIA .. "cw-dock",
	close = MEDIA .. "cw-close",
}
local Media = Style.Media

---------------------------------------------------------------------------------------------------
-- Colours (spec: Colours). Each is { r, g, b, a, hex = "RRGGBB" }, so Style.Fill takes them as is.

local function rgb(hex, a)
	return {
		tonumber(hex:sub(1, 2), 16) / 255,
		tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255,
		a or 1,
		hex = hex,
	}
end

local C = {
	ground = rgb("121314"),
	sheet = rgb("1B1C1F"),
	card = rgb("26282C"),
	cardFlap = rgb("3C3E44"),
	flap = rgb("34363B"),
	planeA = rgb("202125"),
	planeB = rgb("25262A"),
	selected = rgb("212226"),
	rule = rgb("2E3034"),
	ruleStrong = rgb("6F7378"),
	text = rgb("ECEDEA"),
	text2 = rgb("A7AAA6"),
	text3 = rgb("8E918D"),
	nokta = rgb("2CC9BC"),
	action = rgb("E5432F"),
	actionFlap = rgb("F07A68"),
	onAction = rgb("141517"),
	danger = rgb("FF7A63"),
	live = rgb("FF8A2A"),
	keyGold = rgb("E8B94B"),
	keyGoldDark = rgb("D9A93A"),
	keyGoldLight = rgb("F8DD9E"),
	coinGold = rgb("F2C14E"),
	coinSilver = rgb("C3C9D2"),
	coinCopper = rgb("DB8A5C"),
	qPoor = rgb("9D9D9D"),
	qCommon = rgb("ECEDEA"),
	qUncommon = rgb("3BD45A"),
	qRare = rgb("4EA2FF"),
	qEpic = rgb("B86CF5"),
	skill = { orange = rgb("FF8040"), yellow = rgb("FFFF00"), green = rgb("40BF40"), grey = rgb("808080") },
	shadow = rgb("000000", 0.5),
}
Style.C = C
-- Spec values without a constant of their own: text on light sheets (primary button, inverse tooltip)
-- and the primary button's flap.
local INK = rgb("141517")
local PAPER = rgb("FFFFFF")
Style.INK, Style.PAPER = INK, PAPER

-- Item names in the quality colours (C.qPoor … C.qEpic for qualities 0-4); nil for any other quality.
local QUALITY = { [0] = C.qPoor, C.qCommon, C.qUncommon, C.qRare, C.qEpic }
function Style.QualityColor(quality)
	return QUALITY[tonumber(quality) or -1]
end

-- Style.Color("text2"), Style.Color("skill.orange"); a colour table passes through.
function Style.Color(name)
	if type(name) == "table" then
		return name
	end
	local c = C
	for part in tostring(name):gmatch("[^%.]+") do
		c = type(c) == "table" and c[part] or nil
	end
	if type(c) ~= "table" or not c.hex then
		error("CraftWise Style: unknown colour " .. tostring(name), 2)
	end
	return c
end

-- The |cff escape for FontString text: Style.Hex("danger") .. "loss|r".
function Style.Hex(name)
	return "|cff" .. Style.Color(name).hex
end

---------------------------------------------------------------------------------------------------
-- Type (spec: Type). Twelve font objects, created once; colour always comes from the FontString.

local FONTS = MEDIA .. "Fonts\\"
local NEXT = FONTS .. "AtkinsonHyperlegibleNext-Regular.ttf"
local NEXT_BOLD = FONTS .. "AtkinsonHyperlegibleNext-Bold.ttf"
local NEXT_XBOLD = FONTS .. "AtkinsonHyperlegibleNext-ExtraBold.ttf"
local MONO = FONTS .. "AtkinsonHyperlegibleMono-Regular.ttf"
local MONO_SEMI = FONTS .. "AtkinsonHyperlegibleMono-SemiBold.ttf"
Style.FontFiles = { next = NEXT, nextBold = NEXT_BOLD, nextExtraBold = NEXT_XBOLD, mono = MONO, monoSemiBold = MONO_SEMI }

Style.FontSpec = {
	{ "CraftWiseFontBrand", NEXT_XBOLD, 16 },
	{ "CraftWiseFontHero", NEXT_XBOLD, 20 },
	{ "CraftWiseFontSection", NEXT_BOLD, 13 },
	{ "CraftWiseFontBody", NEXT, 12 },
	{ "CraftWiseFontBodyBold", NEXT_BOLD, 12 },
	{ "CraftWiseFontSmall", NEXT, 11 },
	{ "CraftWiseFontLabel", NEXT_BOLD, 10 },
	{ "CraftWiseFontCaption", NEXT, 10 },
	{ "CraftWiseFontFigure", MONO, 12 },
	{ "CraftWiseFontFigureBold", MONO_SEMI, 13 },
	{ "CraftWiseFontFigureL", MONO_SEMI, 24 },
	{ "CraftWiseFontFigureXL", MONO_SEMI, 34 },
}
Style.Fonts = {} -- Style.Fonts.Body == CraftWiseFontBody
for _, f in ipairs(Style.FontSpec) do
	local font = CreateFont(f[1])
	font:SetFont(f[2], f[3], "")
	Style.Fonts[f[1]:sub(#"CraftWiseFont" + 1)] = font
end

-- A FontString in one of the fonts and colours: Style.Text(row, "Body", "text2").
function Style.Text(parent, font, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(Style.Fonts[font or "Body"])
	local c = Style.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], 1)
	return fs
end

-- Chips and buttons: CraftWiseFontSmall's size in the Bold cut (spec: "notes, chips, buttons (Bold)").
local function SmallBold(fs)
	fs:SetFontObject(Style.Fonts.Small)
	fs:SetFont(NEXT_BOLD, 11, "")
end
Style.SmallBold = SmallBold

-- ▲ ▼ → are not in Atkinson Hyperlegible: an inline texture at the text size, tinted.
-- Style.Glyph("up", 11, "danger") .. " 4 %"
function Style.Glyph(name, size, color)
	local path = assert(({ up = Media.up, down = Media.down, arrow = Media.arrow })[name], "unknown glyph")
	local c = Style.Color(color or "text")
	local s = size or 12
	return ("|T%s:%d:%d:0:0:16:16:0:16:0:16:%d:%d:%d|t"):format(path, s, s,
		math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------------------------------
-- Fills and one-pixel rules.

function Style.Fill(texture, color, alpha)
	texture:SetTexture(WHITE)
	texture:SetVertexColor(color[1], color[2], color[3], (color[4] or 1) * (alpha or 1))
end

-- One physical pixel in the region's UI units (spec: 1 unit rules stay one pixel at every UI scale).
function Style.Pixel(region)
	local scale = region and region.GetEffectiveScale and region:GetEffectiveScale()
	if type(scale) ~= "number" or scale <= 0 then
		scale = 1
	end
	if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
		return PixelUtil.GetPixelToUIUnitFactor() / scale
	end
	return 1 / scale
end

local rules = setmetatable({}, { __mode = "k" }) -- texture -> { orientation, parent }

local function SnapRule(tex, r)
	local px = Style.Pixel(r[2])
	if r[1] == "H" then
		tex:SetHeight(px)
	else
		tex:SetWidth(px)
	end
end

-- A 1 unit line: orientation "H" (caller anchors left and right) or "V" (top and bottom).
function Style.Rule(parent, orientation, color, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 0)
	Style.Fill(tex, color or C.rule)
	rules[tex] = { orientation == "V" and "V" or "H", parent }
	SnapRule(tex, rules[tex])
	return tex
end

-- Re-snap every rule; runs on UI scale and display changes. Call it after a frame:SetScale.
function Style.SnapRules()
	for tex, r in pairs(rules) do
		SnapRule(tex, r)
	end
end

local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:SetScript("OnEvent", function()
	Style.SnapRules()
end)

-- Four rules just inside the frame's edges. Returns { top, bottom, left, right, SetColor }.
function Style.Border(frame, color, layer)
	local b = {}
	b.top = Style.Rule(frame, "H", color, layer or "BORDER")
	b.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	b.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	b.bottom = Style.Rule(frame, "H", color, layer or "BORDER")
	b.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	b.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	b.left = Style.Rule(frame, "V", color, layer or "BORDER")
	b.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	b.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	b.right = Style.Rule(frame, "V", color, layer or "BORDER")
	b.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	b.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	function b.SetColor(_, c)
		for _, t in ipairs({ b.top, b.bottom, b.left, b.right }) do
			t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		end
	end
	return b
end

---------------------------------------------------------------------------------------------------
-- Motion: one OnUpdate drives every tween and stops when none runs. Easing curves from the kit.

local function Bezier(x1, y1, x2, y2)
	return function(x)
		if x <= 0 then
			return 0
		elseif x >= 1 then
			return 1
		end
		local lo, hi = 0, 1
		for _ = 1, 24 do
			local t = (lo + hi) / 2
			local u = 1 - t
			if 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t < x then
				lo = t
			else
				hi = t
			end
		end
		local t = (lo + hi) / 2
		local u = 1 - t
		return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
	end
end
Style.Easing = {
	hop = Bezier(0.3, 0, 0, 1), -- the nokta, panels sliding in
	press = Bezier(0.5, 0, 0.5, 1), -- buttons pressed
	fold = Bezier(0.2, 0.8, 0.2, 1), -- a dog-ear lifting
	linear = function(x) return math.min(math.max(x, 0), 1) end,
}

local tweens = {}
local driver = CreateFrame("Frame")
Style.TweenDriver = driver

local function Step(_, elapsed)
	for i = #tweens, 1, -1 do
		local tw = tweens[i]
		tw.t = tw.t + (elapsed or 0)
		local p = math.min(tw.t / tw.duration, 1)
		if p >= 1 then
			table.remove(tweens, i)
		end
		tw.fn(tw.ease(p))
	end
	if #tweens == 0 then
		driver:SetScript("OnUpdate", nil)
	end
end

-- Runs fn(progress 0..1) every frame for duration seconds; a new tween with the same owner and key
-- replaces the running one.
function Style.Tween(owner, key, duration, ease, fn)
	for i = #tweens, 1, -1 do
		if tweens[i].owner == owner and tweens[i].key == key then
			table.remove(tweens, i)
		end
	end
	local e = Style.Easing[ease or "linear"]
	fn(e(0))
	table.insert(tweens, { owner = owner, key = key, duration = duration, ease = e, fn = fn, t = 0 })
	driver:SetScript("OnUpdate", Step)
end

---------------------------------------------------------------------------------------------------
-- Background alpha per window (#162; Settings > Look and > Loot toast). db.settings.alpha[window] is
-- applied to the window's sheet, card and plane textures only: text, icons, rails and the nokta stay at
-- alpha 1. A window's frame carries frame.cwWindow = "main" | "farm"; every Style.Sheet and header plane
-- created under it follows. The loot toast sets its strips itself (LootToast.Render) from the same value.

Style.WINDOW_ALPHA = { main = 0.96, farm = 0.86, toast = 0.70 } -- defaults (spec: Colours)
Style.windowSheets = setmetatable({}, { __mode = "k" })
Style.windowPlanes = setmetatable({}, { __mode = "k" })

-- The alpha of a window: the saved value clamped to 0..1, the default when none (or not a number).
function Style.WindowAlpha(window)
	local set = ns.db and ns.db.settings
	local a = set and type(set.alpha) == "table" and tonumber(set.alpha[window])
	if not a then
		return Style.WINDOW_ALPHA[window] or 1
	end
	return math.min(math.max(a, 0), 1)
end

-- Which window a frame belongs to: its own cwWindow, else its nearest parent's; nil outside the windows.
function Style.WindowOf(frame)
	local f, guard = frame, 0
	while f and guard < 64 do
		if f.cwWindow then
			return f.cwWindow
		end
		f = f.GetParent and f:GetParent() or f.parent
		guard = guard + 1
	end
end

-- Puts a window's alpha on every sheet and plane under it.
function Style.ApplyWindowAlpha(window)
	local a = Style.WindowAlpha(window)
	for s in pairs(Style.windowSheets) do
		if s.window == window then
			s:SetAlpha(a)
		end
	end
	for t in pairs(Style.windowPlanes) do
		if t.cwWindow == window then
			t:SetAlpha(a)
		end
	end
end

-- Saves (clamped to 0..1, 2 decimals) and applies. Returns the stored value.
function Style.SetWindowAlpha(window, value)
	local v = math.floor(math.min(math.max(tonumber(value) or Style.WINDOW_ALPHA[window] or 1, 0), 1) * 100 + 0.5) / 100
	local set = ns.db.settings
	if type(set.alpha) ~= "table" then
		set.alpha = {}
	end
	set.alpha[window] = v
	Style.ApplyWindowAlpha(window)
	return v
end

---------------------------------------------------------------------------------------------------
-- Folded sheet (spec: Shapes and textures). A = left part, full height, width w - cut; B = right strip,
-- width cut, from cut below the top; C = the cut x cut corner with cw-fold in the flap colour. The
-- shadow is the same three pieces in C.shadow, offset (3, -3), one sublevel lower.

local Sheet = {}
Sheet.__index = Sheet
local SHEET_SUBLEVEL = -7

local function Pieces(frame, sublevel)
	local p = {}
	for _, k in ipairs({ "a", "b", "c" }) do
		p[k] = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	end
	p.a:SetTexture(WHITE)
	p.b:SetTexture(WHITE)
	p.c:SetTexture(Media.fold)
	return p
end

local function Place(frame, p, cut, dx, dy)
	p.a:ClearAllPoints()
	p.a:SetPoint("TOPLEFT", frame, "TOPLEFT", dx, dy)
	p.a:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dx - cut, dy)
	p.b:ClearAllPoints()
	p.b:SetPoint("TOPLEFT", frame, "TOPRIGHT", dx - cut, dy - cut)
	p.b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dx, dy)
	p.c:ClearAllPoints()
	p.c:SetPoint("TOPRIGHT", frame, "TOPRIGHT", dx, dy)
	p.c:SetSize(cut, cut)
end

local function Tint(p, fill, flap, alpha)
	local a = alpha or 1
	p.a:SetVertexColor(fill[1], fill[2], fill[3], (fill[4] or 1) * a)
	p.b:SetVertexColor(fill[1], fill[2], fill[3], (fill[4] or 1) * a)
	p.c:SetVertexColor(flap[1], flap[2], flap[3], (flap[4] or 1) * a)
end

-- Style.Sheet(frame, C.sheet, C.flap, 22, true). Returns the sheet; frame.cwSheet points at it too.
function Style.Sheet(frame, fill, flap, cut, shadow)
	local s = setmetatable({ frame = frame, alpha = 1 }, Sheet)
	s.pieces = Pieces(frame, SHEET_SUBLEVEL)
	if shadow then
		s.shadow = Pieces(frame, SHEET_SUBLEVEL - 1)
	end
	s.fill, s.flap = Style.Color(fill or C.sheet), Style.Color(flap or C.flap)
	-- Inside a window that has a background alpha (frame.cwWindow, set on the window's frame) the sheet
	-- follows it from the start; elsewhere it stays at 1 (the toast sets its own per line).
	local window = Style.WindowOf(frame)
	if window then
		s.window, s.alpha = window, Style.WindowAlpha(window)
		Style.windowSheets[s] = true
	end
	s:SetCut(cut or 22)
	s:Paint()
	frame.cwSheet = s
	return s
end

function Sheet:SetCut(cut)
	self.cut = cut
	Place(self.frame, self.pieces, cut, 0, 0)
	if self.shadow then
		Place(self.frame, self.shadow, cut, 3, -3)
	end
end

function Sheet:Paint()
	Tint(self.pieces, self.fill, self.flap, self.alpha)
	if self.shadow then
		Tint(self.shadow, C.shadow, C.shadow, self.alpha)
	end
end

function Sheet:SetColors(fill, flap)
	self.fill = Style.Color(fill or self.fill)
	self.flap = Style.Color(flap or self.flap)
	self:Paint()
end

-- The dog-ear alone carries state on the farm tracker (orange running, rule-strong paused).
function Sheet:SetFlap(flap)
	self:SetColors(nil, flap)
end

-- Background transparency (Settings › Look): sheet and shadow only, never text, rails or the nokta.
function Sheet:SetAlpha(alpha)
	self.alpha = alpha
	self:Paint()
end

function Sheet:SetShown(shown)
	for _, set in ipairs({ self.pieces, self.shadow }) do
		for _, k in ipairs({ "a", "b", "c" }) do
			set[k]:SetShown(shown)
		end
	end
end

-- Header planes, baked: drawn over the whole header (880 x 56 window, 380 x 64 docked).
function Style.HeaderArt(frame, narrow)
	local t = frame:CreateTexture(nil, "BACKGROUND", nil, SHEET_SUBLEVEL + 1)
	t:SetTexture(narrow and Media.headerNarrow or Media.headerWide)
	t:SetAllPoints(frame)
	local window = Style.WindowOf(frame)
	if window then
		t.cwWindow = window
		t:SetAlpha(Style.WindowAlpha(window))
		Style.windowPlanes[t] = true
	end
	return t
end

-- The W key (icon, minimap, compartment); 64 x 64 art, drawn at any size.
function Style.KeyIcon(parent, size, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(Media.keyW)
	t:SetSize(size or 30, size or 30)
	return t
end

---------------------------------------------------------------------------------------------------
-- Nokta: the turkuaz diamond for "here" (orange for live). MoveTo hops it to a new spot with a 160 ms
-- scale 0 -> 1, no fade. It is anchored by its centre so it grows from the middle.

local NOKTA = 11

local function NoktaMoveTo(self, relativeTo, relativePoint, x, y, instant)
	self:ClearAllPoints()
	self:SetPoint("CENTER", relativeTo, relativePoint or "CENTER", x or 0, y or 0)
	self:Show()
	if instant then
		self:SetSize(NOKTA, NOKTA)
		return
	end
	Style.Tween(self, "hop", 0.16, "hop", function(p)
		local s = math.max(NOKTA * p, 0.01)
		self:SetSize(s, s)
	end)
end

local function NoktaSetColor(self, color)
	local c = Style.Color(color)
	self:SetVertexColor(c[1], c[2], c[3], 1)
end

function Style.Nokta(parent, color)
	local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
	t:SetTexture(Media.nokta)
	t:SetSize(NOKTA, NOKTA)
	t.MoveTo = NoktaMoveTo
	t.SetColor = NoktaSetColor
	t:SetColor(color or C.nokta)
	return t
end

---------------------------------------------------------------------------------------------------
-- Rails: 4 unit bars on one shared axis per list. The largest absolute value fills the rail from the
-- zero line to the right end; losses run left of the zero line in C.danger (clamped at the left end).

-- The shared scale of a list: its largest absolute value.
function Style.SharedScale(values)
	local m = 0
	for _, v in pairs(values) do
		if type(v) == "number" and math.abs(v) > m then
			m = math.abs(v)
		end
	end
	return m
end

-- Where a value's bar sits on a rail of this width: left offset and width (0 = no bar).
function Style.RailGeometry(value, maxAbs, width, zeroAt)
	local zero = (zeroAt or 0) * width
	if not value or value == 0 or not maxAbs or maxAbs <= 0 or width <= 0 then
		return zero, 0
	end
	local unit = (width - zero) / maxAbs
	local w = math.abs(value) * unit
	if value < 0 then
		w = math.min(w, zero)
		if w > 0 and w < 1 then
			w = math.min(1, zero)
		end
		return zero - w, w
	end
	return zero, math.max(math.min(w, width - zero), 1)
end

local Rail = {}

function Rail:SetValue(value, maxAbs, selected)
	self.value, self.maxAbs, self.selected = value, maxAbs, selected
	self:Relayout()
end

function Rail:Relayout()
	local width = self:GetWidth() or 0
	local zero = (self.zeroAt or 0) * width
	self.zero:ClearAllPoints()
	self.zero:SetPoint("LEFT", self, "LEFT", zero, 0)
	local x, w = Style.RailGeometry(self.value, self.maxAbs, width, self.zeroAt)
	if w <= 0 then
		self.bar:Hide()
		return
	end
	local c = (self.value or 0) < 0 and C.danger or (self.selected and C.text or C.text2)
	self.bar:SetVertexColor(c[1], c[2], c[3], 1)
	self.bar:ClearAllPoints()
	self.bar:SetPoint("LEFT", self, "LEFT", x, 0)
	self.bar:SetSize(w, 4)
	self.bar:Show()
end

-- A rail inside a row; the caller anchors and sizes it. zeroAt: where zero sits (0.18 on Craft).
function Style.Rail(parent, zeroAt)
	local r = CreateFrame("Frame", nil, parent)
	for k, f in pairs(Rail) do
		r[k] = f
	end
	r.zeroAt = zeroAt or 0
	r.axis = Style.Rule(r, "H", C.rule, "ARTWORK", 0)
	r.axis:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.axis:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.zero = Style.Rule(r, "V", C.ruleStrong, "ARTWORK", 1)
	r.zero:SetHeight(16)
	r.bar = r:CreateTexture(nil, "ARTWORK", nil, 2)
	r.bar:SetTexture(WHITE)
	r.bar:Hide()
	r:SetScript("OnSizeChanged", function(self)
		self:Relayout()
	end)
	return r
end

---------------------------------------------------------------------------------------------------
-- Controls (spec: Controls).

-- Line button and chip: 1 unit border C.ruleStrong, text C.text2; on or hovered: border and text C.text.
-- Filled (segmented control's choice): C.text with dark text.
local function PaintLine(b)
	local lit = b.on or b.hover
	local border, text = lit and C.text or C.ruleStrong, lit and C.text or C.text2
	if b.filled then
		border, text = C.text, INK
	end
	b.border:SetColor(border)
	b.label:SetTextColor(text[1], text[2], text[3], 1)
	b.bg:SetShown(b.filled and true or false)
end

local function LineControl(parent, text, pad, width, height)
	local b = CreateFrame("Button", nil, parent)
	b.pad, b.autoWidth = pad, not width
	b:SetHeight(height or 24)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	Style.Fill(b.bg, C.text)
	b.border = Style.Border(b, C.ruleStrong)
	b.label = b:CreateFontString(nil, "OVERLAY")
	SmallBold(b.label)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	function b:SetLabel(t)
		self.label:SetText(t or "")
		if self.autoWidth then
			self.cwWidth = math.floor((self.label:GetStringWidth() or 0) + 2 * self.pad + 0.5)
			self:SetWidth(self.cwWidth)
		end
	end
	function b:SetOn(on)
		self.on = on and true or false
		PaintLine(self)
	end
	function b:SetFilled(filled)
		self.filled = filled and true or false
		PaintLine(self)
	end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		PaintLine(self)
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		PaintLine(self)
	end)
	if width then
		b.cwWidth = width
		b:SetWidth(width)
	end
	b:SetLabel(text)
	PaintLine(b)
	return b
end

-- Height 24 (26 in the header bar). Width from the text when nil. Tooltips: b:HookScript("OnEnter", ...).
function Style.LineButton(parent, text, width, height)
	return LineControl(parent, text, 12, width, height)
end

function Style.Chip(parent, text, height)
	return LineControl(parent, text, 10, nil, height)
end

-- Segmented control: line buttons side by side sharing their borders; the chosen one filled.
-- onSelect(index) on a click. seg:SetSelected(index) sets it without the callback.
function Style.Segmented(parent, labels, onSelect, height)
	local seg = CreateFrame("Frame", nil, parent)
	seg:SetHeight(height or 24)
	seg.buttons = {}
	local x, overlap = 0, Style.Pixel(parent)
	for i, label in ipairs(labels) do
		local b = LineControl(seg, label, 10, nil, height)
		b:SetPoint("TOPLEFT", seg, "TOPLEFT", x, 0)
		x = x + b.cwWidth - overlap
		b:SetScript("OnClick", function()
			seg:SetSelected(i)
			if onSelect then
				onSelect(i)
			end
		end)
		seg.buttons[i] = b
	end
	seg:SetWidth(x + overlap)
	function seg:SetSelected(index)
		self.selected = index
		for i, b in ipairs(self.buttons) do
			b:SetFilled(i == index)
			b:SetFrameLevel((self:GetFrameLevel() or 0) + (i == index and 2 or 1))
		end
	end
	return seg
end

-- Folded button: action (C.action, flap C.actionFlap, text C.onAction; the dog-ear lifts 10 -> 14 on
-- hover in 140 ms) and primary (C.text, flap #FFFFFF, text #141517). Both move 2 units down while
-- pressed (80 ms).
local function FoldedButton(parent, text, width, height, fill, flap, ink, lift)
	local b = CreateFrame("Button", nil, parent)
	b.autoWidth = not width
	b:SetHeight(height or 28)
	b.face = CreateFrame("Frame", nil, b)
	b.face:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.face:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.sheet = Style.Sheet(b.face, fill, flap, 10, false)
	b.label = b.face:CreateFontString(nil, "OVERLAY")
	SmallBold(b.label)
	b.label:SetTextColor(ink[1], ink[2], ink[3], 1)
	b.label:SetPoint("CENTER", b.face, "CENTER", 0, 0)
	function b:SetLabel(t)
		self.label:SetText(t or "")
		if self.autoWidth then
			self:SetWidth(math.floor((self.label:GetStringWidth() or 0) + 28 + 0.5))
		end
	end
	local function press(self, down)
		local from = self.offset or 0
		local to = down and -2 or 0
		Style.Tween(self, "press", 0.08, "press", function(p)
			self.offset = from + (to - from) * p
			self.face:ClearAllPoints()
			self.face:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.offset)
			self.face:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, self.offset)
		end)
	end
	b:SetScript("OnMouseDown", function(self)
		press(self, true)
	end)
	b:SetScript("OnMouseUp", function(self)
		press(self, false)
	end)
	if lift then
		local function fold(self, cut)
			local from = self.sheet.cut
			Style.Tween(self, "fold", 0.14, "fold", function(p)
				self.sheet:SetCut(from + (cut - from) * p)
			end)
		end
		b:SetScript("OnEnter", function(self)
			fold(self, 14)
		end)
		b:SetScript("OnLeave", function(self)
			fold(self, 10)
		end)
	end
	if width then
		b:SetWidth(width)
	end
	b:SetLabel(text)
	return b
end

function Style.ActionButton(parent, text, width, height)
	return FoldedButton(parent, text, width, height, C.action, C.actionFlap, C.onAction, true)
end

function Style.PrimaryButton(parent, text, width, height)
	return FoldedButton(parent, text, width, height, C.text, PAPER, INK, false)
end

-- Checkbox: 14 x 14 line square; checked = filled C.text with cw-check. Label in Body, 8 to the right.
-- onChange(checked) on a click; the label is part of the click area.
function Style.Checkbox(parent, label, checked, onChange)
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(18)
	c.box = CreateFrame("Frame", nil, c)
	c.box:SetSize(14, 14)
	c.box:SetPoint("LEFT", c, "LEFT", 0, 0)
	c.fill = c.box:CreateTexture(nil, "BACKGROUND")
	c.fill:SetAllPoints(c.box)
	Style.Fill(c.fill, C.text)
	c.border = Style.Border(c.box, C.ruleStrong)
	c.tick = c.box:CreateTexture(nil, "ARTWORK")
	c.tick:SetTexture(Media.check)
	c.tick:SetVertexColor(INK[1], INK[2], INK[3], 1)
	c.tick:SetSize(9, 9)
	c.tick:SetPoint("CENTER", c.box, "CENTER", 0, 0)
	c.text = Style.Text(c, "Body", "text")
	c.text:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
	c.text:SetText(label or "")
	c:SetWidth(22 + (c.text:GetStringWidth() or 0))
	local function paint(self)
		local lit = self.checked or self.hover
		self.border:SetColor(lit and C.text or C.ruleStrong)
		self.fill:SetShown(self.checked)
		self.tick:SetShown(self.checked)
	end
	function c:SetChecked(v)
		self.checked = v and true or false
		paint(self)
	end
	function c:GetChecked()
		return self.checked
	end
	c:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if onChange then
			onChange(self.checked)
		end
	end)
	c:SetScript("OnEnter", function(self)
		self.hover = true
		paint(self)
	end)
	c:SetScript("OnLeave", function(self)
		self.hover = false
		paint(self)
	end)
	c:SetChecked(checked)
	return c
end

-- Slider: 2 unit track C.ruleStrong, filled part C.text, thumb 12 x 14 C.text. onChange(value) when the
-- user drags; s:SetValueQuietly(v) moves it without the callback.
function Style.Slider(parent, width, minValue, maxValue, step, onChange)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width or 180, 14)
	s:SetMinMaxValues(minValue or 0, maxValue or 1)
	s:SetValueStep(step or 1)
	s:SetObeyStepOnDrag(true)
	s:EnableMouse(true)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	Style.Fill(s.track, C.ruleStrong)
	s.track:SetHeight(2)
	s.track:SetPoint("LEFT", s, "LEFT", 0, 0)
	s.track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	s.thumb = s:CreateTexture(nil, "OVERLAY")
	Style.Fill(s.thumb, C.text)
	s.thumb:SetSize(12, 14)
	s:SetThumbTexture(s.thumb)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	Style.Fill(s.fill, C.text)
	s.fill:SetHeight(2)
	s.fill:SetPoint("LEFT", s.track, "LEFT", 0, 0)
	s.fill:SetPoint("RIGHT", s.thumb, "CENTER", 0, 0)
	function s:SetValueQuietly(v)
		self.quiet = true
		self:SetValue(v)
		self.quiet = false
	end
	s:SetScript("OnValueChanged", function(self, value)
		if not self.quiet and onChange then
			onChange(value)
		end
	end)
	return s
end

-- Scroll bar: restyles a MinimalScrollBar (the ScrollBox's bar) to a 4 unit thumb in C.ruleStrong with
-- no arrows and no track art.
function Style.ScrollBar(bar)
	for _, stepper in pairs({ back = bar.Back, forward = bar.Forward }) do
		stepper:Hide()
	end
	local track = assert(bar.Track and bar.Track.Thumb, "Style.ScrollBar expects a MinimalScrollBar") and bar.Track
	track:ClearAllPoints()
	track:SetPoint("TOP", bar, "TOP", 0, 0)
	track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
	for _, region in pairs({ b = track.Begin, m = track.Middle, e = track.End }) do
		region:SetAlpha(0)
	end
	local thumb = track.Thumb
	for _, region in pairs({ b = thumb.Begin, m = thumb.Middle, e = thumb.End }) do
		region:SetAlpha(0) -- the template swaps their atlases on hover; alpha 0 stays
	end
	local fill = thumb:CreateTexture(nil, "OVERLAY")
	Style.Fill(fill, C.ruleStrong)
	fill:SetWidth(4)
	fill:SetPoint("TOP", thumb, "TOP", 0, 0)
	fill:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
	bar.cwThumb = fill
	return fill
end

-- Inverse tooltip for our own cells (not item tooltips): C.text sheet, #141517 text, cut 6, hard shadow.
-- Style.ShowTip(owner, "Not listed in the last full scan", "Vendor buys it for 47s.") / Style.HideTip().
local TIP_WIDTH, TIP_PAD_X, TIP_PAD_Y = 280, 10, 8
local tip

local function Tip()
	if tip then
		return tip
	end
	tip = CreateFrame("Frame", "CraftWiseInverseTip", UIParent)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetClampedToScreen(true)
	tip.sheet = Style.Sheet(tip, C.text, PAPER, 6, true)
	tip.title = tip:CreateFontString(nil, "OVERLAY")
	SmallBold(tip.title)
	tip.body = tip:CreateFontString(nil, "OVERLAY")
	tip.body:SetFontObject(Style.Fonts.Small)
	for _, fs in ipairs({ tip.title, tip.body }) do
		fs:SetTextColor(INK[1], INK[2], INK[3], 1)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
	end
	tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD_X, -TIP_PAD_Y)
	tip.body:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, 0)
	tip:Hide()
	return tip
end

function Style.ShowTip(owner, title, ...)
	local t = Tip()
	local lines = { ... }
	t.title:SetText(title or "")
	t.body:SetText(table.concat(lines, "\n"))
	local w = 0
	for _, fs in ipairs({ t.title, t.body }) do
		fs:SetWidth(TIP_WIDTH)
		w = math.max(w, math.min(fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0, TIP_WIDTH))
	end
	t.title:SetWidth(w)
	t.body:SetWidth(w)
	t:SetSize(w + 2 * TIP_PAD_X, (t.title:GetStringHeight() or 0) + (t.body:GetStringHeight() or 0) + 2 * TIP_PAD_Y)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6)
	t.owner = owner
	t:Show()
	return t
end

function Style.HideTip(owner)
	if tip and (not owner or tip.owner == owner) then
		tip:Hide()
		tip.owner = nil
	end
end

---------------------------------------------------------------------------------------------------
-- `/craftwise debug style`: one sheet with every font, shape and control, for the in-game checks
-- (docs/ingame-checks.md, #151). Not a feature; it goes when the new windows use all of these.

local preview

function Style.Preview()
	if preview then
		preview:SetShown(not preview:IsShown())
		return
	end
	local f = CreateFrame("Frame", "CraftWiseStylePreview", UIParent)
	preview = f
	f:SetSize(640, 520)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	table.insert(UISpecialFrames, "CraftWiseStylePreview")
	Style.Sheet(f, C.sheet, C.flap, 22, true)

	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	head:SetHeight(56)
	Style.HeaderArt(head)
	local key = Style.KeyIcon(head, 30)
	key:SetPoint("LEFT", head, "LEFT", 14, 0)
	local brand = Style.Text(head, "Brand", INK)
	brand:SetPoint("LEFT", key, "RIGHT", 10, 0)
	brand:SetText("CraftWise")
	local close = Style.LineButton(head, "Close", nil, 26)
	close:SetPoint("RIGHT", head, "RIGHT", -30, 0)
	close:SetScript("OnClick", function()
		f:Hide()
	end)

	-- Fonts, one line each, then the glyphs and coin colours.
	local y = -68
	for i, spec in ipairs(Style.FontSpec) do
		local name = spec[1]:sub(#"CraftWiseFont" + 1)
		local fs = Style.Text(f, name, i % 2 == 0 and "text2" or "text")
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", 22, y)
		fs:SetText(name .. " " .. spec[3] .. "  Dusky Belt 12g 40s")
		y = y - math.max(spec[3] + 6, 16)
	end
	local glyphs = Style.Text(f, "Figure", "text")
	glyphs:SetPoint("TOPLEFT", f, "TOPLEFT", 22, y - 4)
	glyphs:SetText(Style.Glyph("up", 12, "danger") .. " 4 %  " .. Style.Glyph("down", 12, "nokta") .. " 3 %  1g 50s "
		.. Style.Glyph("arrow", 12, "text2") .. " 2g 70s  · − ×  " .. Style.Hex("coinGold") .. "12g|r "
		.. Style.Hex("coinSilver") .. "40s|r " .. Style.Hex("coinCopper") .. "20c|r")

	-- Controls, right column.
	local x0 = 360
	local function at(region, dy)
		region:SetPoint("TOPLEFT", f, "TOPLEFT", x0, dy)
	end
	at(Style.LineButton(f, "Price history"), -70)
	local chip = Style.Chip(f, "Hide unpriced")
	chip:SetOn(true)
	chip:SetScript("OnClick", function(self)
		self:SetOn(not self.on)
	end)
	at(chip, -102)
	local seg = Style.Segmented(f, { "Window", "Docked left", "Docked right" })
	seg:SetSelected(1)
	at(seg, -134)
	at(Style.Checkbox(f, "Close with Escape", true), -166)
	local slider = Style.Slider(f, 180, 70, 130, 1)
	slider:SetValueQuietly(100)
	at(slider, -196)
	at(Style.ActionButton(f, "End session"), -222)
	at(Style.PrimaryButton(f, "Start"), -258)
	local small = Style.KeyIcon(f, 20)
	at(small, -294)

	-- A card with rails on one shared scale; click a row to hop the nokta, hover for the inverse tooltip.
	local card = CreateFrame("Frame", nil, f)
	card:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -330)
	card:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 22)
	Style.Sheet(card, C.card, C.cardFlap, 14, false)
	local values = { 12025, 6820, -840, 1850 }
	local scale = Style.SharedScale(values)
	local nokta = Style.Nokta(card)
	local rows = {}
	for i, v in ipairs(values) do
		local row = CreateFrame("Button", nil, card)
		row:SetHeight(36)
		row:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -8 - (i - 1) * 36)
		row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -8 - (i - 1) * 36)
		local name = Style.Text(row, "Body", i == 3 and "skill.grey" or "skill.yellow")
		name:SetPoint("LEFT", row, "LEFT", 18, 0)
		name:SetText(({ "Dusky Belt", "Barbaric Harness", "Barbaric Shoulders", "Guardian Cloak" })[i])
		row.rail = Style.Rail(row, 0.18)
		row.rail:SetPoint("TOPLEFT", row, "TOPLEFT", 190, 0)
		row.rail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -110, 0)
		local fig = Style.Text(row, "FigureBold", v < 0 and "danger" or "text")
		fig:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		fig:SetText(v < 0 and ("−" .. (-v)) or ("+" .. v))
		local hair = Style.Rule(row, "H", C.rule)
		hair:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		hair:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
		row:SetScript("OnClick", function(self)
			for j, r in ipairs(rows) do
				r.rail:SetValue(values[j], scale, r == self)
			end
			nokta:MoveTo(self, "LEFT", 6, 0)
		end)
		row:SetScript("OnEnter", function(self)
			Style.ShowTip(self, "Not listed in the last full scan", "Vendor buys it for 47s.", "Last AH price: 1g 92s, 9 days ago.")
		end)
		row:SetScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
		rows[i] = row
		row.rail:SetValue(v, scale, i == 1)
	end
	nokta:MoveTo(rows[1], "LEFT", 6, 0, true)
	f:Show()
end
