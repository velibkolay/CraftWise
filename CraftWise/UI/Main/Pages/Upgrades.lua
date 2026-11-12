-- Look up › Upgrades (#157; spec in #150 "Look up, Music, Settings", board "Look up · Upgrades"): gear you
-- can craft or buy that beats what you wear. Groups You can craft (known recipes; learnable ones with
-- "learn: trainer 45s") and From the auction house (the latest Search AH, Upgrades #50). Columns: Item
-- (quality colour, how under it), Slot, Replaces, Gain (main stats difference, Upgrades.MainStatsText),
-- Cost. The AH group ends with Search AH for these (UpgradeSearch), disabled with "open the auction house
-- to search" while it is closed. Dismiss from the item menu (ns.ToggleDismissed); Settings › Bags and loot
-- › Show dismissed upgrades lists them again.
-- Row data (Up.Model) is built apart from the drawing (InitRow), so the docked layout (#161) can draw it.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local Up = {}
M.Upgrades = Up

Up.ROW_HEIGHT = 40

local GROUPS = { "craft", "ah" }
local ORDER = { craft = 1, ah = 2 }

----------------------------------------------------------------------------------------------------
-- Model
----------------------------------------------------------------------------------------------------

-- "+6 AGI +4 STA · +31 armor": the main stats of the item minus the equipped one's, then armour.
function Up.GainText(r)
	if r.emptySlot then
		local stats = r.mainStats and r.mainStats ~= "" and (r.mainStats .. " · ") or ""
		return stats .. L["fills the slot"]
	end
	local diff = {}
	for k, v in pairs(r.stats or {}) do
		diff[k] = v
	end
	for k, v in pairs(r.current and r.current.stats or {}) do
		diff[k] = (diff[k] or 0) - v
	end
	local parts = {}
	local main = (r.stats or (r.current and r.current.stats)) and ns.Upgrades.MainStatsText(diff) or nil
	if main and main ~= "" then
		parts[#parts + 1] = main
	end
	if (r.armorGain or 0) ~= 0 then
		parts[#parts + 1] = ("%s%d %s"):format(r.armorGain > 0 and "+" or "", r.armorGain, L["armor"])
	end
	if #parts == 0 and (r.ilvlGain or 0) ~= 0 then
		parts[#parts + 1] = ("%s%d %s"):format(r.ilvlGain > 0 and "+" or "", r.ilvlGain, L["item level"])
	end
	if #parts == 0 then
		return main == nil and L["stats unknown"] or L["same stats"]
	end
	return table.concat(parts, " · ")
end

-- "learn: trainer 45s", "known · reagents in bags", "4 listed", "not seen at Horde AH".
local function How(r)
	if r.section == "ah" then
		if r.notAtHouse then
			return (L["not seen at %s"]):format(r.houseLabel or L["the profit house"]), "danger"
		end
		local age = r.priceAge and (" · " .. M.AgeText(r.priceAge) .. " " .. L["ago"]) or ""
		return (L["%d listed"]):format(r.qty or 0) .. age, "text3"
	end
	if r.learnFirst then
		local cost = r.learnCost and (" " .. ns.FormatMoney(r.learnCost, true)) or ""
		return L["learn"] .. ": " .. (r.learnKind and L[r.learnKind] or L["source unknown"]) .. cost, "text3"
	end
	if r.haveReagents then
		return L["known"] .. " · " .. L["reagents in bags"], "text3"
	end
	return L["known"], "text3"
end

local function CostText(r)
	if r.cost and r.costComplete then
		return ns.FormatCoins(r.cost)
	elseif r.cost and r.cost > 0 then
		return "~" .. ns.FormatCoins(r.cost) -- a reagent or the learn cost has no price
	end
	return M.NoPriceText()
end

-- One list row from an Upgrades.Compare row.
function Up.Row(r)
	local how, howColor = How(r)
	return {
		key = r.section .. ":" .. tostring(r.itemKey or r.itemID), group = r.section, itemID = r.itemID,
		name = r.name, quality = r.quality, icon = r.icon, how = how, howColor = howColor,
		slot = r.slotLabel, replaces = r.emptySlot and L["nothing"] or (r.equippedText or "?"),
		gain = r.gain, gainText = Up.GainText(r), cost = r.costComplete and r.cost or nil, costText = CostText(r),
		dismissed = r.dismissed or false, source = r,
	}
end

-- Professions behind the craft group: "Leatherworking 191".
local function ProfessionNote()
	local parts = {}
	for _, id in ipairs(M.ProfessionIDs()) do
		local p = ns.charDB.professions[id]
		parts[#parts + 1] = p.skill and ("%s %d"):format(p.name, p.skill) or p.name
	end
	return table.concat(parts, " · ")
end

-- The AH group's note and search state.
function Up.SearchState()
	local S = ns.UpgradeSearch
	local st = { open = S.CanSearch(), running = S.Running() }
	if st.running then
		local index, total, label = S.Progress()
		st.progress = (L["Searching %d of %d"]):format(index or 0, total or 0) .. (label and (" · " .. label) or "")
	end
	local last = S.LastRun()
	if last and last.t then
		st.last = (L["searched %s ago at %s"]):format(M.AgeText(last.age or 0), last.houseLabel or "?")
			.. (last.complete and "" or (" · " .. L["stopped early"]))
		st.failed = last.failed
	end
	return st
end

-- { rows (headers, items, the search row), counts = { craft, ah, dismissed }, search }.
function Up.Model()
	local showDismissed = ns.db.settings.showDismissed and true or false
	local search = Up.SearchState()
	local lists = { craft = ns.UpgradeRows(), ah = ns.UpgradeSearch.Rows() }
	local counts = { craft = 0, ah = 0, dismissed = 0 }
	local rows = {}
	for _, group in ipairs(GROUPS) do
		local header = { key = "h:" .. group, group = group, header = true }
		if group == "craft" then
			header.title, header.note = L["You can craft"], ProfessionNote()
		else
			header.title = L["From the auction house"]
			header.note = search.last or L["no search yet"]
			header.right = not search.open and not search.running and L["open the auction house to search"] or nil
		end
		rows[#rows + 1] = header
		local n = 0
		for _, r in ipairs(lists[group]) do
			if r.dismissed then
				counts.dismissed = counts.dismissed + 1
			end
			if showDismissed or not r.dismissed then
				rows[#rows + 1] = Up.Row(r)
				n = n + 1
			end
		end
		counts[group] = n
		if n == 0 then
			local text = group == "craft"
				and L["Nothing you can craft beats what you wear. Open your profession windows so CraftWise knows your recipes."]
				or (search.last and L["No AH gear from your last search beats what you wear."]
					or L["Open the auction house and search: one search per slot, gear you can wear now."])
			rows[#rows + 1] = { key = "e:" .. group, group = group, emptyLine = text }
		end
		if group == "ah" then
			rows[#rows + 1] = { key = "search", group = group, search = true }
		end
	end
	return { rows = rows, counts = counts, search = search }
end

-- Sorts inside each group: its header first, the search row last, dismissed rows after the others.
function Up.SortRows(rows, key, desc)
	local function rank(r)
		if r.header then
			return 0
		elseif r.search then
			return 3
		elseif r.emptyLine then
			return 2
		end
		return 1
	end
	table.sort(rows, function(a, b)
		if a.group ~= b.group then
			return ORDER[a.group] < ORDER[b.group]
		end
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		if ra ~= 1 then
			return false
		end
		if a.dismissed ~= b.dismissed then
			return not a.dismissed
		end
		local va, vb = a[key], b[key]
		if va == vb or (va == nil and vb == nil) then
			return tostring(a.name or "") < tostring(b.name or "")
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		end
		if type(va) == "string" then
			va, vb = va:lower(), tostring(vb):lower()
		end
		if desc then
			return va > vb
		end
		return va < vb
	end)
end

----------------------------------------------------------------------------------------------------
-- Tips on the Gain and Cost cells
----------------------------------------------------------------------------------------------------

local function StatLabel(key)
	local label = _G[key]
	return type(label) == "string" and label or key
end

function Up.GainTip(row)
	local r = row.source
	if not r then
		return nil
	end
	local tip = { L["Gain"] }
	if r.emptySlot then
		tip[#tip + 1] = (L["Fills the empty %s slot."]):format(r.slotLabel or "?")
	else
		tip[#tip + 1] = ("%s: %s (%s %d)"):format(L["Replaces"], r.equippedText or "?", L["item level"], r.current.level or 0)
		local diff, keys = {}, {}
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
			tip[#tip + 1] = ("%s %s%d"):format(StatLabel(k), diff[k] > 0 and "+" or "", diff[k])
		end
		if (r.ilvlGain or 0) ~= 0 then
			tip[#tip + 1] = ("%s %s%d"):format(L["Item level"], r.ilvlGain > 0 and "+" or "", r.ilvlGain)
		end
		if not r.stats then
			tip[#tip + 1] = L["Item stats not loaded yet - hover again."]
		end
	end
	if r.suffix then
		tip[#tip + 1] = L["Random enchant: these are the base item's stats."]
	end
	return tip
end

function Up.CostTip(row)
	local r = row.source
	if not r then
		return nil
	end
	if r.section == "ah" then
		if r.notAtHouse then
			return { L["Cost"], (L["Not seen at %s in your latest search."]):format(r.houseLabel or L["the profit house"]) }
		end
		return { L["Cost"], (L["Lowest buyout at %s: %s, %d listed, %s ago."]):format(r.houseLabel or "?",
			ns.FormatMoney(r.cost, true), r.qty or 0, M.AgeText(r.priceAge or 0)) }
	end
	local tip = { L["Cost"], ("%s: %s"):format(L["Recipe"], r.recipeName or "?") }
	for _, line in ipairs(r.reagents or {}) do
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(line.itemID) or ("item " .. line.itemID)
		local have = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(line.itemID) or 0
		tip[#tip + 1] = ("%d × %s (%s %d)"):format(line.quantity or 1, name, L["have"], have)
	end
	if r.learnFirst then
		tip[#tip + 1] = ("%s: %s"):format(L["Learn"], r.learnText or "?")
	end
	if not r.costComplete then
		tip[#tip + 1] = L["~: a reagent or the recipe has no price, so the cost is at least this."]
	end
	return tip
end

----------------------------------------------------------------------------------------------------
-- Drawing: header rows, the search row and the "how" line under the name
----------------------------------------------------------------------------------------------------

local function Plain(r, field)
	if r.header or r.search or r.emptyLine then
		return ""
	end
	return r[field] or ""
end

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Item"], width = 200, sort = true, text = function(r) return Plain(r, "name") end,
		color = function(r) return r.dismissed and "text3" or Style.QualityColor(r.quality) or "text" end },
	{ key = "slot", label = L["Slot"], width = 64, sort = true, font = "Small", color = function() return "text2" end,
		text = function(r) return Plain(r, "slot") end },
	{ key = "replaces", label = L["Replaces"], sort = true, font = "Small", color = function() return "text2" end,
		text = function(r)
			local v = Plain(r, "replaces")
			return v ~= "" and (L["replaces"] .. " " .. v) or ""
		end },
	{ key = "gain", label = L["Gain"], width = 210, sort = true, font = "Figure",
		text = function(r) return Plain(r, "gainText") end,
		tip = function(r) return not (r.header or r.search or r.emptyLine) and Up.GainTip(r) or nil end },
	{ key = "cost", label = L["Cost"], width = 70, align = "RIGHT", sort = true, font = "FigureBold",
		text = function(r) return Plain(r, "costText") end,
		tip = function(r) return not (r.header or r.search or r.emptyLine) and Up.CostTip(r) or nil end },
}
Up.COLUMNS = COLUMNS

local function Extra(b)
	if b.cwUp then
		return b.cwUp
	end
	local x = {}
	x.how = Style.Text(b, "Caption", "text3")
	x.how:SetJustifyH("LEFT")
	x.how:SetWordWrap(false)
	x.title = Style.Text(b, "Section", "text")
	x.note = Style.Text(b, "Caption", "text3")
	x.right = Style.Text(b, "Caption", "text3")
	x.right:SetJustifyH("RIGHT")
	x.rule = b:CreateTexture(nil, "ARTWORK", nil, 2)
	Style.Fill(x.rule, C.text)
	x.rule:SetHeight(2)
	x.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	x.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	x.line = Style.Text(b, "Small", "text3")
	x.line:SetJustifyH("LEFT")
	x.chip = Style.Chip(b, L["Search AH for these"])
	x.chip:SetScript("OnClick", function()
		Up.Search()
	end)
	x.chip:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Search AH for these"], self.cwTip)
	end)
	x.chip:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	b.cwUp = x
	return x
end

-- The search button: a click is the hardware event the AH search needs. Returns what UpgradeSearch said.
function Up.Search()
	local ok, why = ns.UpgradeSearch.Start()
	M.Refresh()
	return ok, why
end

local function InitRow(b, data)
	local x = Extra(b)
	local special = data.header or data.search or data.emptyLine
	for i, cell in pairs(b.cells or {}) do
		cell:SetShown(not special)
	end
	for _, icon in pairs(b.icons or {}) do
		icon:SetShown(not special)
		icon:SetDesaturated(data.dismissed and true or false)
	end
	x.title:SetShown(data.header and true or false)
	x.note:SetShown(data.header and true or false)
	x.right:SetShown(data.header and data.right ~= nil or false)
	x.rule:SetShown(data.header and true or false)
	x.line:SetShown(data.emptyLine ~= nil)
	x.chip:SetShown(data.search and true or false)
	x.how:SetShown(not special)
	if data.header then
		x.title:ClearAllPoints()
		x.title:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 22, 8)
		x.title:SetText(data.title)
		x.note:ClearAllPoints()
		x.note:SetPoint("BOTTOMLEFT", x.title, "BOTTOMRIGHT", 8, 1)
		x.note:SetText(data.note or "")
		x.right:ClearAllPoints()
		x.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -22, 9)
		x.right:SetText(data.right or "")
	elseif data.emptyLine then
		x.line:ClearAllPoints()
		x.line:SetPoint("LEFT", b, "LEFT", 22, 0)
		x.line:SetText(data.emptyLine)
	elseif data.search then
		local st = Up.SearchState()
		x.chip:ClearAllPoints()
		x.chip:SetPoint("RIGHT", b, "RIGHT", -22, 0)
		local label = st.running and st.progress or L["Search AH for these"]
		x.chip:SetLabel(label)
		local enabled = st.open and not st.running
		if enabled then
			x.chip:Enable()
		else
			x.chip:Disable()
		end
		x.chip.label:SetTextColor(unpack(st.running and C.live or enabled and C.text or C.text3))
		x.chip.cwTip = st.running and L["One search per equipment slot; closing the auction house stops it."]
			or enabled and L["One search per equipment slot for gear you can wear now, while the auction house is open. Nothing runs in the background."]
			or L["open the auction house to search"]
		if st.failed and st.failed[1] then
			x.chip.cwTip = x.chip.cwTip .. "\n" .. L["No answer last time"] .. ": " .. table.concat(st.failed, ", ")
		end
	else
		-- Name on top, how under it (board: 12 over 10).
		local nameCell = b.cells and b.cells[2]
		if nameCell then
			nameCell:ClearAllPoints()
			nameCell:SetPoint("TOPLEFT", b, "TOPLEFT", 22 + 22 + 12, -6)
			nameCell:SetWidth(200)
			x.how:ClearAllPoints()
			x.how:SetPoint("TOPLEFT", nameCell, "BOTTOMLEFT", 0, -1)
			x.how:SetWidth(200)
		end
		local how = data.how
		if data.dismissed then
			how = (how and (how .. " · ") or "") .. L["dismissed"]
		end
		x.how:SetText(how or "")
		local c = Style.Color(data.howColor or "text3")
		x.how:SetTextColor(c[1], c[2], c[3], 1)
	end
end

local function Character()
	local name = UnitName and UnitName("player") or nil
	local level = UnitLevel and UnitLevel("player") or nil
	local class = UnitClass and UnitClass("player") or nil
	local parts = {}
	if name then
		parts[#parts + 1] = name
	end
	if level then
		parts[#parts + 1] = (L["level %d"]):format(level) .. (class and (" " .. class) or "")
	end
	parts[#parts + 1] = L["compared with what you wear"]
	return table.concat(parts, " · ")
end

M.RegisterPage({
	key = "upgrades", section = "lookup", label = L["Upgrades"], order = 2,
	events = { "UPGRADES_CHANGED", "BAGS_CHANGED", "LEDGER_CHANGED" },
	rowHeight = Up.ROW_HEIGHT,
	columns = COLUMNS,
	sort = { key = "gain", desc = true },
	SortRows = Up.SortRows,
	Model = function()
		local model = Up.Model()
		Up.lastModel = model
		local right = (L["%d you can craft · %d from the AH"]):format(model.counts.craft, model.counts.ah)
		if model.counts.dismissed > 0 then
			right = right .. " · " .. (L["%d dismissed"]):format(model.counts.dismissed)
		end
		return {
			rows = model.rows,
			footer = L["Gain: the item's stats minus what you wear in that slot. Cost: reagents for crafts, lowest buyout for the AH."],
			footerRight = right,
		}
	end,
	InitRow = InitRow,
	OnClick = function() end,
	Tools = function(slot)
		slot.text = Style.Text(slot, "Caption", "text3")
		slot.text:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		slot.text:SetJustifyH("RIGHT")
	end,
	UpdateTools = function(slot)
		slot.text:SetText(Character())
	end,
})
