-- Gather › Fishing (#156; spec #150 "Gather: Fishing", board "Gather › Fishing"). Replaces the profit
-- window's Fishing view and Records › Fishing log. Chips in the sub bar: Spots / Log, and All water /
-- Pools / Open water (kept in db.settings.ui.gather).
--   Spots: zones by gold per hour = value per catch (FishingZones: own catches from the own-catch minimum
--     on, else the reference) × your catch rate (Fishing.CatchRate, all water or the chosen water). The line
--     over the list names the rate and where it comes from; a rate from fewer timed catches than the minimum
--     carries "~". Columns: Zone, Your data (own catches; grey under the minimum), Gold per hour as a point
--     with its likely range (the stack range of the reference, low .. high), Per catch, Per hour. A zone
--     opens into its fish: share of catches (grey bar), share of money (gold bar), value each; junk lumped
--     as one line; Show reference / Show own catches switches the side (the old view's source switch).
--   Log: the fishing log (FishingTables) per zone, subzone and water, with value per catch and per hour; a
--     row opens into what was caught there and, for a pool, its visits. Pools only seen are listed too.
--     Find Fish's state is in the footer.
-- Data: FishingZones.lua (Z.Rank, Z.OwnMin), FishingTables.lua (F.Tables, F.CatchRate, F.RowLabel),
-- Fishing.lua; this file only draws.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C
local FF = ns.FarmFrame

local P = {}
ns.GatherFishing = P

P.KEY = "fishing"
P.FISHING_LINE = 356 -- the Fishing skill line (Recipes.lua, ns.GATHERING)
P.FISH_LINE = 24 -- a fish in an opened zone
P.LINE = 18

local QUALITY_POOR = 0
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local POOL_ICON = "Interface\\Icons\\INV_Misc_Fish_02"

local state = { prefer = {} } -- this session: the side an opened zone shows ("own" | "ref")
P.state = state

local function Paint(text, color)
	return Style.Hex(color) .. text .. "|r"
end

local function Coins(copper)
	return FF.Coins(copper)
end

----------------------------------------------------------------------------------------------------
-- Chips: Spots / Log and the water (db.settings.ui.gather)
----------------------------------------------------------------------------------------------------

local function Saved()
	local ui = M.UI()
	ui.gather = type(ui.gather) == "table" and ui.gather or {}
	return ui.gather
end

function P.Mode()
	return Saved().fishMode == "log" and "log" or "spots"
end

function P.Water()
	local w = Saved().fishWater
	return (w == "pool" or w == "open") and w or "all"
end

P.DEFAULT_SORT = { spots = { key = "gph", desc = true }, log = { key = "catches", desc = true } }

function P.SetMode(mode)
	Saved().fishMode = mode == "log" and "log" or "spots"
	M.state.sort[P.KEY] = nil
	if P.page then
		P.page.sort = P.DEFAULT_SORT[P.Mode()]
	end
	M.Refresh()
end

function P.SetWater(water)
	Saved().fishWater = (water == "pool" or water == "open") and water or nil
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Item names the client hasn't loaded yet: asked once per item, the page refreshes when they arrive (as
-- the old Fishing view did, #83: their sell prices are kept too).
----------------------------------------------------------------------------------------------------

local requested = {}
local function LoadItems(lines)
	local missing, sell = {}, {}
	for _, line in ipairs(lines) do
		local id = line.itemID
		if id and not requested[id] then
			requested[id] = true
			sell[id] = true
			if not (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) then
				missing[#missing + 1] = id
			end
		end
	end
	if ns.PersistSellPrices and next(sell) then
		ns.PersistSellPrices(sell)
	end
	if #missing > 0 and ns.WithItemNames then
		ns.WithItemNames(missing, function()
			if M.shown.page == P.KEY then
				M.Refresh()
			end
		end)
	end
end

local function ItemName(line)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(line.itemID)
	return name or line.name or ("item " .. tostring(line.itemID))
end

local function Quality(itemID)
	return C_Item and C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(itemID))
end

----------------------------------------------------------------------------------------------------
-- Spots model
----------------------------------------------------------------------------------------------------

-- The catch rate the page uses: { perHour, enough, timed, min, water } or nil without any timed catch.
function P.Rate(water)
	local F = ns.Fishing
	local r = F and F.CatchRate and F.CatchRate()
	if not r then
		return nil
	end
	local w = water == "all" and r or r.waters[water]
	if not (w and w.perHour) then
		return nil
	end
	return { perHour = w.perHour, enough = w.enough, timed = w.timed, min = r.min, water = water }
end

-- "Fishing 225" from the cached professions, or nil.
function P.SkillText()
	for id, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if ns.SkillLineOf and ns.SkillLineOf(id, prof.name) == P.FISHING_LINE then
			local skill = ns.ProfessionSkill and ns.ProfessionSkill(id) or prof.skill
			return skill and ("%s %d"):format(prof.name or L["Fishing"], skill) or nil
		end
	end
end

local WATER_WORDS = { all = "", pool = " " .. "in pools", open = " " .. "in open water" }

-- The line over the list: what gold per hour is, the rate and its source.
function P.RateNote(rate, water, days)
	local text = L["gold per hour = value per catch × your catch rate"]
	if rate then
		local n = math.floor(rate.perHour + 0.5)
		if rate.enough then
			text = text .. " (" .. (L["%d catches/h%s, your last %d days"]):format(n, L[WATER_WORDS[water]], days) .. ")"
		else
			text = text .. " (" .. (L["~%d catches/h%s from %d of %d timed catches"]):format(n, L[WATER_WORDS[water]], rate.timed,
				rate.min) .. ")"
		end
	else
		text = text .. " · " .. L["no catch rate yet: casts in a row give one"]
	end
	local skill = P.SkillText()
	return skill and (text .. " · " .. skill) or text
end

function P.SpotsModel()
	local Z = ns.FishingZones
	local water = P.Water()
	local rank = Z.Rank({ water = water ~= "all" and water or nil })
	local rate = P.Rate(water)
	local perHour = rate and rate.perHour
	local rows, highs, lines = {}, {}, {}
	for _, z in ipairs(rank.zones) do
		local own = z.own and z.own.n or 0
		local priced = not (z.perCatch == 0 and z.unpriced > 0)
		local row = { key = z.key, name = z.name, own = own, ownLow = own < rank.ownMin, source = z.source, n = z.n,
			unpriced = z.unpriced, perCatch = priced and z.perCatch or nil, perCatchHigh = priced and z.perCatchHigh or nil,
			estimate = rate and not rate.enough or nil, zone = z, ownMin = rank.ownMin, hasRef = z.ref ~= nil }
		if priced and perHour then
			row.gph = math.floor(z.perCatch * perHour + 0.5)
			row.gphHigh = math.floor((z.perCatchHigh or z.perCatch) * perHour + 0.5)
			highs[#highs + 1] = row.gphHigh
		end
		rows[#rows + 1] = row
		for _, line in ipairs(z.items or {}) do
			lines[#lines + 1] = line
		end
	end
	LoadItems(lines)
	local max = Style.SharedScale(highs)
	for _, r in ipairs(rows) do
		r.railMax = max
	end
	local days = rank.days or (ns.Fishing and ns.Fishing.KEEP_DAYS) or 90
	local ref = rank.ref and (L["reference: loaded"] .. (rank.refGenerated and (" (" .. rank.refGenerated .. ")") or ""))
		or L["reference: not loaded"]
	return {
		rows = rows,
		listTitle = L["Where to fish"],
		listNote = P.RateNote(rate, water, days),
		empty = rank.ref and L["No zone to rank yet."] or L["No catches yet and no reference loaded. Fish a while and your spots show here."],
		footer = (L["Thin bar = likely range. Grey count: fewer than %d of your own catches; the zone shows the reference."]):format(rank.ownMin),
		footerRight = ref,
	}
end

----------------------------------------------------------------------------------------------------
-- Log model
----------------------------------------------------------------------------------------------------

local function FindFishText(ff)
	if not ff or ff.known == nil then
		return L["Find Fish: not read yet"]
	end
	if not ff.known then
		return L["Find Fish: not known by this character"]
	end
	if ff.tracking == nil then
		return L["Find Fish: known, tracking state not read"]
	end
	return ff.tracking and L["Find Fish: known, tracking on"] or L["Find Fish: known, tracking off"]
end
P.FindFishText = FindFishText

function P.LogModel()
	local F = ns.Fishing
	local water = P.Water()
	local t = F and F.Tables and F.Tables({ water = water ~= "all" and water or nil })
	if not t then
		return { rows = {}, listTitle = L["Fishing log"], empty = L["Fishing log not loaded yet."] }
	end
	local pools, lines = {}, {}
	for _, p in ipairs(t.pools or {}) do
		pools[p.obj] = p
	end
	local rows, listed = {}, {}
	for _, r in ipairs(t.rows) do
		local priced = not (r.value == 0 and r.unpriced > 0)
		local row = { key = table.concat({ r.zone, r.sub, r.water, tostring(r.obj) }, "\1"), name = r.zone ..
			(r.sub ~= "" and (" · " .. r.sub) or ""), waterLabel = F.RowLabel(r), water = r.water, catches = r.catches,
			perCatch = priced and r.perCatch or nil, perHour = r.perHour, timed = r.timed, seconds = r.seconds,
			unpriced = r.unpriced, units = r.units, items = r.items, icon = r.water == "pool" and POOL_ICON or FISHING_ICON }
		if r.water == "pool" and r.obj then
			row.pool = pools[r.obj]
			listed[r.obj] = true
		end
		rows[#rows + 1] = row
		for _, item in ipairs(r.items) do
			lines[#lines + 1] = item
		end
	end
	-- Pools seen but never fished (or fished only elsewhere in this filter) keep a line.
	if water ~= "open" then
		for _, p in ipairs(t.pools or {}) do
			if not listed[p.obj] then
				rows[#rows + 1] = { key = "pool\1" .. tostring(p.obj), name = p.name or (L["pool object %d (name not seen)"]):format(p.obj),
					waterLabel = L["pool, no catch here"], water = "pool", catches = 0, pool = p, items = {}, icon = POOL_ICON }
			end
		end
	end
	LoadItems(lines)
	local what = water == "pool" and L["pool catches"] or water == "open" and L["open-water catches"] or L["catches"]
	return {
		rows = rows,
		listTitle = L["Fishing log"],
		listNote = (L["last %d days · %d %s · sessions: catches less than %d min apart"]):format(t.days, t.catches, what, t.gap),
		empty = (L["No %s in the last %d days."]):format(what, t.days),
		footer = FindFishText(t.findFish) .. " · " .. L["Value: best sell value (AH after the cut, else vendor)."],
		footerRight = (L["%d pools"]):format(#(t.pools or {})),
	}
end

function P.Model(ctx)
	if P.page then
		P.page.sort = P.DEFAULT_SORT[P.Mode()]
	end
	if P.Mode() == "log" then
		return P.LogModel(ctx)
	end
	return P.SpotsModel(ctx)
end

----------------------------------------------------------------------------------------------------
-- Columns (board: Zone 180, Your data 70, Gold per hour, Per catch 90, Per hour 100)
----------------------------------------------------------------------------------------------------

local function SourceText(row)
	if row.source == "own" then
		return (L["own catches, n = %d"]):format(row.n)
	end
	return (L["reference, n = %d"]):format(row.n)
end

P.SPOTS = {
	{ key = "name", label = L["Zone"], width = 180, sort = true },
	{ key = "own", label = L["Your data"], width = 70, align = "RIGHT", sort = true, font = "Figure",
		text = function(r) return tostring(r.own) end,
		color = function(r) return r.ownLow and "text3" or "text" end,
		tip = function(r)
			if r.ownLow then
				return { (L["%d of your own catches"]):format(r.own), r.hasRef
					and (L["Fewer than %d: the zone shows the reference."]):format(r.ownMin)
					or L["No reference for this zone: your own few catches show."] }
			end
			return { (L["%d of your own catches"]):format(r.own), L["The zone shows your own catches."] }
		end },
	{ key = "rail", label = L["Gold per hour"], rail = function(r)
		return { point = true, value = r.gph, low = r.gph, high = r.gphHigh, max = r.railMax }
	end },
	{ key = "perCatch", label = L["Per catch"], width = 90, align = "RIGHT", sort = true, font = "Figure",
		text = function(r) return r.perCatch and Coins(r.perCatch) or M.NoPriceText() end,
		tip = function(r)
			local lines = { SourceText(r) }
			if r.perCatchHigh and r.perCatch and r.perCatchHigh > r.perCatch then
				lines[#lines + 1] = (L["%s to %s with the stack range"]):format(FF.PlainCoins(r.perCatch), FF.PlainCoins(r.perCatchHigh))
			end
			if (r.unpriced or 0) > 0 then
				lines[#lines + 1] = (L["%d items without a price left out"]):format(r.unpriced)
			end
			return { L["Per catch"], unpack(lines) }
		end },
	{ key = "gph", label = L["Per hour"], width = 100, align = "RIGHT", sort = true, font = "FigureBold",
		text = function(r) return r.gph and ((r.estimate and "~" or "") .. Coins(r.gph)) or Paint(M.DASH, "text3") end,
		tip = function(r)
			if not r.gph then
				return { L["Per hour"], r.perCatch and L["No catch rate yet: casts in a row give one."] or L["No price for this zone's catches."] }
			end
		end },
}

P.LOG = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Where"], sort = true },
	{ key = "waterLabel", label = L["Water"], width = 170, sort = true, color = function() return "text2" end },
	{ key = "catches", label = L["Catches"], width = 70, align = "RIGHT", sort = true, font = "Figure" },
	{ key = "perCatch", label = L["Per catch"], width = 90, align = "RIGHT", sort = true, font = "Figure",
		text = function(r)
			if r.catches == 0 then
				return Paint(M.DASH, "text3")
			end
			return r.perCatch and Coins(r.perCatch) or M.NoPriceText()
		end },
	{ key = "perHour", label = L["Per hour"], width = 100, align = "RIGHT", sort = true, font = "FigureBold",
		text = function(r) return r.perHour and Coins(r.perHour) or Paint(r.catches > 0 and L["not timed"] or M.DASH, "text3") end,
		tip = function(r)
			if r.perHour then
				return { L["Per hour"], (L["n = %d timed, %d min"]):format(r.timed, math.floor(r.seconds / 60 + 0.5)) }
			elseif r.catches > 0 then
				return { L["Per hour"], L["No timed catches: a session's first catch has no time."] }
			end
		end },
}

function P.Columns()
	return P.Mode() == "log" and P.LOG or P.SPOTS
end

-- Sorting with nil last; ties by value per catch (so zones without a catch rate keep their ranking), then name.
function P.SortRows(rows, key, desc)
	table.sort(rows, function(a, b)
		local va, vb = a[key], b[key]
		if va == vb then
			if (a.perCatch or -1) ~= (b.perCatch or -1) then
				return (a.perCatch or -1) > (b.perCatch or -1)
			end
			return tostring(a.name or "") < tostring(b.name or "")
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		end
		if type(va) == "string" then
			va, vb = va:lower(), vb:lower()
		end
		if type(va) == "boolean" then
			va, vb = va and 1 or 0, vb and 1 or 0
		end
		if desc then
			return va > vb
		end
		return va < vb
	end)
end

----------------------------------------------------------------------------------------------------
-- Opened zone (Spots): per fish, share of catches and of money, value each; junk as one line
----------------------------------------------------------------------------------------------------

-- The fish of a side: { { itemID, name, catchShare, moneyShare, each, label, junk, priced } } in the side's
-- order (value per catch), junk lumped at the end.
function P.FishLines(side)
	local total = 0
	for _, line in ipairs(side.items or {}) do
		total = total + (line.low or 0)
	end
	local out, junk = {}, nil
	for _, line in ipairs(side.items or {}) do
		local share = total > 0 and (line.low or 0) / total or 0
		local money = side.perCatch and side.perCatch > 0 and line.perCatch and line.perCatch / side.perCatch or nil
		if Quality(line.itemID) == QUALITY_POOR then
			junk = junk or { junk = true, names = {}, catchShare = 0, moneyShare = 0 }
			junk.names[#junk.names + 1] = ItemName(line)
			junk.catchShare = junk.catchShare + share
			junk.moneyShare = junk.moneyShare + (money or 0)
		else
			out[#out + 1] = { itemID = line.itemID, name = ItemName(line), catchShare = share, moneyShare = money,
				each = line.unit and line.unit.copper or nil, label = line.unit and (line.unit.container and L["contents"] or line.unit.label) or nil }
		end
	end
	if junk then
		junk.name = L["Junk"] .. ": " .. table.concat(junk.names, ", ")
		out[#out + 1] = junk
	end
	return out
end

local function Pct(share)
	if not share then
		return M.DASH
	end
	return ("%d%%"):format(math.floor(share * 100 + 0.5))
end

local BAR_TRACK = { 0x3A / 255, 0x3C / 255, 0x41 / 255 } -- the board's bar track #3A3C41

-- A share bar and its percent; returns nothing. x, y: top left; width: bar + 34 for the percent.
local function ShareBar(pool, content, x, y, width, share, color)
	local track = pool:Bar(BAR_TRACK)
	track:SetPoint("TOPLEFT", content, "TOPLEFT", x, -(y + 10))
	track:SetSize(width - 34, 4)
	if share and share > 0 then
		local bar = pool:Bar(color)
		bar:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
		bar:SetSize(math.max(1, (width - 34) * math.min(share, 1)), 4)
	end
	local pct = pool:Text("Caption", "text3", Pct(share))
	pct:SetPoint("TOPRIGHT", content, "TOPLEFT", x + width, -(y + 6))
	pct:SetJustifyH("RIGHT")
end

local function ZoneDetail(pool, content, row, width)
	local z = row.zone
	local prefer = state.prefer[row.key]
	local side = prefer and z[prefer] or z.side
	local h = 0
	if pool then
		local head = side.source == "own" and (L["Own catches · n = %d"]):format(side.n) or (L["Reference · n = %d recorded loots"]):format(side.n)
		pool:Text("Label", "text3", head):SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		if z.own and z.ref then
			local other = side.source == "own" and "ref" or "own"
			local b = pool:Button(other == "ref" and L["Show reference"] or L["Show own catches"], function()
				state.prefer[row.key] = other
				M.Refresh()
			end)
			b:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 2)
		end
	end
	h = h + 24
	local nameW, eachW = 190, 80
	local shareW = math.floor((width - 18 - 10 - nameW - eachW - 30) / 2)
	local xName, xCatch = 28, 28 + nameW + 10
	local xMoney, xEach = xCatch + shareW + 10, width - eachW
	if pool then
		for _, hd in ipairs({ { L["Fish"], xName }, { L["Share of catches"], xCatch }, { L["Share of money"], xMoney } }) do
			pool:Text("Label", "text3", hd[1]):SetPoint("TOPLEFT", content, "TOPLEFT", hd[2], -h)
		end
		local each = pool:Text("Label", "text3", L["Each"])
		each:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -h)
		each:SetJustifyH("RIGHT")
	end
	h = h + 18
	local fish = P.FishLines(side)
	for _, f in ipairs(fish) do
		if pool then
			if f.itemID then
				local icon = pool:Icon(18, C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(f.itemID))
				icon:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(h + 3))
			end
			local q = f.itemID and Quality(f.itemID)
			local name = pool:Text("Small", f.junk and "text3" or (Style.QualityColor(q) or C.text), f.name)
			name:SetPoint("TOPLEFT", content, "TOPLEFT", xName, -(h + 6))
			name:SetWidth(nameW)
			ShareBar(pool, content, xCatch, h, shareW, f.catchShare, C.text2)
			ShareBar(pool, content, xMoney, h, shareW, f.moneyShare, C.coinGold)
			local each = pool:Text("Figure", "text", f.junk and Paint(L["vendor"], "text3")
				or (f.each and (Coins(f.each) .. (f.label and Paint(" " .. f.label, "text3") or "")) or M.NoPriceText()))
			each:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(h + 6))
			each:SetJustifyH("RIGHT")
			if f.itemID then
				local hit = pool:Hit({ itemID = f.itemID })
				hit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -h)
				hit:SetSize(xCatch, P.FISH_LINE)
			end
		end
		h = h + P.FISH_LINE
	end
	if #fish == 0 then
		if pool then
			pool:Text("Small", "text3", L["Nothing recorded for this zone."]):SetPoint("TOPLEFT", content, "TOPLEFT", 0, -h)
		end
		h = h + P.LINE
	end
	return h
end

----------------------------------------------------------------------------------------------------
-- Opened log row: what was caught there; a pool's visits
----------------------------------------------------------------------------------------------------

function P.VisitText(p)
	local parts = {}
	if p.visits > 0 then
		local per = p.min == p.max and tostring(p.min) or (p.min .. "–" .. p.max)
		parts[#parts + 1] = (L["%d visits ended, %s catches per visit (avg %s)"]):format(p.visits, per, tostring(p.avg))
	else
		parts[#parts + 1] = L["no ended visit"]
	end
	if (p.going or 0) > 0 then
		parts[#parts + 1] = (L["%d going on"]):format(p.going)
	end
	if p.seen then
		parts[#parts + 1] = (L["seen %d times"]):format(p.seen) .. (p.notFished and (", " .. (L["%d not fished"]):format(p.notFished)) or "")
	end
	return table.concat(parts, " · ")
end

local function LogDetail(pool, content, row, width)
	local h = 0
	if row.pool then
		if pool then
			pool:Text("Small", "text2", L["Visits"] .. ": " .. P.VisitText(row.pool)):SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
			local hit = pool:Hit({ tip = { L["Pool visits"], L["A visit ends when you fish elsewhere or stop; its catches are what the pool gave until it vanished or you left."] } })
			hit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
			hit:SetSize(width, P.LINE)
		end
		h = h + P.LINE + 6
	end
	for _, item in ipairs(row.items or {}) do
		if pool then
			local icon = pool:Icon(16, C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemID))
			icon:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(h + 1))
			local name = pool:Text("Small", Style.QualityColor(Quality(item.itemID)) or C.text,
				ItemName(item) .. " " .. Paint("×" .. item.count, "text3"))
			name:SetPoint("TOPLEFT", content, "TOPLEFT", 22, -(h + 3))
			name:SetWidth(260)
			local share = pool:Text("Figure", "text2", Pct(item.share))
			share:SetPoint("TOPLEFT", content, "TOPLEFT", 300, -(h + 3))
			local value = pool:Text("Figure", "text", item.unit and (Coins(item.unit.copper) .. Paint(" " .. (item.unit.label or ""), "text3"))
				or M.NoPriceText())
			value:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(h + 3))
			value:SetJustifyH("RIGHT")
			local hit = pool:Hit({ itemID = item.itemID })
			hit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -h)
			hit:SetSize(290, P.LINE + 2)
		end
		h = h + P.LINE + 2
	end
	if #(row.items or {}) == 0 and not row.pool then
		h = h + P.LINE
	end
	return math.max(h, P.LINE)
end

local function InnerWidth(ctx)
	local m = ctx and ctx.metrics or {}
	return (m.width or 880) - 56 - 22 - 28
end

function P.Layout(pool, content, row, width)
	if row.zone then
		return ZoneDetail(pool, content, row, width)
	end
	return LogDetail(pool, content, row, width)
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
-- Page tools: the chips in the sub bar (board: Spots Log | All water Pools Open water)
----------------------------------------------------------------------------------------------------

P.MODES = { { "spots", L["Spots"] }, { "log", L["Log"] } }
P.WATERS = { { "all", L["All water"] }, { "pool", L["Pools"] }, { "open", L["Open water"] } }

function P.Tools(slot)
	local chips = {}
	local list = {}
	for _, m in ipairs(P.MODES) do
		local c = Style.Chip(slot, m[2], 24)
		c:SetScript("OnClick", function()
			P.SetMode(m[1])
		end)
		c.cwMode = m[1]
		list[#list + 1] = c
	end
	local sep = slot:CreateTexture(nil, "ARTWORK")
	Style.Fill(sep, C.rule)
	sep:SetSize(1, 18)
	list[#list + 1] = sep
	for _, w in ipairs(P.WATERS) do
		local c = Style.Chip(slot, w[2], 24)
		c:SetScript("OnClick", function()
			P.SetWater(w[1])
		end)
		c.cwWater = w[1]
		list[#list + 1] = c
	end
	-- Right aligned, 6 apart (12 around the separator).
	local x = 0
	for i = #list, 1, -1 do
		local w = list[i]
		w:ClearAllPoints()
		w:SetPoint("RIGHT", slot, "RIGHT", -x, 0)
		x = x + (w.cwWidth or 1) + ((w == sep or list[i - 1] == sep) and 12 or 6)
	end
	for _, w in ipairs(list) do
		if w ~= sep then
			chips[#chips + 1] = w
		end
	end
	slot.chips = chips
end

function P.UpdateTools(slot)
	local mode, water = P.Mode(), P.Water()
	for _, c in ipairs(slot.chips or {}) do
		if c.cwMode then
			c:SetOn(c.cwMode == mode)
		else
			c:SetOn(c.cwWater == water)
		end
	end
end

P.page = M.RegisterPage({
	key = P.KEY, section = "gather", label = L["Fishing"], order = 2,
	events = { "PRICES_CHANGED" },
	columns = function(ctx) return P.Columns(ctx) end,
	sort = P.DEFAULT_SORT.spots,
	SortRows = P.SortRows,
	Model = function(ctx) return P.Model(ctx) end,
	Open = P.Open,
	OpenHeight = P.OpenHeight,
	Tools = P.Tools,
	UpdateTools = P.UpdateTools,
})

-- A new catch while the page shows: the page follows.
if ns.Fishing and ns.Fishing.Subscribe then
	ns.Fishing.Subscribe(function()
		if M.shown.page == P.KEY then
			M.Refresh()
		end
	end)
end
