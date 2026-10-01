-- Upgrade advisor (issue #16): items from recipes you know that beat what you wear.
-- An upgrade is a higher item level, or the same item level with more armour (decision on #16:
-- no stat weights, they would be a guess). Everything comes from the client: equipped items,
-- item info, item stats and the item tooltip (red lines = you can't use it).
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

-- Forever (Mainline API) has no global GetItemInfo, only C_Item.GetItemInfo.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local ARMOR_STAT = "RESISTANCE0_NAME" -- GetItemStats key for armour

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

-- The item's tooltip marks what you can't use (armour type, level, skill) in red.
local function CanUse(itemID)
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

-- One row per known recipe whose item beats what you wear in its slot.
function ns.UpgradeRows()
	local out = {}
	local prices = { buy = ns.GetBuyPrice, sell = ns.GetSellValue }
	local myLevel = UnitLevel and UnitLevel("player") or 0
	local seen = {}
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for recipeID, recipe in pairs(prof.recipes) do
			local itemID = recipe.learned and recipe.output and recipe.output.itemID
			if itemID and not seen[itemID] then
				local equipLoc, icon
				if C_Item and C_Item.GetItemInfoInstant then
					equipLoc, icon = select(4, C_Item.GetItemInfoInstant(itemID))
				end
				local current = EQUIP_SLOTS[equipLoc or ""] and Replaced(equipLoc)
				if current then
					local name, link, quality, _, minLevel = GetItemInfo(itemID)
					local stats = ItemStats(link or itemID)
					local level = ItemLevel(link or itemID) or 0
					local armor = stats and stats[ARMOR_STAT] or 0
					local ilvlGain = level - (current.level or 0)
					local armorGain = armor - (current.armor or 0)
					local upgrade = not current.itemID or ilvlGain > 0 or (ilvlGain == 0 and armorGain > 0)
					if upgrade and (minLevel or 0) <= myLevel and CanUse(itemID) and itemID ~= current.itemID then
						seen[itemID] = true
						local eval = ns.Profit.Evaluate({ reagents = recipe.reagents, output = recipe.output, learned = true }, prices)
						out[#out + 1] = {
							itemID = itemID, recipeID = recipeID, name = name or recipe.name or ("item " .. itemID),
							icon = icon or recipe.icon, quality = quality,
							link = link, stats = stats, level = level, armor = armor,
							slotLabel = SLOT_LABELS[current.slotName] or current.slotName,
							current = current, emptySlot = not current.itemID,
							equippedText = current.itemID and (GetItemInfo(current.itemID) or ("item " .. current.itemID)) or nil,
							ilvlGain = ilvlGain, armorGain = armorGain,
							gain = current.itemID and (ilvlGain * 10000 + armorGain) or math.huge,
							cost = eval.cost, costComplete = eval.costComplete, reagents = eval.reagents,
							haveReagents = HaveReagents(recipe.reagents),
							recipeName = recipe.name, professionName = prof.name,
							skillColor = ns.SkillUpColor(recipe, false),
							dismissed = ns.db and ns.db.dismissed and ns.db.dismissed[itemID] or false,
						}
					end
				end
			end
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
