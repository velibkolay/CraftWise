-- Profit table window: building the widgets (header, filters, columns, rows, scroll bar) and opening it.
-- Built lazily on first open, from plain widgets only.
local _, ns = ...
local PF = ns.PF
local Style, L, C = ns.Style, ns.L, ns.Style.colors
local WIDTH, HEIGHT, PAD, ROW_HEIGHT, HEADER_Y, LIST_TOP, VISIBLE_ROWS =
	PF.WIDTH, PF.HEIGHT, PF.PAD, PF.ROW_HEIGHT, PF.HEADER_Y, PF.LIST_TOP, PF.VISIBLE_ROWS
local COLUMN_DEFS, VIEWS, CELL_KEYS = PF.COLUMN_DEFS, PF.VIEWS, PF.CELL_KEYS
local rows, viewButtons, state = PF.rows, PF.viewButtons, PF.state
local Settings, Muted, View = PF.Settings, PF.Muted, PF.View
local Refresh, ShowTooltip = PF.Refresh, PF.ShowTooltip

local function BuildHeader()
	local title = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -16)
	title:SetText("|cffffffffCraftWise|r")
	local subtitle = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3) -- below the title: the header row holds the Records button
	subtitle:SetText(Muted("Profit, gear, loot"))

	-- View switch: Profit (what to craft) | Learn (what to learn and where) | Level.
	-- Bags moved to the main window's Sell › Bags (#155), Fishing to Gather › Fishing (#156), Upgrades and
	-- Music to Look up › Upgrades and Music (#157).
	local levelBtn = Style.Button(PF.frame, 64, 24, L["Level"])
	levelBtn:SetPoint("TOPRIGHT", -66, -14)
	local learnBtn = Style.Button(PF.frame, 64, 24, L["Learn"])
	learnBtn:SetPoint("RIGHT", levelBtn, "LEFT", -6, 0)
	local profitBtn = Style.Button(PF.frame, 64, 24, L["Profit"])
	profitBtn:SetPoint("RIGHT", learnBtn, "LEFT", -6, 0)
	viewButtons.profit, viewButtons.learn = profitBtn, learnBtn
	viewButtons.level = levelBtn
	for key, button in pairs(viewButtons) do
		button:SetScript("OnClick", function()
			Settings().view, state.offset = key, 0
			Refresh()
		end)
	end
	-- Farm (#130): not a view, opens or closes the farm tracker window (Farm.lua, UI/FarmFrame.lua).
	local farmBtn = Style.Button(PF.frame, 50, 24, L["Farm"])
	farmBtn:SetPoint("RIGHT", profitBtn, "LEFT", -10, 0)
	farmBtn:SetScript("OnClick", function()
		ns.Farm.Slash("toggle")
	end)
	farmBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Farm tracker"])
		GameTooltip:AddLine(L["Opens or closes the farm window. Also: /craftwise farm, or a key in Key Bindings > AddOns > CraftWise."],
			0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	farmBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	PF.frame.farmButton = farmBtn
	-- Records (#137): market, where to buy, snapshot (UI/Records/).
	local recordsBtn = Style.Button(PF.frame, 70, 24, L["Records"])
	recordsBtn:SetPoint("RIGHT", farmBtn, "LEFT", -6, 0)
	recordsBtn:SetScript("OnClick", function()
		ns.ToggleRecords()
	end)
	recordsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Records"])
		GameTooltip:AddLine(L["Market prices and scans, where to buy, snapshot."],
			0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	recordsBtn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self:SetSelected(false)
	end)
	PF.frame.recordsButton = recordsBtn

	local close = Style.CloseButton(PF.frame, function()
		PF.frame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -10, -12)
	-- Gear: settings (item tooltip section).
	local gear = CreateFrame("Button", nil, PF.frame)
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

	-- Filter row: search on the left, toggles on the right.
	local search = CreateFrame("EditBox", nil, PF.frame, "InputBoxTemplate")
	PF.frame.search = search
	search:SetSize(200, 22)
	search:SetPoint("TOPLEFT", PAD + 6, -98)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self)
		state.query, state.offset = self:GetText() or "", 0
		Refresh()
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Search")
	PF.frame.searchHint = hint
	search:SetScript("OnEditFocusGained", function()
		hint:Hide()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		hint:SetShown((self:GetText() or "") == "")
	end)

	local unlearned = Style.Check(PF.frame, L["Show unlearned"], Settings().includeUnlearned, function(v)
		Settings().includeUnlearned, state.offset = v, 0
		Refresh()
	end)
	unlearned:SetPoint("TOPRIGHT", -PAD - 110, -100)
	local priced = Style.Check(PF.frame, L["Hide unpriced"], Settings().hideUnpriced, function(v)
		Settings().hideUnpriced, state.offset = v, 0
		Refresh()
	end)
	priced:SetPoint("RIGHT", unlearned, "LEFT", -24, 0)
	local fits = Style.Check(PF.frame, L["Fits my skill"], Settings().learnFitsSkill, function(v)
		Settings().learnFitsSkill, state.offset = v, 0
		Refresh()
	end)
	fits:SetPoint("TOPRIGHT", -PAD - 110, -100)
	PF.frame.unlearned, PF.frame.priced, PF.frame.fits = unlearned, priced, fits

	PF.frame.summary = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	PF.frame.summary:SetPoint("TOPLEFT", PAD, -130)
	PF.frame.summary:SetPoint("RIGHT", -PAD, 0)
	PF.frame.summary:SetJustifyH("LEFT")
end

local function BuildColumns()
	PF.frame.headers = {}
	for key, def in pairs(COLUMN_DEFS) do
		local header = CreateFrame("Button", nil, PF.frame)
		header:SetSize(100, 18)
		header.label = def.label
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.text:SetAllPoints()
		header.text:SetJustifyH(def.align)
		header.text:SetTextColor(0.55, 0.58, 0.65)
		header:SetScript("OnClick", function()
			local s = Settings()
			local ascending = key == "name" or key == "whereText" or key == "required"
			if View() == "level" then
				if (s.levelSortKey or "perPoint") == key then
					s.levelSortDesc = not s.levelSortDesc
				else
					-- money columns: best first (lowest cost / per point); chance and sale: highest first
					s.levelSortKey, s.levelSortDesc = key, key == "chance" or key == "saleValue"
				end
			elseif View() == "learn" then
				if s.learnSortKey == key then
					s.learnSortDesc = not s.learnSortDesc
				else
					s.learnSortKey, s.learnSortDesc = key, not ascending
				end
			elseif s.sortKey == key then
				s.sortDesc = not s.sortDesc
			else
				s.sortKey, s.sortDesc = key, not ascending
			end
			Refresh()
		end)
		PF.frame.headers[key] = header
	end
	local line = PF.frame:CreateTexture(nil, "ARTWORK")
	Style.Fill(line, C.border)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, HEADER_Y - 20)
	line:SetPoint("TOPRIGHT", -PAD, HEADER_Y - 20)
end

local function BuildRows()
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, PF.frame)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", PAD, LIST_TOP - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -PAD - 14, 0)

		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		Style.Fill(row.stripe, C.stripe)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		Style.Fill(hl, C.hover)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 42, -4)
		row.name:SetWidth(VIEWS.profit[1].width)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
		row.status:SetWidth(VIEWS.profit[1].width)
		row.status:SetJustifyH("LEFT")
		row.status:SetWordWrap(false)

		row.cells = {}
		for _, key in ipairs(CELL_KEYS) do
			local font = key == "whereText" and "GameFontHighlightSmall" or "GameFontHighlight"
			local fs = row:CreateFontString(nil, "OVERLAY", font)
			fs:SetSize(100, ROW_HEIGHT)
			fs:SetJustifyH(COLUMN_DEFS[key].align)
			fs:SetWordWrap(false)
			row.cells[key] = fs
		end

		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			local r = self.data
			if not r then
				return
			end
			if C_TradeSkillUI.OpenRecipe then
				pcall(C_TradeSkillUI.OpenRecipe, r.recipeID)
			end
		end)
		rows[i] = row
	end
end

local function BuildScrollBar()
	local bar = CreateFrame("Slider", nil, PF.frame)
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
		state.offset = math.floor(value + 0.5)
		Refresh()
	end)
	PF.frame.scrollBar = bar
end

local function Build()
	PF.frame = CreateFrame("Frame", "CraftWiseFrame", UIParent, "BackdropTemplate")
	PF.frame:SetSize(WIDTH, HEIGHT)
	PF.frame:SetPoint("CENTER")
	PF.frame:SetFrameStrata("HIGH")
	PF.frame:SetToplevel(true)
	PF.frame:SetClampedToScreen(true)
	PF.frame:SetMovable(true)
	PF.frame:EnableMouse(true)
	PF.frame:RegisterForDrag("LeftButton")
	PF.frame:SetScript("OnDragStart", PF.frame.StartMoving)
	PF.frame:SetScript("OnDragStop", PF.frame.StopMovingOrSizing)
	Style.Panel(PF.frame)
	table.insert(UISpecialFrames, "CraftWiseFrame")

	BuildHeader()
	BuildColumns()
	BuildRows()
	BuildScrollBar()

	PF.frame.count = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	PF.frame.count:SetPoint("BOTTOMLEFT", PAD, 14)
	local help = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("BOTTOMRIGHT", -PAD, 14)
	help:SetText(Muted("Hover a row for details  ·  click a header to sort  ·  scroll with the mouse wheel"))

	PF.frame.empty = PF.frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	PF.frame.empty:SetPoint("CENTER", 0, -40)
	PF.frame.empty:SetText("No recipes match. Clear the search or tick \"Show unlearned\".")

	PF.frame:EnableMouseWheel(true)
	PF.frame:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
		local step = IsShiftKeyDown() and VISIBLE_ROWS or 3
		state.offset = math.max(0, math.min(maxOffset, state.offset - delta * step))
		Refresh()
	end)
	PF.frame:SetScript("OnShow", Refresh)
end

function ns.ToggleProfitFrame()
	if not ns.db then
		return
	end
	if not PF.frame then
		Build()
		PF.frame:Show()
		Refresh()
		return
	end
	PF.frame:SetShown(not PF.frame:IsShown())
end
