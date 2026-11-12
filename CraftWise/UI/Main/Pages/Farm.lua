-- Gather › Farm (#156; spec #150 "Gather: Farm", board "Gather › Farm"). Replaces the History panel of the
-- old farm window. Hero: the open session (orange dog-ear and label while it runs: timer, gold per hour,
-- coin, items at AH, vendor only, Open tracker); without one "No session running" with Start. List: the
-- open session on top, then the finished sessions newest first (Started, Zone, Time, gold per hour as a
-- rail from 0 on one shared scale, Total, Per hour). A row opens in place: top items, zones with time, the
-- split, the loot lines kept and Loot log, which shows the log in the same place, newest first. The open
-- session's row lists every looted item with ×: that removes it from the session (Farm.RemoveItem), the
-- tracker's loot list's former home.
-- Data: Farm.lua and UI/FarmHistory.lua (FH.ListRows, FH.SessionRow, FH.Detail, FH.SessionDetail) and the
-- tracker's model (FF.Model); this file only draws. P.Layout measures and draws an opened row with the same
-- code, so its height and its drawing never disagree. The farm tracker's Log, "+ N more" and History links
-- (FF.OpenLog, FF.OpenList, FF.OpenHistory) open this page.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C
local Farm, FH, FF = ns.Farm, ns.FarmHistory, ns.FarmFrame

local P = {}
ns.GatherFarm = P

P.KEY = "farm"
P.LOG_STEP = 50 -- loot log lines shown at first, and per "Show more"
P.LINE = 17 -- a line in an opened row's columns
P.LOG_LINE = 18
P.ITEM_LINE = 20
P.COLUMN_GAP = 18
P.NARROW = 500 -- an opened row narrower than this (docked, #161) stacks its columns

-- This session: rows whose loot log is shown in place, and how many of its lines.
local state = { log = {}, shown = {} }
P.state = state

local function Paint(text, color)
	return Style.Hex(color) .. text .. "|r"
end

----------------------------------------------------------------------------------------------------
-- Model
----------------------------------------------------------------------------------------------------

-- The hero card: { label, labelColor, name, nameFont, sub, flap, state, split }.
function P.HeroModel(s, now)
	if not s then
		return { full = true, label = L["Farm tracker"], name = L["No session running"], state = "none", middle = 48,
			sub = Farm.AutoStart() and L["Press Start, or just loot: \"Start on first loot\" is on."] or L["Press Start, then loot."] }
	end
	local m = FF.Model(s, now)
	local word = m.state == "running" and L["Running now"] or m.word:gsub("^%l", string.upper)
	return { full = true, label = word .. " · " .. m.timer, labelColor = m.state == "running" and "live" or "text2",
		flap = m.state == "running" and "live" or "ruleStrong", name = FF.Coins(m.hero), nameFont = "FigureL",
		sub = m.caption, state = m.state, split = m.split, middle = 3 * 16 + 8 + 26 + 4 }
end

function P.Model()
	local now = Farm.Now()
	local s = Farm.Current()
	local rows = {}
	local cur = FH.SessionRow(s, now)
	if cur then
		rows[1] = cur
	end
	local history = Farm.History()
	for _, r in ipairs(FH.ListRows(history)) do
		rows[#rows + 1] = r
	end
	local values = {}
	for i, r in ipairs(rows) do
		values[i] = r.gph
	end
	local max = Style.SharedScale(values)
	for _, r in ipairs(rows) do
		r.railMax = max
	end
	return {
		rows = rows,
		hero = P.HeroModel(s, now),
		listTitle = L["Finished sessions"],
		listNote = cur and L["the open session on top, then newest first · bar: gold per hour"] or L["newest first · bar: gold per hour"],
		empty = L["No finished session yet. End one in the farm tracker and it shows here."],
		footer = L["Each session keeps the values it had when it ended; the open one is valued now."],
		footerRight = (L["%d of %d kept"]):format(#history, Farm.HISTORY_MAX),
	}
end

-- The open session stays on top whatever the sort.
function P.SortRows(rows, key, desc)
	table.sort(rows, function(a, b)
		if a.current ~= b.current then
			return a.current and true or false
		end
		local va, vb = a[key], b[key]
		if va == vb then
			return (a.start or 0) > (b.start or 0)
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		end
		if type(va) == "string" then
			va, vb = va:lower(), vb:lower()
		end
		if desc then
			return va > vb
		end
		return va < vb
	end)
end

----------------------------------------------------------------------------------------------------
-- Columns (board: Started 110, Zone 170, Time 70, Gold per hour rail, Total 90, Per hour 96)
----------------------------------------------------------------------------------------------------

local function ZoneText(r)
	local text = r.zone or ""
	if (r.zonesMore or 0) > 0 then
		text = text .. Paint((" +%d"):format(r.zonesMore), "text3")
	end
	if r.fishing then
		text = text .. Paint(" · " .. L["fishing"], "text3")
	end
	return text
end

local function StateColor(r)
	if r.current then
		return r.state == "running" and "live" or "text2"
	end
end

P.COLUMNS = {
	{ key = "start", label = L["Started"], width = 110, sort = true, text = function(r) return r.started end,
		color = function(r) return StateColor(r) or "text" end },
	{ key = "zone", label = L["Zone"], width = 170, sort = true, text = ZoneText, color = function() return "text2" end },
	{ key = "seconds", label = L["Time"], width = 70, align = "RIGHT", sort = true, font = "Figure",
		text = function(r) return r.time end, color = function(r) return StateColor(r) or "text2" end },
	{ key = "rail", label = L["Gold per hour"], rail = function(r) return { value = r.gph, max = r.railMax } end },
	{ key = "total", label = L["Total"], width = 90, align = "RIGHT", sort = true, font = "Figure",
		text = function(r) return FF.Coins(r.total) end },
	{ key = "gph", label = L["Per hour"], width = 96, align = "RIGHT", sort = true, font = "FigureBold",
		text = function(r) return FF.Coins(r.gph) end,
		tip = function(r)
			if not r.gph then
				return { L["No per-hour figure"], L["A session needs at least a minute for one."] }
			end
		end },
}

----------------------------------------------------------------------------------------------------
-- Hero: Coin, Items at AH, Vendor only, and Open tracker (or Start)
----------------------------------------------------------------------------------------------------

local HERO_COLUMN, HERO_BUTTONS = 120, 150

local function BuildHero(area)
	local h = {}
	area.cw = h
	h.cols = {}
	for i, label in ipairs({ L["Coin"], L["Items at AH"], L["Vendor only"] }) do
		local col = {}
		col.label = Style.Text(area, "Label", "text3")
		col.label:SetText(label)
		col.figure = Style.Text(area, "FigureBold", "text")
		local x = -(HERO_BUTTONS + P.COLUMN_GAP + (3 - i) * (HERO_COLUMN + P.COLUMN_GAP))
		col.label:SetPoint("TOPLEFT", area, "TOPRIGHT", x - HERO_COLUMN, -8)
		col.figure:SetPoint("TOPLEFT", col.label, "BOTTOMLEFT", 0, -3)
		h.cols[i] = col
	end
	h.open = Style.LineButton(area, L["Open tracker"], nil, 26)
	h.open:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -2)
	h.open:SetScript("OnClick", function()
		if FF and FF.Show then
			FF.Show()
		end
	end)
	h.start = Style.PrimaryButton(area, L["Start"], nil, 28)
	h.start:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -2)
	h.start:SetScript("OnClick", function()
		Farm.Start()
	end)
	h.note = Style.Text(area, "Label", "text3")
	h.note:SetPoint("TOPRIGHT", h.open, "BOTTOMRIGHT", 0, -6)
	h.note:SetJustifyH("RIGHT")
	return h
end

-- slot: the page's own frame over the card inside its padding (hero.full; the shell draws label, name, sub).
function P.Hero(_, hero, _, slot)
	local area = slot
	local h = area.cw or BuildHero(area)
	local none = hero.state == "none"
	for i, key in ipairs({ "coin", "ah", "vendor" }) do
		local col = h.cols[i]
		col.label:SetShown(not none)
		col.figure:SetShown(not none)
		if not none then
			col.figure:SetText(FF.Coins(hero.split[key]))
			local c = Style.Color(key == "ah" and (hero.split.stale or 0) > 0 and "danger" or "text3")
			col.label:SetTextColor(c[1], c[2], c[3], 1)
		end
	end
	h.open:SetShown(not none)
	h.start:SetShown(none)
	h.note:ClearAllPoints()
	h.note:SetPoint("TOPRIGHT", none and h.start or h.open, "BOTTOMRIGHT", 0, -6)
	h.note:SetText(none and L["or open the tracker: key binding, minimap right-click"] or L["Pause · End in the tracker"])
end

-- Docked (#161): the hero stacked (Coin, Items at AH, Vendor only one line each, then Open tracker; or
-- Start), and a row as the start and zone over the gold per hour rail, per hour right with time and
-- total under it.
function P.DockedHero(_, hero, _, slot)
	local none = hero.state == "none"
	if not slot.open then
		slot.open = Style.LineButton(slot, L["Open tracker"], nil, 26)
		slot.open:SetScript("OnClick", function()
			if FF and FF.Show then
				FF.Show()
			end
		end)
		slot.start = Style.PrimaryButton(slot, L["Start"], nil, 28)
		slot.start:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
		slot.start:SetScript("OnClick", function()
			Farm.Start()
		end)
		slot.note = Style.Text(slot, "Label", "text3")
		slot.note:SetJustifyH("LEFT")
	end
	local lines = {}
	if not none then
		for i, key in ipairs({ "coin", "ah", "vendor" }) do
			lines[i] = { label = ({ L["Coin"], L["Items at AH"], L["Vendor only"] })[i], value = FF.Coins(hero.split[key]),
				labelColor = key == "ah" and (hero.split.stale or 0) > 0 and "danger" or "text3" }
		end
	end
	local h = M.Docked.StatLines(slot, lines, 0)
	slot.open:ClearAllPoints()
	slot.open:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -(h + 8))
	slot.open:SetShown(not none)
	slot.start:SetShown(none)
	slot.note:ClearAllPoints()
	slot.note:SetPoint("LEFT", none and slot.start or slot.open, "RIGHT", 10, 0)
	slot.note:SetText(none and L["or open the tracker: key binding, minimap right-click"] or L["Pause · End in the tracker"])
end

function P.DockedRow(r)
	local c = P.COLUMNS
	return {
		name = Paint(r.started or "", StateColor(r) or "text") .. Paint(" · ", "text3") .. Paint(ZoneText(r), "text2"),
		rail = { value = r.gph, max = r.railMax },
		result = c[6].text(r), sub = (r.time or "") .. "  " .. (c[5].text(r) or ""), tip = c[6].tip(r),
	}
end

-- While a session runs the hero's timer and gold per hour follow the clock (the list follows FARM_CHANGED).
function P.Tick()
	local f = M.Frame and M.Frame()
	if not (f and f:IsShown() and M.shown.page == P.KEY and M.shown.state == "list") then
		return
	end
	local s = Farm.Current()
	if not (s and Farm.Running(s)) then
		return
	end
	local hero = P.HeroModel(s, Farm.Now())
	f.hero.label:SetText(hero.label)
	f.hero.name:SetText(hero.name)
	f.hero.sub:SetText(hero.sub)
end

----------------------------------------------------------------------------------------------------
-- Opened row: measured and drawn by one function
----------------------------------------------------------------------------------------------------

local function Detail(row)
	if row.cwDetail == nil then
		if row.current then
			local s = Farm.Current()
			row.cwDetail = s and FH.SessionDetail(s, Farm.Now()) or false
		else
			local h = Farm.History()[row.index]
			row.cwDetail = h and FH.Detail(h) or false
		end
	end
	return row.cwDetail or nil
end
P.Detail = Detail

local function ItemLabel(itemID, name, n)
	local text = Paint(name or FF.ItemName({ itemID = itemID }), itemID and FF.ItemColor(itemID) or "text")
	if n then
		text = text .. " " .. Paint("×" .. n, "text3")
	end
	return text
end

-- Draws a column: label then lines; returns its height. lines = { { text, item = itemID, tip, lines } }.
local function Column(pool, content, x, y, width, label, lines)
	local draw = pool ~= nil
	if draw then
		local fs = pool:Text("Label", "text3", label)
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
	end
	local h = 14
	for _, line in ipairs(lines) do
		if draw then
			local fs = pool:Text(line.font or "Small", line.color or "text", line.text)
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y + h))
			fs:SetWidth(width)
			if line.item or line.tip then
				local hit = pool:Hit({ itemID = line.item, tip = line.tip })
				hit:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y + h))
				hit:SetSize(width, P.LINE)
			end
		end
		h = h + P.LINE
	end
	return h
end

local function SplitLines(d)
	local sp = d.split
	local lines = {
		{ text = L["coin"] .. " " .. FF.Coins(sp.coin), font = "Figure" },
		{ text = "AH " .. FF.Coins(sp.ah) .. Paint(" · ", "text3") .. L["vendor"] .. " " .. FF.Coins(sp.vendor), font = "Figure",
			tip = { L["Split"], L["Items valued at their AH price, and at their vendor price."],
				L["Everything sold to a vendor"] .. ": " .. FF.PlainCoins(sp.vendorOnly) .. ((sp.vendorUnknown or 0) > 0 and " +?" or "") } },
	}
	if (sp.stale or 0) > 0 then
		lines[#lines + 1] = { text = Paint(L["AH part over a day old"] .. " ", "danger") .. FF.Coins(sp.stale), font = "Figure" }
	end
	if (sp.unknown or 0) > 0 then
		lines[#lines + 1] = { text = Paint((L["%d unpriced"]):format(sp.unknown), "text3") }
	end
	local f = d.fish
	if f then
		lines[#lines + 1] = { text = (L["fishing %d catches · %s per catch"]):format(f.catches, FF.Coins(f.perCatch)),
			tip = { L["Fishing"], (L["%s per hour"]):format(FF.PlainCoins(f.gph)),
				(L["%d containers opened"]):format(f.opened or 0) } }
	end
	return lines
end

local function ZoneLines(d)
	local lines = {}
	for _, z in ipairs(d.zones) do
		lines[#lines + 1] = { text = z.zone .. " " .. Paint(z.time, "text2"),
			tip = { z.zone, (L["%s per hour"]):format(FF.PlainCoins(z.gph)) } }
	end
	if (d.zonesMore or 0) > 0 then
		lines[#lines + 1] = { text = Paint(("+%d %s"):format(d.zonesMore, L["more zones"]), "text3") }
	end
	if #lines == 0 then
		lines[1] = { text = Paint("—", "text3") }
	end
	return lines
end

local function TopLines(d)
	local lines = {}
	for _, t in ipairs(d.top or {}) do
		lines[#lines + 1] = { text = ItemLabel(t.itemID, t.name, t.n), item = t.itemID }
	end
	if #lines == 0 then
		lines[1] = { text = Paint("—", "text3") }
	end
	return lines
end

-- Summary of an opened row: Top items (finished) | Zones | Split | the log lines and Loot log.
local function Summary(pool, content, row, d, width)
	local cols = row.current and { { L["Zones"], ZoneLines(d) }, { L["Split"], SplitLines(d) } }
		or { { L["Top items"], TopLines(d) }, { L["Zones"], ZoneLines(d) }, { L["Split"], SplitLines(d) } }
	local n = #cols + 1
	local colWidth = math.floor((width - P.COLUMN_GAP * (n - 1)) / n)
	local h = 0
	if width < P.NARROW then
		-- Docked (#161): the columns one under the other, Loot log top right.
		colWidth = width - 100
		for _, col in ipairs(cols) do
			h = h + Column(pool, content, 0, h, colWidth, col[1], col[2]) + 8
		end
		h = h - 8
	else
		for i, col in ipairs(cols) do
			h = math.max(h, Column(pool, content, (i - 1) * (colWidth + P.COLUMN_GAP), 0, colWidth, col[1], col[2]))
		end
	end
	-- Right: how many loot lines were kept, and Loot log.
	if pool then
		local note = pool:Text("Label", "text3", d.log and d.logNote or (d.logLines and L["loot log not kept"] or d.logNote))
		note:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
		note:SetJustifyH("RIGHT")
		if not d.log and d.logNote then
			local hit = pool:Hit({ tip = { L["Loot log"], d.logNote } })
			hit:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
			hit:SetSize(colWidth, 14)
		end
		if d.log and #d.log > 0 then
			local b = pool:Button(L["Loot log"], function()
				state.log[row.key] = true
				M.Refresh()
			end, { L["Loot log"], L["One line per drop, newest first: time, item, value, zone; fishing catches marked."] })
			b:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -20)
		end
	end
	return math.max(h, 44)
end

-- The open session's items, each with × to remove it from the session.
local function Items(pool, content, d, y, width)
	local items = d.items or {}
	if pool then
		local head = pool:Text("Label", "text3", ("%s · %d"):format(L["Items"], #items))
		head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	end
	local h = 16
	if #items == 0 and pool then
		local fs = pool:Text("Small", "text3", L["Nothing looted yet."])
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + h))
	end
	for _, r in ipairs(items) do
		if pool then
			local top = y + h
			local icon = pool:Icon(16, C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID))
			icon:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(top + 2))
			local name = pool:Text("Small", FF.ItemColor(r.itemID), FF.ItemName(r) .. " " .. Paint("×" .. r.n, "text3"))
			name:SetPoint("TOPLEFT", content, "TOPLEFT", 22, -(top + 4))
			name:SetWidth(width - 22 - (width < P.NARROW and 120 or 200))
			local remove = pool:Button("×", function()
				Farm.RemoveItem(r.itemID)
			end, { L["Remove from this session"], L["The item leaves the session and is ignored until the session ends."] }, 18)
			remove:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(top + 1))
			local value = pool:Text("Figure", "text", FF.ValueText(r))
			value:SetPoint("TOPRIGHT", content, "TOPRIGHT", -30, -(top + 4))
			value:SetJustifyH("RIGHT")
			local hit = pool:Hit({ itemID = r.itemID })
			hit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
			hit:SetSize(width - (width < P.NARROW and 120 or 200), P.ITEM_LINE)
		end
		h = h + P.ITEM_LINE
	end
	if #items == 0 then
		h = h + P.ITEM_LINE
	end
	return h
end

-- The loot log in place: newest first, P.LOG_STEP lines at a time.
local function Log(pool, content, row, d, width)
	local log = d.log or {}
	local shown = math.min(#log, state.shown[row.key] or P.LOG_STEP)
	if pool then
		local head = ("%s · %d"):format(L["Loot log"], #log)
		if (d.logDropped or 0) > 0 then
			head = head .. " " .. Paint(("(%d %s)"):format(d.logDropped, L["older dropped"]), "text3")
		end
		pool:Text("BodyBold", "text", head):SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		local back = pool:Button(row.current and L["Items"] or L["Summary"], function()
			state.log[row.key] = nil
			M.Refresh()
		end)
		back:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 2)
	end
	local h = 26
	for i = 1, shown do
		local e = log[i]
		if pool then
			local top = h
			pool:Text("Figure", "text3", date("%H:%M:%S", e.t)):SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
			local icon = pool:Icon(14, e.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.itemID) or FF.COIN_ICON)
			icon:SetPoint("TOPLEFT", content, "TOPLEFT", 66, -top)
			local mark = e.fish and (FF.FISH_MARK .. " ") or ""
			local name = e.itemID and ItemLabel(e.itemID, FF.ItemName(e), e.n > 1 and e.n or nil) or L["Coin"]
			local fs = pool:Text("Small", "text", mark .. name)
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", 86, -(top + 1))
			local narrow = width < P.NARROW -- docked: no zone column (it is in the line's tooltip)
			fs:SetWidth(width - 86 - (narrow and 90 or 260))
			local value = pool:Text("Figure", "text", FF.LogValueText(e))
			value:SetPoint("TOPRIGHT", content, "TOPRIGHT", narrow and 0 or -130, -top)
			value:SetJustifyH("RIGHT")
			if not narrow then
				local zone = pool:Text("Caption", "text3", e.zone)
				zone:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(top + 1))
				zone:SetWidth(120)
				zone:SetJustifyH("RIGHT")
			end
			if e.itemID then
				local hit = pool:Hit({ itemID = e.itemID, lines = { { L["Looted at"], date("%H:%M:%S", e.t) }, { L["Zone"], e.zone } } })
				hit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
				hit:SetSize(width - 140, P.LOG_LINE)
			end
		end
		h = h + P.LOG_LINE
	end
	if shown < #log then
		if pool then
			local more = pool:Button((L["Show %d more"]):format(math.min(P.LOG_STEP, #log - shown)), function()
				state.shown[row.key] = shown + P.LOG_STEP
				M.Refresh()
			end)
			more:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(h + 4))
			local rest = pool:Text("Caption", "text3", (L["%d older lines"]):format(#log - shown))
			rest:SetPoint("LEFT", more, "RIGHT", 10, 0)
		end
		h = h + 30
	end
	if #log == 0 then
		if pool then
			pool:Text("Small", "text3", L["Nothing looted yet."]):SetPoint("TOPLEFT", content, "TOPLEFT", 0, -h)
		end
		h = h + P.LOG_LINE
	end
	return h
end

-- Measures (pool nil) or draws an opened row; returns its height.
function P.Layout(pool, content, row, width)
	local d = Detail(row)
	if not d then
		if pool then
			pool:Text("Small", "text3", L["This session is no longer kept."]):SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		end
		return P.LINE
	end
	if state.log[row.key] and d.log then
		return Log(pool, content, row, d, width)
	end
	local h = Summary(pool, content, row, d, width)
	if row.current then
		h = h + 12 + Items(pool, content, d, h + 12, width)
	end
	return h
end

-- Inner width of the opened card (list width less its margins and padding, List.lua).
local function InnerWidth(ctx)
	return M.OpenInnerWidth(ctx)
end

function P.Open(content, row, ctx)
	local pool = M.Pool(content)
	pool:Reset()
	P.Layout(pool, content, row, InnerWidth(ctx))
end

function P.OpenHeight(row, ctx)
	return P.Layout(nil, nil, row, InnerWidth(ctx))
end

----------------------------------------------------------------------------------------------------
-- Page tools (sub bar): where the tracker's key binding is
----------------------------------------------------------------------------------------------------

function P.Tools(slot)
	local t = Style.Text(slot, "Caption", "text3")
	t:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	t:SetJustifyH("RIGHT")
	t:SetText(L["Key binding: Toggle CraftWise farm tracker"])
	local ticker = CreateFrame("Frame", nil, slot)
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed >= 1 then
			elapsed = 0
			P.Tick()
		end
	end)
	slot.ticker = ticker
end

----------------------------------------------------------------------------------------------------
-- Opening from the farm tracker and elsewhere
----------------------------------------------------------------------------------------------------

-- Opens Gather › Farm; rowKey opens that row (FH.CURRENT = the open session), log = with its loot log.
function P.Show(rowKey, log)
	if not (M.Open and M.Open(P.KEY)) then
		return false
	end
	if rowKey then
		state.log[rowKey] = log and true or nil
		M.OpenRow(P.KEY, rowKey)
	end
	return true
end

ns.OpenFarmPage = P.Show

P.page = M.RegisterPage({
	key = P.KEY, section = "gather", label = L["Farm"], order = 1,
	events = { "FARM_CHANGED", "PRICES_CHANGED" },
	columns = P.COLUMNS,
	sort = { key = "start", desc = true },
	SortRows = P.SortRows,
	Model = function(ctx) return P.Model(ctx) end,
	Hero = function(card, hero, ctx, slot) return P.Hero(card, hero, ctx, slot) end,
	DockedHero = function(card, hero, ctx, slot) return P.DockedHero(card, hero, ctx, slot) end,
	DockedRow = function(r) return P.DockedRow(r) end,
	Open = P.Open,
	OpenHeight = P.OpenHeight,
	Tools = P.Tools,
})
