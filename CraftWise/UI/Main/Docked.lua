-- Main window, docked layout (#161; spec in #150 "Main window shell", Docked column; board "Docked layout,
-- on your screen"): the same window as a 380 wide sheet on the left or right screen edge, 20 from the edge,
-- top and bottom 20. Header 64 (key block 120 with the W icon 34, title and AH status stacked at x 128,
-- gear, undock and close), the section tabs on their own row (gap 20), a sub bar 40 (padding 18) whose
-- page tools move into the list header, a stacked hero card, two-line rows 44 (List.lua), footer 28.
-- The dock button, Shift-click on the minimap and Settings › Look › Layout swap layouts in place; the
-- sheet slides in from its edge (200 ms). The layout is saved in db.settings.ui.layout (Shell.lua).
--
-- Frame.lua draws both layouts from the metrics (m.docked picks the docked arrangement of the body);
-- this file registers the two layouts and arranges the parts that differ (header, tabs, position).
-- Pages draw their own docked parts from ctx.metrics.docked (M.IsDocked): DockedRow, DockedInitRow and
-- DockedHero in the page registry (Shell.lua contract), the custom pages in their Refresh.
--
-- Provisional choices (#161, posted to the designer on the spec doc; no board covers these yet). Each
-- lives in one place, named "Provisional (#161 Qn)" there:
--   Q1 Look up › Items: the list, and a row click swaps to a full-width card with Back in the sub bar;
--      search box in the sub bar, chips in the list header.          -> Pages/Items.lua, Items.Docked*
--   Q2 Settings: one scrolling list, group titles as group headers (like Bags), the label over its
--      control, wide controls (segmented) across the row.            -> Pages/Settings.lua, Set.Docked*
--   Q3 Music: each profession row stacks: Song, Video, Next cast, then volume. -> Pages/Music.lua, DockedRows
--   Q4 Multi-card heroes (Auctions 3, Crates 2) stack vertically, each in the stacked card form; the Bags
--      split stays one card.                                          -> D.StackCards below
--   Q5 The dock button in the window layout docks to the side used last (ui.lastDocked), Docked left
--      when unset.                                                    -> D.DEFAULT_SIDE below
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local D = {}
M.Docked = D

M.DOCKED_METRICS = {
	docked = true,
	width = 380, edge = 20, top = 20, bottom = 20, cut = 22, slide = 0.2,
	header = 64, keyIcon = 34, keyX = 16, keyY = 14, titleX = 128, titleY = 13, rightPad = 28, buttonGap = 4,
	buttonSize = 22, buttonY = 20,
	tabRow = 40, tabsTop = 14, tabGap = 20, tabHeight = 25, tabsX = 18, statusGap = 0,
	subBar = 40, pad = 18, subGap = 16, noSubBarTop = 12,
	heroHeight = 104, heroPadX = 14, heroPadY = 12, heroCut = 14, heroLeft = 0, heroRight = 0, heroGap = 0,
	heroMiddle = 34, heroAfter = 8,
	noticeGap = 10, toolsRow = 32, listBar = 34, listGap = 8, listHeader = 0, rowHeight = 44, footer = 28,
	rightColumn = 132, openLeft = 18, openRight = 18,
}

-- True when a page draws for a docked layout (ctx from M.Context).
function M.IsDocked(ctx)
	return ctx and ctx.metrics and ctx.metrics.docked and true or false
end

----------------------------------------------------------------------------------------------------
-- Position and motion: anchored to the edge, top and bottom 20; the sheet slides in from its edge.
----------------------------------------------------------------------------------------------------

-- x offset of the sheet's edge anchor: 20 in from the edge, `out` (0..1) of the way out of the screen.
function D.EdgeX(side, m, out)
	local x = m.edge + (out or 0) * -(m.width + m.edge)
	return side == "right" and -x or x
end

local function Place(frame, side, m, out)
	local x = D.EdgeX(side, m, out)
	local edge = side == "right" and "RIGHT" or "LEFT"
	frame:ClearAllPoints()
	frame:SetPoint("TOP" .. edge, UIParent, "TOP" .. edge, x, -m.top)
	frame:SetPoint("BOTTOM" .. edge, UIParent, "BOTTOM" .. edge, x, m.bottom)
end

-- Slides the sheet in from its edge (spec "Mouse and keys": 200 ms; nothing fades or bounces).
function D.SlideIn(frame, side, m)
	frame.cwSlide = side
	Style.Tween(frame, "dockSlide", m.slide, "hop", function(p)
		if frame.cwSlide == side and M.LayoutKey and M.Layout().side == side then
			Place(frame, side, m, 1 - p)
		end
	end)
end

local function Apply(side)
	return function(frame, m)
		frame:SetWidth(m.width)
		frame.movable = false
		frame:SetMovable(false)
		frame.sheet:SetCut(m.cut)
		frame.head.art:SetTexture(Style.Media.headerNarrow)
		-- Swapped in place (from the window or the other side): it slides in. A scale change only places it.
		if frame:IsShown() and frame.cwDockSide ~= side then
			D.SlideIn(frame, side, m)
		else
			Place(frame, side, m, 0)
		end
		frame.cwDockSide = side
	end
end

-- Header (board): key block 120 with the W icon 34, title and AH status stacked at x 128, gear, undock
-- and close 28 from the edge; the tabs on their own row under it with a hairline.
local function Arrange(frame, m)
	local head = frame.head
	head.key:SetSize(m.keyIcon, m.keyIcon)
	head.key:ClearAllPoints()
	head.key:SetPoint("TOPLEFT", head, "TOPLEFT", m.keyX, -m.keyY)
	head.brand:ClearAllPoints()
	head.brand:SetPoint("TOPLEFT", head, "TOPLEFT", m.titleX, -m.titleY)
	head.brand:SetTextColor(C.text[1], C.text[2], C.text[3], 1) -- on the dark plane, not the gold key
	for _, b in ipairs({ head.close, head.dock, head.gear }) do
		b:SetSize(m.buttonSize, m.buttonSize)
	end
	head.close:ClearAllPoints()
	head.close:SetPoint("TOPRIGHT", head, "TOPRIGHT", -m.rightPad, -m.buttonY)
	head.dock:ClearAllPoints()
	head.dock:SetPoint("RIGHT", head.close, "LEFT", -m.buttonGap, 0)
	head.dock.icon:SetTexture(Style.Media.undock)
	head.dock.cwTip = L["Undock to a window"]
	head.gear:ClearAllPoints()
	head.gear:SetPoint("RIGHT", head.dock, "LEFT", -m.buttonGap, 0)
	head.status:ClearAllPoints()
	head.status:SetPoint("TOPLEFT", head.brand, "BOTTOMLEFT", 0, -4)
	head.status:SetJustifyH("LEFT")
	head.status:SetWordWrap(false)
	head.status:SetWidth(m.width - m.titleX - m.rightPad - 3 * m.buttonSize - 2 * m.buttonGap - 6)
	local x = m.pad
	for _, tab in ipairs(head.tabs) do
		local w = math.floor((tab.label:GetStringWidth() or 0) + 0.5)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -(m.header + m.tabsTop))
		tab:SetSize(w, m.tabHeight)
		tab.label:ClearAllPoints()
		tab.label:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
		x = x + w + m.tabGap
	end
	local rule = frame.tabRule
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", frame, "TOPLEFT", m.pad, -(m.header + m.tabRow - 1))
	rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -m.pad, -(m.header + m.tabRow - 1))
	rule:Show()
end

-- Opening the window docked: it slides in.
local function OnShow(side)
	return function(frame, m)
		frame.cwDockSide = side
		D.SlideIn(frame, side, m)
	end
end

-- Provisional (#161 Q5): the dock button docks to the side used last (ui.lastDocked, Shell.lua); with
-- none yet, to the layout registered first, which is Docked left.
D.DEFAULT_SIDE = "dockLeft"
D.SIDES = { { key = "dockLeft", side = "left", label = L["Docked left"] }, { key = "dockRight", side = "right", label = L["Docked right"] } }
if D.SIDES[1].key ~= D.DEFAULT_SIDE then
	D.SIDES[1], D.SIDES[2] = D.SIDES[2], D.SIDES[1]
end
for _, s in ipairs(D.SIDES) do
	M.RegisterLayout(s.key, { label = s.label, docked = true, side = s.side, metrics = M.DOCKED_METRICS,
		Apply = Apply(s.side), Arrange = Arrange, OnShow = OnShow(s.side) })
end

----------------------------------------------------------------------------------------------------
-- Shared drawing for the pages' docked parts
----------------------------------------------------------------------------------------------------

-- A scrolling column (the docked Settings list, the Items card, Music): a ScrollFrame whose child holds
-- the content; the mouse wheel scrolls it, a 4 unit thumb in C.ruleStrong shows where (no arrows).
-- scroll:SetContentHeight(h) after drawing; scroll.child is the parent for the content.
D.WHEEL_STEP = 44

local Scroll = {}

function Scroll:SetContentHeight(h)
	self.contentHeight = h or 0
	self.child:SetHeight(math.max(self.contentHeight, 1))
	local view = self:GetHeight() or 0
	self.maxScroll = math.max(0, self.contentHeight - view)
	self:ScrollTo(self.offset or 0)
end

function Scroll:ScrollTo(offset)
	self.offset = math.max(0, math.min(offset or 0, self.maxScroll or 0))
	self:SetVerticalScroll(self.offset)
	local view = self:GetHeight() or 0
	local total = self.contentHeight or 0
	local show = view > 0 and total > view
	self.thumb:SetShown(show and true or false)
	if show then
		local h = math.max(view * view / total, 16)
		local y = (view - h) * (self.offset / math.max(self.maxScroll, 1))
		self.thumb:ClearAllPoints()
		self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, -y)
		self.thumb:SetSize(4, h)
	end
end

function D.Scroll(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	for k, fn in pairs(Scroll) do
		sf[k] = fn
	end
	sf.child = CreateFrame("Frame", nil, sf)
	sf.child:SetSize(1, 1)
	sf:SetScrollChild(sf.child)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		self:ScrollTo((self.offset or 0) - (delta or 0) * D.WHEEL_STEP)
	end)
	sf:SetScript("OnSizeChanged", function(self, w)
		if w then
			self.child:SetWidth(w)
		end
		self:SetContentHeight(self.contentHeight)
	end)
	sf.thumb = sf:CreateTexture(nil, "OVERLAY")
	Style.Fill(sf.thumb, C.ruleStrong)
	sf.thumb:Hide()
	sf.offset, sf.maxScroll, sf.contentHeight = 0, 0, 0
	return sf
end

-- Label left, figure right, one line each (16 tall): the parts of a stacked hero card (Bags split,
-- Ledger, Farm). lines = { { label, value, square = colour name of a legend square, color } }.
-- Returns the height drawn.
D.STAT_LINE = 16

function D.StatLines(slot, lines, top)
	slot.cwStat = slot.cwStat or {}
	local y = top or 0
	for i, line in ipairs(lines) do
		local s = slot.cwStat[i]
		if not s then
			s = {}
			s.square = slot:CreateTexture(nil, "ARTWORK")
			s.square:SetTexture(Style.WHITE)
			s.square:SetSize(8, 8)
			s.label = Style.Text(slot, "Caption", "text3")
			s.label:SetJustifyH("LEFT")
			s.value = Style.Text(slot, "Figure", "text")
			s.value:SetJustifyH("RIGHT")
			slot.cwStat[i] = s
		end
		s.square:SetShown(line.square ~= nil)
		if line.square then
			local c = Style.Color(line.square)
			s.square:SetVertexColor(c[1], c[2], c[3], 1)
			s.square:ClearAllPoints()
			s.square:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -(y + 3))
		end
		s.label:ClearAllPoints()
		s.label:SetPoint("TOPLEFT", slot, "TOPLEFT", line.square and 13 or 0, -(y + 2))
		s.label:SetText(line.label or "")
		local lc = Style.Color(line.labelColor or "text3")
		s.label:SetTextColor(lc[1], lc[2], lc[3], 1)
		s.value:ClearAllPoints()
		s.value:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -y)
		s.value:SetText(line.value or M.DASH)
		local vc = Style.Color(line.color or "text")
		s.value:SetTextColor(vc[1], vc[2], vc[3], 1)
		for _, r in pairs(s) do
			r:Show()
		end
		s.square:SetShown(line.square ~= nil)
		y = y + D.STAT_LINE
	end
	for i = #lines + 1, #slot.cwStat do
		for _, r in pairs(slot.cwStat[i]) do
			r:Hide()
		end
	end
	return y - (top or 0)
end

-- Provisional (#161 Q4): a hero of several cards stacks them, full width, each in the stacked card form
-- (label, then name or figure with its unit, caption under). cards = { { label, name, nameColor, figure,
-- unit, caption } }. Returns the height of the stack.
D.CARD_HEIGHT, D.CARD_GAP = 64, 8

function D.StackCardsHeight(n)
	return n * D.CARD_HEIGHT + math.max(n - 1, 0) * D.CARD_GAP
end

function D.StackCards(slot, cards)
	slot.cwCards = slot.cwCards or {}
	for i, def in ipairs(cards) do
		local c = slot.cwCards[i]
		if not c then
			c = CreateFrame("Frame", nil, slot)
			c.sheet = Style.Sheet(c, C.card, C.cardFlap, 14, false)
			c.label = Style.Text(c, "Label", "text3")
			c.label:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -10)
			c.name = Style.Text(c, "Hero", "text")
			c.name:SetJustifyH("LEFT")
			c.name:SetWordWrap(false)
			c.name:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -1)
			c.figure = Style.Text(c, "FigureL", "text")
			c.figure:SetJustifyH("LEFT")
			c.figure:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -1)
			c.unit = Style.Text(c, "Body", "text2")
			c.unit:SetPoint("BOTTOMLEFT", c.figure, "BOTTOMRIGHT", 4, 2)
			c.caption = Style.Text(c, "Caption", "text3")
			c.caption:SetJustifyH("LEFT")
			c.caption:SetWordWrap(false)
			c.caption:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 14, 10)
			c.caption:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 10)
			slot.cwCards[i] = c
		end
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -(i - 1) * (D.CARD_HEIGHT + D.CARD_GAP))
		c:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -(i - 1) * (D.CARD_HEIGHT + D.CARD_GAP))
		c:SetHeight(D.CARD_HEIGHT)
		c.key = def.key
		c.label:SetText(def.label or "")
		local isName = def.name ~= nil
		c.name:SetShown(isName)
		c.figure:SetShown(not isName)
		if isName then
			c.name:SetText(def.name)
			local nc = Style.Color(def.nameColor or "text")
			c.name:SetTextColor(nc[1], nc[2], nc[3], 1)
		else
			c.figure:SetText(def.figure or M.DASH)
		end
		c.unit:SetText(def.unit or "")
		c.unit:SetShown(not isName and def.unit ~= nil)
		c.caption:SetText(def.caption or "")
		c:Show()
	end
	for i = #cards + 1, #slot.cwCards do
		slot.cwCards[i]:Hide()
	end
	return D.StackCardsHeight(#cards)
end
