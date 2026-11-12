-- Records window, Fishing log tab (`/craftwise fishing [pools|open] [zone]`, #86): your own catches of the
-- last days per zone, subzone and water (open water, each pool, not known yet), with value per catch and per
-- hour; and the pool visits. The search box filters by zone or subzone, as the slash command's zone argument.
-- (Zones ranked against the reference are the profit window's Fishing view; session gap and "own catches
-- count from" are in the Settings.)
local _, ns = ...
local RW = ns.RW
local L = ns.L
local C = ns.Style.colors
local Money, Muted = RW.Money, RW.Muted

local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local POOL_ICON = "Interface\\Icons\\INV_Misc_Fish_02"

local tab = { key = "fishing", label = L["Fishing log"], search = L["Zone"] }

local CATCH_COLUMNS = {
	{ key = "name", label = L["WHERE"], width = 240 },
	{ key = "catches", label = L["CATCHES"], width = 70, align = "RIGHT" },
	{ key = "perCatch", label = L["PER CATCH"], width = 110, align = "RIGHT" },
	{ key = "perHour", label = L["PER HOUR"], width = 125, align = "RIGHT" },
	{ key = "top", label = L["TOP CATCHES"], width = 190 },
}
local VISIT_COLUMNS = {
	{ key = "name", label = L["POOL"], width = 250 },
	{ key = "visits", label = L["VISITS"], width = 70, align = "RIGHT" },
	{ key = "perVisit", label = L["CATCHES PER VISIT"], width = 150, align = "RIGHT" },
	{ key = "going", label = L["GOING ON"], width = 80, align = "RIGHT" },
	{ key = "seen", label = L["SEEN"], width = 160, align = "RIGHT" },
}

-- "all" | "pool" | "open" (catch rows by water) | "visits" (pool visits).
function tab.Mode(st)
	local m = st.fishWater
	return (m == "pool" or m == "open" or m == "visits") and m or "all"
end

function tab.columns(st)
	return tab.Mode(st) == "visits" and VISIT_COLUMNS or CATCH_COLUMNS
end

function tab.buttons(st)
	local out = {}
	for _, m in ipairs({ { "all", L["All waters"] }, { "pool", L["Pools"] }, { "open", L["Open water"] }, { "visits", L["Pool visits"] } }) do
		out[#out + 1] = { key = m[1], label = m[2], width = 86, selected = tab.Mode(st) == m[1], onClick = function()
			st.fishWater = m[1]
		end }
	end
	return out
end

local function PerCatchText(value, unpriced, perCatch)
	if value == 0 and unpriced > 0 then
		return Muted(L["no price"])
	end
	return Money(perCatch) .. (unpriced > 0 and (" " .. C.warn .. "+" .. unpriced .. "?|r") or "")
end

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

local function ItemShort(itemID)
	local name = ns.ItemInfoNow and (ns.ItemInfoNow(itemID)) or nil
	return name or ("item " .. tostring(itemID))
end

local function CatchRow(r, ids)
	local top = {}
	local tip = { { L["Catches"], tostring(r.catches) }, { L["Items caught"], tostring(r.units) } }
	for i, item in ipairs(r.items) do
		ids[#ids + 1] = item.itemID
		if i <= 3 then
			top[#top + 1] = ("%s %d%%"):format(ItemShort(item.itemID), math.floor(item.share * 100 + 0.5))
		end
		tip[#tip + 1] = { ("%s x%d (%d%%)"):format(RW.ItemText(item.itemID), item.count, math.floor(item.share * 100 + 0.5)),
			item.unit and (Money(item.unit.copper) .. " " .. (item.unit.label or "")) or L["no price"] }
	end
	local hour
	if r.perHour then
		hour = Money(r.perHour)
		tip[#tip + 1] = { L["Per hour"], ("%s (n = %d %s, %d min)"):format(ns.FormatMoney(r.perHour), r.timed, L["timed"],
			math.floor(r.seconds / 60 + 0.5)) }
	else
		hour = Muted(L["not timed"])
		tip[#tip + 1] = L["Per hour: no timed catches (a session's first catch has no time)."]
	end
	local where = r.zone .. (r.sub ~= "" and (Muted(" · ") .. r.sub) or "")
	return { icon = r.water == "pool" and POOL_ICON or FISHING_ICON, name = where, sub = Muted(ns.Fishing.RowLabel(r)),
		cells = { catches = tostring(r.catches), perCatch = PerCatchText(r.value, r.unpriced, r.perCatch), perHour = hour,
			top = #top > 0 and table.concat(top, ", ") or Muted("-") }, tip = tip }
end

local function VisitRow(p)
	local name = p.name or (L["pool object %d (name not seen)"]):format(p.obj)
	local perVisit = p.visits > 0 and ((p.min == p.max and tostring(p.min) or (p.min .. "-" .. p.max)) .. Muted(", " .. L["avg"] .. " " .. tostring(p.avg)))
		or Muted(L["no ended visit"])
	local seen = p.seen and (tostring(p.seen) .. (p.notFished and Muted((", %d " .. L["not fished"]):format(p.notFished)) or "")) or Muted("-")
	return { icon = POOL_ICON, name = name, cells = { visits = tostring(p.visits), perVisit = perVisit,
		going = p.going > 0 and tostring(p.going) or Muted("0"), seen = seen },
		tip = { L["A visit ends when you fish elsewhere or stop; its catches are what the pool gave until it vanished or you left."] } }
end

function tab.Model(st)
	local F = ns.Fishing
	local mode = tab.Mode(st)
	local query = RW.Query("fishing")
	local t = F and F.Tables and F.Tables({ zone = query, water = (mode == "pool" or mode == "open") and mode or nil })
	if not t then
		return { rows = {}, summary = Muted(L["Fishing log not loaded yet."]), empty = "" }
	end
	local rows, ids = {}, {}
	if mode == "visits" then
		for _, p in ipairs(t.pools) do
			rows[#rows + 1] = VisitRow(p)
		end
	else
		for _, z in ipairs(t.zones) do
			for _, s in ipairs(z.subs) do
				for _, r in ipairs(s.rows) do
					rows[#rows + 1] = CatchRow(r, ids)
				end
			end
		end
	end
	RW.LoadNames(ids)
	local what = mode == "pool" and L["pool catches"] or mode == "open" and L["open-water catches"] or L["catches"]
	local line1 = ("|cffffffff%s|r  ·  %s %d %s: %d %s%s"):format(L["Fishing log"], L["last"], t.days, L["days"], t.catches, what,
		query ~= "" and (" " .. L["in"] .. " \"" .. query .. "\"") or "")
	local line2 = Muted((L["Sessions: catches less than %d min apart. Value: best sell value (AH after cut, else vendor)."]):format(t.gap))
		.. "  ·  " .. FindFishText(t.findFish)
	local empty = mode == "visits" and L["No pool seen or fished yet."] or (L["No catches in the last %d days."]):format(t.days)
	return { rows = rows, summary = line1 .. "\n" .. line2, empty = empty }
end

RW.Register(tab)
RW.FishingLog = tab
