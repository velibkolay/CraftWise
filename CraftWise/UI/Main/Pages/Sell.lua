-- Main window, section Sell (#155; spec in #150 "Sell: Bags, Auctions, Ledger", boards "Sell › Bags",
-- "Sell › Auctions", "Sell › Ledger"): what the three pages share. Money texts, item names, the
-- "label over figure" blocks of the hero cards and the split bar. Pages: Pages/Bags.lua, Auctions.lua,
-- Ledger.lua (they load after this file).
local _, ns = ...
local M = ns.Main
local Style = ns.Style
local C = Style.C

local S = {}
M.Sell = S

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

-- Coin digits ("12g 40s"); nil stays nil.
function S.Coins(copper)
	return copper and ns.FormatCoins(copper) or nil
end

-- Signed coin digits for changes: "+12g 30s", "−8s 90c", "0c"; nil stays nil.
function S.Signed(copper)
	if copper == nil then
		return nil
	end
	if copper > 0 then
		return "+" .. ns.FormatCoins(copper)
	end
	return ns.FormatCoins(copper) -- carries the − itself
end

-- "1 item", "3 items".
function S.Count(n, one, many)
	return ("%d %s"):format(n, n == 1 and one or many)
end

-- An item's name and quality: the client's, else the name kept with the record (ledger entry,
-- auction), else "item <id>". stored = { name, link }.
function S.ItemName(itemID, stored)
	stored = stored or {}
	local name, quality
	if itemID and C_Item and C_Item.GetItemInfo then
		local n, _, q = C_Item.GetItemInfo(itemID)
		name, quality = n, q
	end
	if not name and itemID and ns.ItemInfoNow then
		name = ns.ItemInfoNow(itemID)
	end
	if not name and type(stored.link) == "string" then
		name = stored.link:match("|h%[(.-)%]|h")
	end
	return name or stored.name or (itemID and ("item " .. tostring(itemID))) or "?", quality
end

-- Colour name for an item name: its quality colour, else C.text.
function S.QualityColor(quality)
	return Style.QualityColor(quality) or "text"
end

-- Items the client hasn't loaded: asked for once, the window refreshes when they arrive.
local requested = {}
function S.LoadNames(ids)
	local missing = {}
	for _, id in ipairs(ids) do
		if id and not requested[id] then
			requested[id] = true
			if not (ns.ItemInfoNow and ns.ItemInfoNow(id)) then
				missing[#missing + 1] = id
			end
		end
	end
	if #missing > 0 and ns.WithItemNames then
		ns.WithItemNames(missing, function()
			M.Refresh()
		end)
	end
end

----------------------------------------------------------------------------------------------------
-- Drawing: a "label over figure" block (hero cards, boards "Sell › Bags", "Sell › Ledger",
-- "Sell › Auctions"). big = the card's main figure (FigureL); otherwise a part (FigureBold). An optional
-- 8 unit legend square before the label (the Bags split), a unit word after the figure ("1 item") and
-- a caption under it.
----------------------------------------------------------------------------------------------------

local Stat = {}

function Stat:Set(label, figure, caption, square, unit)
	self.label:ClearAllPoints()
	self.label:SetPoint("TOPLEFT", self, "TOPLEFT", square and 13 or 0, 0)
	self.label:SetText(label or "")
	self.square:SetShown(square ~= nil)
	if square then
		local c = Style.Color(square)
		self.square:SetVertexColor(c[1], c[2], c[3], 1)
	end
	self.figure:SetText(figure or M.DASH)
	self.unit:SetText(unit or "")
	self.unit:SetShown(unit ~= nil)
	self.caption:SetText(caption or "")
	self.caption:SetShown((caption or "") ~= "")
end

function S.Stat(parent, big)
	local s = CreateFrame("Frame", nil, parent)
	for k, fn in pairs(Stat) do
		s[k] = fn
	end
	s:SetSize(150, 40)
	s.square = s:CreateTexture(nil, "ARTWORK")
	s.square:SetTexture(Style.WHITE)
	s.square:SetSize(8, 8)
	s.square:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -1)
	s.label = Style.Text(s, big and "Label" or "Caption", "text3")
	s.label:SetJustifyH("LEFT")
	s.figure = Style.Text(s, big and "FigureL" or "FigureBold", "text")
	s.figure:SetJustifyH("LEFT")
	s.figure:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -14)
	s.unit = Style.Text(s, "Body", "text2")
	s.unit:SetPoint("BOTTOMLEFT", s.figure, "BOTTOMRIGHT", 4, 2)
	s.caption = Style.Text(s, "Caption", "text3")
	s.caption:SetJustifyH("LEFT")
	s.caption:SetPoint("TOPLEFT", s.figure, "BOTTOMLEFT", 0, -2)
	s:Set()
	return s
end

-- The split bar (board "Sell › Bags": 6 tall, 2 unit gaps): x and width of each part with a share > 0,
-- in order, over `width`. parts = { { key, share } }. Pure.
function S.SplitGeometry(parts, width, gap)
	gap = gap or 2
	local shown = {}
	for _, p in ipairs(parts) do
		if (p.share or 0) > 0 then
			shown[#shown + 1] = p
		end
	end
	local room = width - gap * math.max(#shown - 1, 0)
	local out, x = {}, 0
	for i, p in ipairs(shown) do
		local w = i == #shown and (width - x) or math.max(math.floor(room * p.share + 0.5), 1)
		out[#out + 1] = { key = p.key, x = x, width = math.max(w, 1) }
		x = x + w + gap
	end
	return out
end

-- A split bar inside parent: bar:Set(parts, width), parts = { { key, share, color } }.
function S.SplitBar(parent, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 6)
	bar.pieces = {}
	function bar:Set(parts, width)
		local colors = {}
		for _, p in ipairs(parts) do
			colors[p.key] = p.color
		end
		self.geometry = S.SplitGeometry(parts, width)
		for i, g in ipairs(self.geometry) do
			local t = self.pieces[i]
			if not t then
				t = self:CreateTexture(nil, "ARTWORK")
				self.pieces[i] = t
			end
			Style.Fill(t, Style.Color(colors[g.key] or C.text))
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", self, "TOPLEFT", g.x, 0)
			t:SetSize(g.width, height or 6)
			t.key = g.key
			t:Show()
		end
		for i = #self.geometry + 1, #self.pieces do
			self.pieces[i]:Hide()
		end
	end
	return bar
end

-- Width of the hero card's inside in a layout (metrics): the window's width less margins and padding.
function S.HeroInner(ctx)
	local m = ctx and ctx.metrics or {}
	return (m.width or 880) - 2 * (m.pad or 22) - 2 * (m.heroPadX or 16)
end

-- A line tag (the user's mark on a Bags row; board: 1 unit C.ruleStrong border, Label in C.text2).
function S.Tag(parent)
	local t = CreateFrame("Frame", nil, parent)
	t:SetHeight(16)
	t.border = Style.Border(t, C.ruleStrong)
	t.label = Style.Text(t, "Label", "text2")
	t.label:SetPoint("CENTER", t, "CENTER", 0, 0)
	function t:SetLabel(text)
		self.label:SetText(text or "")
		self:SetWidth(math.floor((self.label:GetStringWidth() or 0) + 12 + 0.5))
	end
	return t
end

