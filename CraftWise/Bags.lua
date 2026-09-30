-- Bag advisor (issue #12): for every item in the bags, what vendoring, the AH and disenchanting pay,
-- and which is best. Disenchant values wait for a verified Forever disenchant table (#11); until then
-- ns.DisenchantValue returns nil and disenchantable items are only marked as such.
local _, ns = ...

local NUM_BAGS = 4 -- backpack (0) + four bag slots

local function ContainerItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		return C_Container.GetContainerItemInfo(bag, slot)
	end
end

local function NumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	return 0
end

-- Equippable armour or weapon of uncommon or rare quality: what an enchanter can disenchant.
local function CanDisenchant(itemID, quality)
	if not (quality == 2 or quality == 3) then
		return false
	end
	local classID
	if C_Item and C_Item.GetItemInfoInstant then
		classID = select(6, C_Item.GetItemInfoInstant(itemID))
	end
	return classID == 2 or classID == 4 -- Weapon, Armor
end

-- Expected disenchant value of one item: sum of chance x quantity x material price.
-- Needs ns.DisenchantData (verified Forever table, #11). nil until it exists.
function ns.DisenchantValue(itemID, quality)
	local table_ = ns.DisenchantData
	if not table_ then
		return nil
	end
	local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(itemID)
	local rows = table_.Lookup and table_.Lookup(quality, level)
	if not rows then
		return nil
	end
	local total = 0
	for _, r in ipairs(rows) do
		local price = ns.GetAuctionPrice(r.itemID)
		if not price then
			return nil -- a material without a price would understate the value
		end
		total = total + price * r.chance * r.quantity
	end
	return total
end

-- Item IDs used as reagents by recipes the character knows.
local function ReagentSet()
	local set = {}
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for _, recipe in pairs(prof.recipes) do
			if recipe.learned then
				for _, r in ipairs(recipe.reagents or {}) do
					set[r.itemID] = true
				end
			end
		end
	end
	return set
end

-- One row per item ID in the bags, stacks added up.
function ns.BagRows()
	local byItem, order = {}, {}
	for bag = 0, NUM_BAGS do
		for slot = 1, NumSlots(bag) do
			local info = ContainerItem(bag, slot)
			if info and info.itemID then
				local row = byItem[info.itemID]
				if not row then
					row = { itemID = info.itemID, count = 0, quality = info.quality, icon = info.iconFileID,
						link = info.hyperlink, bound = false, noValue = info.hasNoValue }
					byItem[info.itemID] = row
					order[#order + 1] = row
				end
				row.count = row.count + (info.stackCount or 1)
				row.bound = row.bound or info.isBound or false
			end
		end
	end

	local reagents = ReagentSet()
	for _, row in ipairs(order) do
		local id, n = row.itemID, row.count
		row.name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
			or (row.link and row.link:match("%[(.-)%]")) or ("item " .. id)

		local sell = not row.noValue and ns.GetVendorSellPrice(id) or nil
		row.vendorValue = sell and sell > 0 and sell * n or nil

		if not row.bound then
			local ah, age = ns.GetAuctionPrice(id)
			if ah then
				row.ahValue = ah * (1 - ns.AH_CUT) * n
				row.ahAge = age
			end
		end

		row.canDisenchant = CanDisenchant(id, row.quality)
		if row.canDisenchant then
			local de = ns.DisenchantValue(id, row.quality)
			row.deValue = de and de * n or nil
		end

		row.reagent = reagents[id] or false
		if C_Item and C_Item.GetItemInfoInstant then
			row.ammo = select(6, C_Item.GetItemInfoInstant(id)) == 6 -- Projectile
		end

		row.kept = ns.db and ns.db.keep[id] or false
		if row.kept then
			row.best, row.bestValue, row.margin = nil, nil, nil
		end

		-- Best option and how much more it pays than the next one (not for kept items).
		local options = {}
		if row.vendorValue then
			options[#options + 1] = { "vendor", row.vendorValue }
		end
		if row.ahValue then
			options[#options + 1] = { "auction", row.ahValue }
		end
		if row.deValue then
			options[#options + 1] = { "disenchant", row.deValue }
		end
		table.sort(options, function(a, b)
			return a[2] > b[2]
		end)
		if options[1] and not row.kept then
			row.best, row.bestValue = options[1][1], options[1][2]
			row.margin = options[2] and (options[1][2] - options[2][2]) or nil
		end
	end
	return order
end

function ns.ToggleKeep(itemID)
	if not ns.db then
		return
	end
	ns.db.keep[itemID] = not ns.db.keep[itemID] or nil
	ns.Notify("BAGS_CHANGED")
end

ns.On("BAG_UPDATE_DELAYED", function()
	ns.Notify("BAGS_CHANGED")
end)
