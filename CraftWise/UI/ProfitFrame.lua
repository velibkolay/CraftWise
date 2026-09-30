-- Profit table window. Opens from the minimap button, the addon compartment or /cw.
-- Built lazily on first open, from plain widgets only.
local _, ns = ...
local Style = ns.Style
local C = Style.colors

local WIDTH, HEIGHT = 900, 580
local PAD = 16
local ROW_HEIGHT = 36
local HEADER_Y = -150 -- top of the column header row
local LIST_TOP = HEADER_Y - 22
local VISIBLE_ROWS = math.floor((HEIGHT + LIST_TOP - 40) / ROW_HEIGHT)

-- Recipe column is flexible; numbers are fixed and right aligned.
local COLUMNS = {
	{ key = "name", label = "RECIPE", width = 290, align = "LEFT" },
	{ key = "cost", label = "COST", width = 100, align = "RIGHT" },
	{ key = "sellsFor", label = "SELLS FOR", width = 100, align = "RIGHT" },
	{ key = "profit", label = "PROFIT", width = 100, align = "RIGHT" },
	{ key = "learnCost", label = "TO LEARN", width = 95, align = "RIGHT", learn = true },
	{ key = "breakEven", label = "PAYS OFF", width = 75, align = "RIGHT", learn = true },
}

local STATUS_TEXT = {
	known = "Known",
	trainable = "Trainer",
	unlearned = "Source not known yet",
}

-- Texture arrows: the game font has no triangle glyphs.
local ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t"
local ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:3|t"

-- Recipe name colours as in the game's profession window.
local SKILL_COLORS = {
	red = "|cffff4040", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080",
}

local frame, rows, tabs = nil, {}, {}
local state = { professionID = nil, offset = 0, data = {}, query = "", hidden = 0 }

local function Settings()
	return ns.db.settings
end

local function Money(copper)
	return ns.FormatMoney(copper)
end

local function Muted(text)
	return C.muted .. text .. "|r"
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and GetItemInfo then
		name = GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

local function StatusLine(r)
	local text = STATUS_TEXT[r.status] or r.status
	if r.status == "known" then
		return Muted(text)
	end
	local parts = { text }
	if r.required then
		parts[#parts + 1] = ("skill %d"):format(r.required)
	end
	local color = C.good
	if r.tooLow then
		color = C.warn
	elseif r.status == "unlearned" then
		color = C.muted
	end
	return color .. table.concat(parts, " · ") .. "|r"
end

-- Data ---------------------------------------------------------------------

-- Rows after the search box and the filters; also returns how many the filters hid.
local function FilteredRows()
	local s = Settings()
	-- "Learnable now" lists unlearned recipes, so it needs them regardless of "Show unlearned".
	local all = state.professionID and ns.BuildRows(state.professionID, s.includeUnlearned or s.onlyReachable) or {}
	local query = state.query:lower()
	local out, hidden = {}, 0
	for _, r in ipairs(all) do
		local keep = query == "" or (r.name or ""):lower():find(query, 1, true)
		if keep then
			if s.hideUnpriced and not r.profit then
				keep, hidden = false, hidden + 1
			elseif s.onlyReachable and (r.status == "known" or not r.required or r.tooLow) then
				-- unlearned recipes a trainer confirmed you can learn at your skill
				keep, hidden = false, hidden + 1
			end
		end
		if keep then
			out[#out + 1] = r
		end
	end
	return out, hidden
end

local function ProfessionIDs()
	local ids = {}
	for id, prof in pairs(ns.charDB.professions) do
		if next(prof.recipes) and not ns.IsGathering(id) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		return (ns.charDB.professions[a].name or "") < (ns.charDB.professions[b].name or "")
	end)
	return ids
end

-- Rendering -----------------------------------------------------------------

local function RenderTabs(ids)
	for i, id in ipairs(ids) do
		local tab = tabs[i]
		if not tab then
			tab = Style.Button(frame, 160, 26)
			tab:SetPoint("TOPLEFT", PAD + (i - 1) * 166, -58)
			tabs[i] = tab
		end
		local prof = ns.charDB.professions[id]
		tab:SetLabel(("%s  %s%d/%d|r"):format(prof.name or "?", C.muted, prof.skill or 0, prof.maxSkill or 0))
		tab:SetIcon(ns.ProfessionIcon(id))
		tab:SetSelected(id == state.professionID)
		tab:SetScript("OnClick", function()
			state.professionID, state.offset = id, 0
			ns.RefreshProfitFrame()
		end)
		tab:Show()
	end
	for i = #ids + 1, #tabs do
		tabs[i]:Hide()
	end
end

local function RenderSummary(ids)
	local text
	if #ids == 0 then
		text = C.warn .. "Open a profession window once so CraftWise can read your recipes.|r"
	elseif not ns.HasAuctionator() then
		text = C.warn .. "Auctionator not found.|r " .. Muted("Only vendor prices are used. Install Auctionator and run a Full Scan at the auction house.")
	else
		local profitable, priced, unpriced = 0, 0, 0
		for _, r in ipairs(state.data) do
			if r.profit then
				priced = priced + 1
				if r.profit > 0 then
					profitable = profitable + 1
				end
			elseif not r.noItemOutput then
				unpriced = unpriced + 1
			end
		end
		text = ("%s%d|r of %d priced recipes make a profit"):format(C.good, profitable, priced)
		if unpriced > 0 then
			text = text .. Muted(("  ·  %d without a price (reagent or item not on the AH)"):format(unpriced))
		end
		if Settings().onlyReachable and #state.data == 0 then
			text = C.warn .. "Nothing confirmed learnable yet.|r " .. Muted("Open your trainer once so CraftWise records what it teaches and at which skill.")
		end
		if state.hidden > 0 and not (Settings().onlyReachable and #state.data == 0) then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
	end
	frame.summary:SetText(text)
end

local function RenderRow(row, r, index)
	row.data = r
	row.stripe:SetShown(index % 2 == 0)
	row.icon:SetTexture(r.icon or 134400)
	local color = SKILL_COLORS[r.skillColor] or "|cffffffff"
	row.name:SetText(color .. (r.name or ("Recipe " .. r.recipeID)) .. "|r")
	row.status:SetText(StatusLine(r))

	local cells = row.cells
	if r.costComplete then
		cells.cost:SetText(Money(r.cost))
	elseif r.cost > 0 then
		cells.cost:SetText(Money(r.cost) .. C.warn .. " +?|r")
	else
		cells.cost:SetText(Muted("-"))
	end

	if r.noItemOutput then
		cells.sellsFor:SetText(Muted("no item"))
	else
		cells.sellsFor:SetText(r.sellsFor and Money(r.sellsFor) or Muted("-"))
	end

	if r.profit then
		cells.profit:SetText((r.profit >= 0 and C.good .. "+" or C.bad) .. Money(r.profit) .. "|r")
	else
		cells.profit:SetText(Muted("-"))
	end

	cells.learnCost:SetText(r.learnCost and Money(r.learnCost) or "")
	cells.breakEven:SetText(r.breakEven and ("%d crafts"):format(r.breakEven) or "")
	row:Show()
end

local function UpdateScrollBar()
	local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
	local bar = frame.scrollBar
	bar.updating = true
	bar:SetMinMaxValues(0, maxOffset)
	bar:SetValue(state.offset)
	bar.updating = false
	bar:SetShown(maxOffset > 0)
end

-- Positions headers and cells. Learn columns only show with unlearned recipes; without them
-- the recipe column takes their space.
local function Layout(showLearn)
	local extra = 0
	for _, col in ipairs(COLUMNS) do
		if col.learn and not showLearn then
			extra = extra + col.width + 8
		end
	end
	local nameWidth = COLUMNS[1].width + extra
	local hx, cx = PAD + 42, 42
	for i, col in ipairs(COLUMNS) do
		local visible = showLearn or not col.learn
		local width = i == 1 and nameWidth or col.width
		local header = frame.headers[col.key]
		header:SetShown(visible)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hx, HEADER_Y)
		header:SetWidth(width)
		for _, row in ipairs(rows) do
			if i == 1 then
				row.name:SetWidth(width)
				row.status:SetWidth(width)
			else
				local cell = row.cells[col.key]
				cell:SetShown(visible)
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", cx, 0)
			end
		end
		if visible then
			hx, cx = hx + width + 8, cx + width + 8
		end
	end
	state.layoutLearn = showLearn
end

local function Refresh()
	if not (frame and frame:IsShown() and ns.charDB) then
		return
	end
	local ids = ProfessionIDs()
	if not state.professionID or not ns.charDB.professions[state.professionID] then
		state.professionID = ids[1]
	end
	RenderTabs(ids)
	if state.layoutLearn ~= Settings().includeUnlearned then
		Layout(Settings().includeUnlearned)
	end

	state.data, state.hidden = FilteredRows()
	local s = Settings()
	table.sort(state.data, ns.Profit.Comparator(s.sortKey, s.sortDesc))
	state.offset = math.max(0, math.min(state.offset, #state.data - VISIBLE_ROWS))

	RenderSummary(ids)
	for key, header in pairs(frame.headers) do
		local arrow = s.sortKey == key and (s.sortDesc and ARROW_DOWN or ARROW_UP) or ""
		header.text:SetText(header.label .. arrow)
	end

	for i = 1, VISIBLE_ROWS do
		local r = state.data[i + state.offset]
		if r then
			RenderRow(rows[i], r, i + state.offset)
		else
			rows[i].data = nil
			rows[i]:Hide()
		end
	end
	frame.count:SetText(Muted(("%d recipes"):format(#state.data)))
	frame.empty:SetShown(#ids > 0 and #state.data == 0)
	UpdateScrollBar()
end
ns.RefreshProfitFrame = Refresh

-- Tooltip ------------------------------------------------------------------

local function ShowTooltip(row)
	local r = row.data
	if not r then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r")
	GameTooltip:AddLine(StatusLine(r))


	if r.status ~= "known" then
		if r.learnCost then
			GameTooltip:AddDoubleLine("To learn", ("%s (trainer)"):format(Money(r.learnCost)), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if r.source then
			GameTooltip:AddLine(r.source, 0.8, 0.8, 0.8, true)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Reagents", 1, 0.82, 0)
	if #r.reagents == 0 then
		GameTooltip:AddLine("Unknown - open this profession again.", 1, 0.5, 0.25)
	end
	for _, line in ipairs(r.reagents) do
		local left = ("%d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			local src = line.source == "vendor" and "vendor" or "AH"
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), Muted(src)), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	if r.outputItemID then
		GameTooltip:AddLine(" ")
		local sells = r.sellsFor and ("%s  %s"):format(Money(r.sellsFor), Muted(r.sellSource == "vendor" and "vendor" or "AH, after 5% cut")) or "no price"
		GameTooltip:AddDoubleLine("Sells for", sells, 1, 0.82, 0, 1, 1, 1)
	end
	if r.oldestAge and r.oldestAge > 1 then
		GameTooltip:AddLine(("Oldest price is %d days old."):format(r.oldestAge), 1, 0.6, 0.3)
	end
	if r.breakEven then
		GameTooltip:AddLine(("Learning pays off after %d crafts."):format(r.breakEven), 0.3, 0.82, 0.55)
	end
	if r.bundledOnly then
		GameTooltip:AddLine("From bundled data - open the profession to confirm.", 0.55, 0.55, 0.6, true)
	end
	GameTooltip:Show()
end

-- Construction -------------------------------------------------------------

local function BuildHeader()
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -16)
	title:SetText("|cffffffffCraftWise|r")
	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
	subtitle:SetText(Muted("Crafting profit for every recipe you know or can learn"))

	local close = Style.CloseButton(frame, function()
		frame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -10, -12)

	-- Filter row: search on the left, toggles on the right.
	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
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
	hint:SetText("Search recipes")
	search:SetScript("OnEditFocusGained", function()
		hint:Hide()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		hint:SetShown((self:GetText() or "") == "")
	end)

	local unlearned = Style.Check(frame, "Show unlearned", Settings().includeUnlearned, function(v)
		Settings().includeUnlearned, state.offset = v, 0
		Refresh()
	end)
	unlearned:SetPoint("TOPRIGHT", -PAD - 110, -100)
	local reachable = Style.Check(frame, "Learnable now", Settings().onlyReachable, function(v)
		Settings().onlyReachable, state.offset = v, 0
		Refresh()
	end)
	reachable:SetPoint("RIGHT", unlearned, "LEFT", -24, 0)
	local priced = Style.Check(frame, "Hide unpriced", Settings().hideUnpriced, function(v)
		Settings().hideUnpriced, state.offset = v, 0
		Refresh()
	end)
	priced:SetPoint("RIGHT", reachable, "LEFT", -24, 0)

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.summary:SetPoint("TOPLEFT", PAD, -130)
	frame.summary:SetPoint("RIGHT", -PAD, 0)
	frame.summary:SetJustifyH("LEFT")
end

local function BuildColumns()
	frame.headers = {}
	local x = PAD + 42
	for _, col in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, frame)
		header:SetSize(col.width, 18)
		header:SetPoint("TOPLEFT", x, HEADER_Y)
		header.label = col.label
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.text:SetAllPoints()
		header.text:SetJustifyH(col.align)
		header.text:SetTextColor(0.55, 0.58, 0.65)
		header:SetScript("OnClick", function()
			local s = Settings()
			if s.sortKey == col.key then
				s.sortDesc = not s.sortDesc
			else
				s.sortKey, s.sortDesc = col.key, col.key ~= "name"
			end
			Refresh()
		end)
		frame.headers[col.key] = header
		x = x + col.width + 8
	end
	local line = frame:CreateTexture(nil, "ARTWORK")
	Style.Fill(line, C.border)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, HEADER_Y - 20)
	line:SetPoint("TOPRIGHT", -PAD, HEADER_Y - 20)
end

local function BuildRows()
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame)
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
		row.name:SetWidth(COLUMNS[1].width)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
		row.status:SetWidth(COLUMNS[1].width)
		row.status:SetJustifyH("LEFT")
		row.status:SetWordWrap(false)

		row.cells = {}
		local x = 42 + COLUMNS[1].width + 8
		for c = 2, #COLUMNS do
			local col = COLUMNS[c]
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			fs:SetSize(col.width, ROW_HEIGHT)
			fs:SetPoint("LEFT", x, 0)
			fs:SetJustifyH(col.align)
			fs:SetWordWrap(false)
			row.cells[col.key] = fs
			x = x + col.width + 8
		end

		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			if self.data and C_TradeSkillUI.OpenRecipe then
				pcall(C_TradeSkillUI.OpenRecipe, self.data.recipeID)
			end
		end)
		rows[i] = row
	end
end

local function BuildScrollBar()
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
		state.offset = math.floor(value + 0.5)
		Refresh()
	end)
	frame.scrollBar = bar
end

local function Build()
	frame = CreateFrame("Frame", "CraftWiseFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Style.Panel(frame)
	table.insert(UISpecialFrames, "CraftWiseFrame")

	BuildHeader()
	BuildColumns()
	BuildRows()
	BuildScrollBar()

	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.count:SetPoint("BOTTOMLEFT", PAD, 14)
	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("BOTTOMRIGHT", -PAD, 14)
	help:SetText(Muted("Hover a row for details  ·  click a header to sort  ·  scroll with the mouse wheel"))

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", 0, -40)
	frame.empty:SetText("No recipes match. Clear the search or tick \"Show unlearned\".")

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
		local step = IsShiftKeyDown() and VISIBLE_ROWS or 3
		state.offset = math.max(0, math.min(maxOffset, state.offset - delta * step))
		Refresh()
	end)
	frame:SetScript("OnShow", Refresh)
end

function ns.ToggleProfitFrame()
	if not ns.db then
		return
	end
	if not frame then
		Build()
		frame:Show()
		Refresh()
		return
	end
	frame:SetShown(not frame:IsShown())
end

ns.Listen("RECIPES_CHANGED", Refresh)
ns.Listen("PRICES_CHANGED", Refresh)
ns.On("AUCTION_HOUSE_CLOSED", Refresh) -- Auctionator prices may have changed during a scan
