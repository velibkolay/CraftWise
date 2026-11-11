-- Profit table window: the Fishing view (issue #88). Zones ranked by value per catch (FishingZones.lua); a
-- click on a zone shows its loot table. Rows, summary and tooltips for that view; the other files call these.
local _, ns = ...
local PF = ns.PF
local C = ns.Style.colors
local state, Settings, Money, Muted, ItemName = PF.state, PF.Settings, PF.Money, PF.Muted, PF.ItemName

local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"

-- 78986 -> "78,986"
local function Count(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function Pct(chance)
	if not chance then
		return "?"
	end
	local pct = chance * 100
	if pct >= 10 then
		return ("%d%%"):format(math.floor(pct + 0.5))
	elseif pct >= 0.1 then
		return ("%.1f%%"):format(pct)
	end
	return ("%.2f%%"):format(pct)
end

local function ValueText(low, high)
	if high and high > low then
		return Money(low) .. Muted(" - ") .. Money(high)
	end
	return Money(low)
end

local function SourceLabel(side)
	if side.source == "own" then
		return C.good .. "own catches|r" .. Muted(" · n = " .. Count(side.n))
	end
	return C.info .. "reference|r" .. Muted(" · n = " .. Count(side.n))
end

local function ItemLabel(line)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(line.itemID)
	return name or line.name or ItemName(line.itemID)
end

-- The open zone (detail mode): state.fishZone is its key; state.fishPrefer forces a side.
local function OpenZone()
	if not state.fishZone then
		return nil
	end
	return ns.FishingZones.Zone(state.fishZone, { prefer = state.fishPrefer })
end

-- Reference items the client hasn't loaded yet: ask once per item, refresh when they arrive (names, icons and
-- vendor prices), and keep their sell prices (#83).
local requested = {}
local function LoadItems(lists)
	local missing, sell = {}, {}
	local all = {}
	for _, list in ipairs(lists) do
		for _, line in ipairs(list) do
			all[#all + 1] = line
			for _, c in ipairs(line.unit and line.unit.lines or {}) do
				all[#all + 1] = c -- container contents
			end
		end
	end
	for _, line in ipairs(all) do
		local id = line.itemID
		if not requested[id] then
			requested[id] = true
			sell[id] = true
			if not (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) then
				missing[#missing + 1] = id
			end
		end
	end
	if ns.PersistSellPrices and next(sell) then
		ns.PersistSellPrices(sell)
	end
	if #missing > 0 and ns.WithItemNames then
		ns.WithItemNames(missing, function()
			if PF.frame and PF.frame:IsShown() and PF.View() == "fishing" then
				ns.RefreshProfitFrame()
			end
		end)
	end
end

-- Rows of the view: zones, or the open zone's items. Search matches zone or item names.
local function FishingRows()
	local query = (state.query or ""):lower()
	local out = {}
	if state.fishZone then
		local z = OpenZone()
		state.fishOpen = z
		if not z then
			state.fishZone, state.fishPrefer = nil, nil
			return FishingRows()
		end
		LoadItems({ z.items })
		for _, line in ipairs(z.items) do
			line.name = ItemLabel(line)
			line.sample = line.n
			if query == "" or line.name:lower():find(query, 1, true) then
				out[#out + 1] = line
			end
		end
		return out, 0
	end
	local rank = ns.FishingZones.Rank()
	state.fishRank, state.fishOpen = rank, nil
	local lists = {}
	for _, z in ipairs(rank.zones) do
		lists[#lists + 1] = z.items
	end
	LoadItems(lists)
	for _, z in ipairs(rank.zones) do
		if query == "" or z.key:find(query, 1, true) then
			out[#out + 1] = z
		end
	end
	return out, 0
end

local function RenderZoneRow(row, z)
	row.icon:SetDesaturated(false)
	row.icon:SetTexture(FISHING_ICON)
	row.name:SetText("|cffffffff" .. z.name .. "|r")
	local status = SourceLabel(z.side)
	local other = z.source == "own" and z.ref or z.source == "ref" and z.own or nil
	if other then
		status = status .. Muted(("  ·  %s n = %s"):format(other.source == "own" and "own" or "reference", Count(other.n)))
	end
	row.status:SetText(status)
	local cells = row.cells
	cells.sample:SetText(("n = %s"):format(Count(z.n)))
	local top = {}
	for i = 1, math.min(2, #z.top) do
		local line = z.top[i]
		top[i] = ItemLabel(line) .. Muted(" " .. Pct(line.chance))
	end
	cells.topCatches:SetText(#top > 0 and table.concat(top, Muted(", ")) or Muted("-"))
	if z.perCatch == 0 and z.unpriced > 0 then
		cells.perCatch:SetText(Muted("no price data"))
	else
		cells.perCatch:SetText(ValueText(z.perCatch, z.perCatchHigh) .. (z.unpriced > 0 and (C.warn .. " +?|r") or ""))
	end
	cells.perHour:SetText(z.perHour and Money(z.perHour) or Muted("-"))
	row:Show()
end

local function RenderItemRow(row, line)
	row.icon:SetDesaturated(false)
	row.icon:SetTexture(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(line.itemID) or 134400)
	row.name:SetText("|cffffffff" .. line.name .. "|r")
	local notes = {}
	local u = line.unit
	if u and u.container then
		notes[#notes + 1] = C.info .. "container|r" .. C.muted .. ": " .. u.label
	end
	if line.stack and line.stack[1] ~= line.stack[2] then
		notes[#notes + 1] = ("stack %d-%d"):format(line.stack[1], line.stack[2])
	elseif not line.own and not line.stackKnown then
		notes[#notes + 1] = "stack not given, counted as 1"
	end
	row.status:SetText(Muted(table.concat(notes, " · ")))
	local cells = row.cells
	cells.fishChance:SetText(Pct(line.chance) .. (line.own and Muted(" per catch") or ""))
	cells.sample:SetText(("%s / %s"):format(Count(line.n), Count(line.outof)))
	if u then
		local label = u.container and "contents" or u.label
		cells.unitValue:SetText(ValueText(u.copper, u.high) .. Muted("  " .. label) .. ((u.unpriced or 0) > 0 and (C.warn .. " +?|r") or ""))
		cells.perCatch:SetText(ValueText(line.perCatch, line.perCatchHigh))
	else
		cells.unitValue:SetText(Muted("no price data"))
		cells.perCatch:SetText(Muted("-"))
	end
	row:Show()
end

local function RenderFishingRow(row, r)
	if r.key then
		return RenderZoneRow(row, r)
	end
	return RenderItemRow(row, r)
end

local function FishingSummary()
	local z = state.fishOpen
	if z then
		local text = ("|cffffffff%s|r  ·  %s  ·  %s per catch"):format(z.name, SourceLabel(z.side), ValueText(z.perCatch, z.perCatchHigh))
		if z.perHour then
			text = text .. ("  ·  %s per hour"):format(Money(z.perHour))
		end
		if z.unpriced > 0 then
			text = text .. Muted(("  ·  %d without price left out"):format(z.unpriced))
		end
		local how = z.source == "own"
			and "Chance = items caught per catch (own log, last 90 days)."
			or "Chance = recorded count / recorded fishing loots (reference). Units = chance x stack; a stack range gives low - high."
		return text .. "\n" .. Muted(how .. " Right-click a row or All zones to go back.")
	end
	local rank = state.fishRank or {}
	local text = ("%d zones  ·  own catches: %s"):format(#state.data, Count(rank.own or 0))
		.. Muted((" (last %d days)"):format(rank.days or 90))
	if rank.ref then
		text = text .. "  ·  reference: " .. C.good .. "loaded|r" .. Muted(rank.refGenerated and (" (" .. rank.refGenerated .. ")") or "")
	else
		text = text .. "  ·  reference: " .. Muted("not loaded (docs/fishing-reference.md)")
	end
	return text .. "\n" .. Muted(("Own catches count from n = %d (/craftwise fishing ownmin), else the reference. Value: %s, else vendor; containers by their contents. Click a zone."):format(
		rank.ownMin or 50, PF.PriceBasisText()))
end

local function AddSide(side, label)
	GameTooltip:AddDoubleLine(label, ValueText(side.perCatch, side.perCatchHigh) .. " per catch", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(Muted(side.source == "own" and ("own catches, n = %s"):format(Count(side.n))
		or ("reference, n = %s recorded loots"):format(Count(side.n))))
end

local function ShowZoneTooltip(z)
	GameTooltip:AddLine(z.name)
	GameTooltip:AddLine(Muted(z.source == "own" and "Shows your own catches." or
		(z.own and ("Shows the reference: own catches below n = %d."):format(state.fishRank and state.fishRank.ownMin or 50)
			or "Shows the reference: no own catches here yet.")), 1, 1, 1, true)
	if z.own then
		AddSide(z.own, "Own catches")
	end
	if z.ref then
		AddSide(z.ref, "Reference")
	end
	if z.perHour then
		GameTooltip:AddDoubleLine("Per hour", Money(z.perHour), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddLine(Muted(("%d catches per hour (own timed catches here, n = %d) x value per catch"):format(math.floor(z.rate + 0.5), z.timed)))
	end
	GameTooltip:AddLine(" ")
	for i = 1, math.min(6, #z.items) do
		local line = z.items[i]
		GameTooltip:AddDoubleLine(ItemLabel(line) .. Muted(" " .. Pct(line.chance)),
			line.perCatch and ValueText(line.perCatch, line.perCatchHigh) or Muted("no price"), 1, 1, 1, 1, 1, 1)
	end
	if z.own and z.own.waters and #z.own.waters > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Own catches by water", 1, 0.82, 0)
		for i = 1, math.min(6, #z.own.waters) do
			local w = z.own.waters[i]
			local where = (w.sub and w.sub ~= "" and (w.sub .. ": ") or "") .. (w.label or "?")
			GameTooltip:AddDoubleLine(where .. Muted(" n = " .. w.n), Money(w.perCatch) .. " per catch", 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Muted("Click for the loot table."))
end

local function ShowItemTooltip(line)
	GameTooltip:AddLine(line.name)
	if line.own then
		GameTooltip:AddDoubleLine("Caught", ("%s in %s catches"):format(Count(line.n), Count(line.outof)), 1, 0.82, 0, 1, 1, 1)
	else
		GameTooltip:AddDoubleLine("Recorded", ("%s of %s loots (%s)"):format(Count(line.n), Count(line.outof), Pct(line.chance)), 1, 0.82, 0, 1, 1, 1)
		GameTooltip:AddDoubleLine("Stack", line.stack and ("%d-%d"):format(line.stack[1], line.stack[2]) or "not given (1 counted)", 1, 0.82, 0, 1, 1, 1)
	end
	local u = line.unit
	if not u then
		GameTooltip:AddLine(Muted("No price data: left out of the value per catch."))
		return
	end
	GameTooltip:AddDoubleLine("Unit value", ValueText(u.copper, u.high), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddLine(Muted(u.label))
	if u.container then
		if u.sell then
			GameTooltip:AddDoubleLine("Unopened sells for", Money(u.sell.copper) .. Muted(" " .. u.sell.label), 1, 0.82, 0, 1, 1, 1)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Contents per opening", 1, 0.82, 0)
		for i = 1, math.min(8, #u.lines) do
			local c = u.lines[i]
			local amount = c.high > c.low and ("%.2f-%.2f"):format(c.low, c.high) or ("%.2f"):format(c.low)
			GameTooltip:AddDoubleLine(ItemLabel(c), amount, 1, 1, 1, 1, 1, 1)
		end
		if (u.unpriced or 0) > 0 then
			GameTooltip:AddLine(C.warn .. ("%d contained items without a price left out."):format(u.unpriced) .. "|r", 1, 1, 1, true)
		end
	end
	if line.perCatch then
		GameTooltip:AddDoubleLine("Per catch", ValueText(line.perCatch, line.perCatchHigh), 1, 0.82, 0, 1, 1, 1)
	end
end

local function ShowFishingTooltip(row, r)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if r.key then
		ShowZoneTooltip(r)
	else
		ShowItemTooltip(r)
	end
	GameTooltip:Show()
end

-- Row click: a zone opens its loot table; right-click in the loot table goes back.
local function FishingClick(r, mouse)
	if r.key and mouse ~= "RightButton" then
		state.fishZone, state.fishPrefer, state.offset = r.key, nil, 0
	elseif not r.key and mouse == "RightButton" then
		state.fishZone, state.fishPrefer, state.offset = nil, nil, 0
	else
		return
	end
	state.query = ""
	if PF.frame.search then
		PF.frame.search:SetText("")
		PF.frame.searchHint:Show()
	end
	ns.RefreshProfitFrame()
end

-- Column set of the current fishing mode.
local function FishingLayout()
	return state.fishZone and "fishzone" or "fishing"
end

local function FishingSort()
	local s = Settings()
	if state.fishZone then
		return s.fishItemSortKey or "perCatch", s.fishItemSortDesc ~= false
	end
	return s.fishSortKey or "perCatch", s.fishSortDesc ~= false
end

PF.FishingRows, PF.RenderFishingRow, PF.FishingSummary, PF.ShowFishingTooltip = FishingRows, RenderFishingRow, FishingSummary, ShowFishingTooltip
PF.FishingClick, PF.FishingLayout, PF.FishingSort = FishingClick, FishingLayout, FishingSort
