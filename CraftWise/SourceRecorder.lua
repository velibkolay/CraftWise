-- Records where recipes come from while you play (issue #37): merchants that sell a recipe item, recipe
-- items seen in a loot window, recipe items offered as quest rewards. Only what the game shows; nothing is
-- estimated (no drop chance: kills without a drop are not counted). Trainers are recorded by Trainer.lua.
--
-- Stored account-wide in CraftWiseDB.sources, keyed by the recipe ITEM ID (stable, exportable):
--   sources[itemID] = {
--     recipe = recipe spell ID, when known,
--     name = item name, when the client had it,
--     vendors = { [npcID] = { name, zone, sub, faction = "A"|"H", price = copper, costs = { { name, amount } },
--                             limited = stock shown, t = last seen } },
--     loot    = { ["Creature:<id>" | "GameObject:<id>"] = { name, zone, sub, n = times seen, t } },
--     quests  = { [questID] = { name, zone, faction = "A"|"H", choice = true if a choice, t } },
--   }
-- t is a Unix time. Merged() combines these with ns.SourceData: in-game recorded > Veli's manual entry >
-- QuestieDB (the last two live in ns.SourceData).
local _, ns = ...

local S = {}
ns.Sources = S

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

-- "Creature-0-3-0-0-1234-0000A1B2C3" -> "Creature", 1234. Items, players and pets give nil.
local KINDS = { Creature = "Creature", Vehicle = "Creature", GameObject = "GameObject" }
local function ParseGUID(guid)
	guid = Text(guid)
	if not guid then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	kind = kind and KINDS[kind]
	id = tonumber(id)
	if kind and id then
		return kind, id
	end
end
S.ParseGUID = ParseGUID

local function NpcFaction(unit)
	local group = UnitFactionGroup and Text(UnitFactionGroup(unit))
	return group == "Horde" and "H" or group == "Alliance" and "A" or nil
end

local function Where()
	local zone = GetRealZoneText and Text(GetRealZoneText())
	local sub = GetSubZoneText and Text(GetSubZoneText())
	return zone, sub
end

----------------------------------------------------------------------------------------------------
-- Item <-> recipe
----------------------------------------------------------------------------------------------------

local index, indexFor, byRecipe
local dirty = true

local function Sources()
	return ns.db and ns.db.sources
end

local function Rebuild()
	index, byRecipe, indexFor, dirty = {}, {}, ns.SourceData, false
	for recipeID, data in pairs(ns.SourceData or {}) do
		if data.item then
			index[data.item] = recipeID
		end
	end
	for itemID, rec in pairs(Sources() or {}) do
		local recipeID = index[itemID] or rec.recipe
		if recipeID then
			byRecipe[recipeID] = byRecipe[recipeID] or {}
			table.insert(byRecipe[recipeID], itemID)
		end
	end
	for _, list in pairs(byRecipe) do
		table.sort(list)
	end
end

local function EnsureIndex()
	if dirty or indexFor ~= ns.SourceData then
		Rebuild()
	end
end

local function RecipeClass()
	return (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
end

local function ItemIDOf(link)
	link = Text(link)
	if not (link and C_Item and C_Item.GetItemInfoInstant) then
		return nil
	end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
	return itemID, classID
end

-- Is this item a recipe (pattern, plans, formula, recipe, schematic)?
local function IsRecipeItem(itemID)
	if not itemID then
		return false
	end
	EnsureIndex()
	if index[itemID] then
		return true
	end
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	return classID == RecipeClass()
end

-- The recipe spell this item teaches: from the bundled data, else the item's spell when it is a known recipe.
local function ResolveRecipe(itemID)
	EnsureIndex()
	if index[itemID] then
		return index[itemID]
	end
	if C_Item and C_Item.GetItemSpell and ns.RecipeData then
		local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
		if ok and spellID and ns.RecipeData[spellID] then
			return spellID
		end
	end
end

-- Record for an item, created on first use. Returns the record and whether it is new.
local function Record(itemID)
	local all = Sources()
	local rec = all[itemID]
	if rec then
		return rec, false
	end
	rec = {}
	all[itemID] = rec
	local recipeID = ResolveRecipe(itemID)
	if recipeID and recipeID ~= index[itemID] then
		rec.recipe = recipeID
	end
	local name = C_Item.GetItemNameByID and Text(C_Item.GetItemNameByID(itemID))
	rec.name = name
	dirty = true
	return rec, true
end

local function Done(changed)
	if changed > 0 then
		dirty = true
		ns.Notify("RECIPES_CHANGED")
	end
	return changed
end

----------------------------------------------------------------------------------------------------
-- Merchants
----------------------------------------------------------------------------------------------------

local function MerchantInfo(index_)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index_)
		if info then
			return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
		end
		return nil
	end
	if GetMerchantItemInfo then
		local _, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(index_)
		return price, quantity, available, extended
	end
end

-- Non-gold costs shown on a merchant item: currencies and items, as { name, amount }.
local function ExtendedCosts(index_)
	local costs = {}
	local count = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index_) or 0
	for i = 1, count or 0 do
		local _, amount, link, currencyName = GetMerchantItemCostItem(index_, i)
		local name = Text(currencyName) or (Text(link) and link:match("%[(.-)%]"))
		if name and type(amount) == "number" and amount > 0 then
			costs[#costs + 1] = { name = name, amount = amount }
		end
	end
	return #costs > 0 and costs or nil
end

local function SameCosts(a, b)
	if (a == nil) ~= (b == nil) then
		return false
	end
	if not a then
		return true
	end
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i].name ~= b[i].name or a[i].amount ~= b[i].amount then
			return false
		end
	end
	return true
end

function S.RecordMerchant()
	if not (Sources() and GetMerchantNumItems and GetMerchantItemID) then
		return 0
	end
	local kind, npcID = ParseGUID(UnitGUID and UnitGUID("npc"))
	if kind ~= "Creature" then
		return 0
	end
	local npcName = Text(UnitName and UnitName("npc"))
	local zone, sub = Where()
	local faction = NpcFaction("npc")
	local changed = 0
	for i = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(i)
		if IsRecipeItem(itemID) then
			local price, stack, available, extended = MerchantInfo(i)
			local copper = type(price) == "number" and price > 0 and math.floor(price / math.max(stack or 1, 1) + 0.5) or nil
			local costs = extended and ExtendedCosts(i) or nil
			local limited = type(available) == "number" and available > 0 and available or nil
			local rec, isNew = Record(itemID)
			rec.vendors = rec.vendors or {}
			local entry = rec.vendors[npcID]
			if not entry then
				entry = {}
				rec.vendors[npcID] = entry
				isNew = true
			end
			if isNew or entry.price ~= copper or entry.limited ~= limited or not SameCosts(entry.costs, costs)
				or (entry.name == nil and npcName ~= nil) then
				changed = changed + 1
			end
			entry.name = npcName or entry.name
			entry.zone, entry.sub = zone or entry.zone, sub or entry.sub
			entry.faction = faction or entry.faction
			entry.price, entry.costs, entry.limited = copper, costs, limited
			entry.t = time()
		end
	end
	return Done(changed)
end

----------------------------------------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------------------------------------

local counted = {} -- guid .. item seen this session: reopening one corpse's window counts once

local function SourceName(guid)
	for _, unit in ipairs({ "target", "mouseover", "focus" }) do
		if UnitGUID(unit) == guid then
			return Text(UnitName(unit))
		end
	end
end

function S.RecordLoot()
	if not (Sources() and GetNumLootItems and GetLootSlotLink and GetLootSourceInfo) then
		return 0
	end
	local zone, sub = Where()
	local changed = 0
	for slot = 1, GetNumLootItems() do
		local itemID = ItemIDOf(GetLootSlotLink(slot))
		if IsRecipeItem(itemID) then
			local sources = { GetLootSourceInfo(slot) }
			for i = 1, #sources, 2 do
				local guid = Text(sources[i])
				local kind, id = ParseGUID(guid)
				if kind and not counted[guid .. ":" .. itemID] then
					counted[guid .. ":" .. itemID] = true
					local rec = Record(itemID)
					rec.loot = rec.loot or {}
					local key = kind .. ":" .. id
					local entry = rec.loot[key]
					if not entry then
						entry = { n = 0 }
						rec.loot[key] = entry
					end
					entry.n = entry.n + 1
					entry.name = SourceName(guid) or entry.name
					entry.zone, entry.sub = zone or entry.zone, sub or entry.sub
					entry.t = time()
					changed = changed + 1
				end
			end
		end
	end
	return Done(changed)
end

----------------------------------------------------------------------------------------------------
-- Quest rewards
----------------------------------------------------------------------------------------------------

function S.RecordQuest()
	if not (Sources() and GetQuestID and GetQuestItemLink) then
		return 0
	end
	local questID = Safe(GetQuestID())
	if type(questID) ~= "number" or questID <= 0 then
		return 0
	end
	local title = GetTitleText and Text(GetTitleText())
	local zone = Where()
	local faction = NpcFaction("questnpc")
	local changed = 0
	for _, group in ipairs({ { "choice", GetNumQuestChoices }, { "reward", GetNumQuestRewards } }) do
		local count = group[2] and group[2]() or 0
		for i = 1, count do
			local itemID = ItemIDOf(GetQuestItemLink(group[1], i))
			if IsRecipeItem(itemID) then
				local rec = Record(itemID)
				rec.quests = rec.quests or {}
				local entry = rec.quests[questID]
				if not entry then
					entry = {}
					rec.quests[questID] = entry
					changed = changed + 1
				end
				entry.name = title or entry.name
				entry.zone = entry.zone or zone
				entry.faction = faction or entry.faction
				entry.choice = group[1] == "choice" or nil
				entry.t = time()
			end
		end
	end
	return Done(changed)
end

ns.On("MERCHANT_SHOW", S.RecordMerchant)
ns.On("MERCHANT_UPDATE", S.RecordMerchant)
ns.On("LOOT_OPENED", S.RecordLoot)
ns.On("QUEST_DETAIL", S.RecordQuest)
ns.On("QUEST_COMPLETE", S.RecordQuest)

----------------------------------------------------------------------------------------------------
-- Merge with the bundled data
----------------------------------------------------------------------------------------------------

local function FormatAge(seconds)
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return ("%dm ago"):format(math.floor(seconds / 60))
	elseif seconds < 2 * 86400 then
		return ("%dh ago"):format(math.floor(seconds / 3600))
	end
	return ("%dd ago"):format(math.floor(seconds / 86400))
end

-- "seen by you 2h ago" for a recorded line (seenAt = Unix time), else the static source's label
-- (an entry's own src, e.g. "QuestieDB", otherwise "bundled data").
function S.Label(entry)
	if entry.seen then
		return "seen by you " .. FormatAge(math.max(0, time() - entry.seen))
	end
	return entry.src or "bundled data"
end

local function Key(name)
	return name and name:lower() or nil
end

local function StaticList(list, replaced)
	local out = {}
	for _, e in ipairs(list or {}) do
		if not (e.name and replaced[Key(e.name)]) then
			out[#out + 1] = e
		end
	end
	return out
end

-- Recorded items for a recipe, or nil.
local function RecordedItems(recipeID)
	EnsureIndex()
	return byRecipe[recipeID]
end

-- Source data of a recipe in the ns.SourceData format, recorded lines first. Recorded lines carry seen = time;
-- a recorded vendor/loot/quest line replaces a bundled one of the same name. Without records this is the
-- bundled entry itself (or nil).
function S.Merged(recipeID)
	local static = ns.SourceData and ns.SourceData[recipeID]
	local items = Sources() and RecordedItems(recipeID)
	if not items then
		return static
	end
	local vendors, drops, quests = {}, {}, {}
	local seenVendor, seenDrop, seenQuest = {}, {}, {}
	for _, itemID in ipairs(items) do
		local rec = Sources()[itemID]
		for npcID, v in pairs(rec.vendors or {}) do
			local line = { name = v.name, zone = v.zone, faction = v.faction, price = v.price, costs = v.costs,
				limited = v.limited, seen = v.t, id = npcID }
			vendors[#vendors + 1] = line
			if v.name then
				seenVendor[Key(v.name)] = true
			end
		end
		for key, l in pairs(rec.loot or {}) do
			drops[#drops + 1] = { name = l.name, zone = l.zone, count = l.n, seen = l.t, key = key }
			if l.name then
				seenDrop[Key(l.name)] = true
			end
		end
		for questID, q in pairs(rec.quests or {}) do
			quests[#quests + 1] = { name = q.name, faction = q.faction, zone = q.zone, seen = q.t, id = questID }
			if q.name then
				seenQuest[Key(q.name)] = true
			end
		end
	end
	local function newest(a, b)
		return (a.seen or 0) > (b.seen or 0)
	end
	table.sort(vendors, newest)
	table.sort(drops, newest)
	table.sort(quests, newest)
	for _, e in ipairs(StaticList(static and static.vendors, seenVendor)) do
		vendors[#vendors + 1] = e
	end
	for _, e in ipairs(StaticList(static and static.drops, seenDrop)) do
		drops[#drops + 1] = e
	end
	for _, e in ipairs(StaticList(static and static.quests, seenQuest)) do
		quests[#quests + 1] = e
	end
	local merged = {}
	for k, v in pairs(static or {}) do
		merged[k] = v
	end
	merged.item = merged.item or items[1]
	merged.vendors = #vendors > 0 and vendors or nil
	merged.drops = #drops > 0 and drops or nil
	merged.quests = #quests > 0 and quests or nil
	return merged
end

-- Number of items with records, for diagnostics.
function S.Count()
	local n = 0
	for _ in pairs(Sources() or {}) do
		n = n + 1
	end
	return n
end
