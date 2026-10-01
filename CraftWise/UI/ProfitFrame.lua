-- Profit table window. Opens from the minimap button, the addon compartment or /cw.
-- Built lazily on first open, from plain widgets only.
local _, ns = ...
local Style = ns.Style
local C = Style.colors

local WIDTH, HEIGHT = 900, 580
local PAD = 16
local ROW_HEIGHT = 36
local HEADER_Y = -150 -- top of the column header row
local LIST_TOP = HEADER_Y - 22
local VISIBLE_ROWS = math.floor((HEIGHT + LIST_TOP - 40) / ROW_HEIGHT)

-- Column definitions; each view lists the columns it shows, in order, with widths.
local COLUMN_DEFS = {
	name = { label = "RECIPE", align = "LEFT" },
	cost = { label = "COST", align = "RIGHT" },
	sellsFor = { label = "SELLS FOR", align = "RIGHT" },
	profit = { label = "PROFIT", align = "RIGHT" },
	learnCost = { label = "TO LEARN", align = "RIGHT" },
	breakEven = { label = "PAYS OFF", align = "RIGHT" },
	required = { label = "SKILL", align = "RIGHT" },
	whereText = { label = "WHERE TO GET IT", align = "LEFT" },
	vendorValue = { label = "VENDOR", align = "RIGHT" },
	ahValue = { label = "AUCTION", align = "RIGHT" },
	deValue = { label = "DISENCHANT", align = "RIGHT" },
	bestValue = { label = "BEST", align = "LEFT" },
	equippedText = { label = "REPLACES", align = "LEFT" },
	gain = { label = "UPGRADE", align = "LEFT" },
	songText = { label = "SONG", align = "LEFT" },
	modeText = { label = "NEXT CAST", align = "LEFT" },
}
local VIEWS = {
	-- Profit: what to craft. The learn columns only show with unlearned recipes.
	profit = {
		{ key = "name", width = 290 },
		{ key = "cost", width = 100 },
		{ key = "sellsFor", width = 100 },
		{ key = "profit", width = 100 },
		{ key = "learnCost", width = 95, learn = true },
		{ key = "breakEven", width = 75, learn = true },
	},
	-- Learn: every recipe you don't know yet, where to get it and what it earns.
	learn = {
		{ key = "name", width = 245 },
		{ key = "required", width = 50 },
		{ key = "whereText", width = 280 },
		{ key = "learnCost", width = 95 },
		{ key = "profit", width = 100 },
	},
	-- Bags: what to do with every item you carry.
	bags = {
		{ key = "name", width = 270 },
		{ key = "vendorValue", width = 100 },
		{ key = "ahValue", width = 100 },
		{ key = "deValue", width = 100 },
		{ key = "bestValue", width = 180 },
	},
	-- Upgrades: items from your recipes that beat what you wear.
	upgrades = {
		{ key = "name", width = 280 },
		{ key = "equippedText", width = 220 },
		{ key = "gain", width = 150 },
		{ key = "cost", width = 110 },
	},
	-- Music: a song per profession while you level it.
	music = {
		{ key = "name", width = 260 },
		{ key = "songText", width = 300 },
		{ key = "modeText", width = 240 },
	},
}
local CELL_KEYS = { "cost", "sellsFor", "profit", "learnCost", "breakEven", "required", "whereText",
	"vendorValue", "ahValue", "deValue", "bestValue", "equippedText", "gain", "songText", "modeText" }

local QUALITY_COLORS = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }
local BEST_TEXT = { vendor = "Vendor", auction = "Auction", disenchant = "Disenchant" }

local STATUS_TEXT = {
	known = "Known",
	trainable = "Trainer",
	vendor = "Vendor recipe",
	drop = "Drop recipe",
	quest = "Quest recipe",
	unlearned = "Source not known yet",
}

-- Texture arrows: the game font has no triangle glyphs.
local ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t"
local ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:3|t"

-- Recipe name colours as in the game's profession window.
local SKILL_COLORS = {
	red = "|cffff4040", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080",
}

local frame, rows, tabs, viewButtons = nil, {}, {}, {}
local state = { professionID = nil, offset = 0, data = {}, query = "", hidden = 0 }

local function Settings()
	return ns.db.settings
end

local function Money(copper)
	return ns.FormatMoney(copper)
end

local function Muted(text)
	return C.muted .. text .. "|r"
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

local function StatusLine(r)
	local text = STATUS_TEXT[r.status] or r.status
	if r.status == "known" then
		return Muted(text)
	end
	local parts = { text }
	if r.required then
		parts[#parts + 1] = ("skill %d"):format(r.required)
	end
	local color = C.good
	if r.tooLow then
		color = C.warn
	elseif r.status == "unlearned" then
		color = C.muted
	end
	return color .. table.concat(parts, " · ") .. "|r"
end

-- Data ---------------------------------------------------------------------

local function View()
	local v = Settings().view
	return (v == "learn" or v == "bags" or v == "upgrades" or v == "music") and v or "profit"
end

-- Views that list items across all professions (no profession tabs).
local function ItemView()
	return View() == "bags" or View() == "upgrades" or View() == "music"
end

-- Rows after the search box and the view's filters; also returns how many the filters hid.
local function FilteredRows()
	local s = Settings()
	if View() == "music" then
		local out = {}
		local music = ns.db.music
		local partyChoice = music.professions[ns.Music.PARTY] or {}
		out[1] = { name = ns.Music.PARTY, icon = ns.Music.PARTY_ICON, party = true, song = partyChoice.song,
			video = partyChoice.video, mode = partyChoice.mode or "resume",
			position = partyChoice.song and music.position[partyChoice.song] }
		for _, prof in ipairs(ns.Music.Professions()) do
			local choice = music.professions[prof.name] or {}
			out[#out + 1] = { name = prof.name, icon = prof.icon, skill = prof.skill, maxSkill = prof.maxSkill,
				song = choice.song, mode = choice.mode or "resume", position = choice.song and music.position[choice.song] }
		end
		return out, 0
	end
	if View() == "upgrades" then
		local query = state.query:lower()
		local out, hidden = {}, 0
		for _, r in ipairs(ns.UpgradeRows()) do
			if query == "" or r.name:lower():find(query, 1, true) then
				if r.dismissed and not s.showDismissed then
					hidden = hidden + 1
				else
					out[#out + 1] = r
				end
			end
		end
		return out, hidden
	end
	if View() == "bags" then
		local query = state.query:lower()
		local out = {}
		local hidden = 0
		for _, r in ipairs(ns.BagRows()) do
			if query == "" or r.name:lower():find(query, 1, true) then
				if r.kept and not s.showKept then
					hidden = hidden + 1
				else
					out[#out + 1] = r
				end
			end
		end
		return out, hidden
	end
	local learnView = View() == "learn"
	local all = state.professionID and ns.BuildRows(state.professionID, learnView or s.includeUnlearned) or {}
	local query = state.query:lower()
	local out, hidden = {}, 0
	for _, r in ipairs(all) do
		local keep = query == "" or (r.name or ""):lower():find(query, 1, true)
		if keep and learnView then
			if r.status == "known" then
				keep = false
			elseif s.learnFitsSkill and (not r.required or r.tooLow) then
				-- fits your skill only when the requirement is known and met
				keep, hidden = false, hidden + 1
			end
		elseif keep and s.hideUnpriced and not r.profit then
			keep, hidden = false, hidden + 1
		end
		if keep then
			if learnView then
				r.where = ns.RecipeWhere(r.recipeID)
				r.whereText = r.where[1] and r.where[1].text or nil
			end
			out[#out + 1] = r
		end
	end
	return out, hidden
end

local function ProfessionIDs()
	local ids = {}
	for id, prof in pairs(ns.charDB.professions) do
		if next(prof.recipes) and not ns.IsGathering(id) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		return (ns.charDB.professions[a].name or "") < (ns.charDB.professions[b].name or "")
	end)
	return ids
end

-- Rendering -----------------------------------------------------------------

local function RenderTabs(ids)
	for i, id in ipairs(ids) do
		local tab = tabs[i]
		if not tab then
			tab = Style.Button(frame, 160, 26)
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
		if withSource == 0 then
			text = text .. "\n" .. Muted("Sources come with the recipe data (issue #11). Recipes your trainer teaches appear after you open the trainer once.")
		end
		if state.hidden > 0 then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
	elseif not ns.HasAuctionator() then
		text = C.warn .. "Auctionator not found.|r " .. Muted("Only vendor prices are used. Install Auctionator and run a Full Scan at the auction house.")
	else
		local profitable, priced, unpriced = 0, 0, 0
		for _, r in ipairs(state.data) do
			if r.profit then
				priced = priced + 1
				if r.profit > 0 then
					profitable = profitable + 1
				end
			elseif not r.noItemOutput then
				unpriced = unpriced + 1
			end
		end
		text = ("%s%d|r of %d priced recipes make a profit"):format(C.good, profitable, priced)
		if unpriced > 0 then
			text = text .. Muted(("  ·  %d without a price (reagent or item not on the AH)"):format(unpriced))
		end
		if state.hidden > 0 then
			text = text .. Muted(("  ·  %d hidden by filters"):format(state.hidden))
		end
	end
	frame.summary:SetText(text)
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
	cells.ahValue:SetText(r.ahValue and Money(r.ahValue) or Muted(r.bound and "bound" or "-"))
	if r.deValue then
		cells.deValue:SetText(Money(r.deValue))
	else
		cells.deValue:SetText(Muted(r.canDisenchant and "?" or "-"))
	end
	if r.questItem then
		cells.bestValue:SetText(C.info .. "Quest item|r")
	elseif r.kept then
		cells.bestValue:SetText(C.info .. "Kept|r" .. Muted("  right-click to sell"))
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
			or "key: Key Bindings > AddOns > CraftWise, or /cw party"))
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

local function RenderRow(row, r, index)
	row.data = r
	row.stripe:SetShown(index % 2 == 0)
	if View() == "music" then
		return RenderMusicRow(row, r)
	end
	if View() == "bags" then
		return RenderBagRow(row, r)
	elseif View() == "upgrades" then
		return RenderUpgradeRow(row, r)
	end
	row.icon:SetDesaturated(false)
	row.icon:SetTexture(r.icon or 134400)
	local color = SKILL_COLORS[r.skillColor] or "|cffffffff"
	row.name:SetText(color .. (r.name or ("Recipe " .. r.recipeID)) .. "|r")
	row.status:SetText(StatusLine(r))

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
		cells.sellsFor:SetText(r.sellsFor and Money(r.sellsFor) or Muted("-"))
	end

	if r.profit then
		cells.profit:SetText((r.profit >= 0 and C.good .. "+" or C.bad) .. Money(r.profit) .. "|r")
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
		cells.whereText:SetText(r.whereText .. more)
	else
		cells.whereText:SetText(Muted("Not known yet"))
	end
	row:Show()
end

local function UpdateScrollBar()
	local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
	local bar = frame.scrollBar
	bar.updating = true
	bar:SetMinMaxValues(0, maxOffset)
	bar:SetValue(state.offset)
	bar.updating = false
	bar:SetShown(maxOffset > 0)
end

-- Positions headers and cells for a view. In the profit view the learn columns only show with
-- unlearned recipes; without them the recipe column takes their space.
local function Layout(view, showLearn)
	local cols = VIEWS[view]
	local extra = 0
	for _, col in ipairs(cols) do
		if col.learn and not showLearn then
			extra = extra + col.width + 8
		end
	end
	local visibleKeys = {}
	local hx, cx = PAD + 42, 42
	for i, col in ipairs(cols) do
		local visible = showLearn or not col.learn
		local width = i == 1 and (col.width + extra) or col.width
		local header = frame.headers[col.key]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hx, HEADER_Y)
		header:SetWidth(width)
		header:SetShown(visible)
		visibleKeys[col.key] = visible
		for _, row in ipairs(rows) do
			if i == 1 then
				row.name:SetWidth(width)
				row.status:SetWidth(width)
			else
				local cell = row.cells[col.key]
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", cx, 0)
				cell:SetWidth(width)
			end
		end
		if visible then
			hx, cx = hx + width + 8, cx + width + 8
		end
	end
	-- Hide everything the view doesn't use.
	for key, header in pairs(frame.headers) do
		if not visibleKeys[key] then
			header:Hide()
		end
	end
	for _, row in ipairs(rows) do
		for _, key in ipairs(CELL_KEYS) do
			row.cells[key]:SetShown(visibleKeys[key] or false)
		end
	end
	state.layout = view .. tostring(showLearn)
end

local function SortSettings()
	local s = Settings()
	if View() == "learn" then
		return s.learnSortKey or "required", s.learnSortDesc
	elseif View() == "bags" then
		return s.bagSortKey or "bestValue", s.bagSortDesc ~= false
	elseif View() == "upgrades" then
		return s.upgradeSortKey or "gain", s.upgradeSortDesc ~= false
	elseif View() == "music" then
		return "name", false
	end
	return s.sortKey, s.sortDesc
end

local function UpdateControls()
	local learnView = View() == "learn"
	for key, button in pairs(viewButtons) do
		button:SetSelected(key == View())
	end
	local bagsView = View() == "bags"
	frame.fits:SetShown(learnView)
	local upgradesView = View() == "upgrades"
	frame.showKept:SetShown(bagsView)
	frame.sortBtn:SetShown(bagsView)
	frame.showDismissed:SetShown(upgradesView)
	frame.musicOn:SetShown(View() == "music")
	frame.partyBtn:SetShown(View() == "music")
	frame.partyBtn:SetLabel(ns.Music.PartyActive() and "Stop party" or "Party!")
	frame.partyBtn:SetSelected(ns.Music.PartyActive())
	frame.priced:SetShown(not learnView and not ItemView())
	frame.unlearned:SetShown(not learnView and not ItemView())
	for _, tab in ipairs(tabs) do
		if ItemView() then
			tab:Hide()
		end
	end
end

local function Refresh()
	if not (frame and frame:IsShown() and ns.charDB) then
		return
	end
	local ids = ProfessionIDs()
	if not state.professionID or not ns.charDB.professions[state.professionID] then
		state.professionID = ids[1]
	end
	if not ItemView() then
		RenderTabs(ids)
	end
	UpdateControls()
	local showLearn = View() == "learn" or Settings().includeUnlearned
	if state.layout ~= View() .. tostring(showLearn) then
		Layout(View(), showLearn)
	end

	state.data, state.hidden = FilteredRows()
	local sortKey, sortDesc = SortSettings()
	local compare = ns.Profit.Comparator(sortKey, sortDesc)
	if ItemView() and View() ~= "music" then
		local inner = compare
		local flag = View() == "bags" and "kept" or "dismissed"
		compare = function(a, b)
			if a[flag] ~= b[flag] then
				return b[flag] -- kept / dismissed items last
			end
			return inner(a, b)
		end
	end
	table.sort(state.data, compare)
	state.offset = math.max(0, math.min(state.offset, #state.data - VISIBLE_ROWS))

	RenderSummary(ids)
	for key, header in pairs(frame.headers) do
		local arrow = sortKey == key and (sortDesc and ARROW_DOWN or ARROW_UP) or ""
		local label = header.label
		if key == "name" and View() == "music" then
			label = "PROFESSION"
		elseif key == "name" and ItemView() then
			label = "ITEM"
		end
		header.text:SetText(label .. arrow)
	end

	for i = 1, VISIBLE_ROWS do
		local r = state.data[i + state.offset]
		if r then
			RenderRow(rows[i], r, i + state.offset)
		else
			rows[i].data = nil
			rows[i]:Hide()
		end
	end
	local unit = View() == "music" and "professions" or ItemView() and "items" or "recipes"
	frame.count:SetText(Muted(("%d %s"):format(#state.data, unit)))
	local empty = "No recipes match. Clear the search or tick \"Show unlearned\"."
	if View() == "learn" then
		empty = "No recipes match. Clear the search or untick \"Fits my skill\"."
	elseif View() == "upgrades" then
		empty = "No upgrades from the recipes you know. Open your professions once so CraftWise knows them."
	end
	frame.empty:SetText(empty)
	frame.empty:SetShown((#ids > 0 or ItemView()) and #state.data == 0)
	UpdateScrollBar()
end
ns.RefreshProfitFrame = Refresh

-- Tooltip ------------------------------------------------------------------

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
		GameTooltip:AddLine("Kept - not counted. Right-click to sell it again.", 0.54, 0.7, 1)
	elseif r.best then
		local line = BEST_TEXT[r.best]:upper()
		if r.margin and r.margin > 0 then
			line = line .. (" pays %s more"):format(Money(r.margin))
		end
		GameTooltip:AddLine(line, 0.3, 0.82, 0.55)
	end
	if r.reagent then
		GameTooltip:AddLine("Used by recipes you know - maybe keep it.", 0.54, 0.7, 1)
	end
	if r.ammo then
		GameTooltip:AddLine("Ammo - keep what you shoot.", 0.54, 0.7, 1)
	end
	if r.ahAge and r.ahAge > 1 then
		GameTooltip:AddLine(("AH price is %d days old."):format(r.ahAge), 1, 0.6, 0.3)
	end
	if not r.kept then
		GameTooltip:AddLine("Right-click: keep this item (leave it out of the advice)", 0.55, 0.55, 0.6)
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

local function ShowTooltip(row)
	local r = row.data
	if not r then
		return
	end
	if View() == "bags" then
		return ShowBagTooltip(row, r)
	elseif View() == "upgrades" then
		return ShowUpgradeTooltip(row, r)
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

-- Song picker (Music view) -------------------------------------------------

local picker

local function BuildPicker()
	picker = CreateFrame("Frame", "CraftWiseSongPicker", frame, "BackdropTemplate")
	picker:SetFrameStrata("DIALOG")
	picker:SetWidth(300)
	picker:EnableMouse(true)
	Style.Panel(picker)
	table.insert(UISpecialFrames, "CraftWiseSongPicker")
	picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	picker.title:SetPoint("TOPLEFT", 12, -10)
	local close = Style.CloseButton(picker, function()
		picker:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)
	picker.songs = {}
	picker.videos = {}
	picker.videoLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.videoLabel:SetText(Muted("Video (small window while you cast)"))
	picker.modeLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.modeLabel:SetText(Muted("Next cast"))
	picker.resume = Style.Button(picker, 134, 22, "Resume where it stopped")
	picker.restart = Style.Button(picker, 134, 22, "From the beginning")
	picker.volLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.volDown = Style.Button(picker, 26, 22, "-")
	picker.volUp = Style.Button(picker, 26, 22, "+")
	picker.volText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.empty:SetPoint("TOPLEFT", 12, -36)
	picker.empty:SetPoint("RIGHT", -12, 0)
	picker.empty:SetJustifyH("LEFT")
	picker.empty:SetText(Muted("No songs yet. Add them with tools/music_split.py and restart the game."))
	-- Add a song file by name.
	picker.addLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.addLabel:SetJustifyH("LEFT")
	picker.addLabel:SetWidth(276)
	picker.addLabel:SetText(Muted("Add a song: put an .mp3 or .ogg in") .. "\n|cffffffff" .. ns.Music.FOLDER_TEXT
		.. "|r\n" .. Muted("restart the game, then type its file name here."))
	picker.addBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
	picker.addBox:SetSize(200, 22)
	picker.addBox:SetAutoFocus(false)
	picker.addBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	picker.addBtn = Style.Button(picker, 60, 22, "Add")
	picker.addMsg = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.addMsg:SetJustifyH("LEFT")
	picker.addMsg:SetWidth(276)
	local function add()
		local name, err = ns.Music.AddFile(picker.addBox:GetText())
		if name then
			picker.addBox:SetText("")
			picker.addMsg:SetText(C.good .. "Added " .. name .. "|r")
			ns.Music.SetSong(picker.profession, name)
		else
			picker.addMsg:SetText(C.warn .. err .. "|r")
		end
		picker.addBox:ClearFocus()
		picker.render(picker.profession)
	end
	picker.addBtn:SetScript("OnClick", add)
	picker.addBox:SetScript("OnEnterPressed", add)
	picker:SetScript("OnHide", function()
		if ns.Music.PreviewSong() then
			ns.Music.Stop()
		end
		if ns.Video.PreviewName() then
			ns.Video.Stop()
		end
	end)
end

local function RenderPicker(prof)
	local choice = ns.db.music.professions[prof] or {}
	local names = ns.Music.SongNames()
	local options = { false }
	for _, n in ipairs(names) do
		options[#options + 1] = n
	end
	picker.title:SetText(prof .. "  " .. Muted("song"))
	local y = -34
	for i, name in ipairs(options) do
		local line = picker.songs[i]
		if not line then
			line = {}
			line.pick = Style.Button(picker, 190, 22)
			line.play = Style.Button(picker, 44, 22)
			line.remove = Style.Button(picker, 22, 22, "x")
			picker.songs[i] = line
		end
		line.pick:ClearAllPoints()
		line.pick:SetPoint("TOPLEFT", 12, y)
		line.play:ClearAllPoints()
		line.play:SetPoint("LEFT", line.pick, "RIGHT", 6, 0)
		local label = name and name:gsub("_", " ") or "No music"
		if name and ns.Music.IsWhole(name) then
			label = label .. Muted("  from start")
		end
		line.pick:SetLabel(label)
		line.pick:SetSelected((choice.song or false) == name)
		line.pick:SetScript("OnClick", function()
			ns.Music.SetSong(prof, name or nil)
			RenderPicker(prof)
		end)
		line.pick:Show()
		if name then
			line.play:SetLabel(ns.Music.PreviewSong() == name and "Stop" or "Play")
			line.play:SetScript("OnClick", function()
				if ns.Music.PreviewSong() == name then
					ns.Music.Stop()
				else
					ns.Music.Preview(name, ns.Music.Volume(prof))
				end
				RenderPicker(prof)
			end)
			line.play:Show()
			line.remove:ClearAllPoints()
			line.remove:SetPoint("LEFT", line.play, "RIGHT", 6, 0)
			line.remove:SetScript("OnClick", function()
				ns.Music.RemoveFile(name)
				RenderPicker(prof)
			end)
			line.remove:SetShown(ns.Music.IsWhole(name))
		else
			line.play:Hide()
			line.remove:Hide()
		end
		y = y - 26
	end
	for i = #options + 1, #picker.songs do
		picker.songs[i].pick:Hide()
		picker.songs[i].play:Hide()
		picker.songs[i].remove:Hide()
	end
	picker.empty:SetShown(#names == 0)
	if #names == 0 then
		y = y - 30
	end
	picker.modeLabel:ClearAllPoints()
	picker.modeLabel:SetPoint("TOPLEFT", 12, y - 8)
	picker.resume:ClearAllPoints()
	picker.resume:SetPoint("TOPLEFT", 12, y - 24)
	picker.restart:ClearAllPoints()
	picker.restart:SetPoint("LEFT", picker.resume, "RIGHT", 6, 0)
	local whole = choice.song and ns.Music.IsWhole(choice.song)
	local restart = choice.mode == "restart" or whole
	picker.resume:SetLabel(whole and Muted("Resume: split the song") or "Resume where it stopped")
	picker.resume:SetSelected(not restart)
	picker.restart:SetSelected(restart)
	picker.resume:SetScript("OnClick", function()
		ns.Music.SetMode(prof, "resume")
		RenderPicker(prof)
	end)
	picker.restart:SetScript("OnClick", function()
		ns.Music.SetMode(prof, "restart")
		RenderPicker(prof)
	end)
	-- Volume for this profession (e.g. low while fishing so the bobber splash stays audible).
	picker.volLabel:ClearAllPoints()
	picker.volLabel:SetPoint("TOPLEFT", 12, y - 58)
	picker.volLabel:SetText(Muted("Volume"))
	picker.volDown:ClearAllPoints()
	picker.volDown:SetPoint("TOPLEFT", 80, y - 52)
	picker.volText:ClearAllPoints()
	picker.volText:SetPoint("LEFT", picker.volDown, "RIGHT", 8, 0)
	picker.volText:SetWidth(44)
	picker.volText:SetText(("%d%%"):format(ns.Music.Volume(prof) * 100 + 0.5))
	picker.volUp:ClearAllPoints()
	picker.volUp:SetPoint("LEFT", picker.volText, "RIGHT", 8, 0)
	picker.volDown:SetScript("OnClick", function()
		ns.Music.SetVolume(prof, ns.Music.Volume(prof) - 0.1)
		RenderPicker(prof)
	end)
	picker.volUp:SetScript("OnClick", function()
		ns.Music.SetVolume(prof, ns.Music.Volume(prof) + 0.1)
		RenderPicker(prof)
	end)
	y = y - 30

	-- Video choice: "No video" and every converted video, with a preview.
	y = y - 58
	picker.videoLabel:ClearAllPoints()
	picker.videoLabel:SetPoint("TOPLEFT", 12, y)
	y = y - 16
	local videoOptions = { false }
	for _, n in ipairs(ns.Video.Names()) do
		videoOptions[#videoOptions + 1] = n
	end
	for i, name in ipairs(videoOptions) do
		local line = picker.videos[i]
		if not line then
			line = { pick = Style.Button(picker, 190, 22), play = Style.Button(picker, 44, 22) }
			picker.videos[i] = line
		end
		line.pick:ClearAllPoints()
		line.pick:SetPoint("TOPLEFT", 12, y)
		line.play:ClearAllPoints()
		line.play:SetPoint("LEFT", line.pick, "RIGHT", 6, 0)
		line.pick:SetLabel(name and name:gsub("_", " ") or "No video")
		line.pick:SetSelected((choice.video or false) == name)
		line.pick:SetScript("OnClick", function()
			ns.Video.SetVideo(prof, name or nil)
			RenderPicker(prof)
		end)
		line.pick:Show()
		if name then
			line.play:SetLabel(ns.Video.PreviewName() == name and "Stop" or "Play")
			line.play:SetScript("OnClick", function()
				if ns.Video.PreviewName() == name then
					ns.Video.Stop()
				else
					ns.Video.Preview(name)
				end
				RenderPicker(prof)
			end)
			line.play:Show()
		else
			line.play:Hide()
		end
		y = y - 26
	end
	for i = #videoOptions + 1, #picker.videos do
		picker.videos[i].pick:Hide()
		picker.videos[i].play:Hide()
	end
	y = y + 58 - 8
	picker.addLabel:ClearAllPoints()
	picker.addLabel:SetPoint("TOPLEFT", 12, y - 58)
	picker.addBox:ClearAllPoints()
	picker.addBox:SetPoint("TOPLEFT", 18, y - 106)
	picker.addBtn:ClearAllPoints()
	picker.addBtn:SetPoint("LEFT", picker.addBox, "RIGHT", 8, 0)
	picker.addMsg:ClearAllPoints()
	picker.addMsg:SetPoint("TOPLEFT", 12, y - 134)
	picker:SetHeight(-(y - 134) + 26)
	picker.profession = prof
	picker.render = RenderPicker
end

local function ShowPicker(row, prof)
	if not picker then
		BuildPicker()
	end
	if picker:IsShown() and picker.profession == prof then
		picker:Hide()
		return
	end
	RenderPicker(prof)
	picker:ClearAllPoints()
	picker:SetPoint("TOPLEFT", row.cells.songText, "TOPLEFT", -8, -4)
	picker:Show()
end
ns.ShowSongPicker = ShowPicker

-- Construction -------------------------------------------------------------

local function BuildHeader()
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -16)
	title:SetText("|cffffffffCraftWise|r")
	local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subtitle:SetPoint("LEFT", title, "RIGHT", 10, -1)
	subtitle:SetText(Muted("Profit, learning, gear upgrades and loot"))

	-- View switch: Profit (what to craft) | Learn (what to learn and where) | Upgrades | Bags.
	local musicBtn = Style.Button(frame, 70, 24, "Music")
	musicBtn:SetPoint("TOPRIGHT", -44, -14)
	local bagsBtn = Style.Button(frame, 70, 24, "Bags")
	bagsBtn:SetPoint("RIGHT", musicBtn, "LEFT", -6, 0)
	local upgradesBtn = Style.Button(frame, 86, 24, "Upgrades")
	upgradesBtn:SetPoint("RIGHT", bagsBtn, "LEFT", -6, 0)
	local learnBtn = Style.Button(frame, 70, 24, "Learn")
	learnBtn:SetPoint("RIGHT", upgradesBtn, "LEFT", -6, 0)
	local profitBtn = Style.Button(frame, 70, 24, "Profit")
	profitBtn:SetPoint("RIGHT", learnBtn, "LEFT", -6, 0)
	viewButtons.profit, viewButtons.learn, viewButtons.bags = profitBtn, learnBtn, bagsBtn
	viewButtons.upgrades, viewButtons.music = upgradesBtn, musicBtn
	for key, button in pairs(viewButtons) do
		button:SetScript("OnClick", function()
			Settings().view, state.offset = key, 0
			Refresh()
		end)
	end

	local close = Style.CloseButton(frame, function()
		frame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -10, -12)

	-- Filter row: search on the left, toggles on the right.
	local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetSize(200, 22)
	search:SetPoint("TOPLEFT", PAD + 6, -98)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self)
		state.query, state.offset = self:GetText() or "", 0
		Refresh()
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", 2, 0)
	hint:SetText("Search")
	frame.searchHint = hint
	search:SetScript("OnEditFocusGained", function()
		hint:Hide()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		hint:SetShown((self:GetText() or "") == "")
	end)

	local unlearned = Style.Check(frame, "Show unlearned", Settings().includeUnlearned, function(v)
		Settings().includeUnlearned, state.offset = v, 0
		Refresh()
	end)
	unlearned:SetPoint("TOPRIGHT", -PAD - 110, -100)
	local priced = Style.Check(frame, "Hide unpriced", Settings().hideUnpriced, function(v)
		Settings().hideUnpriced, state.offset = v, 0
		Refresh()
	end)
	priced:SetPoint("RIGHT", unlearned, "LEFT", -24, 0)
	local fits = Style.Check(frame, "Fits my skill", Settings().learnFitsSkill, function(v)
		Settings().learnFitsSkill, state.offset = v, 0
		Refresh()
	end)
	fits:SetPoint("TOPRIGHT", -PAD - 110, -100)
	local showKept = Style.Check(frame, "Show kept items", Settings().showKept, function(v)
		Settings().showKept, state.offset = v, 0
		Refresh()
	end)
	showKept:SetPoint("TOPRIGHT", -PAD - 110, -100)
	local showDismissed = Style.Check(frame, "Show dismissed", Settings().showDismissed, function(v)
		Settings().showDismissed, state.offset = v, 0
		Refresh()
	end)
	showDismissed:SetPoint("TOPRIGHT", -PAD - 110, -100)
	frame.unlearned, frame.priced, frame.fits, frame.showKept = unlearned, priced, fits, showKept
	local sortBtn = Style.Button(frame, 96, 22, "Sort bags")
	sortBtn:SetPoint("RIGHT", showKept, "LEFT", -24, 0)
	sortBtn:SetScript("OnClick", function()
		ns.BagSort.Start()
	end)
	sortBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Sort bags")
		GameTooltip:AddLine("Kept items and reagents first, then free slots, then items to sell (best value first) in the last bag.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	sortBtn:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self:SetSelected(false)
	end)
	frame.sortBtn = sortBtn
	frame.showDismissed = showDismissed
	local musicOn = Style.Check(frame, "Music on", ns.db.music.enabled, function(v)
		ns.db.music.enabled = v
		if not v then
			ns.Music.Stop()
		end
		Refresh()
	end)
	musicOn:SetPoint("TOPRIGHT", -PAD - 110, -100)
	frame.musicOn = musicOn
	local partyBtn = Style.Button(frame, 96, 22, "Party!")
	partyBtn:SetPoint("RIGHT", musicOn, "LEFT", -24, 0)
	partyBtn:SetScript("OnClick", function()
		ns.Music.ToggleParty()
		Refresh()
	end)
	frame.partyBtn = partyBtn

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.summary:SetPoint("TOPLEFT", PAD, -130)
	frame.summary:SetPoint("RIGHT", -PAD, 0)
	frame.summary:SetJustifyH("LEFT")
end

local function BuildColumns()
	frame.headers = {}
	for key, def in pairs(COLUMN_DEFS) do
		local header = CreateFrame("Button", nil, frame)
		header:SetSize(100, 18)
		header.label = def.label
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header.text:SetAllPoints()
		header.text:SetJustifyH(def.align)
		header.text:SetTextColor(0.55, 0.58, 0.65)
		header:SetScript("OnClick", function()
			local s = Settings()
			local ascending = key == "name" or key == "whereText" or key == "required"
			if View() == "music" then
				return
			elseif View() == "upgrades" then
				if (s.upgradeSortKey or "gain") == key then
					s.upgradeSortDesc = not (s.upgradeSortDesc ~= false)
				else
					s.upgradeSortKey, s.upgradeSortDesc = key, not (key == "name" or key == "equippedText" or key == "cost")
				end
			elseif View() == "bags" then
				if (s.bagSortKey or "bestValue") == key then
					s.bagSortDesc = not (s.bagSortDesc ~= false)
				else
					s.bagSortKey, s.bagSortDesc = key, key ~= "name"
				end
			elseif View() == "learn" then
				if s.learnSortKey == key then
					s.learnSortDesc = not s.learnSortDesc
				else
					s.learnSortKey, s.learnSortDesc = key, not ascending
				end
			elseif s.sortKey == key then
				s.sortDesc = not s.sortDesc
			else
				s.sortKey, s.sortDesc = key, not ascending
			end
			Refresh()
		end)
		frame.headers[key] = header
	end
	local line = frame:CreateTexture(nil, "ARTWORK")
	Style.Fill(line, C.border)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", PAD, HEADER_Y - 20)
	line:SetPoint("TOPRIGHT", -PAD, HEADER_Y - 20)
end

local function BuildRows()
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", PAD, LIST_TOP - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -PAD - 14, 0)

		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		Style.Fill(row.stripe, C.stripe)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		Style.Fill(hl, C.hover)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 6, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 42, -4)
		row.name:SetWidth(VIEWS.profit[1].width)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
		row.status:SetWidth(VIEWS.profit[1].width)
		row.status:SetJustifyH("LEFT")
		row.status:SetWordWrap(false)

		row.cells = {}
		for _, key in ipairs(CELL_KEYS) do
			local font = key == "whereText" and "GameFontHighlightSmall" or "GameFontHighlight"
			local fs = row:CreateFontString(nil, "OVERLAY", font)
			fs:SetSize(100, ROW_HEIGHT)
			fs:SetJustifyH(COLUMN_DEFS[key].align)
			fs:SetWordWrap(false)
			row.cells[key] = fs
		end

		row:SetScript("OnEnter", ShowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, mouse)
			local r = self.data
			if not r then
				return
			end
			if View() == "bags" then
				if mouse == "RightButton" and not r.questItem then
					ns.ToggleKeep(r.itemID)
					ShowTooltip(self)
				end
			elseif View() == "music" then
				ShowPicker(self, r.name)
			elseif View() == "upgrades" and mouse == "RightButton" then
				ns.ToggleDismissed(r.itemID)
				ShowTooltip(self)
			elseif C_TradeSkillUI.OpenRecipe then
				pcall(C_TradeSkillUI.OpenRecipe, r.recipeID)
			end
		end)
		rows[i] = row
	end
end

local function BuildScrollBar()
	local bar = CreateFrame("Slider", nil, frame)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	bar:SetPoint("TOPRIGHT", -PAD + 2, LIST_TOP)
	bar:SetPoint("BOTTOMRIGHT", -PAD + 2, 40)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	Style.Fill(track, { 1, 1, 1, 0.05 })
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	Style.Fill(thumb, C.accent)
	thumb:SetSize(6, 40)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetObeyStepOnDrag(true)
	bar:SetScript("OnValueChanged", function(self, value)
		if self.updating then
			return
		end
		state.offset = math.floor(value + 0.5)
		Refresh()
	end)
	frame.scrollBar = bar
end

local function Build()
	frame = CreateFrame("Frame", "CraftWiseFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Style.Panel(frame)
	table.insert(UISpecialFrames, "CraftWiseFrame")

	BuildHeader()
	BuildColumns()
	BuildRows()
	BuildScrollBar()

	frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.count:SetPoint("BOTTOMLEFT", PAD, 14)
	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("BOTTOMRIGHT", -PAD, 14)
	help:SetText(Muted("Hover a row for details  ·  click a header to sort  ·  scroll with the mouse wheel"))

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", 0, -40)
	frame.empty:SetText("No recipes match. Clear the search or tick \"Show unlearned\".")

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local maxOffset = math.max(0, #state.data - VISIBLE_ROWS)
		local step = IsShiftKeyDown() and VISIBLE_ROWS or 3
		state.offset = math.max(0, math.min(maxOffset, state.offset - delta * step))
		Refresh()
	end)
	frame:SetScript("OnShow", Refresh)
end

function ns.ToggleProfitFrame()
	if not ns.db then
		return
	end
	if not frame then
		Build()
		frame:Show()
		Refresh()
		return
	end
	frame:SetShown(not frame:IsShown())
end

ns.Listen("RECIPES_CHANGED", Refresh)
ns.Listen("PRICES_CHANGED", Refresh)
ns.Listen("BAGS_CHANGED", function()
	if frame and frame:IsShown() and ItemView() then
		Refresh()
	end
end)
ns.Listen("MUSIC_CHANGED", function()
	if frame and frame:IsShown() and View() == "music" then
		Refresh()
	end
end)
ns.Listen("UPGRADES_CHANGED", function()
	if frame and frame:IsShown() and View() == "upgrades" then
		Refresh()
	end
end)
ns.On("AUCTION_HOUSE_CLOSED", Refresh) -- Auctionator prices may have changed during a scan
