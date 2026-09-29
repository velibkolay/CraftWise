-- Price sources for the MVP:
--   buy side (reagents): cheapest of merchant price (recorded at vendors) and Auctionator
--   sell side (outputs): Auctionator price after the AH cut, or the vendor sell price
-- Own AH scan (C_AuctionHouse.ReplicateItems) is tracked in issue #6.
local addonName, ns = ...

ns.AH_CUT = 0.05

local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	return api and api.GetAuctionPriceByItemID and api
end

function ns.HasAuctionator()
	return AuctionatorAPI() ~= nil
end

-- Auctionator unit price in copper and its age in days (nil when unknown).
function ns.GetAuctionPrice(itemID)
	local api = AuctionatorAPI()
	if not api then
		return nil
	end
	local ok, copper = pcall(api.GetAuctionPriceByItemID, addonName, itemID)
	if not (ok and type(copper) == "number" and copper > 0) then
		return nil
	end
	local age
	if api.GetAuctionAgeByItemID then
		local okAge, days = pcall(api.GetAuctionAgeByItemID, addonName, itemID)
		age = okAge and type(days) == "number" and days or nil
	end
	return copper, age
end

-- Seen at a merchant beats the bundled list (Data/Vendor.lua), which is the base price.
function ns.GetVendorBuyPrice(itemID)
	local price = (ns.db and ns.db.vendor[itemID]) or (ns.VendorPrices and ns.VendorPrices[itemID])
	return price and price > 0 and price or nil
end

-- What a vendor pays for one unit (ItemSparse sell price). nil if the item isn't cached yet.
function ns.GetVendorSellPrice(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not getInfo then
		return nil
	end
	local sell = select(11, getInfo(itemID))
	if sell == nil then
		if C_Item and C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
		sell = ns.ItemSellPrices and ns.ItemSellPrices[itemID]
	end
	return sell
end

-- Cheapest way to obtain one unit: { copper, source = "vendor"|"auction", age }
function ns.GetBuyPrice(itemID)
	local vendor = ns.GetVendorBuyPrice(itemID)
	local ah, age = ns.GetAuctionPrice(itemID)
	if vendor and (not ah or vendor <= ah) then
		return { copper = vendor, source = "vendor" }
	elseif ah then
		return { copper = ah, source = "auction", age = age }
	end
	return nil
end

-- Best net value of one unit when selling: { copper, source = "auction"|"vendor", age }
-- AH value is after the AH cut; selling to a vendor is always possible, so the higher one wins.
function ns.GetSellValue(itemID)
	local ah, age = ns.GetAuctionPrice(itemID)
	local net = ah and ah * (1 - ns.AH_CUT)
	local vendor = ns.GetVendorSellPrice(itemID)
	if net and (not vendor or vendor == 0 or net >= vendor) then
		return { copper = net, source = "auction", age = age, gross = ah }
	elseif vendor and vendor > 0 then
		return { copper = vendor, source = "vendor" }
	end
	return nil
end

-- Record merchant prices so vendor reagents (thread, vials, dyes, flux) cost what vendors ask.
local function MerchantItem(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			return info.price, info.stackCount, info.hasExtendedCost
		end
		return nil
	end
	if GetMerchantItemInfo then
		local _, _, price, quantity, _, _, _, extendedCost = GetMerchantItemInfo(index)
		return price, quantity, extendedCost
	end
end

function ns.RecordMerchant()
	if not ns.db or not GetMerchantNumItems then
		return 0
	end
	local recorded = 0
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID and GetMerchantItemID(index)
		local price, quantity, extended = MerchantItem(index)
		if itemID and price and price > 0 and not extended then
			ns.db.vendor[itemID] = price / math.max(quantity or 1, 1)
			recorded = recorded + 1
		end
	end
	if recorded > 0 then
		ns.Notify("PRICES_CHANGED")
	end
	return recorded
end

ns.On("MERCHANT_SHOW", ns.RecordMerchant)
ns.On("MERCHANT_UPDATE", ns.RecordMerchant)
