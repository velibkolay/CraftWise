-- Records window: building the widgets (title, tabs, toolbar, summary, columns, rows, scroll bar), the refresh
-- and opening it. Built lazily on first open, from plain widgets, in the profit window's style. The data comes
-- from each tab's Model (the tab files before this one); this file only draws it.
local _, ns = ...
local RW = ns.RW
local Style, L = ns.Style, ns.L
local C = Style.colors
local Muted = RW.Muted

local WIDTH, HEIGHT, PAD, ROW_HEIGHT = RW.WIDTH, RW.HEIGHT, RW.PAD, RW.ROW_HEIGHT
local HEADER_Y, LIST_TOP, VISIBLE_ROWS = RW.HEADER_Y, RW.LIST_TOP, RW.VISIBLE_ROWS
local MAX_COLUMNS, MAX_BUTTONS = 6, 6

local frame
local state = RW.state

local function Tab()
	return RW.byKey[RW.CurrentTab()]
end

local function Offset()
	return state.offsets[RW.CurrentTab()] or 0
end

local function SetOffset(v)
	state.offsets[RW.CurrentTab()] = v
end

----------------------------------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------------------------------

local function ShowRowTooltip(self)
	local r = self.data
	if not r then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if r.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
		if r.tip and r.tip[1] then
			GameTooltip:AddLine(" ")
		end
	else
		GameTooltip:AddLine(r.name or "")
	end
	for _, line in ipairs(r.tip or {}) do
		if type(line) == "table" then
			GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
		else
			GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
		end
	end
	if r.itemID and not r.onClick then
		GameTooltip:AddLine(L["Click: item menu (Keep, Junk, Where to buy, Price history)."], 0.55, 0.55, 0.6, true)
	end
	GameTooltip:Show()
end

-- Column headers and cell positions for the tab's columns.
local function Layout(columns)
	local hx, cx = PAD + 34, 34
	for i = 1, MAX_COLUMNS do
		local col = columns[i]
		local header = frame.headers[i]
		header:SetShown(col ~= nil)
		if col then
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", hx, HEADER_Y)
			header:SetWidth(col.width)
			header:SetJustifyH(col.align or "LEFT")
			header:SetText(col.label)
		end
		for _, row in ipairs(frame.rows) do
			if i == 1 then
				if col then
					row.name:SetWidth(col.width)
					row.sub:SetWidth(col.width)
				end
			else
				local cell = row.cells[i]
				cell:SetShown(col ~= nil)
				if col then
					cell:ClearAllPoints()
					cell:SetPoint("LEFT", cx, 0)
					cell:SetWidth(col.width)
					cell:SetJustifyH(col.align or "LEFT")
				end
			end
		end
		if col then
			hx, cx = hx + col.width + 8, cx + col.width + 8
		end
	end
end

local function UpdateScrollBar(n)
	local bar = frame.scrollBar
	local maxOffset = math.max(0, n - VISIBLE_ROWS)
	bar.updating = true
	bar:SetMinMaxValues(0, maxOffset)
	bar:SetValue(Offset())
	bar.updating = false
	bar:SetShown(maxOffset > 0)
end

-- Draws the cached model: rows from the scroll offset.
function RW.Render()
	if not (frame and frame:IsShown()) then
		return
	end
	local model = state.model or { rows = {} }
	local columns = state.columns or {}
	local n = #model.rows
	SetOffset(math.max(0, math.min(Offset(), n - VISIBLE_ROWS)))
	for i, row in ipairs(frame.rows) do
		local r = model.rows[i + Offset()]
		row.data = r
		if r then
			row.icon:SetTexture(r.icon or RW.QUESTION_ICON)
			row.name:SetText(r.name or "")
			row.sub:SetText(r.sub or "")
			row.name:ClearAllPoints()
			if r.sub then
				row.name:SetPoint("TOPLEFT", 34, -3)
			else
				row.name:SetPoint("LEFT", 34, 0)
			end
			for c = 2, MAX_COLUMNS do
				local col = columns[c]
				row.cells[c]:SetText(col and r.cells and r.cells[col.key] or "")
			end
			row:Show()
		else
			row:Hide()
		end
	end
	frame.count:SetText(Muted(("%d %s"):format(n, n == 1 and L["row"] or L["rows"])))
	frame.empty:SetText(model.empty or "")
	frame.empty:SetShown(n == 0 and (model.empty or "") ~= "")
	UpdateScrollBar(n)
end

-- Tab buttons, search box and the tab's buttons as they are now (also once a second: an armed button
-- goes back to normal).
local function UpdateControls()
	local tab = Tab()
	for key, b in pairs(frame.tabButtons) do
		b:SetSelected(key == tab.key)
	end
	local search = frame.search
	search:SetShown(tab.search ~= nil)
	if tab.search then
		frame.searchHint:SetText(tab.search)
		frame.searchHint:SetShown((search:GetText() or "") == "" and not search.focused)
	end
	local buttons = tab.buttons and tab.buttons(state) or {}
	local x = tab.search and (PAD + 6 + 240 + 12) or PAD
	for i = 1, MAX_BUTTONS do
		local b, def = frame.buttons[i], buttons[i]
		b.def = def
		if def then
			b:SetWidth(def.width or 90)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", x, -82)
			b:SetLabel(def.warn and (C.warn .. def.label .. "|r") or def.label)
			b:SetSelected(def.selected and true or false)
			b:Show()
			x = x + (def.width or 90) + 6
		else
			b:Hide()
		end
	end
end

-- Builds the tab's model and draws it.
function RW.Refresh()
	if not (frame and frame:IsShown() and ns.db) then
		return
	end
	local tab = Tab()
	state.columns = RW.Columns(tab)
	local ok, model = pcall(tab.Model, state)
	if not ok then
		model = { rows = {}, summary = C.bad .. L["Could not build this view:"] .. "|r " .. tostring(model), empty = "" }
	end
	state.model = model
	Layout(state.columns)
	UpdateControls()
	frame.summary:SetText(model.summary or "")
	RW.Render()
end

----------------------------------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------------------------------

local function BuildHeader()
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -16)
	title:SetText("|cffffffffCraftWise|r")
	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
	subtitle:SetText(Muted(L["Records: snapshot"]))
	local close = Style.CloseButton(frame, function()
		frame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -10, -12)
	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(18, 18)
	gear:SetPoint("RIGHT", close, "LEFT", -8, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetAllPoints()
	gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetScript("OnClick", function(self)
		ns.ToggleSettings(self)
	end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Settings"])
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	-- The profit window is gone (#154): this opens the main window; never closes it from here.
	local main = Style.Button(frame, 110, 22, L["Main window"])
	main:SetPoint("RIGHT", gear, "LEFT", -12, 0)
	main:SetScript("OnClick", function()
		if ns.OpenMainWindow then
			ns.OpenMainWindow()
		end
	end)

	frame.tabButtons = {}
	local x = PAD
	for _, tab in ipairs(RW.tabs) do
		local width = math.max(84, 18 + 6 * #tab.label)
		local b = Style.Button(frame, width, 24, tab.label)
		b:SetPoint("TOPLEFT", x, -46)
		x = x + width + 6
		b:SetScript("OnClick", function()
			RW.Open(tab.key)
		end)
		frame.tabButtons[tab.key] = b
	end
end

local function BuildToolbar()
	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	frame.search = search
	search:SetSize(240, 22)
	search:SetPoint("TOPLEFT", PAD + 6, -82)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self)
		local tab = Tab()
		local text = self:GetText() or ""
		if tab.search and text ~= RW.Query(tab.key) then
			RW.SetQuery(tab.key, text)
			RW.Refresh()
		end
		frame.searchHint:SetShown(text == "" and not self.focused)
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	frame.searchHint = hint
	search:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		hint:Hide()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		self.focused = false
		hint:SetShown((self:GetText() or "") == "")
	end)

	frame.buttons = {}
	for i = 1, MAX_BUTTONS do
		local b = Style.Button(frame, 90, 22, "")
		b:SetScript("OnClick", function(self)
			if self.def and self.def.onClick then
				self.def.onClick()
				RW.Refresh()
			end
		end)
		b:SetScript("OnEnter", function(self)
			if self.def and self.def.tip then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:AddLine(self.def.label)
				GameTooltip:AddLine(self.def.tip, 0.8, 0.8, 0.8, true)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
			self:SetSelected(self.def and self.def.selected or false)
		end)
		b:Hide()
		frame.buttons[i] = b
	end

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.summary:SetPoint("TOPLEFT", PAD, -114)
	frame.summary:SetPoint("RIGHT", -PAD, 0)
	frame.summary:SetJustifyH("LEFT")
end

local function BuildList()
	frame.headers = {}
	for i = 1, MAX_COLUMNS do
		local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header:SetHeight(18)
		header:SetTextColor(0.55, 0.58, 0.65)
		frame.headers[i] = header
	end
	local line = frame:CreateTexture(nil, "ARTWORK")
	Style.Fill(line, C.border)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, HEADER_Y - 20)
	line:SetPoint("TOPRIGHT", -PAD, HEADER_Y - 20)

	frame.rows = {}
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", PAD, LIST_TOP - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -PAD - 14, 0)
		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		Style.Fill(row.stripe, i % 2 == 0 and C.stripe or { 0, 0, 0, 0 })
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		Style.Fill(hl, C.hover)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", 34, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)
		row.cells = {}
		for c = 2, MAX_COLUMNS do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetHeight(ROW_HEIGHT)
			fs:SetWordWrap(false)
			row.cells[c] = fs
		end
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnEnter", ShowRowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self, mouse)
			local r = self.data
			if not r then
				return
			end
			GameTooltip:Hide()
			if r.onClick then
				r.onClick(r, mouse)
				RW.Refresh()
			elseif r.itemID and ns.ShowItemMenu then
				ns.ShowItemMenu(r.itemID, self)
			end
		end)
		row:Hide()
		frame.rows[i] = row
	end

	local bar = CreateFrame("Slider", nil, frame)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	bar:SetPoint("TOPRIGHT", -PAD + 2, LIST_TOP)
	bar:SetPoint("BOTTOMRIGHT", -PAD + 2, 40)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	Style.Fill(track, { 1, 1, 1, 0.05 })
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	Style.Fill(thumb, C.accent)
	thumb:SetSize(6, 40)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar:SetScript("OnValueChanged", function(self, value)
		if self.updating then
			return
		end
		SetOffset(math.floor(value + 0.5))
		RW.Render()
	end)
	frame.scrollBar = bar

	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.count:SetPoint("BOTTOMLEFT", PAD, 14)
	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("BOTTOMRIGHT", -PAD, 14)
	help:SetText(Muted(L["Hover a row for details  ·  click an item for its menu  ·  scroll with the mouse wheel  ·  also /craftwise <tab>"]))
	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", 0, -50)
	frame.empty:SetWidth(WIDTH - 120)
end

local function Build()
	frame = CreateFrame("Frame", "CraftWiseRecordsFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 40, -30)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Style.Panel(frame)
	table.insert(UISpecialFrames, "CraftWiseRecordsFrame")
	BuildHeader()
	BuildToolbar()
	BuildList()
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local n = state.model and #state.model.rows or 0
		local step = IsShiftKeyDown() and VISIBLE_ROWS or 3
		SetOffset(math.max(0, math.min(math.max(0, n - VISIBLE_ROWS), Offset() - delta * step)))
		RW.Render()
	end)
	frame:SetScript("OnShow", function()
		RW.Refresh()
	end)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed >= 1 then
			elapsed = 0
			UpdateControls()
		end
	end)
	frame:Hide()
end

----------------------------------------------------------------------------------------------------
-- Opening
----------------------------------------------------------------------------------------------------

-- Opens the window at a tab (the last one when nil); query fills that tab's search box.
function RW.Open(key, query)
	if not ns.db then
		return
	end
	if not frame then
		Build()
	end
	if key then
		RW.SetTab(key)
	end
	local tab = Tab()
	if query then
		RW.SetQuery(tab.key, query)
	end
	if tab.onOpen then
		pcall(tab.onOpen, state)
	end
	frame.search:SetText(RW.Query(tab.key))
	if frame:IsShown() then
		RW.Refresh()
	else
		frame:Show() -- OnShow refreshes
	end
end

ns.ShowRecords = RW.Open

function ns.ToggleRecords(key)
	if frame and frame:IsShown() and (not key or key == RW.CurrentTab()) then
		frame:Hide()
		return
	end
	RW.Open(key)
end

function RW.Frame()
	return frame
end

ns.Listen("PRICES_CHANGED", function()
	RW.Refresh()
end)
