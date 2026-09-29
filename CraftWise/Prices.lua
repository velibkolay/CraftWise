-- Price source for the MVP: Auctionator's public API, vendor price as fallback.
-- Own AH scan (C_AuctionHouse.ReplicateItems) is tracked as a separate issue.
local addonName, ns = ...

local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	return api and api.GetAuctionPriceByItemID and api
end

function ns.HasAuctionator()
	return AuctionatorAPI() ~= nil
end

-- Returns copper, source ("auctionator" | "vendor"), ageDays (nil if unknown)
function ns.GetPrice(itemID)
	local api = AuctionatorAPI()
	if api then
		local ok, copper = pcall(api.GetAuctionPriceByItemID, addonName, itemID)
		if ok and type(copper) == "number" then
			local okAge, days = pcall(api.GetAuctionAgeByItemID, addonName, itemID)
			return copper, "auctionator", (okAge and type(days) == "number") and days or nil
		end
	end
	-- TODO: vendor buy price for vendor reagents (threads, vials, dyes) - needs a data table
	return nil, nil, nil
end
