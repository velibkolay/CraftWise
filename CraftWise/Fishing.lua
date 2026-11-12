-- Fishing log (issue #69): every catch with where it was caught, to compare fishing spots by value.
-- Issue #86 adds what each catch came from (pool or open water), pool names, pool sightings, the player's
-- position and Find Fish; the tables built from the log are in FishingTables.lua.
--
-- Recorded inside the loot flow before anything is looted: Loot.lua (#41) calls Fishing.Capture() first
-- thing on LOOT_READY, and this file listens to LOOT_READY itself for when fast auto-loot is off. Once per
-- loot window.
--   * Fishing loot: IsFishingLoot(), the check Blizzard's Forever LootFrame.lua makes on LOOT_OPENED. Every
--     item slot of the window is the catch: item ID and count, zone, subzone, map ID (C_Map.GetBestMapForUnit),
--     the player's position on that map (C_Map.GetPlayerMapPosition, percent, one decimal), time. Coins and
--     currency are not recorded (coin slots only give a localized text).
--   * Loot source: the GameObject GUID GetLootSourceInfo names for the window, kept as `obj` (its object ID)
--     and `spawn` (the GUID's last part, one per spawned object). The client has no "pool" flag, so the water
--     type is worked out from what the client shows, never from a list of IDs (F.Kinds below):
--       - `clk` = the object the player clicked to loot: UnitGUID("mouseover"), else the GUID of the world
--         object tooltip shown in the last 2 seconds, else UnitGUID("softinteract") (interact key). Source ==
--         clicked object (`same = true`): the loot came from what was clicked, the bobber: open water.
--       - source != clicked object, and the clicked object ID is known as the bobber: the source is a pool.
--       - the same source GUID in two catches: an object that outlived a cast, a pool.
--   * Object names: whenever the client shows a GameObject GUID together with a name (a world object tooltip
--     with a GUID, the mouseover or soft-interact unit). Stored, CraftWiseDB.fishObjects[objectID] = { name, t },
--     only for objects that were the source of a catch; names of other objects are kept for the session only,
--     until they become one (a pool hovered before it is fished).
--   * Pool sightings: a world object tooltip or soft-interact target that is a known pool (by object ID, or
--     by name when the client gives no GUID) is logged with the player's position and time, once per spawn
--     (or per name and place) every 10 minutes. Catches from a pool are sightings by themselves.
--   * Find Fish: spell 43308, named "Find Fish" in Blizzard's Forever UI (Blizzard_Minimap/Mainline/
--     Minimap.lua, TRACKING_SPELL_OVERRIDE_ATLAS). Known = C_SpellBook.IsSpellKnown; tracking = the entry of
--     the client's tracking list (C_Minimap.GetTrackingInfo) with that spellID is active. A catch made while
--     it was active has `ff = true`.
--   * Containers: a caught item that is opened later (LOOT_OPENED with isFromItem, the opened item is the locked
--     bag slot whose item has loot) logs its contents against the container's item ID. Only item IDs this
--     character caught count; another copy of the same item (bought, looted) can't be told apart.
--   * Each recorded catch and logged opening is passed to subscribers (F.Subscribe, #130): the farm tracker
--     counts fishing from these, so fishing is detected in this one place.
--
-- CraftWiseDB.fishing["<realm>-<name> <surname>"] (account-wide, per character), kept 90 days (Scout default, #69):
--   catches  = { { t, zone, sub, map, x, y, obj, spawn, clk, same, ff, items = { [itemID] = count } }, ... }
--   opened   = { { t, item = container itemID, items = { [itemID] = count } }, ... }
--   seen     = { { t, obj, spawn, name, zone, sub, map, x, y, how = "tooltip"|"mouseover"|"interact" }, ... }
--   findFish = { known, tracking, t }   as last read
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
-- Blizzard Forever UI, Blizzard_Minimap/Mainline/Minimap.lua: [43308] = "professions_tracking_fish", -- Find Fish
F.FIND_FISH = 43308
F.SEEN_EVERY = 600 -- seconds: one sighting per pool spawn (or name and place) in this time
F.SEEN_MAX = 1000 -- sightings kept per character, newest
F.CLICK_WINDOW = 2 -- seconds: a world object tooltip this recent counts as the clicked object

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
		log = { catches = {}, opened = {}, seen = {} }
		ns.db.fishing[key] = log
	end
	log.seen = log.seen or {}
	return log
end

-- Object names, account-wide: [objectID] = { name, t }.
function F.Objects()
	if not ns.db then
		return {}
	end
	ns.db.fishObjects = ns.db.fishObjects or {}
	return ns.db.fishObjects
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
		log.seen = PruneList(log.seen or {}, cutoff)
	end
	F.kinds = nil
end

----------------------------------------------------------------------------------------------------
-- What the client shows: loot source, clicked object, position, object names
----------------------------------------------------------------------------------------------------

local function ItemIDOf(link)
	link = Text(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Items of the open loot window: { [itemID] = count }, whether any slot had one, and whether a slot holds
-- coin (GetLootSlotInfo's isCoin; the amount is only a localized text, so not read).
local function ReadSlots()
	local items, any, coin = {}, false, false
	if not (GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then
		return items, any, coin
	end
	for slot = 1, Safe(GetNumLootItems()) or 0 do
		local itemID = ItemIDOf(GetLootSlotLink(slot))
		local _, _, quantity, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
		quantity, currencyID, isCoin = Safe(quantity), Safe(currencyID), Safe(isCoin)
		if isCoin == true then
			coin = true
		elseif itemID and not currencyID then
			items[itemID] = (items[itemID] or 0) + math.max(1, tonumber(quantity) or 1)
			any = true
		end
	end
	return items, any, coin
end

-- A GameObject GUID: guid, object ID, spawn (the GUID's last part). Anything else: nil.
local function ObjectGUID(guid)
	guid = Text(guid)
	if not (guid and ns.Sources and ns.Sources.ParseGUID) then
		return nil
	end
	local kind, id = ns.Sources.ParseGUID(guid)
	if kind ~= "GameObject" then
		return nil
	end
	return guid, id, guid:match("%-(%x+)$")
end
F.ObjectGUID = ObjectGUID

-- GUID of the window's loot source, when the client names a GameObject.
local function SourceGUID()
	if not GetLootSourceInfo then
		return nil
	end
	local ok, guid = pcall(GetLootSourceInfo, 1)
	if not ok then
		return nil
	end
	return ObjectGUID(guid)
end

-- A unit token that points at a GameObject: guid, object ID, spawn, name.
local function UnitObject(unit)
	if not UnitGUID then
		return nil
	end
	local ok, guid = pcall(UnitGUID, unit)
	local g, id, spawn = ObjectGUID(ok and guid or nil)
	if not g then
		return nil
	end
	local okName, name = pcall(UnitName, unit)
	return g, id, spawn, okName and Text(name) or nil
end

local function Now()
	return GetTime and Safe(GetTime()) or time()
end

local lastTip -- { guid, name, at } of the last world object tooltip

-- The object the player clicked (or used the interact key on) to open this window: guid, object ID.
local function ClickedGUID()
	local guid, id = UnitObject("mouseover")
	if guid then
		return guid, id
	end
	if lastTip and lastTip.guid and Now() - lastTip.at <= F.CLICK_WINDOW then
		return lastTip.guid, lastTip.id
	end
	return UnitObject("softinteract")
end

local function Position(map)
	if not (map and C_Map and C_Map.GetPlayerMapPosition) then
		return nil
	end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	pos = ok and Safe(pos) or nil
	if type(pos) ~= "table" then
		return nil
	end
	local x, y = Safe(pos.x), Safe(pos.y)
	if (x == nil or y == nil) and pos.GetXY then
		x, y = pos:GetXY()
		x, y = Safe(x), Safe(y)
	end
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

local function Where()
	local zone = GetRealZoneText and Text(GetRealZoneText())
	-- "" = the client names no subzone here (kept, #78; nil only when the text isn't readable).
	local sub = GetSubZoneText and Safe(GetSubZoneText())
	sub = type(sub) == "string" and sub or nil
	local map = C_Map and C_Map.GetBestMapForUnit and Safe(C_Map.GetBestMapForUnit("player"))
	local x, y = Position(map)
	return zone, sub, map, x, y
end

local sessionNames = {} -- [objectID] = name shown this session, for objects that were no loot source (yet)

-- Remembers the name the client gives for a GameObject: stored for loot sources of catches, else for the session.
local function LearnName(id, name)
	name = Text(name)
	if not (id and name and ns.db) then
		return
	end
	local objects = F.Objects()
	local o = objects[id]
	if not o and not F.Kinds().sources[id] then
		sessionNames[id] = name
		return
	end
	if not o then
		objects[id] = { name = name, t = time() }
	elseif o.name ~= name then
		o.name, o.t = name, time()
	end
end

----------------------------------------------------------------------------------------------------
-- Find Fish (#86)
----------------------------------------------------------------------------------------------------

-- { known = bool|nil, tracking = bool|nil, inList = bool|nil }; nil = the client didn't say.
function F.FindFish()
	local known
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, v = pcall(C_SpellBook.IsSpellKnown, F.FIND_FISH)
		v = ok and Safe(v)
		if type(v) == "boolean" then
			known = v
		end
	end
	local tracking, inList
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
		n = ok and tonumber(Safe(n)) or 0
		tracking, inList = false, false
		for i = 1, n do
			local okInfo, info = pcall(C_Minimap.GetTrackingInfo, i)
			if okInfo and type(info) == "table" and Safe(info.spellID) == F.FIND_FISH then
				inList = true
				tracking = Safe(info.active) == true
			end
		end
	end
	return { known = known, tracking = tracking, inList = inList }
end

-- Reads Find Fish into this character's log (only once it has one: login must not create logs before the
-- character key migration, #77); returns what was read.
function F.ReadFindFish()
	local key = ns.db and ns.db.fishing and F.CharKey()
	local log = key and ns.db.fishing[key]
	if not log then
		return nil
	end
	local ok, ff = pcall(F.FindFish)
	if ok and ff then
		log.findFish = { known = ff.known, tracking = ff.tracking, t = time() }
		return log.findFish
	end
end

----------------------------------------------------------------------------------------------------
-- Catches
----------------------------------------------------------------------------------------------------

local captured = false -- this loot window was read
local pending -- items of a window that isn't fishing loot, until LOOT_OPENED says whether it came from an item
local pendingCoin -- that window had a coin slot

-- Subscribers (#130, the farm tracker): fn("catch", { catch = the stored catch, coin = window had coin }) right
-- after a catch is recorded, fn("opened", { item = container itemID, items, coin }) after an opening is logged.
-- Called inside the loot flow, so a subscriber's error never stops it: it is raised again on the next frame.
local subscribers = {}

function F.Subscribe(fn)
	subscribers[#subscribers + 1] = fn
end

local function Emit(kind, data)
	for _, fn in ipairs(subscribers) do
		local ok, err = pcall(fn, kind, data)
		if not ok and C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				error(err, 0)
			end)
		end
	end
end

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
	local hasCoin = false
	local ok, result = pcall(function()
		local items, any, coin = ReadSlots()
		if not any then
			return nil
		end
		if not IsFishing() then
			pending, pendingCoin = items, coin
			return nil
		end
		hasCoin = coin
		local log = F.Log()
		if not log then
			return nil
		end
		local zone, sub, map, x, y = Where()
		local catch = { t = time(), zone = zone, sub = sub, map = map, x = x, y = y, items = items }
		local src, obj, spawn = SourceGUID()
		catch.obj, catch.spawn = obj, spawn
		local clicked, clk = ClickedGUID()
		if src and clicked then
			catch.clk = clk
			catch.same = src == clicked or nil
		end
		local ff = F.ReadFindFish()
		catch.ff = ff and ff.tracking or nil
		log.catches[#log.catches + 1] = catch
		F.kinds = nil
		if obj and sessionNames[obj] then
			LearnName(obj, sessionNames[obj])
		end
		-- The source under the cursor (or the interact target) names itself.
		for _, unit in ipairs({ "mouseover", "softinteract" }) do
			local g, _, _, name = UnitObject(unit)
			if g and g == src then
				LearnName(obj, name)
			end
		end
		return catch
	end)
	if ok and result then
		Emit("catch", { catch = result, coin = hasCoin })
		return result
	end
	return nil
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
	local items, coin = pending, pendingCoin
	pending, pendingCoin = nil, nil
	if not (items and Safe(isFromItem) == true) then
		return
	end
	local ok, entry = pcall(function()
		local log = F.Log()
		local container = log and OpenedContainer(log)
		if container then
			local e = { t = time(), item = container, items = items }
			log.opened[#log.opened + 1] = e
			return e
		end
	end)
	if ok and entry then
		Emit("opened", { item = entry.item, items = entry.items, coin = coin or false })
	end
end

ns.On("LOOT_READY", function()
	F.Capture()
end)
ns.On("LOOT_OPENED", OnOpened)
ns.On("LOOT_CLOSED", function()
	captured, pending, pendingCoin = false, nil, nil
end)
ns.On("PLAYER_LOGIN", function()
	F.Prune()
	F.ReadFindFish()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
		and Enum.TooltipDataType.Object then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tooltip, data)
			pcall(F.OnObjectTooltip, tooltip, data)
		end)
	end
end)
for _, event in ipairs({ "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED" }) do
	ns.On(event, function()
		F.ReadFindFish()
	end)
end

----------------------------------------------------------------------------------------------------
-- Pool or open water (#86)
----------------------------------------------------------------------------------------------------

-- What each loot source object ID is, from all characters' catches (never from a list of IDs):
-- { kind = { [objID] = "open"|"pool" }, open = { [objID] = evidence }, pool = { [objID] = evidence },
--   sources = { [objID] = true } (every loot source of a catch) }.
-- Open-water evidence: a catch whose source was the clicked object (`same`). Pool evidence: every catch
-- after the first from one source GUID (it outlived a cast), and a catch whose clicked object is open water
-- while the source is another object. The kind is the side with more evidence; a tie leaves it unknown.
function F.Kinds()
	if F.kinds then
		return F.kinds
	end
	local open, pool, perGUID, sources = {}, {}, {}, {}
	local logs = ns.db and ns.db.fishing or {}
	for _, log in pairs(logs) do
		for _, c in ipairs(log.catches or {}) do
			if c.obj then
				sources[c.obj] = true
				if c.same then
					open[c.obj] = (open[c.obj] or 0) + 1
				end
				if c.spawn then
					local key = c.obj .. ":" .. c.spawn
					perGUID[key] = (perGUID[key] or 0) + 1
					if perGUID[key] > 1 then
						pool[c.obj] = (pool[c.obj] or 0) + 1
					end
				end
			end
		end
	end
	local function isOpen(id)
		return (open[id] or 0) > (pool[id] or 0)
	end
	local viaClick = {}
	for _, log in pairs(logs) do
		for _, c in ipairs(log.catches or {}) do
			if c.obj and c.clk and not c.same and c.clk ~= c.obj and isOpen(c.clk) then
				viaClick[c.obj] = (viaClick[c.obj] or 0) + 1
			end
		end
	end
	for id, n in pairs(viaClick) do
		pool[id] = (pool[id] or 0) + n
	end
	local kind = {}
	for _, list in ipairs({ open, pool }) do
		for id in pairs(list) do
			local o, p = open[id] or 0, pool[id] or 0
			kind[id] = o > p and "open" or p > o and "pool" or nil
		end
	end
	F.kinds = { kind = kind, open = open, pool = pool, sources = sources }
	return F.kinds
end

-- "open", "pool" or "?" (not known yet) for one catch.
function F.WaterOf(catch, kinds)
	kinds = kinds or F.Kinds()
	return catch.obj and kinds.kind[catch.obj] or "?"
end

-- Name of a loot source object as the client showed it, or nil.
function F.ObjectName(id)
	local o = id and F.Objects()[id]
	return o and o.name or nil
end

----------------------------------------------------------------------------------------------------
-- Pool sightings (#86)
----------------------------------------------------------------------------------------------------

local function Near(a, x, y)
	if not (a.x and a.y and x and y) then
		return a.x == x and a.y == y
	end
	return math.abs(a.x - x) <= 1 and math.abs(a.y - y) <= 1
end

-- An object the client shows (tooltip, mouseover, interact target). Learns its name; logs a sighting when it
-- is a known pool. id/spawn nil when the client gave a name only. Returns the sighting, if one was logged.
function F.Notice(id, spawn, name, how)
	name = Text(name)
	LearnName(id, name)
	local kinds = F.Kinds().kind
	if id then
		if kinds[id] ~= "pool" then
			return nil
		end
	else
		if not name then
			return nil
		end
		local found, count = nil, 0
		for objID, o in pairs(F.Objects()) do
			if o.name == name and kinds[objID] == "pool" then
				found, count = objID, count + 1
			end
		end
		if count == 0 then
			return nil
		end
		id = count == 1 and found or nil -- several pool objects share the name: name only
	end
	local log = F.Log()
	if not log then
		return nil
	end
	local zone, sub, map, x, y = Where()
	local now = time()
	for i = #log.seen, 1, -1 do
		local e = log.seen[i]
		if now - (e.t or 0) > F.SEEN_EVERY then
			break
		end
		if spawn and e.spawn == spawn and e.obj == id then
			return nil
		end
		if not spawn and not e.spawn and e.name == name and e.zone == zone and Near(e, x, y) then
			return nil
		end
	end
	local entry = { t = now, obj = id, spawn = spawn, name = name or F.ObjectName(id), zone = zone, sub = sub, map = map,
		x = x, y = y, how = how }
	log.seen[#log.seen + 1] = entry
	while #log.seen > F.SEEN_MAX do
		table.remove(log.seen, 1)
	end
	return entry
end

-- World object tooltip (TooltipDataProcessor post-call, Enum.TooltipDataType.Object): the first line is the
-- object's name. Its GUID comes from the tooltip data when the client fills `guid`, else from the mouseover
-- unit when that is a GameObject of the same name.
function F.OnObjectTooltip(_, data)
	if type(data) ~= "table" then
		return
	end
	local line = type(data.lines) == "table" and data.lines[1]
	local name = type(line) == "table" and Text(line.leftText) or nil
	local guid, id, spawn = ObjectGUID(data.guid)
	if not guid then
		local g, mid, mspawn, mname = UnitObject("mouseover")
		if g and (not name or mname == name) then
			guid, id, spawn = g, mid, mspawn
		end
	end
	lastTip = { guid = guid, id = id, name = name, at = Now() }
	F.Notice(id, spawn, name, "tooltip")
end

local function NoticeUnit(unit, how)
	pcall(function()
		local g, id, spawn, name = UnitObject(unit)
		if g then
			F.Notice(id, spawn, name, how)
		end
	end)
end

ns.On("PLAYER_SOFT_INTERACT_CHANGED", function()
	NoticeUnit("softinteract", "interact")
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function()
	NoticeUnit("mouseover", "mouseover")
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

-- Value of one unit: { copper, label, contents = true when valued by its logged contents } or nil (no price data).
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
		return { copper = copper, label = ("contents of %d opened"):format(n), contents = true }
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
