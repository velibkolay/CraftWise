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

P.WIDTH = 300
P.LINES = 12
P.RESULTS = 6

local panel
local lines = {} -- the line rows
local results = {} -- the result texts
local cached -- AHBuy.Lines(), kept until the basket, the bags or the prices change

local function Money(copper)
	return ns.FormatMoney(copper, true)
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	return name or ("item " .. tostring(itemID))
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
	local t = ("%d × %s"):format(r.qty, Money(r.unit))
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
	r:SetSize(P.WIDTH - 24, 22)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
	r.text:SetWidth(P.WIDTH - 60)
	r.text:SetJustifyH("LEFT")
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
	r.remove:SetPoint("RIGHT", r, "RIGHT", 0, 0)
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
	panel.linesTitle:SetShown(#list > 0)
	panel.empty:SetShown(#list == 0)
	for i = 1, math.max(#list, #lines) do
		local l = list[i]
		if i <= P.LINES then
			local r = l and LineRow(i) or lines[i]
			if r then
				r.line = l
				r:SetShown(l ~= nil)
				if l then
					r.text:SetText(P.LineText(l))
					r.remove:SetShown(l.snipe and true or false)
					r.mark:SetShown(S.target and S.target.itemID == l.itemID and S.target.kind == l.kind)
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
					y = y - 22
				end
			end
		end
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
	panel.buy:SetText(text)
	panel.buy:SetEnabled(enabled)
	y = y - 30
	local status = S.message
	if not status and plan and plan.profit then
		status = (L["Profit %s"]):format(Money(plan.profit))
	end
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
for _, name in ipairs({ "BASKET_CHANGED", "BAGS_CHANGED", "PRICES_CHANGED", "SNIPE_CHANGED" }) do
	ns.Listen(name, function()
		cached = nil
		P.Update()
	end)
end
