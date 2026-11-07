-- Profit table window: the row tooltips of every view.
local _, ns = ...
local PF = ns.PF
local C = ns.Style.colors
local BEST_TEXT, SKILL_COLORS = PF.BEST_TEXT, PF.SKILL_COLORS
local state = PF.state
local Money, Muted, ItemName, StatusLine, View = PF.Money, PF.Muted, PF.ItemName, PF.StatusLine, PF.View

local function ShowBagTooltip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
	else
		GameTooltip:AddLine(r.name)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("CraftWise", C.accent[1], C.accent[2], C.accent[3])
	GameTooltip:AddDoubleLine(("Vendor (x%d)"):format(r.count), r.vendorValue and Money(r.vendorValue) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Auction, after 5% cut", r.ahValue and Money(r.ahValue) or (r.bound and "soulbound" or "no price"), 0.8, 0.8, 0.8, 1, 1, 1)
	if r.canDisenchant then
		GameTooltip:AddDoubleLine("Disenchant", r.deValue and Money(r.deValue) or "needs disenchant data", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if r.questItem then
		GameTooltip:AddLine("Quest item - always kept.", 0.54, 0.7, 1)
	elseif r.kept then
		GameTooltip:AddLine("Kept - not counted.", 0.54, 0.7, 1)
	elseif r.best then
		local line = BEST_TEXT[r.best]:upper()
		if r.margin and r.margin > 0 then
			line = line .. (" pays %s more"):format(Money(r.margin))
		end
		GameTooltip:AddLine(line, 0.3, 0.82, 0.55)
		if r.ahSmallEdge then
			local s = ns.db.settings
			GameTooltip:AddLine(("The AH pays %s more after the 5%% cut - under your AH rule (+%d%% and at least %s), so vendor it: no deposit at risk, no trip to the AH. Change it with \"AH rule\" at the top of the Bags view."):format(
				Money(math.max(0, r.ahSmallEdge)), s.ahMinPercent or 20, Money(s.ahMinCopper or 0)), 0.8, 0.8, 0.8, true)
		end
	end
	local used = ns.UsedIn(r.itemID)
	if #used > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Used in %d %s"):format(#used, #used == 1 and "recipe" or "recipes"), 1, 0.82, 0)
		local shown, lastProf, perProf = 0, nil, 0
		for _, e in ipairs(used) do
			if e.profession ~= lastProf then
				lastProf, perProf = e.profession, 0
				if shown < 14 then
					GameTooltip:AddLine("  " .. e.profession, e.state == "other" and 0.6 or 1, e.state == "other" and 0.6 or 1,
						e.state == "other" and 0.6 or 1)
				end
			end
			perProf = perProf + 1
			if shown < 14 and perProf <= 4 then
				local right
				if e.state == "known" then
					right = C.good .. "known|r"
				elseif e.state == "learnable" then
					right = e.required and ((e.tooLow and C.warn or C.good) .. "learn at " .. e.required .. "|r") or Muted("learnable")
				else
					right = Muted("other profession")
				end
				GameTooltip:AddDoubleLine(("    %s  ×%d"):format(e.name, e.quantity), right, 0.9, 0.9, 0.9, 1, 1, 1)
				shown = shown + 1
			end
		end
		if shown < #used then
			GameTooltip:AddLine(("    +%d more - click the item: Recipes using this"):format(#used - shown), 0.6, 0.6, 0.6)
		end
	else
		GameTooltip:AddLine("Not used in any recipe.", 0.6, 0.6, 0.6)
	end
	if r.ammo then
		GameTooltip:AddLine("Ammo - keep what you shoot.", 0.54, 0.7, 1)
	end
	if r.ahAge and r.ahAge > 1 then
		GameTooltip:AddLine(("AH price is %d days old."):format(r.ahAge), 1, 0.6, 0.3)
	end
	if not r.questItem then
		local how = ({ middle = "middle click", altright = "Alt + right-click" })[ns.db.settings.menuClick or "middle"]
		GameTooltip:AddLine("Click: Keep / Junk / Normal" .. (how and ("  ·  in your bags: " .. how) or ""), 0.55, 0.55, 0.6)
	end
	GameTooltip:Show()
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
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Recipe", (SKILL_COLORS[r.skillColor] or "") .. (r.recipeName or "?") .. "|r", 1, 0.82, 0, 1, 1, 1)
	for _, line in ipairs(r.reagents or {}) do
		local have = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(line.itemID)) or 0
		local color = have >= line.quantity and C.good or C.warn
		GameTooltip:AddDoubleLine(("  %d × %s"):format(line.quantity, ItemName(line.itemID)),
			color .. ("have %d|r"):format(have), 1, 1, 1, 1, 1, 1)
	end
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
	end
	if info.kind == "orange" then
		GameTooltip:AddLine("  Orange: every craft gives a point (100%).", 0.9, 0.9, 0.9, true)
	elseif info.kind == "recipe" then
		GameTooltip:AddLine(("  Your %d crafts of this recipe in the %s: %d points = %d%%."):format(info.n, STAGE_TEXT[info.stage],
			info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
	elseif info.kind == "stage" then
		GameTooltip:AddLine(("  Your %d crafts of all recipes in the %s (between their yellow and grey skill): %d points = %d%%."):format(
			info.n, STAGE_TEXT[info.stage], info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(("  This recipe gets its own rate after %d crafts in this stage."):format(ns.Leveling.MIN_CRAFTS), 0.55, 0.55, 0.6, true)
	elseif info.kind == "color" then
		GameTooltip:AddLine(("  No yellow/grey thresholds for this recipe: your %d %s crafts gave %d points = %d%%."):format(
			info.n, info.color == 1 and "yellow" or "green", info.ups, math.floor(r.chance * 100 + 0.5)), 0.9, 0.9, 0.9, true)
	elseif info.kind == "formula" then
		GameTooltip:AddLine(("  Estimate: (grey - skill) / (grey - yellow) = (%d - %d) / (%d - %d) = %d%%."):format(
			info.grey, info.skill, info.grey, info.yellow, math.floor(r.chance * 100 + 0.5)), 1, 0.6, 0.3, true)
		GameTooltip:AddLine("  Community formula (SkillUp Forever, Skillet), not official. Your own crafts replace it: "
			.. ("%d crafts of any recipe in this stage so far, %d needed."):format(info.n or 0, ns.Leveling.MIN_CRAFTS), 0.55, 0.55, 0.6, true)
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
	GameTooltip:AddLine("One craft", 1, 0.82, 0)
	for _, line in ipairs(r.reagents or {}) do
		local left = ("  %d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), Muted(line.source == "vendor" and "vendor" or "AH")), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	local d = r.saleDetails or {}
	if r.saleSource == "auction" then
		GameTooltip:AddDoubleLine("  Sale: AH after 5% cut", ("%s  %s"):format(Money(r.saleValue), Muted("(" .. Money(d.ahGross or 0) .. " - 5%)")), 1, 1, 1, 0.3, 0.82, 0.55)
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
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("The chance shown is for your current skill; it drops as you level.", 0.55, 0.55, 0.6, true)
	GameTooltip:Show()
end

local function ShowTooltip(row)
	local r = row.data
	if not r then
		return
	end
	if View() == "bags" then
		return ShowBagTooltip(row, r)
	elseif View() == "upgrades" then
		return ShowUpgradeTooltip(row, r)
	elseif View() == "level" then
		return ShowLevelTooltip(row, r)
	elseif View() == "music" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:AddLine(r.name)
		if r.party then
			GameTooltip:AddLine("One key: your character dances, the Party song and video start. Press again or move to stop.", 0.8, 0.8, 0.8, true)
			GameTooltip:AddLine("Key: Esc > Options > Key Bindings > AddOns > CraftWise. Macro: /cw party", 0.8, 0.8, 0.8, true)
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
	end
	local n, ups = ns.SkillUpStats(r.recipeID)
	if n > 0 then
		GameTooltip:AddDoubleLine("Your crafts", ("%d skill-ups in %d crafts"):format(ups, n), 0.8, 0.8, 0.8, 1, 1, 1)
	end

	if r.status ~= "known" then
		if r.learnCost then
			local how = r.learnSource == "vendor" and "vendor" or r.learnSource == "auction" and "AH" or "trainer"
			GameTooltip:AddDoubleLine("To learn", ("%s (%s)"):format(Money(r.learnCost), how), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		local where = r.where or ns.RecipeWhere(r.recipeID)
		if #where > 0 then
			GameTooltip:AddLine("Where to get it", 1, 0.82, 0)
			for i = 1, math.min(6, #where) do
				local w = where[i]
				local color = w.own == false and C.info or ""
				GameTooltip:AddLine("  " .. color .. w.text .. (w.own == false and (" (" .. (w.faction == "H" and "Horde" or "Alliance") .. ")|r") or ""), 0.9, 0.9, 0.9, true)
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
	GameTooltip:AddLine("Reagents", 1, 0.82, 0)
	if #r.reagents == 0 then
		GameTooltip:AddLine("Unknown - open this profession again.", 1, 0.5, 0.25)
	end
	for _, line in ipairs(r.reagents) do
		local left = ("%d × %s"):format(line.quantity, ItemName(line.itemID))
		if line.total then
			local src = line.source == "vendor" and "vendor" or "AH"
			GameTooltip:AddDoubleLine(left, ("%s  %s"):format(Money(line.total), Muted(src)), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(left, "no price", 1, 1, 1, 1, 0.4, 0.4)
		end
	end
	if r.outputItemID then
		GameTooltip:AddLine(" ")
		local sells = r.sellsFor and ("%s  %s"):format(Money(r.sellsFor), Muted(r.sellSource == "vendor" and "vendor" or "AH, after 5% cut")) or "no price"
		GameTooltip:AddDoubleLine("Sells for", sells, 1, 0.82, 0, 1, 1, 1)
	end
	if r.oldestAge and r.oldestAge > 1 then
		GameTooltip:AddLine(("Oldest price is %d days old."):format(r.oldestAge), 1, 0.6, 0.3)
	end
	if r.breakEven then
		GameTooltip:AddLine(("Learning pays off after %d crafts."):format(r.breakEven), 0.3, 0.82, 0.55)
	end
	if r.bundledOnly then
		GameTooltip:AddLine("From bundled data - open the profession to confirm.", 0.55, 0.55, 0.6, true)
	end
	GameTooltip:Show()
end

PF.ShowTooltip = ShowTooltip
