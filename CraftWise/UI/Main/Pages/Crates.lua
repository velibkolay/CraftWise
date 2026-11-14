-- Gather › Crates (#156; spec #150 "Gather: Crates", board "Gather › Crates"). Replaces Records › Crates.
-- Two cards (the best of the crates you hold: cheapest to fill per Favor; the best to buy and fill), then
-- every recorded Waylaid crate by cost per Merchant's Favor: Crate (with "10 Favor · measured" when the
-- reward was measured at turn-ins, "· tooltip" when the crate's tooltip states it), Crate price, Fill,
-- a rail of cost per Favor (shorter = cheaper), You hold, Per Favor. A fill without bundle prices says
-- "no price". The sub bar names Merchant's Favor on this character. A row opens into its bundles, the
-- reward and what is missing.
-- Data: Crates.lua (C.Ranked, C.Evaluate, C.Balance, C.Reward, C.FavorName); this file only draws. Showing
-- the page looks at the bags and the auction house records for crates, as /craftwise crates does.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C
local FF = ns.FarmFrame

local P = {}
ns.GatherCrates = P

P.KEY = "crates"
P.SCAN_EVERY = 10 -- seconds between looks at the bags and AH records while the page refreshes
P.LINE = 18

local lastScan

local function Paint(text, color)
	return Style.Hex(color) .. text .. "|r"
end

local function Coins(copper)
	return FF.Coins(copper and math.floor(copper + 0.5) or nil)
end

----------------------------------------------------------------------------------------------------
-- Model
----------------------------------------------------------------------------------------------------

-- "10 Favor · measured" | "10 Favor · tooltip" | "10 Favor · guide" | "reward not seen yet".
function P.RewardNote(e)
	if not e.reward then
		return L["reward not seen yet"]
	end
	local how = e.rewardFrom == "tooltip" and L["tooltip"] or e.rewardFrom == "guide" and L["guide"] or L["measured"]
	return ("%d %s · %s"):format(e.reward, L["Favor"], how)
end

-- The guide's source for the tooltip: "guide (Forever Mastery, Forever Changes), not measured".
function P.GuideNote()
	local g = ns.CrateFavorGuide
	local names = {}
	for _, src in ipairs(g and g.sources or {}) do
		names[#names + 1] = src.label
	end
	return (L["guide (%s), not measured"]):format(table.concat(names, ", "))
end

local function Scan(now)
	local Cr = ns.Crates
	if not Cr or (lastScan and now - lastScan < P.SCAN_EVERY) then
		return
	end
	lastScan = now
	pcall(Cr.ScanBags)
	pcall(Cr.ScanMarket)
end

local function Row(e, max)
	return { key = e.id, itemID = e.id, name = e.name or ("item " .. tostring(e.id)), note = P.RewardNote(e),
		measured = e.rewardFrom == "seen", guide = e.rewardFrom == "guide", crate = e.crate, crateLabel = e.crateLabel, fill = e.fillCost,
		fillName = e.fill and e.fill.name, fillN = e.fill and e.fill.n, hasOptions = #e.options > 0,
		perFavor = e.perFavor, fillPerFavor = e.fillPerFavor, held = e.held, railMax = max, entry = e }
end

function P.Model(ctx)
	local Cr = ns.Crates
	if not Cr then
		return { rows = {}, empty = "" }
	end
	Scan(time())
	local list, best, bestHeld = Cr.Ranked()
	local values = {}
	for i, e in ipairs(list) do
		values[i] = e.perFavor
	end
	local max = Style.SharedScale(values)
	local rows = {}
	for i, e in ipairs(list) do
		rows[i] = Row(e, max)
	end
	return {
		rows = rows,
		hero = { bare = true, height = M.IsDocked(ctx) and M.Docked.StackCardsHeight(2) or 66, -- provisional (#161 Q4)
			held = bestHeld, best = best, favor = Cr.FavorName() or L["Merchant's Favor"] },
		listTitle = L["Waylaid crates by cost per Favor"],
		listNote = L["crate bought + cheapest bundle, divided by the Favor it gives"],
		empty = L["No Waylaid crate seen yet: carry one, or let an auction house scan see one."],
		footer = L["Favor per crate: measured at your turn-ins, as the crate's tooltip states it, else the published guide (labelled guide)."],
	}
end

-- Cheapest Favor first, then those only priced to fill, then by name (as Crates.Ranked).
function P.SortRows(rows, key, desc)
	table.sort(rows, function(a, b)
		local va, vb = a[key], b[key]
		if va ~= vb then
			if va == nil then
				return false
			elseif vb == nil then
				return true
			end
			if type(va) == "string" then
				va, vb = va:lower(), vb:lower()
			end
			if desc then
				return va > vb
			end
			return va < vb
		end
		if (a.fillPerFavor ~= nil) ~= (b.fillPerFavor ~= nil) then
			return a.fillPerFavor ~= nil
		end
		if a.fillPerFavor and a.fillPerFavor ~= b.fillPerFavor then
			return a.fillPerFavor < b.fillPerFavor
		end
		return a.name < b.name
	end)
end

----------------------------------------------------------------------------------------------------
-- Columns (board: icon 22, Crate 180, Crate 70, Fill 80, rail, You hold 60, Per Favor 80)
----------------------------------------------------------------------------------------------------

P.COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Crate"], width = 180, sort = true },
	{ key = "crate", label = L["Crate"], width = 70, align = "RIGHT", sort = true, font = "Figure",
		text = function(r) return r.crate and Coins(r.crate) or Paint(M.DASH, "text3") end,
		color = function() return "text2" end,
		tip = function(r)
			return r.crate and { L["Crate price"], FF.PlainCoins(math.floor(r.crate + 0.5)) .. " " .. (r.crateLabel or "") }
				or { L["Crate price"], L["No vendor or auction house price seen for the crate."] }
		end },
	{ key = "fill", label = L["Fill"], width = 80, align = "RIGHT", sort = true, font = "Figure",
		text = function(r)
			if r.fill then
				return Coins(r.fill)
			end
			return r.hasOptions and M.NoPriceText() or Paint(L["not read"], "text3")
		end,
		tip = function(r)
			if r.fill then
				return { L["Cheapest fill"], ("%d %s"):format(r.fillN or 0, r.fillName or "") }
			end
			return { L["Fill"], r.hasOptions and L["No price for any of its bundles."] or L["Fill list not read yet: carry the crate once."] }
		end },
	{ key = "rail", label = "", rail = function(r) return { value = r.perFavor, max = r.railMax } end },
	{ key = "held", label = L["You hold"], width = 60, align = "RIGHT", sort = true, font = "Figure",
		color = function(r) return r.held > 0 and "text" or "text3" end },
	{ key = "perFavor", label = L["Per Favor"], width = 80, align = "RIGHT", sort = true, font = "FigureBold",
		text = function(r) return r.perFavor and Coins(r.perFavor) or Paint(M.DASH, "text3") end },
}

-- The note under the crate's name (board: two lines in the Crate cell).
function P.InitRow(b, row)
	local list = b.cwList
	local i = 2
	local pos = list and list.positions and list.positions[i]
	local cell = b.cells[i]
	if not (pos and cell) then
		return
	end
	if not b.cwNote then
		b.cwNote = Style.Text(b, "Caption", "text3")
		b.cwNote:SetJustifyH("LEFT")
		b.cwNote:SetWordWrap(false)
	end
	cell:ClearAllPoints()
	cell:SetPoint("LEFT", b, "LEFT", pos.x, 6)
	b.cwNote:ClearAllPoints()
	b.cwNote:SetPoint("LEFT", b, "LEFT", pos.x, -7)
	b.cwNote:SetWidth(pos.width)
	b.cwNote:SetText(row.note or "")
	b.cwNote:Show()
end

----------------------------------------------------------------------------------------------------
-- The two cards (a bare hero: the page draws both, board "Crates")
----------------------------------------------------------------------------------------------------

local CARD_GAP = 10

local function Card(area)
	local card = CreateFrame("Frame", nil, area)
	Style.Sheet(card, C.card, C.cardFlap, 14, false)
	card.label = Style.Text(card, "Label", "text3")
	card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
	card.name = Style.Text(card, "Hero", "text")
	card.name:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -1)
	card.name:SetWordWrap(false)
	card.sub = Style.Text(card, "Caption", "text3")
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -1)
	card.sub:SetWordWrap(false)
	return card
end

-- What the two cards say: { label, name, sub } each.
function P.CardTexts(hero)
	local favor = hero.favor
	local held, best = hero.held, hero.best
	local a = { label = L["Best of the crates you hold"] }
	if held then
		a.name = held.name
		local parts = { L["fill for"] .. " " .. Coins(held.fillCost), (L["%s per %s"]):format(Coins(held.fillPerFavor), favor) }
		if held.fill then
			parts[#parts + 1] = ("%d %s"):format(held.fill.n, held.fill.name)
		end
		a.sub = table.concat(parts, " · ")
	else
		a.name, a.nameColor = L["None priced"], "text3"
		a.sub = L["Carry a Waylaid crate whose bundles have a price and it shows here."]
	end
	local b = { label = L["Best to buy and fill"] }
	if best then
		b.name = best.name
		b.sub = L["crate"] .. " " .. Coins(best.crate) .. " + " .. L["fill"] .. " " .. Coins(best.fillCost) .. " · "
			.. (L["%s per %s"]):format(Coins(best.perFavor), favor)
	else
		b.name, b.nameColor = L["None priced"], "text3"
		b.sub = L["Needs a crate price, a bundle price and the reward."]
	end
	return a, b
end

-- slot: with hero.bare, the page's own frame over the whole hero area.
function P.Hero(_, hero, _, slot)
	local area = slot
	if not area.cards then
		area.cards = { Card(area), Card(area) }
	end
	local left, right = area.cards[1], area.cards[2]
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", area, "BOTTOM", -CARD_GAP / 2, 0)
	right:ClearAllPoints()
	right:SetPoint("TOPLEFT", area, "TOP", CARD_GAP / 2, 0)
	right:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
	local texts = { P.CardTexts(hero) }
	for i, t in ipairs(texts) do
		local c = area.cards[i]
		c.label:SetText(t.label)
		c.name:SetText(t.name or "")
		local nc = Style.Color(t.nameColor or "text")
		c.name:SetTextColor(nc[1], nc[2], nc[3], 1)
		c.sub:SetText(t.sub or "")
		c:Show()
	end
end

-- Provisional (#161 Q4): docked, the two cards stack (M.Docked.StackCards).
function P.DockedHero(_, hero, _, slot)
	local cards = {}
	for i, t in ipairs({ P.CardTexts(hero) }) do
		cards[i] = { label = t.label, name = t.name or "", nameColor = t.nameColor, caption = t.sub }
	end
	M.Docked.StackCards(slot, cards)
end

-- Docked (#161): the crate over its cost per Favor, per Favor right with the Favor note under it.
function P.DockedRow(row)
	local c = P.COLUMNS
	return {
		icon = row.icon or (row.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(row.itemID)) or nil,
		name = row.name, rail = c[5].rail(row), result = c[7].text(row), sub = row.note,
		tip = c[4].tip(row),
	}
end

----------------------------------------------------------------------------------------------------
-- Opened row: bundles, reward, crate price, what is missing
----------------------------------------------------------------------------------------------------

local function Lines(row, favor)
	local e = row.entry
	local out = {}
	out[#out + 1] = { L["Crate"], e.crate and (Coins(e.crate) .. Paint(" " .. (e.crateLabel or ""), "text3")) or Paint(L["no crate price"], "text3") }
	for i, o in ipairs(e.options) do
		local what = ("%d %s"):format(o.n, o.name) .. (o.id and "" or Paint(" " .. L["(item not identified)"], "text3"))
		local cost = o.total and (Coins(o.total) .. Paint(" " .. (o.label or "") .. (o.crafted and (" · " .. L["crafted"]) or ""), "text3"))
			or M.NoPriceText()
		if o == e.fill then
			what = what .. Paint(" · " .. L["cheapest"], "text2")
		end
		out[#out + 1] = { i == 1 and L["Bundles"] or "", what, cost, item = o.id }
	end
	if #e.options == 0 then
		out[#out + 1] = { L["Bundles"], Paint(L["fill list not read yet"], "text3") }
	end
	local reward
	if e.reward then
		local how
		if e.rewardFrom == "tooltip" then
			how = L["from the tooltip"]
		elseif e.rewardFrom == "guide" then
			how = P.GuideNote()
		else
			how = (L["seen at %d turn-ins"]):format(e.observed or 0)
		end
		reward = ("%d %s"):format(e.reward, favor) .. Paint(" · " .. how, "text3")
	else
		reward = Paint(L["Reward not seen yet: turn one in once."], "text3")
	end
	out[#out + 1] = { L["Reward"], reward }
	if e.held > 0 and e.fillPerFavor then
		out[#out + 1] = { L["You hold"] .. " " .. e.held, (L["fill only: %s per %s"]):format(Coins(e.fillPerFavor), favor) }
	end
	if #e.missing > 0 then
		out[#out + 1] = { L["Missing"], Paint(table.concat(e.missing, ", "), "danger") }
	end
	return out
end

function P.Layout(pool, content, row, width)
	local favor = ns.Crates and ns.Crates.FavorName() or L["Merchant's Favor"]
	local lines = Lines(row, favor)
	-- Docked (#161): a narrower label column, the cost right aligned.
	local narrow = width < 500
	local x, costX = narrow and 76 or 110, 420
	if pool then
		for i, l in ipairs(lines) do
			local y = (i - 1) * P.LINE
			pool:Text("Label", "text3", l[1]):SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 2))
			local fs = pool:Text("Small", "text", l[2])
			fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
			if narrow then
				fs:SetWidth(width - x - (l[3] and 90 or 0))
			end
			if l[3] then
				local cost = pool:Text("Figure", "text", l[3])
				if narrow then
					cost:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
					cost:SetJustifyH("RIGHT")
				else
					cost:SetPoint("TOPLEFT", content, "TOPLEFT", costX, -y)
				end
			end
			if l.item then
				local hit = pool:Hit({ itemID = l.item })
				hit:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
				hit:SetSize(narrow and (width - x - 90) or 300, P.LINE)
			end
		end
	end
	return #lines * P.LINE
end

local function InnerWidth(ctx)
	return M.OpenInnerWidth(ctx)
end

function P.Open(content, row, ctx)
	local pool = M.Pool(content)
	pool:Reset()
	P.Layout(pool, content, row, InnerWidth(ctx))
end

function P.OpenHeight(row, ctx)
	return P.Layout(nil, nil, row, InnerWidth(ctx))
end

----------------------------------------------------------------------------------------------------
-- Page tools: Merchant's Favor on this character (sub bar, right)
----------------------------------------------------------------------------------------------------

function P.BalanceText()
	local Cr = ns.Crates
	local b = Cr and Cr.Balance()
	local name = (b and b.name) or (Cr and Cr.FavorName()) or L["Merchant's Favor"]
	local amount = b and b.balance
	return ("%s %s: %s"):format(name, L["on this character"], amount and Paint(tostring(amount), "text") or Paint(L["unknown"], "text3"))
end

function P.Tools(slot)
	slot.balance = Style.Text(slot, "Caption", "text3")
	slot.balance:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	slot.balance:SetJustifyH("RIGHT")
end

function P.UpdateTools(slot)
	slot.balance:SetText(P.BalanceText())
end

P.page = M.RegisterPage({
	key = P.KEY, section = "gather", label = L["Crates"], order = 3,
	events = { "CRATES_CHANGED", "PRICES_CHANGED", "BAGS_CHANGED" },
	columns = P.COLUMNS,
	sort = { key = "perFavor", desc = false },
	SortRows = P.SortRows,
	rowHeight = 36,
	Model = function(ctx) return P.Model(ctx) end,
	Hero = function(card, hero, ctx, slot) return P.Hero(card, hero, ctx, slot) end,
	DockedHero = function(card, hero, ctx, slot) return P.DockedHero(card, hero, ctx, slot) end,
	DockedRow = function(row) return P.DockedRow(row) end,
	InitRow = P.InitRow,
	Open = P.Open,
	OpenHeight = P.OpenHeight,
	Tools = P.Tools,
	UpdateTools = P.UpdateTools,
})
