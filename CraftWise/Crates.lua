-- Waylaid Crates and Merchant's Favor (issue #91): what each crate asks for and gives, read from its
-- tooltip in game, what filling one costs per Merchant's Favor, the Favor balance and the merchants
-- that take Favor. Only what the client shows; a reward or requirement that wasn't seen stays missing.
--
-- Evidence (2026-11-11, Veli's SavedVariables):
--   * Merchant's Favor is currency 3402: the cost links of 82 items at Pawani (NPC 248201, The Barrens,
--     faction Durotar Supply and Logistics) recorded by the merchant recorder (#66) are "currency:3402".
--     Its name is read from the client (C_CurrencyInfo), else from those recorded costs.
--   * Crate items are named "Waylaid Crate: <tier> <goods>" (e.g. 248682 "Waylaid Crate: Apprentice
--     Herbs"), and their tooltip has "Use: Fill the crate with any bundle from the following list:"
--     followed by "- <count> <item name>" lines (tooltip texts the client showed, kept by another addon
--     in the same SavedVariables folder). Crates are found by that name prefix (English client) and
--     parsed by the "- <count> <name>" lines; the raw lines are kept in case parsing misses.
--   * No reward was seen on a crate tooltip so far. A reward line naming the Favor currency is parsed
--     when the tooltip has one; otherwise the reward is measured: a Favor gain seen within a few seconds
--     of one crate leaving the bags (CURRENCY_DISPLAY_UPDATE + BAG_UPDATE_DELAYED).
--
-- Stored account-wide in CraftWiseDB.crates[itemID] = {
--   name, label, tier,     item name; the part after the colon; its first word ("Apprentice")
--   lines = { "..." },     raw tooltip lines (left text, a tab and the right text when there is one)
--   fill = { { n, name, id } },  bundles the crate takes (any one of them); id once the name resolved
--   reward, rewardText,    Favor reward and the line it was read from, when the tooltip states one
--   got = { { n, t } },    Favor gains measured when one of these crates left the bags (last 20)
--   seen = { bags, ah, merchant = true },  where the crate was seen
--   t }                    last time the tooltip was read
local _, ns = ...

local C = {}
ns.Crates = C

C.FAVOR = 3402 -- Merchant's Favor (see the evidence above)
C.PREFIX = "Waylaid " -- crate item names on an English client
C.WINDOW = 3 -- seconds between a Favor gain and a crate leaving the bags to count as one turn-in
C.GOT_MAX = 20
C.LINES_MAX = 40
C.READ_TRIES = 3 -- tooltip reads per session while the client hasn't filled the tooltip in yet
C.MARKET_EVERY = 30 -- seconds between looks for crates among the auction house items (#90)

local function Safe(value)
	if value ~= nil and issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

local function Text(value)
	value = Safe(value)
	return type(value) == "string" and value ~= "" and value or nil
end

local function Number(value)
	value = Safe(value)
	return type(value) == "number" and value or nil
end

local function Store()
	if not ns.db then
		return nil
	end
	ns.db.crates = ns.db.crates or {}
	return ns.db.crates
end
C.Store = Store

local function Now()
	return GetTime and GetTime() or 0
end

----------------------------------------------------------------------------------------------------
-- Merchant's Favor
----------------------------------------------------------------------------------------------------

local function CurrencyInfo()
	if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
		return nil
	end
	local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, C.FAVOR)
	return ok and type(info) == "table" and info or nil
end

-- Every recorded merchant item that costs Favor: calls fn(npcID, merchant, itemID, item, amount, name).
local function EachFavorItem(fn)
	for npcID, m in pairs(ns.db and ns.db.merchants or {}) do
		for itemID, item in pairs(m.items or {}) do
			for _, c in ipairs(item.c or {}) do
				if c.currency == C.FAVOR then
					fn(npcID, m, itemID, item, c.amount, c.name)
				end
			end
		end
	end
end

-- The currency's name as the client shows it; else as a merchant's cost line showed it.
function C.FavorName()
	local info = CurrencyInfo()
	local name = info and Text(info.name)
	if name then
		return name
	end
	EachFavorItem(function(_, _, _, _, _, costName)
		name = name or Text(costName)
	end)
	return name
end

-- This character's balance: { id, name, balance, max, earned } or nil when the client gives none.
function C.Balance()
	local info = CurrencyInfo()
	if not info then
		return nil
	end
	local max = Number(info.maxQuantity)
	local earned = Number(info.totalEarned)
	return { id = C.FAVOR, name = Text(info.name) or C.FavorName(), balance = Number(info.quantity),
		max = max and max > 0 and max or nil, earned = earned and earned > 0 and earned or nil }
end

----------------------------------------------------------------------------------------------------
-- Tooltip parsing (pure)
----------------------------------------------------------------------------------------------------

-- Text without colour codes, texture and atlas markup.
function C.Clean(s)
	s = s:gsub("|c[nN][^:]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return s
end

local function Escape(s)
	return (s:gsub("(%W)", "%%%1"))
end

local function Amount(s)
	return s and tonumber((s:gsub(",", ""))) or nil
end

-- A Favor amount in one tooltip segment: "<n> <Favor>" or "<Favor>: <n>". A percentage ("100% increased
-- Merchant's Favor") is no amount.
function C.RewardIn(segment, favorName)
	if not favorName then
		return nil
	end
	local name = Escape(favorName)
	return Amount(segment:match("^(%d[%d,]*)%s+" .. name) or segment:match("[^%d%%,](%d[%d,]*)%s+" .. name)
		or segment:match(name .. "%s*:%s*(%d[%d,]*)") or segment:match(name .. "%s*x%s*(%d[%d,]*)"))
end

-- Tooltip lines ({ leftText, rightText }) -> { raw = { text }, fill = { { n, name } }, reward = { n, text } }.
function C.Parse(lines, favorName)
	local out = { raw = {}, fill = {} }
	for _, line in ipairs(lines or {}) do
		local left, right = Text(line.leftText), Text(line.rightText)
		if left or right then
			if #out.raw < C.LINES_MAX then
				out.raw[#out.raw + 1] = right and ((left or "") .. "\t" .. right) or left
			end
			for _, text in ipairs({ left or "", right or "" }) do
				for segment in (C.Clean(text) .. "\n"):gmatch("(.-)\n") do
					segment = segment:match("^%s*(.-)%s*$")
					local n, name = segment:match("^%-%s*(%d+)%s+(.-)$")
					if n and name ~= "" then
						out.fill[#out.fill + 1] = { n = tonumber(n), name = name }
					elseif not out.reward then
						local amount = C.RewardIn(segment, favorName)
						if amount then
							out.reward = { n = amount, text = segment }
						end
					end
				end
			end
		end
	end
	return out
end

-- "Waylaid Crate: Apprentice Herbs" -> "Apprentice Herbs", "Apprentice".
function C.NameParts(name)
	local label = name and name:match("^[^:]+:%s*(.-)%s*$")
	if not label or label == "" then
		return nil, nil
	end
	return label, label:match("^(%S+)%s+%S")
end

----------------------------------------------------------------------------------------------------
-- Finding crates and reading their tooltip
----------------------------------------------------------------------------------------------------

local tries, done, waiting = {}, {}, {} -- per session: tooltip reads, items settled, names requested

-- Names of auction house items as the scans saw them (CraftWiseMarketDB.names, #90).
local function MarketNames()
	return CraftWiseMarketDB and CraftWiseMarketDB.names or {}
end

local function ItemName(itemID)
	return C_Item and C_Item.GetItemNameByID and Text(C_Item.GetItemNameByID(itemID)) or nil
end

local function IsCrateName(name)
	return name and name:sub(1, #C.PREFIX) == C.PREFIX
end

-- Reads a crate's tooltip into the store. Returns the record, or nil when the client had no tooltip.
function C.Read(itemID, name, src)
	local store = Store()
	if not (store and C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
	if not (ok and data and data.lines and #data.lines > 0) then
		return nil
	end
	tries[itemID] = (tries[itemID] or 0) + 1
	local parsed = C.Parse(data.lines, C.FavorName())
	local rec = store[itemID] or {}
	store[itemID] = rec
	rec.name = name
	rec.label, rec.tier = C.NameParts(name)
	rec.lines = parsed.raw
	-- Names already resolved to an item keep their ID.
	local ids = {}
	for _, f in ipairs(rec.fill or {}) do
		ids[f.name] = f.id
	end
	if #parsed.fill > 0 or not rec.fill then
		for _, f in ipairs(parsed.fill) do
			f.id = ids[f.name]
		end
		rec.fill = parsed.fill
	end
	if parsed.reward then
		rec.reward, rec.rewardText = parsed.reward.n, parsed.reward.text
	end
	rec.seen = rec.seen or {}
	if src then
		rec.seen[src] = true
	end
	rec.t = time()
	-- Settled for this session once the list (or a reward) was there, or after a few tries.
	if #parsed.fill > 0 or parsed.reward or tries[itemID] >= C.READ_TRIES then
		done[itemID] = true
	end
	ns.Notify("CRATES_CHANGED", itemID)
	return rec
end

-- Looks at one item seen somewhere (src: "bags", "ah", "merchant"); reads it when it is a crate.
function C.Consider(itemID, src)
	if type(itemID) ~= "number" or done[itemID] then
		return nil
	end
	local name = ItemName(itemID)
	if not name then
		if not waiting[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
			waiting[itemID] = src or true
			pcall(C_Item.RequestLoadItemDataByID, itemID)
		end
		return nil
	end
	if not IsCrateName(name) then
		done[itemID] = true
		return nil
	end
	return C.Read(itemID, name, src)
end

function C.ScanBags()
	if not (ns.Holdings and ns.Holdings.Carried) then
		return {}
	end
	local carried = ns.Holdings.Carried()
	for itemID in pairs(carried) do
		C.Consider(itemID, "bags")
	end
	return carried
end

-- Items the auction house scans stored (CraftWiseMarketDB.items; every full-scan item since #90): by
-- the names the scans kept (CraftWiseMarketDB.names), else by the client cache. Nothing is requested
-- for thousands of items: only a crate's name is loaded so its tooltip can be read.
function C.ScanMarket()
	for itemID, name in pairs(MarketNames()) do
		if type(itemID) == "number" and not done[itemID] and IsCrateName(Text(name)) then
			C.Consider(itemID, "ah")
		end
	end
	for key in pairs(CraftWiseMarketDB and CraftWiseMarketDB.items or {}) do
		if type(key) == "number" and not done[key] and ItemName(key) then
			C.Consider(key, "ah")
		end
	end
end

function C.ScanMerchant()
	if not (GetMerchantNumItems and GetMerchantItemID) then
		return
	end
	for index = 1, Number(GetMerchantNumItems()) or 0 do
		C.Consider(Number(GetMerchantItemID(index)), "merchant")
	end
end

ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
	local src = itemID and waiting[itemID]
	if src then
		waiting[itemID] = nil
		C.Consider(itemID, src ~= true and src or nil)
	elseif itemID and tries[itemID] and not done[itemID] then
		local name = ItemName(itemID)
		if IsCrateName(name) then
			C.Read(itemID, name)
		end
	end
end)

ns.On("MERCHANT_SHOW", function()
	C.ScanMerchant()
end)

local lastMarket
ns.Listen("PRICES_CHANGED", function()
	local now = Now()
	if lastMarket and now - lastMarket < C.MARKET_EVERY then
		return
	end
	lastMarket = now
	C.ScanMarket()
end)

----------------------------------------------------------------------------------------------------
-- Reward measured at turn-in
----------------------------------------------------------------------------------------------------

local held -- crate counts in the bags at the last bag update
local lastDrop, lastGain -- { id, t } one crate left the bags; { n, t } Favor gained

local function RecordGot(itemID, n)
	local rec = Store()[itemID]
	if not rec then
		return
	end
	rec.got = rec.got or {}
	rec.got[#rec.got + 1] = { n = n, t = time() }
	while #rec.got > C.GOT_MAX do
		table.remove(rec.got, 1)
	end
	ns.Notify("CRATES_CHANGED", itemID)
end

local function Match()
	if lastDrop and lastGain and math.abs(lastDrop.t - lastGain.t) <= C.WINDOW then
		RecordGot(lastDrop.id, lastGain.n)
		lastDrop, lastGain = nil, nil
	end
end

function C.OnBags()
	local carried = C.ScanBags()
	local store = Store() or {}
	local counts, dropped = {}, {}
	for itemID in pairs(store) do
		counts[itemID] = carried[itemID] or 0
		if held and held[itemID] and counts[itemID] == held[itemID] - 1 then
			dropped[#dropped + 1] = itemID
		end
	end
	held = counts
	if #dropped == 1 then
		lastDrop = { id = dropped[1], t = Now() }
		Match()
	elseif #dropped > 1 then
		lastDrop = nil -- several crate types left at once: which one was turned in can't be told
	end
end

function C.OnCurrency(currencyType, _, change)
	if Number(currencyType) ~= C.FAVOR then
		return
	end
	change = Number(change)
	if change and change > 0 then
		lastGain = { n = change, t = Now() }
		Match()
	end
	ns.Notify("CRATES_CHANGED")
end

ns.On("BAG_UPDATE_DELAYED", function()
	C.OnBags()
end)
ns.On("CURRENCY_DISPLAY_UPDATE", function(_, currencyType, quantity, change)
	C.OnCurrency(currencyType, quantity, change)
end)

----------------------------------------------------------------------------------------------------
-- Cost per Favor
----------------------------------------------------------------------------------------------------

-- The guide's Favor for a crate (Data/CrateFavorGuide.lua, generated from the site's crateFavorGuide.ts): rank
-- is any word of the part after the colon, kind its last word ("Waylaid Crate: Earthly Expert Herbs" = Expert,
-- Herbs). Artisan and unknown ranks or kinds have no value. Returns favor, basis ("listed" | "rule") or nil.
function C.GuideFavor(name)
	local guide = ns.CrateFavorGuide
	if not (guide and type(name) == "string") then
		return nil
	end
	local label = name:match(":%s*(.*)$") or name
	local words = {}
	for w in label:gmatch("%S+") do
		words[#words + 1] = w
	end
	local kind = words[#words]
	for _, w in ipairs(words) do
		local row = guide.table[w]
		local cell = row and kind and row[kind]
		if cell then
			return cell[1], cell[2]
		end
	end
	return nil
end

-- Reward per crate: the tooltip's, else the most often measured gain (ties: the smaller; a 5% chance
-- doubles it, so the usual value is the one seen most), else the same from a crate of the same name.
-- else the guide's (labelled so, never mixed with measured data).
-- Returns n, from ("tooltip" | "seen" | "guide"), observations.
function C.Reward(itemID)
	local store = Store() or {}
	local function from(rec)
		if rec.reward then
			return rec.reward, "tooltip", nil
		end
		local counts, n = {}, 0
		for _, g in ipairs(rec.got or {}) do
			counts[g.n] = (counts[g.n] or 0) + 1
			n = n + 1
		end
		local best
		for value, c in pairs(counts) do
			if not best or c > counts[best] or (c == counts[best] and value < best) then
				best = value
			end
		end
		if best then
			return best, "seen", n
		end
	end
	local rec = store[itemID]
	if not rec then
		return nil
	end
	local n, src, obs = from(rec)
	if n then
		return n, src, obs
	end
	for otherID, other in pairs(store) do
		if otherID ~= itemID and other.name and other.name == rec.name then
			n, src, obs = from(other)
			if n then
				return n, src, obs
			end
		end
	end
	-- Nothing measured and no tooltip: the published guide, by rank and kind of the crate's name (#176).
	local g = C.GuideFavor(rec.name)
	if g then
		return g, "guide", nil
	end
	return nil
end

-- Item IDs the addon knows of, by the name the client has cached: reagents and outputs of the bundled
-- recipes, vendor items, recorded merchants, auction house items and the bags.
function C.NameIndex()
	local index, seen = {}, {}
	local function add(id)
		if type(id) == "number" and not seen[id] then
			seen[id] = true
			local name = ItemName(id)
			if name and not index[name] then
				index[name] = id
			end
		end
	end
	for _, recipe in pairs(ns.RecipeData or {}) do
		for _, r in ipairs(recipe.reagents or {}) do
			add(r.itemID)
		end
		if recipe.output then
			add(recipe.output.itemID)
		end
	end
	for id in pairs(ns.VendorPrices or {}) do
		add(id)
	end
	for id in pairs(ns.db and ns.db.vendor or {}) do
		add(id)
	end
	for _, m in pairs(ns.db and ns.db.merchants or {}) do
		for id in pairs(m.items or {}) do
			add(id)
		end
	end
	for id in pairs(CraftWiseMarketDB and CraftWiseMarketDB.items or {}) do
		add(id)
	end
	-- Names the auction house scans kept, also for items the client hasn't cached (#90).
	for id, name in pairs(MarketNames()) do
		name = Text(name)
		if type(id) == "number" and name and not index[name] then
			index[name] = id
		end
	end
	if ns.Holdings and ns.Holdings.Carried then
		for id in pairs(ns.Holdings.Carried()) do
			add(id)
		end
	end
	return index
end

-- One crate: crate price (cheapest of vendor and AH), cheapest bundle (craft-or-buy per item as the
-- profit view, #47/#60), reward and the cost per Favor point.
-- { id, name, label, tier, held, crate, crateLabel, options = { { n, name, id, unit, total, label, crafted } },
--   fill (cheapest option), fillCost, reward, rewardFrom, observed, total, perFavor, fillPerFavor, missing }
function C.Evaluate(itemID, prices, index, carried)
	local rec = (Store() or {})[itemID]
	if not rec then
		return nil
	end
	local out = { id = itemID, name = rec.name, label = rec.label, tier = rec.tier, held = carried and carried[itemID] or 0,
		options = {}, missing = {} }
	local crate = ns.GetBuyPrice and ns.GetBuyPrice(itemID)
	if crate then
		out.crate, out.crateLabel = crate.copper, crate.label
	end
	for i, f in ipairs(rec.fill or {}) do
		if not f.id and index then
			f.id = index[f.name] -- kept in the store once resolved
		end
		local o = { n = f.n, name = f.name, id = f.id }
		if f.id then
			local unit = ns.Profit.UnitCost(f.id, prices)
			if unit then
				o.unit, o.total, o.label, o.crafted = unit.copper, unit.copper * f.n, unit.label, unit.crafted or nil
			end
		end
		out.options[i] = o
		if o.total and (not out.fill or o.total < out.fill.total) then
			out.fill = o
		end
	end
	out.fillCost = out.fill and out.fill.total
	out.reward, out.rewardFrom, out.observed = C.Reward(itemID)
	if #out.options == 0 then
		out.missing[#out.missing + 1] = "fill list not read"
	elseif not out.fill then
		out.missing[#out.missing + 1] = "no price for any bundle"
	end
	if not out.reward then
		out.missing[#out.missing + 1] = "reward not seen"
	end
	if not out.crate then
		out.missing[#out.missing + 1] = "no crate price"
	end
	if out.reward and out.reward > 0 and out.fillCost then
		out.fillPerFavor = out.fillCost / out.reward
		if out.crate then
			out.total = out.crate + out.fillCost
			out.perFavor = out.total / out.reward
		end
	end
	return out
end

-- Every recorded crate, cheapest Favor first (crate bought + filled), then those only priced to fill,
-- then the rest by name. Returns list, best (cheapest to buy and fill), bestHeld (cheapest to fill
-- among the crates in the bags).
function C.Ranked()
	local list = {}
	local prices = ns.ReagentPrices("profit", "ah")
	-- The name index (thousands of item IDs) is only built while a bundle name has no item ID yet.
	local index
	for _, rec in pairs(Store() or {}) do
		for _, f in ipairs(rec.fill or {}) do
			if not f.id then
				index = index or C.NameIndex()
			end
		end
	end
	local carried = ns.Holdings and ns.Holdings.Carried and ns.Holdings.Carried() or {}
	for itemID in pairs(Store() or {}) do
		list[#list + 1] = C.Evaluate(itemID, prices, index, carried)
	end
	table.sort(list, function(a, b)
		if (a.perFavor ~= nil) ~= (b.perFavor ~= nil) then
			return a.perFavor ~= nil
		end
		if a.perFavor and a.perFavor ~= b.perFavor then
			return a.perFavor < b.perFavor
		end
		if (a.fillPerFavor ~= nil) ~= (b.fillPerFavor ~= nil) then
			return a.fillPerFavor ~= nil
		end
		if a.fillPerFavor and a.fillPerFavor ~= b.fillPerFavor then
			return a.fillPerFavor < b.fillPerFavor
		end
		return (a.name or "") < (b.name or "")
	end)
	local best, bestHeld = list[1] and list[1].perFavor and list[1] or nil, nil
	for _, e in ipairs(list) do
		if e.held > 0 and e.fillPerFavor and (not bestHeld or e.fillPerFavor < bestHeld.fillPerFavor) then
			bestHeld = e
		end
	end
	return list, best, bestHeld
end

----------------------------------------------------------------------------------------------------
-- Chat: /craftwise crates
----------------------------------------------------------------------------------------------------

local function Money(copper)
	return ns.FormatMoney(math.floor(copper + 0.5))
end

local function RewardText(e, favor)
	if not e.reward then
		return "reward not seen yet"
	end
	local how = e.rewardFrom == "tooltip" and "tooltip" or e.rewardFrom == "guide" and "guide" or ("seen at %d turn-in%s"):format(e.observed or 0, e.observed == 1 and "" or "s")
	return ("%d %s (%s)"):format(e.reward, favor, how)
end

function C.Lines(list, favor)
	local lines = {}
	for i, e in ipairs(list) do
		local parts = {}
		local head = ("%d. %s"):format(i, ns.ItemChatText(e.id, { name = e.name }))
		if e.perFavor then
			head = head .. (" %s per %s"):format(Money(e.perFavor), favor)
		end
		parts[1] = head
		parts[#parts + 1] = e.crate and ("crate %s (%s)"):format(Money(e.crate), e.crateLabel or "?") or "no crate price"
		if e.fill then
			parts[#parts + 1] = ("fill %d %s %s (%s)"):format(e.fill.n, e.fill.name, Money(e.fill.total), e.fill.label or "?")
		elseif #e.options > 0 then
			local names = {}
			for _, o in ipairs(e.options) do
				names[#names + 1] = ("%d %s%s"):format(o.n, o.name, o.id and "" or " (item not identified)")
			end
			parts[#parts + 1] = "no price for " .. table.concat(names, ", ")
		else
			parts[#parts + 1] = "fill list not read from the tooltip"
		end
		parts[#parts + 1] = RewardText(e, favor)
		if e.held > 0 then
			parts[#parts + 1] = e.fillPerFavor and ("you hold %d: fill only %s per %s"):format(e.held, Money(e.fillPerFavor), favor)
				or ("you hold %d"):format(e.held)
		end
		lines[#lines + 1] = "  " .. table.concat(parts, " · ")
	end
	return lines
end

function C.Slash()
	C.ScanBags()
	C.ScanMarket()
	local favor = C.FavorName() or "Merchant's Favor"
	local balance = C.Balance()
	if balance and balance.balance then
		ns.Print(("%s: %d on this character"):format(balance.name or favor, balance.balance))
	end
	local list, best, bestHeld = C.Ranked()
	if #list == 0 then
		ns.Print("no Waylaid crate seen yet: carry one, or let an auction house scan see one")
		return
	end
	ns.Print(("Waylaid crates by cost per %s (crate bought + cheapest bundle):"):format(favor))
	for _, line in ipairs(C.Lines(list, favor)) do
		print(line)
	end
	if best then
		ns.Print(("best to buy and fill: %s, %s per %s"):format(best.name or ("item " .. best.id), Money(best.perFavor), favor))
	end
	if bestHeld then
		ns.Print(("best of the crates you hold: %s, fill for %s per %s"):format(bestHeld.name or ("item " .. bestHeld.id),
			Money(bestHeld.fillPerFavor), favor))
	end
end

----------------------------------------------------------------------------------------------------
-- Snapshot sections (#63): `crates` and `favor`
----------------------------------------------------------------------------------------------------

local function Round(v)
	return v and math.floor(v + 0.5) or nil
end

function C.SnapshotCrates()
	local list, best, bestHeld = C.Ranked()
	local out = { list = {}, best = best and best.id, bestHeld = bestHeld and bestHeld.id }
	for _, e in ipairs(list) do
		local row = { id = e.id, name = e.name, tier = e.tier, held = e.held > 0 and e.held or nil,
			crate = Round(e.crate), crateFrom = e.crateLabel, fillCost = Round(e.fillCost), total = Round(e.total),
			reward = e.reward, rewardFrom = e.rewardFrom, observed = e.observed,
			perFavor = Round(e.perFavor), fillPerFavor = Round(e.fillPerFavor),
			missing = #e.missing > 0 and table.concat(e.missing, ", ") or nil, options = {} }
		for _, o in ipairs(e.options) do
			row.options[#row.options + 1] = { n = o.n, name = o.name, id = o.id, cost = Round(o.total), how = o.label,
				best = (o == e.fill) or nil }
		end
		out.list[#out.list + 1] = row
	end
	return out
end

local function StandingLabel(n)
	return ns.Merchant and ns.Merchant.StandingLabel(n) or n
end

-- Balance, and every recorded merchant that takes Favor with its list (cost, requirement, known).
function C.SnapshotFavor()
	local out = C.Balance() or { id = C.FAVOR, name = C.FavorName() }
	local byNpc = {}
	EachFavorItem(function(npcID, m, itemID, item, amount)
		local v = byNpc[npcID]
		if not v then
			v = { npc = npcID, name = m.name, zone = m.zone, sub = m.sub, map = m.map, x = m.x, y = m.y, t = m.t,
				faction = m.faction and m.faction.name, factionID = m.faction and m.faction.id,
				standing = StandingLabel(m.standing), full = m.full, items = {} }
			if v.factionID and C_Reputation and C_Reputation.GetFactionDataByID then
				local f = C_Reputation.GetFactionDataByID(v.factionID)
				if f and Number(f.reaction) then
					v.standingNow = StandingLabel(Number(f.reaction))
					v.rep = { value = Number(f.currentStanding), min = Number(f.currentReactionThreshold),
						max = Number(f.nextReactionThreshold) }
				end
			end
			byNpc[npcID] = v
		end
		local other = {}
		for _, c in ipairs(item.c or {}) do
			if c.currency ~= C.FAVOR then
				other[#other + 1] = ("%d %s"):format(c.amount, c.name)
			end
		end
		-- Requirement: the standing alone when it is with the merchant's own faction, else the line as read.
		local req = item.req
		if req and req.standing and req.faction == v.faction then
			req = StandingLabel(req.standing)
		else
			req = req and req.text
		end
		v.items[#v.items + 1] = { id = itemID, name = item.name, favor = amount, p = item.p and item.p > 0 and item.p or nil,
			other = #other > 0 and table.concat(other, ", ") or nil, s = (item.s or 1) > 1 and item.s or nil,
			req = req, known = item.known, unusable = item.unusable,
			n = item.n and item.n >= 0 and item.n or nil }
	end)
	out.vendors = {}
	for _, v in pairs(byNpc) do
		table.sort(v.items, function(a, b)
			if a.favor ~= b.favor then
				return a.favor < b.favor
			end
			return (a.name or "") < (b.name or "")
		end)
		out.vendors[#out.vendors + 1] = v
	end
	table.sort(out.vendors, function(a, b)
		return (a.name or "") < (b.name or "")
	end)
	return out
end
