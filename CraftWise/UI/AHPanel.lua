-- The CraftWise panel next to the auction house window (#315, part 1): the flips and the basket's AH lines, a
-- search per line, the listed results, and one Buy button that shows what it will spend. All the buying is in
-- AHBuy.lua; this file only draws and forwards the clicks:
--   * a click on a line picks it and searches it (one search, nothing else);
--   * the Search button searches the picked line again;
--   * the Buy button's OnClick calls AHBuy.Click: the one place a purchase can start from this panel.
-- Nothing here buys, searches or lists on an event or a timer.
local _, ns = ...
local L, Style = ns.L, ns.Style

local P = {}
ns.AHPanel = P

P.WIDTH = 300
P.LINES = 8
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

-- The text of a line row: "Linen Cloth ×15 · max 99c".
function P.LineText(l)
	local t = ("%s ×%d"):format(ItemName(l.itemID), l.need)
	if l.maxUnit then
		t = t .. " · max " .. Money(l.maxUnit)
	end
	return t
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
	r.text:SetWidth(P.WIDTH - 32)
	r.text:SetJustifyH("LEFT")
	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetAllPoints(r)
	Style.Fill(r.mark, Style.C.selected)
	r:SetScript("OnClick", function(self)
		if self.line and ns.AHBuy.Pick(self.line) then
			ns.AHBuy.Search() -- one click: pick and search this line, nothing more
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
	panel:SetHeight(-y + 28)
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
	panel:SetScript("OnShow", function()
		cached = nil
		P.Update()
	end)
	P.panel = panel
end

ns.On("AUCTION_HOUSE_SHOW", function()
	Create()
	cached = nil
	P.Update()
end)
ns.Listen("AHBUY_CHANGED", P.Update)
-- The basket, the bags or the prices changed: the kept lines are out of date.
for _, name in ipairs({ "BASKET_CHANGED", "BAGS_CHANGED", "PRICES_CHANGED" }) do
	ns.Listen(name, function()
		cached = nil
		P.Update()
	end)
end
