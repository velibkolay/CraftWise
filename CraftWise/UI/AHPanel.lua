-- The CraftWise panel next to the auction house window (#315, part 1): the flips and the basket's AH lines, a
-- search per line, the listed results, and one Buy button that shows what it will spend. All the buying is in
-- AHBuy.lua; this file only draws and forwards the clicks:
--   * a click on a line picks it and searches it (one search, nothing else);
--   * the Search button searches the picked line again;
--   * the Buy button's OnClick calls AHBuy.Click: the one place a purchase can start from this panel.
-- Nothing here buys, searches or lists on an event or a timer.
-- Part 2 (#315): the snipe list lives here too. Lines of the list are marked "snipe" and have a × to remove them;
-- a click on any line also fills the form below (item, max price per unit, "up to"), where Veli types his
-- max price (3g 40s 5c) and saves it. The two keys (AHBuy.lua) walk and buy these same lines.
local _, ns = ...
local L, Style = ns.L, ns.Style

local P = {}
ns.AHPanel = P

P.WIDTH = 340
P.LINES = 12
P.RESULTS = 6
P.ROW = 34 -- a row is two lines: the item and its quantity, then cost, vendor and profit

local panel
local lines = {} -- the line rows
local results = {} -- the result texts
local headings = {} -- the group headings (snipes, flips, basket)
local cached -- AHBuy.Lines(), kept until the basket, the bags or the prices change

local function Money(copper)
	return ns.FormatMoney(copper, true)
end

-- The item's name, never its ID (#328): an item the client hasn't cached is asked for (one load request, the
-- shared throttle in ns.RequestItemData) and shows "…" until ITEM_DATA_LOAD_RESULT redraws the panel.
P.PLACEHOLDER = "…"
local function ItemName(itemID)
	local name = ns.ItemInfoNow and ns.ItemInfoNow(itemID)
	if name then
		return name
	end
	if ns.RequestItemData then
		ns.RequestItemData(itemID, "AHPanel")
	end
	return P.PLACEHOLDER
end

function P.Lines()
	if not cached then
		cached = ns.AHBuy.Lines()
	end
	return cached
end

-- The text of a line row: "Linen Cloth ×15 · max 99c" ("snipe" in front when it is on the snipe list).
function P.LineText(l)
	local t = ("%s ×%d"):format(ItemName(l.itemID), l.need)
	if l.maxUnit then
		t = t .. " · max " .. Money(l.maxUnit)
	end
	if l.snipe then
		t = t .. " · " .. L["snipe"]
	end
	return t
end

-- What a line is: "snipe" (his list), "flip" (AH → vendor) or "basket"; the group a row sits under.
function P.GroupOf(l)
	return l.snipe and "snipe" or l.kind
end

P.GROUPS = { "snipe", "flip", "basket" }

local function Mark(mark, text)
	return (mark and (mark .. " ") or "") .. text
end

-- The model of the panel from the lines (pure reads: the stored tiers, the vendor price kept on the line, the
-- market price): { groups = { snipe = { row... }, flip = {...}, basket = {...} }, totals, scanT }. A row is
-- { line, group, figures } with figures = Loops.FlipLine for a flip, Loops.BasketLine for a basket line, none
-- for a snipe (its max price and limit are the line itself). Nothing is guessed: a figure the data can't give is nil.
function P.Model(list)
	local model = { groups = { snipe = {}, flip = {}, basket = {} } }
	local house = ns.ProfitHouse and ns.ProfitHouse()
	local atLeast = {}
	for _, f in ipairs(ns.Basket and ns.Basket.Flips() or {}) do
		atLeast[f.itemID] = f.atLeast
	end
	local flipLines = {}
	for _, l in ipairs(list or {}) do
		local group = P.GroupOf(l)
		local row = { line = l, group = group }
		if group == "flip" then
			row.sub = l.single and "one" or "bulk" -- two headings: bulk flips first, then one by one (#344)
		end
		if group == "flip" then
			local depth = house and ns.Market and ns.Market.Depth and ns.Market.Depth(l.itemID, house, 8)
			row.atLeast = atLeast[l.itemID] and true or false
			row.figures = ns.Loops.FlipLine(l.need, ns.Loops.TiersOf(depth), l.sell, row.atLeast)
			flipLines[#flipLines + 1] = { need = l.need, sell = l.sell or 0, figures = row.figures, buys = l.buys }
		elseif group == "basket" then
			local quote = ns.AuctionQuote and ns.AuctionQuote(l.itemID)
			row.figures = ns.Loops.BasketLine(l.need, quote and quote.copper)
		end
		local g = model.groups[group]
		g[#g + 1] = row
	end
	if #flipLines > 0 then
		model.totals = ns.Loops.FlipTotals(flipLines)
	end
	local flips = ns.db and ns.db.flips
	model.scanT = flips and flips.t
	return model
end

local function Gain(profit, mark)
	if profit == nil then
		return "?"
	end
	return Mark(mark, (profit < 0 and "-" or "+") .. Money(math.abs(profit)))
end

-- The summary at the top of the panel: "Flips: cost 12g · vendor 20g · profit +8g" and, second, where the figures
-- come from ("from the scan 12m ago"). nil when there are no flip lines.
function P.SummaryText(totals, scanT, now)
	if not totals then
		return nil
	end
	local t = L["Flips"] .. ": " .. L["cost"] .. " " .. Mark(totals.costMark, Money(totals.cost)) .. " · " .. L["vendor"] .. " "
		.. Mark(totals.vendorMark, Money(totals.vendor)) .. " · " .. L["profit"] .. " " .. Gain(totals.profit, totals.profitMark)
	local buys = totals.buys and totals.buys > 0 and ((totals.buysKnown and "" or "≥ ") .. totals.buys .. (totals.buys == 1 and " buy" or " buys") .. " · ") or ""
	local age
	if scanT and ns.Market and ns.Market.FormatAge then
		age = (L["from the scan %s ago; the live search may differ"]):format(ns.Market.FormatAge(math.max(0, (now or time()) - scanT)))
	else
		age = L["scan age unknown; the live search may differ"]
	end
	return t, buys .. age
end

-- The heading of a group: "Flips (3)".
function P.GroupHeading(group, n)
	local name = ({ snipe = L["Snipes"], flip = L["Flips"], basket = L["Basket"] })[group]
	return ("%s (%d)"):format(name, n)
end

-- The heading of a flip sub-group: "Flips · bulk (3)" and "Flips · one by one (2)".
function P.FlipHeading(sub, n)
	return ("%s · %s (%d)"):format(L["Flips"], sub == "one" and L["one by one"] or L["bulk"], n)
end

-- Right end of a flip's first line (#339): "+3c each · 52 buys" or "1 buy"; nil for other rows.
function P.RowEach(row)
	return row.group == "flip" and ns.Loops.EachText(row.line) or nil
end

-- First line of a row: "Linen Cloth ×15" (≥ when the flip lists more than the tiers show).
function P.RowName(row)
	local l = row.line
	return ("%s ×%s%d"):format(ItemName(l.itemID), row.atLeast and "≥" or "", l.need)
end

-- Second line of a row: what it costs, what a vendor pays and the profit (flip); the max per unit and "up to"
-- (snipe); the quantity's cost from the market price, or nothing (basket).
function P.RowDetail(row)
	local l, f = row.line, row.figures
	if row.group == "flip" then
		if not f then
			return L["no stored prices for the cost"] .. " · " .. L["vendor"] .. " " .. Money((l.sell or 0) * l.need)
		end
		return L["cost"] .. " " .. Mark(f.costMark, Money(f.cost)) .. " · " .. L["vendor"] .. " " .. Mark(f.vendorMark, Money(f.vendor))
			.. " · " .. L["profit"] .. " " .. Gain(f.profit, f.profitMark)
	elseif row.group == "snipe" then
		return L["max"] .. " " .. Money(l.maxUnit) .. " " .. L["each"] .. " · " .. L["up to"] .. " " .. l.need
	end
	if not f then
		return L["no market price"]
	end
	return L["cost"] .. " " .. L["about"] .. " " .. Money(f.cost) .. " (" .. L["market price"] .. ")"
end

-- The text of a result row: "12 × 3s 40c = 40s 80c" is built by ResultText below.

-- What the line under the buttons says: AHBuy's message first, else the profit of the plan, else why there is no
-- plan (a button that is off must say why): no line picked, searching, nothing listed.
function P.StatusText(S, plan, why)
	if S.message then
		return S.message
	end
	if plan then
		return plan.profit and (L["Profit %s"]):format(Money(plan.profit)) or nil
	end
	if not S.target then
		return L["Click a line to search it first"]
	end
	return why
end

-- The form below the lines: fills it from a line or an item ID (nothing is saved or searched).
function P.Prefill(what)
	local itemID = type(what) == "table" and what.itemID or what
	local entry = itemID and ns.Snipe.Find(itemID)
	local max = entry and entry.max or type(what) == "table" and what.maxUnit or nil
	P.form = { item = itemID and tostring(itemID) or "", max = max and ns.Snipe.PriceText(max) or "",
		upTo = entry and entry.upTo and tostring(entry.upTo) or "" }
	if itemID then
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
		P.form.item = name or tostring(itemID)
	end
	if P.panel and P.panel.itemBox then
		P.panel.itemBox:SetText(P.form.item)
		P.panel.maxBox:SetText(P.form.max)
		P.panel.upToBox:SetText(P.form.upTo)
		P.form = nil
	end
end

-- Saves the form into the snipe list. Returns true, or false and why (the panel shows it).
function P.Save()
	local panel = P.panel
	if not (panel and panel.itemBox) then
		return false
	end
	local itemID = ns.Snipe.ItemFromText(panel.itemBox:GetText())
	local max, why = ns.Snipe.ParsePrice(panel.maxBox:GetText())
	local upTo
	local upText = (panel.upToBox:GetText() or ""):gsub("%s+", "")
	if upText ~= "" then
		upTo = tonumber(upText)
		if not upTo then
			why = "Buy up to: a whole number"
		end
	end
	local ok
	if not itemID then
		ok, why = false, "Paste an item link or an item ID, or type a name the game knows"
	elseif max and not why then
		ok, why = ns.Snipe.Set(itemID, max, upTo)
	else
		ok = false
	end
	panel.formStatus:SetText(ok and L["Saved to the snipe list"] or why or "")
	if ok then
		panel.itemBox:SetText("")
		panel.maxBox:SetText("")
		panel.upToBox:SetText("")
	end
	return ok, why
end

-- Is the panel there to see (the auction house is open)? Drawn again so it is current.
function P.Show()
	if panel and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		P.Update()
		return true
	end
	return false
end

-- The text of a result row: "12 × 3s 40c · 2h" (units, price per unit, time left when the client says).
function P.ResultText(r, isCommodity)
	local t = ("%d × %s = %s"):format(r.qty, Money(r.unit), Money(r.qty * r.unit))
	if r.left and ns.Market and ns.Market.FormatAge then
		t = t .. " · " .. ns.Market.FormatAge(r.left)
	end
	if r.own then
		t = t .. " · " .. L["yours"]
	end
	return t
end

local function LineRow(i)
	local r = lines[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, panel)
	r:SetSize(P.WIDTH - 24, P.ROW)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
	r.text:SetWidth(P.WIDTH - 60)
	r.text:SetJustifyH("LEFT")
	r.each = Style.Text(r, "Small", "text3")
	r.each:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
	r.each:SetJustifyH("RIGHT")
	r.detail = Style.Text(r, "Small", "text2")
	r.detail:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -17)
	r.detail:SetWidth(P.WIDTH - 30)
	r.detail:SetJustifyH("LEFT")
	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetAllPoints(r)
	Style.Fill(r.mark, Style.C.selected)
	r:SetScript("OnClick", function(self)
		if self.line and ns.AHBuy.Pick(self.line) then
			P.Prefill(self.line) -- the form below shows this line's item and max price
			ns.AHBuy.Search() -- one click: pick and search this line, nothing more
		end
	end)
	-- The × of a snipe line takes it off the list (nothing else; no search, no purchase).
	r.remove = CreateFrame("Button", nil, r)
	r.remove:SetSize(22, 22)
	r.remove:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
	r.remove.text = Style.Text(r.remove, "Small", "text3")
	r.remove.text:SetPoint("CENTER")
	r.remove.text:SetText("×")
	r.remove:SetScript("OnClick", function(self)
		local line = self:GetParent().line
		if line and line.snipe then
			ns.Snipe.Remove(line.itemID)
		end
	end)
	lines[i] = r
	return r
end

local function ResultText(i)
	local fs = results[i]
	if not fs then
		fs = Style.Text(panel, "Small", "text2")
		fs:SetWidth(P.WIDTH - 24)
		fs:SetJustifyH("LEFT")
		results[i] = fs
	end
	return fs
end

-- Draws everything from AHBuy's state.
function P.Update()
	if not (panel and panel:IsShown()) then
		return
	end
	local AB, S = ns.AHBuy, ns.AHBuy.state
	local y = -30
	local list = P.Lines()
	local model = P.Model(list)
	panel.linesTitle:SetShown(#list > 0)
	panel.empty:SetShown(#list == 0)
	-- the summary: the totals of the flips and where they come from
	local sum, age = P.SummaryText(model.totals, model.scanT)
	panel.summary:SetShown(sum ~= nil)
	panel.age:SetShown(sum ~= nil)
	if sum then
		panel.summary:SetText(sum)
		panel.age:SetText(age)
		panel.summary:ClearAllPoints()
		panel.summary:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		panel.age:ClearAllPoints()
		panel.age:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 15)
		y = y - 36
	end
	-- the rows under their group headings, snipes, then flips, then the basket (the order AHBuy.Lines uses)
	local order, h = {}, 0
	for _, g in ipairs(P.GROUPS) do
		for _, row in ipairs(model.groups[g]) do
			order[#order + 1] = row
		end
	end
	local lastGroup
	local sizes = {}
	for _, row in ipairs(order) do
		local key = row.group .. (row.sub or "")
		sizes[key] = (sizes[key] or 0) + 1
	end
	for i = 1, math.max(#order, #lines) do
		local row = order[i]
		local shownRow = row and i <= P.LINES
		if row and i <= P.LINES then
			local key = row.group .. (row.sub or "")
			if key ~= lastGroup then
				lastGroup, h = key, h + 1
				local fs = headings[h]
				if not fs then
					fs = Style.Text(panel, "Small", "text3")
					headings[h] = fs
				end
				fs:SetText(row.sub and P.FlipHeading(row.sub, sizes[key]) or P.GroupHeading(row.group, #model.groups[row.group]))
				fs:ClearAllPoints()
				fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
				fs:Show()
				y = y - 16
			end
			local l = row.line
			local r = LineRow(i)
			r.line = l
			r:Show()
			r.text:SetText(P.RowName(row))
			r.detail:SetText(P.RowDetail(row))
			r.each:SetText(P.RowEach(row) or "")
			r.remove:SetShown(l.snipe and true or false)
			r.mark:SetShown(S.target and S.target.itemID == l.itemID and S.target.kind == l.kind)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
			y = y - P.ROW
		elseif lines[i] then
			lines[i].line = nil
			lines[i]:Hide()
		end
	end
	for i = h + 1, #headings do
		headings[i]:Hide()
	end
	if #list == 0 then
		panel.empty:ClearAllPoints()
		panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 20
	end
	panel.more:SetShown(#list > P.LINES)
	if #list > P.LINES then
		panel.more:SetText((L["+%d more: the search key walks them all"]):format(#list - P.LINES))
		panel.more:ClearAllPoints()
		panel.more:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
		y = y - 16
	end
	y = y - 8
	local plan, why = AB.Refresh()
	local shown = 0
	if S.target and S.isCommodity ~= nil and S.phase ~= "idle" and S.phase ~= "searching" then
		local rows = AB.ReadRows(S.target.itemID, S.isCommodity)
		for i = 1, math.min(#rows, P.RESULTS) do
			local fs = ResultText(i)
			fs:SetText(P.ResultText(rows[i], S.isCommodity))
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
			fs:Show()
			y = y - 16
			shown = i
		end
	end
	panel.listed:SetShown(shown > 0)
	for i = shown + 1, #results do
		results[i]:Hide()
	end
	y = y - 6
	panel.search:ClearAllPoints()
	panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	panel.search:SetEnabled(S.target ~= nil and not S.busy)
	panel.buy:ClearAllPoints()
	panel.buy:SetPoint("LEFT", panel.search, "RIGHT", 8, 0)
	local text, enabled = AB.Describe(plan, why, S.phase, S.busy, GetMoney and GetMoney() or nil)
	panel.buy:SetLabel(text) -- the folded button's label: SetText alone would leave "Buy" on the face
	panel.buy:SetText(text)
	panel.buy:SetEnabled(enabled)
	y = y - 30
	local status = P.StatusText(S, plan, why)
	panel.status:ClearAllPoints()
	panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	panel.status:SetText(status or "")
	y = y - 28
	-- The snipe list's form: item, max price per unit, "up to", Save.
	panel.formTitle:ClearAllPoints()
	panel.formTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	y = y - 16
	local x = 12
	for _, f in ipairs({ { panel.itemBox, 100 }, { panel.maxBox, 76 }, { panel.upToBox, 36 }, { panel.saveButton, 48 } }) do
		f[1]:ClearAllPoints()
		f[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
		x = x + f[2] + 5
	end
	y = y - 28
	panel.formStatus:ClearAllPoints()
	panel.formStatus:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	y = y - 18
	panel.keys:ClearAllPoints()
	panel.keys:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
	y = y - 30
	panel:SetHeight(-y + 12)
end

local function Create()
	if panel or not AuctionHouseFrame then
		return
	end
	panel = CreateFrame("Frame", "CraftWiseAHPanel", AuctionHouseFrame)
	panel:SetSize(P.WIDTH, 200)
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, -30)
	panel:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 5)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.title = Style.Text(panel, "Small", "text3")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText("CraftWise · " .. L["Buy"])
	panel.linesTitle = Style.Text(panel, "Small", "text3")
	panel.linesTitle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -10)
	panel.linesTitle:SetText(L["Click a line to search it"])
	panel.summary = Style.Text(panel, "Small", "text")
	panel.age = Style.Text(panel, "Small", "text3")
	panel.listed = Style.Text(panel, "Small", "text3")
	panel.listed:SetText(L["Listed now (units × price = row total)"])
	panel.empty = Style.Text(panel, "Small", "text3")
	panel.empty:SetText(L["No flips or basket AH lines."])
	panel.search = Style.ActionButton(panel, L["Search"], 70, 24)
	panel.search:SetScript("OnClick", function()
		ns.AHBuy.Search()
	end)
	panel.buy = Style.ActionButton(panel, L["Buy"], P.WIDTH - 24 - 78, 24)
	panel.buy:SetScript("OnClick", function()
		ns.AHBuy.Click()
	end)
	panel.status = Style.Text(panel, "Small", "text2")
	panel.status:SetWidth(P.WIDTH - 24)
	panel.status:SetJustifyH("LEFT")
	panel.more = Style.Text(panel, "Small", "text3")
	-- The snipe list's form (part 2). The boxes are plain edit boxes; Save is the only thing that writes.
	local function Box(width, numeric)
		local box = CreateFrame("EditBox", nil, panel)
		box:SetSize(width, 24)
		box:SetAutoFocus(false)
		box:SetFontObject(Style.Fonts.Small)
		box:SetTextInsets(6, 6, 0, 0)
		box.border = Style.Border(box, Style.C.ruleStrong)
		if numeric then
			box:SetNumeric(true)
			box:SetMaxLetters(4)
		end
		box:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
		end)
		box:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
		end)
		return box
	end
	panel.formTitle = Style.Text(panel, "Small", "text3")
	panel.formTitle:SetText(L["Snipe list: item · max per unit · up to"])
	panel.itemBox = Box(100)
	panel.maxBox = Box(76)
	panel.upToBox = Box(36, true)
	panel.saveButton = Style.ActionButton(panel, L["Save"], 48, 24)
	panel.saveButton:SetScript("OnClick", function()
		P.Save()
	end)
	panel.formStatus = Style.Text(panel, "Small", "text2")
	panel.formStatus:SetWidth(P.WIDTH - 24)
	panel.formStatus:SetJustifyH("LEFT")
	panel.keys = Style.Text(panel, "Small", "text3")
	panel.keys:SetWidth(P.WIDTH - 24)
	panel.keys:SetJustifyH("LEFT")
	panel.keys:SetText(L["Keys: set \"AH: search next\" and \"AH: buy best\" under Key Bindings › AddOns › CraftWise."])
	panel:SetScript("OnShow", function()
		cached = nil
		P.Update()
	end)
	P.panel = panel
	if P.form then -- filled from the item menu before the auction house was opened
		panel.itemBox:SetText(P.form.item)
		panel.maxBox:SetText(P.form.max)
		panel.upToBox:SetText(P.form.upTo)
		P.form = nil
	end
end

ns.On("AUCTION_HOUSE_SHOW", function()
	Create()
	cached = nil
	P.Update()
end)
ns.Listen("AHBUY_CHANGED", P.Update)
-- The basket, the bags or the prices changed: the kept lines are out of date.
-- An item name that was not cached arrived: draw the rows again (only the rows' own items).
local function NameArrived(_, itemID)
	if not (panel and panel:IsShown()) then
		return
	end
	for _, l in ipairs(P.Lines()) do
		if l.itemID == itemID then
			P.Update()
			return
		end
	end
end
ns.On("ITEM_DATA_LOAD_RESULT", NameArrived)
ns.On("GET_ITEM_INFO_RECEIVED", NameArrived)
for _, name in ipairs({ "BASKET_CHANGED", "BAGS_CHANGED", "PRICES_CHANGED", "SNIPE_CHANGED" }) do
	ns.Listen(name, function()
		cached = nil
		P.Update()
	end)
end
