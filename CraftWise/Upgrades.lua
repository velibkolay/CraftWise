-- Upgrade advisor (issue #16): items you can craft (known recipes, or recipes you can learn now) that
-- beat what you wear. An upgrade is a higher item level, or the same item level with more armour
-- (decision on #16: no stat weights, they would be a guess). Rows show the total cost to obtain the
-- item (reagents, plus the learn cost for recipes you still have to learn), never a crafting profit.
-- Everything comes from the client: equipped items, item info, item stats and the item tooltip (red
-- lines = you can't use it); learn sources and costs from Recipes.lua (trainer, vendor, drop, AH).
local _, ns = ...

-- Equip location -> inventory slot names. Rings, trinkets and one-hand weapons fit two slots;
-- they are compared with the weaker of the two.
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { "HEADSLOT" },
	INVTYPE_NECK = { "NECKSLOT" },
	INVTYPE_SHOULDER = { "SHOULDERSLOT" },
	INVTYPE_BODY = { "SHIRTSLOT" },
	INVTYPE_CHEST = { "CHESTSLOT" },
	INVTYPE_ROBE = { "CHESTSLOT" },
	INVTYPE_WAIST = { "WAISTSLOT" },
	INVTYPE_LEGS = { "LEGSSLOT" },
	INVTYPE_FEET = { "FEETSLOT" },
	INVTYPE_WRIST = { "WRISTSLOT" },
	INVTYPE_HAND = { "HANDSSLOT" },
	INVTYPE_FINGER = { "FINGER0SLOT", "FINGER1SLOT" },
	INVTYPE_TRINKET = { "TRINKET0SLOT", "TRINKET1SLOT" },
	INVTYPE_CLOAK = { "BACKSLOT" },
	INVTYPE_WEAPON = { "MAINHANDSLOT", "SECONDARYHANDSLOT" },
	INVTYPE_2HWEAPON = { "MAINHANDSLOT" },
	INVTYPE_WEAPONMAINHAND = { "MAINHANDSLOT" },
	INVTYPE_WEAPONOFFHAND = { "SECONDARYHANDSLOT" },
	INVTYPE_SHIELD = { "SECONDARYHANDSLOT" },
	INVTYPE_HOLDABLE = { "SECONDARYHANDSLOT" },
	INVTYPE_RANGED = { "RANGEDSLOT", "MAINHANDSLOT" },
	INVTYPE_RANGEDRIGHT = { "RANGEDSLOT", "MAINHANDSLOT" },
	INVTYPE_THROWN = { "RANGEDSLOT" },
}
local SLOT_LABELS = {
	HEADSLOT = "Head", NECKSLOT = "Neck", SHOULDERSLOT = "Shoulder", SHIRTSLOT = "Shirt", CHESTSLOT = "Chest",
	WAISTSLOT = "Waist", LEGSSLOT = "Legs", FEETSLOT = "Feet", WRISTSLOT = "Wrist", HANDSSLOT = "Hands",
	FINGER0SLOT = "Ring", FINGER1SLOT = "Ring", TRINKET0SLOT = "Trinket", TRINKET1SLOT = "Trinket",
	BACKSLOT = "Back", MAINHANDSLOT = "Main hand", SECONDARYHANDSLOT = "Off hand", RANGEDSLOT = "Ranged",
}
ns.EQUIP_SLOTS, ns.SLOT_LABELS = EQUIP_SLOTS, SLOT_LABELS

local Upgrades = {}
ns.Upgrades = Upgrades

-- Forever (Mainline API) has no global GetItemInfo, only C_Item.GetItemInfo.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local ARMOR_STAT = "RESISTANCE0_NAME" -- GetItemStats key for armour

-- Main stats shown inline (#16, 2026-11-08): the base attributes, stamina last. No weights.
local MAIN_STATS = {
	{ key = "ITEM_MOD_STRENGTH_SHORT", short = "STR" },
	{ key = "ITEM_MOD_AGILITY_SHORT", short = "AGI" },
	{ key = "ITEM_MOD_INTELLECT_SHORT", short = "INT" },
	{ key = "ITEM_MOD_SPIRIT_SHORT", short = "SPI" },
	{ key = "ITEM_MOD_STAMINA_SHORT", short = "STA" },
}

-- "+3 AGI +2 STA" from GetItemStats. "" when the item has none of them, nil when its stats are unknown.
function Upgrades.MainStatsText(stats)
	if not stats then
		return nil
	end
	local parts = {}
	for _, s in ipairs(MAIN_STATS) do
		local v = stats[s.key]
		if v and v ~= 0 then
			parts[#parts + 1] = ("%s%d %s"):format(v > 0 and "+" or "", v, s.short)
		end
	end
	return table.concat(parts, " ")
end

local function SlotID(name)
	if not GetInventorySlotInfo then
		return nil
	end
	local ok, id = pcall(GetInventorySlotInfo, name)
	return ok and id or nil
end

local function ItemStats(linkOrID)
	if not linkOrID then
		return nil
	end
	local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
	if not fn then
		return nil
	end
	local link = linkOrID
	if type(link) == "number" then
		link = select(2, GetItemInfo(link))
		if not link then
			return nil
		end
	end
	local ok, stats = pcall(fn, link)
	return ok and stats or nil
end
ns.ItemStats = ItemStats

local function ItemLevel(linkOrID)
	if C_Item and C_Item.GetDetailedItemLevelInfo then
		local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, linkOrID)
		if ok and level then
			return level
		end
	end
	return GetItemInfo and select(4, GetItemInfo(linkOrID)) or nil
end

-- Can this character wear the item? The client's own check where it has one (armour and weapon
-- proficiency), then the item's tooltip, which marks what you can't use (armour type, level, skill) in red.
local function CanUse(itemID)
	if C_PlayerInfo and C_PlayerInfo.CanUseItem then
		local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
		if ok and usable == false then
			return false
		end
	end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return true
	end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
	if not ok or not data or not data.lines then
		return true
	end
	for _, line in ipairs(data.lines) do
		local c = line.leftColor
		if c and c.r and c.r > 0.9 and c.g < 0.25 and c.b < 0.25 then
			return false
		end
	end
	return true
end

-- What you wear in a slot: item ID, link, item level, armour. nil fields for an empty slot.
local function Equipped(slotName)
	local slot = SlotID(slotName)
	if not slot then
		return nil
	end
	local id = GetInventoryItemID and GetInventoryItemID("player", slot)
	local e = { slotName = slotName, slot = slot }
	if id then
		local link = GetInventoryItemLink and GetInventoryItemLink("player", slot) or select(2, GetItemInfo(id))
		local stats = ItemStats(link or id)
		e.itemID, e.link = id, link
		e.quality = select(3, GetItemInfo(link or id))
		e.level = ItemLevel(link or id)
		e.armor = stats and stats[ARMOR_STAT] or 0
		e.stats = stats
	end
	return e
end

local function Better(a, b) -- is equipped a weaker than b?
	if not a.itemID then
		return true
	end
	if not b.itemID then
		return false
	end
	if (a.level or 0) ~= (b.level or 0) then
		return (a.level or 0) < (b.level or 0)
	end
	return (a.armor or 0) < (b.armor or 0)
end

-- The equipped item this one would replace: the weaker one when it fits two slots.
local function Replaced(equipLoc)
	local names = EQUIP_SLOTS[equipLoc]
	if not names then
		return nil
	end
	local weakest
	for _, name in ipairs(names) do
		local e = Equipped(name)
		if e and (not weakest or Better(e, weakest)) then
			weakest = e
		end
	end
	return weakest
end

-- Items whose info the client is still loading; their rows appear once it arrives.
local waiting = {}
local function RequestItem(itemID)
	if waiting[itemID] then
		return
	end
	waiting[itemID] = true
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
end

-- Compares an item with what you wear in its slot. Returns the comparison, or nil when the item
-- doesn't fit a slot, isn't an upgrade by the #16 rule, or this character can't wear it now.
-- opts.level: item level when the caller knows it better (an AH row); opts.link: the item's link.
function Upgrades.Compare(itemID, opts)
	opts = opts or {}
	local equipLoc, icon
	if C_Item and C_Item.GetItemInfoInstant then
		equipLoc, icon = select(4, C_Item.GetItemInfoInstant(itemID))
	end
	if not EQUIP_SLOTS[equipLoc or ""] then
		return nil
	end
	local name, link, quality, _, minLevel = GetItemInfo(opts.link or itemID)
	if not name then
		RequestItem(itemID) -- level and requirements unknown until the client has the item
		return nil
	end
	local current = Replaced(equipLoc)
	if not current or itemID == current.itemID then
		return nil
	end
	link = opts.link or link
	local stats = ItemStats(link or itemID)
	local level = opts.level or ItemLevel(link or itemID) or 0
	local armor = stats and stats[ARMOR_STAT] or 0
	local ilvlGain = level - (current.level or 0)
	local armorGain = armor - (current.armor or 0)
	local upgrade = not current.itemID or ilvlGain > 0 or (ilvlGain == 0 and armorGain > 0)
	local myLevel = UnitLevel and UnitLevel("player") or 0
	if not upgrade or (minLevel or 0) > myLevel or not CanUse(itemID) then
		return nil
	end
	return {
		itemID = itemID, name = name, icon = icon, quality = quality, link = link,
		stats = stats, level = level, armor = armor, minLevel = minLevel,
		mainStats = Upgrades.MainStatsText(stats),
		slotLabel = SLOT_LABELS[current.slotName] or current.slotName,
		current = current, emptySlot = not current.itemID,
		equippedText = current.itemID and (GetItemInfo(current.itemID) or ("item " .. current.itemID)) or nil,
		currentStats = current.itemID and Upgrades.MainStatsText(current.stats) or nil,
		ilvlGain = ilvlGain, armorGain = armorGain,
		gain = current.itemID and (ilvlGain * 10000 + armorGain) or math.huge,
		dismissed = ns.db and ns.db.dismissed and ns.db.dismissed[itemID] or false,
	}
end

local function HaveReagents(reagents)
	if not reagents or #reagents == 0 then
		return false
	end
	local count = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not count then
		return false
	end
	for _, r in ipairs(reagents) do
		if (count(r.itemID) or 0) < r.quantity then
			return false
		end
	end
	return true
end

-- How a recipe you don't know can be learned now (decision on #16, 2026-11-09): from a trainer, a
-- vendor of your faction or a neutral one, a drop, or its recipe item on the AH. The required skill
-- must be known and met; a recipe whose requirement is unknown is left out (nothing is guessed).
-- Returns the RecipeWhere line it is learned from, or nil.
local LEARN_KINDS = { trainer = true, vendor = true, drop = true, auction = true }
function Upgrades.LearnRoute(row)
	if row.status == "known" or row.required == nil or row.tooLow then
		return nil
	end
	for _, line in ipairs(ns.RecipeWhere(row.recipeID)) do
		if LEARN_KINDS[line.kind] and (line.kind ~= "vendor" or line.own) then
			return line
		end
	end
	return nil
end

-- Total cost to obtain the item: reagents, plus the learn cost for a recipe you don't know yet.
-- Incomplete (shown "+?") when a reagent or the learn cost has no price.
local function ObtainCost(row, learnFirst)
	local total, complete = row.cost or 0, row.costComplete
	if learnFirst then
		if row.learnCost then
			total = total + row.learnCost
		else
			complete = false
		end
	end
	return total, complete
end

-- A known recipe beats a learnable one for the same item; between learnable ones the cheaper.
local function Preferred(a, b)
	if a.learnFirst ~= b.learnFirst then
		return not a.learnFirst
	end
	if a.costComplete ~= b.costComplete then
		return a.costComplete
	end
	return (a.cost or 0) < (b.cost or 0)
end

-- One row per item you can craft (known recipe, or one you can learn now) that beats what you wear
-- in its slot. Section "craft" of the Upgrades view.
function ns.UpgradeRows()
	local candidates, order = {}, {}
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for _, r in ipairs(ns.BuildRows(professionID, true, "upgrades")) do
			local itemID = not r.noItemOutput and r.outputItemID
			if itemID then
				local learnFirst = r.status ~= "known"
				local route = learnFirst and Upgrades.LearnRoute(r) or nil
				if not learnFirst or route then
					local total, complete = ObtainCost(r, learnFirst)
					local c = { r = r, prof = prof, route = route, learnFirst = learnFirst, cost = total, costComplete = complete }
					if not candidates[itemID] then
						order[#order + 1] = itemID
						candidates[itemID] = c
					elseif Preferred(c, candidates[itemID]) then
						candidates[itemID] = c
					end
				end
			end
		end
	end
	local out = {}
	for _, itemID in ipairs(order) do
		local c = candidates[itemID]
		local row = Upgrades.Compare(itemID)
		if row then
			local r = c.r
			row.section = "craft"
			row.name = row.name or r.name or ("item " .. itemID)
			row.icon = row.icon or r.icon
			row.recipeID, row.recipeName, row.professionName = r.recipeID, r.name, c.prof.name
			row.reagents, row.reagentCost, row.reagentComplete = r.reagents, r.cost, r.costComplete
			row.paidFallbacks = r.paidFallbacks
			row.cost, row.costComplete = c.cost, c.costComplete
			row.haveReagents = HaveReagents(r.reagents)
			row.skillColor = r.skillColor
			row.learnFirst = c.learnFirst
			if c.learnFirst then
				row.learnCost, row.learnSource, row.learnLabel = r.learnCost, r.learnSource, r.learnLabel
				row.learnKind, row.learnText = c.route.kind, c.route.text
				row.required = r.required
			end
			out[#out + 1] = row
		end
	end
	return out
end

function ns.ToggleDismissed(itemID)
	if not ns.db then
		return
	end
	ns.db.dismissed = ns.db.dismissed or {}
	ns.db.dismissed[itemID] = not ns.db.dismissed[itemID] or nil
	ns.Notify("UPGRADES_CHANGED")
end

ns.On("PLAYER_EQUIPMENT_CHANGED", function()
	ns.Notify("UPGRADES_CHANGED")
end)
ns.On("PLAYER_LEVEL_UP", function()
	ns.Notify("UPGRADES_CHANGED")
end)

-- Item info arrives in bursts; refresh once per burst, and only for items a row is waiting for.
local refreshQueued = false
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
	if not (itemID and waiting[itemID]) then
		return
	end
	waiting[itemID] = nil
	if refreshQueued then
		return
	end
	refreshQueued = true
	local function run()
		refreshQueued = false
		ns.Notify("UPGRADES_CHANGED")
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, run)
	else
		run()
	end
end)
