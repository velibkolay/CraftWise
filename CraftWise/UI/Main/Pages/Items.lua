-- Look up › Items (#157; spec in #150 "Look up, Music, Settings", board "Look up · Items"): one page for
-- every item's prices, where to buy it and where it is used. It merges Records › Market and Where to buy.
--   Sub bar tools: the search box (name, item ID or link; Shift-clicking an item while it has focus fills it).
--   Left list, 300 wide: chips Watched (only once #165 gives ns.ItemWatch), Your recipes (recorded items
--   in the market scope, Market.InScope), Recent (items looked up here); a search replaces the chip's list.
--   Row: name, listings note ("214 listed", "3 listed · thin", "vendor only"), typical price, 7-day change.
--   Right card: icon 40, name, class and stack, what you hold (Holdings), the Watched toggle (with #165);
--   Typical 3 days, Lowest now, On the AH, 7 days change; a chart of typical (solid) and lowest (dashed)
--   per day with the nokta on the latest point (Line objects; seven 4 unit day bars where the client has
--   no CreateLine); Used in (UsedIn); Where to buy (Merchant), vendor sell price, your last purchase.
--   Outside the market scope only the latest price is kept: "latest only" and no chart.
-- Prices are the profit house's (Settings › Prices). The item menu's Where to buy opens this page on the
-- item: ns.ShowItemLookup(itemID, "where" | "history"). Price history buttons show the site address instead
-- (ns.ShowPriceHistory, UI/ItemMenu.lua, #202); "history" here is the focus of /craftwise market.
-- Cost on open (#202): nothing walks all the market data per refresh. The recorded-key index lives in
-- Market.lua, the sorted "Your recipes" list and the search names are cached here (Cache) while
-- Market.DataVersion() stays the same, and a list row is priced when the scroll box first reads it
-- (LazyRow). The page's Refresh is a timed hook ("Look up › Items: Refresh") in Settings › Debug.
--
-- Prices per house (#350): the card's "Auction houses" section lists every house this character can use that
-- has a record of the item (the profit house first), with the lowest price, units, typical price and the age
-- of each, and for the other houses what buying there and selling at the profit house nets per unit (the
-- profit house's lowest x (1 - Market.MeasuredCut) - the other house's lowest; an unmeasured cut shows the
-- gross difference and says so; deposits are not counted, #26 phase 3). The chip "Cheaper elsewhere" lists
-- the items where that net is above zero, best first. Read only: it uses what scans already stored. The list
-- is built in slices like the cache above and kept while Market.DataVersion() and Market.HouseStamp() stay.
--
-- Watched hook for #165: ns.ItemWatch = { List() -> itemIDs, IsWatched(itemID) -> bool, Toggle(itemID) }.
-- Until it exists neither the chip nor the card's toggle shows.
--
-- Row data (Items.Row, Items.ListModel, Items.Card) is built apart from the drawing below, so the docked
-- layout (#161) can draw the same data its own way.
-- Provisional (#161 Q1), docked: the list across the sheet (chips in its header), and a click on an item
-- swaps to its card across the sheet, scrolling, with Back in the sub bar in place of the search box.
-- Items.state.dockedCard says which of the two shows (Items.Select shows the card, Back, a chip or a
-- search the list).
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
	if #Items.OtherHouses() > 0 then -- provisional (#350): Veli may drop it after trying it
		chips[#chips + 1] = { key = "elsewhere", label = L["Cheaper elsewhere"] }
	end
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
	Items.state.dockedCard = false
	M.Refresh()
end

-- Docked: back from the card to the list (provisional, #161 Q1).
function Items.Back()
	Items.state.dockedCard = false
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
	Items.state.dockedCard = true -- docked: the card shows (provisional, #161 Q1)
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
	Items.state.dockedCard = false
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
	return Items.Name(itemID) or M.Make.ItemName(itemID) -- never the raw id (#412)
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

-- Cache (#202). The market data holds tens of thousands of items, so nothing that walks all of them runs
-- inside a frame the player sees. The key index (Market.BuildIndexStep) and one pass over the recorded items
-- that gathers (a) the first Items.LIST_MAX of "Your recipes" by stored name and how many there are, and
-- (b) the lower-case stored names a search reads, are built in slices: each slice runs from a C_Timer.After(0)
-- until Items.SLICE_MS (or Items.SLICE_MAX items) is used, as a timed hook ("Look up › Items: build slice",
-- Settings › Debug). Until the first build is done the list says "Loading…"; a finished build refreshes the
-- page. It starts a short while after login (prebuild) or at the latest when the page is first refreshed, and
-- starts over when Market.DataVersion() (keys, scope, stored names) moves; the older result is used meanwhile.
-- Items.cacheBuilds counts the finished builds, for the specs.
Items.cacheBuilds = 0
Items.SLICE_MS = 4 -- time one slice may take
Items.SLICE_KEYS = 40 -- items handled between two looks at the clock
Items.SLICE_MAX = 800 -- and at most this many in a slice, whatever the clock says
Items.PREBUILD_DELAY = 20 -- seconds after login
-- A search looks at the client's name of at most this many recorded items without a stored name.
Items.UNNAMED_MAX = 300

local latest -- the last complete build: { version, top, topNames, count, lowerNames, unnamed }
local job -- the build in progress: { version, stage = "index" | "lists", ... }
local sliceQueued, starting = false, false

-- Name used to order and search the whole market data: the stored one (a table read), never a client call.
local function StoredLower(itemID)
	return (ns.Market.StoredName(itemID) or ""):lower()
end

local function NewJob()
	return { version = ns.Market.DataVersion(), stage = "index" }
end

-- `a` before `b` in "Your recipes": by stored name, then item ID.
local function Before(names, a, b)
	if names[a] ~= names[b] then
		return names[a] < names[b]
	end
	return a < b
end

-- Keeps the first Items.LIST_MAX items by name in c.top (sorted), c.topNames their names.
local function TopAdd(c, itemID, name)
	local top, names = c.top, c.topNames
	names[itemID] = name
	if #top >= Items.LIST_MAX and not Before(names, itemID, top[#top]) then
		names[itemID] = nil
		return
	end
	local lo, hi = 1, #top + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if Before(names, top[mid], itemID) then
			lo = mid + 1
		else
			hi = mid
		end
	end
	table.insert(top, lo, itemID)
	if #top > Items.LIST_MAX then
		names[table.remove(top)] = nil
	end
end

-- Does up to budgetMs (and maxItems items) of the build; true once it is complete (j.result). A false with
-- j.restart set says the table moved under the cursor: start over.
local function Work(j, budgetMs, maxItems)
	local Mk = ns.Market
	local started, handled = debugprofilestop(), 0
	local function room()
		return handled < maxItems and debugprofilestop() - started < budgetMs
	end
	if j.stage == "index" then
		repeat
			handled = handled + Items.SLICE_KEYS
			if Mk.BuildIndexStep(Items.SLICE_KEYS) then
				j.stage = "lists"
				j.byItem = Mk.RecordedItemIDs()
				j.c = { top = {}, topNames = {}, count = 0, lowerNames = {}, unnamed = {} }
			end
		until j.stage ~= "index" or not room()
		if j.stage == "index" then
			return false
		end
	end
	local c = j.c
	repeat
		for _ = 1, Items.SLICE_KEYS do
			local ok, itemID = pcall(next, j.byItem, j.cursor)
			if not ok then
				j.restart = true
				return false
			end
			if itemID == nil then
				c.version = j.version
				j.result = c
				return true
			end
			j.cursor = itemID
			local name = StoredLower(itemID)
			if name == "" then
				if #c.unnamed < Items.UNNAMED_MAX then
					c.unnamed[#c.unnamed + 1] = itemID
				end
			else
				c.lowerNames[itemID] = name
			end
			if Mk.InScope(itemID) then
				c.count = c.count + 1
				TopAdd(c, itemID, name)
			end
		end
		handled = handled + Items.SLICE_KEYS
	until not room()
	return false
end

local function PageShown()
	local f = M.Frame and M.Frame()
	local page = M.CurrentPage and M.CurrentPage()
	return f and f:IsShown() and page and page.key == "items" and true or false
end

local function Finish(j)
	latest = j.result
	Items.cacheBuilds = Items.cacheBuilds + 1
	job = nil
end

local Schedule
local Slice = ns.Timed("Look up › Items: build slice", function()
	sliceQueued = false
	if not job then
		return
	end
	if job.restart or job.version ~= ns.Market.DataVersion() then
		job = NewJob() -- the data moved: start over
	end
	if Work(job, Items.SLICE_MS, Items.SLICE_MAX) then
		Finish(job)
		if not starting and PageShown() then
			M.Refresh() -- the list was "Loading…" or older
		end
	else
		Schedule()
	end
end)

function Schedule()
	if not sliceQueued then
		sliceQueued = true
		C_Timer.After(0, Slice)
	end
end

-- Starts (or restarts) the build unless the cache is current. Returns true when it is.
function Items.Warm()
	local version = ns.Market.DataVersion()
	if latest and latest.version == version then
		return true
	end
	if not job or job.version ~= version then
		job = NewJob()
	end
	starting = true -- a stub that runs the timer at once finishes inside this call: nothing to refresh then
	Schedule()
	starting = false
	return latest ~= nil and latest.version == version
end

-- The whole build now, in this frame: for a typed command that needs the answer at once.
function Items.WarmNow()
	if latest and latest.version == ns.Market.DataVersion() then
		return
	end
	local j = NewJob()
	while not Work(j, math.huge, math.huge) do
		j = NewJob()
	end
	job = nil
	Finish(j)
end

-- The "Used in" index of UsedIn.lua walks every bundled recipe; the card needs it, so it is built in the
-- same kind of slices (Items.WarmUsedIn). True when it is ready; the card shows "Loading…" until then.
local usedInQueued, usedInStarting = false, false
local UsedInSlice
local function ScheduleUsedIn()
	if not usedInQueued then
		usedInQueued = true
		C_Timer.After(0, UsedInSlice)
	end
end
UsedInSlice = ns.Timed("Look up › Items: used-in slice", function()
	usedInQueued = false
	local started, done = debugprofilestop(), false
	repeat
		done = ns.UsedInStep(Items.SLICE_KEYS)
	until done or debugprofilestop() - started >= Items.SLICE_MS
	if not done then
		ScheduleUsedIn()
	elseif not usedInStarting and PageShown() then
		M.Refresh()
	end
end)

function Items.WarmUsedIn()
	if not ns.UsedInStep or ns.UsedInReady() then
		return true
	end
	usedInStarting = true
	ScheduleUsedIn()
	usedInStarting = false
	return ns.UsedInReady()
end

-- What the list and the search read: the current build, else the older one, nil before the first.
local function Cache()
	Items.Warm()
	return latest
end

-- A short while after login the build starts by itself, so it is ready before the page is first opened.
ns.On("PLAYER_LOGIN", function()
	C_Timer.NewTimer(Items.PREBUILD_DELAY, ns.Timed("Look up › Items: prebuild", function()
		Items.Warm()
		Items.WarmUsedIn()
	end))
end)

-- Recorded items whose lower-case stored name contains `lower`, then (up to Items.UNNAMED_MAX of the
-- items without a stored name) those the client names so. Returns ids and the matched set; nil while
-- the first build isn't done.
local function FindRecorded(lower)
	local c = Cache()
	if not c then
		return nil
	end
	local ids, seen = {}, {}
	for itemID, name in pairs(c.lowerNames) do
		if name:find(lower, 1, true) then
			seen[itemID] = true
			ids[#ids + 1] = itemID
		end
	end
	for _, itemID in ipairs(c.unnamed) do
		local name = Items.Name(itemID)
		if name and name:lower():find(lower, 1, true) then
			seen[itemID] = true
			ids[#ids + 1] = itemID
		end
	end
	return ids, seen
end

-- Items a search finds: the item of an ID or link; else recorded items (AH or merchants) whose name
-- contains the text, exact names first. Returns itemIDs and how many more matched than Items.LIST_MAX; nil
-- while the first build of the cache isn't done (Items.WarmNow waits for it).
function Items.Search(query)
	query = tostring(query or ""):match("^%s*(.-)%s*$")
	if query == "" then
		return {}, 0
	end
	local wanted = Items.QueryItemID(query)
	if wanted then
		return { wanted }, 0
	end
	local lower = query:lower()
	local ids, seen = FindRecorded(lower)
	if not ids then
		return nil
	end
	for _, itemID in ipairs((ns.Merchant.FindItems(query))) do
		if not seen[itemID] then
			seen[itemID] = true
			ids[#ids + 1] = itemID
		end
	end
	local stored, names = latest and latest.lowerNames or {}, {}
	for _, id in ipairs(ids) do
		names[id] = stored[id] or DisplayName(id):lower()
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
	-- Your recipes: the first Items.LIST_MAX recorded items of the market scope by stored name, from the
	-- cache; nil while the first build isn't done.
	local c = Cache()
	if not c then
		return nil
	end
	local out = {}
	for i, id in ipairs(c.top) do
		out[i] = id
	end
	return out, math.max(0, c.count - Items.LIST_MAX)
end

-- The market key used for an item at the profit house: the plain ID, else its first suffix variant.
function Items.Key(itemID)
	local keys = ns.Market.ItemKeys(itemID, true) -- nil while the index is still being built: the plain ID
	if not keys then
		return itemID, {}
	end
	return keys[1] or itemID, keys
end

----------------------------------------------------------------------------------------------------
-- Prices per auction house (#350)
----------------------------------------------------------------------------------------------------

-- The houses other than the profit house that this character can use and has recorded something at:
-- { { key, label } }, own faction house first, then the neutral houses of the realm.
function Items.OtherHouses()
	local Mk = ns.Market
	local profit = ns.ProfitHouse()
	local out = {}
	if not profit then
		return out
	end
	for _, choice in ipairs(Mk.CHOICES) do
		local key, label = Mk.HouseFor(choice)
		if key and key ~= profit and Mk.HasData(key) then
			out[#out + 1] = { key = key, label = Mk.HouseLabel(key) or label }
		end
	end
	return out
end

-- What buying at another house and selling at the profit house leaves per unit: { copper, measured, cut }.
-- The cut is the profit house's measured cut (Market.MeasuredCut); without one it is the gross difference
-- (measured = false). Never a constant. nil without both prices.
function Items.Spread(sellMin, buyMin, cut)
	if not (sellMin and buyMin) then
		return nil
	end
	if cut then
		return { copper = math.floor(sellMin * (1 - cut) + 1e-7) - buyMin, measured = true, cut = cut }
	end
	return { copper = sellMin - buyMin, measured = false }
end

local function Signed(copper)
	if copper < 0 then
		return "−" .. ns.FormatCoins(-copper)
	end
	return "+" .. ns.FormatCoins(copper)
end

local function PercentText(cut)
	return ("%g %%"):format(math.floor(cut * 1000 + 0.5) / 10)
end

-- " · via Velikopter Kitchenchant" for a price another of your characters scanned (#356), else nothing.
local function Via(houseKey, t)
	local who = ns.Market.SyncedVia and ns.Market.SyncedVia(houseKey, t)
	return who and (" · " .. L["via"] .. " " .. who) or ""
end

local function AgeAgo(seconds)
	return M.AgeText(math.max(0, seconds)) .. " " .. L["ago"]
end

-- The card's "Auction houses" section: nil unless a house other than the profit house has a record of the
-- item. { title, rows = { { key, label, profit, lowest, qty, t, typical, diff } }, lines (for the block),
-- tip }. diff: { copper, measured, cut } or { none = "profit unlisted" }, only on other houses that list it.
function Items.HouseSection(p, now)
	local Mk = ns.Market
	if not p.house then
		return nil
	end
	local others = {}
	for _, h in ipairs(Mk.UsableHouses(p.key)) do
		if h.key ~= p.house then
			others[#others + 1] = h
		end
	end
	if #others == 0 then
		return nil
	end
	local list = { { key = p.house, label = p.houseLabel or Mk.HouseLabel(p.house), profit = true } }
	for _, h in ipairs(others) do
		list[#list + 1] = h
	end
	local cut = Mk.MeasuredCut(p.house)
	local sellMin = p.current and p.current.listed and p.current.min or nil
	local sec = { title = L["Auction houses"], rows = {}, lines = {} }
	for _, h in ipairs(list) do
		local cur = h.profit and p.current or Mk.Current(p.key, h.key)
		local typ = Mk.Typical(p.key, h.key)
		local row = { key = h.key, label = h.label, profit = h.profit, t = cur and cur.t,
			lowest = cur and cur.listed and cur.min or nil, qty = cur and cur.listed and cur.qty or nil,
			typical = typ.status == "ok" and typ.price or nil }
		local parts = {}
		if cur and cur.listed then
			parts[#parts + 1] = (L["%d listed"]):format(cur.qty or 0)
		elseif cur then
			parts[#parts + 1] = L["not listed in the last full scan"]
		else
			parts[#parts + 1] = L["no price recorded"]
		end
		if cur then
			parts[#parts + 1] = (L["seen %s"]):format(AgeAgo(now - cur.t))
		end
		if row.typical then
			parts[#parts + 1] = L["typical"] .. " " .. ns.FormatCoins(row.typical)
		end
		sec.lines[#sec.lines + 1] = { left = h.label .. (h.profit and (" · " .. L["profit house"]) or ""),
			right = row.lowest and ns.FormatCoins(row.lowest) or M.NoPriceText(), rightColor = not row.lowest and "text3" or nil }
		sec.lines[#sec.lines + 1] = { left = table.concat(parts, " · "), leftColor = "text3", small = true }
		if not h.profit and row.lowest then
			local sellAge = p.current and (" (" .. (L["seen %s"]):format(AgeAgo(now - p.current.t)) .. ")") or ""
			if not sellMin then
				row.diff = { none = true }
				sec.lines[#sec.lines + 1] = { left = (L["Not listed at %s: nothing to sell against."]):format(p.houseLabel) .. sellAge,
					leftColor = "text3", small = true }
			else
				local sp = Items.Spread(sellMin, row.lowest, cut)
				row.diff = sp
				local left, right
				if sp.measured then
					left = (L["Buy here, sell at %s%s, after the %s cut"]):format(p.houseLabel, sellAge, PercentText(sp.cut))
					right = Signed(sp.copper)
				else
					left = (L["Buy here, sell at %s%s: cut not measured"]):format(p.houseLabel, sellAge)
					right = Signed(sp.copper) .. " " .. L["gross"]
				end
				sec.lines[#sec.lines + 1] = { left = left, leftColor = "text2", small = true, right = right,
					rightColor = sp.copper > 0 and "nokta" or "text3" }
			end
		end
		sec.rows[#sec.rows + 1] = row
	end
	sec.tip = {
		L["Auction houses"],
		L["Read from the scans already stored: no auction house is queried."],
		L["Net = lowest at the profit house x (1 - its measured cut) - lowest here, per unit."],
		L["Without a measured cut the difference is gross and says so."],
		L["The scans are from different times: each price shows its age."],
		L["Deposits are not counted yet (#26 phase 3)."],
	}
	return sec
end

-- "Cheaper elsewhere" (#350): items whose lowest price at another house is below what the profit house
-- pays after its cut. Built in slices (like the cache above) over the recorded-key index, kept while
-- Market.DataVersion() and Market.HouseStamp() stay (the first only moves with keys, the second with every
-- scan): { stamp, rows = { { itemID, key, buyHouse, buyLabel, buyMin, buyQty, buyT, sellMin, sellT, copper,
-- measured, cut } } } by net, best first. Items.elseBuilds counts the finished builds, for the specs.
Items.elseBuilds = 0
local eLatest, eJob
local eQueued, eStarting = false, false

local function ElseStamp()
	local Mk = ns.Market
	local house = ns.ProfitHouse()
	return table.concat({ Mk.DataVersion(), Mk.HouseStamp(), tostring(house), tostring(house and Mk.MeasuredCut(house) or "-") }, "|")
end

local function ElseNewJob()
	local house = ns.ProfitHouse()
	return { stamp = ElseStamp(), stage = "index", house = house, others = Items.OtherHouses(), rows = {},
		cut = house and ns.Market.MeasuredCut(house) or nil }
end

local function ElseItem(j, itemID)
	local Mk = ns.Market
	local key = (j.byItem[itemID] or {})[1] or itemID
	if not Mk.RecordedAt(key, j.house) then
		return
	end
	local sell
	local best
	for _, h in ipairs(j.others) do
		if Mk.RecordedAt(key, h.key) then
			if sell == nil then
				local cur = Mk.Current(key, j.house)
				sell = cur and cur.listed and cur.min and cur or false
			end
			if not sell then
				return
			end
			local cur = Mk.Current(key, h.key)
			if cur and cur.listed and cur.min then
				local sp = Items.Spread(sell.min, cur.min, j.cut)
				if sp.copper > 0 and (not best or sp.copper > best.copper) then
					best = { itemID = itemID, key = key, buyHouse = h.key, buyLabel = h.label, buyMin = cur.min,
						buyQty = cur.qty, buyT = cur.t, sellMin = sell.min, sellT = sell.t, copper = sp.copper,
						measured = sp.measured, cut = sp.cut }
				end
			end
		end
	end
	if best then
		j.rows[#j.rows + 1] = best
	end
end

local function ElseFinish(j)
	table.sort(j.rows, function(a, b)
		if a.copper ~= b.copper then
			return a.copper > b.copper
		end
		return a.itemID < b.itemID
	end)
	j.result = { stamp = j.stamp, rows = j.rows }
end

-- Does up to budgetMs (and maxItems items) of the build; true once it is complete (j.result). A false with
-- j.restart set says the table moved under the cursor: start over.
local function ElseWork(j, budgetMs, maxItems)
	local Mk = ns.Market
	local started, handled = debugprofilestop(), 0
	local function room()
		return handled < maxItems and debugprofilestop() - started < budgetMs
	end
	if j.stage == "index" then
		repeat
			handled = handled + Items.SLICE_KEYS
			if Mk.BuildIndexStep(Items.SLICE_KEYS) then
				j.stage = "walk"
				j.byItem = Mk.RecordedItemIDs()
			end
		until j.stage ~= "index" or not room()
		if j.stage == "index" then
			return false
		end
	end
	if not j.house or #j.others == 0 then
		ElseFinish(j)
		return true
	end
	repeat
		for _ = 1, Items.SLICE_KEYS do
			local ok, itemID = pcall(next, j.byItem, j.cursor)
			if not ok then
				j.restart = true
				return false
			end
			if itemID == nil then
				ElseFinish(j)
				return true
			end
			j.cursor = itemID
			ElseItem(j, itemID)
		end
		handled = handled + Items.SLICE_KEYS
	until not room()
	return false
end

local ElseSchedule
local ElseSlice = ns.Timed("Look up › Items: elsewhere slice", function()
	eQueued = false
	if not eJob then
		return
	end
	if eJob.restart or eJob.stamp ~= ElseStamp() then
		eJob = ElseNewJob() -- the data moved: start over
	end
	if ElseWork(eJob, Items.SLICE_MS, Items.SLICE_MAX) then
		eLatest = eJob.result
		eJob = nil
		Items.elseBuilds = Items.elseBuilds + 1
		if not eStarting and PageShown() then
			M.Refresh()
		end
	else
		ElseSchedule()
	end
end)

function ElseSchedule()
	if not eQueued then
		eQueued = true
		C_Timer.After(0, ElseSlice)
	end
end

-- Starts (or restarts) the build unless the list is current. Returns true when it is.
function Items.ElseWarm()
	local stamp = ElseStamp()
	if eLatest and eLatest.stamp == stamp then
		return true
	end
	if not eJob or eJob.stamp ~= stamp then
		eJob = ElseNewJob()
	end
	eStarting = true
	ElseSchedule()
	eStarting = false
	return eLatest ~= nil and eLatest.stamp == stamp
end

-- The whole build now, in this frame (the specs).
function Items.ElseWarmNow()
	if Items.ElseWarm() then
		return
	end
	local j = eJob or ElseNewJob()
	while not ElseWork(j, math.huge, math.huge) do
		j = ElseNewJob()
	end
	eJob = nil
	eLatest = j.result
	Items.elseBuilds = Items.elseBuilds + 1
end

-- The list's rows: the current list, else the older one, nil before the first.
function Items.ElseItems()
	Items.ElseWarm()
	return eLatest and eLatest.rows or nil
end

-- One row of the "Cheaper elsewhere" list, in the shape of the other rows plus a tip.
function Items.ElseRow(e, now)
	local info = ns.Market.ItemInfo(e.itemID) or {}
	local sellLabel = ns.ProfitHouse() and ns.Market.HouseLabel((ns.ProfitHouse())) or L["the auction house"]
	local buyAge, sellAge = AgeAgo(now - e.buyT), AgeAgo(now - e.sellT)
	local tip = {
		DisplayName(e.itemID),
		(L["Buy at %s: %s, %d listed, seen %s"]):format(e.buyLabel, ns.FormatMoney(e.buyMin, true), e.buyQty or 0, buyAge),
		(L["Sell at %s: %s, seen %s"]):format(sellLabel, ns.FormatMoney(e.sellMin, true), sellAge),
		e.measured and (L["Net per unit after the %s cut: %s"]):format(PercentText(e.cut), Signed(e.copper))
			or (L["Cut not measured: gross %s per unit"]):format(Signed(e.copper)),
		L["Deposits are not counted yet (#26 phase 3)."],
	}
	return { key = e.itemID, itemID = e.itemID, name = DisplayName(e.itemID), quality = info.q, icon = info.i,
		note = ("%s %s ×%d · %s"):format(e.buyLabel, ns.FormatCoins(e.buyMin), e.buyQty or 0, M.AgeText(math.max(0, now - e.buyT))),
		priceText = Signed(e.copper) .. (e.measured and "" or "*"), net = e.copper,
		changeText = ("%s %s · %s"):format(sellLabel, ns.FormatCoins(e.sellMin), M.AgeText(math.max(0, now - e.sellT))),
		changeColor = "text3", tip = tip, elsewhere = e }
end

-- The left list on the "Cheaper elsewhere" chip; same shape as ListModel's.
function Items.ElseModel(now, chip)
	local items = Items.ElseItems()
	local chips = Items.Chips()
	if not items then
		return { rows = {}, empty = L["Loading…"], more = 0, chips = chips, chip = chip, searching = false, loading = true }
	end
	local rows = {}
	for i = 1, math.min(#items, Items.LIST_MAX) do
		rows[i] = Items.ElseRow(items[i], now)
	end
	return { rows = rows, more = math.max(0, #items - Items.LIST_MAX), chips = chips, chip = chip, searching = false,
		empty = (L["Nothing is cheaper at another house than the net price at %s. Scan another auction house."])
			:format(ns.ProfitHouse() and ns.Market.HouseLabel((ns.ProfitHouse())) or L["the auction house"]) }
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

-- A row whose figures are worked out when first read: the list holds up to Items.LIST_MAX rows but the
-- scroll box draws a dozen, so opening the page prices only those (#202). itemID and key are set at once.
local LazyRow = {
	__index = function(row, k)
		setmetatable(row, nil)
		local now = row.priceNow
		row.priceNow = nil
		for field, v in pairs(Items.Row(row.itemID, now)) do
			rawset(row, field, v)
		end
		return rawget(row, k)
	end,
}

function Items.LazyRow(itemID, now)
	return setmetatable({ key = itemID, itemID = itemID, priceNow = now }, LazyRow)
end

-- The left list: { rows, empty, more, chips, chip, searching, loading }; loading while the first build of the
-- cache isn't done (empty then says so).
function Items.ListModel(now)
	local query = Items.state.query or ""
	local searching = query:match("%S") ~= nil
	local chip = Items.Chip()
	Items.Warm() -- the page needs the key index, whichever chip shows
	if chip == "elsewhere" and not searching then
		return Items.ElseModel(now, chip)
	end
	local ids, more
	if searching then
		ids, more = Items.Search(query)
	else
		ids, more = Items.ChipItems(chip)
	end
	if not ids then
		return { rows = {}, empty = L["Loading…"], more = 0, chips = Items.Chips(), chip = chip, searching = searching,
			loading = true }
	end
	local rows = {}
	for i, id in ipairs(ids) do
		rows[i] = Items.LazyRow(id, now)
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

----------------------------------------------------------------------------------------------------
-- Used in (#351): every recipe that takes the item, with its profit and, for one you don't know, the recipe's
-- cost. The profit is Make › Craft's own: the rows come from ns.BuildRows (view "profit", the profit house),
-- never a second calculation. Built once per item and kept while prices, settings and recipes stay the same.
----------------------------------------------------------------------------------------------------

Items.USED_ROWS = 6 -- recipe rows shown; the rest sit behind "and N more · Show all"
Items.USED_TTL = 30 -- seconds a built block is kept; ledger and bag changes move the paid basis
local usedCache = {}
ns.Listen("RECIPES_CHANGED", function()
	usedCache = {}
end)

local function UsedStamp()
	local s = ns.db and ns.db.settings or {}
	local basis, house = ns.PriceSettings()
	return table.concat({ ns.Market.DataVersion and ns.Market.DataVersion() or 0, basis, house,
		ns.CostBasis("profit"), s.priceBasis or "", math.floor(time() / Items.USED_TTL) }, "|")
end

-- The rows Make › Craft builds for the recipes of my professions that use the item: { [recipeID] = row }.
local function UsedMakeRows(entries)
	local want = {}
	for _, e in ipairs(entries) do
		if e.professionID then
			want[e.professionID] = want[e.professionID] or {}
			want[e.professionID][e.recipeID] = true
		end
	end
	local byRecipe = {}
	for professionID, only in pairs(want) do
		for _, row in ipairs(ns.BuildRows(professionID, true, "profit", only)) do
			byRecipe[row.recipeID] = row
		end
	end
	return byRecipe
end

-- "Sell: 2s 15c each (AH)": what one unit of the item brings, after the house's cut (ns.GetSellValue).
local function SellLine(itemID)
	local v = ns.GetSellValue(itemID)
	local line = { left = L["Sell"] .. ": " .. L["no price"], leftColor = "text2" }
	if not v then
		line.tip = { L["Sell"], L["No AH price and no vendor price."] }
		return line
	end
	local copper = math.floor(v.copper)
	if v.source == "vendor" then
		line.left = ("%s: %s %s (%s)"):format(L["Sell"], ns.FormatCoins(copper), L["each"], L["vendor"])
		line.tip = { L["Sell"], L["Sold to a vendor."] }
	else
		local how = v.cutUnverified and L["AH, cut unverified"] or L["AH, after cut"]
		line.left = ("%s: %s %s (%s)"):format(L["Sell"], ns.FormatCoins(copper), L["each"], how)
		line.tip = { L["Sell"], v.label or "", v.cutText or "", v.age and (L["%d days old"]):format(v.age) or nil }
		line.tip = Lines(line.tip)
	end
	return line
end

-- "recipe 50s (AH, typical · Horde AH, 2d)" | "recipe source unknown" for a recipe you don't know.
local function RecipeCostText(r)
	if r.learnCost then
		local how = r.learnSource == "vendor" and L["vendor"] or r.learnSource == "auction" and L["AH"] or L["trainer"]
		local detail = how
		if r.learnSource == "auction" then
			local data = ns.Sources and ns.Sources.Merged and ns.Sources.Merged(r.recipeID)
			local quote = data and data.item and ns.AuctionQuote(data.item)
			detail = how .. (r.learnLabel and (", " .. r.learnLabel) or "")
				.. (quote and quote.age and (", " .. (quote.age == 0 and L["today"] or (L["%d days old"]):format(quote.age))) or "")
		end
		return (L["recipe %s (%s)"]):format(ns.FormatCoins(r.learnCost), detail)
	end
	local where = ns.RecipeWhere and ns.RecipeWhere(r.recipeID) or {}
	return #where > 0 and L["recipe price unknown"] or L["recipe source unknown"]
end

local function UsedHouseLabel()
	local _, label = ns.ProfitHouse()
	return label
end

-- One recipe row. r = the Make row (nil: my profession's recipe without a row, or another profession).
local function UsedRecipeLine(e, r, houseLabel)
	local line = { left = e.name, right = "×" .. (e.quantity or 1), rightColor = "text2", recipe = e }
	if e.state == "other" then
		line.mid, line.midColor, line.leftColor = e.profession, "text3", "text3"
		line.tip = { e.name, e.profession, (L["Uses %d"]):format(e.quantity or 1) }
		return line
	end
	line.action = { kind = "recipe", entry = e }
	line.makeRow = r
	if r and r.profit ~= nil then
		line.mid, line.midColor = M.Make.Signed(r.profit)
		line.profit = r.profit
	else
		line.mid, line.midColor = L["no price"], "text3"
		local why = r and M.Make.WhyNoPrice(r, { prices = { label = houseLabel } })
		line.why = why and why[2] or nil
	end
	local sub = {}
	if e.state == "learnable" then
		local skill = e.required and ((L["skill %d"]):format(e.required)) or nil
		if skill then
			sub[#sub + 1] = e.tooLow and (Style.Hex("danger") .. skill .. "|r") or skill
		end
		sub[#sub + 1] = r and RecipeCostText(r) or L["recipe source unknown"]
	elseif line.why and r and not r.costComplete then
		local names = {}
		for _, id in ipairs(r.missing or {}) do
			names[#names + 1] = M.Make.ItemName(id)
		end
		sub[#sub + 1] = (L["no price: %s"]):format(table.concat(names, ", "))
	elseif line.why then
		sub[#sub + 1] = line.why
	else
		sub[#sub + 1] = L["profit per craft"]
	end
	line.sub = table.concat(sub, " · ")
	return line
end

-- The block: { lines, more } (pure; Items.Card turns it into the rows). Cached per item.
function Items.UsedModel(itemID)
	local stamp = UsedStamp()
	local cached = usedCache[itemID]
	if cached and cached.stamp == stamp then
		return cached.model
	end
	local lines = {}
	local entries = ns.UsedIn and ns.UsedIn(itemID) or {}
	local summary = ns.UsedInSummary and ns.UsedInSummary(itemID) or {}
	if #entries == 0 then
		lines[1] = { left = L["No recipe uses it."], leftColor = "text2" }
	else
		lines[#lines + 1] = SellLine(itemID)
		for i, g in ipairs(summary) do
			if i > 2 then
				break
			end
			lines[#lines + 1] = { left = g.profession, right = g.mine and (L["%d recipes · %d known"]):format(g.count, g.known)
				or (L["%d recipes"]):format(g.count) }
		end
		local houseLabel = UsedHouseLabel()
		local rows = UsedMakeRows(entries)
		local list = {}
		for i, e in ipairs(entries) do
			list[i] = { e = e, i = i, r = rows[e.recipeID] }
		end
		-- known, then learnable, then other professions (the order of ns.UsedIn); inside the first two the
		-- better profit per craft first, a recipe without a profit last
		local ORDER = { known = 1, learnable = 2, other = 3 }
		table.sort(list, function(a, b)
			if a.e.state ~= b.e.state then
				return ORDER[a.e.state] < ORDER[b.e.state]
			end
			if a.e.state ~= "other" then
				local pa, pb = a.r and a.r.profit, b.r and b.r.profit
				if pa ~= pb and (pa or pb) then
					if pa == nil or pb == nil then
						return pa ~= nil
					end
					return pa > pb
				end
			end
			return a.i < b.i
		end)
		for i, item in ipairs(list) do
			if i > Items.USED_ROWS then
				lines[#lines + 1] = { left = (L["and %d more"]):format(#list - Items.USED_ROWS) .. " · " .. L["Show all"],
					leftColor = "text2", action = { kind = "all" },
					tip = { L["Recipes using this"], L["Opens Make › Craft with every recipe that uses it."] } }
				break
			end
			lines[#lines + 1] = UsedRecipeLine(item.e, item.r, houseLabel)
		end
	end
	local model = { lines = lines }
	usedCache[itemID] = { stamp = stamp, model = model }
	return model
end

-- A click on a row of the block: Make › Craft on that recipe (my profession), or on every recipe using the item.
function Items.UsedClick(itemID, action)
	if not action then
		return false
	end
	local e = action.kind == "recipe" and action.entry
	local MK = M.Make
	if not (e and e.professionID and MK and MK.state) or tostring(e.name):find("^Recipe #") then
		return ns.ShowRecipesUsing(itemID)
	end
	ns.db.settings.includeUnlearned = true
	M.UI().profession = e.professionID
	MK.state.query = e.name
	M.Open("craft")
	return true
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
		fig.typical = { text = Style.Hex("text3") .. L["latest only"] .. "|r", tip = { L["Typical, 3 days"], L["Outside the market scope only the latest price is kept."] } }
	elseif typical and typical.status == "ok" then
		fig.typical = { text = ns.FormatCoins(typical.price), tip = { L["Typical, 3 days"], (L["Median of %d days at %s."]):format(typical.days, houseLine) } }
	elseif typical and typical.status == Mk.TOO_LITTLE_HISTORY then
		fig.typical = { text = M.NoPriceText(), tip = { L["Typical, 3 days"], (L["Too little history: %d of %d days."]):format(typical.days, Mk.MIN_HISTORY_DAYS) } }
	else
		fig.typical = { text = M.NoPriceText(), tip = { L["Typical, 3 days"], (L["Nothing recorded at %s."]):format(houseLine) } }
	end
	local cur = p.current
	if cur and cur.listed then
		local tip = { L["Lowest now"], (L["Seen %s ago at %s."]):format(M.AgeText(now - cur.t), houseLine) .. Via(p.house, cur.t) }
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
			(L["Last seen at %s, %s ago."]):format(ns.FormatMoney(cur.min, true), M.AgeText(now - cur.t)) .. Via(p.house, cur.t) } }
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
	-- Other houses have their own section below (#350); Auctionator stays on the Typical tip.
	local exported = Mk.AuctionatorExport and Mk.AuctionatorExport(itemID)
	if exported then
		table.insert(fig.typical.tip, ("%s: %s, %s %s"):format(ns.AUCTIONATOR_LABEL, ns.FormatMoney(exported.copper, true),
			M.AgeText(now - exported.t), L["ago"]))
	end
	card.figures = fig
	card.houses = Items.HouseSection(p, now)

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
	local usedReady = Items.WarmUsedIn()
	card.usedIn = usedReady and ns.UsedIn and Items.UsedModel(itemID).lines
		or { { left = L["Loading…"], leftColor = "text2" } }

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
local KV_ROW, KV_ROW_SUB, KV_QTY_W = 20, 34, 34

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
		if self.row and self.row.tip then
			Style.ShowTip(self, unpack(self.row.tip))
		elseif self.row then
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
	b.name:SetWidth(Items.rowNameWidth or 150)
	b.note:SetWidth(Items.rowNameWidth or 150)
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
	local x, y, rows = 16, 10, 1
	local avail = (left.GetWidth and left:GetWidth() or 0) > 0 and left:GetWidth() or Items.LIST_WIDTH
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
		-- a chip that doesn't fit in the row goes on the next one (provisional, #350: four chips)
		if x > 16 and x + (b.cwWidth or 80) > avail - 12 then
			x, y, rows = 16, y + 32, rows + 1
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", left, "TOPLEFT", x, -y)
		b:Show()
		x = x + (b.cwWidth or 80) + 6
	end
	left.box:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -(12 + 32 * rows))
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
	-- Lines: { left, right, mid, sub, leftColor, rightColor, midColor, tip, makeRow, action }. Returns the height
	-- of the rows (a line with a sub caption is taller). mid sits left of right; a line with an action is a click.
	-- leftWidth: a fixed width for the left text (the Auction houses block); onClick(action) answers a click.
	function blk:Set(lines, leftWidth, onClick)
		local y = 22
		for i, line in ipairs(lines) do
			local r = self.rows[i]
			if not r then
				r = CreateFrame("Button", nil, self)
				r:RegisterForClicks("LeftButtonUp")
				r.right = Style.Text(r, "Figure", "text")
				r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -3)
				r.right:SetJustifyH("RIGHT")
				r.mid = Style.Text(r, "Figure", "text")
				r.mid:SetJustifyH("RIGHT")
				r.mid:SetWordWrap(false)
				r.left = Style.Text(r, "Small", "text")
				r.left:SetJustifyH("LEFT")
				r.left:SetWordWrap(false)
				r.sub = Style.Text(r, "Caption", "text3")
				r.sub:SetJustifyH("LEFT")
				r.sub:SetWordWrap(false)
				r.hair = Style.Rule(r, "H", C.rule)
				r.hair:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
				r.hair:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
				r:SetScript("OnEnter", function(row)
					local l = row.line
					if l and l.makeRow and M.Make and M.Make.ShowRecipeTooltip then
						M.Make.ShowRecipeTooltip(row, l.makeRow, "profit")
					elseif l and l.tip and l.tip[1] then
						Style.ShowTip(row, unpack(l.tip))
					end
				end)
				r:SetScript("OnLeave", function(row)
					HideTips(row)
				end)
				r:SetScript("OnClick", function(row)
					if row.line and row.line.action and onClick then
						onClick(row.line.action)
					end
				end)
				self.rows[i] = r
			end
			r.line = line
			local h = line.sub and KV_ROW_SUB or KV_ROW
			r:SetHeight(h)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
			r:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
			r.right:SetText(line.right or "")
			SetColor(r.right, line.rightColor or "text")
			r.mid:ClearAllPoints()
			r.mid:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(KV_QTY_W), -3)
			r.mid:SetText(line.mid or "")
			SetColor(r.mid, line.midColor or "text")
			r.left:ClearAllPoints()
			r.left:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -3)
			if leftWidth then
				r.left:SetWidth(leftWidth)
			else
				r.left:SetPoint("RIGHT", line.mid and r.mid or r.right, "LEFT", -8, 0)
			end
			r.left:SetText(line.left or "")
			SetColor(r.left, line.leftColor or "text")
			r.sub:ClearAllPoints()
			r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -17)
			r.sub:SetPoint("RIGHT", r, "RIGHT", 0, 0)
			r.sub:SetText(line.sub or "")
			r.sub:SetShown(line.sub ~= nil)
			r:EnableMouse(line.action ~= nil or line.tip ~= nil or line.makeRow ~= nil)
			r:Show()
			y = y + h
		end
		for i = #lines + 1, #self.rows do
			self.rows[i]:Hide()
			self.rows[i].line = nil
		end
		self.lines = lines
		return y
	end
	return blk
end

local FIGURES = {
	{ key = "typical", label = "Typical, 3 days", font = "FigureL" },
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

	-- Auction houses (#350): one block under the other two, over the full width.
	card.houses = KVBlock(card, L["Auction houses"])
	card.housesHit = TipArea(card.houses, function()
		local sec = card.data and card.data.houses
		return sec and sec.tip
	end)
	card.housesHit:SetPoint("TOPLEFT", card.houses, "TOPLEFT", 0, 0)
	card.housesHit:SetPoint("TOPRIGHT", card.houses, "TOPRIGHT", 0, 0)
	card.housesHit:SetHeight(18)

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

local function DrawCard(body, data, width, docked)
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
	card.houses:SetShown(shown and data.houses ~= nil)
	card.housesHit:SetShown(shown and data.houses ~= nil)
	if not shown then
		card.contentHeight = 0
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
	-- Figures: four in a row; docked two by two.
	local perRow = docked and 2 or 4
	local colW = (width - (perRow - 1) * FIG_GAP) / perRow
	for i, f in ipairs(card.figs) do
		local fig = data.figures[f.key]
		local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X + col * (colW + FIG_GAP), -(FIG_TOP + row * (44 + 8)))
		f:SetWidth(colW)
		f.value:SetText(fig and fig.text or "")
	end
	local chartTop = FIG_TOP + math.ceil(#card.figs / perRow) * (44 + 8) + 4
	card.chart:ClearAllPoints()
	card.chart:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -chartTop)
	card.chart:SetWidth(width)
	card.chart.note:ClearAllPoints()
	card.chart.note:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -chartTop)
	card.chart.note:SetWidth(width)
	DrawChart(card, data.chart, width)
	local blockTop = chartTop + (data.chart and data.chart.mode == "chart" and (Items.CHART_HEIGHT + 22) or 36)
	local half = docked and width or (width - 20) / 2 -- docked: Used in over Where to buy
	card.used:ClearAllPoints()
	card.used:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -blockTop)
	card.used:SetSize(half, 22 + 5 * KV_ROW)
	local usedH = card.used:Set(data.usedIn, nil, function(action)
		Items.UsedClick(card.itemID, action)
	end)
	card.used:SetHeight(math.max(usedH, 22 + 5 * KV_ROW))
	local blockH = 22 + 5 * KV_ROW
	local usedBlockH = math.max(usedH, blockH)
	card.where:ClearAllPoints()
	if docked then
		card.where:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -(blockTop + usedBlockH + 12))
	else
		card.where:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X + half + 20, -blockTop)
	end
	card.where:SetSize(half, blockH)
	card.where:Set(data.where)
	-- the card's whole height (what the scroll holds), with the Auction houses block under the other two
	local bottom = docked and (blockTop + usedBlockH + 12 + blockH) or (blockTop + math.max(usedBlockH, blockH))
	if data.houses then
		local housesH = 22 + #data.houses.lines * KV_ROW
		card.houses:ClearAllPoints()
		card.houses:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD_X, -(bottom + 14))
		card.houses:SetSize(width, housesH)
		card.houses:Set(data.houses.lines, width - 150)
		bottom = bottom + 14 + housesH
	end
	card.contentHeight = bottom + CARD_PAD_Y
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
		-- Docked: Back from the card to the list, in place of the search box (provisional, #161 Q1).
		slot.back = Style.LineButton(slot, L["Back"], nil, 26)
		slot.back:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		slot.back:SetScript("OnClick", function()
			Items.Back()
		end)
		slot.back:Hide()
	end,
	UpdateTools = function(slot, ctx)
		local box = Items.searchBox
		if box and (box:GetText() or "") ~= Items.state.query then
			box:SetText(Items.state.query)
		end
		local docked = M.IsDocked(ctx)
		local card = Items.DockedShowsCard(ctx)
		box:SetWidth(docked and Items.DOCKED_SEARCH_WIDTH or 300)
		box:SetShown(not card)
		slot.back:SetShown(card)
	end,
	Build = function(body)
		BuildList(body)
		BuildCard(body)
		body.search = Items.searchBox
	end,
	Refresh = ns.Timed("Look up › Items: Refresh", function(body, ctx)
		local model = Items.Model()
		Items.lastModel = model
		body.search = Items.searchBox
		Items.body = body
		if M.IsDocked(ctx) then
			return Items.DockedRefresh(body, ctx, model)
		end
		-- Window: the list left, the card right (put back after a docked draw).
		local width = (ctx and ctx.metrics and ctx.metrics.width or 880) - Items.LIST_WIDTH - 1 - 2 * CARD_PAD_X
		local left, card = body.left, body.card
		left:SetWidth(Items.LIST_WIDTH)
		left.empty:SetWidth(Items.LIST_WIDTH - 32)
		left.rule:Show()
		left:Show()
		-- The card scrolls like the docked one: the Auction houses section can make it taller than the window.
		if not body.dscroll then
			body.dscroll = M.Docked.Scroll(body)
		end
		local scroll = body.dscroll
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", body, "TOPLEFT", Items.LIST_WIDTH + 1, 0)
		scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
		local cardWidth = width + 2 * CARD_PAD_X
		card:SetParent(scroll.child)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, 0)
		card:SetWidth(cardWidth)
		scroll.child:SetWidth(cardWidth)
		scroll:Show()
		card:Show()
		Items.rowNameWidth = nil
		DrawList(body, model.list)
		DrawCard(body, model.card, width)
		local h = math.max(card.contentHeight or 0, 1)
		card:SetHeight(h)
		scroll:SetContentHeight(h)
	end),
})

----------------------------------------------------------------------------------------------------
-- Provisional (#161 Q1): the docked Items page. The list across the sheet, or the card across it in a
-- scroll, never both.
----------------------------------------------------------------------------------------------------

Items.DOCKED_SEARCH_WIDTH = 170

-- Docked and an item chosen to look at: the card shows, not the list.
function Items.DockedShowsCard(ctx)
	return M.IsDocked(ctx) and Items.state.dockedCard and Items.Selected() ~= nil and true or false
end

function Items.DockedRefresh(body, ctx, model)
	local m = ctx.metrics
	local left, card = body.left, body.card
	local showCard = Items.DockedShowsCard(ctx)
	left:SetShown(not showCard)
	left.rule:Hide()
	if not body.dscroll then
		body.dscroll = M.Docked.Scroll(body)
	end
	local scroll = body.dscroll
	scroll:ClearAllPoints()
	scroll:SetAllPoints(body)
	if showCard then
		card:SetParent(scroll.child)
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", 0, 0)
		card:SetWidth(m.width)
		card:Show()
		scroll.child:SetWidth(m.width)
		scroll:Show()
		DrawCard(body, model.card, m.width - 2 * CARD_PAD_X, true)
		local h = card.contentHeight or 0
		card:SetHeight(h)
		scroll:SetContentHeight(h)
		return
	end
	scroll:Hide()
	card:Hide()
	left:SetWidth(m.width)
	left.empty:SetWidth(m.width - 32)
	Items.rowNameWidth = m.width - 46 - 16 - 110
	DrawList(body, model.list)
end

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
		Items.WarmNow() -- a typed name wants its answer now
		local found = Items.Search(arg) or {}
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
