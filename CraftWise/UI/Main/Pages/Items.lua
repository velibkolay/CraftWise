-- Look up › Items (#157; spec in #150 "Look up, Music, Settings", board "Look up · Items"): one page for
-- every item's prices, where to buy it and where it is used. It merges Records › Market and Where to buy.
--   Sub bar tools: the search box (name, item ID or link; Shift-clicking an item while it has focus fills it).
--   Left list, 300 wide: chips Watched (only once #165 gives ns.ItemWatch), Your recipes (recorded items
--   in the market scope, Market.InScope), Recent (items looked up here); a search replaces the chip's list.
--   Row: name, listings note ("214 listed", "3 listed · thin", "vendor only"), typical price, 7-day change.
--   Right card: icon 40, name, class and stack, what you hold (Holdings), the Watched toggle (with #165);
--   Typical 7 days, Lowest now, On the AH, 7 days change; a chart of typical (solid) and lowest (dashed)
--   per day with the nokta on the latest point (Line objects; seven 4 unit day bars where the client has
--   no CreateLine); Used in (UsedIn); Where to buy (Merchant), vendor sell price, your last purchase.
--   Outside the market scope only the latest price is kept: "latest only" and no chart.
-- Prices are the profit house's (Settings › Prices). The item menu's Where to buy and Price history open
-- this page on the item: ns.ShowItemLookup(itemID, "where" | "history").
--
-- Watched hook for #165: ns.ItemWatch = { List() -> itemIDs, IsWatched(itemID) -> bool, Toggle(itemID) }.
-- Until it exists neither the chip nor the card's toggle shows.
--
-- Row data (Items.Row, Items.ListModel, Items.Card) is built apart from the drawing below, so the docked
-- layout (#161) can draw the same data its own way.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local Items = {}
M.Items = Items

Items.LIST_MAX = 150 -- rows listed at once; a search narrows them
Items.RECENT_MAX = 20
Items.DAYS = 7
Items.CHART_HEIGHT = 120
Items.LIST_WIDTH = 300
Items.ROW_HEIGHT = 36

----------------------------------------------------------------------------------------------------
-- State: chip, search and the item shown. Chip, item and recent items are kept in db.settings.ui.lookup.
----------------------------------------------------------------------------------------------------

Items.state = { query = "" }

local function Saved()
	local ui = M.UI()
	ui.lookup = type(ui.lookup) == "table" and ui.lookup or {}
	ui.lookup.recent = type(ui.lookup.recent) == "table" and ui.lookup.recent or {}
	return ui.lookup
end

function Items.WatchAvailable()
	local w = ns.ItemWatch
	return type(w) == "table" and type(w.List) == "function" and type(w.IsWatched) == "function"
		and type(w.Toggle) == "function"
end

-- The chips shown, in the board's order.
function Items.Chips()
	local chips = {}
	if Items.WatchAvailable() then
		chips[#chips + 1] = { key = "watched", label = L["Watched"] }
	end
	chips[#chips + 1] = { key = "recipes", label = L["Your recipes"] }
	chips[#chips + 1] = { key = "recent", label = L["Recent"] }
	return chips
end

function Items.Chip()
	local chosen = Saved().chip
	for _, c in ipairs(Items.Chips()) do
		if c.key == chosen then
			return chosen
		end
	end
	return "recipes" -- not Watched: a fresh list is empty (#165)
end

function Items.SetChip(key)
	Saved().chip = key
	M.Refresh()
end

function Items.Selected()
	return tonumber(Saved().item)
end

-- Shows an item on the card and puts it first in Recent.
function Items.Select(itemID, focus)
	itemID = tonumber(itemID)
	if not itemID then
		return
	end
	local saved = Saved()
	saved.item = itemID
	Items.state.focus = focus
	local recent = saved.recent
	for i = #recent, 1, -1 do
		if recent[i] == itemID then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, itemID)
	for i = #recent, Items.RECENT_MAX + 1, -1 do
		recent[i] = nil
	end
	M.Refresh()
end

function Items.SetQuery(text)
	Items.state.query = text or ""
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Model (pure apart from reading the saved data)
----------------------------------------------------------------------------------------------------

-- The item named by a query: an item ID or a link, else nil.
function Items.QueryItemID(query)
	query = tostring(query or "")
	return tonumber(query:match("item:(%d+)") or query:match("^%s*(%d+)%s*$"))
end

function Items.Name(itemID)
	local name = ns.ItemInfoNow and (ns.ItemInfoNow(itemID)) or nil
	return name or (ns.Market.StoredName and ns.Market.StoredName(itemID)) or nil
end

local function DisplayName(itemID)
	return Items.Name(itemID) or ("item " .. tostring(itemID))
end

local function SortByName(ids)
	local names = {}
	for _, id in ipairs(ids) do
		names[id] = DisplayName(id):lower()
	end
	table.sort(ids, function(a, b)
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		return a < b
	end)
	return ids
end

local function Cap(ids)
	local more = math.max(0, #ids - Items.LIST_MAX)
	for i = #ids, Items.LIST_MAX + 1, -1 do
		ids[i] = nil
	end
	return ids, more
end

-- Items a search finds: the item of an ID or link; else recorded items (AH or merchants) whose name
-- contains the text, exact names first. Returns itemIDs and how many more matched than Items.LIST_MAX.
function Items.Search(query)
	query = tostring(query or ""):match("^%s*(.-)%s*$")
	if query == "" then
		return {}, 0
	end
	local wanted = Items.QueryItemID(query)
	if wanted then
		return { wanted }, 0
	end
	local lower, seen, ids = query:lower(), {}, {}
	for itemID in pairs(ns.Market.RecordedItemIDs()) do
		local name = Items.Name(itemID)
		if name and name:lower():find(lower, 1, true) then
			seen[itemID] = true
			ids[#ids + 1] = itemID
		end
	end
	for _, itemID in ipairs((ns.Merchant.FindItems(query))) do
		if not seen[itemID] then
			seen[itemID] = true
			ids[#ids + 1] = itemID
		end
	end
	local names = {}
	for _, id in ipairs(ids) do
		names[id] = DisplayName(id):lower()
	end
	table.sort(ids, function(a, b)
		local ea, eb = names[a] == lower, names[b] == lower
		if ea ~= eb then
			return ea -- exact name first
		end
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		return a < b
	end)
	return Cap(ids)
end

-- The items behind a chip.
function Items.ChipItems(chip)
	if chip == "watched" then
		local ids = {}
		for _, id in ipairs(Items.WatchAvailable() and ns.ItemWatch.List() or {}) do
			ids[#ids + 1] = id
		end
		return Cap(SortByName(ids))
	elseif chip == "recent" then
		local ids = {}
		for i, id in ipairs(Saved().recent) do
			ids[i] = id
		end
		return ids, 0
	end
	local ids = {}
	for itemID in pairs(ns.Market.RecordedItemIDs()) do
		if ns.Market.InScope(itemID) then
			ids[#ids + 1] = itemID
		end
	end
	return Cap(SortByName(ids))
end

-- The market key used for an item at the profit house: the plain ID, else its first suffix variant.
function Items.Key(itemID)
	local keys = ns.Market.ItemKeys(itemID)
	return keys[1] or itemID, keys
end

-- 7-day change of the typical price: first and last day with a typical price in the series, in whole
-- percent; nil with fewer than two such days.
function Items.Change(series)
	local first, last
	for _, d in ipairs(series or {}) do
		if d.typ then
			first = first or d.typ
			last = d.typ
		end
	end
	local days = 0
	for _, d in ipairs(series or {}) do
		days = days + (d.typ and 1 or 0)
	end
	if days < 2 or not first or first <= 0 then
		return nil
	end
	local pct = (last - first) / first * 100
	return pct >= 0 and math.floor(pct + 0.5) or -math.floor(-pct + 0.5)
end

-- "▲ +4 %" (up, C.danger), "▼ −12 %" (down, C.nokta), "±0 %"; text, colour.
function Items.ChangeText(pct)
	if pct == nil then
		return M.DASH, "text3"
	elseif pct > 0 then
		return Style.Glyph("up", 10, "danger") .. " +" .. pct .. " %", "danger"
	elseif pct < 0 then
		return Style.Glyph("down", 10, "nokta") .. " −" .. (-pct) .. " %", "nokta"
	end
	return "±0 %", "text3"
end

-- Prices of an item at the profit house: { key, house, houseLabel, current, typical, quote, series,
-- lastOnly, depth, thin, vendorBuy }.
function Items.Prices(itemID, now)
	local Mk = ns.Market
	local key = Items.Key(itemID)
	local house, houseLabel = ns.ProfitHouse()
	local p = { key = key, house = house, houseLabel = houseLabel, vendorBuy = ns.GetVendorBuyPrice(itemID) }
	if not house then
		return p
	end
	p.current = Mk.Current(key, house)
	p.typical = Mk.Typical(key, house)
	p.lastOnly = Mk.IsLastOnlyAt(key, house) == true and not Mk.InScope(itemID)
	p.quote = Mk.Quote(key, house, "typical")
	if not p.lastOnly and p.current then
		p.series = Mk.DaySeries(key, house, Items.DAYS, now)
	end
	local depth = Mk.Depth(key, house, 8)
	if depth and depth[1] then
		p.depth = depth
		p.thin = Mk.IsThin(depth, Mk.StackSize(key))
	end
	return p
end

-- One row of the left list: { key, itemID, name, quality, icon, note, price, priceText, change, changeText,
-- changeColor }.
function Items.Row(itemID, now)
	local p = Items.Prices(itemID, now)
	local info = ns.Market.ItemInfo(itemID) or {}
	local row = { key = itemID, itemID = itemID, name = DisplayName(itemID), quality = info.q, icon = info.i }
	if p.current then
		if p.current.listed then
			row.note = (L["%d listed"]):format(p.current.qty or 0) .. (p.thin and (" · " .. L["thin"]) or "")
		else
			row.note = L["none listed"]
		end
	elseif p.vendorBuy then
		row.note = L["vendor only"]
	else
		row.note = L["no AH data"]
	end
	if p.quote then
		row.price = p.quote.copper
		row.priceText = ns.FormatCoins(p.quote.copper)
	elseif p.vendorBuy and not p.current then
		row.price = p.vendorBuy
		row.priceText = ns.FormatCoins(p.vendorBuy)
	else
		row.priceText = M.NoPriceText()
	end
	if p.lastOnly then
		row.changeText, row.changeColor = L["latest only"], "text3"
	elseif not p.current and p.vendorBuy then
		row.changeText, row.changeColor = L["vendor"], "text3"
	else
		row.change = Items.Change(p.series)
		row.changeText, row.changeColor = Items.ChangeText(row.change)
	end
	return row
end

-- The left list: { rows, empty, more, chips, chip, searching }.
function Items.ListModel(now)
	local query = Items.state.query or ""
	local searching = query:match("%S") ~= nil
	local chip = Items.Chip()
	local ids, more
	if searching then
		ids, more = Items.Search(query)
	else
		ids, more = Items.ChipItems(chip)
	end
	local rows = {}
	for i, id in ipairs(ids) do
		rows[i] = Items.Row(id, now)
	end
	local empty
	if searching then
		empty = (L["No recorded item matches \"%s\"."]):format(query)
	elseif chip == "recent" then
		empty = L["Items you look up show here."]
	elseif chip == "watched" then
		empty = L["Watch an item from its card and it shows here."]
	else
		empty = L["No recorded item of your recipes yet. Open the auction house and browse or scan."]
	end
	return { rows = rows, empty = empty, more = more, chips = Items.Chips(), chip = chip, searching = searching }
end

-- The chart's points: x per day, y per value inside height (pad above and below); nil values skip.
-- Returns { typ = { {x, y, day} }, lo = {...}, max, min, latest = {x, y} } or nil without two values.
function Items.ChartGeometry(series, width, height, pad)
	pad = pad or 8
	local lo, hi
	for _, d in ipairs(series or {}) do
		for _, v in ipairs({ d.typ or false, d.lo or false }) do
			if v then
				lo = (not lo or v < lo) and v or lo
				hi = (not hi or v > hi) and v or hi
			end
		end
	end
	if not lo then
		return nil
	end
	local n = #series
	local function X(i)
		return n > 1 and (i - 1) * width / (n - 1) or width / 2
	end
	local function Y(v)
		if hi == lo then
			return height / 2
		end
		return pad + (v - lo) / (hi - lo) * (height - 2 * pad)
	end
	local g = { typ = {}, lo = {}, max = hi, min = lo }
	for i, d in ipairs(series) do
		if d.typ then
			g.typ[#g.typ + 1] = { x = X(i), y = Y(d.typ), day = d.day }
		end
		if d.lo then
			g.lo[#g.lo + 1] = { x = X(i), y = Y(d.lo), day = d.day }
		end
	end
	g.latest = g.typ[#g.typ] or g.lo[#g.lo]
	return g
end

-- Dashes along a line: on units drawn, off units left out. { { x1, y1, x2, y2 }, ... }.
function Items.Dashes(x1, y1, x2, y2, on, off)
	on, off = on or 3, off or 3
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local out = {}
	if len <= 0 then
		return out
	end
	local ux, uy, t = dx / len, dy / len, 0
	while t < len do
		local e = math.min(t + on, len)
		out[#out + 1] = { x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e }
		t = e + off
	end
	return out
end

-- How the chart is drawn on a frame: "lines" where the client has Line objects, else "bars".
function Items.ChartMode(frame)
	return (frame and type(frame.CreateLine) == "function") and "lines" or "bars"
end

local function WeekdayLabel(day)
	local t = day * 86400 + 43200
	return date("%a", t) .. " " .. tonumber(date("%d", t))
end

-- "6 in bags, 40 in the bank" from the holdings counter, and the places counted (Holdings.PlacesText).
local function HoldText(itemID)
	local H = ns.Holdings
	if not (H and H.Counter) then
		return nil
	end
	local total, parts = H.Counter()(itemID)
	local bits = {}
	if parts.bags > 0 then
		bits[#bits + 1] = ("%d %s"):format(parts.bags, L["in bags"])
	end
	if (parts.bank or 0) > 0 then
		bits[#bits + 1] = ("%d %s"):format(parts.bank, L["in the bank"])
	end
	if (parts.mail or 0) > 0 then
		bits[#bits + 1] = ("%d %s"):format(parts.mail, L["in the mail"])
	end
	local text = total > 0 and (L["you have"] .. " " .. table.concat(bits, ", ")) or L["you have none"]
	local counted, missing = H.PlacesText()
	return text, { L["Counted"] .. ": " .. (counted or ""), missing and (L["Not counted"] .. ": " .. missing) or nil }
end

-- Your last purchase from the ledger: "8s 80c each · Tue", nil when none was logged.
local function LastPurchase(itemID, now)
	local entries = ns.Ledger and ns.Ledger.Entries and ns.Ledger.Entries() or {}
	for i = #entries, 1, -1 do
		local e = entries[i]
		if e.i == itemID and (e.k == "ahbuy" or e.k == "vbuy") and (e.q or 0) > 0 then
			local when = (now - (e.t or now)) < 6 * 86400 and date("%a", e.t) or date("%d %b", e.t)
			return ns.FormatCoins(math.floor(e.m / e.q + 0.5)) .. " " .. L["each"] .. " · " .. when, e
		end
	end
	return nil
end

local function Lines(list)
	local out = {}
	for _, l in ipairs(list) do
		if l then
			out[#out + 1] = l
		end
	end
	return out
end

-- Everything the card shows for one item (pure data).
function Items.Card(itemID, now)
	now = now or time()
	local Mk = ns.Market
	local info = Mk.ItemInfo(itemID) or {}
	local p = Items.Prices(itemID, now)
	local card = { itemID = itemID, name = DisplayName(itemID), quality = info.q, focus = Items.state.focus }
	local getInfo = C_Item and C_Item.GetItemInfo
	local itemType, stack
	if getInfo then
		itemType = select(6, getInfo(itemID))
		stack = select(8, getInfo(itemID))
	end
	card.icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or info.i
	stack = Mk.StackSize(itemID) or stack
	local sub = {}
	if type(itemType) == "string" and itemType ~= "" then
		sub[#sub + 1] = itemType
	end
	if stack and stack > 1 then
		sub[#sub + 1] = (L["stacks of %d"]):format(stack)
	end
	local hold, holdTip = HoldText(itemID)
	if hold then
		sub[#sub + 1] = hold
	end
	card.sub, card.subTip = table.concat(sub, " · "), holdTip
	if Items.WatchAvailable() then
		card.watched = ns.ItemWatch.IsWatched(itemID) and true or false
	end

	-- Figures.
	local houseLine = p.houseLabel or L["the auction house"]
	local fig = {}
	local typical = p.typical
	if p.lastOnly then
		fig.typical = { text = Style.Hex("text3") .. L["latest only"] .. "|r", tip = { L["Typical, 7 days"], L["Outside the market scope only the latest price is kept."] } }
	elseif typical and typical.status == "ok" then
		fig.typical = { text = ns.FormatCoins(typical.price), tip = { L["Typical, 7 days"], (L["Median of %d days at %s."]):format(typical.days, houseLine) } }
	elseif typical and typical.status == Mk.TOO_LITTLE_HISTORY then
		fig.typical = { text = M.NoPriceText(), tip = { L["Typical, 7 days"], (L["Too little history: %d of %d days."]):format(typical.days, Mk.MIN_HISTORY_DAYS) } }
	else
		fig.typical = { text = M.NoPriceText(), tip = { L["Typical, 7 days"], (L["Nothing recorded at %s."]):format(houseLine) } }
	end
	local cur = p.current
	if cur and cur.listed then
		local tip = { L["Lowest now"], (L["Seen %s ago at %s."]):format(M.AgeText(now - cur.t), houseLine) }
		if p.depth then
			tip[#tip + 1] = L["Cheapest"] .. ": " .. Mk.DepthText(p.depth, 5, function(c) return ns.FormatMoney(c, true) end)
		end
		local lo, hi = Mk.Range(p.key, p.house)
		if lo then
			tip[#tip + 1] = L["Last 7 days"] .. ": " .. ns.FormatMoney(lo, true) .. (hi and hi > lo and (" – " .. ns.FormatMoney(hi, true)) or "")
		end
		fig.lowest = { text = ns.FormatCoins(cur.min), tip = tip }
	elseif cur then
		fig.lowest = { text = M.NoPriceText(), tip = { L["Lowest now"], L["Not listed in the last full scan"],
			(L["Last seen at %s, %s ago."]):format(ns.FormatMoney(cur.min, true), M.AgeText(now - cur.t)) } }
	else
		fig.lowest = { text = M.NoPriceText(), tip = { L["Lowest now"], (L["Nothing recorded at %s."]):format(houseLine) } }
	end
	if cur then
		local tip = { L["On the AH"] }
		if cur.listings then
			tip[#tip + 1] = ("%d %s, %d %s"):format(cur.qty or 0, L["units"], cur.listings, Mk.ListingsLabel(p.key) or L["listings"])
		end
		local gone = Mk.Disappeared(p.key, p.house)
		if gone > 0 then
			tip[#tip + 1] = (L["%d units disappeared in 7 days (sold or expired)."]):format(gone)
		end
		if p.thin then
			tip[#tip + 1] = L["Thin market: little at the lowest price."]
		end
		fig.listed = { text = cur.listed and M.Thousands(cur.qty or 0) or "0", tip = tip }
	else
		fig.listed = { text = M.DASH, tip = { L["On the AH"], (L["Nothing recorded at %s."]):format(houseLine) } }
	end
	local pct = not p.lastOnly and Items.Change(p.series) or nil
	local chText, chColor = Items.ChangeText(pct)
	fig.change = { text = Style.Hex(chColor) .. chText .. "|r", color = chColor, pct = pct,
		tip = { L["7 days"], L["First to last day with a typical price, last 7 days."] } }
	-- Other houses and Auctionator: on the Typical tip, as Records › Market listed them.
	for _, h in ipairs(Mk.Houses(p.key)) do
		if h.key ~= p.house then
			local q = Mk.Quote(p.key, h.key, "typical")
			table.insert(fig.typical.tip, ("%s: %s"):format(h.label, q and ns.FormatMoney(q.copper, true) or L["no price"]))
		end
	end
	local exported = Mk.AuctionatorExport and Mk.AuctionatorExport(itemID)
	if exported then
		table.insert(fig.typical.tip, ("%s: %s, %s %s"):format(ns.AUCTIONATOR_LABEL, ns.FormatMoney(exported.copper, true),
			M.AgeText(now - exported.t), L["ago"]))
	end
	card.figures = fig

	-- Chart.
	if p.lastOnly then
		card.chart = { mode = "latest", note = L["Latest price only: the item is outside the market scope (your recipes and items you handled), so no history is kept."] }
	elseif p.series then
		local any = 0
		for _, d in ipairs(p.series) do
			any = any + ((d.typ or d.lo) and 1 or 0)
		end
		if any > 0 then
			card.chart = { mode = "chart", series = p.series, first = WeekdayLabel(p.series[1].day), last = L["Today"] }
		else
			card.chart = { mode = "none", note = L["No price in the last 7 days."] }
		end
	else
		card.chart = { mode = "none", note = (L["No auction house price recorded at %s yet."]):format(houseLine) }
	end

	-- Used in.
	local used = {}
	for i, g in ipairs(ns.UsedInSummary and ns.UsedInSummary(itemID) or {}) do
		if i > 2 then
			break
		end
		used[#used + 1] = { left = g.profession, right = g.mine and (L["%d recipes · %d known"]):format(g.count, g.known)
			or (L["%d recipes"]):format(g.count) }
	end
	for _, e in ipairs(ns.UsedIn and ns.UsedIn(itemID) or {}) do
		if #used >= 4 or e.state ~= "known" then
			break
		end
		used[#used + 1] = { left = e.name, right = "×" .. (e.quantity or 1), rightColor = "text2" }
	end
	if #used == 0 then
		used[1] = { left = L["No recipe uses it."], leftColor = "text2" }
	end
	card.usedIn = used

	-- Where to buy.
	local where = {}
	local sellers = ns.Merchant.Sellers(itemID)
	for i, s in ipairs(sellers) do
		if i > 2 then
			break
		end
		where[#where + 1] = { left = s.merchant.name or ("NPC " .. tostring(s.npcID)), right = ns.Merchant.PriceText(s.item, true) }
	end
	if #sellers == 0 then
		where[1] = { left = L["No merchant you opened sells it."], leftColor = "text2" }
	elseif #sellers > 2 then
		where[#where + 1] = { left = (L["%d more merchants"]):format(#sellers - 2), leftColor = "text2" }
	end
	card.whereTip = Lines(ns.Merchant.SellerLines(itemID, now))
	local sell = ns.GetVendorSellPrice(itemID)
	where[#where + 1] = { left = L["Vendor sell price"], right = sell and sell > 0 and ns.FormatCoins(sell) or (sell == 0 and L["vendors don't buy it"]) or L["unknown"],
		rightColor = sell and sell > 0 and nil or "text3" }
	local last = LastPurchase(itemID, now)
	where[#where + 1] = { left = L["Your last purchase"], right = last or L["none logged"], rightColor = not last and "text3" or nil }
	card.where = where
	return card
end

-- What the page shows: { list, card }.
function Items.Model(now)
	now = now or time()
	local list = Items.ListModel(now)
	local selected = Items.Selected()
	return { list = list, card = selected and Items.Card(selected, now) or nil }
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local CARD_PAD_X, CARD_PAD_Y, FIG_TOP, FIG_GAP = 20, 14, 66, 14
local KV_ROW = 20

local function SetColor(fs, color)
	local c = Style.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function ItemTip(owner, itemID)
	if itemID and GameTooltip and GameTooltip.SetItemByID then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(itemID)
		GameTooltip:Show()
	end
end

local function HideTips(owner)
	if GameTooltip then
		GameTooltip:Hide()
	end
	Style.HideTip(owner)
end

-- A hover area over a region that shows the inverse tip of tipFn().
local function TipArea(parent, tipFn)
	local hit = CreateFrame("Frame", nil, parent)
	hit:EnableMouse(true)
	hit:SetScript("OnEnter", function(self)
		local tip = tipFn()
		if tip and tip[1] then
			Style.ShowTip(self, unpack(tip))
		end
	end)
	hit:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	return hit
end

-- Left list rows.
local function BuildListRow(page, b)
	b.cw = true
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	Style.Fill(b.bg, C.selected)
	b.hair = Style.Rule(b, "H", C.rule, "BORDER")
	b.hair:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.hair:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(20, 20)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon:SetPoint("LEFT", b, "LEFT", 16, 0)
	b.price = Style.Text(b, "FigureBold", "text")
	b.price:SetJustifyH("RIGHT")
	b.price:SetPoint("TOPRIGHT", b, "TOPRIGHT", -16, -5)
	b.change = Style.Text(b, "Caption", "text3")
	b.change:SetJustifyH("RIGHT")
	b.change:SetPoint("TOPRIGHT", b.price, "BOTTOMRIGHT", 0, -1)
	b.name = Style.Text(b, "Body", "text")
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(false)
	b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 46, -5)
	b.name:SetWidth(150)
	b.note = Style.Text(b, "Caption", "text3")
	b.note:SetJustifyH("LEFT")
	b.note:SetWordWrap(false)
	b.note:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -1)
	b.note:SetWidth(150)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	b:SetScript("OnClick", function(self, mouse)
		Items.ClickRow(self.row, mouse, self)
	end)
	b:SetScript("OnEnter", function(self)
		if self.row then
			ItemTip(self, self.row.itemID)
		end
	end)
	b:SetScript("OnLeave", function(self)
		HideTips(self)
	end)
end

local function InitListRow(b, row)
	if not b.cw then
		BuildListRow(nil, b)
	end
	b.row = row
	b.bg:SetShown(row.itemID == Items.Selected())
	b.icon:SetTexture(row.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.itemID)) or 134400)
	b.name:SetText(row.name)
	SetColor(b.name, Style.QualityColor(row.quality) or "text")
	b.note:SetText(row.note or "")
	b.price:SetText(row.priceText or "")
	b.change:SetText(row.changeText or "")
	SetColor(b.change, row.changeColor or "text3")
end

-- A click on a list row: left selects (Shift: link to chat), right or middle opens the item menu.
-- Returns what it did, for the specs.
function Items.ClickRow(row, mouse, owner)
	if not row then
		return nil
	end
	if mouse == "LeftButton" and IsShiftKeyDown() then
		M.LinkToChat(row.itemID)
		return "link"
	end
	if mouse == "RightButton" or mouse == "MiddleButton" then
		HideTips(owner)
		if ns.ShowItemMenu then
			ns.ShowItemMenu(row.itemID, owner)
		end
		return "menu"
	end
	Items.Select(row.itemID)
	return "select"
end

local function BuildList(body)
	local left = CreateFrame("Frame", nil, body)
	body.left = left
	left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	left:SetWidth(Items.LIST_WIDTH)
	left.rule = Style.Rule(body, "V", C.rule)
	left.rule:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	left.rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 0)
	left.chips = {}
	left.box = CreateFrame("Frame", nil, left, "WowScrollBoxList")
	left.box:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -44)
	left.box:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, 0)
	left.bar = CreateFrame("EventFrame", nil, left, "MinimalScrollBar")
	left.bar:SetPoint("TOPRIGHT", left.box, "TOPRIGHT", -4, 0)
	left.bar:SetPoint("BOTTOMRIGHT", left.box, "BOTTOMRIGHT", -4, 0)
	Style.ScrollBar(left.bar)
	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(function(factory, element)
		factory("Button", function(b, e)
			InitListRow(b, e.row)
		end)
	end)
	view:SetElementExtentCalculator(function()
		return Items.ROW_HEIGHT
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(left.box, left.bar, view)
	if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
		ScrollUtil.AddManagedScrollBarVisibilityBehavior(left.box, left.bar)
	end
	left.empty = Style.Text(left, "Small", "text3")
	left.empty:SetPoint("TOPLEFT", left.box, "TOPLEFT", 16, -12)
	left.empty:SetWidth(Items.LIST_WIDTH - 32)
	left.empty:SetJustifyH("LEFT")
	left.empty:SetWordWrap(true)
	left.more = Style.Text(left, "Caption", "text3")
	left.more:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 16, 6)
end

local function DrawList(body, list)
	local left = body.left
	local x = 16
	for i, chip in ipairs(list.chips) do
		local b = left.chips[i]
		if not b then
			b = Style.Chip(left, "")
			b:SetScript("OnClick", function(self)
				Items.state.query = ""
				if body.search then
					body.search:SetText("")
				end
				Items.SetChip(self.key)
			end)
			left.chips[i] = b
		end
		b.key = chip.key
		b:SetLabel(chip.label)
		b:SetOn(chip.key == list.chip and not list.searching)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", left, "TOPLEFT", x, -10)
		b:Show()
		x = x + (b.cwWidth or 80) + 6
	end
	for i = #list.chips + 1, #left.chips do
		left.chips[i]:Hide()
	end
	local elements = {}
	for i, row in ipairs(list.rows) do
		elements[i] = { row = row }
	end
	left.box:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	left.empty:SetShown(#list.rows == 0)
	left.empty:SetText(list.empty or "")
	left.more:SetShown((list.more or 0) > 0)
	left.more:SetText((L["%d more, search to narrow"]):format(list.more or 0))
end

-- Card: key-value block (Used in, Where to buy).
local function KVBlock(parent, title)
	local blk = CreateFrame("Frame", nil, parent)
	blk.title = Style.Text(blk, "BodyBold", "text")
	blk.title:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, 0)
	blk.title:SetText(title)
	blk.rule = blk:CreateTexture(nil, "ARTWORK")
	Style.Fill(blk.rule, C.text)
	blk.rule:SetHeight(2)
	blk.rule:SetPoint("TOPLEFT", blk, "TOPLEFT", 0, -18)
	blk.rule:SetPoint("TOPRIGHT", blk, "TOPRIGHT", 0, -18)
	blk.rows = {}
	function blk:Set(lines)
		for i, line in ipairs(lines) do
			local r = self.rows[i]
			if not r then
				r = CreateFrame("Frame", nil, self)
				r:SetHeight(KV_ROW)
				r.left = Style.Text(r, "Small", "text")
				r.left:SetPoint("LEFT", r, "LEFT", 0, 0)
				r.left:SetJustifyH("LEFT")
				r.left:SetWordWrap(false)
				r.right = Style.Text(r, "Figure", "text")
				r.right:SetPoint("RIGHT", r, "RIGHT", 0, 0)
				r.right:SetJustifyH("RIGHT")
				r.hair = Style.Rule(r, "H", C.rule)
				r.hair:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
				r.hair:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
				self.rows[i] = r
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -22 - (i - 1) * KV_ROW)
			r:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -22 - (i - 1) * KV_ROW)
			r.left:SetText(line.left or "")
			SetColor(r.left, line.leftColor or "text")
			r.right:SetText(line.right or "")
			SetColor(r.right, line.rightColor or "text")
			r:Show()
		end
		for i = #lines + 1, #self.rows do
			self.rows[i]:Hide()
		end
		self.lines = lines
	end
	return blk
end

local FIGURES = {
	{ key = "typical", label = "Typical, 7 days", font = "FigureL" },
	{ key = "lowest", label = "Lowest now", font = "FigureBold" },
	{ key = "listed", label = "On the AH", font = "FigureBold" },
	{ key = "change", label = "7 days", font = "FigureBold" },
}

local function BuildCard(body)
	local card = CreateFrame("Frame", nil, body)
	body.card = card
	card:SetPoint("TOPLEFT", body, "TOPLEFT", Items.LIST_WIDTH + 1, 0)
	card:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(40, 40)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -CARD_PAD_Y)
	card.iconHit = CreateFrame("Frame", nil, card)
	card.iconHit:EnableMouse(true)
	card.iconHit:SetAllPoints(card.icon)
	card.iconHit:SetScript("OnEnter", function(self)
		ItemTip(self, card.itemID)
	end)
	card.iconHit:SetScript("OnLeave", function(self)
		HideTips(self)
	end)
	card.name = Style.Text(card, "Hero", "text")
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 0)
	card.sub = Style.Text(card, "Caption", "text3")
	card.sub:SetJustifyH("LEFT")
	card.sub:SetWordWrap(false)
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
	card.subHit = TipArea(card, function()
		return card.data and card.data.subTip and { L["Where you hold it"], unpack(card.data.subTip) }
	end)
	card.subHit:SetAllPoints(card.sub)
	card.watch = Style.Chip(card, L["Watched"], 26)
	card.watch:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD_X, -CARD_PAD_Y)
	card.watch:SetScript("OnClick", function()
		if card.itemID and Items.WatchAvailable() then
			ns.ItemWatch.Toggle(card.itemID)
			M.Refresh()
		end
	end)
	card.watch:Hide()

	card.figs = {}
	for i, def in ipairs(FIGURES) do
		local f = CreateFrame("Frame", nil, card)
		f:SetHeight(44)
		f.label = Style.Text(f, "Label", "text3")
		f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		f.label:SetText(L[def.label])
		f.value = Style.Text(f, def.font, "text")
		f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, def.font == "FigureL" and -1 or -5)
		f.value:SetJustifyH("LEFT")
		f.key = def.key
		f:EnableMouse(true)
		f:SetScript("OnEnter", function(self)
			local fig = card.data and card.data.figures[self.key]
			if fig and fig.tip then
				Style.ShowTip(self, unpack(fig.tip))
			end
		end)
		f:SetScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
		card.figs[i] = f
	end

	local chart = CreateFrame("Frame", nil, card)
	card.chart = chart
	chart:SetHeight(Items.CHART_HEIGHT)
	chart.axis = Style.Rule(chart, "H", C.ruleStrong)
	chart.axis:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 0, 0)
	chart.axis:SetPoint("BOTTOMRIGHT", chart, "BOTTOMRIGHT", 0, 0)
	chart.top = Style.Text(chart, "Caption", "text3")
	chart.top:SetPoint("TOPLEFT", chart, "TOPLEFT", 0, 0)
	chart.bottom = Style.Text(chart, "Caption", "text3")
	chart.bottom:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 0, 4)
	chart.first = Style.Text(card, "Caption", "text3")
	chart.first:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -3)
	chart.last = Style.Text(card, "Caption", "text3")
	chart.last:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -3)
	chart.note = Style.Text(card, "Small", "text3")
	chart.note:SetJustifyH("LEFT")
	chart.note:SetWordWrap(true)
	chart.nokta = Style.Nokta(chart)
	chart.nokta:Hide()
	chart.lines, chart.bars = {}, {}

	card.used = KVBlock(card, L["Used in"])
	card.where = KVBlock(card, L["Where to buy"])
	card.whereHit = TipArea(card.where, function()
		local tip = card.data and card.data.whereTip
		return tip and tip[1] and { L["Where to buy"], unpack(tip) } or nil
	end)
	card.whereHit:SetPoint("TOPLEFT", card.where, "TOPLEFT", 0, 0)
	card.whereHit:SetPoint("TOPRIGHT", card.where, "TOPRIGHT", 0, 0)
	card.whereHit:SetHeight(18)

	card.empty = Style.Text(card, "Body", "text3")
	card.empty:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -CARD_PAD_Y - 6)
	card.empty:SetJustifyH("LEFT")
	card.empty:SetText(L["Choose an item on the left, or search for one."])
end

-- A line on the chart: a Line object, reused.
local function ChartLine(chart, i, color, thickness)
	local line = chart.lines[i]
	if not line then
		line = chart:CreateLine(nil, "ARTWORK")
		chart.lines[i] = line
	end
	line:SetThickness(thickness)
	line:SetColorTexture(color[1], color[2], color[3], 1)
	line:Show()
	return line
end

local function DrawChart(card, chartData, width)
	local chart = card.chart
	for _, l in ipairs(chart.lines) do
		l:Hide()
	end
	for _, b in ipairs(chart.bars) do
		b:Hide()
	end
	chart.nokta:Hide()
	chart.mode = nil
	local show = chartData and chartData.mode == "chart"
	for _, r in ipairs({ chart, chart.first, chart.last }) do
		r:SetShown(show and true or false)
	end
	chart.note:SetShown(not show)
	chart.note:SetText(chartData and chartData.note or "")
	if not show then
		return
	end
	local h = Items.CHART_HEIGHT
	local g = Items.ChartGeometry(chartData.series, width, h)
	if not g then
		return
	end
	chart.top:SetText(ns.FormatMoney(g.max, true))
	chart.bottom:SetText(ns.FormatMoney(g.min, true))
	chart.first:SetText(chartData.first or "")
	chart.last:SetText(chartData.last or "")
	chart.mode = Items.ChartMode(chart)
	if chart.mode == "lines" then
		local n = 0
		for i = 2, #g.typ do
			n = n + 1
			local line = ChartLine(chart, n, C.text, 2)
			line:SetStartPoint("BOTTOMLEFT", chart, g.typ[i - 1].x, g.typ[i - 1].y)
			line:SetEndPoint("BOTTOMLEFT", chart, g.typ[i].x, g.typ[i].y)
		end
		for i = 2, #g.lo do
			for _, d in ipairs(Items.Dashes(g.lo[i - 1].x, g.lo[i - 1].y, g.lo[i].x, g.lo[i].y)) do
				n = n + 1
				local line = ChartLine(chart, n, C.text2, 1.5)
				line:SetStartPoint("BOTTOMLEFT", chart, d[1], d[2])
				line:SetEndPoint("BOTTOMLEFT", chart, d[3], d[4])
			end
		end
		chart.drawn = n
	else
		-- Seven 4 unit day bars of the typical price (no Line objects in this client).
		local n = 0
		for _, pt in ipairs(g.typ) do
			n = n + 1
			local bar = chart.bars[n]
			if not bar then
				bar = chart:CreateTexture(nil, "ARTWORK")
				chart.bars[n] = bar
			end
			Style.Fill(bar, pt == g.latest and C.text or C.text2)
			bar:ClearAllPoints()
			bar:SetPoint("BOTTOM", chart, "BOTTOMLEFT", pt.x, 0)
			bar:SetSize(4, math.max(pt.y, 1))
			bar:Show()
		end
		chart.drawn = n
	end
	if g.latest then
		chart.nokta:MoveTo(chart, "BOTTOMLEFT", g.latest.x, g.latest.y, true)
	end
end

local function DrawCard(body, data, width)
	local card = body.card
	card.data = data
	local shown = data ~= nil
	for _, r in ipairs({ card.icon, card.iconHit, card.name, card.sub, card.subHit, card.used, card.where }) do
		r:SetShown(shown)
	end
	for _, f in ipairs(card.figs) do
		f:SetShown(shown)
	end
	card.empty:SetShown(not shown)
	if not shown then
		card.itemID = nil
		card.watch:Hide()
		card.chart:Hide()
		card.chart.note:Hide()
		card.chart.first:Hide()
		card.chart.last:Hide()
		return
	end
	card.itemID = data.itemID
	card.icon:SetTexture(data.icon or 134400)
	card.name:SetText(data.name)
	SetColor(card.name, Style.QualityColor(data.quality) or "text")
	card.name:SetWidth(width - 52 - 110)
	card.sub:SetText(data.sub or "")
	card.sub:SetWidth(width - 52)
	card.watch:SetShown(data.watched ~= nil)
	if data.watched ~= nil then
		card.watch:SetOn(data.watched)
	end
	local colW = (width - 3 * FIG_GAP) / 4
	for i, f in ipairs(card.figs) do
		local fig = data.figures[f.key]
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X + (i - 1) * (colW + FIG_GAP), -FIG_TOP)
		f:SetWidth(colW)
		f.value:SetText(fig and fig.text or "")
	end
	local chartTop = FIG_TOP + 44 + 12
	card.chart:ClearAllPoints()
	card.chart:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -chartTop)
	card.chart:SetWidth(width)
	card.chart.note:ClearAllPoints()
	card.chart.note:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -chartTop)
	card.chart.note:SetWidth(width)
	DrawChart(card, data.chart, width)
	local blockTop = chartTop + (data.chart and data.chart.mode == "chart" and (Items.CHART_HEIGHT + 22) or 36)
	local half = (width - 20) / 2
	card.used:ClearAllPoints()
	card.used:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -blockTop)
	card.used:SetSize(half, 22 + 5 * KV_ROW)
	card.used:Set(data.usedIn)
	card.where:ClearAllPoints()
	card.where:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X + half + 20, -blockTop)
	card.where:SetSize(half, 22 + 5 * KV_ROW)
	card.where:Set(data.where)
end

-- Search box in the sub bar (board: 300 x 26, 1 unit C.text border).
local function BuildSearch(slot, body)
	local box = CreateFrame("EditBox", nil, slot)
	box:SetSize(300, 26)
	box:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Style.Fonts.Small)
	box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	box:SetTextInsets(8, 8, 0, 0)
	box.border = Style.Border(box, C.text)
	box.hint = Style.Text(box, "Small", "text3")
	box.hint:SetPoint("LEFT", box, "LEFT", 8, 0)
	box.hint:SetText(L["Item name, ID or link (Shift-click an item)"])
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "")
		if text ~= Items.state.query then
			Items.SetQuery(text)
		end
	end)
	box:SetScript("OnEnterPressed", function(self)
		local first = Items.lastModel and Items.lastModel.list.rows[1]
		if first then
			Items.Select(first.itemID)
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	body.search = box
	Items.searchBox = box
	return box
end

-- Shift-clicking an item while the search box has focus puts its link there (Blizzard's modified click
-- calls ChatFrameUtil.InsertLink; no chat box is open, so nothing else takes it).
function Items.InsertLink(link)
	local box = Items.searchBox
	if box and box.HasFocus and box:HasFocus() and type(link) == "string" then
		box:SetText(link)
		return true
	end
	return false
end

if ChatFrameUtil and ChatFrameUtil.InsertLink and hooksecurefunc then
	hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
		Items.InsertLink(link)
	end)
end

M.RegisterPage({
	key = "items", section = "lookup", label = L["Items"], order = 1, kind = "custom", prices = true, pricesOptional = true,
	events = { "MERCHANTS_CHANGED", "LEDGER_CHANGED", "BAGS_CHANGED", "ITEM_WATCH_CHANGED" },
	Tools = function(slot)
		BuildSearch(slot, slot)
	end,
	UpdateTools = function(slot)
		local box = Items.searchBox
		if box and (box:GetText() or "") ~= Items.state.query then
			box:SetText(Items.state.query)
		end
	end,
	Build = function(body)
		BuildList(body)
		BuildCard(body)
		body.search = Items.searchBox
	end,
	Refresh = function(body, ctx)
		local width = (ctx and ctx.metrics and ctx.metrics.width or 880) - Items.LIST_WIDTH - 1 - 2 * CARD_PAD_X
		local model = Items.Model()
		Items.lastModel = model
		body.search = Items.searchBox
		DrawList(body, model.list)
		DrawCard(body, model.card, width)
		Items.body = body
	end,
})

-- The item menu's Where to buy and Price history (UI/ItemMenu.lua), the tooltip hints and old callers.
function ns.ShowItemLookup(itemID, focus)
	if not itemID then
		return false
	end
	Items.state.query = ""
	if Items.searchBox then
		Items.searchBox:SetText("")
	end
	Items.Select(itemID, focus)
	return M.Open("items")
end

-- /craftwise market <item> and /craftwise where <item> (Core.lua): Look up › Items on that item. An item ID
-- or link shows its card; a name goes into the search box (and shows the card when one item matches);
-- nothing opens the page as it was. focus = "history" (market) | "where".
function ns.OpenItemsFromSlash(arg, focus)
	arg = tostring(arg or ""):match("^%s*(.-)%s*$")
	local itemID = Items.QueryItemID(arg)
	if itemID then
		return ns.ShowItemLookup(itemID, focus)
	end
	if arg ~= "" then
		Items.state.query = arg
		if Items.searchBox then
			Items.searchBox:SetText(arg)
		end
		local found = Items.Search(arg)
		if #found == 1 then
			Items.Select(found[1], focus)
		end
	end
	return M.Open("items")
end

function ns.ShowWhereToBuy(itemID)
	return ns.ShowItemLookup(itemID, "where")
end

function ns.ShowMarketPrices(itemID)
	return ns.ShowItemLookup(itemID, "history")
end

-- Item names arrive later for items the client hasn't cached: one refresh per burst while the page shows.
local refreshQueued = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
	local f = M.Frame and M.Frame()
	local page = M.CurrentPage and M.CurrentPage()
	if refreshQueued or not (f and f:IsShown() and page and page.key == "items") then
		return
	end
	refreshQueued = true
	C_Timer.After(0.3, function()
		refreshQueued = false
		M.Refresh()
	end)
end)
