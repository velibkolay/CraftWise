-- Records window, Auctions tab (`/craftwise auctions`, #26 phase 3): your listings, sales awaiting mail,
-- returns and uncertain outcomes, with the gold on its way and what the listings bring if all sell.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local C = ns.Style.colors
local Money, Muted = RW.Money, RW.Muted

local tab = { key = "auctions", label = L["Auctions"] }

tab.columns = {
	{ key = "name", label = L["ITEM"], width = 230 },
	{ key = "status", label = L["STATUS"], width = 140 },
	{ key = "qty", label = L["QTY"], width = 45, align = "RIGHT" },
	{ key = "house", label = L["HOUSE"], width = 95 },
	{ key = "gold", label = L["GOLD"], width = 120, align = "RIGHT" },
	{ key = "when", label = L["WHEN"], width = 100, align = "RIGHT" },
}

local STATUS_COLOR = { active = C.info, sold = C.good, expired = C.warn, cancelled = C.warn, gone = C.muted }

local function Row(row, now)
	local cells = { qty = tostring(row.q or 0), house = row.houseLabel or Muted("?") }
	local tip = {}
	cells.status = (STATUS_COLOR[row.status] or "") .. (row.statusText or row.status or "?") .. "|r"
	if row.status == "active" then
		cells.gold = row.unitBuyout and (Money(row.unitBuyout) .. Muted(" " .. L["each"])) or Muted(L["no buyout"])
		if row.overdue then
			cells.when = C.warn .. L["time is up"] .. "|r"
			tip[#tip + 1] = L["Time is up, outcome not seen yet."]
		elseif row.expires then
			cells.when = Muted(L["ends in"] .. " ") .. (RW.Ago(now, row.expires) or "?")
		end
		if row.unitBid then
			tip[#tip + 1] = { L["Bid"], Money(row.unitBid) .. " " .. L["each"] }
		end
		if row.deposit then
			tip[#tip + 1] = { L["Deposit"], Money(row.deposit) }
		end
	elseif row.status == "sold" then
		cells.gold = row.expected and Money(row.expected) or Muted(L["unknown"])
		tip[#tip + 1] = row.expected and { L["Expected"], Money(row.expected) .. " " .. L["after"] .. " " .. tostring(row.expectedNote) }
			or (L["Expected unknown:"] .. " " .. tostring(row.expectedNote))
		if row.unitsSold then
			tip[#tip + 1] = { L["Units sold"], tostring(row.unitsSold) }
		end
		cells.when = row.soldAt and (RW.Ago(row.soldAt, now) .. Muted(" " .. L["ago"])) or Muted("-")
	else
		cells.gold = Muted("-")
		local t = row.at or row.posted
		cells.when = t and (RW.Ago(t, now) .. Muted(" " .. L["ago"])) or Muted("-")
	end
	if row.uncertain then
		tip[#tip + 1] = row.uncertain
	end
	if row.posted then
		tip[#tip + 1] = { L["Posted"], date("%m-%d %H:%M", row.posted) }
	end
	local name = row.item and RW.ItemText(row.item, { name = row.name }) or (row.name or L["unknown item"])
	return { itemID = row.item, icon = RW.ItemIcon(row.item), name = name, cells = cells, tip = tip }
end

function tab.Model()
	local A = ns.Auctions
	local s = A and A.Summary()
	if not s then
		return { rows = {}, summary = Muted(L["Nothing recorded for this character yet."]),
			empty = L["Post an auction (Blizzard's auction house or another addon) and it shows here."] }
	end
	local now = time()
	local rows, ids = {}, {}
	for _, list in ipairs({ s.active, s.sold, s.returning, s.uncertain }) do
		for _, row in ipairs(list) do
			rows[#rows + 1] = Row(row, now)
			if row.item then
				ids[#ids + 1] = row.item
			end
		end
	end
	RW.LoadNames(ids)
	local line1 = ("|cffffffff%s|r  ·  %d %s  ·  %d %s  ·  %d %s  ·  %d %s"):format(L["Auctions"], #s.active, L["listed"],
		#s.sold, L["sold, awaiting mail"], #s.returning, L["returning by mail"], #s.uncertain, L["uncertain"])
	local onWay = L["On its way:"] .. " " .. Money(s.expectedTotal)
	if s.expectedMissing > 0 then
		onWay = onWay .. Muted((" " .. L["plus %d with unknown payout"]):format(s.expectedMissing))
	end
	local parts = { onWay }
	if #s.active > 0 then
		local listed = s.listedCounted > 0 and (Money(s.listedTotal) .. Muted(" " .. L["after"] .. " " .. tostring(s.listedNote)))
			or Muted(L["unknown"])
		local left = {}
		if s.listedNoBuyout > 0 then
			left[#left + 1] = ("%d %s"):format(s.listedNoBuyout, L["without buyout"])
		end
		if s.listedUnknownCut > 0 then
			left[#left + 1] = ("%d %s"):format(s.listedUnknownCut, L["with cut unverified"])
		end
		if s.listedUnpriced > 0 then
			left[#left + 1] = ("%d %s"):format(s.listedUnpriced, L["with price not recorded"])
		end
		if #left > 0 then
			listed = listed .. Muted(" (" .. L["not counted:"] .. " " .. table.concat(left, ", ") .. ")")
		end
		parts[#parts + 1] = L["If all listed sell:"] .. " " .. listed
	end
	if s.ownedListAt then
		parts[#parts + 1] = Muted(L["owned list read"] .. " " .. (RW.Ago(s.ownedListAt, now) or "?") .. " " .. L["ago"]
			.. (s.ownedListHouse and (" " .. L["at"] .. " " .. (ns.Market and ns.Market.HouseLabel(s.ownedListHouse) or s.ownedListHouse)) or ""))
	end
	return { rows = rows, summary = line1 .. "\n" .. table.concat(parts, "  ·  "),
		empty = L["No auction listed, sold or returning."] }
end

RW.Register(tab)
RW.Auctions = tab
