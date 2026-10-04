-- CraftWise section in the game's item tooltips (bags, links, everywhere), under a "CraftWise"
-- header like other addons use. Every line can be turned on or off, and the whole section can show
-- always or only while Shift is held (settings: db.tooltip, panel in UI/Settings.lua).
local _, ns = ...

ns.TOOLTIP_LINES = {
	{ key = "status", label = "Junk / Keep mark" },
	{ key = "advice", label = "Vendor or AH advice" },
	{ key = "usedIn", label = "Used in (recipes)" },
	{ key = "skillups", label = "Your skill-ups (crafted items)" },
}

local ACCENT = "|cff4fb3ff"
local MUTED = "|cff8c95a6"

local function Settings()
	return ns.db and ns.db.tooltip
end

-- Vendor and AH value of `count` items and the advice by the AH rule (as in the Bags view).
function ns.ItemAdvice(itemID, count)
	count = count or 1
	local each = ns.GetVendorSellPrice(itemID)
	local vendor = each and each > 0 and each * count or nil
	local ah = ns.GetAuctionPrice(itemID)
	local ahNet = ah and math.floor(ah * (1 - ns.AH_CUT) * count) or nil
	local best
	if ahNet and (not vendor or ns.AuctionWorthIt(ahNet, vendor)) then
		best = "auction"
	elseif vendor then
		best = "vendor"
	end
	return vendor, ahNet, best
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
		elseif ns.db.keep[itemID] then
			lines[#lines + 1] = { "Marked", "|cff8ab4ffKeep|r" }
		end
	end
	if s.lines.advice then
		local count = BagCount(itemID)
		local vendor, ahNet, best = ns.ItemAdvice(itemID, count)
		if vendor or ahNet then
			local parts = {}
			parts[#parts + 1] = "Vendor " .. (vendor and ns.FormatMoney(vendor) or "-")
			parts[#parts + 1] = "AH " .. (ahNet and ns.FormatMoney(ahNet) or "-")
			local left = count > 1 and ("Sell x%d"):format(count) or "Sell"
			local advice = best == "auction" and "|cff4fd18cAuction|r" or best == "vendor" and "|cff4fd18cVendor|r" or ""
			lines[#lines + 1] = { left, table.concat(parts, MUTED .. "  ·  |r") .. "  " .. advice }
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
