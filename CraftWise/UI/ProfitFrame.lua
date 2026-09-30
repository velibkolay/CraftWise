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

-- Column definitions; each view lists the columns it shows, in order, with widths.
local COLUMN_DEFS = {
	name = { label = "RECIPE", align = "LEFT" },
	cost = { label = "COST", align = "RIGHT" },
	sellsFor = { label = "SELLS FOR", align = "RIGHT" },
	profit = { label = "PROFIT", align = "RIGHT" },
	learnCost = { label = "TO LEARN", align = "RIGHT" },
	breakEven = { label = "PAYS OFF", align = "RIGHT" },
	required = { label = "SKILL", align = "RIGHT" },
	whereText = { label = "WHERE TO GET IT", align = "LEFT" },
}
local VIEWS = {
	-- Profit: what to craft. The learn columns only show with unlearned recipes.
	profit = {
		{ key = "name", width = 290 },
		{ key = "cost", width = 100 },
		{ key = "sellsFor", width = 100 },
		{ key = "profit", width = 100 },
		{ key = "learnCost", width = 95, learn = true },
		{ key = "breakEven", width = 75, learn = true },
	},
	-- Learn: every recipe you don't know yet, where to get it and what it earns.
	learn = {
		{ key = "name", width = 245 },
		{ key = "required", width = 50 },
		{ key = "whereText", width = 280 },
		{ key = "learnCost", width = 95 },
		{ key = "profit", width = 100 },
	},
}
local CELL_KEYS = { "cost", "sellsFor", "profit", "learnCost", "breakEven", "required", "whereText" }

local STATUS_TEXT = {
	known = "Known",
	trainable = "Trainer",
	vendor = "Vendor recipe",
	drop = "Drop recipe",
	quest = "Quest recipe",
	unlearned = "Source not known yet",
}

-- Texture arrows: the game font has no triangle glyphs.
local ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t"
local ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:3|t"

-- Recipe name colours as in the game's profession window.
local SKILL_COLORS = {
	red = "|cffff4040", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080",
}

local frame, rows, tabs, viewButtons = nil, {}, {}, {}
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

local function View()
	return Settings().view == "learn" and "learn" or "profit"
end

-- Rows after the search box and the view's filters; also returns how many the filters hid.
local function FilteredRows()
	local s = Settings()
	local learnView = View() == "learn"
	local all = state.professionID and ns.BuildRows(state.professionID, learnView or s.includeUnlearned) or {}
	local query = state.query:lower()
	local out, hidden = {}, 0
	for _, r in ipairs(all) do
		local keep = query == "" or (r.name or ""):lower():find(query, 1, true)
		if keep and learnView then
			if r.status == "known" then
				keep = false
			elseif s.learnFitsSkill and (not r.required or r.tooLow) then
				-- fits your skill only when the requirement is known and met
				keep, hidden = false, hidden + 1
			end
		elseif keep and s.hideUnpriced and not r.profit then
			keep, hidden = false, hidden + 1
		end
		if keep then
			if learnView then
				r.where = ns.RecipeWhere(r.recipeID)
				r.whereText = r.where[1] and r.where[1].text or nil
			end
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
	elseif View() == "learn" then
		local withSource, fits = 0, 0
		for _, r in ipairs(state.data) do
			if r.whereText then
				withSource = withSource + 1
			end
			if r.required and not r.tooLow then
				fits = fits + 1
			end
		end
		text = ("%d recipes to learn  ·  %s%d|r with a known source  ·  %s%d|r fit your skill"):format(#state.data, C.good, withSource, C.good, fits)
		if withSource == 0 then
			text = text .. "\n" .. Muted("Sources come with the recipe data (issue #11). Recipes your trainer teaches appear after you open the trainer once.")
		end
		if state.hidden > 0 then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
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
		if state.hidden > 0 then
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
	if r.required then
		cells.required:SetText((r.tooLow and C.warn or C.good) .. r.required .. "|r")
	else
		cells.required:SetText(Muted("?"))
	end
	if r.whereText then
		local more = #r.where > 1 and Muted(("  +%d"):format(#r.where - 1)) or ""
		cells.whereText:SetText(r.whereText .. more)
	else
		cells.whereText:SetText(Muted("Not known yet"))
	end
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

-- Positions headers and cells for a view. In the profit view the learn columns only show with
-- unlearned recipes; without them the recipe column takes their space.
local function Layout(view, showLearn)
	local cols = VIEWS[view]
	local extra = 0
	for _, col in ipairs(cols) do
		if col.learn and not showLearn then
			extra = extra + col.width + 8
		end
	end
	local visibleKeys = {}
	local hx, cx = PAD + 42, 42
	for i, col in ipairs(cols) do
		local visible = showLearn or not col.learn
		local width = i == 1 and (col.width + extra) or col.width
		local header = frame.headers[col.key]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hx, HEADER_Y)
		header:SetWidth(width)
		header:SetShown(visible)
		visibleKeys[col.key] = visible
		for _, row in ipairs(rows) do
			if i == 1 then
				row.name:SetWidth(width)
				row.status:SetWidth(width)
			else
				local cell = row.cells[col.key]
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", cx, 0)
				cell:SetWidth(width)
			end
		end
		if visible then
			hx, cx = hx + width + 8, cx + width + 8
		end
	end
	-- Hide everything the view doesn't use.
	for key, header in pairs(frame.headers) do
		if not visibleKeys[key] then
			header:Hide()
		end
	end
	for _, row in ipairs(rows) do
		for _, key in ipairs(CELL_KEYS) do
			row.cells[key]:SetShown(visibleKeys[key] or false)
		end
	end
	state.layout = view .. tostring(showLearn)
end

local function SortSettings()
	local s = Settings()
	if View() == "learn" then
		return s.learnSortKey or "required", s.learnSortDesc
	end
	return s.sortKey, s.sortDesc
end

local function UpdateControls()
	local learnView = View() == "learn"
	for key, button in pairs(viewButtons) do
		button:SetSelected(key == View())
	end
	frame.priced:SetShown(not learnView)
	frame.unlearned:SetShown(not learnView)
	frame.fits:SetShown(learnView)
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
	UpdateControls()
	local showLearn = View() == "learn" or Settings().includeUnlearned
	if state.layout ~= View() .. tostring(showLearn) then
		Layout(View(), showLearn)
	end

	state.data, state.hidden = FilteredRows()
	local sortKey, sortDesc = SortSettings()
	table.sort(state.data, ns.Profit.Comparator(sortKey, sortDesc))
	state.offset = math.max(0, math.min(state.offset, #state.data - VISIBLE_ROWS))

	RenderSummary(ids)
	for key, header in pairs(frame.headers) do
		local arrow = sortKey == key and (sortDesc and ARROW_DOWN or ARROW_UP) or ""
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
	frame.empty:SetText(View() == "learn" and "No recipes match. Clear the search or untick \"Fits my skill\"."
		or "No recipes match. Clear the search or tick \"Show unlearned\".")
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
	-- The crafted item's own tooltip first (item level, stats, requirements, other addons' lines),
	-- then a CraftWise section. Recipes without an item output get the CraftWise section only.
	if r.outputItemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.outputItemID)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("CraftWise", C.accent[1], C.accent[2], C.accent[3])
		GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r  " .. StatusLine(r))
	else
		GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r")
		GameTooltip:AddLine(StatusLine(r))
	end


	if r.status ~= "known" then
		if r.learnCost then
			local how = r.learnSource == "vendor" and "vendor" or r.learnSource == "auction" and "AH" or "trainer"
			GameTooltip:AddDoubleLine("To learn", ("%s (%s)"):format(Money(r.learnCost), how), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		local where = r.where or ns.RecipeWhere(r.recipeID)
		if #where > 0 then
			GameTooltip:AddLine("Where to get it", 1, 0.82, 0)
			for i = 1, math.min(6, #where) do
				local w = where[i]
				local color = w.own == false and C.info or ""
				GameTooltip:AddLine("  " .. color .. w.text .. (w.own == false and (" (" .. (w.faction == "H" and "Horde" or "Alliance") .. ")|r") or ""), 0.9, 0.9, 0.9, true)
			end
			if #where > 6 then
				GameTooltip:AddLine(("  +%d more"):format(#where - 6), 0.6, 0.6, 0.6)
			end
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
	subtitle:SetText(Muted("Crafting profit and what to learn next"))

	-- View switch: Profit (what to craft) | Learn (what to learn and where).
	local learnBtn = Style.Button(frame, 90, 24, "Learn")
	learnBtn:SetPoint("TOPRIGHT", -44, -14)
	local profitBtn = Style.Button(frame, 90, 24, "Profit")
	profitBtn:SetPoint("RIGHT", learnBtn, "LEFT", -6, 0)
	viewButtons.profit, viewButtons.learn = profitBtn, learnBtn
	for key, button in pairs(viewButtons) do
		button:SetScript("OnClick", function()
			Settings().view, state.offset = key, 0
			Refresh()
		end)
	end

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
	local priced = Style.Check(frame, "Hide unpriced", Settings().hideUnpriced, function(v)
		Settings().hideUnpriced, state.offset = v, 0
		Refresh()
	end)
	priced:SetPoint("RIGHT", unlearned, "LEFT", -24, 0)
	local fits = Style.Check(frame, "Fits my skill", Settings().learnFitsSkill, function(v)
		Settings().learnFitsSkill, state.offset = v, 0
		Refresh()
	end)
	fits:SetPoint("TOPRIGHT", -PAD - 110, -100)
	frame.unlearned, frame.priced, frame.fits = unlearned, priced, fits

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.summary:SetPoint("TOPLEFT", PAD, -130)
	frame.summary:SetPoint("RIGHT", -PAD, 0)
	frame.summary:SetJustifyH("LEFT")
end

local function BuildColumns()
	frame.headers = {}
	for key, def in pairs(COLUMN_DEFS) do
		local header = CreateFrame("Button", nil, frame)
		header:SetSize(100, 18)
		header.label = def.label
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.text:SetAllPoints()
		header.text:SetJustifyH(def.align)
		header.text:SetTextColor(0.55, 0.58, 0.65)
		header:SetScript("OnClick", function()
			local s = Settings()
			local ascending = key == "name" or key == "whereText" or key == "required"
			if View() == "learn" then
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
		frame.headers[key] = header
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
