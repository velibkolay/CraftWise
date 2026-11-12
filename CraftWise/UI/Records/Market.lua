-- Records window, Market tab (`/craftwise market <item>`, #26): auction house prices CraftWise recorded, per
-- item and house: latest lowest price, typical (median of the days), units listed, when it was seen; the
-- tooltip adds the cheapest tiers, the 7-day range, units that disappeared and the Auctionator export. The
-- summary says when each house was last scanned. Without a search it lists the items of the market scope
-- (reagents and products of your recipes, items you handled); a search (name, item ID or link) finds any
-- recorded item. Read only: nothing here changes CraftWiseMarketDB.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local C = ns.Style.colors
local Money, Muted = RW.Money, RW.Muted

local tab = { key = "market", label = L["Market"], search = L["Item name, ID or link"] }

tab.columns = {
	{ key = "name", label = L["ITEM"], width = 230 },
	{ key = "house", label = L["HOUSE"], width = 100 },
	{ key = "last", label = L["LATEST LOWEST"], width = 115, align = "RIGHT" },
	{ key = "typical", label = L["TYPICAL"], width = 115, align = "RIGHT" },
	{ key = "listed", label = L["ON THE AH"], width = 95, align = "RIGHT" },
	{ key = "seen", label = L["SEEN"], width = 70, align = "RIGHT" },
}

local function DB()
	return type(CraftWiseMarketDB) == "table" and CraftWiseMarketDB or nil
end

local function ItemIDOfKey(key)
	return tonumber(tostring(key):match("^%d+"))
end

local function NameOf(itemID)
	local name = ns.ItemInfoNow and (ns.ItemInfoNow(itemID)) or nil
	local db = DB()
	return name or (db and db.names and db.names[itemID]) or nil
end

-- Item keys to list: the query's item (ID or link), the items whose name contains it, or the scope.
-- Returns keys sorted by name, and how many more matched than RW.MARKET_MAX.
function tab.Keys(query)
	local db = DB()
	if not (db and db.items) then
		return {}, 0
	end
	query = (query or ""):match("^%s*(.-)%s*$")
	local wanted = tonumber(query:match("item:(%d+)") or query:match("^(%d+)$"))
	local lower = query:lower()
	local keys, names = {}, {}
	for key in pairs(db.items) do
		local itemID = ItemIDOfKey(key)
		local keep
		if wanted then
			keep = itemID == wanted
		elseif query == "" then
			keep = ns.Market.InScope(itemID)
		else
			local name = itemID and NameOf(itemID)
			keep = name and name:lower():find(lower, 1, true) ~= nil
		end
		if keep and itemID then
			keys[#keys + 1] = key
			names[key] = NameOf(itemID) or ("item " .. itemID)
		end
	end
	table.sort(keys, function(a, b)
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		return tostring(a) < tostring(b)
	end)
	local more = math.max(0, #keys - RW.MARKET_MAX)
	for i = #keys, RW.MARKET_MAX + 1, -1 do
		keys[i] = nil
	end
	return keys, more
end

local function HouseRow(key, house, now)
	local M = ns.Market
	local itemID = ItemIDOfKey(key)
	local cells, tip = {}, {}
	local current = M.Current(key, house.key)
	if current then
		cells.last = Money(current.min)
		cells.listed = current.listed and (tostring(current.qty) .. (current.listings and Muted(" / " .. current.listings) or ""))
			or Muted(L["none"])
		cells.seen = RW.Ago(current.t, now) or Muted("-")
		if not current.listed then
			tip[#tip + 1] = L["None in the latest full scan."]
		end
		if current.listings then
			tip[#tip + 1] = { L["Listed"], ("%d %s, %d %s"):format(current.qty, L["units"], current.listings, M.ListingsLabel(key) or L["listings"]) }
		end
	else
		cells.last, cells.listed, cells.seen = Muted("-"), Muted("-"), Muted("-")
	end
	local db = DB()
	local entry = db and db.items[key] and db.items[key][house.key]
	if entry and M.IsLastOnly(entry) and not M.InScope(itemID) then
		cells.typical = Muted(L["latest only"])
		tip[#tip + 1] = L["History: none (outside the market scope, latest price only)."]
	else
		local typical = M.Typical(key, house.key)
		if typical.status == "ok" then
			cells.typical = Money(typical.price) .. Muted((" %dd"):format(typical.days))
		elseif typical.status == M.TOO_LITTLE_HISTORY then
			cells.typical = Muted(("%d/%d %s"):format(typical.days, M.MIN_HISTORY_DAYS, L["days"]))
			tip[#tip + 1] = (L["Typical: too little history (%d of %d days)."]):format(typical.days, M.MIN_HISTORY_DAYS)
		else
			cells.typical = Muted("-")
		end
	end
	local depth = M.Depth(key, house.key, 5)
	if depth and depth[1] then
		local parts = {}
		for _, tier in ipairs(depth) do
			parts[#parts + 1] = ("%d @ %s"):format(tier.qty, ns.FormatMoney(tier.price))
		end
		tip[#tip + 1] = { L["Cheapest"], table.concat(parts, ", ") }
	end
	local lo, hi = M.Range(key, house.key)
	if lo then
		tip[#tip + 1] = { L["Last 7 days"], ns.FormatMoney(lo) .. (hi and hi > lo and (" - " .. ns.FormatMoney(hi)) or "") }
	end
	local gone = M.Disappeared(key, house.key)
	if gone > 0 then
		tip[#tip + 1] = { L["Disappeared in 7 days"], ("%d %s"):format(gone, L["units (sold or expired)"]) }
	end
	cells.house = house.label
	local name = RW.ItemText(itemID, { name = NameOf(itemID) })
	if key ~= itemID then
		name = name .. Muted(" (" .. tostring(key) .. ")")
	end
	return { itemID = itemID, icon = RW.ItemIcon(itemID), name = name, cells = cells, tip = tip }
end

local function ScanLine(now)
	local ok, sum = pcall(ns.Market.SnapshotSummary)
	if not (ok and sum and sum.houses) then
		return Muted(L["Market data not loaded."])
	end
	local houses = {}
	for _, h in pairs(sum.houses) do
		houses[#houses + 1] = h
	end
	table.sort(houses, function(a, b)
		if (a.kind == "faction") ~= (b.kind == "faction") then
			return a.kind == "faction"
		end
		return (a.label or "") < (b.label or "")
	end)
	local parts = {}
	for _, h in ipairs(houses) do
		local scan = h.lastFullScan and (L["full scan"] .. " " .. RW.Ago(h.lastFullScan, now) .. " " .. L["ago"])
			or L["no full scan"]
		parts[#parts + 1] = ("%s: %s, %d %s (%d %s)"):format(h.label or "?", scan, h.items, L["items"], h.withHistory, L["with history"])
	end
	if #parts == 0 then
		return Muted(L["No auction house visited yet: open one and CraftWise records what you browse and scan."])
	end
	return table.concat(parts, "  ·  ")
end

function tab.Model()
	local M = ns.Market
	local now = time()
	local query = RW.Query("market")
	local keys, more = tab.Keys(query)
	local rows, ids = {}, {}
	for _, key in ipairs(keys) do
		for _, house in ipairs(M.Houses(key)) do
			rows[#rows + 1] = HouseRow(key, house, now)
		end
		ids[#ids + 1] = ItemIDOfKey(key)
	end
	RW.LoadNames(ids)
	local line1 = ("|cffffffff%s|r  ·  %s"):format(L["Market"], query == "" and L["items of your recipes and items you handled"]
		or (L["items matching \"%s\""]):format(query))
	if more > 0 then
		line1 = line1 .. "  ·  " .. C.warn .. (L["%d more, search to narrow"]):format(more) .. "|r"
	end
	-- Auctionator's price for a single item asked for by ID or link (the slash command shows it too).
	local wanted = tonumber(query:match("item:(%d+)") or query:match("^%s*(%d+)%s*$"))
	local exported = wanted and M.AuctionatorExport(wanted)
	if exported then
		local db = DB()
		line1 = line1 .. ("  ·  %s: %s, %s %s"):format(db and db.auctionator and db.auctionator.label or "Auctionator",
			ns.FormatMoney(exported.copper), RW.Ago(exported.t, now), L["ago"])
	end
	local empty = query == "" and L["No recorded item of your recipes yet. Open the auction house and browse or scan."]
		or (L["No recorded item matches \"%s\"."]):format(query)
	return { rows = rows, summary = line1 .. "\n" .. ScanLine(now), empty = empty }
end

RW.Register(tab)
RW.Market = tab
