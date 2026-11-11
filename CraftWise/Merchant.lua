-- Merchant recorder (issue #66): the whole inventory of every merchant this account opens, so
-- "who sells X" has an answer (`/craftwise where <item>`, the "Sold by" tooltip line). Only what the
-- merchant window shows; nothing is estimated. No assumed discount table and no assumed restock time:
-- the player's standing is stored next to each recording, and limited stock keeps a log of counts so
-- discounts and restock intervals can be measured.
--
-- Stored account-wide in CraftWiseDB.merchants, keyed by the NPC ID from the merchant's GUID:
--   merchants[npcID] = {
--     name, zone, sub,            NPC name, zone and subzone when the window opened
--     map, x, y,                  uiMapID and the player's position there (0-100, one decimal); none in instances
--     group = "H"|"A",            the NPC's faction group (UnitFactionGroup), when it has one
--     faction = { id, name },     the NPC's reputation faction: a line of the NPC's tooltip that is the name
--                                 of a faction in the player's reputation list (unverified in Forever, see
--                                 docs/ingame-checks.md). Missing when no line matched.
--     standing = 1..8,            the player's standing with that faction (FactionData.reaction)
--     reaction = 1..8,            UnitReaction("npc", "player"): what the client reports for this NPC, always
--                                 stored, also when no faction matched
--     realm,                      realm of the last visit (limited stock is per realm)
--     char,                       character key ("<realm>-<name> <surname>", #77) that opened it last (#75; missing in
--                                 records from before #75)
--     filter, full,               merchant filter (GetMerchantFilter) and whether it showed everything
--                                 (LE_LOOT_FILTER_ALL). A filtered view keeps items it did not show.
--     first, t,                   first and last visit (Unix time)
--     items = { [itemID] = {
--       name,                     item name as the merchant window showed it
--       p, s,                     price in copper for one purchase and the stack it buys (p = 0: currency only)
--       c = { { name, amount, item = id | currency = id } },  extended costs
--       n,                        stock: -1 unlimited, else the number available
--       unusable = true,          the merchant shows it in red (not usable by this character)
--       known = true,             the item's tooltip says "Already known"
--       req = { faction, standing, text },  reputation requirement on the item's tooltip (#91), as the
--                                 line reads; standing 1..8 when the label is a known standing
--       ps = { [standing] = p },  price seen at each standing with the NPC's faction (discount evidence)
--       pk = { [standing] = key },  character key that saw ps[standing] last (#75)
--       pc = { [key] = { p, st, t } },  per character: the copper price it saw last, its standing with
--                                 the NPC's faction then (missing when no faction matched) and when (#75).
--                                 Records from before #75 have no pc/pk; they still show as before.
--       log = { { n, first, last, realm } },  limited stock: each count seen, first and last time
--       t }                       last seen
--   }
local _, ns = ...

local M = {}
ns.Merchant = M

M.LOG_MAX = 20 -- stock observations kept per limited item
M.TOOLTIP_CHARS = 3 -- characters per merchant on the "Sold by" tooltip line (#75)
M.NEUTRAL = 4 -- FactionData.reaction: 1 Hated .. 4 Neutral .. 8 Exalted
M.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

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

-- The only place this file builds a character key: ns.CharKey() (Core.lua, #77), "<realm>-<name> <surname>".
local function CharKey()
	return ns.CharKey()
end
M.CharKey = CharKey

local function Store()
	if not ns.db then
		return nil
	end
	ns.db.merchants = ns.db.merchants or {}
	return ns.db.merchants
end

function M.StandingLabel(standing)
	return standing and (_G["FACTION_STANDING_LABEL" .. standing] or M.STANDINGS[standing]) or nil
end

----------------------------------------------------------------------------------------------------
-- Where and who
----------------------------------------------------------------------------------------------------

local function Round1(v)
	return v and math.floor(v * 1000 + 0.5) / 10 or nil
end

-- uiMapID and the player's position on it in percent; nil x, y where the client gives none.
local function Position()
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return nil
	end
	local mapID = Number(C_Map.GetBestMapForUnit("player"))
	if not mapID then
		return nil
	end
	local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y
	if pos then
		x, y = pos.x, pos.y
		if (x == nil or y == nil) and pos.GetXY then
			x, y = pos:GetXY()
		end
	end
	return mapID, Round1(Number(x)), Round1(Number(y))
end

-- Faction names of the player's reputation list -> faction data. Rows under collapsed headers are not
-- listed by the client; their IDs come from earlier visits (factionIDs cache in the store).
local function ReputationByName()
	local byName = {}
	local R = C_Reputation
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then
		return byName
	end
	ns.db.factionIDs = ns.db.factionIDs or {}
	for index = 1, R.GetNumFactions() or 0 do
		local f = R.GetFactionDataByIndex(index)
		local name = f and Text(f.name)
		if name and (not f.isHeader or f.isHeaderWithRep) then
			byName[name] = f
			if f.factionID then
				ns.db.factionIDs[name] = f.factionID
			end
		end
	end
	if R.GetFactionDataByID then
		for name, id in pairs(ns.db.factionIDs) do
			if not byName[name] then
				byName[name] = R.GetFactionDataByID(id)
			end
		end
	end
	return byName
end

-- The NPC's reputation faction as the client shows it: a tooltip line (after the name) that is the name
-- of a faction the player has. Returns the faction data or nil.
local function NpcFaction()
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
	if not (ok and data and data.lines) then
		return nil
	end
	local byName = ReputationByName()
	for i = 2, #data.lines do
		local name = Text(data.lines[i].leftText)
		local f = name and byName[name]
		if f and f.factionID then
			return f
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------------------------------

local function ItemInfo(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if not info then
			return nil
		end
		return { name = Text(info.name), price = Number(info.price), stack = Number(info.stackCount),
			available = Number(info.numAvailable), usable = info.isUsable, extended = info.hasExtendedCost,
			currency = Number(info.currencyID) }
	end
	if GetMerchantItemInfo then
		local name, _, price, stack, available, _, usable, extended = GetMerchantItemInfo(index)
		if name == nil and price == nil then
			return nil
		end
		return { name = Text(name), price = Number(price), stack = Number(stack), available = Number(available),
			usable = usable, extended = extended }
	end
end

-- Currencies and items the merchant asks besides (or instead of) copper.
local function Costs(index)
	local count = GetMerchantItemCostInfo and Number(GetMerchantItemCostInfo(index)) or 0
	local costs = {}
	for i = 1, count do
		local _, amount, link, currencyName = GetMerchantItemCostItem(index, i)
		link = Text(link)
		amount = Number(amount)
		local name = Text(currencyName) or (link and link:match("%[(.-)%]"))
		if name and amount and amount > 0 then
			costs[#costs + 1] = { name = name, amount = amount,
				item = link and tonumber(link:match("item:(%d+)")) or nil,
				currency = link and tonumber(link:match("currency:(%d+)")) or nil }
		end
	end
	return #costs > 0 and costs or nil
end

-- Standing number (1..8) of a standing label as the client names it (FACTION_STANDING_LABELn).
local function StandingNumber(label)
	for i = 1, 8 do
		if label == (Text(_G["FACTION_STANDING_LABEL" .. i]) or M.STANDINGS[i]) then
			return i
		end
	end
end

-- Lua pattern of the client's reputation requirement line, ITEM_REQ_REPUTATION ("Requires %s - %s" on
-- an English client): faction and standing captured. nil when the client has no such string.
local function ReqPattern()
	local fmt = Text(ITEM_REQ_REPUTATION)
	if not fmt then
		return nil
	end
	local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("%%%d%$s", "(.+)"):gsub("%%s", "(.+)")
	return "^" .. p .. "$"
end

-- The item's merchant tooltip (#66, #91): "Already known" (recipes, mounts, toys) and the reputation
-- requirement { faction, standing = 1..8 | nil, text } exactly as the line reads. Returns read (the
-- client gave a tooltip), known, req.
local function ItemTooltip(index)
	if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then
		return false
	end
	local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
	if not (ok and data and data.lines) then
		return false
	end
	local knownText, pattern = Text(ITEM_SPELL_KNOWN), ReqPattern()
	local known, req
	for _, line in ipairs(data.lines) do
		local text = Text(line.leftText)
		text = text and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		if text then
			if knownText and text == knownText then
				known = true
			elseif pattern and not req then
				local faction, standing = text:match(pattern)
				if faction then
					req = { faction = faction, standing = StandingNumber(standing), text = text }
				end
			end
		end
	end
	return true, known, req
end
M.ItemTooltip = ItemTooltip

local function IsRecipe(itemID)
	if not (C_Item and C_Item.GetItemInfoInstant) then
		return false
	end
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	return classID == ((Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9)
end

-- Limited stock: a new log entry when the count changed, else the last entry's last-seen time moves.
local function LogStock(item, n, now, realm)
	item.log = item.log or {}
	local last = item.log[#item.log]
	if last and last.n == n and last.realm == realm then
		last.last = now
		return
	end
	item.log[#item.log + 1] = { n = n, first = now, last = now, realm = realm }
	while #item.log > M.LOG_MAX do
		table.remove(item.log, 1)
	end
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

local function ParseNpc(guid)
	if ns.Sources and ns.Sources.ParseGUID then
		return ns.Sources.ParseGUID(guid)
	end
end

local openFaction -- { npcID, f = faction data or false } for the merchant window that is open

-- Records the open merchant. Returns the number of items recorded (0 when nothing was recorded).
function M.Record()
	local store = Store()
	if not (store and GetMerchantNumItems and GetMerchantItemID) then
		return 0
	end
	local kind, npcID = ParseNpc(UnitGUID and UnitGUID("npc"))
	if kind ~= "Creature" then
		return 0
	end
	local count = Number(GetMerchantNumItems()) or 0
	if count == 0 then
		return 0 -- not loaded yet (MERCHANT_UPDATE follows), or nothing for sale: keep what was recorded
	end
	local now = time()
	local m = store[npcID]
	if not m then
		m = { first = now, items = {} }
		store[npcID] = m
	end
	m.name = Text(UnitName and UnitName("npc")) or m.name
	m.zone = Text(GetRealZoneText and GetRealZoneText()) or m.zone
	m.sub = Text(GetSubZoneText and GetSubZoneText())
	local map, x, y = Position()
	if map then
		m.map, m.x, m.y = map, x, y
	end
	local group = Text(UnitFactionGroup and UnitFactionGroup("npc"))
	m.group = group == "Horde" and "H" or group == "Alliance" and "A" or nil
	-- The NPC's faction and the player's standing don't change while the window is open: read once per
	-- MERCHANT_SHOW, not on every MERCHANT_UPDATE (each purchase fires one).
	if not (openFaction and openFaction.npcID == npcID) then
		openFaction = { npcID = npcID, f = NpcFaction() or false }
	end
	local f = openFaction.f
	if f then
		m.faction = { id = f.factionID, name = Text(f.name) }
		m.standing = Number(f.reaction)
	else
		m.faction, m.standing = nil, nil
	end
	m.reaction = UnitReaction and Number(UnitReaction("npc", "player")) or nil
	m.realm = Text(GetRealmName and GetRealmName())
	local key = CharKey()
	m.char = key or m.char
	local filter = GetMerchantFilter and Number(GetMerchantFilter()) or nil
	m.filter = filter
	m.full = (filter ~= nil and filter == LE_LOOT_FILTER_ALL) or nil
	m.t = now

	local seen, recorded, resolved = {}, 0, 0
	for index = 1, count do
		local itemID = Number(GetMerchantItemID(index))
		local info = itemID and ItemInfo(index)
		if info then
			resolved = resolved + 1
		end
		if info and not info.currency then
			local item = m.items[itemID] or {}
			m.items[itemID] = item
			item.name = info.name or item.name
			item.p = info.price or 0
			item.s = info.stack and info.stack > 0 and info.stack or 1
			item.c = info.extended and Costs(index) or nil
			item.n = info.available
			item.unusable = info.usable == false or nil
			-- Tooltip only for recipes and items with currency/item costs (Favor vendors, #91).
			local recipe = IsRecipe(itemID)
			if recipe or info.extended then
				local read, known, req = ItemTooltip(index)
				if read then
					if recipe then
						item.known = known
					end
					item.req = req
				end
			end
			if m.standing and item.p > 0 then
				item.ps = item.ps or {}
				item.ps[m.standing] = item.p
				if key then
					item.pk = item.pk or {}
					item.pk[m.standing] = key
				end
			end
			if key and item.p > 0 then
				item.pc = item.pc or {}
				item.pc[key] = { p = item.p, st = m.standing, t = now }
			end
			if item.n and item.n >= 0 then
				LogStock(item, item.n, now, m.realm)
			end
			item.t = now
			seen[itemID] = true
			recorded = recorded + 1
		end
	end
	-- An unfiltered view is the whole inventory: items it no longer shows are gone. A filtered view (or
	-- one whose filter is unknown, or a list the client had not fully loaded) keeps them, with their own
	-- last-seen time.
	if m.full and resolved == count then
		for itemID in pairs(m.items) do
			if not seen[itemID] then
				m.items[itemID] = nil
			end
		end
	end
	if recorded > 0 then
		ns.Notify("MERCHANTS_CHANGED")
	end
	return recorded
end

ns.On("MERCHANT_SHOW", function()
	openFaction = nil
	M.Record()
end)
ns.On("MERCHANT_UPDATE", function()
	M.Record()
end)
ns.On("MERCHANT_CLOSED", function()
	openFaction = nil
end)

----------------------------------------------------------------------------------------------------
-- Lookup: who sells X
----------------------------------------------------------------------------------------------------

-- Unit price in copper of a recorded item (nil when it costs no copper).
local function Unit(item)
	return item.p and item.p > 0 and item.p / math.max(item.s or 1, 1) or nil
end

-- Account snapshots (#63) whose owner is known: a pre-#77 key kept as `legacy` may mix characters.
local function Snapshots()
	local out = {}
	for key, snap in pairs(ns.db and ns.db.snapshots or {}) do
		if type(snap) == "table" and not snap.legacy then
			out[key] = snap
		end
	end
	return out
end

-- The standing of an account character with a faction: live for the character logged in, else from
-- its #63 snapshot's reputation list. Returns reaction (1..8) or nil when neither has it (never guessed;
-- a faction under a collapsed header is not in the snapshot).
local function StandingOf(key, factionID, current, snaps)
	if key == current and C_Reputation and C_Reputation.GetFactionDataByID then
		local f = C_Reputation.GetFactionDataByID(factionID)
		local reaction = f and Number(f.reaction)
		if reaction then
			return reaction
		end
	end
	local reps = snaps[key] and snaps[key].reputations
	for _, f in ipairs(reps and reps.list or {}) do
		if f.id == factionID then
			return Number(f.reaction)
		end
	end
end

-- Price per account character at one merchant (#75), cheapest first:
-- { { key, p, st, t, seen = true } }. Characters that opened the merchant give what they saw (pc).
-- A character that never opened it is listed with seen = true only when its standing with the
-- merchant's faction is known (live or snapshot) and a price at exactly that standing was observed
-- here (ps, by any character). No price is ever derived from a discount.
function M.CharPrices(m, item)
	local out, have = {}, {}
	for key, o in pairs(item.pc or {}) do
		if o.p and o.p > 0 then
			out[#out + 1] = { key = key, p = o.p, st = o.st, t = o.t }
			have[key] = true
		end
	end
	local factionID = m.faction and m.faction.id
	if factionID and item.ps then
		local current = CharKey()
		local snaps = Snapshots()
		local keys = {}
		for key in pairs(snaps) do
			keys[key] = true
		end
		if current then
			keys[current] = true
		end
		for key in pairs(keys) do
			if not have[key] then
				local st = StandingOf(key, factionID, current, snaps)
				local p = st and item.ps[st]
				if p and p > 0 then
					out[#out + 1] = { key = key, p = p, st = st, seen = true }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.p ~= b.p then
			return a.p < b.p
		end
		if (a.seen or false) ~= (b.seen or false) then
			return not a.seen -- observed by that character first
		end
		return a.key < b.key
	end)
	return out
end

-- Every recorded merchant that sold itemID: { npcID, merchant, item, unit, chars }, cheapest copper price
-- first (the cheapest any account character gets, #75), currency-only offers after them.
function M.Sellers(itemID)
	local out = {}
	for npcID, m in pairs(Store() or {}) do
		local item = m.items and m.items[itemID]
		if item then
			local chars = M.CharPrices(m, item)
			local unit = Unit(item)
			if chars[1] then
				local best = chars[1].p / math.max(item.s or 1, 1)
				unit = unit and math.min(unit, best) or best
			end
			out[#out + 1] = { npcID = npcID, merchant = m, item = item, unit = unit, chars = chars }
		end
	end
	table.sort(out, function(a, b)
		if (a.unit ~= nil) ~= (b.unit ~= nil) then
			return a.unit ~= nil
		end
		if a.unit and a.unit ~= b.unit then
			return a.unit < b.unit
		end
		return (a.item.t or 0) > (b.item.t or 0)
	end)
	return out
end

-- Recorded item IDs whose name contains text (case-insensitive), sorted by name.
function M.FindItems(text)
	text = (text or ""):lower()
	local found, names = {}, {}
	for _, m in pairs(Store() or {}) do
		for itemID, item in pairs(m.items or {}) do
			local name = item.name or (C_Item and C_Item.GetItemNameByID and Text(C_Item.GetItemNameByID(itemID)))
			if not names[itemID] and name and name:lower():find(text, 1, true) then
				names[itemID] = name
				found[#found + 1] = itemID
			end
		end
	end
	table.sort(found, function(a, b)
		local exactA, exactB = names[a]:lower() == text, names[b]:lower() == text
		if exactA ~= exactB then
			return exactA -- exact name first
		end
		return names[a] < names[b]
	end)
	return found, names
end

----------------------------------------------------------------------------------------------------
-- Reputation discounts (#8): measured, never assumed
----------------------------------------------------------------------------------------------------

-- Base price of one purchase of itemID: a price seen at Neutral (or below) with the merchant's faction.
-- Returns copper, stack or nil. Only observations count; a discount is never applied backwards.
function M.BasePrice(itemID)
	for _, seller in ipairs(M.Sellers(itemID)) do
		for standing, p in pairs(seller.item.ps or {}) do
			if standing <= M.NEUTRAL then
				return p, seller.item.s or 1
			end
		end
	end
end

-- Price ratios seen per standing above Neutral, against a Neutral price of the same item:
-- { [standing] = { min, max, n = observations, items = distinct items } }.
function M.Discounts()
	local out = {}
	local counted = {}
	for _, m in pairs(Store() or {}) do
		for itemID, item in pairs(m.items or {}) do
			for standing, p in pairs(item.ps or {}) do
				if standing > M.NEUTRAL then
					local base, stack = M.BasePrice(itemID)
					if base and base > 0 and stack == (item.s or 1) then
						local ratio = p / base
						local d = out[standing] or { n = 0, items = 0 }
						out[standing] = d
						d.n = d.n + 1
						d.min = math.min(d.min or ratio, ratio)
						d.max = math.max(d.max or ratio, ratio)
						counted[standing] = counted[standing] or {}
						if not counted[standing][itemID] then
							counted[standing][itemID] = true
							d.items = d.items + 1
						end
					end
				end
			end
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Limited stock: restocks seen
----------------------------------------------------------------------------------------------------

-- Each time a limited item's count went up on the same realm: { from, to, after, before } -- the
-- rise happened after the last time the lower count was seen and before the higher count was seen.
-- Forever layers may keep separate stock and the client doesn't say which layer was seen, so a rise
-- is not proven to be a restock of the same layer (Scout on #73).
function M.Restocks(item)
	local out = {}
	local log = item and item.log or {}
	for i = 2, #log do
		local a, b = log[i - 1], log[i]
		if b.n > a.n and a.realm == b.realm then
			out[#out + 1] = { from = a.n, to = b.n, after = a.last, before = b.first }
		end
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

function M.FormatAge(seconds)
	seconds = math.max(0, seconds or 0)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return ("%dm ago"):format(math.floor(seconds / 60))
	elseif seconds < 2 * 86400 then
		return ("%dh ago"):format(math.floor(seconds / 3600))
	end
	return ("%dd ago"):format(math.floor(seconds / 86400))
end

local function Span(seconds)
	if seconds < 3600 then
		return ("%dm"):format(math.floor(seconds / 60))
	elseif seconds < 2 * 86400 then
		return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return ("%dd"):format(math.floor(seconds / 86400))
end

-- "90c", "90c for 5", "10 Merchant's Favor", "1s + 2 Silk Cloth".
function M.PriceText(item, plain)
	local parts = {}
	if item.p and item.p > 0 then
		parts[1] = ns.FormatMoney(item.p, plain)
	end
	for _, c in ipairs(item.c or {}) do
		parts[#parts + 1] = ("%d %s"):format(c.amount, c.name)
	end
	local text = #parts > 0 and table.concat(parts, " + ") or "price not seen"
	if (item.s or 1) > 1 then
		text = text .. (" for %d"):format(item.s)
	end
	return text
end

function M.StockText(item)
	if not item.n or item.n < 0 then
		return nil
	end
	return item.n == 0 and "sold out" or ("%d in stock"):format(item.n)
end

-- A character key as people read it: the full name ("Velikopter Tanner"), with "-<realm>" only when the
-- character is on another realm than the one logged in. Names have no "-"; realms may.
function M.CharDisplay(key)
	local name = key:match("([^-]+)$") or key
	local realm = key:sub(1, #key - #name - 1)
	if realm == "" or realm == (Text(GetRealmName and GetRealmName()) or "") then
		return name
	end
	return name .. "-" .. realm
end

-- One character's price: "90c with Velikopter Tanner (Honored)", "1s with Velikopter Wright (seen at
-- Neutral)". short (tooltip): without "with".
function M.CharPriceText(e, item, short, plain)
	local text = M.PriceText({ p = e.p, s = item.s, c = item.c }, plain) .. (short and " " or " with ") .. M.CharDisplay(e.key)
	local label = M.StandingLabel(e.st)
	if e.seen then
		return text .. (" (seen at %s)"):format(label or "?")
	elseif label then
		return text .. (" (%s)"):format(label)
	end
	return text
end

function M.CharPricesText(chars, item, short, max)
	local parts = {}
	for i, e in ipairs(chars) do
		if max and i > max then
			parts[#parts + 1] = ("+%d"):format(#chars - max)
			break
		end
		parts[#parts + 1] = M.CharPriceText(e, item, short)
	end
	return table.concat(parts, ", ")
end

-- "Honored with Thunder Bluff", or the reaction the client reports when no faction was matched.
function M.StandingText(m)
	if m.faction and m.standing then
		return ("%s with %s"):format(M.StandingLabel(m.standing) or "?", m.faction.name or "?")
	elseif m.reaction then
		return ("reaction %s, faction not reported"):format(M.StandingLabel(m.reaction) or tostring(m.reaction))
	end
	return "standing not reported"
end

local function PlaceText(m)
	local place = m.zone or "?"
	if m.sub and m.sub ~= m.zone then
		place = place .. ", " .. m.sub
	end
	if m.x and m.y then
		place = place .. (" (%.1f, %.1f)"):format(m.x, m.y)
	end
	return place
end

-- Chat lines for `/craftwise where`: one per merchant, then restocks seen.
function M.SellerLines(itemID, now)
	now = now or time()
	local lines = {}
	for _, s in ipairs(M.Sellers(itemID)) do
		local m, item = s.merchant, s.item
		local parts = { ("%s - %s"):format(m.name or ("NPC " .. s.npcID), PlaceText(m)) }
		if s.chars and s.chars[1] then
			-- Per character (#75); the standings are in the list, the faction once.
			parts[#parts + 1] = M.CharPricesText(s.chars, item)
			parts[#parts + 1] = m.faction and ("faction " .. (m.faction.name or "?")) or M.StandingText(m)
		else
			parts[#parts + 1] = M.PriceText(item)
			parts[#parts + 1] = M.StandingText(m)
		end
		local stock = M.StockText(item)
		if stock then
			parts[#parts + 1] = stock
		end
		if item.known then
			parts[#parts + 1] = "already known"
		elseif item.unusable then
			parts[#parts + 1] = "not usable"
		end
		parts[#parts + 1] = "seen " .. M.FormatAge(now - (item.t or m.t or now))
		lines[#lines + 1] = "  " .. table.concat(parts, " · ")
		for _, r in ipairs(M.Restocks(item)) do
			lines[#lines + 1] = ("    count rose %d -> %d between %s and %s (within %s, may be another layer)"):format(r.from, r.to,
				date("%m-%d %H:%M", r.after), date("%m-%d %H:%M", r.before), Span(r.before - r.after))
		end
	end
	local base, stack = M.BasePrice(itemID)
	if base then
		lines[#lines + 1] = ("  base price seen at Neutral: %s%s"):format(ns.FormatMoney(base),
			(stack or 1) > 1 and (" for %d"):format(stack) or "")
	end
	return lines
end

-- Tooltip: "Sold by" with the cheapest merchants (at most 2) and how many more.
function M.TooltipLines(itemID, now)
	now = now or time()
	local sellers = M.Sellers(itemID)
	local lines = {}
	for i, s in ipairs(sellers) do
		if i > 2 then
			lines[#lines + 1] = { "", ("|cff8c95a6+%d more: /craftwise where|r"):format(#sellers - 2) }
			break
		end
		local m, item = s.merchant, s.item
		local parts = { m.name or ("NPC " .. s.npcID) }
		if s.chars and s.chars[1] then
			parts[#parts + 1] = M.CharPricesText(s.chars, item, true, M.TOOLTIP_CHARS)
		else
			parts[#parts + 1] = M.PriceText(item)
			if m.faction and m.standing then
				parts[#parts + 1] = M.StandingLabel(m.standing)
			end
		end
		local stock = M.StockText(item)
		if stock then
			parts[#parts + 1] = stock
		end
		parts[#parts + 1] = M.FormatAge(now - (item.t or now))
		lines[#lines + 1] = { i == 1 and "Sold by" or "", table.concat(parts, " · ") }
	end
	return lines
end

local function PrintItem(itemID, name)
	ns.Print(ns.ItemChatText(itemID, { name = name }) .. ":")
	for _, line in ipairs(M.SellerLines(itemID)) do
		print(line)
	end
end

-- `/craftwise where <item link | item ID | name>`.
function M.Slash(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	if arg == "" then
		ns.Print("usage: /craftwise where <item link, item ID or name>")
		return
	end
	local itemID = tonumber(arg) or tonumber(arg:match("item:(%d+)"))
	if itemID then
		if #M.Sellers(itemID) == 0 then
			ns.Print(ns.ItemChatText(itemID) .. ": no merchant you opened sells it")
			return
		end
		ns.WithItemNames({ itemID }, function()
			PrintItem(itemID)
		end)
		return
	end
	local found, names = M.FindItems(arg)
	if #found == 0 then
		ns.Print(("no merchant you opened sells an item named \"%s\""):format(arg))
		return
	end
	for i, id in ipairs(found) do
		if i > 3 then
			ns.Print(("%d more items match \"%s\"; be more specific"):format(#found - 3, arg))
			break
		end
		PrintItem(id, names[id])
	end
end

-- Number of merchants recorded, for diagnostics.
function M.Count()
	local n = 0
	for _ in pairs(Store() or {}) do
		n = n + 1
	end
	return n
end
