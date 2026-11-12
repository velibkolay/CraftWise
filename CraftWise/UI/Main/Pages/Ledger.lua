-- Main window, Sell › Ledger (#155; spec in #150 "Sell", board "Sell › Ledger"): period chips Since reset,
-- Today, Since login, Per day (default Per day). Per day: one row per recorded day (today with the nokta)
-- with its money change as a zero-centred rail; the hero sums the recorded days. The other periods list
-- the items bought and sold (the Records ledger columns). Reset ledger in the footer asks twice ("Click
-- again" for 3 s). Replaces Records › Ledger. Sources: Ledger.lua (L.Days, L.Summary, L.View, L.Reset);
-- this file only draws them. Row data (P.DayRows, P.ItemRows) is kept apart from the drawing.
local _, ns = ...
local M = ns.Main
local S = M.Sell
local Style, L = ns.Style, ns.L
local C = Style.C

local P = {}

P.ARM_SECONDS = 3 -- spec: the first click turns Reset into "Click again" for 3 s
P.ZERO_AT = 0.3 -- where zero sits on the money change rail (board "Sell › Ledger")

-- Period chips in the board's order; "days" is Per day, the others are Ledger.lua's views.
P.PERIODS = {
	{ key = "reset", label = L["Since reset"] },
	{ key = "today", label = L["Today"] },
	{ key = "login", label = L["Since login"] },
	{ key = "days", label = L["Per day"] },
}
local PERIOD_LABEL = {}
for _, p in ipairs(P.PERIODS) do
	PERIOD_LABEL[p.key] = p.label
end

-- The chosen period: Per day unless an item period was chosen (settings.ledgerPerDay = false); the item
-- period is the one /craftwise ledger uses (settings.ledgerView, L.View()).
function P.Period()
	if ns.db.settings.ledgerPerDay == false then
		return ns.Ledger.View()
	end
	return "days"
end

function P.SetPeriod(key)
	local s = ns.db.settings
	if key == "days" then
		s.ledgerPerDay = nil
	else
		s.ledgerPerDay = false
		s.ledgerView = key
	end
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Rows (data)
----------------------------------------------------------------------------------------------------

local function DayTime(day)
	local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
	return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
end

-- "Today", "Wed 11".
function P.DayLabel(day, today)
	if day == today then
		return L["Today"]
	end
	local t = DayTime(day)
	return date("%a", t) .. " " .. tonumber(day:match("(%d+)$"))
end

-- Per day rows from L.Days(), newest first: { key, name, today, start, spent, received, change, other }.
function P.DayRows(days, today)
	local rows = {}
	for _, d in ipairs(days or {}) do
		local row = { key = d.day, day = d.day, name = P.DayLabel(d.day, today), today = d.day == today,
			start = d.startMoney, spent = d.spent, received = d.received, change = d.change, other = d.other }
		if d.other and d.other ~= 0 then
			row.tip = { row.name, L["Not from logged trades"] .. " " .. S.Signed(d.other) }
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- The hero of Per day: the money change over the recorded days, with Spent, Received and Not from
-- logged trades. Days whose end is unknown add their spent and received only.
function P.DaysHero(days)
	if not days or #days == 0 then
		return nil
	end
	local h = { days = #days, spent = 0, received = 0 }
	for _, d in ipairs(days) do
		h.spent = h.spent + (d.spent or 0)
		h.received = h.received + (d.received or 0)
		if d.change then
			h.change = (h.change or 0) + d.change
		end
		if d.other then
			h.other = (h.other or 0) + d.other
		end
	end
	h.label = #days == 1 and L["Today"] or (L["Last %d days"]):format(#days)
	h.caption = L["money change"] .. " · " .. S.Count(#days, L["day recorded"], L["days recorded"])
	return h
end

-- The hero of an item period, from L.Summary(view).
function P.SummaryHero(sum)
	return { label = PERIOD_LABEL[sum.view] or sum.label, change = sum.change, spent = sum.spent,
		received = sum.received, other = sum.other,
		caption = sum.startMoney and (L["money change"] .. " · " .. L["start"] .. " " .. ns.FormatCoins(sum.startMoney))
			or L["money change"] }
end

-- Item rows of a period (the Records ledger columns): { key, itemID, name, quality, where, bought, spent,
-- sold, received, net }.
function P.ItemRows(sum)
	local rows, ids = {}, {}
	for _, r in ipairs(sum and sum.items or {}) do
		local where = {}
		for label in pairs(r.sources or {}) do
			where[#where + 1] = label
		end
		table.sort(where)
		local name, quality = S.ItemName(r.itemID, { name = r.name, link = r.link })
		rows[#rows + 1] = { key = r.itemID, itemID = r.itemID, name = name, quality = quality,
			where = #where > 0 and table.concat(where, ", ") or nil,
			bought = r.bought, spent = r.spent, sold = r.sold, received = r.received, net = r.received - r.spent }
		if not (r.name or r.link) then -- a name kept with the entry needs no request (#59)
			ids[#ids + 1] = r.itemID
		end
	end
	return rows, ids
end

function P.Model(ctx)
	local Ledger = ns.Ledger
	local period = P.Period()
	if period == "days" then
		local days = Ledger.Days()
		local hero = P.DaysHero(days)
		if hero then
			hero.full, hero.height = true, 80
		end
		return { rows = P.DayRows(days, Ledger.DayKey()), hero = hero,
			footer = L["A day ends with the money the next recorded day started with."],
			empty = L["No day recorded yet for this character."] }
	end
	local sum = Ledger.Summary(period)
	if not sum then
		return { rows = {}, empty = L["The ledger starts once the client shows this character's money."] }
	end
	local rows, ids = P.ItemRows(sum)
	S.LoadNames(ids)
	local hero = P.SummaryHero(sum)
	hero.full, hero.height = true, 80
	return { rows = rows, hero = hero,
		footer = L["Net = received − spent. Not from logged trades: loot, quests, repairs, fees."],
		empty = L["No purchase or sale recorded in this period."] }
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function Minus(copper)
	return copper and copper > 0 and ("−" .. ns.FormatCoins(copper)) or M.DASH
end

local function Plus(copper)
	return copper and copper > 0 and ("+" .. ns.FormatCoins(copper)) or M.DASH
end

local function ChangeColor(v)
	return v and v < 0 and "danger" or "text"
end

P.DAY_COLUMNS = {
	{ key = "name", label = L["Day"], width = 90, font = "BodyBold" },
	{ key = "start", label = L["Start"], width = 90, align = "RIGHT", font = "Figure", color = function() return "text2" end,
		text = function(r) return S.Coins(r.start) or M.DASH end },
	{ key = "spent", label = L["Spent"], width = 90, align = "RIGHT", font = "Figure", text = function(r) return Minus(r.spent) end },
	{ key = "received", label = L["Received"], width = 90, align = "RIGHT", font = "Figure",
		text = function(r) return Plus(r.received) end },
	{ key = "rail", label = L["Money change"], text = function() return "" end },
	{ key = "change", width = 96, align = "RIGHT", font = "FigureBold", color = function(r) return ChangeColor(r.change) end,
		text = function(r) return S.Signed(r.change) or M.DASH end,
		tip = function(r)
			if r.change == nil then
				return { L["Money change unknown"], L["The money at the end of this day was not seen."] }
			end
		end },
}
local RAIL_COLUMN = 5

P.ITEM_COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Item"], color = function(r) return S.QualityColor(r.quality) end },
	{ key = "where", label = L["Bought at"], width = 120, font = "Small", color = function() return "text2" end,
		text = function(r) return r.where or "" end },
	{ key = "bought", label = L["Bought"], width = 110, align = "RIGHT", font = "Figure",
		text = function(r) return r.bought > 0 and (r.bought .. "  " .. ns.FormatCoins(r.spent)) or M.DASH end },
	{ key = "sold", label = L["Sold"], width = 110, align = "RIGHT", font = "Figure",
		text = function(r)
			return (r.sold ~= 0 or r.received ~= 0) and (r.sold .. "  " .. ns.FormatCoins(r.received)) or M.DASH
		end },
	{ key = "net", label = L["Net"], width = 96, align = "RIGHT", font = "FigureBold",
		color = function(r) return ChangeColor(r.net) end, text = function(r) return S.Signed(r.net) end },
}

function P.Columns()
	return P.Period() == "days" and P.DAY_COLUMNS or P.ITEM_COLUMNS
end

function P.InitRow(b, data, ctx)
	if data.day == nil then
		if b.cwRail then
			b.cwRail:Hide()
		end
		if b.cwToday then
			b.cwToday:Hide()
		end
		return
	end
	-- today: the nokta before its name and C.selected behind the row (board)
	b.cwToday = b.cwToday or Style.Nokta(b)
	local name = b.cells[1]
	if data.today then
		name:ClearAllPoints()
		name:SetPoint("LEFT", b, "LEFT", 22 + 14, 0)
		b.cwToday:ClearAllPoints()
		b.cwToday:SetPoint("CENTER", b, "LEFT", 22 + 5.5, 0)
		b.cwToday:Show()
		b.bg:Show()
	else
		b.cwToday:Hide()
	end
	-- the money change rail: zero-centred, one shared scale over the list, today's bar in C.text
	b.cwRail = b.cwRail or Style.Rail(b, P.ZERO_AT)
	local cell = b.cells[RAIL_COLUMN]
	b.cwRail:ClearAllPoints()
	b.cwRail:SetPoint("LEFT", cell, "LEFT", 0, 0)
	b.cwRail:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
	b.cwRail:SetHeight(16)
	b.cwRail:Show()
	b.cwRail:SetValue(data.change, ctx and ctx.railMax or 0, data.today)
end

function P.Hero(card, hero, ctx, slot)
	if not slot.change then
		slot.change = S.Stat(slot, true)
		slot.change.label:Hide() -- the shell draws the card's label
		slot.change:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
		slot.change:SetSize(240, 56)
		slot.parts = {}
		for i = 1, 3 do
			slot.parts[i] = S.Stat(slot)
			slot.parts[i]:SetSize(150, 40)
		end
		slot.parts[3]:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -14)
		slot.parts[2]:SetPoint("TOPRIGHT", slot.parts[3], "TOPLEFT", -20, 0)
		slot.parts[1]:SetPoint("TOPRIGHT", slot.parts[2], "TOPLEFT", -20, 0)
	end
	slot.change:Set(nil, S.Signed(hero.change), hero.caption)
	slot.parts[1]:Set(L["Spent"], S.Coins(hero.spent))
	slot.parts[2]:Set(L["Received"], S.Coins(hero.received))
	slot.parts[3]:Set(L["Not from logged trades"], S.Signed(hero.other), L["loot, quests, mail"])
end

----------------------------------------------------------------------------------------------------
-- Tools: period chips (sub bar), Reset ledger (footer)
----------------------------------------------------------------------------------------------------

function P.Tools(slot)
	slot.chips = {}
	local right
	for i = #P.PERIODS, 1, -1 do
		local p = P.PERIODS[i]
		local chip = Style.Chip(slot, p.label)
		chip.key = p.key
		chip:SetScript("OnClick", function()
			P.SetPeriod(p.key)
		end)
		if right then
			chip:SetPoint("RIGHT", right, "LEFT", -8, 0)
		else
			chip:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		end
		right = chip
		slot.chips[p.key] = chip
	end
end

function P.UpdateTools(slot)
	local period = P.Period()
	for key, chip in pairs(slot.chips) do
		chip:SetOn(key == period)
	end
end

-- Reset: the first click arms it ("Click again" for 3 s), a second one within that time resets. After a
-- reset the page shows Since reset (as the Records window did). Returns "armed" or "reset".
P.armedAt = nil

function P.ClickReset(now)
	now = now or time()
	if P.armedAt and now - P.armedAt <= P.ARM_SECONDS then
		P.armedAt = nil
		ns.Ledger.Reset()
		P.SetPeriod("reset")
		return "reset"
	end
	P.armedAt = now
	local armed = now
	if C_Timer and C_Timer.NewTimer then
		C_Timer.NewTimer(P.ARM_SECONDS, function()
			if P.armedAt == armed then
				P.armedAt = nil
				M.Refresh()
			end
		end)
	end
	M.Refresh()
	return "armed"
end

function P.Armed(now)
	return P.armedAt ~= nil and (now or time()) - P.armedAt <= P.ARM_SECONDS
end

function P.FooterTools(slot)
	slot.reset = Style.LineButton(slot, L["Reset ledger"], nil, 22)
	slot.reset:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	slot.reset:SetScript("OnClick", function()
		P.ClickReset()
	end)
	slot.reset:HookScript("OnEnter", function(self)
		P.UpdateFooterTools(slot) -- keeps the armed red over the hover colours
		Style.ShowTip(self, L["Reset ledger"],
			L["Starts \"since reset\" now. Nothing is deleted: Today and the days stay. Asks for a second click."])
	end)
	slot.reset:HookScript("OnLeave", function(self)
		P.UpdateFooterTools(slot)
		Style.HideTip(self)
	end)
end

function P.UpdateFooterTools(slot)
	local armed = P.Armed()
	slot.reset:SetLabel(armed and L["Click again"] or L["Reset ledger"])
	-- armed: the committing action in view, in red
	if armed then
		slot.reset.label:SetTextColor(C.danger[1], C.danger[2], C.danger[3], 1)
		slot.reset.border:SetColor(C.danger)
	else
		slot.reset:SetOn(false) -- the line button's own colours (hover lights it)
	end
end

-- The rail's shared scale is set on the context before the rows draw.
local function Model(ctx)
	local model = P.Model(ctx)
	if P.Period() == "days" then
		local values = {}
		for i, r in ipairs(model.rows) do
			values[i] = r.change
		end
		ctx.railMax = Style.SharedScale(values)
	end
	return model
end

-- /craftwise ledger [login | today | all]: opens this page on that period (reset stays slash-only).
local SLASH_VIEWS = { login = "login", session = "login", today = "today", day = "today", all = "reset", since = "reset" }
function P.OpenFromSlash(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	if arg == "reset" or not ns.OpenMainWindow then
		return false
	end
	if arg ~= "" then
		local view = SLASH_VIEWS[arg]
		if not view then
			return false
		end
		ns.db.settings.ledgerPerDay = false
		ns.db.settings.ledgerView = view
	end
	return ns.OpenMainWindow("ledger")
end
ns.OpenLedgerPage = P.OpenFromSlash

M.RegisterPage({
	key = "ledger", section = "sell", label = L["Ledger"], order = 3, events = { "LEDGER_CHANGED" },
	columns = P.Columns, Model = Model, InitRow = P.InitRow, Hero = P.Hero,
	Tools = P.Tools, UpdateTools = P.UpdateTools, FooterTools = P.FooterTools, UpdateFooterTools = P.UpdateFooterTools,
	P = P,
})
