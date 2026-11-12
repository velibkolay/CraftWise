-- Main window: CraftWiseMainFrame, the window layout, refresh and opening (#153; spec "Main window shell").
-- One frame, strata MEDIUM, toplevel, clamped to the screen, in UISpecialFrames while "Close with Escape"
-- is on. Header: gold key block (W icon, "CraftWise"), five section tabs, AH status, gear, dock, close;
-- sub bar with the sub-pages (the nokta before the active one) and the page's tools; then the page:
-- stale card, hero card, list bar, list, footer - or one of the states. Built on first open.
-- The docked layout (#161) registers its own layout (M.RegisterLayout with docked = true): its metrics
-- feed the same arrangement, and Arrange(frame, metrics) may move what differs.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local FRAME_NAME = "CraftWiseMainFrame"
local STATUS_POLL = 0.25 -- seconds between AH status checks while the window shows

-- Window layout (spec table, "Window layout" column; board "Window layout").
M.WINDOW_METRICS = {
	width = 880, height = 600, point = { "CENTER", "CENTER", 0, 40 }, cut = 22,
	header = 56, keyIcon = 30, keyX = 14, tabsX = 198, tabGap = 24, rightPad = 30, buttonGap = 6, statusGap = 8,
	subBar = 46, pad = 22, subGap = 18, noSubBarTop = 16,
	heroHeight = 76, heroPadX = 16, heroPadY = 12, heroCut = 14, heroLeft = 240, heroRight = 170, heroGap = 24,
	noticeGap = 10, listBar = 40, listGap = 12, listHeader = 24, rowHeight = 36, footer = 24,
}

local f -- the frame

----------------------------------------------------------------------------------------------------
-- Header
----------------------------------------------------------------------------------------------------

local function IconButton(parent, texture, size, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	Style.Fill(b.bg, C.text)
	b.bg:Hide()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(texture)
	b.icon:SetSize(size, size)
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.icon:SetVertexColor(C.text[1], C.text[2], C.text[3], 1)
	-- On: filled C.text with a dark icon (the gear while Settings shows; board "Settings").
	function b:SetOn(on)
		self.bg:SetShown(on and true or false)
		local c = on and Style.INK or C.text
		self.icon:SetVertexColor(c[1], c[2], c[3], 1)
	end
	b:SetScript("OnEnter", function(self)
		Style.ShowTip(self, tip)
	end)
	b:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	return b
end

local function BuildHeader()
	local head = CreateFrame("Frame", nil, f)
	f.head = head
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function()
		if f.movable and not M.UI().locked then
			f:StartMoving()
		end
	end)
	head:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if f.movable then
			local point, _, relativePoint, x, y = f:GetPoint(1)
			if point then
				M.UI().pos = { point, relativePoint, x, y }
			end
		end
	end)
	head.art = Style.HeaderArt(head)
	head.key = Style.KeyIcon(head, 30)
	head.brand = Style.Text(head, "Brand", Style.INK)
	head.brand:SetText("CraftWise")

	head.tabs = {}
	for i, section in ipairs(M.SECTIONS) do
		local tab = CreateFrame("Button", nil, head)
		tab.key = section.key
		tab.label = Style.Text(tab, "Section", "text3")
		tab.label:SetText(section.label)
		tab.label:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -20)
		tab.bar = tab:CreateTexture(nil, "ARTWORK")
		Style.Fill(tab.bar, C.text)
		tab.bar:SetHeight(3)
		tab.bar:SetPoint("TOPLEFT", tab.label, "BOTTOMLEFT", 0, -6)
		tab.bar:SetPoint("TOPRIGHT", tab.label, "BOTTOMRIGHT", 0, -6)
		tab:SetScript("OnClick", function()
			M.SelectSection(section.key)
		end)
		head.tabs[i] = tab
	end

	head.close = IconButton(head, Style.Media.close, 11, L["Close"])
	head.close:SetScript("OnClick", function()
		f:Hide()
	end)
	head.dock = IconButton(head, Style.Media.dock, 14, L["Dock to screen edge"])
	head.dock:SetScript("OnClick", function()
		M.ToggleDock()
	end)
	head.gear = IconButton(head, Style.Media.gear, 14, L["Settings"])
	head.gear:SetScript("OnClick", function()
		M.ToggleSettings()
	end)
	-- AH status: "Horde AH · 2 h ago"; stale in C.danger bold; while scanning orange with its nokta.
	head.status = Style.Text(head, "Caption", "text3")
	head.status:SetJustifyH("RIGHT")
	head.live = Style.Nokta(head, C.live)
	head.live:Hide()

	-- Scanning: a 2 unit orange progress line under the header.
	f.progress = CreateFrame("Frame", nil, f)
	f.progress:SetHeight(2)
	f.progress.track = f.progress:CreateTexture(nil, "ARTWORK")
	f.progress.track:SetAllPoints(f.progress)
	Style.Fill(f.progress.track, C.rule)
	f.progress.fill = f.progress:CreateTexture(nil, "ARTWORK", nil, 1)
	Style.Fill(f.progress.fill, C.live)
	f.progress.fill:SetPoint("TOPLEFT", f.progress, "TOPLEFT", 0, 0)
	f.progress.fill:SetPoint("BOTTOMLEFT", f.progress, "BOTTOMLEFT", 0, 0)
	f.progress:Hide()
end

-- Header arrangement of the window layout: key block, tabs from x 198 (gap 24), buttons 30 from the edge.
local function ArrangeHeader(m)
	local head = f.head
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	head:SetHeight(m.header)
	head.key:SetSize(m.keyIcon, m.keyIcon)
	head.key:ClearAllPoints()
	head.key:SetPoint("LEFT", head, "LEFT", m.keyX, 0)
	head.brand:ClearAllPoints()
	head.brand:SetPoint("LEFT", head.key, "RIGHT", 10, 0)
	local x = m.tabsX
	for _, tab in ipairs(head.tabs) do
		local w = math.floor((tab.label:GetStringWidth() or 0) + 0.5)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", head, "TOPLEFT", x, 0)
		tab:SetSize(w, m.header)
		x = x + w + m.tabGap
	end
	head.close:ClearAllPoints()
	head.close:SetPoint("RIGHT", head, "RIGHT", -m.rightPad, 0)
	head.dock:ClearAllPoints()
	head.dock:SetPoint("RIGHT", head.close, "LEFT", -m.buttonGap, 0)
	local dockShown = M.CanDock()
	head.dock:SetShown(dockShown)
	head.gear:ClearAllPoints()
	head.gear:SetPoint("RIGHT", dockShown and head.dock or head.close, "LEFT", -m.buttonGap, 0)
	head.status:ClearAllPoints()
	head.status:SetPoint("RIGHT", head.gear, "LEFT", -(m.buttonGap + m.statusGap), 0)
	f.progress:ClearAllPoints()
	f.progress:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	f.progress:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
end

-- The AH status in the header; returns its kind ("scanning" | "stale" | "ok" | "none") or nil when hidden.
local function UpdateStatus(page)
	local head = f.head
	if not (page and page.prices) then
		head.status:Hide()
		head.live:Hide()
		f.progress:Hide()
		return nil
	end
	local status = M.PriceStatus()
	local text, kind = M.StatusText(status)
	head.status:SetText(text or "")
	head.status:SetShown(text ~= nil)
	local stale = kind == "stale"
	head.status:SetFontObject(Style.Fonts[(stale or kind == "scanning") and "Label" or "Caption"])
	local c = stale and C.danger or C.text3
	head.status:SetTextColor(c[1], c[2], c[3], 1)
	if kind == "scanning" then
		head.live:ClearAllPoints()
		head.live:SetPoint("RIGHT", head.status, "LEFT", -6, 0)
		head.live:SetSize(8, 8)
		head.live:Show()
		local p = status.scanning
		local width = M.Layout().metrics.width or 880
		f.progress.fill:SetWidth(math.max(p.total > 0 and width * p.done / p.total or 0, 0.01))
		f.progress:Show()
	else
		head.live:Hide()
		f.progress:Hide()
	end
	return kind, status
end

----------------------------------------------------------------------------------------------------
-- Sub bar
----------------------------------------------------------------------------------------------------

local function BuildSubBar()
	local bar = CreateFrame("Frame", nil, f)
	f.sub = bar
	bar.rule = Style.Rule(bar, "H", C.rule)
	bar.rule:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.rule:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
	bar.buttons = {}
	bar.nokta = Style.Nokta(bar)
	bar.nokta:Hide()
	bar.tools = CreateFrame("Frame", nil, bar) -- page tools, right aligned
end

local function SubButton(i)
	local bar = f.sub
	local b = bar.buttons[i]
	if not b then
		b = CreateFrame("Button", nil, bar)
		b.label = Style.Text(b, "Section", "text3")
		b:SetScript("OnClick", function(self)
			M.ShowPage(self.key)
		end)
		bar.buttons[i] = b
	end
	return b
end

-- The sub-pages of the section; the nokta hops (160 ms) when the active one changes.
local function UpdateSubBar(section, page, m)
	local bar = f.sub
	local pages = section ~= M.SETTINGS and M.SectionPages(section) or {}
	local shown = #pages > 1
	bar:SetShown(shown)
	if not shown then
		bar.nokta:Hide()
		return false
	end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -m.header)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -m.header)
	bar:SetHeight(m.subBar)
	local x = m.pad
	for i, p in ipairs(pages) do
		local b = SubButton(i)
		b.key = p.key
		b.label:SetText(p.label)
		local active = p == page
		local c = active and C.text or C.text3
		b.label:SetTextColor(c[1], c[2], c[3], 1)
		local lead = active and 18 or 0 -- nokta (11) + gap 7
		local w = math.floor((b.label:GetStringWidth() or 0) + 0.5) + lead
		b:ClearAllPoints()
		b:SetPoint("LEFT", bar, "LEFT", x, 0)
		b:SetSize(w, m.subBar)
		b.label:ClearAllPoints()
		b.label:SetPoint("LEFT", b, "LEFT", lead, 0)
		if active then
			bar.nokta:MoveTo(b, "LEFT", 5.5, 0, f.lastSub == p.key)
			f.lastSub = p.key
		end
		b:Show()
		x = x + w + m.subGap
	end
	for i = #pages + 1, #bar.buttons do
		bar.buttons[i]:Hide()
	end
	bar.tools:ClearAllPoints()
	bar.tools:SetPoint("RIGHT", bar, "RIGHT", -m.pad, 0)
	bar.tools:SetSize(m.width / 2, m.subBar)
	return true
end

----------------------------------------------------------------------------------------------------
-- Page slots: each page builds its tools once into its own frames, shown only while it is current.
----------------------------------------------------------------------------------------------------

local slots = {} -- [page key] = { tools, listTools, footerTools, list, body }

local function Slots(page)
	local s = slots[page.key]
	if not s then
		s = {}
		slots[page.key] = s
	end
	return s
end

local function Slot(page, name, parent, builder, ctx)
	local s = Slots(page)
	if not s[name] and page[builder] then
		local frame = CreateFrame("Frame", nil, parent)
		frame:SetAllPoints(parent)
		s[name] = frame
		local ok, err = M.Call(page[builder], frame, ctx)
		if not ok then
			error(err, 0)
		end
	end
	return s[name]
end

-- For the specs: a page's slots and list.
function M.SlotsOf(key)
	return slots[key]
end

function M.ListOf(key)
	return slots[key] and slots[key].list
end

local function HideOtherSlots(page)
	for key, s in pairs(slots) do
		if key ~= page.key then
			for _, frame in pairs(s) do
				frame:Hide()
			end
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Body: stale card, hero card, list bar, list, footer; the panel for the states; custom bodies.
----------------------------------------------------------------------------------------------------

local function BuildBody()
	f.body = CreateFrame("Frame", nil, f)
	f.notice = M.StaleCard(f.body)

	local hero = CreateFrame("Frame", nil, f.body)
	f.hero = hero
	hero.sheet = Style.Sheet(hero, C.card, C.cardFlap, 14, false)
	hero.label = Style.Text(hero, "Label", "text3")
	hero.name = Style.Text(hero, "Hero", "text")
	hero.name:SetWordWrap(false)
	hero.sub = Style.Text(hero, "Caption", "text2")
	hero.sub:SetWordWrap(false)
	hero.figure = Style.Text(hero, "FigureL", "text")
	hero.figure:SetJustifyH("RIGHT")
	hero.middle = CreateFrame("Frame", nil, hero) -- the page's rails go here
	hero:Hide()

	local lb = CreateFrame("Frame", nil, f.body)
	f.listBar = lb
	lb.title = Style.Text(lb, "BodyBold", "text")
	lb.note = Style.Text(lb, "Caption", "text3")
	lb.tools = CreateFrame("Frame", nil, lb)
	lb:Hide()

	local foot = CreateFrame("Frame", nil, f)
	f.foot = foot
	foot.rule = Style.Rule(foot, "H", C.rule)
	foot.rule:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
	foot.rule:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
	foot.left = Style.Text(foot, "Caption", "text3")
	foot.left:SetJustifyH("LEFT")
	foot.left:SetWordWrap(false)
	foot.right = Style.Text(foot, "Caption", "text3")
	foot.right:SetJustifyH("RIGHT")
	foot.tools = CreateFrame("Frame", nil, foot)

	f.panel = M.Panel(f.body)
	f.panel:SetAllPoints(f.body)
end

local function PlaceHero(model, m)
	local hero = f.hero
	local h = model.hero
	hero:SetShown(h ~= nil)
	if not h then
		return 0
	end
	local px, py = m.heroPadX, m.heroPadY
	hero.sheet:SetFlap(Style.Color(h.flap or "cardFlap")) -- the dog-ear carries a state (Farm: orange running)
	hero.label:ClearAllPoints()
	hero.label:SetPoint("TOPLEFT", hero, "TOPLEFT", px, -py)
	hero.label:SetText(h.label or "")
	local lc = Style.Color(h.labelColor or "text3")
	hero.label:SetTextColor(lc[1], lc[2], lc[3], 1)
	hero.name:ClearAllPoints()
	hero.name:SetPoint("TOPLEFT", hero.label, "BOTTOMLEFT", 0, -1)
	hero.name:SetWidth(m.heroLeft)
	hero.name:SetFontObject(Style.Fonts[h.nameFont or "Hero"])
	hero.name:SetText(h.name or "")
	local nc = Style.Color(h.nameColor or "text")
	hero.name:SetTextColor(nc[1], nc[2], nc[3], 1)
	hero.sub:ClearAllPoints()
	hero.sub:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -1)
	hero.sub:SetWidth(m.heroLeft)
	hero.sub:SetText(h.sub or "")
	hero.figure:ClearAllPoints()
	hero.figure:SetPoint("RIGHT", hero, "RIGHT", -px, 0)
	hero.figure:SetWidth(m.heroRight)
	hero.figure:SetText(h.figure or "")
	-- h.full: the page draws the figures itself, over the whole card inside its padding (label still
	-- the shell's). h.bare: no card at all; the page draws its own cards in the slot (Auctions).
	hero.sheet:SetShown(not h.bare)
	hero.middle:ClearAllPoints()
	if h.bare then
		hero.middle:SetPoint("TOPLEFT", hero, "TOPLEFT", 0, 0)
		hero.middle:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, 0)
	elseif h.full then
		hero.middle:SetPoint("TOPLEFT", hero, "TOPLEFT", px, -py)
		hero.middle:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -px, py)
	else
		hero.middle:SetPoint("TOPLEFT", hero, "TOPLEFT", px + m.heroLeft + m.heroGap, -py)
		hero.middle:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -(px + m.heroRight + m.heroGap), py)
	end
	return h.height or m.heroHeight
end

-- Draws a list page under the sub bar; top = y offset where the page starts.
local function DrawListPage(page, ctx, m, top, status)
	local ok, model = M.Call(page.Model, ctx)
	if not ok then
		error(model, 0)
	end
	model = model or {}
	local y = top
	-- Stale: the card above the hero card.
	local stale = page.prices and status and status.stale and not status.scanning
	f.notice:SetShown(stale and true or false)
	if stale then
		f.notice:SetStatus(status)
		f.notice:ClearAllPoints()
		f.notice:SetPoint("TOPLEFT", f.body, "TOPLEFT", m.pad, -y)
		f.notice:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", -m.pad, -y)
		y = y + M.STALE_CARD_HEIGHT + m.noticeGap
	end
	local heroHeight = PlaceHero(model, m)
	if heroHeight > 0 then
		f.hero:ClearAllPoints()
		f.hero:SetPoint("TOPLEFT", f.body, "TOPLEFT", m.pad, -y)
		f.hero:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", -m.pad, -y)
		f.hero:SetHeight(heroHeight)
		f.hero.middle:SetShown(page.Hero ~= nil)
		-- The page's own frame in the middle, hidden while another page shows (like its tools).
		local heroSlot
		if page.Hero then
			local s = Slots(page)
			if not s.hero then
				s.hero = CreateFrame("Frame", nil, f.hero.middle)
				s.hero:SetAllPoints(f.hero.middle)
			end
			heroSlot = s.hero
			heroSlot:Show()
		end
		local okHero, err = M.Call(page.Hero, f.hero, model.hero, ctx, heroSlot)
		if not okHero then
			error(err, 0)
		end
		y = y + heroHeight
	end
	-- List bar: "11 recipes" + note, the page's chips on the right (board "Window layout").
	local lb = f.listBar
	local listTools = Slot(page, "listTools", lb.tools, "ListTools", ctx)
	if model.listTitle or listTools then
		lb:ClearAllPoints()
		lb:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
		lb:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -y)
		lb:SetHeight(m.listBar)
		lb.title:ClearAllPoints()
		lb.title:SetPoint("LEFT", lb, "LEFT", m.pad, 0)
		lb.title:SetText(model.listTitle or "")
		lb.note:ClearAllPoints()
		lb.note:SetPoint("LEFT", lb.title, "RIGHT", 8, 0)
		lb.note:SetText(model.listNote or "")
		lb.tools:ClearAllPoints()
		lb.tools:SetPoint("RIGHT", lb, "RIGHT", -m.pad, 0)
		lb.tools:SetSize(m.width / 2, m.listBar)
		if listTools then
			listTools:Show()
			M.Call(page.UpdateListTools, listTools, ctx)
		end
		lb:Show()
		y = y + m.listBar
	else
		lb:Hide()
		y = y + m.listGap
	end
	-- The list itself.
	local s = Slots(page)
	if not s.list then
		s.list = M.List(f.body, page)
	end
	local list = s.list
	list.onError = function(err)
		M.ShowError(page, err)
	end
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -y)
	list:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, 0)
	local columns = page.columns
	if type(columns) == "function" then
		local okCols, cols = M.Call(columns, ctx)
		if not okCols then
			error(cols, 0)
		end
		columns = cols
	end
	list:SetRows(M.SortRows(page, model.rows or {}), ctx, columns or {}, m, model.empty)
	list:Show()
	-- Footer.
	f.foot.left:SetText(model.footer or "")
	f.foot.right:SetText(model.footerRight or "")
	return true
end

local function HideBody()
	f.notice:Hide()
	f.hero:Hide()
	f.listBar:Hide()
	f.panel:Hide()
	for _, s in pairs(slots) do
		if s.list then
			s.list:Hide()
		end
		if s.body then
			s.body:Hide()
		end
	end
end

-- The Error state over the page's body (a model, hero, tools or row that raised).
function M.ShowError(page, err)
	if not f then
		return
	end
	HideBody()
	f.foot.left:SetText("")
	f.foot.right:SetText("")
	f.panel:Set(M.ErrorSpec(page, err))
	f.lastError = err
end

-- What a state shows (First run, No prices).
local function StateSpec(state, page, ctx)
	local copy = M.StateCopy(state, ctx)
	local spec = { title = copy.title, body = copy.body, icon = state == "firstRun" }
	if state == "noPrices" then
		spec.buttons = { { label = copy.button, onClick = function()
			M.state.vendorOnly[page.key] = true
			M.Refresh()
		end } }
	end
	return spec
end

local function DrawPage(page, ctx, m, top, status, hasSub)
	HideBody()
	f.lastError = nil
	local tools = hasSub and Slot(page, "tools", f.sub.tools, "Tools", ctx) or nil
	if tools then
		tools:Show()
		M.Call(page.UpdateTools, tools, ctx)
	end
	f.body:ClearAllPoints()
	f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
	f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, page.footerHeight or m.footer)
	local footShown = page.kind == "list"
	f.foot:SetShown(footShown)
	if not footShown then
		f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	end
	f.foot:ClearAllPoints()
	f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	f.foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	f.foot:SetHeight(page.footerHeight or m.footer)
	f.foot.left:ClearAllPoints()
	f.foot.left:SetPoint("LEFT", f.foot, "LEFT", m.pad, 0)
	f.foot.right:ClearAllPoints()
	f.foot.tools:ClearAllPoints()
	f.foot.tools:SetPoint("RIGHT", f.foot, "RIGHT", -m.pad, 0)
	f.foot.tools:SetSize(m.width / 2, page.footerHeight or m.footer)
	local footTools = Slot(page, "footerTools", f.foot.tools, "FooterTools", ctx)
	if footTools then
		footTools:Show()
		M.Call(page.UpdateFooterTools, footTools, ctx)
		f.foot.right:SetPoint("RIGHT", f.foot.tools, "LEFT", -12, 0)
	else
		f.foot.right:SetPoint("RIGHT", f.foot, "RIGHT", -m.pad, 0)
	end
	local state = M.BlockingState(page, ctx)
	if state then
		f.foot:Hide()
		f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.panel:Set(StateSpec(state, page, ctx))
		return state
	end
	if page.kind == "custom" then
		local s = Slots(page)
		if not s.body then
			s.body = CreateFrame("Frame", nil, f.body)
			s.body:SetAllPoints(f.body)
			local ok, err = M.Call(page.Build, s.body, ctx)
			if not ok then
				error(err, 0)
			end
		end
		s.body:Show()
		local ok, err = M.Call(page.Refresh, s.body, ctx)
		if not ok then
			error(err, 0)
		end
		return "custom"
	end
	DrawListPage(page, ctx, m, 0, status)
	return "list"
end

----------------------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------------------

-- What the window shows now, for the specs: { section, page, state, layout }.
M.shown = {}

function M.Refresh()
	if not (f and f:IsShown() and ns.db) then
		return
	end
	local layout = M.Layout()
	local m = layout.metrics
	local section, page = M.CurrentSection(), M.CurrentPage()
	for _, tab in ipairs(f.head.tabs) do
		local active = tab.key == section
		local c = active and C.text or C.text3
		tab.label:SetTextColor(c[1], c[2], c[3], 1)
		tab.bar:SetShown(active)
	end
	f.head.gear:SetOn(section == M.SETTINGS)
	f.head.dock:SetShown(M.CanDock())
	M.shown = { section = section, page = page and page.key, layout = layout.key }
	if not page then
		HideBody()
		f.sub:Hide()
		f.foot:Hide()
		f.head.status:Hide()
		return
	end
	local kind, status = UpdateStatus(page)
	f.statusKind = kind
	local hasSub = UpdateSubBar(section, page, m)
	local top = m.header + (hasSub and m.subBar or m.noSubBarTop)
	local ctx = M.Context(page)
	HideOtherSlots(page)
	local ok, res = pcall(DrawPage, page, ctx, m, top, status, hasSub)
	if not ok then
		M.ShowError(page, res)
		M.shown.state = "error"
	else
		M.shown.state = res
		if f.lastError then
			M.shown.state = "error"
		end
	end
	if M.WakeSkeletons then
		M.WakeSkeletons()
	end
end

----------------------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------------------

local function ApplyWindow(frame, m)
	frame:SetSize(m.width, m.height)
	frame:ClearAllPoints()
	local pos = M.UI().pos
	if type(pos) == "table" and pos[1] then
		frame:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
	else
		frame:SetPoint(m.point[1], UIParent, m.point[2], m.point[3], m.point[4])
	end
	frame.movable = true
	frame:SetMovable(true)
	frame.sheet:SetCut(m.cut)
	frame.head.art:SetTexture(Style.Media.headerWide)
end

M.RegisterLayout("window", { label = L["Window"], docked = false, metrics = M.WINDOW_METRICS, Apply = ApplyWindow })

-- Puts the current layout on the frame (the dock button swaps in place, no reload).
function M.ApplyLayout()
	if not f then
		return
	end
	local layout = M.Layout()
	local m = layout.metrics
	f:SetScale(tonumber(M.UI().scale) or 1)
	Style.SnapRules()
	f.movable = false
	f:SetMovable(false)
	layout.Apply(f, m)
	ArrangeHeader(m)
	if layout.Arrange then
		layout.Arrange(f, m)
	end
	M.Refresh()
end

-- Close with Escape: the frame's name in UISpecialFrames while the setting is on.
function M.ApplyEscape()
	local listed
	for i = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[i] == FRAME_NAME then
			if M.UI().escape and not listed then
				listed = true
			else
				table.remove(UISpecialFrames, i)
			end
		end
	end
	if M.UI().escape and not listed then
		table.insert(UISpecialFrames, FRAME_NAME)
	end
end

----------------------------------------------------------------------------------------------------
-- Building and opening
----------------------------------------------------------------------------------------------------

local function Build()
	f = CreateFrame("Frame", FRAME_NAME, UIParent)
	M.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f.sheet = Style.Sheet(f, C.sheet, C.flap, 22, true)
	BuildHeader()
	BuildSubBar()
	BuildBody()
	f:SetScript("OnShow", function()
		M.Refresh()
	end)
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < STATUS_POLL then
			return
		end
		elapsed = 0
		local page = M.CurrentPage()
		if not (page and page.prices) then
			return
		end
		local before = f.statusKind
		local kind = UpdateStatus(page)
		f.statusKind = kind
		if kind ~= before then
			M.Refresh() -- scan started or ended, prices went stale: the page follows
		end
	end)
	f:Hide()
	M.ApplyEscape()
	M.ApplyLayout()
end

function M.Frame()
	return f
end

-- Opens the window (on a page when given); the specs and the binding use these.
function M.Open(pageKey)
	if not ns.db then
		return false
	end
	if not f then
		Build()
	end
	if pageKey then
		M.ShowPage(pageKey)
	end
	if not f:IsShown() then
		f:Show()
	else
		M.Refresh()
	end
	return true
end

function M.Toggle()
	if f and f:IsShown() then
		f:Hide()
		return false
	end
	return M.Open()
end

-- Hooks other files call: the minimap button and the addon compartment (UI/MinimapButton.lua), and
-- the key binding.
ns.ToggleMainWindow = M.Toggle
ns.OpenMainWindow = M.Open

_G.BINDING_NAME_CRAFTWISE_MAIN = "Toggle CraftWise"
function CraftWise_MainToggle()
	M.Toggle()
end

ns.Listen("RECIPES_CHANGED", M.Refresh)
ns.Listen("PROFESSIONS_CHANGED", M.Refresh)
ns.Listen("PRICES_CHANGED", M.Refresh)
