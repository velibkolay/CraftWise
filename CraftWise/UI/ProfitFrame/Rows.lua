-- Profit table window: list rendering. Profession tabs, the summary line, one row per view, the scroll bar.
local _, ns = ...
local PF = ns.PF
local Style, L, C = ns.Style, ns.L, ns.Style.colors
local PAD, VISIBLE_ROWS = PF.PAD, PF.VISIBLE_ROWS
local QUALITY_COLORS, BEST_TEXT, SKILL_COLORS = PF.QUALITY_COLORS, PF.BEST_TEXT, PF.SKILL_COLORS
local tabs, state = PF.tabs, PF.state
local Money, Muted, StatusLine, View = PF.Money, PF.Muted, PF.StatusLine, PF.View

local function RenderTabs(ids)
	for i, id in ipairs(ids) do
		local tab = tabs[i]
		if not tab then
			tab = Style.Button(PF.frame, 160, 26)
			tab:SetPoint("TOPLEFT", PAD + (i - 1) * 166, -58)
			tabs[i] = tab
		end
		local prof = ns.charDB.professions[id]
		tab:SetLabel(("%s  %s%d/%d|r"):format(prof.name or "?", C.muted, prof.skill or 0, prof.maxSkill or 0))
		tab:SetIcon(ns.ProfessionIcon(id))
		tab:SetSelected(id == state.professionID)
		tab:SetScript("OnClick", function()
			state.professionID, state.offset = id, 0
			ns.RefreshProfitFrame()
		end)
		tab:Show()
	end
	for i = #ids + 1, #tabs do
		tabs[i]:Hide()
	end
end

-- The view's reagent cost basis for its header (#47), with how many rows fell back to AH prices.
local function BasisNote(view)
	local text = PF.CostBasisText(view)
	if ns.CostBasis(view) == "paid" then
		local fallback = 0
		for _, r in ipairs(state.data) do
			if r.paidFallbacks then
				fallback = fallback + 1
			end
		end
		if fallback > 0 then
			text = text .. (" (%d %s with reagents at AH)"):format(fallback, fallback == 1 and "row" or "rows")
		end
	end
	return text
end

local function RenderSummary(ids)
	local text
	if View() == "music" then
		local songs = #ns.Music.SongNames()
		if songs == 0 then
			text = C.warn .. "No songs yet.|r " .. Muted("Put .mp3 or .ogg files in ") .. ns.Music.FOLDER_TEXT
				.. "\n" .. Muted("restart the game, then click a profession and add the file by name.")
		else
			text = ("%s%d|r songs  ·  music plays while you cast a profession and stops when the cast ends"):format(C.good, songs)
				.. "\n" .. Muted("Click a profession to choose its song, preview it, and pick resume or start over.")
		end
	elseif View() == "upgrades" then
		local ready, dismissed = 0, state.hidden
		for _, r in ipairs(state.data) do
			if r.dismissed then
				dismissed = dismissed + 1
			elseif r.haveReagents then
				ready = ready + 1
			end
		end
		text = ("%d upgrades from your recipes  ·  %s%d|r you can craft right now"):format(#state.data - (dismissed - state.hidden), C.good, ready)
			.. Muted("  ·  " .. BasisNote("upgrades"))
		if dismissed > 0 then
			text = text .. Muted(("  ·  %d dismissed"):format(dismissed))
		end
		text = text .. "\n" .. Muted("Upgrade = higher item level, or same item level with more armour. Hover for the stat changes.")
	elseif View() == "bags" then
		local vendor, auction, best, deable, kept = 0, 0, 0, 0, 0
		for _, r in ipairs(state.data) do
			if r.kept then
				kept = kept + 1
			else
				vendor = vendor + (r.vendorValue or 0)
				auction = auction + (r.ahValue or 0)
				best = best + (r.bestValue or 0)
				if r.canDisenchant then
					deable = deable + 1
				end
			end
		end
		text = ("%d items to sell  ·  best total %s%s|r  ·  vendor %s  ·  auction %s"):format(#state.data - kept, C.good,
			Money(best), Money(vendor), Money(auction))
		kept = kept + state.hidden
		if kept > 0 then
			text = text .. Muted(("  ·  %d kept"):format(kept))
		end
		if deable > 0 and not ns.DisenchantData then
			text = text .. "\n" .. Muted(("%d %s can be disenchanted; disenchant values come with the disenchant data (issue #11)."):format(deable, deable == 1 and "item" or "items"))
		end
	elseif #ids == 0 then
		text = C.warn .. "Open a profession window once so CraftWise can read your recipes.|r"
	elseif View() == "level" then
		local best
		for _, r in ipairs(state.data) do
			if r.perPoint and (not best or r.perPoint < best.perPoint) then
				best = r
			end
		end
		local prof = ns.charDB.professions[state.professionID]
		text = ("%s %s%d|r/%d"):format(prof and prof.name or "", C.good, state.levelSkill or 0, prof and prof.maxSkill or 0)
		if best then
			local money = best.perPoint <= 0 and (C.good .. "earns " .. Money(-best.perPoint)) or (C.warn .. "costs " .. Money(best.perPoint))
			text = text .. ("  ·  best: |cffffffff%s|r %s|r per skill-up"):format(best.name or "?", money)
		else
			text = text .. "  ·  " .. C.warn .. "no recipe with both a chance and reagent prices yet|r"
		end
		text = text .. ("  ·  %d crafts recorded"):format(ns.CraftsRecorded()) .. Muted("  ·  " .. BasisNote("level"))
			.. "\n" .. Muted("Per skill-up = (reagents - sale) / chance. Orange always, grey never (hidden), yellow and green from your recorded crafts (~ = formula estimate until you have some). Hover a row for the maths.")
	elseif View() == "learn" then
		local withSource, fits = 0, 0
		for _, r in ipairs(state.data) do
			if r.whereText then
				withSource = withSource + 1
			end
			if r.required and not r.tooLow then
				fits = fits + 1
			end
		end
		text = ("%d recipes to learn  ·  %s%d|r with a known source  ·  %s%d|r fit your skill"):format(#state.data, C.good, withSource, C.good, fits)
			.. Muted("  ·  " .. BasisNote("learn"))
		if withSource == 0 then
			text = text .. "\n" .. Muted("Sources come with the recipe data (issue #11). Recipes your trainer teaches appear after you open the trainer once.")
		end
		if state.hidden > 0 then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
	elseif not ns.HasAuctionator() and not ns.Market.HasAnyData() then
		text = C.warn .. "No auction prices yet.|r " .. Muted("Only vendor prices are used. Search or run a scan at an auction house (Auctionator's Full Scan works too).")
	else
		local profitable, priced, unpriced, uncut = 0, 0, 0, 0
		for _, r in ipairs(state.data) do
			if r.profit then
				priced = priced + 1
				if r.profit > 0 then
					profitable = profitable + 1
				end
			elseif r.cutUnverified then
				uncut = uncut + 1
			elseif not r.noItemOutput then
				unpriced = unpriced + 1
			end
		end
		text = ("%s%d|r of %d priced recipes make a profit"):format(C.good, profitable, priced)
		if uncut > 0 then
			text = text .. ("  ·  %s%d|r %s"):format(C.warn, uncut, Muted("sell where the AH cut is unverified"))
		end
		if unpriced > 0 then
			text = text .. Muted(("  ·  %d without a price (reagent or item not on the AH)"):format(unpriced))
		end
		if state.hidden > 0 then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
		text = text .. "\n" .. Muted("Auction prices: " .. PF.PriceBasisText() .. ", else " .. ns.AUCTIONATOR_LABEL .. "  ·  "
			.. BasisNote("profit") .. ". Change them in Settings: gear button.")
	end
	PF.frame.summary:SetText(text)
end

local function RenderBagRow(row, r)
	row.icon:SetTexture(r.icon or 134400)
	row.icon:SetDesaturated(r.kept)
	row.name:SetText((r.kept and C.muted or (QUALITY_COLORS[r.quality] or "|cffffffff")) .. r.name .. "|r")
	local notes = { ("x%d"):format(r.count) }
	if r.bound then
		notes[#notes + 1] = "soulbound"
	end
	if r.canDisenchant then
		notes[#notes + 1] = "can be disenchanted"
	end
	if r.reagent then
		notes[#notes + 1] = C.info .. "reagent for your recipes|r" .. C.muted
	end
	if r.ammo then
		notes[#notes + 1] = C.info .. "ammo|r" .. C.muted
	end
	row.status:SetText(Muted(table.concat(notes, " · ")))
	local cells = row.cells
	cells.vendorValue:SetText(r.vendorValue and Money(r.vendorValue) or Muted("-"))
	cells.ahValue:SetText(r.ahValue and Money(r.ahValue) or Muted(r.bound and "bound" or r.ahCutUnverified and "cut ?" or "-"))
	-- Used in: up to two professions, the ones you have first. Green = you know a recipe with it,
	-- white = your profession, grey = another profession.
	local parts = {}
	for i, g in ipairs(r.usedIn or {}) do
		if i > 2 then
			parts[#parts + 1] = Muted(("+%d"):format(#r.usedIn - 2))
			break
		end
		local color = g.known > 0 and C.good or g.mine and "|cffffffff" or C.muted
		parts[#parts + 1] = ("%s%s %d|r"):format(color, g.profession, g.count)
	end
	cells.usedCount:SetText(#parts > 0 and table.concat(parts, Muted("  ·  ")) or Muted("-"))
	if r.deValue then
		cells.deValue:SetText(Money(r.deValue))
	else
		cells.deValue:SetText(Muted(r.canDisenchant and "?" or "-"))
	end
	if r.junk then
		cells.bestValue:SetText(C.bad .. L["Junk"] .. "|r" .. Muted("  " .. L["sold with Sell junk"]))
	elseif r.markedAH then
		cells.bestValue:SetText(C.good .. L["Auction"] .. "|r" .. Muted("  " .. L["marked"]))
	elseif r.questItem then
		cells.bestValue:SetText(C.info .. "Quest item|r")
	elseif r.kept then
		cells.bestValue:SetText(C.info .. "Kept|r")
	elseif r.best and r.ahSmallEdge then
		local more = r.ahSmallEdge > 0 and ("AH +" .. Money(r.ahSmallEdge) .. ", too little") or "AH no better"
		cells.bestValue:SetText(C.good .. BEST_TEXT[r.best] .. "|r" .. Muted("  " .. more))
	elseif r.best then
		local margin = r.margin and r.margin > 0 and Muted(("  +%s"):format(Money(r.margin))) or ""
		cells.bestValue:SetText(C.good .. BEST_TEXT[r.best] .. "|r" .. margin)
	else
		cells.bestValue:SetText(Muted("no value"))
	end
	row:Show()
end

local function RenderUpgradeRow(row, r)
	row.icon:SetTexture(r.icon or 134400)
	row.icon:SetDesaturated(r.dismissed)
	row.name:SetText((r.dismissed and C.muted or (QUALITY_COLORS[r.quality] or "|cffffffff")) .. r.name .. "|r")
	local notes = { r.slotLabel, ("ilvl %d"):format(r.level or 0) }
	if r.dismissed then
		notes[#notes + 1] = C.info .. "dismissed|r" .. C.muted
	elseif r.haveReagents then
		notes[#notes + 1] = C.good .. "reagents in bags|r" .. C.muted
	end
	row.status:SetText(Muted(table.concat(notes, " · ")))
	local cells = row.cells
	if r.emptySlot then
		cells.equippedText:SetText(Muted("empty slot"))
	else
		cells.equippedText:SetText((QUALITY_COLORS[r.current.quality] or "") .. (r.equippedText or "?") .. "|r")
	end
	local parts = {}
	if r.emptySlot then
		parts[1] = C.good .. "fills the slot|r"
	else
		if r.ilvlGain ~= 0 then
			parts[#parts + 1] = (r.ilvlGain > 0 and C.good .. "+" or C.bad) .. r.ilvlGain .. " ilvl|r"
		end
		if r.armorGain ~= 0 then
			parts[#parts + 1] = (r.armorGain > 0 and C.good .. "+" or C.bad) .. r.armorGain .. " armor|r"
		end
	end
	cells.gain:SetText(#parts > 0 and table.concat(parts, "  ") or Muted("same"))
	if r.costComplete then
		cells.cost:SetText(Money(r.cost))
	elseif r.cost and r.cost > 0 then
		cells.cost:SetText(Money(r.cost) .. C.warn .. " +?|r")
	else
		cells.cost:SetText(Muted("-"))
	end
	row:Show()
end

local function RenderMusicRow(row, r)
	row.icon:SetTexture(r.icon or 134400)
	row.icon:SetDesaturated(not r.song)
	row.name:SetText("|cffffffff" .. r.name .. "|r")
	if r.party then
		row.status:SetText(Muted(ns.Music.PartyActive() and (C.good .. "on|r  ·  press the key again or move to stop")
			or "key: Key Bindings > AddOns > CraftWise, or /craftwise party"))
	else
		row.status:SetText(r.skill and Muted(("%d/%d"):format(r.skill, r.maxSkill or 0)) or "")
	end
	local playing, prof = ns.Music.IsPlaying()
	local note = playing and prof == r.name and ("  " .. C.good .. "playing|r") or ""
	row.cells.songText:SetText(r.song and (r.song:gsub("_", " ") .. note) or Muted("none  -  click to choose"))
	if not r.song then
		row.cells.modeText:SetText("")
	elseif r.mode == "restart" then
		row.cells.modeText:SetText("Start from the beginning")
	else
		row.cells.modeText:SetText("Resume where it stopped" .. (r.position and Muted(("  (part %d)"):format(r.position)) or ""))
	end
	row:Show()
end

local CHANCE_KIND = {
	orange = "orange: always",
	recipe = "your crafts",
	stage = "all your crafts",
	color = "all your crafts",
}

local function RenderLevelRow(row, r)
	row.icon:SetDesaturated(false)
	row.icon:SetTexture(r.icon or 134400)
	local color = SKILL_COLORS[r.skillColor] or "|cffffffff"
	row.name:SetText(color .. (r.name or ("Recipe " .. r.recipeID)) .. "|r")
	local notes = {}
	if r.thresholdYellow then
		notes[#notes + 1] = ("yellow %d · grey %d"):format(r.thresholdYellow, r.thresholdGrey)
	end
	if r.craftsPerPoint then
		notes[#notes + 1] = ("~%.1f crafts per point"):format(r.craftsPerPoint)
	end
	row.status:SetText(Muted(table.concat(notes, "  ·  ")))
	local cells = row.cells
	local info = r.chanceInfo or {}
	if r.chance and info.kind == "formula" then
		cells.chance:SetText(C.warn .. ("~%d%%"):format(math.floor(r.chance * 100 + 0.5)) .. "|r  " .. Muted("estimate"))
	elseif r.chance then
		local pct = ("%d%%"):format(math.floor(r.chance * 100 + 0.5))
		local how = info.n and ("%s %d/%d"):format(CHANCE_KIND[info.kind], info.ups, info.n) or CHANCE_KIND[info.kind]
		cells.chance:SetText(C.good .. pct .. "|r  " .. Muted(how or ""))
	else
		cells.chance:SetText(Muted(("no data yet (%d crafts)"):format(info.n or 0)))
	end
	if r.costComplete then
		cells.cost:SetText(Money(r.cost))
	elseif r.cost and r.cost > 0 then
		cells.cost:SetText(Money(r.cost) .. C.warn .. " +?|r")
	else
		cells.cost:SetText(Muted("-"))
	end
	if r.saleSource == "none" then
		cells.saleValue:SetText(Muted("no item"))
	elseif r.saleValue then
		cells.saleValue:SetText(Money(r.saleValue) .. Muted(r.saleSource == "auction" and " AH" or " vendor"))
	else
		cells.saleValue:SetText(Muted("no price"))
	end
	if r.net then
		cells.net:SetText((r.net <= 0 and (C.good .. "+" .. Money(-r.net)) or (C.bad .. "-" .. Money(r.net))) .. "|r")
	else
		cells.net:SetText(Muted("-"))
	end
	if r.perPoint then
		local money = r.perPoint <= 0 and (C.good .. "+" .. Money(-r.perPoint)) or (C.bad .. "-" .. Money(r.perPoint))
		cells.perPoint:SetText(money .. "|r")
	else
		cells.perPoint:SetText(Muted("-"))
	end
	row:Show()
end

local function RenderRow(row, r, index)
	row.data = r
	row.stripe:SetShown(index % 2 == 0)
	if View() == "music" then
		return RenderMusicRow(row, r)
	end
	if View() == "bags" then
		return RenderBagRow(row, r)
	elseif View() == "level" then
		return RenderLevelRow(row, r)
	elseif View() == "upgrades" then
		return RenderUpgradeRow(row, r)
	end
	row.icon:SetDesaturated(false)
	row.icon:SetTexture(r.icon or 134400)
	local color = SKILL_COLORS[r.skillColor] or "|cffffffff"
	row.name:SetText(color .. (r.name or ("Recipe " .. r.recipeID)) .. "|r")
	row.status:SetText(StatusLine(r) .. (r.thin and ("  " .. C.warn .. "thin market|r") or ""))

	local cells = row.cells
	if r.costComplete then
		cells.cost:SetText(Money(r.cost))
	elseif r.cost > 0 then
		cells.cost:SetText(Money(r.cost) .. C.warn .. " +?|r")
	else
		cells.cost:SetText(Muted("-"))
	end

	if r.noItemOutput then
		cells.sellsFor:SetText(Muted("no item"))
	else
		local tag = PF.SaleTag(r.sellSource, r.cutUnverified)
		local tagText = tag and ("  " .. (r.cutUnverified and (C.warn .. tag .. "|r") or Muted(tag))) or ""
		cells.sellsFor:SetText(r.sellsFor and (Money(r.sellsFor) .. tagText) or Muted("-"))
	end

	if r.profit then
		cells.profit:SetText((r.profit >= 0 and C.good .. "+" or C.bad) .. Money(r.profit) .. "|r")
	elseif r.cutUnverified then
		cells.profit:SetText(C.warn .. "cut unverified|r")
	else
		cells.profit:SetText(Muted("-"))
	end

	cells.learnCost:SetText(r.learnCost and Money(r.learnCost) or "")
	cells.breakEven:SetText(r.breakEven and ("%d crafts"):format(r.breakEven) or "")
	if r.required then
		cells.required:SetText((r.tooLow and C.warn or C.good) .. r.required .. "|r")
	else
		cells.required:SetText(Muted("?"))
	end
	if r.whereText then
		local more = #r.where > 1 and Muted(("  +%d"):format(#r.where - 1)) or ""
		cells.whereText:SetText(r.whereText .. (r.whereLabel and Muted("  " .. r.whereLabel) or "") .. more)
	else
		cells.whereText:SetText(Muted("Not known yet"))
	end
	row:Show()
end

local function UpdateScrollBar()
	local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
	local bar = PF.frame.scrollBar
	bar.updating = true
	bar:SetMinMaxValues(0, maxOffset)
	bar:SetValue(state.offset)
	bar.updating = false
	bar:SetShown(maxOffset > 0)
end

PF.RenderTabs, PF.RenderSummary, PF.RenderRow, PF.UpdateScrollBar =
	RenderTabs, RenderSummary, RenderRow, UpdateScrollBar
