-- Send lists (issue #299, reusable for mail, #300): what to hand to another character in bulk. A list is
-- { { itemID, qty = nil | N } } (qty nil = every stack in the bags). Pure data and planning, no client
-- calls except reading the bags: UI/TradeFill.lua places stacks into the trade window on a click.
-- Stored account-wide:
--   db.send = {
--     work = list,                  the list being sent now ("To send")
--     lists = { [name] = list },    saved lists, e.g. "to Mac char"
--     partners = { [name] = listName },  the list to load when a trade opens with that character
--   }
local _, ns = ...

local S = {}
ns.SendList = S

S.MAX_ITEMS = 60
S.MAX_NAME = 40

local function Store()
	if not ns.db then
		return nil
	end
	local d = ns.db.send
	if not d then
		d = { work = {}, lists = {}, partners = {} }
		ns.db.send = d
	end
	d.work, d.lists, d.partners = d.work or {}, d.lists or {}, d.partners or {}
	return d
end

local function Changed(kind)
	ns.Notify("SEND_LIST_CHANGED", kind)
end

-- The working list (a table the caller must not keep: use the functions below to change it).
function S.Work()
	local d = Store()
	return d and d.work or {}
end

function S.Find(itemID)
	for i, e in ipairs(S.Work()) do
		if e.itemID == itemID then
			return e, i
		end
	end
end

-- Adds an item (or sets its quantity when it is on the list). qty nil or 0 = all stacks.
function S.Add(itemID, qty)
	local d = Store()
	if not (d and itemID) then
		return false
	end
	qty = qty and math.floor(qty) or nil
	if qty and qty < 1 then
		qty = nil
	end
	local e = S.Find(itemID)
	if e then
		e.qty = qty
	else
		if #d.work >= S.MAX_ITEMS then
			return false
		end
		d.work[#d.work + 1] = { itemID = itemID, qty = qty }
	end
	Changed()
	return true
end

function S.Remove(itemID)
	local _, i = S.Find(itemID)
	if i then
		table.remove(Store().work, i)
		Changed()
		return true
	end
	return false
end

-- Part of an entry went out (a trade completed): its quantity shrinks, and it leaves the list when none is
-- left. Entries for all stacks stay; they empty with the bags. Not a change the player made ("sent").
function S.Consume(itemID, n)
	local e, i = S.Find(itemID)
	if e and e.qty then
		e.qty = e.qty - n
		if e.qty <= 0 then
			table.remove(Store().work, i)
		end
		Changed("sent")
	end
end

function S.Clear()
	local d = Store()
	if d then
		d.work = {}
		Changed()
	end
end

local function Copy(list)
	local out = {}
	for _, e in ipairs(list) do
		out[#out + 1] = { itemID = e.itemID, qty = e.qty }
	end
	return out
end

-- Saved lists ------------------------------------------------------------------------------------------

local function CleanName(name)
	name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
	return name ~= "" and name:sub(1, S.MAX_NAME) or nil
end

function S.Names()
	local d, out = Store(), {}
	for name in pairs(d and d.lists or {}) do
		out[#out + 1] = name
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

function S.Get(name)
	local d = Store()
	return d and d.lists[name]
end

-- Saves the working list under a name (replacing one of that name). Returns the name, or nil for an empty
-- list or name.
function S.Save(name)
	local d = Store()
	name = CleanName(name)
	if not (d and name and #d.work > 0) then
		return nil
	end
	d.lists[name] = Copy(d.work)
	Changed()
	return name
end

-- Replaces the working list with a saved one.
function S.Load(name)
	local d = Store()
	local list = d and d.lists[name]
	if not list then
		return false
	end
	d.work = Copy(list)
	Changed()
	return true
end

function S.Delete(name)
	local d = Store()
	if d and d.lists[name] then
		d.lists[name] = nil
		for partner, listName in pairs(d.partners) do
			if listName == name then
				d.partners[partner] = nil
			end
		end
		Changed()
		return true
	end
	return false
end

-- The list to load when a trade opens with `partner` (a character name), when one was chosen.
function S.SetPartner(partner, name)
	local d = Store()
	if not (d and partner and partner ~= "") then
		return false
	end
	if name == nil then
		d.partners[partner] = nil
	elseif d.lists[name] then
		d.partners[partner] = name
	else
		return false
	end
	Changed()
	return true
end

function S.PartnerList(partner)
	local d = Store()
	local name = d and partner and d.partners[partner]
	return name and d.lists[name] and name or nil
end

-- Quick sources -------------------------------------------------------------------------------------------

-- The basket's materials (everything its crafts need), as quantities: not stacks, so a count is kept.
function S.AddBasket()
	local added = 0
	if ns.Basket and ns.Basket.Plan then
		for _, n in ipairs(ns.Basket.Plan().need or {}) do
			if S.Add(n.itemID, n.quantity) then
				added = added + 1
			end
		end
	end
	return added
end

-- Items marked Sell on AH that are in the bags, all stacks.
function S.AddSellAH()
	local added = 0
	local marked = ns.db and ns.db.sellAH or {}
	for _, itemID in ipairs(S.BagItems()) do
		if marked[itemID] and S.Add(itemID, nil) then
			added = added + 1
		end
	end
	return added
end

-- Bags ----------------------------------------------------------------------------------------------------

local function Info(bag, slot)
	return C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
end

-- Every stack in the bags: { bag, slot, itemID, count, bound, locked }.
function S.Stacks()
	local out = {}
	for bag = 0, ns.LAST_BAG or 4 do
		for slot = 1, (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0 do
			local info = Info(bag, slot)
			if info and info.itemID then
				out[#out + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = info.stackCount or 1,
					bound = info.isBound or false, locked = info.isLocked or false }
			end
		end
	end
	return out
end

-- Item IDs in the bags, once each, in bag order.
function S.BagItems()
	local seen, out = {}, {}
	for _, st in ipairs(S.Stacks()) do
		if not seen[st.itemID] then
			seen[st.itemID] = true
			out[#out + 1] = st.itemID
		end
	end
	return out
end

-- The plan for a list against the bags: units { bag, slot, itemID, count, take } in list order, largest
-- stacks first; take < count means the stack has to be split. Soulbound and locked stacks, and any in
-- `skip` ("bag:slot" = true, the ones already in the trade window), are left out: bound = how many
-- stacks of listed items were left out as bound. `short` = items whose wanted quantity the bags can't cover.
function S.Plan(list, skip)
	local units, short, bound = {}, {}, 0
	local stacks = S.Stacks()
	for _, e in ipairs(list or S.Work()) do
		local mine = {}
		for _, st in ipairs(stacks) do
			if st.itemID == e.itemID then
				if st.bound then
					bound = bound + 1
				elseif not st.locked and not (skip and skip[st.bag .. ":" .. st.slot]) then
					mine[#mine + 1] = st
				end
			end
		end
		table.sort(mine, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return (a.bag * 1000 + a.slot) < (b.bag * 1000 + b.slot)
		end)
		local left = e.qty
		for _, st in ipairs(mine) do
			if left and left <= 0 then
				break
			end
			local take = left and math.min(left, st.count) or st.count
			units[#units + 1] = { bag = st.bag, slot = st.slot, itemID = st.itemID, count = st.count, take = take }
			if left then
				left = left - take
			end
		end
		if left and left > 0 then
			short[#short + 1] = { itemID = e.itemID, missing = left }
		end
	end
	return units, short, bound
end
