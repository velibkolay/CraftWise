-- Physical bag sort (issue #12): moves stacks so the bags match the Bags view advice.
-- Order: items you keep (quest items, kept, reagents for your recipes) first, then free slots,
-- then items to sell at the end, best value first - so selling is a run of clicks on the last bag.
-- Only plain bags take part (profession bags and quivers keep their own contents).
-- One click starts it; each swap waits until the client has unlocked both slots. Combat, an item
-- on the cursor or a slot that stays locked stops it.
local _, ns = ...

local NUM_BAGS = 4
local LOCK_TIMEOUT = 3 -- seconds a swap may stay locked before giving up

local Sort = {}
ns.BagSort = Sort

local inCombat = false
local job -- { swaps, index, waitingSince, frame }

local function PlainBag(bag)
	if bag == 0 then
		return true
	end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	return family == 0
end

-- Current slots of the plain bags, each with what it holds and the group it belongs to.
function Sort.Slots()
	local slots = {}
	local info = {}
	for _, row in ipairs(ns.BagRows()) do
		info[row.itemID] = row
	end
	for bag = 0, NUM_BAGS do
		if PlainBag(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				local item = C_Container.GetContainerItemInfo(bag, slot)
				local entry = { bag = bag, slot = slot }
				if item and item.itemID then
					local row = info[item.itemID] or {}
					entry.itemID, entry.count, entry.locked = item.itemID, item.stackCount or 1, item.isLocked
					entry.keep = row.kept or row.reagent or row.questItem or row.ammo or not row.best or false
					entry.value = row.bestValue and row.count and row.count > 0 and row.bestValue / row.count or 0
					entry.name = row.name or ""
					if C_Item and C_Item.GetItemInfoInstant then
						local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(item.itemID)
						entry.class, entry.subClass = classID or 99, subClassID or 99
					end
					entry.junk = row.junk or false
					if entry.junk then
						entry.keep = false
					end
				end
				slots[#slots + 1] = entry
			end
		end
	end
	return slots
end

-- Order the stacks should end up in (pure: slots in, list of stacks out, empties as false).
function Sort.Target(slots)
	local keep, sell, empty = {}, {}, 0
	for _, s in ipairs(slots) do
		if not s.itemID then
			empty = empty + 1
		elseif s.keep then
			keep[#keep + 1] = s
		else
			sell[#sell + 1] = s
		end
	end
	-- By item class, then item ID: the same order every time, whether or not item names are loaded.
	table.sort(keep, function(a, b)
		if (a.class or 99) ~= (b.class or 99) then
			return (a.class or 99) < (b.class or 99)
		end
		if (a.subClass or 99) ~= (b.subClass or 99) then
			return (a.subClass or 99) < (b.subClass or 99)
		end
		if a.itemID ~= b.itemID then
			return a.itemID < b.itemID
		end
		return a.count > b.count
	end)
	table.sort(sell, function(a, b)
		if a.junk ~= b.junk then
			return b.junk -- junk at the very end, ready for "Sell junk"
		end
		local va, vb = a.value * a.count, b.value * b.count
		if va ~= vb then
			return va > vb
		end
		return a.itemID < b.itemID
	end)
	local target = {}
	for _, s in ipairs(keep) do target[#target + 1] = s end
	for _ = 1, empty do target[#target + 1] = false end
	for _, s in ipairs(sell) do target[#target + 1] = s end
	return target
end

-- Swaps (pairs of slot positions) that turn the current layout into the target one.
function Sort.Plan(slots)
	local target = Sort.Target(slots)
	local current = {}
	for i, s in ipairs(slots) do
		current[i] = s.itemID and { itemID = s.itemID, count = s.count } or false
	end
	-- Stacks of the same item count as equal: swapping them would merge them instead.
	local function same(a, b)
		if not a or not b then
			return not a and not b
		end
		return a.itemID == b.itemID
	end
	local swaps = {}
	for i = 1, #slots do
		local want = target[i] and { itemID = target[i].itemID, count = target[i].count } or false
		if not same(current[i], want) then
			for j = i + 1, #slots do
				if same(current[j], want) and not same(current[j], target[j] and target[j] or false) then
					swaps[#swaps + 1] = { from = slots[j], to = slots[i] }
					current[i], current[j] = current[j], current[i]
					break
				end
			end
		end
	end
	return swaps
end

local function Locked(s)
	local item = C_Container.GetContainerItemInfo(s.bag, s.slot)
	return item and item.isLocked
end

local function Finish(message)
	if job and job.frame then
		job.frame:SetScript("OnUpdate", nil)
	end
	job = nil
	if message then
		ns.Print(message)
	end
	ns.Notify("BAGS_CHANGED")
end

local function Step()
	if not job then
		return
	end
	if inCombat then
		return Finish("Bag sort stopped: combat.")
	end
	local swap = job.swaps[job.index]
	if not swap then
		return Finish(("Bags sorted (%d moves)."):format(#job.swaps))
	end
	if Locked(swap.from) or Locked(swap.to) then
		if GetTime() - job.waitingSince > LOCK_TIMEOUT then
			return Finish("Bag sort stopped: a slot stayed locked. Try again.")
		end
		return
	end
	if GetCursorInfo() then
		return Finish("Bag sort stopped: you are holding an item.")
	end
	C_Container.PickupContainerItem(swap.from.bag, swap.from.slot)
	C_Container.PickupContainerItem(swap.to.bag, swap.to.slot)
	if GetCursorInfo() then
		ClearCursor()
		return Finish("Bag sort stopped: a move didn't go through.")
	end
	job.index = job.index + 1
	job.waitingSince = GetTime()
end

-- Right after login the client hasn't loaded every item's data (sell price, name), which would
-- change the advice and so the order. Load them first, then sort.
local function Uncached()
	if not (C_Item and C_Item.IsItemDataCachedByID) then
		return 0
	end
	local missing = 0
	for bag = 0, NUM_BAGS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local item = C_Container.GetContainerItemInfo(bag, slot)
			if item and item.itemID and not C_Item.IsItemDataCachedByID(item.itemID) then
				missing = missing + 1
				C_Item.RequestLoadItemDataByID(item.itemID)
			end
		end
	end
	return missing
end

function Sort.Start(retry)
	if job then
		return false
	end
	if inCombat then
		ns.Print("Can't sort bags in combat.")
		return false
	end
	if Uncached() > 0 and (retry or 0) < 6 then
		if not retry then
			ns.Print("Loading item info, sorting in a moment...")
		end
		C_Timer.After(0.5, function()
			Sort.Start((retry or 0) + 1)
		end)
		return true
	end
	local swaps = Sort.Plan(Sort.Slots())
	if #swaps == 0 then
		ns.Print("Bags are already in order.")
		return false
	end
	job = { swaps = swaps, index = 1, waitingSince = GetTime() }
	job.frame = Sort.frame or CreateFrame("Frame")
	Sort.frame = job.frame
	job.frame:SetScript("OnUpdate", Step)
	Step()
	return true
end

function Sort.Running()
	return job ~= nil
end

ns.On("PLAYER_REGEN_DISABLED", function()
	inCombat = true
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	inCombat = false
end)
