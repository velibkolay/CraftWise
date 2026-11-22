-- Main window, Make › Basket (#186): the crafts you added (from Make › Craft or the vendor loop toast) and
-- what to buy for them. The list: the crafts first (count, expected profit; open one to change the count or
-- remove it), then what to buy at the AH, what to buy at a vendor, items without a price, and what is
-- already in your bags. Lines tick off as the bags fill (BAGS_CHANGED). Data and maths: Basket.lua.
--   AH lines: "Auctionator list" in the list bar builds the shopping list "CraftWise basket" (Auctionator
--   loaded); without Auctionator an AH line opens to its search string.
--   AH → vendor (#312): after each scan Loops.lua puts the items cheaper at the AH than a vendor pays here
--   (units below the vendor price, the max price per unit to pay, the expected profit). The section is
--   replaced on every scan; open a line to dismiss it until it gets clearly better. Auctionator loaded:
--   the shopping list "CraftWise vendor flips" is rebuilt with each check, without it a line opens to its
--   search string. Lines tick off from the bags. Buying is yours: nothing here buys, bids or confirms.
--   Vendor lines: open the line while a merchant that sells it is open: one Buy button, one click, that
--   line's quantity (Basket.Buy). Nothing is bought, listed or confirmed without that click.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L

local B = {}
M.BasketPage = B

local ORDER = { intermediate = -1, craft = 0, made = 0.25, flip = 0.5, auction = 1, vendor = 2, unknown = 3, done = 4 }

local COLUMNS = {
	{ key = "icon", icon = true, width = 22 },
	MK.Column("name", L["Item"], 250, "LEFT", "Body", false),
	MK.Column("qty", L["Quantity"], 90, "RIGHT", "Figure"),
	MK.Column("where", L["Where"], 120, "LEFT", "Body"),
	MK.Column("each", L["Each"], 100, "RIGHT", "Figure"),
	MK.Column("total", L["Total"], 110, "RIGHT", "FigureBold"),
}
B.COLUMNS = COLUMNS

local function Each(line)
	return line.quote and ns.FormatCoins(math.floor(line.quote.cost / line.quantity + 0.5)) or M.DASH
end

-- One row of the list (pure over the plan's pieces): kind, cells in the window layout, view for docked.
local function NewRow(kind, key, name, itemID, icon)
	local view = { name = name, nameColor = kind == "done" and "text3" or "text", icon = icon, itemID = itemID,
		cells = {}, colors = {}, tips = {} }
	view.cells.name, view.colors.name = name, view.nameColor
	return { kind = kind, order = ORDER[kind], key = key, name = name, itemID = itemID, icon = icon, view = view }
end

local function Fill(r, qty, where, each, total, totalColor, whereColor)
	local v = r.view
	v.cells.qty, v.cells.where, v.cells.each, v.cells.total = qty, where, each, total
	v.colors.qty, v.colors.where, v.colors.each, v.colors.total = "text2", whereColor or "text2", "text2", totalColor or "text"
	v.result, v.resultColor, v.sub = total, totalColor or "text", where .. (qty ~= "" and (" · " .. qty) or "")
	return r
end

local function Icon(itemID)
	return itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
end

-- Where a craft sells and whether the bags hold its reagents, as one short text.
function B.StateText(ln)
	if ln.state == "made" then
		return L["made"]
	elseif ln.state == "ready" then
		return L["ready"]
	elseif ln.state == "partly" then
		return (L["%d ready"]):format(ln.can)
	end
	return L["missing reagents"]
end

function B.CountText(ln)
	if ln.made > 0 or ln.left ~= ln.planned then
		return (L["%d of %d crafts"]):format(ln.left, ln.planned)
	end
	return (L["%d crafts"]):format(ln.left)
end

-- The cells of one craft-list line (kind craft, intermediate or made).
function B.FillRun(r, ln)
	local label = ln.label and L[ln.label] or (ln.kind == "intermediate" and L["intermediate"] or L["craft"])
	local where = label .. ", " .. B.StateText(ln)
	local c = ln.craft
	local each, total, color = M.DASH, M.DASH, "text3"
	if ln.profitEach then
		local text
		text, color = MK.Signed(math.floor(ln.profitEach + 0.5))
		each = text
		if ln.kind ~= "made" then
			total, color = MK.Signed(math.floor(ln.profitEach * ln.left + 0.5))
		else
			total, color = MK.Signed(math.floor(ln.profitEach * ln.made + 0.5))
		end
	elseif c then
		local profit = c.row.vendorProfit and c.row.vendorProfit * c.count or nil
		if profit then
			total, color = MK.Signed(profit)
		end
		each = c.row.vendorSale and ns.FormatCoins(c.row.vendorSale) or M.DASH
	end
	if ln.state == "made" or (ln.kind == "craft" and ln.left == 0) then
		r.view.nameColor, r.view.colors.name = "text3", "text3"
		color = "text3"
	end
	Fill(r, B.CountText(ln), where, each, total, color, ln.state == "missing" and "text3" or "text")
end

-- The reagents the next craft lacks, as text for the open line.
function B.MissingText(ln)
	local names = {}
	for _, m in ipairs(ln.missing or {}) do
		names[#names + 1] = ("%d %s"):format(m.short, MK.ItemName(m.itemID))
	end
	return table.concat(names, ", ")
end

-- The rows of a plan (Basket.Plan()).
function B.Rows(plan)
	local rows = {}
	-- The craft list (#389): intermediates first, the crafts by profit per craft-second, what is made last.
	local list = ns.Basket.CraftList(plan, ns.Holdings.Carried())
	plan.list = list
	for i, ln in ipairs(list.lines) do
		local r = NewRow(ln.kind, ln.kind .. ":" .. ln.recipeID, ln.name, ln.outputItemID, ln.icon or Icon(ln.outputItemID))
		r.run, r.craft, r.rank = ln, ln.craft, i
		r.recipeID = ln.recipeID
		B.FillRun(r, ln)
		rows[#rows + 1] = r
	end
	local function ItemRows(lines, kind, where)
		for _, l in ipairs(lines) do
			local r = NewRow(kind, kind .. ":" .. l.itemID, MK.ItemName(l.itemID), l.itemID, Icon(l.itemID))
			r.line = l
			Fill(r, "×" .. l.quantity, where, Each(l), l.quote and ns.FormatCoins(l.quote.cost) or M.NoPriceText(),
				l.quote and "text" or "text3")
			rows[#rows + 1] = r
		end
	end
	for i, f in ipairs(plan.flips or {}) do
		local held = ns.Basket.FlipHeld(f)
		local bought = held >= f.units
		local r = NewRow("flip", "flip:" .. f.itemID, MK.ItemName(f.itemID), f.itemID, Icon(f.itemID))
		r.line, r.rank = f, i
		r.ownTip = B.FlipTip(f)
		r.order = ORDER.flip + i * 1e-6 -- the list sorts by order, then name: best profit first
		if bought then
			r.view.nameColor = "text3"
			r.view.colors.name = "text3"
		end
		local total, color = MK.Signed(f.profit)
		Fill(r, f.atLeast and (L["%d or more"]):format(f.units) or "×" .. f.units, bought and L["in bags"] or L["AH → vendor"],
			"≤ " .. ns.FormatCoins(f.maxUnit), total, bought and "text3" or color, bought and "text3" or "text")
		rows[#rows + 1] = r
	end
	ItemRows(plan.split.auction, "auction", L["AH"])
	ItemRows(plan.split.vendor, "vendor", L["vendor"])
	ItemRows(plan.split.unknown, "unknown", L["no price"])
	for _, d in ipairs(plan.done) do
		local r = NewRow("done", "done:" .. d.itemID, MK.ItemName(d.itemID), d.itemID, Icon(d.itemID))
		r.line = d
		Fill(r, ("%d/%d"):format(math.min(d.held, d.quantity), d.quantity), L["in bags"], "", "", "text3", "text3")
		rows[#rows + 1] = r
	end
	table.sort(rows, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		if a.rank and b.rank and a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return (a.name or "") < (b.name or "")
	end)
	return rows
end

function B.Hero(plan)
	local label = L["Basket"]
	local sum = plan.list and plan.list.summary
	if sum and sum.done then
		local figure, color = M.DASH, "text3"
		if sum.madeProfit then
			figure, color = MK.Signed(math.floor(sum.madeProfit + 0.5))
		end
		return { label = label, name = L["Done"], nameColor = "text",
			sub = (L["%d crafts made"]):format(sum.madeTotal),
			figureLabel = L["Expected profit of the crafts made"], figure = figure, figureColor = color }
	end
	local flips = plan.flips or {}
	if #plan.crafts == 0 and #flips > 0 then
		local profit = 0
		for _, f in ipairs(flips) do
			profit = profit + f.profit
		end
		local figure, color = MK.Signed(profit)
		return { label = label, name = (#flips == 1 and L["1 AH → vendor flip"] or (L["%d AH → vendor flips"]):format(#flips)),
			nameColor = "text", sub = L["buy at the AH, sell to a vendor"],
			figureLabel = L["Expected flip profit"], figure = figure, figureColor = color }
	end
	if #plan.crafts == 0 then
		return MK.NoHero(label, L["nothing in it yet. Open an entry in Make › Craft and add it."])
	end
	local crafts = 0
	for _, c in ipairs(plan.crafts) do
		crafts = crafts + c.count
	end
	local sub = {}
	sub[#sub + 1] = (L["buy at the AH %s"]):format(plan.split.auctionCost > 0 and ns.FormatCoins(plan.split.auctionCost) or M.DASH)
	sub[#sub + 1] = (L["buy at a vendor %s"]):format(plan.split.vendorCost > 0 and ns.FormatCoins(plan.split.vendorCost) or M.DASH)
	if plan.sale then
		sub[#sub + 1] = (L["vendor sale %s"]):format(ns.FormatCoins(plan.sale))
	end
	local figure, color = MK.Signed(plan.profit)
	return {
		label = label,
		name = (#plan.crafts == 1 and L["1 recipe"] or (L["%d recipes"]):format(#plan.crafts)) .. " · " .. (L["%d crafts"]):format(crafts),
		nameColor = "text", sub = table.concat(sub, " · "),
		figureLabel = L["Expected vendor profit"], figure = figure, figureColor = color,
	}
end

function B.Model(ctx)
	local plan = ns.Basket.Plan()
	local rows = B.Rows(plan)
	local note = {}
	if #plan.split.unknown > 0 then
		note[#note + 1] = (L["%d without a price"]):format(#plan.split.unknown)
	end
	if #plan.missing > 0 then
		note[#note + 1] = (L["%d recipes not known any more"]):format(#plan.missing)
	end
	return {
		rows = rows,
		hero = B.Hero(plan),
		listTitle = (L["%d lines"]):format(#rows),
		listNote = L["crafts in order (profit per second), AH → vendor, then AH, vendor, in bags"],
		empty = L["The basket is empty. Open a recipe in Make › Craft and use Add to basket."],
		footer = L["To buy = reagents of the crafts minus what is in your bags, each at the cheaper of the AH and a vendor"]
			.. " · " .. L["Prices"] .. ": " .. MK.PriceBasisText(),
		footerRight = table.concat(note, " · "),
		plan = plan,
	}
end

----------------------------------------------------------------------------------------------------
-- Open: change a craft, search string, Buy
----------------------------------------------------------------------------------------------------

B.OPEN_HEIGHT = 34
B.FLIP_OPEN_HEIGHT = 56 -- the flip line has a second row of text (#312)

local function EditBox(owner)
	local box = CreateFrame("EditBox", nil, owner)
	box:SetSize(360, 24)
	box:SetAutoFocus(false)
	box:SetFontObject(Style.Fonts.Small)
	box:SetTextInsets(8, 8, 0, 0)
	box.border = Style.Border(box, Style.C.ruleStrong)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnTextChanged", function(self, user)
		if user and self.cwText then
			self:SetText(self.cwText) -- read only: it is there to copy
			self:HighlightText()
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	return box
end

function B.Open(content, r, ctx)
	local pool = M.Pool(content)
	pool:Reset()
	local function Say(text, color)
		local fs = pool:Text("Small", color or "text2", text)
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
		return fs
	end
	local Bk = ns.Basket
	-- Every craft-list line: Open the recipe in the profession window (the player presses Create there).
	local function OpenButton(anchor, dx, y)
		local open = pool:Button(L["Open recipe"], function()
			MK.OpenRecipe(r.recipeID)
		end, { L["Open recipe"], L["Shows the recipe in the profession window. You press Create yourself."] }, 24)
		if anchor then
			open:SetPoint("LEFT", anchor, "RIGHT", dx, 0)
		else
			open:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		end
		open:SetShown(MK.CanOpenRecipe(r))
		return open
	end
	if r.kind == "intermediate" or r.kind == "made" then
		local open = OpenButton(nil, 0, -4)
		local text = r.kind == "made" and (L["%d made."]):format(r.run.made)
			or (r.run.state == "ready" and L["The bags hold what these crafts need."] or (L["Missing for the next craft: %s."]):format(B.MissingText(r.run)))
		local fs = pool:Text("Small", "text3", text)
		fs:SetPoint("LEFT", open, "RIGHT", 12, 0)
	elseif r.kind == "craft" then
		local c = r.craft
		local minus = pool:Button("−", function()
			Bk.SetCount(c.entry.recipeID, c.count - 1)
		end, { L["One craft less"], L["At zero the recipe leaves the basket."] }, 24)
		minus:SetSize(28, 24)
		minus:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
		local box = pool:CountBox(c.count, function(v)
			Bk.SetCount(c.entry.recipeID, v)
		end)
		box:SetPoint("LEFT", minus, "RIGHT", 6, 0)
		local plus = pool:Button("+", function()
			Bk.SetCount(c.entry.recipeID, c.count + 1)
		end, { L["One craft more"] }, 24)
		plus:SetSize(28, 24)
		plus:SetPoint("LEFT", box, "RIGHT", 6, 0)
		local ten = pool:Button("+10", function()
			Bk.SetCount(c.entry.recipeID, c.count + 10)
		end, { L["Ten crafts more"] }, 24)
		ten:SetSize(40, 24)
		ten:SetPoint("LEFT", plus, "RIGHT", 6, 0)
		local last = ten
		local max = Bk.Max(c.row.reagents)
		if max then
			local maxButton = pool:Button(L["Max"], function()
				Bk.SetCount(c.entry.recipeID, max)
			end, { L["Max"], (L["Sets the count to %d: what the reagents you hold that no vendor sells allow."]):format(max) }, 24)
			maxButton:SetSize(40, 24)
			maxButton:SetPoint("LEFT", ten, "RIGHT", 6, 0)
			if maxButton.SetEnabled then
				maxButton:SetEnabled(max >= 1)
			end
			last = maxButton
		end
		local remove = pool:Button(L["Remove from basket"], function()
			Bk.Remove(c.entry.recipeID)
		end, { L["Remove from basket"] }, 24)
		remove:SetPoint("LEFT", last, "RIGHT", 12, 0)
		local open = OpenButton(remove, 12)
		if r.run and r.run.state ~= "ready" and #r.run.missing > 0 then
			local fs = pool:Text("Small", "text3", (L["Missing for the next craft: %s."]):format(B.MissingText(r.run)))
			fs:SetPoint("LEFT", open, "RIGHT", 12, 0)
		end
	elseif r.kind == "flip" then
		local f = r.line
		local held = Bk.FlipHeld(f)
		local dismiss = pool:Button(L["Dismiss"], function()
			Bk.DismissFlip(f.itemID)
		end, { L["Dismiss"], L["Takes the line out until it gets clearly better. Buying it is up to you."] }, 24)
		dismiss:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
		local text = (L["%d of %d in your bags."]):format(math.min(held, f.units), f.units)
		if Bk.HasAuctionator() then
			text = text .. " " .. (L["Search it in the Auctionator list \"%s\" (max price per unit set)."]):format(Bk.FLIP_LIST_NAME)
		else
			local s = Bk.FlipSearchString(f)
			if s then
				local box = pool:Take("edit", EditBox)
				box.cwText = s
				box:SetText(s)
				box:SetPoint("LEFT", dismiss, "RIGHT", 12, 0)
				text = L["Auctionator isn't loaded. Search string to copy:"]
			end
		end
		local fs = pool:Text("Small", "text3", text)
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -34)
	elseif r.kind == "auction" then
		if Bk.HasAuctionator() then
			Say(L["Use Auctionator list in the list bar: it builds the shopping list \"CraftWise basket\" from the AH lines."])
		else
			local s = Bk.SearchString(r.line)
			if s then
				Say(L["Auctionator isn't loaded. Search string to copy:"], "text3")
				local box = pool:Take("edit", EditBox)
				box.cwText = s
				box:SetText(s)
				box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -22)
			else
				Say(L["The item's name isn't loaded yet."], "text3")
			end
		end
	elseif r.kind == "vendor" then
		local ok, why, slot, quantity = Bk.CanBuy(r.line)
		local lot = slot and slot.stack or 1
		local label = ok and (lot > 1 and (L["Buy %d (%d lots of %d)"]):format(quantity, quantity / lot, lot)
			or (L["Buy %d"]):format(quantity)) or L["Buy"]
		local buy = pool:Button(label, function()
			local bought, err = Bk.Buy(r.line)
			if bought then
				ns.Print(("Bought %d × %s."):format(bought, MK.ItemName(r.line.itemID)))
			elseif err then
				ns.Print(err .. ".")
			end
			M.Refresh()
		end, { L["Buy"], L["Buys this line's quantity from the open merchant. One click, one purchase."] }, 24)
		buy:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
		if buy.SetEnabled then
			buy:SetEnabled(ok)
		end
		local fs = pool:Text("Small", "text3", ok and "" or (why or ""))
		fs:SetPoint("LEFT", buy, "RIGHT", 12, 0)
	elseif r.kind == "done" then
		Say((L["%d of %d in your bags."]):format(math.min(r.line.held, r.line.quantity), r.line.quantity), "text3")
	else
		Say(L["No AH price at the profit house and no vendor price: nothing to buy it with is known."], "text3")
	end
end

-- What a flip line says when hovered: its count and its price (Style tip: title, lines).
function B.FlipTip(f)
	local count = f.atLeast
		and (L["%d or more units are listed below the vendor price. Only the cheapest eight price steps are stored, so there may be more."]):format(f.units)
		or (L["%d units are listed below the vendor price."]):format(f.units)
	return { MK.ItemName(f.itemID), count,
		(L["Pay at most %s each: a vendor pays %s. The profit is what you keep selling them all to a vendor."]):format(ns.FormatCoins(f.maxUnit), ns.FormatCoins(f.sell)),
		L["Profit: for each unit below the vendor price, the vendor price minus its AH price."], ns.Loops.EachText(f) }
end

function B.OpenHeight(r)
	return r and r.kind == "flip" and B.FLIP_OPEN_HEIGHT or B.OPEN_HEIGHT
end

----------------------------------------------------------------------------------------------------
-- List bar: Auctionator list, Clear
----------------------------------------------------------------------------------------------------

function B.AuctionatorList()
	local plan = ns.Basket.Plan()
	local n, why = ns.Basket.CreateAuctionatorList(plan.split.auction)
	if n then
		ns.Print((L["Auctionator shopping list \"%s\" has %d items. Open the auction house and search it there."]):format(ns.Basket.LIST_NAME, n))
	else
		ns.Print(why .. ".")
	end
end

----------------------------------------------------------------------------------------------------
-- Craft list next to the profession window (#389)
----------------------------------------------------------------------------------------------------
-- A panel on the right of the profession window (like "To send" at the trade window, TradeFill.lua) lists the crafts
-- of the basket in order: intermediates first, then by profit per craft-second, what is made ticked and last. A click
-- on a line opens the recipe there (C_TradeSkillUI.OpenRecipe); the player presses Create, nothing is crafted from here.
-- It redraws on BASKET_CHANGED (a craft ticked, an entry added) and BAGS_CHANGED, at most 4 times a second. The x hides
-- it until the basket changes next; it is not there while the basket has nothing to craft or tally.
B.PANEL_WIDTH, B.PANEL_ROWS, B.PANEL_ROW = 290, 9, 34
B.PANEL_THROTTLE = 0.25

-- Pure over the craft list: what the panel says. { title, sub, rows = { { name, count, sub, tick, state, recipeID, tip } },
-- more = lines not shown } | nil when there is nothing to show.
function B.PanelModel(list)
	if not list or #list.lines == 0 then
		return nil
	end
	local sum = list.summary
	local model = { title = L["Craft list"], rows = {} }
	if sum.done then
		local text = (L["Done: %d crafts made"]):format(sum.madeTotal)
		if sum.madeProfit then
			text = text .. ", " .. (L["expected profit %s"]):format(ns.FormatCoins(math.floor(sum.madeProfit + 0.5)))
		end
		model.sub = text
	else
		local text = (L["%d crafts left"]):format(sum.left)
		if sum.profitLeft then
			text = text .. ", " .. (L["expected profit %s"]):format(ns.FormatCoins(math.floor(sum.profitLeft + 0.5)))
		end
		if sum.madeTotal > 0 then
			text = text .. ", " .. (L["%d made"]):format(sum.madeTotal)
		end
		model.sub = text
	end
	for i, ln in ipairs(list.lines) do
		local parts = {}
		if ln.label then
			parts[#parts + 1] = L[ln.label]
		end
		if ln.profitEach then
			parts[#parts + 1] = (L["%s each"]):format(ns.FormatCoins(math.floor(ln.profitEach + 0.5)))
		end
		parts[#parts + 1] = B.StateText(ln)
		if ln.state ~= "ready" and ln.state ~= "made" and #ln.missing > 0 then
			parts[#parts + 1] = (L["needs %s"]):format(B.MissingText(ln))
		end
		model.rows[i] = { name = ln.name, count = ln.state == "made" and (L["%d made"]):format(ln.made) or B.CountText(ln),
			sub = table.concat(parts, ", "), tick = ln.left == 0, state = ln.state, recipeID = ln.recipeID,
			intermediate = ln.kind == "intermediate" }
	end
	return model
end

local panel, dismissed, queued

local function PanelRow(i)
	local rows = panel.rows
	if rows[i] then
		return rows[i]
	end
	local r = CreateFrame("Button", nil, panel)
	r:SetSize(B.PANEL_WIDTH - 24, B.PANEL_ROW - 2)
	r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(58 + (i - 1) * B.PANEL_ROW))
	r.hover = r:CreateTexture(nil, "BACKGROUND")
	r.hover:SetAllPoints(r)
	Style.Fill(r.hover, Style.C.card)
	r.hover:Hide()
	r.tick = r:CreateTexture(nil, "ARTWORK")
	r.tick:SetSize(14, 14)
	r.tick:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
	r.tick:SetTexture("Interface\Buttons\UI-CheckBox-Check")
	r.name = Style.Text(r, "Body", "text")
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 20, 0)
	r.name:SetWidth(B.PANEL_WIDTH - 24 - 20)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.sub = Style.Text(r, "Small", "text3")
	r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
	r.sub:SetWidth(B.PANEL_WIDTH - 24 - 20)
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(false)
	r:SetScript("OnClick", function(self)
		if self.recipeID then
			MK.OpenRecipe(self.recipeID)
		end
	end)
	r:SetScript("OnEnter", function(self)
		self.hover:Show()
		Style.ShowTip(self, self.name:GetText() or "", L["Click to open the recipe. You press Create yourself."])
	end)
	r:SetScript("OnLeave", function(self)
		self.hover:Hide()
		Style.HideTip(self)
	end)
	rows[i] = r
	return r
end

function B.DrawPanel()
	queued = false
	if not panel then
		return
	end
	local model = ns.db and B.PanelModel(ns.Basket.CraftList(ns.Basket.Plan(), ns.Holdings.Carried()))
	if not model or dismissed then
		panel:Hide()
		return
	end
	panel:Show()
	panel.sub:SetText(model.sub)
	local shown = math.min(#model.rows, B.PANEL_ROWS)
	for i = 1, shown do
		local row, r = model.rows[i], PanelRow(i)
		r.recipeID = row.recipeID
		r.tick:SetShown(row.tick)
		local text = row.count .. "  " .. (row.name or "")
		r.name:SetText(text)
		local c = Style.Color((row.tick and "text3") or "text")
		r.name:SetTextColor(c[1], c[2], c[3], 1)
		r.sub:SetText(row.sub)
		r:Show()
	end
	for i = shown + 1, #panel.rows do
		panel.rows[i]:Hide()
	end
	panel.more:SetText(#model.rows > shown and (L["+%d more in Make > Basket"]):format(#model.rows - shown) or "")
	panel:SetHeight(58 + shown * B.PANEL_ROW + 26)
	panel.more:ClearAllPoints()
	panel.more:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -(58 + shown * B.PANEL_ROW + 4))
end

-- Redraws soon, once for a burst of events.
function B.QueuePanel()
	if not panel or queued then
		return
	end
	queued = true
	if C_Timer and C_Timer.After then
		C_Timer.After(B.PANEL_THROTTLE, B.DrawPanel)
	else
		B.DrawPanel()
	end
end

-- Where the panel sits (#397): the spot the player dragged it to (account-wide, settings.craftListPos), else beside the
-- profession window. The saved spot is kept on the screen.
local function PlacePanel()
	panel:ClearAllPoints()
	local pos = ns.db and ns.db.settings.craftListPos
	if pos and pos.point then
		panel:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, -30)
	end
end

local function SavePanelPosition()
	local point, _, relPoint, x, y = panel:GetPoint(1)
	if point and ns.db then
		ns.db.settings.craftListPos = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

-- Back beside the profession window (right-click the title, or Settings > Look > Reset window positions).
function B.ResetPanelPosition()
	if ns.db then
		ns.db.settings.craftListPos = {}
	end
	if panel then
		panel:StopMovingOrSizing()
		PlacePanel()
	end
end

-- Makes the panel once the profession window exists.
function B.EnsurePanel()
	if panel or not (ProfessionsFrame and type(ProfessionsFrame.GetFrameLevel) == "function") then
		return panel ~= nil
	end
	panel = CreateFrame("Frame", "CraftWiseCraftList", ProfessionsFrame)
	panel:SetSize(B.PANEL_WIDTH, 120)
	PlacePanel()
	panel:SetFrameLevel((ProfessionsFrame:GetFrameLevel() or 1) + 5)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	-- The title is the handle: left button drags, right click goes back to the default place. Only this strip and the
	-- rows and buttons take the mouse; the sheet around them does not.
	panel.handle = CreateFrame("Button", nil, panel)
	panel.handle:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
	panel.handle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, 0)
	panel.handle:SetHeight(28)
	panel.handle:RegisterForDrag("LeftButton")
	panel.handle:RegisterForClicks("RightButtonUp")
	panel.handle:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	panel.handle:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		SavePanelPosition()
	end)
	panel.handle:SetScript("OnClick", B.ResetPanelPosition)
	panel.handle:SetScript("OnEnter", function(self)
		Style.ShowTip(self, L["Craft list"], L["Drag to move. Right-click for the default place."])
	end)
	panel.handle:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	panel.title = Style.Text(panel, "BodyBold", "text")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText(L["Craft list"])
	panel.sub = Style.Text(panel, "Small", "text2")
	panel.sub:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -30)
	panel.sub:SetWidth(B.PANEL_WIDTH - 24)
	panel.sub:SetJustifyH("LEFT")
	panel.more = Style.Text(panel, "Small", "text3")
	panel.close = Style.ActionButton(panel, "x", 22, 18)
	panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
	panel.close:SetScript("OnClick", function()
		dismissed = true
		panel:Hide()
	end)
	panel.rows = {}
	panel:Hide()
	B.panel = panel
	if ProfessionsFrame.HookScript then
		ProfessionsFrame:HookScript("OnShow", B.QueuePanel)
	end
	B.QueuePanel()
	return true
end

ns.Listen("BASKET_CHANGED", function()
	dismissed = false
	B.QueuePanel()
end)
ns.Listen("BAGS_CHANGED", B.QueuePanel)
ns.On("TRADE_SKILL_SHOW", B.EnsurePanel)
ns.On("PLAYER_LOGIN", B.EnsurePanel)
ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_Professions" then
		B.EnsurePanel()
	end
end)

M.RegisterPage({
	key = "basket", section = "make", label = L["Basket"], order = 4, title = L["Basket"],
	prices = true,
	events = { "BAGS_CHANGED", "BASKET_CHANGED", "PRICES_CHANGED" },
	columns = COLUMNS,
	rowHeight = 34,
	sort = { key = "order", desc = false },
	Model = B.Model,
	ListTools = function(slot)
		local clear = Style.Chip(slot, L["Clear basket"])
		clear:SetScript("OnClick", function()
			ns.Basket.Clear()
		end)
		clear:HookScript("OnEnter", function(self)
			Style.ShowTip(self, L["Clear basket"], L["Empties the basket: the crafts you added. Nothing else changes."])
		end)
		clear:HookScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
		local list = Style.Chip(slot, L["Auctionator list"])
		list:SetScript("OnClick", B.AuctionatorList)
		list:HookScript("OnEnter", function(self)
			Style.ShowTip(self, L["Auctionator list"], L["Creates the Auctionator shopping list \"CraftWise basket\" from the AH lines. You search and buy there yourself."])
		end)
		list:HookScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
		slot.chips = { list, clear }
		MK.LayoutChips(slot, slot.chips)
	end,
	UpdateListTools = function(slot)
		slot.chips[1]:SetShown(ns.Basket.HasAuctionator())
	end,
	Open = B.Open,
	OpenHeight = B.OpenHeight,
})
