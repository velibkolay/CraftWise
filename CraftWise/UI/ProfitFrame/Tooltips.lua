-- Profit table window: the row tooltips of every view.
local _, ns = ...
local PF = ns.PF
local C = ns.Style.colors
local SKILL_COLORS = PF.SKILL_COLORS
local state = PF.state
local Money, Muted, ItemName, StatusLine, View = PF.Money, PF.Muted, PF.ItemName, PF.StatusLine, PF.View

local WARN = C.warn

-- Where a price came from: "vendor", or the auction label ("typical · Horde AH",
-- "Auctionator (house unknown)"), plus a thin-market mark.
local function PriceLabel(line)
	local text
	if line.source == "vendor" then
		text = Muted("vendor")
	elseif line.source == "crafted" then
		text = C.good .. "crafted|r"
	else
		text = Muted(line.label or "AH") .. (line.thin and (" " .. WARN .. "thin|r") or "")
	end
	if line.crafted == false then
		text = Muted("bought: ") .. text
	end
	if line.paidFallback and line.source ~= "crafted" then -- a crafted line says it in its detail line
		text = text .. " " .. WARN .. "no paid cost|r"
	end
	return text
end

-- Second line under a reagent (#47): both unit values when a known recipe makes it, why the paid
-- cost wasn't used, or what a partial paid cost covers. nil when there is nothing to add.
local function ReagentDetail(line)
	local parts = {}
	if line.crafted ~= nil then
		local bought = line.buyUnit and (Money(line.buyUnit) .. " " .. (line.buySource == "vendor" and "vendor" or (line.buyLabel or "AH")))
			or ns.Market.NO_DATA
		parts[#parts + 1] = ("each: crafted %s · bought %s"):format(Money(line.craftUnit), bought)
	end
	if (line.paidFallback or line.paidPartial) and line.paidNote then
		parts[#parts + 1] = line.paidNote
	end
	if #parts == 0 then
		return nil
	end
	return "    " .. table.concat(parts, " · ")
end
PF.ReagentDetail = ReagentDetail

-- "Sells for" line: the chosen value and its tag (#48).
local function SellText(r)
	if not r.sellsFor then
		return ns.Market.NO_DATA
	end
	local tag = PF.SaleTag(r.sellSource, r.cutUnverified)
	return ("%s  %s"):format(Money(r.sellsFor), r.cutUnverified and (WARN .. tag .. "|r") or Muted(tag or ""))
end

-- Both sale options under "Sells for", the one "Sells for" uses marked (#48):
--   Vendor   5s99 (no cut)
--   AH net   x (gross y, 5% cut (confirmed), typical · Horde AH)   or   AH  gross y, cut unverified, Booty Bay
-- Returns { { left, right, chosen } } for the recipe's output quantity.
local function SaleOptionLines(r)
	if not r.outputItemID then
		return {}
	end
	local o = ns.SaleOptions(r.outputItemID, r.outputQuantity or 1)
	local lines = {}
	local vendor
	if o.vendor == nil then
		vendor = Muted("sell price not loaded yet")
	elseif o.vendor <= 0 then
		vendor = Muted("vendors don't buy it")
	else
		vendor = Money(o.vendor) .. " " .. Muted("(no cut)")
	end
	lines[1] = { "Vendor", vendor, r.sellSource == "vendor" }
	local a = o.auction
	if not a then
		lines[2] = { "AH net", Muted(ns.Market.NO_DATA), false }
	elseif a.cutUnverified then
		lines[2] = { "AH", WARN .. ("gross %s, cut unverified|r"):format(Money(a.gross)) .. Muted(", " .. (a.label or "?"))
			.. (a.thin and (" " .. WARN .. "thin|r") or ""), r.sellSource == "auction" }
	else
		local cut = a.cutDiffers and (WARN .. (a.cutText or "?") .. "|r") or (a.cutText or "?")
		lines[2] = { "AH net", Money(a.net) .. " " .. Muted("(gross " .. Money(a.gross) .. ", ") .. cut .. Muted(", " .. (a.label or "?") .. ")")
			.. (a.thin and (" " .. WARN .. "thin|r") or ""), r.sellSource == "auction" }
	end
	for _, l in ipairs(lines) do
		l[1] = l[3] and (C.good .. "  " .. l[1] .. " (used)|r") or Muted("  " .. l[1])
	end
	return lines
end

-- Reagents held vs needed, the limiting one and a buy list (#49) that crafts intermediates cheaper to
-- craft at market prices (#60).
local function AddBalance(r)
	local lines = ns.BalanceLines(r.reagents, nil, r.outputItemID)
	if #lines == 0 then
		return
	end
	GameTooltip:AddLine(" ")
	for _, l in ipairs(lines) do
		if l[2] == "" then
			GameTooltip:AddLine(l[1], 0.9, 0.9, 0.9, true)
		else
			GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 1, 1, 1)
		end
	end
end

local function AddLines(lines, r, g, b)
	for _, l in ipairs(lines) do
		GameTooltip:AddDoubleLine(l[1], l[2], r or 0.8, g or 0.8, b or 0.8, 1, 1, 1)
	end
end

-- Market per item (#26 phase 2): each reagent at the profit house with the best house for one craft's
-- quantity, then the crafted item in detail with the best house to sell and the other houses.
local function AddMarketSection(r)
	local buy = {}
	for _, line in ipairs(r.reagents or {}) do
		for _, l in ipairs(ns.MarketLines(line.itemID, { mode = "buy", need = line.quantity, name = ItemName(line.itemID) })) do
			buy[#buy + 1] = l
		end
	end
	local sell = r.outputItemID and ns.MarketLines(r.outputItemID, { mode = "sell" }) or {}
	if #buy == 0 and #sell == 0 then
		return
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Auction houses  " .. Muted("prices: " .. PF.PriceBasisText()), 1, 0.82, 0)
	if #buy > 0 then
		GameTooltip:AddLine("Reagents, one craft", 0.9, 0.9, 0.9)
		AddLines(buy)
	end
	if #sell > 0 then
		GameTooltip:AddLine("Crafted item", 0.9, 0.9, 0.9)
		AddLines(sell)
	end
end

local function StatLabel(key)
	local label = _G[key]
	return type(label) == "string" and label or key
end

local function ShowUpgradeTooltip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
	else
		GameTooltip:AddLine(r.name)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("CraftWise", C.accent[1], C.accent[2], C.accent[3])
	if r.emptySlot then
		GameTooltip:AddDoubleLine("Replaces", "empty " .. r.slotLabel .. " slot", 0.8, 0.8, 0.8, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Replaces", ("%s (ilvl %d)"):format(r.equippedText or "?", r.current.level or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		-- Stat differences, new minus equipped, from the client's item stats.
		local keys, diff = {}, {}
		for k, v in pairs(r.stats or {}) do
			diff[k] = v
		end
		for k, v in pairs(r.current.stats or {}) do
			diff[k] = (diff[k] or 0) - v
		end
		for k, v in pairs(diff) do
			if v ~= 0 then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local v = diff[k]
			GameTooltip:AddDoubleLine("  " .. StatLabel(k), (v > 0 and "+" or "") .. v, 0.8, 0.8, 0.8,
				v > 0 and 0.3 or 1, v > 0 and 0.82 or 0.4, v > 0 and 0.55 or 0.4)
		end
		if not r.stats then
			GameTooltip:AddLine("Item stats not loaded yet - hover again.", 0.55, 0.55, 0.6)
		end
	end
	if r.mainStats or r.currentStats then
		GameTooltip:AddDoubleLine("Main stats", ("%s  vs  %s"):format(
			r.mainStats == nil and "?" or r.mainStats == "" and "none" or r.mainStats,
			r.emptySlot and "empty" or r.currentStats == nil and "?" or r.currentStats == "" and "none" or r.currentStats),
			0.8, 0.8, 0.8, 1, 1, 1)
	end
	if r.section == "ah" then
		if r.suffix then
			GameTooltip:AddLine("Random enchant: the stats above are the base item's, the listing's own enchant is not included.", 0.55, 0.55, 0.6, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Auction house", 1, 0.82, 0)
		if r.notAtHouse then
			GameTooltip:AddLine(("  Not seen at %s in your latest search. Search there, or change the profit house in Settings."):format(
				r.houseLabel or "the profit house"), 1, 0.6, 0.3, true)
		else
			GameTooltip:AddDoubleLine("  Lowest buyout", Money(r.cost), 0.8, 0.8, 0.8, 1, 1, 1)
			GameTooltip:AddDoubleLine("  Listed", ("%d at %s"):format(r.qty or 0, r.houseLabel or "?"), 0.8, 0.8, 0.8, 1, 1, 1)
			GameTooltip:AddDoubleLine("  Seen", ns.Market.FormatAge(r.priceAge or 0) .. " ago", 0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(r.dismissed and "Right-click: suggest this item again" or "Right-click: don't suggest this item",
			0.55, 0.55, 0.6)
		GameTooltip:Show()
		return
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Recipe", (SKILL_COLORS[r.skillColor] or "") .. (r.recipeName or "?") .. "|r", 1, 0.82, 0, 1, 1, 1)
	for _, line in ipairs(r.reagents or {}) do
		local have = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(line.itemID)) or 0
		local color = have >= line.quantity and C.good or C.warn
		GameTooltip:AddDoubleLine(("  %d × %s"):format(line.quantity, ItemName(line.itemID)),
			color .. ("have %d|r"):format(have), 1, 1, 1, 1, 1, 1)
	end
	if r.learnFirst then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Learn first%s"):format(r.required and (" (skill %d)"):format(r.required) or ""), 1, 0.6, 0.3)
		for i, line in ipairs(ns.RecipeWhere(r.recipeID)) do
			if i > 4 then
				break
			end
			GameTooltip:AddDoubleLine("  " .. line.text, line.label or "", 1, 1, 1, 0.55, 0.55, 0.6)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Cost to obtain", 1, 0.82, 0)
	local reagents = r.reagentComplete and Money(r.reagentCost or 0)
		or ((r.reagentCost or 0) > 0 and (Money(r.reagentCost) .. C.warn .. " +?|r") or (C.warn .. "no price|r"))
	GameTooltip:AddDoubleLine("  Reagents", reagents, 0.8, 0.8, 0.8, 1, 1, 1)
	if r.learnFirst then
		local how = ({ trainer = "trainer", vendor = "vendor" })[r.learnSource] or r.learnLabel or ""
		GameTooltip:AddDoubleLine("  Learn" .. (how ~= "" and (" (" .. how .. ")") or ""),
			r.learnCost and Money(r.learnCost) or (C.warn .. "no price|r"), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("  Total", Money(r.cost or 0) .. (r.costComplete and "" or (C.warn .. " +?|r")), 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(r.dismissed and "Right-click: suggest this item again" or "Right-click: don't suggest this item",
		0.55, 0.55, 0.6)
	GameTooltip:Show()
end

local STAGE_TEXT = { "1st quarter after yellow", "2nd quarter", "3rd quarter", "last quarter before grey" }

local function ShowLevelTooltip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r")
	local skill = state.levelSkill
	local info = r.chanceInfo or {}
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Chance of a skill point", 1, 0.82, 0)
	if r.thresholdYellow then
		GameTooltip:AddDoubleLine("  Your skill · yellow · grey", ("%s · %d · %d"):format(skill or "?", r.thresholdYellow, r.thresholdGrey),
			0.8, 0.8, 0.8, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("  Yellow · grey", "thresholds unknown", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6) -- never guessed (#83)
	end
	if info.kind == "orange" then
		GameTooltip:AddLine("  Orange: every craft gives a point (100%).", 0.9, 0.9, 0.9, true)
	elseif info.kind == "recipe" then
		GameTooltip:AddLine(("  Your %d crafts of this recipe in the %s: %d points = %d%%."):format(info.n, STAGE_TEXT[info.stage],
			info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
	elseif info.kind == "stage" then
		GameTooltip:AddLine(("  Your %d crafts of all recipes of this profession in the %s (between their yellow and grey skill): %d points = %d%%."):format(
			info.n, STAGE_TEXT[info.stage], info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(("  This recipe gets its own rate after %d crafts in this stage."):format(ns.Leveling.MIN_CRAFTS), 0.55, 0.55, 0.6, true)
	elseif info.kind == "color" then
		GameTooltip:AddLine(("  No yellow/grey thresholds for this recipe: your %d %s crafts gave %d points = %d%%."):format(
			info.n, info.color == 1 and "yellow" or "green", info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
	elseif info.kind == "formula" then
		GameTooltip:AddLine(("  Estimate: (grey - skill) / (grey - yellow) = (%d - %d) / (%d - %d) = %d%%."):format(
			info.grey, info.skill, info.grey, info.yellow, math.floor(r.chance * 100 + 0.5)), 1, 0.6, 0.3, true)
		GameTooltip:AddLine("  Community formula (SkillUp Forever, Skillet), not official. Your own crafts replace it: "
			.. ("%d crafts of any recipe of this profession in this stage so far, %d needed."):format(info.n or 0, ns.Leveling.MIN_CRAFTS), 0.55, 0.55, 0.6, true)
	else
		GameTooltip:AddLine(("  Not enough crafts recorded yet (%d, need %d), and no yellow/grey thresholds for an estimate."):format(
			info.n or 0, ns.Leveling.MIN_CRAFTS), 1, 0.6, 0.3, true)
	end
	-- The formula next to a measured rate, as a reference.
	if info.kind == "recipe" or info.kind == "stage" then
		local est = ns.Leveling.Formula(skill, r.thresholdYellow, r.thresholdGrey)
		if est then
			GameTooltip:AddLine(("  For reference, the community formula says %d%%."):format(math.floor(est * 100 + 0.5)), 0.55, 0.55, 0.6, true)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("One craft", Muted(PF.CostBasisText("level")), 1, 0.82, 0, 1, 1, 1)
	for _, line in ipairs(r.reagents or {}) do
		local left = ("  %d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), PriceLabel(line)), 1, 1, 1, 1, 1, 1)
			local detail = ReagentDetail(line)
			if detail then
				GameTooltip:AddLine(detail, 0.55, 0.55, 0.6)
			end
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	local d = r.saleDetails or {}
	if r.saleSource == "auction" then
		local pct = ("%g%%"):format((d.cut or 0) * 100)
		GameTooltip:AddDoubleLine("  Sale: AH after " .. pct .. " cut", ("%s  %s"):format(Money(r.saleValue), Muted("(" .. Money(d.ahGross or 0) .. " - " .. pct .. ")")), 1, 1, 1, 0.3, 0.82, 0.55)
		if d.label then
			GameTooltip:AddLine("    " .. d.label .. " · " .. (d.cutDiffers and WARN or "") .. (d.cutText or "") .. (d.cutDiffers and "|r" or ""), 0.55, 0.55, 0.6)
		end
		if d.vendor then
			GameTooltip:AddDoubleLine("  (vendor would pay)", Money(d.vendor), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
	elseif r.saleSource == "vendor" then
		GameTooltip:AddDoubleLine("  Sale: vendor", Money(r.saleValue), 1, 1, 1, 0.3, 0.82, 0.55)
		if d.ahNet then
			GameTooltip:AddLine(("  AH after cut: %s - under your AH rule, so vendor."):format(Money(d.ahNet)), 0.6, 0.6, 0.6, true)
		end
	elseif r.saleSource == "none" then
		GameTooltip:AddLine("  No item made: sale 0.", 0.8, 0.8, 0.8)
	else
		GameTooltip:AddLine("  Sale price unknown: counted as 0.", 1, 0.6, 0.3)
	end
	if d.cutUnverified then
		GameTooltip:AddLine(("  AH %s gross (%s): cut unverified there, so not counted."):format(Money(d.ahGross or 0), d.label or "?"),
			1, 0.6, 0.3, true)
	end
	if r.net then
		GameTooltip:AddDoubleLine("  Net per craft (reagents - sale)", (r.net <= 0 and C.good .. "+" .. Money(-r.net) or C.bad .. "-" .. Money(r.net)) .. "|r",
			1, 0.82, 0, 1, 1, 1)
	else
		GameTooltip:AddLine("  Reagent price missing - can't rank this recipe.", 1, 0.6, 0.3, true)
	end
	if r.perPoint then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Crafts per point (1 / chance)", ("%.1f"):format(r.craftsPerPoint), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("Per skill-up (net / chance)", (r.perPoint <= 0 and C.good .. "earns " .. Money(-r.perPoint)
			or C.bad .. "costs " .. Money(r.perPoint)) .. "|r", 1, 0.82, 0, 1, 1, 1)
		if r.perPoint < 0 and r.craftsPerPoint > 2 then
			GameTooltip:AddLine(("Makes money, but ~%.0f items per point to sell: check the AH can take them."):format(r.craftsPerPoint), 0.55, 0.55, 0.6, true)
		end
	end
	AddBalance(r)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("The chance shown is for your current skill; it drops as you level.", 0.55, 0.55, 0.6, true)
	GameTooltip:Show()
end

local function ShowTooltip(row)
	local r = row.data
	if not r then
		return
	end
	if View() == "fishing" then
		return PF.ShowFishingTooltip(row, r)
	elseif View() == "upgrades" then
		return ShowUpgradeTooltip(row, r)
	elseif View() == "level" then
		return ShowLevelTooltip(row, r)
	elseif View() == "music" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine(r.name)
		if r.party then
			GameTooltip:AddLine("One key: your character dances, the Party song and video start. Press again or move to stop.", 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine("Key: Esc > Options > Key Bindings > AddOns > CraftWise. Macro: /craftwise party", 0.8, 0.8, 0.8, true)
		else
			GameTooltip:AddLine("Plays while you cast " .. r.name .. " and stops when the cast ends.", 0.8, 0.8, 0.8, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: choose the song, preview it, resume or start over", 0.55, 0.55, 0.6)
		GameTooltip:Show()
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	-- The crafted item's own tooltip first (item level, stats, requirements, other addons' lines),
	-- then a CraftWise section. Recipes without an item output get the CraftWise section only.
	if r.outputItemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.outputItemID)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("CraftWise", C.accent[1], C.accent[2], C.accent[3])
		GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r  " .. StatusLine(r))
	else
		GameTooltip:AddLine((SKILL_COLORS[r.skillColor] or "|cffffffff") .. (r.name or "?") .. "|r")
		GameTooltip:AddLine(StatusLine(r))
	end

	-- Skill-up thresholds (client DB2) and crafts recorded in game (#15). No chance % until verified.
	local yellow, grey = ns.RecipeThresholds(r.recipeID)
	if yellow then
		GameTooltip:AddDoubleLine("Skill-ups", ("|cffffff00yellow %d|r  |cff808080grey %d|r"):format(yellow, grey), 0.8, 0.8, 0.8, 1, 1, 1)
	elseif r.thresholdsUnknown then
		GameTooltip:AddDoubleLine("Skill-ups", "thresholds unknown", 0.8, 0.8, 0.8, 0.6, 0.6, 0.6) -- not in the bundled data (#83)
	end
	local n, ups = ns.SkillUpStats(r.recipeID)
	if n > 0 then
		GameTooltip:AddDoubleLine("Your crafts", ("%d skill-ups in %d crafts"):format(ups, n), 0.8, 0.8, 0.8, 1, 1, 1)
	end

	if r.status ~= "known" then
		if r.learnCost then
			local how = r.learnSource == "vendor" and "vendor" or r.learnSource == "auction" and "AH" or "trainer"
			GameTooltip:AddDoubleLine("To learn", ("%s (%s)"):format(Money(r.learnCost), how), 0.8, 0.8, 0.8, 1, 1, 1)
			if r.learnLabel then
				GameTooltip:AddLine("  " .. r.learnLabel, 0.55, 0.55, 0.6)
			end
		end
		local where = r.where or ns.RecipeWhere(r.recipeID)
		if #where > 0 then
			GameTooltip:AddLine("Where to get it", 1, 0.82, 0)
			for i = 1, math.min(6, #where) do
				local w = where[i]
				local color = w.own == false and C.info or ""
				GameTooltip:AddLine("  " .. color .. w.text .. (w.own == false and (" (" .. (w.faction == "H" and "Horde" or "Alliance") .. ")|r") or "")
					.. (w.label and Muted("  [" .. w.label .. "]") or ""), 0.9, 0.9, 0.9, true)
			end
			if #where > 6 then
				GameTooltip:AddLine(("  +%d more"):format(#where - 6), 0.6, 0.6, 0.6)
			end
		end
		if r.source then
			GameTooltip:AddLine(r.source, 0.8, 0.8, 0.8, true)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Reagents", Muted(PF.CostBasisText(View())), 1, 0.82, 0, 1, 1, 1)
	if #r.reagents == 0 then
		GameTooltip:AddLine("Unknown - open this profession again.", 1, 0.5, 0.25)
	end
	for _, line in ipairs(r.reagents) do
		local left = ("%d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), PriceLabel(line)), 1, 1, 1, 1, 1, 1)
			local detail = ReagentDetail(line)
			if detail then
				GameTooltip:AddLine(detail, 0.55, 0.55, 0.6)
			end
		else
			GameTooltip:AddDoubleLine(left, ns.Market.NO_DATA, 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	AddBalance(r)
	if r.outputItemID then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Sells for", SellText(r), 1, 0.82, 0, 1, 1, 1)
		for _, l in ipairs(SaleOptionLines(r)) do
			GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if r.cutUnverified then
			GameTooltip:AddLine("The AH cut at this house isn't measured yet, so no profit is shown (it is never assumed).", 1, 0.6, 0.3, true)
		end
	end
	AddMarketSection(r)
	if r.oldestAge and r.oldestAge > 1 then
		GameTooltip:AddLine(("Oldest price is %d days old."):format(r.oldestAge), 1, 0.6, 0.3)
	end
	if r.breakEven then
		GameTooltip:AddLine(("Learning pays off after %d crafts."):format(r.breakEven), 0.3, 0.82, 0.55)
	end
	if r.bundledOnly then
		GameTooltip:AddLine("From bundled data - open the profession to confirm.", 0.55, 0.55, 0.6, true)
	elseif r.recordedInGame then
		GameTooltip:AddLine("Recorded in game at a trainer (not in the bundled data).", 0.55, 0.55, 0.6, true)
	end
	GameTooltip:Show()
end

PF.ShowTooltip, PF.SaleOptionLines = ShowTooltip, SaleOptionLines
