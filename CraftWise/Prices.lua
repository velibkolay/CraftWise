-- Price sources:
--   buy side (reagents): cheapest of merchant price (recorded at vendors) and the auction price
--   sell side (outputs): auction price after the AH cut, or the vendor sell price
-- Auction price (#26 phase 2): CraftWise's own price history at the house and basis chosen in
-- Settings (Market.lua), then Auctionator's price as a labelled fallback (it can't tell houses apart).
local addonName, ns = ...

ns.AH_CUT = 0.05 -- faction house cut the addon has always used; neutral houses wait for a measured cut

ns.BASIS_TEXT = { typical = "typical", current = "current lowest" }
ns.AUCTIONATOR_LABEL = "Auctionator (house unknown)"

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

-- Profit price settings: basis "typical" | "current", house choice (Market.CHOICES).
function ns.PriceSettings()
	local s = ns.db and ns.db.settings or {}
	return s.priceBasis == "current" and "current" or "typical", s.priceHouse or "faction"
end

-- The house profit uses: key, label, kind ("faction" | "neutral"); nil when it can't be told.
function ns.ProfitHouse()
	local _, choice = ns.PriceSettings()
	return ns.Market.HouseFor(choice)
end

-- Short label of a quote: "typical · Horde AH", "current lowest, too little history · Booty Bay".
local function QuoteLabel(quote)
	local basis = ns.BASIS_TEXT[quote.basis]
	if quote.fallback then
		basis = basis .. ", " .. quote.fallback
	end
	return basis .. " · " .. quote.houseLabel
end

-- One unit at auction, in the fallback order of #26 phase 2:
--   1. Market price at the profit house by the chosen basis (typical with too little history falls
--      back to the current lowest there, labelled);
--   2. Auctionator's price, labelled "Auctionator (house unknown)";
--   3. nil ("no price data").
-- Returns { copper, source = "market"|"auctionator", basis, fallback, house, houseLabel, houseKind,
-- label, age (days), thin, thinWhy }.
function ns.AuctionQuote(itemID)
	local basis = ns.PriceSettings()
	local house, houseLabel, kind = ns.ProfitHouse()
	if house then
		local quote = ns.Market.Quote(itemID, house, basis)
		if quote then
			quote.source, quote.house, quote.houseLabel, quote.houseKind = "market", house, houseLabel, kind
			quote.label = QuoteLabel(quote)
			quote.age = quote.t and math.floor((time() - quote.t) / 86400) or nil
			local depth = ns.Market.Depth(itemID, house)
			quote.thin, quote.thinWhy = ns.Market.IsThin(depth, ns.Market.StackSize(itemID))
			return quote
		end
	end
	local ah, age = ns.GetAuctionPrice(itemID)
	if ah then
		return { copper = ah, source = "auctionator", age = age, label = ns.AUCTIONATOR_LABEL }
	end
	return nil
end

-- Where a cut comes from (#40), shown wherever the cut is applied:
--   "measured"   Veli's own sales at that house (phase 3 of #26): "5% cut measured (12 sales)"
--   "confirmed"  entered by Veli in game: the own faction house takes 5% (2026-11-07): "5% cut (confirmed)"
--   "unverified" neutral houses until measured or confirmed: no cut, no profit: "cut unverified"
--   "unknown"    Auctionator's price, house not known: keeps the 5% it always had: "5% cut (house unknown)"
-- A measurement wins over a confirmed value; when they differ both are shown and `differs` is set.
ns.CONFIRMED_CUTS = { faction = ns.AH_CUT } -- by house kind; add a house kind here when Veli confirms it
ns.CUT_EPSILON = 0.0005

local function Pct(rate)
	return ("%g%%"):format(math.floor(rate * 1000 + 0.5) / 10)
end

-- { cut (nil when unverified), source, text, differs, measured, samples, confirmed }
function ns.CutInfo(quote)
	if quote.source ~= "market" then
		return { cut = ns.AH_CUT, source = "unknown", text = Pct(ns.AH_CUT) .. " cut (house unknown)" }
	end
	local confirmed = ns.CONFIRMED_CUTS[quote.houseKind]
	local measured, samples = ns.Market.MeasuredCut(quote.house)
	if measured then
		local info = { cut = measured, source = "measured", measured = measured, samples = samples or 0, confirmed = confirmed }
		info.text = ("%s cut measured (%d %s)"):format(Pct(measured), info.samples, info.samples == 1 and "sale" or "sales")
		if confirmed and math.abs(measured - confirmed) > ns.CUT_EPSILON then
			info.differs = true
			info.text = ("%s, differs from %s confirmed"):format(info.text, Pct(confirmed))
		end
		return info
	end
	if confirmed then
		return { cut = confirmed, source = "confirmed", confirmed = confirmed, text = Pct(confirmed) .. " cut (confirmed)" }
	end
	return { source = "unverified", text = "cut unverified" }
end

-- Cut taken from a sale at the quote's house (nil = cut unverified, decision 6 on #26), then its
-- source info.
function ns.AuctionCut(quote)
	local info = ns.CutInfo(quote)
	return info.cut, info
end

-- What `count` units bring at auction at the profit house and basis, after the cut:
-- { quote, label, gross (total), net (total, nil when the cut is unverified), cut, cutInfo, cutText,
-- cutUnverified, thin, age } or nil ("no price data"). Whole copper, rounded down: the cut is taken
-- from the sale total.
function ns.AuctionSale(itemID, count)
	local quote = ns.AuctionQuote(itemID)
	if not quote then
		return nil
	end
	count = count or 1
	local cut, info = ns.AuctionCut(quote)
	local sale = { quote = quote, label = quote.label, gross = math.floor(quote.copper * count), cut = cut,
		cutInfo = info, cutText = info.text, cutDiffers = info.differs, thin = quote.thin, age = quote.age }
	if cut then
		sale.net = math.floor(quote.copper * (1 - cut) * count)
	else
		sale.cutUnverified = true
	end
	return sale
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

-- Cheapest way to obtain one unit: { copper, source = "vendor"|"auction", age, label, thin }
function ns.GetBuyPrice(itemID)
	local vendor = ns.GetVendorBuyPrice(itemID)
	local ah = ns.AuctionQuote(itemID)
	if vendor and (not ah or vendor <= ah.copper) then
		return { copper = vendor, source = "vendor", label = "vendor" }
	elseif ah then
		return { copper = ah.copper, source = "auction", age = ah.age, label = ah.label, thin = ah.thin, quote = ah }
	end
	return nil
end

-- Reagent cost basis per view (#47): "ah" (the cheapest of vendor and AH, as above) or "paid" (what
-- you paid for the units you hold, from the ledger #46; per reagent the AH basis when there is none).
ns.COST_BASIS_VIEWS = { "profit", "learn", "level", "upgrades" }
ns.COST_BASIS_TEXT = { ah = "AH", paid = "paid cost" }

function ns.CostBasis(view)
	local bases = ns.db and ns.db.settings.costBasis
	return bases and bases[view or "profit"] == "paid" and "paid" or "ah"
end

-- One unit at what you paid: { copper, source = "paid", label, units, noCraft } from the ledger. When
-- some held units have no recorded price, it is the average of the logged ones, marked paidPartial
-- with "N of M units" (decision 2 on #47). Without any paid cost: the AH basis price, marked
-- paidFallback with the reason (paidNote). noCraft: a paid cost is the cost of what you hold, so
-- craft-or-buy doesn't replace it (decision 1 on #47).
local function Units(n)
	return math.floor(n + 0.5)
end

function ns.GetPaidBuyPrice(itemID)
	local paid = ns.Ledger and ns.Ledger.PaidCost(itemID)
	if paid then
		local price = { copper = paid.copper, source = "paid", units = paid.units, noCraft = true }
		if paid.partial then
			price.paidPartial = true
			price.label = ("paid cost, %d of %d units"):format(Units(paid.known), Units(paid.units))
			price.paidNote = ("average of the %d units you bought; %d held have no recorded price"):format(
				Units(paid.known), Units(paid.units - paid.known))
		else
			price.label = ("paid cost, %d held"):format(Units(paid.units))
		end
		return price
	end
	local price = ns.GetBuyPrice(itemID)
	if not price then
		return nil
	end
	local out = {}
	for k, v in pairs(price) do
		out[k] = v
	end
	out.paidFallback = true
	out.paidNote = "no paid cost"
	return out
end

-- Price functions for Profit.Evaluate in one view: the view's cost basis, the sale value, and the
-- recipes this character knows, so intermediate reagents cost min(buy, craft) (#47). basis overrides
-- the view's setting ("ah" for the buy list, #60).
function ns.ReagentPrices(view, basis)
	basis = basis or ns.CostBasis(view)
	-- Each item's buy price is looked up once per build: intermediates appear in many recipes.
	local base, memo = basis == "paid" and ns.GetPaidBuyPrice or ns.GetBuyPrice, {}
	return {
		basis = basis,
		buy = function(itemID)
			local v = memo[itemID]
			if v == nil then
				v = base(itemID) or false
				memo[itemID] = v
			end
			return v or nil
		end,
		sell = ns.GetSellValue,
		recipesFor = ns.KnownRecipesFor,
	}
end

-- Is selling on the AH worth it over vendoring? When it pays at least ahMinPercent more than a
-- vendor AND at least ahMinCopper more (defaults 20% and 10 copper, set in the Bags view; Veli,
-- 2026-10-04). Below that the vendor wins: no deposit at risk, no trip to the auctioneer.
-- Returns worth, edge (AH minus vendor, copper).
function ns.AuctionWorthIt(ahNet, vendor)
	if not ahNet then
		return false, nil
	end
	if not vendor or vendor <= 0 then
		return true, nil
	end
	local edge = ahNet - vendor
	local s = ns.db and ns.db.settings or {}
	local minPercent, minCopper = s.ahMinPercent or 20, s.ahMinCopper or 0
	return edge > 0 and edge >= minCopper and ahNet >= vendor * (1 + minPercent / 100), edge
end

-- Best net value of one unit when selling: { copper, source = "auction"|"vendor", age, gross, cut,
-- label, thin, cutUnverified }. AH value is after the house's cut; selling to a vendor is always
-- possible, so the higher one wins. Without a known cut the AH value stays gross and is marked
-- cutUnverified (it can't be netted); a vendor paying more than that gross still wins.
function ns.GetSellValue(itemID)
	local ah = ns.AuctionQuote(itemID)
	local vendor = ns.GetVendorSellPrice(itemID)
	local hasVendor = vendor and vendor > 0
	if ah then
		local cut, info = ns.AuctionCut(ah)
		local value = { source = "auction", age = ah.age, gross = ah.copper, cut = cut, label = ah.label, thin = ah.thin, quote = ah,
			cutText = info.text, cutSource = info.source, cutDiffers = info.differs }
		if cut then
			value.copper = ah.copper * (1 - cut)
			if not hasVendor or value.copper >= vendor then
				return value
			end
		elseif not hasVendor or ah.copper > vendor then
			value.copper, value.cutUnverified = ah.copper, true
			return value
		end
	end
	if hasVendor then
		return { copper = vendor, source = "vendor", label = "vendor" }
	end
	return nil
end

-- Both ways to sell `quantity` units, for display (#48). Same values ns.GetSellValue compares, so
-- the chosen one matches "Sells for" to the copper.
-- { chosen = "vendor"|"auction"|nil (what ns.GetSellValue picks),
--   vendor = copper (nil: sell price not loaded yet; 0: vendors don't buy it),
--   auction = { gross, net (nil when the cut is unverified), cut, cutText, label, thin, cutUnverified } | nil }
function ns.SaleOptions(itemID, quantity)
	quantity = quantity or 1
	local options = {}
	local vendor = ns.GetVendorSellPrice(itemID)
	options.vendor = vendor and vendor * quantity
	local quote = ns.AuctionQuote(itemID)
	if quote then
		local cut, info = ns.AuctionCut(quote)
		options.auction = { gross = quote.copper * quantity, cut = cut, cutText = info.text, cutDiffers = info.differs,
			label = quote.label, thin = quote.thin, cutUnverified = not cut or nil,
			net = cut and quote.copper * (1 - cut) * quantity or nil }
	end
	local chosen = ns.GetSellValue(itemID)
	options.chosen = chosen and chosen.source
	return options
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

-- What the open merchant asks for one unit, in copper: prices[itemID], and extended[itemID] = true
-- for items that also (or only) cost currency or items.
function ns.MerchantUnitPrices()
	local prices, extended = {}, {}
	if not GetMerchantNumItems then
		return prices, extended
	end
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID and GetMerchantItemID(index)
		local price, quantity, ext = MerchantItem(index)
		if itemID then
			if ext then
				extended[itemID] = true
			elseif price and price > 0 then
				prices[itemID] = price / math.max(quantity or 1, 1)
			end
		end
	end
	return prices, extended
end

function ns.RecordMerchant()
	if not ns.db or not GetMerchantNumItems then
		return 0
	end
	local recorded = 0
	local prices, extended = ns.MerchantUnitPrices()
	for itemID, unit in pairs(prices) do
		if not extended[itemID] then
			ns.db.vendor[itemID] = unit
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
