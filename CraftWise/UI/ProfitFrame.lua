-- Profit table window (/cw). Built lazily on first open, from plain widgets only.
local _, ns = ...

local ROW_HEIGHT, VISIBLE_ROWS = 24, 16
local WIDTH = 820

local COLUMNS = {
	{ key = "name", label = "Recipe", width = 250, align = "LEFT" },
	{ key = "status", label = "Status", width = 110, align = "LEFT" },
	{ key = "cost", label = "Cost", width = 95, align = "RIGHT" },
	{ key = "sellsFor", label = "Sells for", width = 95, align = "RIGHT" },
	{ key = "profit", label = "Profit", width = 95, align = "RIGHT" },
	{ key = "learnCost", label = "Learn", width = 80, align = "RIGHT" },
	{ key = "breakEven", label = "Break-even", width = 75, align = "RIGHT" },
}

local STATUS_TEXT = {
	known = "|cff9d9d9dKnown|r",
	trainable = "|cff40ff40Trainable|r",
	later = "|cffffd100Trainable at %d|r",
	unlearned = "|cffff8040Not learned|r",
}

local frame, rows, tabs = nil, {}, {}
local state = { professionID = nil, offset = 0, data = {} }

local function Money(copper)
	return ns.FormatMoney(copper)
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and GetItemInfo then
		name = GetItemInfo(itemID)
	end
	return name or ("item:" .. itemID)
end

local function SourceLabel(source)
	if source == "vendor" then
		return "vendor"
	elseif source == "auction" then
		return "AH"
	end
	return source or ""
end

local function Settings()
	return ns.db.settings
end

-- Sorting ---------------------------------------------------------------

local function SortData()
	local s = Settings()
	table.sort(state.data, ns.Profit.Comparator(s.sortKey, s.sortDesc))
end

local function Refresh()
	if not (frame and frame:IsShown() and ns.charDB) then
		return
	end
	-- Profession tabs: one per cached profession with recipes.
	local ids = {}
	for id, prof in pairs(ns.charDB.professions) do
		if next(prof.recipes) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return (ns.charDB.professions[a].name or "") < (ns.charDB.professions[b].name or "")
	end)
	if not state.professionID or not ns.charDB.professions[state.professionID] then
		state.professionID = ids[1]
	end
	for i, id in ipairs(ids) do
		local tab = tabs[i]
		if not tab then
			tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			tab:SetSize(130, 22)
			tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (i - 1) * 134, -34)
			tabs[i] = tab
		end
		local prof = ns.charDB.professions[id]
		tab:SetText(("%s %d"):format(prof.name or "?", prof.skill or 0))
		tab:SetScript("OnClick", function()
			state.professionID, state.offset = id, 0
			Refresh()
		end)
		if id == state.professionID then
			tab:LockHighlight()
		else
			tab:UnlockHighlight()
		end
		tab:Show()
	end
	for i = #ids + 1, #tabs do
		tabs[i]:Hide()
	end

	state.data = state.professionID and ns.BuildRows(state.professionID, Settings().includeUnlearned) or {}
	SortData()

	-- Status line
	local profitable, priced = 0, 0
	for _, r in ipairs(state.data) do
		if r.profit then
			priced = priced + 1
			if r.profit > 0 then
				profitable = profitable + 1
			end
		end
	end
	local line
	if #ids == 0 then
		line = "|cffffd100Open a profession window once so CraftWise can read your recipes.|r"
	elseif not ns.HasAuctionator() then
		line = "|cffff8040Auctionator not found - only vendor prices are used.|r Install Auctionator and run a full scan."
	else
		line = ("%d of %d recipes make a profit. Prices come from your last Auctionator scan."):format(profitable, priced)
	end
	frame.statusText:SetText(line)

	local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
	state.offset = math.min(state.offset, maxOffset)

	for i = 1, VISIBLE_ROWS do
		local row, r = rows[i], state.data[i + state.offset]
		if r then
			row.data = r
			row.icon:SetTexture(r.icon or 134400)
			row.cells.name:SetText(r.name or ("recipe " .. r.recipeID))
			local status = STATUS_TEXT[r.status] or r.status
			if r.status == "later" then
				status = status:format(r.required or 0)
			end
			row.cells.status:SetText(status)
			if r.costComplete then
				row.cells.cost:SetText(Money(r.cost))
			elseif r.cost > 0 then
				row.cells.cost:SetText(Money(r.cost) .. " |cffff8040+?|r") -- partial: some reagents unpriced
			else
				row.cells.cost:SetText("|cff9d9d9d?|r")
			end
			if r.noItemOutput then
				row.cells.sellsFor:SetText("|cff9d9d9d-|r")
			else
				row.cells.sellsFor:SetText(r.sellsFor and Money(r.sellsFor) or "|cff9d9d9d?|r")
			end
			if r.profit then
				local color = r.profit >= 0 and "|cff40ff40+" or "|cffff4040"
				row.cells.profit:SetText(color .. Money(r.profit) .. "|r")
			else
				row.cells.profit:SetText("|cff9d9d9d?|r")
			end
			row.cells.learnCost:SetText(r.learnCost and Money(r.learnCost) or "")
			row.cells.breakEven:SetText(r.breakEven and (r.breakEven .. " crafts") or "")
			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end
	frame.empty:SetShown(#ids > 0 and #state.data == 0)
end
ns.RefreshProfitFrame = Refresh

-- Tooltip ---------------------------------------------------------------

local function ShowTooltip(row)
	local r = row.data
	if not r then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(r.name or "?", 1, 1, 1)
	if r.source and r.status ~= "known" then
		GameTooltip:AddLine(r.source, 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine(" ")
	if #r.reagents == 0 then
		GameTooltip:AddLine("Reagents unknown - open this profession again.", 1, 0.5, 0.25)
	end
	for _, line in ipairs(r.reagents) do
		local left = ("%dx %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s (%s)"):format(Money(line.total), SourceLabel(line.source)), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	GameTooltip:AddLine(" ")
	if r.outputItemID then
		local sells = r.sellsFor and ("%s (%s)"):format(Money(r.sellsFor), r.sellSource == "vendor" and "vendor" or "AH, after 5% cut") or "no price"
		GameTooltip:AddDoubleLine("Sells for", sells, 1, 0.82, 0, 1, 1, 1)
	end
	if r.oldestAge and r.oldestAge > 1 then
		GameTooltip:AddLine(("Oldest price is %d days old."):format(r.oldestAge), 1, 0.5, 0.25)
	end
	if r.breakEven then
		GameTooltip:AddLine(("Learning pays off after %d crafts."):format(r.breakEven), 0.25, 1, 0.25)
	end
	GameTooltip:Show()
end

-- Construction ----------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", "CraftWiseFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 132 + VISIBLE_ROWS * ROW_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.06, 0.07, 0.10, 0.95)
	frame:SetBackdropBorderColor(0.3, 0.35, 0.45, 1)
	table.insert(UISpecialFrames, "CraftWiseFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -12)
	title:SetText("CraftWise - crafting profit")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPRIGHT", -150, -34)
	check:SetChecked(Settings().includeUnlearned)
	check:SetScript("OnClick", function(self)
		Settings().includeUnlearned = self:GetChecked() and true or false
		Refresh()
	end)
	local checkLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
	checkLabel:SetText("Show unlearned")

	frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.statusText:SetPoint("TOPLEFT", 16, -64)
	frame.statusText:SetPoint("RIGHT", -16, 0)
	frame.statusText:SetJustifyH("LEFT")

	-- Column headers (click to sort, click again to flip)
	local x = 44
	for _, col in ipairs(COLUMNS) do
		local header = CreateFrame("Button", nil, frame)
		header:SetSize(col.width, 18)
		header:SetPoint("TOPLEFT", x, -84)
		local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetAllPoints()
		text:SetJustifyH(col.align)
		text:SetText(col.label)
		header:SetScript("OnClick", function()
			local s = Settings()
			if s.sortKey == col.key then
				s.sortDesc = not s.sortDesc
			else
				s.sortKey, s.sortDesc = col.key, col.key ~= "name" and col.key ~= "status"
			end
			Refresh()
		end)
		x = x + col.width + 4
	end

	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 28, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 14, -104 - (i - 1) * ROW_HEIGHT)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 4, 0)
		row.cells = {}
		local cx = 30
		for _, col in ipairs(COLUMNS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetSize(col.width, ROW_HEIGHT)
			fs:SetPoint("LEFT", cx, 0)
			fs:SetJustifyH(col.align)
			fs:SetWordWrap(false)
			row.cells[col.key] = fs
			cx = cx + col.width + 4
		end
		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			local r = self.data
			if r and C_TradeSkillUI.OpenRecipe then
				pcall(C_TradeSkillUI.OpenRecipe, r.recipeID)
			end
		end)
		rows[i] = row
	end

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", 0, -20)
	frame.empty:SetText("No recipes to show. Tick \"Show unlearned\" or open the profession again.")

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
