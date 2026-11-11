-- Fishing log (issue #69): every catch with where it was caught, to compare fishing spots by value.
--
-- Recorded inside the loot flow before anything is looted: Loot.lua (#41) calls Fishing.Capture() first
-- thing on LOOT_READY, and this file listens to LOOT_READY itself for when fast auto-loot is off. Once per
-- loot window.
--   * Fishing loot: IsFishingLoot(), the check Blizzard's Forever LootFrame.lua makes on LOOT_OPENED. Every
--     item slot of the window is the catch: item ID and count, zone, subzone, map ID (C_Map.GetBestMapForUnit),
--     time. Coins and currency are not recorded (coin slots only give a localized text).
--   * Pool or open water: the client has no "pool" flag. The loot source's GameObject ID (GetLootSourceInfo) is
--     stored as `obj` when the client gives one, as it is; it is not interpreted here (docs/ingame-checks.md).
--   * Containers: a caught item that is opened later (LOOT_OPENED with isFromItem, the opened item is the locked
--     bag slot whose item has loot) logs its contents against the container's item ID. Only item IDs this
--     character caught count; another copy of the same item (bought, looted) can't be told apart.
--
-- CraftWiseDB.fishing["<realm>-<name> <surname>"] (account-wide, per character), kept 90 days (Scout default, #69):
--   catches = { { t, zone, sub, map, obj, items = { [itemID] = count } }, ... }   one per loot window
--   opened  = { { t, item = container itemID, items = { [itemID] = count } }, ... }
--
-- Value per catch: each item's best sell value (ns.GetSellValue: AH at the profit house and basis after the
-- cut, or vendor; labelled). A container without a value of its own is worth the mean value of what the
-- logged openings gave, labelled "contents of N opened". Items with neither count as "no price data" and are
-- left out of the sum, which then says so.
local _, ns = ...

local F = {}
ns.Fishing = F

F.KEEP_DAYS = 90
local DAY = 86400

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

-- "<realm>-<name> <surname>", the key the ledger and the snapshot use too (#77).
function F.CharKey()
	return ns.CharKey()
end

-- This character's log, created on first use; nil before the DB is loaded.
function F.Log(key)
	if not ns.db then
		return nil
	end
	key = key or F.CharKey()
	if not key then
		return nil
	end
	ns.db.fishing = ns.db.fishing or {}
	local log = ns.db.fishing[key]
	if not log then
		log = { catches = {}, opened = {} }
		ns.db.fishing[key] = log
	end
	return log
end

local function PruneList(list, cutoff)
	local kept = {}
	for _, e in ipairs(list) do
		if (e.t or 0) >= cutoff then
			kept[#kept + 1] = e
		end
	end
	return kept
end

-- Drops records older than KEEP_DAYS, for every character.
function F.Prune(now)
	if not (ns.db and ns.db.fishing) then
		return
	end
	local cutoff = (now or time()) - F.KEEP_DAYS * DAY
	for _, log in pairs(ns.db.fishing) do
		log.catches = PruneList(log.catches or {}, cutoff)
		log.opened = PruneList(log.opened or {}, cutoff)
	end
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

local function ItemIDOf(link)
	link = Text(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Items of the open loot window: { [itemID] = count }, and whether any slot had one.
local function ReadSlots()
	local items, any = {}, false
	if not (GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then
		return items, any
	end
	for slot = 1, Safe(GetNumLootItems()) or 0 do
		local itemID = ItemIDOf(GetLootSlotLink(slot))
		if itemID then
			local _, _, quantity, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
			quantity, currencyID, isCoin = Safe(quantity), Safe(currencyID), Safe(isCoin)
			if not (isCoin or currencyID) then
				items[itemID] = (items[itemID] or 0) + math.max(1, tonumber(quantity) or 1)
				any = true
			end
		end
	end
	return items, any
end

-- GameObject ID of the window's loot source, when the client names one.
local function SourceObject()
	if not (GetLootSourceInfo and ns.Sources and ns.Sources.ParseGUID) then
		return nil
	end
	local ok, guid = pcall(GetLootSourceInfo, 1)
	if not ok then
		return nil
	end
	local kind, id = ns.Sources.ParseGUID(guid)
	return kind == "GameObject" and id or nil
end

local function Where()
	local zone = GetRealZoneText and Text(GetRealZoneText())
	-- "" = the client names no subzone here (kept, #78; nil only when the text isn't readable).
	local sub = GetSubZoneText and Safe(GetSubZoneText())
	sub = type(sub) == "string" and sub or nil
	local map = C_Map and C_Map.GetBestMapForUnit and Safe(C_Map.GetBestMapForUnit("player"))
	return zone, sub, map
end

local captured = false -- this loot window was read
local pending -- items of a window that isn't fishing loot, until LOOT_OPENED says whether it came from an item

local function IsFishing()
	if not IsFishingLoot then
		return false
	end
	local ok, fishing = pcall(IsFishingLoot)
	return ok and Safe(fishing) == true
end

-- Reads the open loot window once. Fishing loot is recorded right away; anything else waits for LOOT_OPENED.
-- Returns the stored catch, if any.
function F.Capture()
	if captured then
		return nil
	end
	captured = true
	local ok, result = pcall(function()
		local items, any = ReadSlots()
		if not any then
			return nil
		end
		if not IsFishing() then
			pending = items
			return nil
		end
		local log = F.Log()
		if not log then
			return nil
		end
		local zone, sub, map = Where()
		local catch = { t = time(), zone = zone, sub = sub, map = map, obj = SourceObject(), items = items }
		log.catches[#log.catches + 1] = catch
		return catch
	end)
	return ok and result or nil
end

-- Item IDs this character caught (within the retention).
local function CaughtSet(log)
	local set = {}
	for _, c in ipairs(log.catches) do
		for itemID in pairs(c.items or {}) do
			set[itemID] = true
		end
	end
	return set
end

-- The caught item being opened: the locked bag slot holding a caught item that has loot.
local function OpenedContainer(log)
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return nil
	end
	local caught = CaughtSet(log)
	if next(caught) == nil then
		return nil
	end
	for bag = 0, ns.LAST_BAG or 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and Safe(info.isLocked) and Safe(info.hasLoot) and caught[Safe(info.itemID)] then
				return info.itemID
			end
		end
	end
end

local function OnOpened(_, _, isFromItem)
	if not captured then
		F.Capture()
	end
	local items = pending
	pending = nil
	if not (items and Safe(isFromItem) == true) then
		return
	end
	pcall(function()
		local log = F.Log()
		local container = log and OpenedContainer(log)
		if container then
			log.opened[#log.opened + 1] = { t = time(), item = container, items = items }
		end
	end)
end

ns.On("LOOT_READY", function()
	F.Capture()
end)
ns.On("LOOT_OPENED", OnOpened)
ns.On("LOOT_CLOSED", function()
	captured, pending = false, nil
end)
ns.On("PLAYER_LOGIN", function()
	F.Prune()
end)

----------------------------------------------------------------------------------------------------
-- Values and summary
----------------------------------------------------------------------------------------------------

F.NO_PRICE = "no price data"

-- Mean value of what openings of this container gave, or nil, plus how many openings were priced.
local function ContentsValue(log, containerID, depth)
	local total, n = 0, 0
	for _, o in ipairs(log.opened) do
		if o.item == containerID then
			local sum, complete = 0, true
			for itemID, count in pairs(o.items or {}) do
				local unit = depth < 2 and F.UnitValue(log, itemID, depth + 1)
				if unit then
					sum = sum + unit.copper * count
				else
					complete = false
				end
			end
			if complete then
				total, n = total + sum, n + 1
			end
		end
	end
	if n == 0 then
		return nil
	end
	return math.floor(total / n), n
end

-- Value of one unit: { copper, label } or nil (no price data).
function F.UnitValue(log, itemID, depth)
	local value = ns.GetSellValue and ns.GetSellValue(itemID)
	if value and value.copper and value.copper > 0 then
		local label = value.label or value.source
		if value.cutUnverified then
			label = label .. ", cut unverified"
		end
		return { copper = math.floor(value.copper), label = label }
	end
	local copper, n = ContentsValue(log, itemID, depth or 0)
	if copper then
		return { copper = copper, label = ("contents of %d opened"):format(n) }
	end
	return nil
end

local function Lower(s)
	return s and s:lower() or ""
end

-- Per zone, per subzone: catches, count per item, value per catch. zoneFilter (case-insensitive, whole zone
-- or subzone name) limits it to one zone. Sorted by catches, most first.
-- { zones = { { zone, catches, value, unpriced, perCatch, subzones = { { sub, maps = {..}, catches,
--   items = { { itemID, count, unit = { copper, label } | nil } }, value, unpriced, perCatch } } } },
--   catches, days = F.KEEP_DAYS } ; unpriced = item units without a price (left out of value).
function F.Summary(zoneFilter, key)
	local log = F.Log(key)
	if not log then
		return nil
	end
	F.Prune()
	local filter = zoneFilter and zoneFilter ~= "" and Lower(zoneFilter) or nil
	local byZone, zones, total = {}, {}, 0
	for _, c in ipairs(log.catches) do
		local zoneName = c.zone or "?"
		if not filter or Lower(c.zone) == filter or Lower(c.sub) == filter then
			local z = byZone[zoneName]
			if not z then
				z = { zone = zoneName, catches = 0, bySub = {}, subzones = {} }
				byZone[zoneName] = z
				zones[#zones + 1] = z
			end
			local subName = c.sub or ""
			local s = z.bySub[subName]
			if not s then
				s = { sub = subName, catches = 0, counts = {}, maps = {}, mapSeen = {} }
				z.bySub[subName] = s
				z.subzones[#z.subzones + 1] = s
			end
			z.catches, s.catches, total = z.catches + 1, s.catches + 1, total + 1
			if c.map and not s.mapSeen[c.map] then
				s.mapSeen[c.map] = true
				s.maps[#s.maps + 1] = c.map
			end
			for itemID, count in pairs(c.items or {}) do
				s.counts[itemID] = (s.counts[itemID] or 0) + count
			end
		end
	end
	local units = {}
	local function unit(itemID)
		if units[itemID] == nil then
			units[itemID] = F.UnitValue(log, itemID) or false
		end
		return units[itemID] or nil
	end
	local function byCatches(a, b)
		if a.catches ~= b.catches then
			return a.catches > b.catches
		end
		return (a.zone or a.sub or "") < (b.zone or b.sub or "")
	end
	for _, z in ipairs(zones) do
		z.value, z.unpriced = 0, 0
		for _, s in ipairs(z.subzones) do
			s.items, s.value, s.unpriced = {}, 0, 0
			for itemID, count in pairs(s.counts) do
				local u = unit(itemID)
				s.items[#s.items + 1] = { itemID = itemID, count = count, unit = u }
				if u then
					s.value = s.value + u.copper * count
				else
					s.unpriced = s.unpriced + count
				end
			end
			table.sort(s.items, function(a, b)
				if a.count ~= b.count then
					return a.count > b.count
				end
				return a.itemID < b.itemID
			end)
			s.perCatch = math.floor(s.value / s.catches)
			z.value, z.unpriced = z.value + s.value, z.unpriced + s.unpriced
			s.counts, s.mapSeen = nil, nil
		end
		z.perCatch = math.floor(z.value / z.catches)
		table.sort(z.subzones, byCatches)
		z.bySub = nil
	end
	table.sort(zones, byCatches)
	return { zones = zones, catches = total, days = F.KEEP_DAYS, opened = #log.opened }
end

-- Per-zone summary for the character snapshot (#63): plain data, no links.
function F.SnapshotSummary()
	local summary = F.Summary()
	if not summary then
		return nil, "fishing log not loaded"
	end
	local out = { days = summary.days, catches = summary.catches, containersOpened = summary.opened, zones = {} }
	for _, z in ipairs(summary.zones) do
		local zone = { zone = z.zone, catches = z.catches, valuePerCatch = z.perCatch, unpricedUnits = z.unpriced,
			subzones = {} }
		for _, s in ipairs(z.subzones) do
			local sub = { subzone = s.sub, maps = s.maps, catches = s.catches, valuePerCatch = s.perCatch,
				unpricedUnits = s.unpriced, items = {} }
			for _, item in ipairs(s.items) do
				sub.items[#sub.items + 1] = { itemID = item.itemID, name = ns.ItemInfoNow and (ns.ItemInfoNow(item.itemID)) or nil,
					count = item.count, unitValue = item.unit and item.unit.copper or nil,
					valueSource = item.unit and item.unit.label or F.NO_PRICE }
			end
			zone.subzones[#zone.subzones + 1] = sub
		end
		out.zones[#out.zones + 1] = zone
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- /craftwise fishing [zone]
----------------------------------------------------------------------------------------------------

local function Money(copper)
	return ns.FormatMoney and ns.FormatMoney(copper) or (tostring(copper) .. "c")
end

local function ValueText(value, unpriced)
	if value == 0 and unpriced > 0 then
		return F.NO_PRICE
	end
	local text = Money(value)
	if unpriced > 0 then
		text = text .. (" + %d without price"):format(unpriced)
	end
	return text
end

function F.Slash(arg)
	local summary = F.Summary(arg)
	if not summary then
		ns.Print("fishing log not loaded yet")
		return
	end
	if summary.catches == 0 then
		if arg and arg ~= "" then
			ns.Print(("No catches in %s in the last %d days."):format(arg, summary.days))
		else
			ns.Print(("No catches in the last %d days."):format(summary.days))
		end
		return
	end
	local ids, seen = {}, {}
	for _, z in ipairs(summary.zones) do
		for _, s in ipairs(z.subzones) do
			for _, item in ipairs(s.items) do
				if not seen[item.itemID] then
					seen[item.itemID] = true
					ids[#ids + 1] = item.itemID
				end
			end
		end
	end
	ns.WithItemNames(ids, function()
		ns.Print(("Fishing, last %d days: %d catches. Value per catch = best sell value (AH after cut or vendor)."):format(
			summary.days, summary.catches))
		for _, z in ipairs(summary.zones) do
			local perCatch = z.value == 0 and z.unpriced > 0 and F.NO_PRICE or Money(z.perCatch)
			ns.Print(("%s: %d catches, %s per catch"):format(z.zone, z.catches, perCatch))
			for _, s in ipairs(z.subzones) do
				local sPer = s.value == 0 and s.unpriced > 0 and F.NO_PRICE or Money(s.perCatch)
				ns.Print(("  %s: %d catches, %s per catch (total %s)"):format(s.sub ~= "" and s.sub or "(no subzone)", s.catches, sPer,
					ValueText(s.value, s.unpriced)))
				for _, item in ipairs(s.items) do
					local value = item.unit and ("%s each (%s)"):format(Money(item.unit.copper), item.unit.label) or F.NO_PRICE
					ns.Print(("    %s x%d - %s"):format(ns.ItemChatText(item.itemID), item.count, value))
				end
			end
		end
	end)
end
