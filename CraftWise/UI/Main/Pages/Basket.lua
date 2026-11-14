-- Main window, Make › Basket (#186): the crafts you added (from Make › Craft or the vendor loop toast) and
-- what to buy for them. The list: the crafts first (count, expected profit; open one to change the count or
-- remove it), then what to buy at the AH, what to buy at a vendor, items without a price, and what is
-- already in your bags. Lines tick off as the bags fill (BAGS_CHANGED). Data and maths: Basket.lua.
--   AH lines: "Auctionator list" in the list bar builds the shopping list "CraftWise basket" (Auctionator
--   loaded); without Auctionator an AH line opens to its search string.
--   Vendor lines: open the line while a merchant that sells it is open: one Buy button, one click, that
--   line's quantity (Basket.Buy). Nothing is bought, listed or confirmed without that click.
local _, ns = ...
local M = ns.Main
local MK = M.Make
local Style, L = ns.Style, ns.L

local B = {}
M.BasketPage = B

local ORDER = { craft = 0, auction = 1, vendor = 2, unknown = 3, done = 4 }

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

-- The rows of a plan (Basket.Plan()).
function B.Rows(plan)
	local rows = {}
	for _, c in ipairs(plan.crafts) do
		local r = NewRow("craft", "craft:" .. c.entry.recipeID, c.row.name, c.row.outputItemID, c.row.icon)
		r.craft = c
		local profit = c.row.vendorProfit and c.row.vendorProfit * c.count or nil
		local total, color = M.DASH, "text3"
		if profit then
			total, color = MK.Signed(profit)
		end
		Fill(r, (L["%d crafts"]):format(c.count), L["craft"], c.row.vendorSale and ns.FormatCoins(c.row.vendorSale) or M.DASH, total, color, "text")
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
		return (a.name or "") < (b.name or "")
	end)
	return rows
end

function B.Hero(plan)
	local label = L["Basket"]
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
		listNote = L["crafts, then AH, vendor, in bags"],
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
	if r.kind == "craft" then
		local c = r.craft
		local minus = pool:Button("−", function()
			Bk.SetCount(c.entry.recipeID, c.count - 1)
		end, { L["One craft less"], L["At zero the recipe leaves the basket."] }, 24)
		minus:SetSize(28, 24)
		minus:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -4)
		local plus = pool:Button("+", function()
			Bk.SetCount(c.entry.recipeID, c.count + 1)
		end, { L["One craft more"] }, 24)
		plus:SetSize(28, 24)
		plus:SetPoint("LEFT", minus, "RIGHT", 6, 0)
		local ten = pool:Button("+10", function()
			Bk.SetCount(c.entry.recipeID, c.count + 10)
		end, { L["Ten crafts more"] }, 24)
		ten:SetSize(40, 24)
		ten:SetPoint("LEFT", plus, "RIGHT", 6, 0)
		local remove = pool:Button(L["Remove from basket"], function()
			Bk.Remove(c.entry.recipeID)
		end, { L["Remove from basket"] }, 24)
		remove:SetPoint("LEFT", ten, "RIGHT", 12, 0)
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
		local ok, why, _, quantity = Bk.CanBuy(r.line)
		local label = ok and (L["Buy %d"]):format(quantity) or L["Buy"]
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

function B.OpenHeight()
	return B.OPEN_HEIGHT
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
