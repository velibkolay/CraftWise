-- Issue #327: warn when the item picked into the sell frame expired unsold before. Read only.
local HORDE, BOOTY = "PvP|H", "PvP|N:BootyBay"
local ITEM = 2318

local function Setup()
	local ns, stub = LoadAddon()
	stub.names.player = "Veli"
	stub.surnames.player = "Tanner"
	stub.items[ITEM] = { name = "Light Leather", stack = 200 }
	AUCTION_DURATION_ONE = "12 Hours"
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	ns.Market.CurrentHouse = function() return HORDE end
	return ns, stub
end

local function Add(ns, rec)
	local list = ns.Auctions.List()
	rec.i, rec.h = rec.i or ITEM, rec.h or HORDE
	list[#list + 1] = rec
end

local function SellFrame()
	local f = CreateFrame("Frame")
	function f:SetItem(loc) self.itemLocation = loc end
	function f:GetItem() return self.itemLocation end
	return f
end

local function Tip()
	local t = CreateFrame("GameTooltip")
	t.lines, t.pairs = {}, {}
	function t:AddLine(text) table.insert(self.lines, text) end
	function t:AddDoubleLine(l, r) table.insert(self.pairs, { l, r }) end
	function t:Show() end
	return t
end

it("counts expired and returned-after-expiry, not gone, cancelled or other house/item", function()
	local ns = Setup()
	local A = ns.Auctions
	eq(A.ExpiredBefore(ITEM), nil)
	Add(ns, { st = "gone", expT = nil, t = 1000 })
	Add(ns, { st = "cancelled", t = 1000, cancelT = 1500 })
	Add(ns, { st = "expired", expT = 5000, t = 1000, h = BOOTY })
	Add(ns, { st = "expired", expT = 5000, t = 1000, i = 999 })
	Add(ns, { st = "expired", t = 1000 }) -- no expT
	eq(A.ExpiredBefore(ITEM), nil)
	Add(ns, { st = "expired", expT = 5000, t = 1000, unit = 120, q = 3, durText = "12 Hours" })
	eq(A.ExpiredBefore(ITEM).count, 1)
	Add(ns, { st = "returned", expT = 9000, t = 8000, unit = 150, q = 1, durText = "48 Hours" })
	local info = A.ExpiredBefore(ITEM)
	eq(info.count, 2)
	eq(info.latest.unit, 150) -- the most recent expiry
	local text = A.ExpiredWarn.Text(info, true)
	assert(text:find("48 Hours", 1, true), text)
	assert(text:find("and 1 more", 1, true), text)
end)

it("sell frame label: shown for an expired item, hidden for others, frame state untouched", function()
	local ns, stub = Setup()
	Add(ns, { st = "expired", expT = 5000, t = 1000, unit = 120, q = 3, durText = "12 Hours" })
	AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
	AuctionHouseFrame.ItemSellFrame, AuctionHouseFrame.CommoditiesSellFrame = SellFrame(), SellFrame()
	stub.Fire("AUCTION_HOUSE_SHOW")
	stub.Fire("AUCTION_HOUSE_SHOW")
	for _, f in ipairs({ AuctionHouseFrame.ItemSellFrame, AuctionHouseFrame.CommoditiesSellFrame }) do
		local label = ns.Auctions.ExpiredWarn.labels[f]
		assert(label, "label")
		f:SetItem({ itemID = ITEM })
		eq(label.shown, true)
		assert(label.text:find("Expired before", 1, true), label.text)
		assert(label.text:find("12 Hours", 1, true), label.text)
		f:SetItem({ itemID = 400 })
		eq(label.shown, false)
		f:SetItem({ itemID = ITEM })
		ns.db.settings.expiredWarn = false
		f:SetItem({ itemID = ITEM })
		eq(label.shown, false)
		ns.db.settings.expiredWarn = true
	end
	eq(AuctionHouseFrame.ItemSellFrame:GetItem().itemID, ITEM)
	AuctionHouseFrame = nil
end)

it("tooltip line: once per call, off with the setting, none away from a house", function()
	local ns = Setup()
	Add(ns, { st = "expired", expT = 5000, t = 1000, unit = 120, q = 1, durText = "12 Hours" })
	local t = Tip()
	assert(ns.AddTooltipLines(t, ITEM))
	local n = 0
	for _, p in ipairs(t.pairs) do if p[1] == "Expired before" then n = n + 1 end end
	eq(n, 1)
	ns.db.tooltip.lines.expired = false
	t = Tip()
	ns.AddTooltipLines(t, ITEM)
	for _, p in ipairs(t.pairs) do assert(p[1] ~= "Expired before", "line shown") end
	ns.db.tooltip.lines.expired = true
	ns.Market.CurrentHouse = function() return nil end
	t = Tip()
	ns.AddTooltipLines(t, ITEM)
	for _, p in ipairs(t.pairs) do assert(p[1] ~= "Expired before", "line shown") end
end)
