-- Farm history view (#137): the finished farm sessions (`/craftwise farm history`) in the farm window. A History
-- button next to List/Log lays this panel over the whole window: one line per session (date, duration, zone,
-- coin, items, gold per hour, fishing); a click on one shows its details (stats, zones, top items, fishing) and
-- its loot log, kept for the newest Farm.HISTORY_LOGS sessions. Back returns to the list, then to the session.
-- The numbers are the ones each session kept when it ended (Farm.Summary); this file only draws them, its
-- view models (FH.ListRows, FH.Detail) are plain data for the specs.
local _, ns = ...
local Style, L = ns.Style, ns.L
local C = Style.colors
local Farm = ns.Farm

local FH = {}
ns.FarmHistory = FH

FH.ROW_HEIGHT = 18
FH.VISIBLE_ROWS = 12
FH.LOG_ROWS = 12
FH.STAT_LINES = 20
FH.HEIGHT = 360 -- over the farm window from its top; taller than it without the Fishing panel

local panel
local state = { offset = 0, logOffset = 0, index = nil }

local function Muted(text)
	return C.muted .. text .. "|r"
end

local function Money(copper)
	return copper and ns.FormatMoney(copper) or Muted("-")
end

----------------------------------------------------------------------------------------------------
-- View models
----------------------------------------------------------------------------------------------------

-- One line per finished session, newest first: { index, date, time, zone, coin, items, gph, fish }.
function FH.ListRows(history)
	local out = {}
	for i, h in ipairs(history or {}) do
		local zone = h.zone or "?"
		if (h.zonesMore or 0) > 0 or (h.zones and #h.zones > 1) then
			zone = zone .. Muted((" +%d"):format(math.max(#(h.zones or {}) - 1, 0) + (h.zonesMore or 0)))
		end
		out[i] = { index = i, date = date("%m-%d %H:%M", h.start or 0), time = Farm.FormatTime(h.seconds), zone = zone,
			coin = Money(h.coin), items = Money(h.items) .. ((h.unknown or 0) > 0 and (" " .. C.warn .. "+" .. h.unknown .. "?|r") or ""),
			gph = Money(h.gph), fish = h.fish and (h.fish.catches .. " " .. L["catches"]) or Muted("-") }
	end
	return out
end

-- Details of one session: { title, stats = { { label, value } }, log = entries | nil, logNote }.
function FH.Detail(h)
	local stats = {
		{ L["Started"], date("%Y-%m-%d %H:%M", h.start or 0) },
		{ L["Time"], Farm.FormatTime(h.seconds) },
		{ L["Coin"], Money(h.coin) },
		{ L["Items"], Money(h.items) },
		{ L["Vendor only"], Money(h.vendor) .. ((h.vendorUnknown or 0) > 0 and Muted(" +?") or "") },
		{ L["AH part"], Money(h.ah) .. ((h.stale or 0) > 0 and (" " .. C.warn .. L["stale"] .. " " .. ns.FormatMoney(h.stale) .. "|r") or "") },
		{ L["Gold / hour"], Money(h.gph) },
		{ L["Coin / hour"], Money(h.coinGph) },
		{ L["Unpriced"], (h.unknown or 0) > 0 and (C.warn .. h.unknown .. "|r") or Muted("0") },
	}
	for i, z in ipairs(h.zones or {}) do
		stats[#stats + 1] = { i == 1 and L["Zones"] or "", ("%s  %s  %s%s"):format(z.zone, Farm.FormatTime(z.seconds), Money(z.gph), Muted("/h")) }
	end
	if (h.zonesMore or 0) > 0 then
		stats[#stats + 1] = { "", Muted(("+%d %s"):format(h.zonesMore, L["more zones"])) }
	end
	for i, t in ipairs(h.top or {}) do
		stats[#stats + 1] = { i == 1 and L["Top items"] or "", ("%dx %s  %s"):format(t.n or 0, t.name or ("item " .. tostring(t.id)), Money(t.value)) }
	end
	local f = h.fish
	if f then
		stats[#stats + 1] = { L["Fishing"], ("%d %s, %s %s, %s/h"):format(f.catches, L["catches"], Money(f.perCatch), L["per catch"], Money(f.gph)) }
		if f.best then
			stats[#stats + 1] = { "", L["Best catch"] .. ": " .. (f.best.name or ("item " .. tostring(f.best.id))) .. " " .. Money(f.best.value) }
		end
		if (f.opened or 0) > 0 then
			stats[#stats + 1] = { "", ("%d %s"):format(f.opened, L["containers opened"]) }
		end
	end
	local log, note
	if h.log and #h.log > 0 then
		log = Farm.LogEntries(h)
		note = ("%d %s"):format(#log, L["lines"]) .. ((h.logDropped or 0) > 0 and (" (%d %s)"):format(h.logDropped, L["older dropped"]) or "")
	elseif (h.logLines or 0) > 0 then
		note = (L["Loot log not kept: only the newest %d sessions keep theirs (%d lines)."]):format(Farm.HISTORY_LOGS, h.logLines)
	else
		note = L["No loot log for this session."]
	end
	return { title = ("%s  ·  %s"):format(date("%m-%d %H:%M", h.start or 0), h.zone or "?"), stats = stats, log = log, logNote = note }
end

----------------------------------------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------------------------------------

local LIST_COLUMNS = { { "date", 74 }, { "time", 58 }, { "zone", 100 }, { "coin", 72, "RIGHT" }, { "items", 80, "RIGHT" },
	{ "gph", 72, "RIGHT" }, { "fish", 64, "RIGHT" } }
local LIST_LABELS = { date = "STARTED", time = "TIME", zone = "ZONE", coin = "COIN", items = "ITEMS", gph = "GOLD / H",
	fish = "FISHING" }

local function Line(parent, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, FH.ROW_HEIGHT)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	Style.Fill(hl, C.hover)
	return row
end

local function BuildList()
	local list = CreateFrame("Frame", nil, panel)
	list:SetAllPoints()
	panel.list = list
	local x = 12
	for _, col in ipairs(LIST_COLUMNS) do
		local h = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", x, -38)
		h:SetWidth(col[2])
		h:SetJustifyH(col[3] or "LEFT")
		h:SetTextColor(0.55, 0.58, 0.65)
		h:SetText(L[LIST_LABELS[col[1]]])
		x = x + col[2] + 4
	end
	list.rows = {}
	for i = 1, FH.VISIBLE_ROWS do
		local row = Line(list, x - 12)
		row:SetPoint("TOPLEFT", 8, -54 - (i - 1) * FH.ROW_HEIGHT)
		Style.Fill(row.bg, i % 2 == 0 and C.stripe or { 0, 0, 0, 0 })
		row.cells = {}
		local cx = 4
		for _, col in ipairs(LIST_COLUMNS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(col[2])
			fs:SetJustifyH(col[3] or "LEFT")
			fs:SetWordWrap(false)
			row.cells[col[1]] = fs
			cx = cx + col[2] + 4
		end
		row:SetScript("OnClick", function(self)
			if self.data then
				FH.Open(self.data.index)
			end
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L["Click for the session's details and loot log."], 0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		list.rows[i] = row
	end
	list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	list.empty:SetPoint("CENTER")
	list.empty:SetText(L["No finished farm session yet: Reset ends one and keeps it here."])
end

local function BuildDetail()
	local detail = CreateFrame("Frame", nil, panel)
	detail:SetAllPoints()
	panel.detail = detail
	detail.labels, detail.values = {}, {}
	for i = 1, FH.STAT_LINES do
		local y = -40 - (i - 1) * 15
		local label = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 12, y)
		label:SetWidth(78)
		label:SetJustifyH("LEFT")
		local value = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOPLEFT", 92, y)
		value:SetWidth(170)
		value:SetJustifyH("LEFT")
		value:SetWordWrap(false)
		detail.labels[i], detail.values[i] = label, value
	end
	local lx = 276
	detail.logHead = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	detail.logHead:SetPoint("TOPLEFT", lx, -40)
	detail.logRows = {}
	for i = 1, FH.LOG_ROWS do
		local row = Line(detail, 288)
		row:SetPoint("TOPLEFT", lx, -56 - (i - 1) * FH.ROW_HEIGHT)
		Style.Fill(row.bg, i % 2 == 0 and C.stripe or { 0, 0, 0, 0 })
		row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.time:SetPoint("LEFT", 2, 0)
		row.time:SetWidth(48)
		row.time:SetJustifyH("LEFT")
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 52, 0)
		row.name:SetWidth(120)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.zone:SetPoint("RIGHT", 0, 0)
		row.zone:SetWidth(50)
		row.zone:SetJustifyH("RIGHT")
		row.zone:SetWordWrap(false)
		row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", row.zone, "LEFT", -4, 0)
		row.value:SetJustifyH("RIGHT")
		row:SetScript("OnEnter", function(self)
			local e = self.data
			if not e then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if e.itemID and GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(e.itemID)
			else
				GameTooltip:AddLine(L["Coin"])
			end
			GameTooltip:AddDoubleLine(L["Looted at"], date("%H:%M:%S", e.t), 0.8, 0.8, 0.8, 1, 1, 1)
			GameTooltip:AddDoubleLine(L["Zone"], e.zone, 0.8, 0.8, 0.8, 1, 1, 1)
			if e.fish then
				GameTooltip:AddLine(L["From a fishing catch."], 0.5, 0.8, 1, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		detail.logRows[i] = row
	end
	detail.logEmpty = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	detail.logEmpty:SetPoint("TOPLEFT", lx, -80)
	detail.logEmpty:SetWidth(280)
	detail.logEmpty:SetJustifyH("LEFT")
end

local function Build(parent)
	panel = CreateFrame("Frame", "CraftWiseFarmHistory", parent, "BackdropTemplate")
	panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	panel:SetSize(parent:GetWidth() or 572, FH.HEIGHT)
	panel:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	panel:EnableMouse(true)
	Style.Panel(panel)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -12)
	title:SetText("|cffffffffCraftWise|r " .. Muted(L["Farm history"]))
	panel.head = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.head:SetPoint("LEFT", title, "RIGHT", 10, 0)
	local close = Style.CloseButton(panel, function()
		FH.Close()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)
	panel.back = Style.Button(panel, 70, 20, L["Back"])
	panel.back:SetPoint("RIGHT", close, "LEFT", -6, 0)
	panel.back:SetScript("OnClick", function()
		if state.index then
			state.index, state.logOffset = nil, 0
			FH.Refresh()
		else
			FH.Close()
		end
	end)
	BuildList()
	BuildDetail()
	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		if state.index then
			state.logOffset = math.max(0, state.logOffset - delta * 3)
		else
			state.offset = math.max(0, state.offset - delta * 3)
		end
		FH.Refresh()
	end)
	panel:Hide()
end

----------------------------------------------------------------------------------------------------
-- Refresh and opening
----------------------------------------------------------------------------------------------------

local function RenderList(history)
	local rows = FH.ListRows(history)
	state.offset = math.max(0, math.min(state.offset, #rows - FH.VISIBLE_ROWS))
	panel.head:SetText(Muted(("%d %s"):format(#rows, #rows == 1 and L["session"] or L["sessions"])))
	panel.back:SetLabel(L["Session"])
	panel.list:Show()
	panel.detail:Hide()
	panel.list.empty:SetShown(#rows == 0)
	for i, row in ipairs(panel.list.rows) do
		local r = rows[state.offset + i]
		row.data = r
		if r then
			for key, fs in pairs(row.cells) do
				fs:SetText(r[key] or "")
			end
			row:Show()
		else
			row:Hide()
		end
	end
end

local function RenderDetail(h)
	local d = FH.Detail(h)
	panel.head:SetText(Muted(d.title))
	panel.back:SetLabel(L["Back"])
	panel.list:Hide()
	panel.detail:Show()
	local det = panel.detail
	for i, label in ipairs(det.labels) do
		local s = d.stats[i]
		label:SetText(s and Muted(s[1]) or "")
		det.values[i]:SetText(s and s[2] or "")
	end
	det.logHead:SetText(Muted(L["Loot log"] .. "  ·  " .. d.logNote))
	local log = d.log or {}
	state.logOffset = math.max(0, math.min(state.logOffset, #log - FH.LOG_ROWS))
	det.logEmpty:SetShown(#log == 0)
	det.logEmpty:SetText(#log == 0 and d.logNote or "")
	for i, row in ipairs(det.logRows) do
		local e = log[state.logOffset + i]
		row.data = e
		if e then
			row.time:SetText(Muted(date("%H:%M:%S", e.t)))
			local name = e.itemID and ((e.n > 1 and (C.warn .. e.n .. "x|r ") or "") .. ns.FarmFrame.ItemText(e)) or L["Coin"]
			row.name:SetText((e.fish and (ns.FarmFrame.FISH_MARK .. " ") or "") .. name)
			row.value:SetText(ns.FarmFrame.LogValueText(e))
			row.zone:SetText(Muted(e.zone))
			row:Show()
		else
			row:Hide()
		end
	end
end

function FH.Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	local history = Farm.History() or {}
	local h = state.index and history[state.index]
	if state.index and not h then
		state.index = nil
	end
	if h then
		RenderDetail(h)
	else
		RenderList(history)
	end
end

-- Shows the history over the farm window (opening it when hidden); index opens one session's details.
function FH.Open(index)
	local ff = ns.FarmFrame
	if not (ff and ff.Window) then
		return
	end
	if not ff.IsShown() then
		Farm.Slash("show")
	end
	local parent = ff.Window()
	if not parent then
		return
	end
	if not panel then
		Build(parent)
	end
	if index ~= state.index then
		state.logOffset = 0
	end
	state.index = index
	panel:Show()
	FH.Refresh()
end

function FH.Close()
	if panel then
		panel:Hide()
	end
	state.index = nil
end

function FH.Toggle()
	if panel and panel:IsShown() then
		FH.Close()
	else
		FH.Open()
	end
end

function FH.IsShown()
	return panel ~= nil and panel:IsShown()
end

function FH.State()
	return state
end

ns.Listen("FARM_CHANGED", FH.Refresh)
