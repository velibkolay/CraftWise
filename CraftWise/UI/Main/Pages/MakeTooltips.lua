-- Main window, Make: the hover tooltips of recipe rows (Craft, Learn) and skill-up rows (Level up). Moved
-- from the profit window's Tooltips.lua (#154) with the same lines: the crafted item's own tooltip, then
-- a CraftWise section with skill-up thresholds, where to get it, every reagent with its price source
-- (#47), what you hold and the buy list (#49, #60), both sale options (#48) and the auction houses
-- (#26); Level up explains the chance and the maths. Colours follow the Origami palette: white for
-- values, C.danger for warnings, grey for notes.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style = ns.Style

local GOOD, WARN, BAD, INFO = Style.Hex("text"), Style.Hex("danger"), Style.Hex("danger"), Style.Hex("text2")
local HEAD = Style.C.keyGold -- section headings
local NOTE = { 0.55, 0.55, 0.6 }
local ORANGE = { Style.C.danger[1], Style.C.danger[2], Style.C.danger[3] }

local function Money(copper)
	return ns.FormatMoney(copper)
end

local function Muted(text)
	return Style.Hex("text3") .. text .. "|r"
end

local ItemName = MK.ItemName

local function Heading(text, right)
	if right then
		GameTooltip:AddDoubleLine(text, right, HEAD[1], HEAD[2], HEAD[3], 1, 1, 1)
	else
		GameTooltip:AddLine(text, HEAD[1], HEAD[2], HEAD[3])
	end
end

local function Note(text, wrap)
	GameTooltip:AddLine(text, NOTE[1], NOTE[2], NOTE[3], wrap)
end

local function Warn(text, wrap)
	GameTooltip:AddLine(text, ORANGE[1], ORANGE[2], ORANGE[3], wrap)
end

local function SkillName(r)
	local color = MK.NameColor(r)
	return Style.Hex(color) .. (r.name or "?") .. "|r"
end

local STATUS_TEXT = {
	known = "Known",
	trainable = "Trainer",
	vendor = "Vendor recipe",
	drop = "Drop recipe",
	quest = "Quest recipe",
	unlearned = "Source not known yet",
}

local function StatusLine(r)
	local text = STATUS_TEXT[r.status] or r.status or ""
	if r.status == "known" then
		return Muted(text)
	end
	local parts = { text }
	if r.required then
		parts[#parts + 1] = ("skill %d"):format(r.required)
	end
	local color = GOOD
	if r.tooLow then
		color = Style.Hex("skill.orange")
	elseif r.status == "unlearned" then
		color = Style.Hex("text3")
	end
	return color .. table.concat(parts, " · ") .. "|r"
end
MK.StatusLine = StatusLine

-- Where a price came from: "vendor", or the auction label ("typical · Horde AH",
-- "Auctionator (house unknown)"), plus a thin-market mark.
local function PriceLabel(line)
	local text
	if line.source == "vendor" then
		text = Muted("vendor")
	elseif line.source == "crafted" then
		text = GOOD .. "crafted|r"
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
MK.ReagentDetail = ReagentDetail

-- "Sells for" line: the chosen value and its tag (#48).
local function SellText(r)
	if not r.sellsFor then
		return ns.Market.NO_DATA
	end
	local tag = MK.SaleTag(r.sellSource, r.cutUnverified)
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
		l[1] = l[3] and (GOOD .. "  " .. l[1] .. " (used)|r") or Muted("  " .. l[1])
	end
	return lines
end
MK.SaleOptionLines = SaleOptionLines

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

local function AddLines(lines)
	for _, l in ipairs(lines) do
		GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
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
	Heading("Auction houses  " .. Muted("prices: " .. MK.PriceBasisText()))
	if #buy > 0 then
		GameTooltip:AddLine("Reagents, one craft", 0.9, 0.9, 0.9)
		AddLines(buy)
	end
	if #sell > 0 then
		GameTooltip:AddLine("Crafted item", 0.9, 0.9, 0.9)
		AddLines(sell)
	end
end

-- Vendor check (#185): per reagent the AH and vendor unit prices and the one the cost used, then the
-- vendor sale and profit, and the loop when it holds. Pure data comes from Profit.VendorCheck.
function MK.AddVendorCheck(r)
	GameTooltip:AddLine(" ")
	Heading("Vendor check", r.vendorLoop and (GOOD .. "loop|r") or nil)
	for _, line in ipairs(r.reagents or {}) do
		local ah = line.ahUnit and Money(line.ahUnit) or Muted("no AH price")
		local vendor = line.vendorBuy and Money(line.vendorBuy) or Muted("not sold by a vendor")
		local used = line.source == "vendor" and "vendor" or line.source == "auction" and "AH"
			or line.source == "paid" and "paid cost" or line.source == "crafted" and "crafted" or "none"
		GameTooltip:AddDoubleLine(("%d × %s"):format(line.quantity, ItemName(line.itemID)),
			("AH %s · vendor %s · used: %s"):format(ah, vendor, used), 1, 1, 1, 1, 1, 1)
	end
	if r.vendorSale then
		GameTooltip:AddDoubleLine("Vendor sale", Money(r.vendorSale), 0.8, 0.8, 0.8, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Vendor sale", Muted("vendors don't buy it / price not known"), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if r.vendorProfit then
		GameTooltip:AddDoubleLine("Vendor profit (sale - reagents as used)", (r.vendorProfit < 0 and BAD .. "-" or GOOD .. "+")
			.. Money(math.abs(r.vendorProfit)) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if r.vendorCost then
		GameTooltip:AddDoubleLine("Reagents all at vendors", Money(r.vendorCost), 0.8, 0.8, 0.8, 1, 1, 1)
	end
end

-- Disenchant check (#190): the materials with chance, expected quantity and price, the value and where it
-- comes from (sample count, or the Classic table (guide)); "few samples" is a warning.
function MK.AddDisenchantCheck(r)
	local d = r.deDetails
	if not d then
		return
	end
	GameTooltip:AddLine(" ")
	Heading("Disenchant check", Muted(d.sourceLabel or ""))
	for _, m in ipairs(d.materials or {}) do
		local qty = m.min and m.max and m.min ~= m.max and ("%d-%d"):format(m.min, m.max) or ("%g"):format(m.perHit or 1)
		GameTooltip:AddDoubleLine(("%s × %s  %s%d%%|r"):format(qty, ItemName(m.itemID), Muted(""), math.floor(m.chance * 100 + 0.5)),
			("%s each %s"):format(Money(math.floor(m.unit + 0.5)), Muted(m.from == "vendor" and "vendor" or "AH")), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("Expected value", Money(math.floor(r.deValue + 0.5)), 0.8, 0.8, 0.8, 1, 1, 1)
	if r.deProfit then
		GameTooltip:AddDoubleLine("Profit (value - reagents)", (r.deProfit < 0 and BAD .. "-" or GOOD .. "+")
			.. Money(math.floor(math.abs(r.deProfit) + 0.5)) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if d.few then
		Warn(("Few samples (%d, Settings asks for %d): treat this value as rough."):format(d.samples or 0, ns.Disenchant.MinSamples()), true)
	elseif d.source == "guide" then
		Note("No measured disenchants of this item or its kind: the Classic baseline, not measured on Forever.", true)
	end
	if ns.Disenchant.SalvagerActive() then
		Note("Arcane Salvager is active: salvager samples are used.", true)
	end
end

local function CraftWiseHeader()
	GameTooltip:AddLine(("|T%s:12|t %sCraftWise|r"):format(Style.Media.keyW, Style.Hex("keyGold")))
end

-- Craft and Learn: the crafted item's own tooltip first (item level, stats, requirements, other addons'
-- lines), then the CraftWise section. Recipes without an item output get the CraftWise section only.
-- view: the reagent cost basis ("profit" | "learn").
function MK.ShowRecipeTooltip(owner, r, view)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if r.outputItemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.outputItemID)
		GameTooltip:AddLine(" ")
		CraftWiseHeader()
		GameTooltip:AddLine(SkillName(r) .. "  " .. StatusLine(r))
	else
		GameTooltip:AddLine(SkillName(r))
		GameTooltip:AddLine(StatusLine(r))
	end

	-- Skill-up thresholds (client DB2) and crafts recorded in game (#15).
	local yellow, grey = ns.RecipeThresholds(r.recipeID)
	if yellow then
		GameTooltip:AddDoubleLine("Skill-ups", ("%syellow %d|r  %sgrey %d|r"):format(Style.Hex("skill.yellow"), yellow,
			Style.Hex("skill.grey"), grey), 0.8, 0.8, 0.8, 1, 1, 1)
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
				Note("  " .. r.learnLabel)
			end
		end
		local where = r.where or ns.RecipeWhere(r.recipeID)
		if #where > 0 then
			Heading("Where to get it")
			for i = 1, math.min(6, #where) do
				local w = where[i]
				local color = w.own == false and INFO or ""
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
	Heading("Reagents", Muted(MK.CostBasisText(view or "profit")))
	if #(r.reagents or {}) == 0 then
		Warn("Unknown - open this profession again.")
	end
	for _, line in ipairs(r.reagents or {}) do
		local left = ("%d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), PriceLabel(line)), 1, 1, 1, 1, 1, 1)
			local detail = ReagentDetail(line)
			if detail then
				Note(detail)
			end
		else
			GameTooltip:AddDoubleLine(left, ns.Market.NO_DATA, 1, 1, 1, ORANGE[1], ORANGE[2], ORANGE[3])
		end
	end
	AddBalance(r)
	if r.vendorView or r.vendorLoop then
		MK.AddVendorCheck(r)
	end
	if r.disenchantView then
		MK.AddDisenchantCheck(r)
	end
	if r.outputItemID then
		GameTooltip:AddLine(" ")
		Heading("Sells for", SellText(r))
		for _, l in ipairs(SaleOptionLines(r)) do
			GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if r.cutUnverified then
			Warn("The AH cut at this house isn't measured yet, so no profit is shown (it is never assumed).", true)
		end
	end
	AddMarketSection(r)
	if r.oldestAge and r.oldestAge > 1 then
		Warn(("Oldest price is %d days old."):format(r.oldestAge))
	end
	if r.breakEven then
		GameTooltip:AddLine(("Learning pays off after %d crafts."):format(r.breakEven), 1, 1, 1)
	end
	if r.bundledOnly then
		Note("From bundled data - open the profession to confirm.", true)
	elseif r.recordedInGame then
		Note("Recorded in game at a trainer (not in the bundled data).", true)
	end
	GameTooltip:Show()
end

local STAGE_TEXT = { "1st quarter after yellow", "2nd quarter", "3rd quarter", "last quarter before grey" }

-- Level up: the chance of a skill point and how it was found, one craft's money, per skill-up.
function MK.ShowLevelTooltip(owner, r, skill)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(SkillName(r))
	local info = r.chanceInfo or {}
	GameTooltip:AddLine(" ")
	Heading("Chance of a skill point")
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
		Note(("  This recipe gets its own rate after %d crafts in this stage."):format(ns.Leveling.MIN_CRAFTS), true)
	elseif info.kind == "color" then
		GameTooltip:AddLine(("  No yellow/grey thresholds for this recipe: your %d %s crafts gave %d points = %d%%."):format(
			info.n, info.color == 1 and "yellow" or "green", info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
	elseif info.kind == "formula" then
		GameTooltip:AddLine(("  Estimate: (grey - skill) / (grey - yellow) = (%d - %d) / (%d - %d) = %d%%."):format(
			info.grey, info.skill, info.grey, info.yellow, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
		Note("  Community formula (SkillUp Forever, Skillet), not official. Your own crafts replace it: "
			.. ("%d crafts of any recipe of this profession in this stage so far, %d needed."):format(info.n or 0, ns.Leveling.MIN_CRAFTS), true)
	else
		Warn(("  Not enough crafts recorded yet (%d, need %d), and no yellow/grey thresholds for an estimate."):format(
			info.n or 0, ns.Leveling.MIN_CRAFTS), true)
	end
	-- The formula next to a measured rate, as a reference.
	if info.kind == "recipe" or info.kind == "stage" then
		local est = ns.Leveling.Formula(skill, r.thresholdYellow, r.thresholdGrey)
		if est then
			Note(("  For reference, the community formula says %d%%."):format(math.floor(est * 100 + 0.5)), true)
		end
	end
	GameTooltip:AddLine(" ")
	Heading("One craft", Muted(MK.CostBasisText("level")))
	for _, line in ipairs(r.reagents or {}) do
		local left = ("  %d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), PriceLabel(line)), 1, 1, 1, 1, 1, 1)
			local detail = ReagentDetail(line)
			if detail then
				Note(detail)
			end
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, ORANGE[1], ORANGE[2], ORANGE[3])
		end
	end
	local d = r.saleDetails or {}
	if r.saleSource == "auction" then
		local pct = ("%g%%"):format((d.cut or 0) * 100)
		GameTooltip:AddDoubleLine("  Sale: AH after " .. pct .. " cut", ("%s  %s"):format(Money(r.saleValue), Muted("(" .. Money(d.ahGross or 0) .. " - " .. pct .. ")")), 1, 1, 1, 1, 1, 1)
		if d.label then
			Note("    " .. d.label .. " · " .. (d.cutDiffers and WARN or "") .. (d.cutText or "") .. (d.cutDiffers and "|r" or ""))
		end
		if d.vendor then
			GameTooltip:AddDoubleLine("  (vendor would pay)", Money(d.vendor), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
	elseif r.saleSource == "vendor" then
		GameTooltip:AddDoubleLine("  Sale: vendor", Money(r.saleValue), 1, 1, 1, 1, 1, 1)
		if d.ahNet then
			GameTooltip:AddLine(("  AH after cut: %s - under your AH rule, so vendor."):format(Money(d.ahNet)), 0.6, 0.6, 0.6, true)
		end
	elseif r.saleSource == "none" then
		GameTooltip:AddLine("  No item made: sale 0.", 0.8, 0.8, 0.8)
	else
		Warn("  Sale price unknown: counted as 0.")
	end
	if d.cutUnverified then
		Warn(("  AH %s gross (%s): cut unverified there, so not counted."):format(Money(d.ahGross or 0), d.label or "?"), true)
	end
	if r.net then
		GameTooltip:AddDoubleLine("  Net per craft (reagents - sale)", (r.net <= 0 and GOOD .. "+" .. Money(-r.net) or BAD .. "-" .. Money(r.net)) .. "|r",
			HEAD[1], HEAD[2], HEAD[3], 1, 1, 1)
	else
		Warn("  Reagent price missing - can't rank this recipe.", true)
	end
	if r.perPoint then
		GameTooltip:AddLine(" ")
		Heading("Crafts per point (1 / chance)", ("%.1f"):format(r.craftsPerPoint))
		Heading("Per skill-up (net / chance)", (r.perPoint <= 0 and GOOD .. "earns " .. Money(-r.perPoint)
			or BAD .. "costs " .. Money(r.perPoint)) .. "|r")
		if r.perPoint < 0 and r.craftsPerPoint > 2 then
			Note(("Makes money, but ~%.0f items per point to sell: check the AH can take them."):format(r.craftsPerPoint), true)
		end
	end
	AddBalance(r)
	GameTooltip:AddLine(" ")
	Note("The chance shown is for your current skill; it drops as you level.", true)
	GameTooltip:Show()
end
