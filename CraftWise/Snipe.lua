-- The snipe list (#315, part 2): items Veli wants to buy when they are listed cheap, each with a max price per
-- unit he types himself and an optional "buy up to N". Saved per account in ns.db.snipe, editable and removable.
--   * His typed max price always wins: a flip line (default max = vendor price - 1c) or a basket line (default
--     no max) of an item on the list gets his max, and his "up to N" when he set one (Merge).
--   * "At or below" is allowed: a unit priced exactly at the max qualifies.
--   * After a scan or a search the items on the list that are listed at or below the max are counted for the
--     toast (Finds, Loops.RunSnipes). Nothing is bought here; the buying is AHBuy.lua's, from a click or a key.
-- Pure parts (ParsePrice, PriceText, Merge, Finds) take plain data so the specs can feed them.
local _, ns = ...

local Snipe = {}
ns.Snipe = Snipe

Snipe.UPTO = 20 -- default "buy up to" for a snipe without a line of its own (provisional, #315)
Snipe.MAX_UPTO = 1000
Snipe.MAX_ENTRIES = 60

local function Store()
	if not ns.db then
		return {}
	end
	ns.db.snipe = ns.db.snipe or {}
	return ns.db.snipe
end

-- The list, in the order it was added: { { itemID, max (copper per unit), upTo (units or nil) } }.
function Snipe.Entries()
	return Store()
end

function Snipe.Find(itemID)
	for i, e in ipairs(Store()) do
		if e.itemID == itemID then
			return e, i
		end
	end
end

local function Changed(itemID)
	ns.Notify("SNIPE_CHANGED", itemID)
end

-- Adds an item or changes its max price and limit. Returns true, or false and why. max is copper per unit
-- (a whole number above 0); upTo nil (no limit of his own) or a whole number from 1.
function Snipe.Set(itemID, max, upTo)
	itemID = tonumber(itemID)
	if not itemID or itemID < 1 or itemID ~= math.floor(itemID) then
		return false, "Not an item"
	end
	max = tonumber(max)
	if not max or max < 1 or max ~= math.floor(max) then
		return false, "Type a max price per unit above 0"
	end
	if upTo ~= nil then
		upTo = tonumber(upTo)
		if not upTo or upTo < 1 or upTo ~= math.floor(upTo) or upTo > Snipe.MAX_UPTO then
			return false, "Buy up to: a whole number from 1 to " .. Snipe.MAX_UPTO
		end
	end
	local list = Store()
	local e = Snipe.Find(itemID)
	if not e then
		if #list >= Snipe.MAX_ENTRIES then
			return false, "The snipe list is full"
		end
		e = { itemID = itemID }
		list[#list + 1] = e
	end
	e.max, e.upTo = max, upTo
	Changed(itemID)
	return true
end

function Snipe.Remove(itemID)
	local _, i = Snipe.Find(itemID)
	if i then
		table.remove(Store(), i)
		Changed(itemID)
		return true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Typed prices and items
----------------------------------------------------------------------------------------------------

local MULT = { g = 10000, s = 100, c = 1 }

-- "3g 40s 5c", "40s", "12c", "3.5g" or a bare "3" (gold) -> copper; nil, why when it is not a price above 0.
function Snipe.ParsePrice(text)
	text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil, "Type a max price per unit"
	end
	local copper
	if text:match("^%d+%.?%d*$") then
		copper = math.floor(tonumber(text) * MULT.g + 0.5)
	else
		local rest = text
		copper = 0
		local seen = {}
		for number, unit in text:gmatch("(%d+%.?%d*)%s*([gsc])") do
			if seen[unit] then
				return nil, "Use each of g, s and c once"
			end
			seen[unit] = true
			copper = copper + math.floor(tonumber(number) * MULT[unit] + 0.5)
		end
		rest = rest:gsub("%d+%.?%d*%s*[gsc]", ""):gsub("%s+", "")
		if rest ~= "" or next(seen) == nil then
			return nil, "Write the price like 3g 40s 5c"
		end
	end
	if copper < 1 then
		return nil, "Type a max price per unit above 0"
	end
	return copper
end

-- The price as the text box shows it: "3g 40s 5c" (parts that are 0 left out).
function Snipe.PriceText(copper)
	copper = math.floor(tonumber(copper) or 0)
	local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end

-- The item a typed text means: an item link, an item ID, or a name the client knows. nil when it is none.
function Snipe.ItemFromText(text)
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end
	local id = text:match("item:(%d+)") or text:match("^(%d+)$")
	if id then
		return tonumber(id)
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local found = C_Item.GetItemInfoInstant(text)
		if found then
			return tonumber(found)
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Lines and finds
----------------------------------------------------------------------------------------------------

-- The buying lines with the snipe list in: lines = AHBuy.Lines() before this ({ kind, itemID, need, maxUnit,
-- sell }). Items on the list first, in list order: a flip or basket line of one keeps its kind but takes his
-- max price (and his limit when he set one); an item without a line gets a "snipe" line. The other lines follow.
function Snipe.Merge(lines)
	local entries = Snipe.Entries()
	if #entries == 0 then
		return lines
	end
	local first, rest, used = {}, {}, {}
	for _, e in ipairs(entries) do
		local any = false
		for i, l in ipairs(lines) do
			if l.itemID == e.itemID then
				any, used[i] = true, true
				local copy = {}
				for k, v in pairs(l) do
					copy[k] = v
				end
				copy.maxUnit, copy.snipe = e.max, true
				copy.need = e.upTo or l.need
				first[#first + 1] = copy
			end
		end
		if not any then
			first[#first + 1] = { kind = "snipe", itemID = e.itemID, need = e.upTo or Snipe.UPTO, maxUnit = e.max, snipe = true }
		end
	end
	for i, l in ipairs(lines) do
		if not used[i] then
			rest[#rest + 1] = l
		end
	end
	for _, l in ipairs(rest) do
		first[#first + 1] = l
	end
	return first
end

-- What the stored tiers say about the list: rows = Market.FreshBelow rows ({ itemID, t, total, tiers }) asked
-- with limit max + 1, so a unit exactly at the max is a find. Returns { { itemID, units, price, max, atLeast } }
-- in list order; units = the stored units priced at or below the max ("at least" when more may be listed).
function Snipe.Finds(rows)
	local out = {}
	local byItem = {}
	for _, r in ipairs(rows or {}) do
		byItem[r.itemID] = r
	end
	for _, e in ipairs(Snipe.Entries()) do
		local r = byItem[e.itemID]
		if r and r.tiers then
			local units, n = 0, 0
			for i = 1, #r.tiers, 2 do
				local price, qty = r.tiers[i], r.tiers[i + 1]
				if not (price and qty and price <= e.max) then
					break
				end
				units, n = units + qty, n + 1
			end
			if units > 0 then
				out[#out + 1] = { itemID = e.itemID, units = units, price = r.tiers[1], max = e.max, t = r.t,
					atLeast = n * 2 == #r.tiers and (#r.tiers >= 16 or units < (r.total or 0)) }
			end
		end
	end
	return out
end

-- The max price of an item on the list plus one (Market.FreshBelow asks for prices below a limit), else nil.
function Snipe.LimitOf(itemID)
	local e = Snipe.Find(itemID)
	return e and (e.max + 1) or nil
end
