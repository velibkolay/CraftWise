-- Main window, Sell › Bags (#155; spec in #150 "Sell", board "Sell › Bags"): every carried item grouped by
-- its best outcome (Sell at the AH, Sell to a vendor, Keep, Junk), the user's mark as a line tag, and the
-- hero "What your bags would bring" with its three-part bar. Replaces the profit window's Bags view.
-- Rows come from ns.BagRows (Bags.lua) and the hero from ns.HeroCards.BagValue; this file only groups and
-- draws. The row data (P.Rows) is kept apart from the drawing (columns, InitRow), so the docked layout
-- (#161) can draw it in two lines.
local _, ns = ...
local M = ns.Main
local S = M.Sell
local Style, L = ns.Style, ns.L
local C = Style.C

local P = {}

-- Groups in their order (spec: Sell at the AH, Sell to a vendor, Keep, Junk). Disenchant only appears once
-- a verified disenchant table exists (#11); "No price" holds items with no value at all, so nothing
-- carried drops out of the list.
P.GROUPS = {
	{ key = "auction", title = L["Sell at the AH"], reason = L["AH beats vendor by your AH rule"] },
	{ key = "vendor", title = L["Sell to a vendor"], reason = L["no AH price, or vendor pays more"] },
	{ key = "disenchant", title = L["Disenchant"], reason = L["disenchanting pays most"] },
	{ key = "none", title = L["No price"], reason = L["no vendor or AH price known"] },
	{ key = "keep", title = L["Keep"], reason = L["marked Keep, or quest items"] },
	{ key = "junk", title = L["Junk"], reason = L["sold with Sell junk at any merchant"] },
}

-- Hero split (spec: AH after cut white, vendor coin gold, junk rule-strong).
P.PARTS = {
	{ key = "auction", label = L["Sell at the AH, after cut"], color = "text" },
	{ key = "vendor", label = L["Sell to a vendor"], color = "coinGold" },
	{ key = "junk", label = L["Junk"], color = "ruleStrong" },
}

local function GroupOf(r)
	if r.junk then
		return "junk"
	elseif r.kept then
		return "keep"
	end
	return r.best or "none"
end
P.GroupOf = GroupOf

local function Each(copper, count)
	if not copper then
		return nil
	end
	if count > 1 then
		return (L["%s each"]):format(ns.FormatCoins(math.floor(copper / count)))
	end
	return ns.FormatCoins(copper)
end

local function UsedText(r)
	local known = 0
	for _, g in ipairs(r.usedIn or {}) do
		known = known + (g.known or 0)
	end
	if known > 0 then
		return (L["used in %d of your recipes"]):format(known)
	end
end

-- Why a row has no value (the tip of its "—").
local function NoValueReason(r)
	if r.ahCutUnverified then
		return L["The AH cut at this house is unverified, so the AH value is not counted."]
	elseif r.bound and not r.vendorValue then
		return L["Soulbound and vendors don't buy it."]
	elseif r.noValue then
		return L["Vendors don't buy it, and no AH price is recorded."]
	end
	return L["No AH price recorded at the profit house, and no vendor price."]
end

-- The note of an item row (board: "22s each · vendor 1s 50c · used in 9 of your recipes").
local function Note(r, group, opts)
	local parts = {}
	local function add(text)
		if text then
			parts[#parts + 1] = text
		end
	end
	-- Stale: each AH figure carries its age in red (spec "States"); ahAge is in days (Prices.lua).
	local ahAge = opts.stale and r.ahAge and (" " .. Style.Hex("danger") .. M.ShortAge(r.ahAge * 86400) .. "|r") or ""
	if group == "auction" then
		add(r.ahValue and (Each(r.ahValue, r.count) .. ahAge) or M.NoPriceText())
		add(r.vendorValue and (L["vendor"] .. " " .. Each(r.vendorValue, r.count)))
	elseif group == "vendor" then
		add(L["vendor"] .. " " .. Each(r.vendorValue, r.count))
		if r.ahSmallEdge then
			add((L["AH +%s, under your AH rule"]):format(ns.FormatCoins(r.ahSmallEdge)) .. ahAge)
		elseif r.ahValue then
			add((L["AH %s after cut"]):format(ns.FormatCoins(r.ahValue)) .. ahAge)
		elseif r.bound then
			add(L["soulbound"])
		elseif r.ahCutUnverified then
			add(L["AH cut unverified"])
		else
			add(L["no AH price"])
		end
	elseif group == "disenchant" then
		add(L["can be disenchanted"])
	elseif group == "junk" then
		add(r.quality == 0 and L["grey"] or nil)
		add(r.vendorValue and (L["vendor"] .. " " .. Each(r.vendorValue, r.count)) or M.NoPriceText())
	elseif group == "keep" then
		add(r.questItem and L["quest item"] or nil)
	else
		add(M.NoPriceText())
		add(r.bound and L["soulbound"] or nil)
	end
	add(UsedText(r))
	return table.concat(parts, " · ")
end

-- The user's mark (spec: Keep / Junk / AH as a line tag); quest items have none.
local function Mark(r)
	if r.junk then
		return L["Junk"]
	elseif r.markedAH then
		return L["AH"]
	elseif r.kept and not r.questItem then
		return L["Keep"]
	end
end

-- Rows of the list from ns.BagRows(): a group row ({ group = true, title, note, total, count }) before the
-- items of each group, items by value (highest first, unknown last), ties by name. opts = { matsOnly,
-- showKept, stale }. Returns rows, hidden (items left out by My crafting materials and Show kept).
function P.Rows(bagRows, opts)
	opts = opts or {}
	local byGroup, hidden = {}, 0
	for _, r in ipairs(bagRows or {}) do
		if (r.kept and not r.junk and not opts.showKept) or (opts.matsOnly and not r.usedMine) then
			hidden = hidden + 1
		else
			local g = GroupOf(r)
			byGroup[g] = byGroup[g] or {}
			table.insert(byGroup[g], r)
		end
	end
	local rows = {}
	for _, def in ipairs(P.GROUPS) do
		local items = byGroup[def.key]
		if items then
			table.sort(items, function(a, b)
				local va, vb = a.bestValue, b.bestValue
				if def.key == "keep" then
					va, vb = nil, nil
				end
				if va ~= vb then
					if va == nil then
						return false
					elseif vb == nil then
						return true
					end
					return va > vb
				end
				return (a.name or "") < (b.name or "")
			end)
			local total, valued = 0, 0
			local group = { group = true, key = "group:" .. def.key, groupKey = def.key, title = def.title, count = #items }
			rows[#rows + 1] = group
			for _, r in ipairs(items) do
				local value = def.key ~= "keep" and r.bestValue or nil
				if value then
					total, valued = total + value, valued + 1
				end
				rows[#rows + 1] = {
					key = r.itemID, itemID = r.itemID, icon = r.icon, name = r.name, quality = r.quality, count = r.count,
					groupKey = def.key, note = Note(r, def.key, opts), mark = Mark(r), value = value,
					kept = def.key == "keep", noValue = value == nil and def.key ~= "keep",
					reason = value == nil and def.key ~= "keep" and NoValueReason(r) or nil,
				}
			end
			group.note = S.Count(#items, L["item"], L["items"]) .. " · " .. def.reason
			group.total = valued > 0 and total or nil
		end
	end
	return rows, hidden
end

-- The hero's parts from ns.HeroCards.BagValue: { key, label, color, copper, share }.
function P.HeroParts(value)
	local out = {}
	for _, p in ipairs(P.PARTS) do
		out[#out + 1] = { key = p.key, label = p.label, color = p.color, copper = value.parts[p.key] or 0,
			share = value.shares[p.key] or 0 }
	end
	return out
end

-- Footer line (board), with the bag click the user chose in Settings › Bags and loot.
function P.FooterText(menuClick)
	local text = L["Click an item: Keep · Junk · Sell on AH · Where to buy · Price history."]
	if menuClick == "middle" then
		return text .. " " .. L["In your bags: middle-click."]
	elseif menuClick == "altright" then
		return text .. " " .. L["In your bags: Alt + right-click."]
	end
	return text
end

function P.Model(ctx)
	local s = ns.db.settings
	local all = ns.BagRows()
	local rows, hidden = P.Rows(all, { matsOnly = s.bagsMatsOnly, showKept = s.showKept,
		stale = ctx.prices and ctx.prices.stale })
	local model = { rows = rows, footer = P.FooterText(s.menuClick) }
	local value = ns.HeroCards.BagValue(all)
	if value then
		model.hero = { label = L["What your bags would bring"], full = true, height = 88, total = value.total,
			parts = P.HeroParts(value), uncounted = value.uncounted }
	end
	if hidden > 0 then
		model.footerRight = (L["%d hidden by the filters"]):format(hidden)
	end
	if #all == 0 then
		model.empty = L["Your bags are empty."]
	elseif #rows == 0 then
		model.empty = L["Every item is hidden by My crafting materials or Show kept."]
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

P.columns = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", width = 210, color = function(r) return S.QualityColor(r.quality) end },
	{ key = "count", width = 40, align = "RIGHT", font = "Figure", color = function() return "text2" end,
		text = function(r) return r.count and ("×" .. r.count) or "" end },
	{ key = "note", font = "Caption", color = function() return "text2" end },
	{ key = "mark", width = 70, align = "RIGHT", text = function() return "" end },
	{ key = "value", width = 90, align = "RIGHT", font = "FigureBold",
		text = function(r)
			if r.kept then
				return ""
			end
			return r.value and ns.FormatCoins(r.value) or M.DASH
		end,
		tip = function(r)
			if r.reason then
				return { L["No value"], r.reason }
			end
		end },
}
local VALUE_COLUMN, MARK_COLUMN = 6, 5

-- Group rows: title (Section), count and reason (Caption C.text3), total right, the 2 unit C.text rule.
local function GroupParts(b)
	local g = b.cwGroup
	if g then
		return g
	end
	g = {}
	g.title = Style.Text(b, "Section", "text")
	g.title:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 22, 8)
	g.note = Style.Text(b, "Caption", "text3")
	g.note:SetPoint("BOTTOMLEFT", g.title, "BOTTOMRIGHT", 8, 1)
	g.total = Style.Text(b, "Figure", "text")
	g.total:SetJustifyH("RIGHT")
	g.total:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -22, 8)
	g.rule = b:CreateTexture(nil, "ARTWORK")
	Style.Fill(g.rule, C.text)
	g.rule:SetHeight(2)
	g.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	g.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.cwGroup = g
	return g
end

function P.InitRow(b, data, ctx)
	local g = GroupParts(b)
	local isGroup = data.group and true or false
	for _, part in pairs(g) do
		part:SetShown(isGroup)
	end
	b.hair:SetShown(not isGroup)
	for _, set in ipairs({ b.cells, b.icons, b.hits }) do
		for _, region in pairs(set) do
			if isGroup then
				region:Hide()
			end
		end
	end
	if isGroup then
		if b.cwTag then
			b.cwTag:Hide()
		end
		if b.cwSkeleton then
			b.cwSkeleton:Hide()
		end
		g.title:SetText(data.title)
		g.note:SetText(data.note or "")
		g.total:SetText(data.total and ns.FormatCoins(data.total) or "")
		return
	end
	if b.icons[1] then
		b.icons[1]:SetDesaturated(data.kept)
	end
	-- the user's mark as a line tag, right-aligned in its column
	if data.mark then
		b.cwTag = b.cwTag or S.Tag(b)
		b.cwTag:SetLabel(data.mark)
		b.cwTag:ClearAllPoints()
		b.cwTag:SetPoint("RIGHT", b.cells[MARK_COLUMN], "RIGHT", 0, 0)
		b.cwTag:Show()
	elseif b.cwTag then
		b.cwTag:Hide()
	end
	-- Scanning: a figure still missing is a skeleton bar (spec "States").
	local scanning = ctx and ctx.prices and ctx.prices.scanning and data.noValue
	if scanning then
		b.cwSkeleton = b.cwSkeleton or M.Skeleton(b, 60, 8)
		b.cwSkeleton:ClearAllPoints()
		b.cwSkeleton:SetPoint("RIGHT", b.cells[VALUE_COLUMN], "RIGHT", 0, 0)
		b.cwSkeleton:Show()
		b.cells[VALUE_COLUMN]:SetText("")
	elseif b.cwSkeleton then
		b.cwSkeleton:Hide()
	end
end

-- Hero: the total under the label, the three parts right, the split bar along the bottom.
function P.Hero(card, hero, ctx, slot)
	if not slot.total then
		slot.total = Style.Text(slot, "FigureL", "text")
		slot.total:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -14)
		slot.uncounted = Style.Text(slot, "Caption", "text3")
		slot.uncounted:SetPoint("TOPLEFT", slot.total, "BOTTOMLEFT", 0, -2)
		slot.parts = {}
		for i = 1, #P.PARTS do
			slot.parts[i] = S.Stat(slot)
		end
		slot.bar = S.SplitBar(slot, 6)
		slot.bar:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0, 0)
		slot.bar:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
	end
	slot.total:SetText(ns.FormatCoins(hero.total))
	slot.uncounted:SetText(hero.uncounted > 0
		and (L["%s without a price not counted"]):format(S.Count(hero.uncounted, L["item"], L["items"])) or "")
	-- parts from the right: Junk, vendor, AH (board order left to right: AH, vendor, Junk)
	local right = nil
	for i = #hero.parts, 1, -1 do
		local p, stat = hero.parts[i], slot.parts[i]
		stat:Set(p.label, ns.FormatCoins(p.copper), nil, p.color)
		stat:SetSize(150, 34)
		stat:ClearAllPoints()
		if right then
			stat:SetPoint("TOPRIGHT", right, "TOPLEFT", -26, 0)
		else
			stat:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
		end
		right = stat
	end
	slot.bar:Set(hero.parts, S.HeroInner(ctx))
end

----------------------------------------------------------------------------------------------------
-- Tools (sub bar): My crafting materials, Show kept, Sort bags. Show dismissed stays in Settings.
----------------------------------------------------------------------------------------------------

function P.Tools(slot)
	local s = ns.db.settings
	slot.mats = Style.Chip(slot, L["My crafting materials"])
	slot.mats:SetScript("OnClick", function()
		s.bagsMatsOnly = not s.bagsMatsOnly
		M.Refresh()
	end)
	slot.kept = Style.Chip(slot, L["Show kept"])
	slot.kept:SetScript("OnClick", function()
		s.showKept = not s.showKept
		M.Refresh()
	end)
	slot.sort = Style.Chip(slot, L["Sort bags"])
	slot.sort:SetScript("OnClick", function()
		if ns.BagSort and not ns.BagSort.Running() then
			ns.BagSort.Start()
		end
		M.Refresh()
	end)
	slot.sort:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Sort bags"],
			L["Kept items and reagents first, then free slots, then items to sell (best value first) in the last bag."])
	end)
	slot.sort:HookScript("OnLeave", function(self)
		P.UpdateTools(slot)
		Style.HideTip(self)
	end)
	slot.sort:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	slot.kept:SetPoint("RIGHT", slot.sort, "LEFT", -8, 0)
	slot.mats:SetPoint("RIGHT", slot.kept, "LEFT", -8, 0)
end

function P.UpdateTools(slot)
	local s = ns.db.settings
	slot.mats:SetOn(s.bagsMatsOnly)
	slot.kept:SetOn(s.showKept)
	-- Orange while it runs (spec: orange means happening now).
	local running = ns.BagSort and ns.BagSort.Running() or false
	slot.sort:SetLabel(running and L["Sorting"] or L["Sort bags"])
	if running then
		slot.sort.label:SetTextColor(C.live[1], C.live[2], C.live[3], 1)
	end
end

-- A click on an item: the item menu (Keep, Junk, Sell on AH, Where to buy, Price history).
function P.OnClick(data)
	if data.itemID and ns.ShowItemMenu then
		ns.ShowItemMenu(data.itemID)
	end
end

M.RegisterPage({
	key = "bags", section = "sell", label = L["Bags"], order = 1, prices = true, noHeader = true,
	events = { "BAGS_CHANGED", "JUNK_CHANGED" },
	columns = P.columns, Model = P.Model, InitRow = P.InitRow, Hero = P.Hero, OnClick = P.OnClick,
	Tools = P.Tools, UpdateTools = P.UpdateTools,
	P = P,
})
