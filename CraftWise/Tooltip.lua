-- CraftWise section in the game's item tooltips (bags, links, everywhere), under a "CraftWise"
-- header like other addons use. Every line can be turned on or off, and the whole section can show
-- always or only while Shift is held (settings: db.tooltip, panel in UI/Settings.lua).
local _, ns = ...

ns.TOOLTIP_LINES = {
	{ key = "status", label = "Junk / Sell on AH / Keep mark" },
	{ key = "advice", label = "Vendor or AH advice" },
	{ key = "usedIn", label = "Used in (recipes)" },
	{ key = "skillups", label = "Your skill-ups (crafted items)" },
	{ key = "market", label = "Auction prices per house" },
	{ key = "tracked", label = "Tracked recipe: reagents you hold" },
}

local ACCENT = "|cff4fb3ff"
local MUTED = "|cff8c95a6"
local WARN = "|cffffc24d"

----------------------------------------------------------------------------------------------------
-- Auction prices per house (#26 phase 2), shared by item tooltips and the CraftWise window.
-- Every price comes with its depth (Veli on #26: a cheap price at a thin house says little).
----------------------------------------------------------------------------------------------------

local function Money(copper)
	return ns.FormatMoney(copper)
end

function ns.TypicalText(typical)
	if typical.status == "ok" then
		return ("typical %s (%d days)"):format(Money(typical.price), typical.days)
	elseif typical.status == ns.Market.TOO_LITTLE_HISTORY then
		return ("%s (%d of %d days)"):format(ns.Market.TOO_LITTLE_HISTORY, typical.days, ns.Market.MIN_HISTORY_DAYS)
	end
	return ns.Market.NO_DATA
end

function ns.ThinText(s)
	if s.thinWhy == "stack" then
		return ("cheapest tier %d, under one stack (%d)"):format(s.depth[1].qty, s.stack)
	end
	return ("cheapest tier %d of %d%s within +10%%"):format(s.depth[1].qty, s.near, s.nearPartial and "+" or "")
end

-- min, units, listings or price levels, last seen.
local function CurrentText(s, itemID, now)
	local c = s.current
	local parts = { "min " .. Money(c.min), ("%d units"):format(c.qty or 0) }
	local kind = c.listings and ns.Market.ListingsLabel(itemID)
	if kind then
		parts[#parts + 1] = ("%d %s"):format(c.listings, kind)
	end
	parts[#parts + 1] = "seen " .. ns.Market.FormatAge(now - c.t) .. " ago"
	if not c.listed then
		parts[#parts + 1] = WARN .. "none in the latest full scan|r"
	end
	return table.concat(parts, " · ")
end

-- One line of figures for a house: min, cheapest tiers, typical, age, thin.
function ns.MarketShortText(s, now)
	local c = s.current
	if not c then
		return ns.Market.NO_DATA
	end
	local parts = { "min " .. Money(c.min) .. (c.listed and "" or " (none listed now)") }
	if s.depth then
		parts[#parts + 1] = ns.Market.DepthText(s.depth, 2, Money)
	end
	parts[#parts + 1] = s.typical.status == "ok" and ("typ " .. Money(s.typical.price)) or ns.Market.TOO_LITTLE_HISTORY
	parts[#parts + 1] = ns.Market.FormatAge(now - c.t) .. " ago"
	local text = table.concat(parts, " · ")
	if s.thin then
		text = text .. " · " .. WARN .. "thin|r"
	end
	return text
end

local function BuyText(best, cheapest, need)
	if best and need > 1 then
		return ("%s  %d for %s (%s each)"):format(best.label, need, Money(best.cost), Money(best.unit))
	elseif best then
		local depth = best.atPrice and ("%d at that price"):format(best.atPrice) or ("%d units listed"):format(best.qty or 0)
		return ("%s  %s (%s)"):format(best.label, Money(best.unit), depth)
	elseif cheapest then
		return ("no house shows %d units; lowest %s at %s (%d there)"):format(need, Money(cheapest.unit), cheapest.label, cheapest.qty or 0)
	end
	return "none listed"
end

local function SellText(best)
	local basis = ns.BASIS_TEXT[best.basis] .. (best.fallback and (", " .. best.fallback) or "")
	local listed = ("%d listed there"):format(best.qty)
	if best.cutUnverified then
		return ("%s  %s gross (%s) · cut unverified · %s"):format(best.label, Money(best.gross), basis, listed)
	end
	local text = ("%s  %s net (%s, %s - %g%% measured cut) · %s"):format(best.label, Money(best.net), basis,
		Money(best.gross), best.cut * 100, listed)
	if (best.unverifiedLeft or 0) > 0 then
		text = text .. (" · %d with cut unverified not compared"):format(best.unverifiedLeft)
	end
	return text
end

-- { left, right } lines. opts.mode:
--   "full" (item tooltip): the profit house in detail, best to buy (one unit), best to sell, other houses
--   "sell" (crafted item): the profit house in detail, best to sell, other houses
--   "buy"  (reagent): the profit house in one line, best to buy opts.need units (one craft)
-- Only houses this character can use. Nothing when none of them has data.
function ns.MarketLines(itemID, opts)
	opts = opts or {}
	local M = ns.Market
	local mode = opts.mode or "full"
	local lines = {}
	local houses = M and M.UsableHouses(itemID) or {}
	if #houses == 0 then
		return lines
	end
	local function add(left, right)
		lines[#lines + 1] = { left, right }
	end
	local now = time()
	local basis = ns.PriceSettings()
	local selected, selectedLabel = ns.ProfitHouse()
	local s = selected and M.Snapshot(itemID, selected)
	local need = math.max(1, opts.need or 1)

	if mode == "buy" then
		add("  " .. (opts.name or ("item " .. itemID)), (selectedLabel or "?") .. ": " .. (s and ns.MarketShortText(s, now) or M.NO_DATA))
		local best, cheapest = M.BestToBuy(itemID, need)
		add(("    best for %d"):format(need), BuyText(best, cheapest, need))
		return lines
	end

	if not (s and s.current) then
		add(selectedLabel or "Profit house", M.NO_DATA)
	else
		add(selectedLabel, ns.TypicalText(s.typical))
		add("  Current", CurrentText(s, itemID, now))
		if s.depth then
			local stale = s.depth.t < s.current.t - 60 and (" (%s ago)"):format(M.FormatAge(now - s.depth.t)) or ""
			add("  Cheapest", M.DepthText(s.depth, 3, Money) .. stale)
			add("  Within +10% of min", ("%d%s units"):format(s.near, s.nearPartial and "+" or ""))
		end
		if s.lo then
			add("  Last 7 days", ("%s to %s"):format(Money(s.lo), Money(s.hi)))
		end
		if s.thin then
			add("  " .. WARN .. "Thin market|r", ns.ThinText(s))
		end
	end
	if mode == "full" then
		local best, cheapest = M.BestToBuy(itemID, 1)
		add("Best to buy", BuyText(best, cheapest, 1))
	end
	local sell = M.BestToSell(itemID, basis)
	if sell then
		add("Best to sell", SellText(sell))
	end
	for _, house in ipairs(houses) do
		if house.key ~= selected then
			add("  " .. house.label, ns.MarketShortText(M.Snapshot(itemID, house.key), now))
		end
	end
	return lines
end

local function Settings()
	return ns.db and ns.db.tooltip
end

-- Vendor and AH value of `count` items and the advice by the AH rule (as in the Bags view). The AH
-- value is at the profit house and basis (#40); the 4th result says which: ns.AuctionSale's table
-- (label, cutText, gross, cutUnverified) or nil without a price. A cut that isn't verified leaves
-- ahNet nil, so the vendor is advised.
function ns.ItemAdvice(itemID, count)
	count = count or 1
	local each = ns.GetVendorSellPrice(itemID)
	local vendor = each and each > 0 and each * count or nil
	local sale = ns.AuctionSale(itemID, count)
	local ahNet = sale and sale.net or nil
	local best
	if ahNet and (not vendor or ns.AuctionWorthIt(ahNet, vendor)) then
		best = "auction"
	elseif vendor then
		best = "vendor"
	end
	return vendor, ahNet, best, sale
end

local function BagCount(itemID)
	local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0
	return count > 0 and count or 1
end

-- Recipes you know that make this item, with your recorded skill-ups.
local function SkillUpLine(itemID)
	local crafts, ups = 0, 0
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for recipeID, recipe in pairs(prof.recipes) do
			if recipe.output and recipe.output.itemID == itemID then
				local n, u = ns.SkillUpStats(recipeID)
				crafts, ups = crafts + n, ups + u
			end
		end
	end
	if crafts > 0 then
		return ("%d skill-ups in %d crafts"):format(ups, crafts)
	end
end

-- Tracked recipes (profession window "Track") that use or make this item: the reagent balance of
-- each (#49), so hovering Cured Light Hide in the bags says how many pants the leather allows.
function ns.TrackedBalanceLines(itemID)
	local out = {}
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and ns.charDB) then
		return out
	end
	local ok, tracked = pcall(C_TradeSkillUI.GetRecipesTracked, false)
	if not ok or type(tracked) ~= "table" then
		return out
	end
	for _, recipeID in ipairs(tracked) do
		local recipe
		for _, prof in pairs(ns.charDB.professions) do
			recipe = recipe or prof.recipes[recipeID]
		end
		local reagents = recipe and recipe.reagents or ns.BundledRecipe(recipeID)
		local output = recipe and recipe.output
		local uses = output and output.itemID == itemID
		for _, r in ipairs(reagents or {}) do
			uses = uses or r.itemID == itemID
		end
		if uses then
			local lines = ns.BalanceLines(reagents, nil, output and output.itemID)
			if #lines > 0 then
				out[#out + 1] = { "Tracked", "|cffffffff" .. (recipe and recipe.name or ("Recipe " .. recipeID)) .. "|r" }
				for _, l in ipairs(lines) do
					out[#out + 1] = l
				end
			end
		end
	end
	return out
end

function ns.AddTooltipLines(tooltip, itemID)
	local s = Settings()
	if not (s and s.enabled and itemID and ns.db) then
		return false
	end
	if s.mode == "shift" and not IsShiftKeyDown() then
		return false
	end
	local lines = {}
	if s.lines.status then
		if ns.db.junk and ns.db.junk[itemID] then
			lines[#lines + 1] = { "Marked", "|cffff5555Junk|r" }
		elseif ns.db.sellAH and ns.db.sellAH[itemID] then
			lines[#lines + 1] = { "Marked", "|cffffd100Sell on AH|r" }
		elseif ns.db.keep[itemID] then
			lines[#lines + 1] = { "Marked", "|cff8ab4ffKeep|r" }
		end
	end
	if s.lines.advice then
		local count = BagCount(itemID)
		local vendor, ahNet, best, sale = ns.ItemAdvice(itemID, count)
		if vendor or sale then
			local parts = {}
			parts[#parts + 1] = "Vendor " .. (vendor and ns.FormatMoney(vendor) or "-")
			parts[#parts + 1] = "AH " .. (ahNet and ns.FormatMoney(ahNet) or sale and sale.cutUnverified and "?" or "-")
			local left = count > 1 and ("Sell x%d"):format(count) or "Sell"
			local advice = best == "auction" and "|cff4fd18cAuction|r" or best == "vendor" and "|cff4fd18cVendor|r" or ""
			lines[#lines + 1] = { left, table.concat(parts, MUTED .. "  ·  |r") .. "  " .. advice }
			-- Which price the AH figure is, and which cut was taken off it.
			if sale then
				local cutText = sale.cutDiffers and ("|cffffc24d" .. sale.cutText .. "|r") or (MUTED .. sale.cutText .. "|r")
				local gross = sale.cutUnverified and (" · gross " .. ns.FormatMoney(sale.gross)) or ""
				lines[#lines + 1] = { "  AH price", MUTED .. sale.label .. "|r" .. gross .. MUTED .. " · |r" .. cutText }
			else
				lines[#lines + 1] = { "  AH price", MUTED .. ns.Market.NO_DATA .. "|r" }
			end
		end
	end
	if s.lines.usedIn and ns.UsedInSummary then
		local groups = ns.UsedInSummary(itemID)
		if #groups > 0 then
			local parts = {}
			for i, g in ipairs(groups) do
				if i > 3 then
					parts[#parts + 1] = MUTED .. ("+%d|r"):format(#groups - 3)
					break
				end
				local color = g.known > 0 and "|cff4fd18c" or g.mine and "|cffffffff" or MUTED
				local known = g.known > 0 and (" (%d known)"):format(g.known) or ""
				parts[#parts + 1] = ("%s%s %d%s|r"):format(color, g.profession, g.count, known)
			end
			lines[#lines + 1] = { "Used in", table.concat(parts, MUTED .. " · |r") }
		end
	end
	if s.lines.skillups then
		local text = SkillUpLine(itemID)
		if text then
			lines[#lines + 1] = { "Your crafts", text }
		end
	end
	if s.lines.tracked then
		for _, line in ipairs(ns.TrackedBalanceLines(itemID)) do
			lines[#lines + 1] = line
		end
	end
	if s.lines.market then
		for _, line in ipairs(ns.MarketLines(itemID, { mode = "full" })) do
			lines[#lines + 1] = line
		end
	end
	if #lines == 0 then
		return false
	end
	tooltip:AddLine(" ")
	tooltip:AddLine(ACCENT .. "CraftWise|r")
	for _, l in ipairs(lines) do
		tooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
	end
	tooltip:Show()
	return true
end

local function OnItemTooltip(tooltip, data)
	if not (data and data.id) or tooltip == ShoppingTooltip1 or tooltip == ShoppingTooltip2 then
		return
	end
	-- The CraftWise window shows its own details; don't add them twice there.
	if tooltip == GameTooltip and ns.InOwnWindow and ns.InOwnWindow(tooltip:GetOwner()) then
		return
	end
	ns.AddTooltipLines(tooltip, data.id)
end

ns.On("PLAYER_LOGIN", function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	end
end)

-- Shift mode: redraw an open tooltip when Shift is pressed or released.
ns.On("MODIFIER_STATE_CHANGED", function(_, key)
	local s = Settings()
	if s and s.enabled and s.mode == "shift" and key and key:find("SHIFT") and GameTooltip:IsShown()
		and GameTooltip.RefreshData then
		GameTooltip:RefreshData()
	end
end)
