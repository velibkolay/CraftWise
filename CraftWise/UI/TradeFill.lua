-- Trade window: fill up to 6 slots with one click from a send list (issue #299).
--   * When the trade window opens (TRADE_SHOW) a panel "To send" sits next to TradeFrame: the working send
--     list (SendList.lua), a search to add items from the bags (name, all stacks, or N), quick sources (the
--     basket's materials, items marked Sell on AH), saved lists (click loads, right-click deletes) and a list
--     that loads by itself when the trade partner is that character ("Use for <partner>").
--   * "Fill 6" is the player's click. It places the next stacks into the empty slots of the player's side,
--     as Blizzard's TradeFrame does for a drag: the stack goes on the cursor (C_Container.PickupContainerItem;
--     SplitContainerItem when only part of a stack is wanted) and ClickTradeButton(slot) drops it in the
--     slot. All of it happens inside that one click. If the client keeps an item on the cursor after the
--     drop, the cursor is cleared and the fill stops with a line saying so: then it is one slot per click.
--   * Accepting is never done here: no AcceptTrade, no C_SecureTransfer.AcceptTrade. The player presses Trade.
--   * After a trade the panel counts what went ("sent 12 of 30 stacks") by looking at the bag slots that were
--     placed: gone or smaller = sent. Quantities on the list shrink by what was sent. "Fill next 6" follows.
local _, ns = ...
local L, Style = ns.L, ns.Style

local TF = {}
ns.TradeFill = TF

TF.WIDTH, TF.SLOTS, TF.ROWS, TF.SAVED = 270, 6, 7, 4
TF.SETTLE_SECONDS = 3 -- how long after TRADE_CLOSED the bags are looked at again

local panel
local open = false
local partner
local placed = {} -- [trade slot] = unit placed this trade
local pending = {} -- units of a closed trade not yet seen gone from the bags
local sent = 0 -- stacks sent since the list was last changed by the player
local status = ""

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

local function Say(text)
	if ns.Print then
		ns.Print(text)
	end
end

local function Key(u)
	return u.bag .. ":" .. u.slot
end

local function PlacedKeys()
	local keys = {}
	for _, u in pairs(placed) do
		keys[Key(u)] = true
	end
	for _, u in ipairs(pending) do
		keys[Key(u)] = true
	end
	return keys
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

function TF.IsOpen()
	return open
end

function TF.Partner()
	return partner
end

-- Slots of the player's side that hold nothing, counting what this module has just placed (the client
-- answers a drop a moment later).
function TF.EmptySlots()
	local out = {}
	for i = 1, TF.SLOTS do
		local name = GetTradePlayerItemInfo and GetTradePlayerItemInfo(i)
		if not name and not placed[i] then
			out[#out + 1] = i
		end
	end
	return out
end

-- { sent, inTrade, left, total }: the progress of the list.
function TF.Progress()
	local units = ns.SendList.Plan(ns.SendList.Work(), PlacedKeys())
	local inTrade = Count(placed)
	return { sent = sent, inTrade = inTrade, left = #units, total = sent + inTrade + #units }
end

function TF.ProgressText()
	local p = TF.Progress()
	if p.total == 0 then
		return ""
	end
	return (L["sent %d of %d stacks"]):format(p.sent, p.total)
end

-- Puts one planned stack into a trade slot. Returns true, or false and why.
local function PlaceOne(unit, slot)
	if unit.take < unit.count then
		C_Container.SplitContainerItem(unit.bag, unit.slot, unit.take)
	else
		C_Container.PickupContainerItem(unit.bag, unit.slot)
	end
	if not GetCursorInfo() then
		return false, L["the client did not pick the stack up"]
	end
	ClickTradeButton(slot)
	if GetCursorInfo() then
		ClearCursor()
		return false, L["the trade window did not take it: one slot per click"]
	end
	placed[slot] = unit
	return true
end

-- The click: places the next stacks of the list into the empty slots. Returns how many were placed, and
-- the line saying why it stopped when it did not fill every slot it could.
function TF.Fill()
	if not open then
		return 0, L["Open a trade first"]
	end
	if GetCursorInfo() then
		return 0, L["Put down what is on the cursor first"]
	end
	local slots = TF.EmptySlots()
	if #slots == 0 then
		return 0, L["The trade window is full"]
	end
	local units, short, bound = ns.SendList.Plan(ns.SendList.Work(), PlacedKeys())
	if #units == 0 then
		local why = L["Nothing left to send"]
		if bound > 0 then
			why = (L["Nothing left to send (%d bound stacks can't be traded)"]):format(bound)
		end
		return 0, why
	end
	local n, why = 0, nil
	for i, slot in ipairs(slots) do
		local unit = units[i]
		if not unit then
			break
		end
		local ok, reason = PlaceOne(unit, slot)
		if not ok then
			why = reason
			break
		end
		n = n + 1
	end
	if not why and #short > 0 then
		why = (L["%d items have less in the bags than listed"]):format(#short)
	end
	return n, why
end

-- A closed trade: placed stacks that are gone from the bags (or smaller) went out.
local function Settle()
	local left = {}
	for _, u in ipairs(pending) do
		local info = C_Container.GetContainerItemInfo(u.bag, u.slot)
		local gone = not info or info.itemID ~= u.itemID or (info.stackCount or 1) < u.count
		if gone then
			sent = sent + 1
			ns.SendList.Consume(u.itemID, u.take)
		else
			left[#left + 1] = u
		end
	end
	pending = left
end

function TF.Settle()
	Settle()
	TF.Update()
end

local function OnOpen()
	open = true
	placed = {}
	partner = C_SecureTransfer and C_SecureTransfer.GetTradePartner and C_SecureTransfer.GetTradePartner() or nil
	local listed = partner and ns.SendList.PartnerList(partner)
	if listed and #ns.SendList.Work() == 0 then
		ns.SendList.Load(listed)
		sent = 0
	end
	status = ""
	TF.Update()
end

local function OnClosed()
	open = false
	for _, u in pairs(placed) do
		pending[#pending + 1] = u
	end
	placed = {}
	Settle()
	if #pending > 0 and C_Timer and C_Timer.After then
		C_Timer.After(TF.SETTLE_SECONDS, function()
			Settle()
			pending = {} -- still in the bags: the trade did not go through
			TF.Update()
		end)
	end
	TF.Update()
end

-- Panel ------------------------------------------------------------------------------------------------------

local rows, savedButtons = {}, {}

local function Row(i)
	local r = rows[i]
	if r then
		return r
	end
	r = CreateFrame("Frame", nil, panel)
	r:SetSize(TF.WIDTH - 24, 20)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.text:SetWidth(TF.WIDTH - 24 - 30)
	r.text:SetJustifyH("LEFT")
	r.del = Style.ActionButton(r, "×", 24, 18)
	r.del:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.del:SetScript("OnClick", function(self)
		if self.itemID then
			ns.SendList.Remove(self.itemID)
		end
	end)
	rows[i] = r
	return r
end

-- The first item in the bags whose name contains the text (case-insensitive), or an item link / ID.
function TF.FindBagItem(text)
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == "" then
		return nil
	end
	local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
	local bag = ns.SendList.BagItems()
	if id then
		for _, itemID in ipairs(bag) do
			if itemID == id then
				return id
			end
		end
		return nil
	end
	text = text:lower()
	for _, itemID in ipairs(bag) do
		if ItemName(itemID):lower():find(text, 1, true) then
			return itemID
		end
	end
end

function TF.AddTyped()
	local itemID = TF.FindBagItem(panel.search:GetText())
	if not itemID then
		status = L["No item in your bags matches"]
	else
		local qty = tonumber(panel.qty:GetText())
		ns.SendList.Add(itemID, qty)
		panel.search:SetText("")
		status = ""
	end
	TF.Update()
end

local function DrawLists()
	local names = ns.SendList.Names()
	for i = 1, TF.SAVED do
		local b = savedButtons[i]
		local name = names[i]
		if b then
			b.listName = name
			b:SetShown(name ~= nil)
			if name then
				b:SetLabel(name)
			end
		end
	end
end

function TF.Update()
	if not (panel and open) then
		if panel then
			panel:Hide()
		end
		return
	end
	panel:Show()
	panel.partner:SetText(partner and (L["Trading with %s"]):format(partner) or L["Trading"])
	local work = ns.SendList.Work()
	for i = 1, math.max(#work, #rows) do
		local e = work[i]
		if i <= TF.ROWS then
			local r = e and Row(i) or rows[i]
			if r then
				r:SetShown(e ~= nil)
				if e then
					r.text:SetText(("%s · %s"):format(ItemName(e.itemID), e.qty and ("×" .. e.qty) or L["all stacks"]))
					r.del.itemID = e.itemID
					r:ClearAllPoints()
					r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -52 - (i - 1) * 20)
				end
			end
		end
	end
	panel.more:SetText(#work > TF.ROWS and (L["+%d more"]):format(#work - TF.ROWS) or "")
	panel.progress:SetText(TF.ProgressText())
	local p = TF.Progress()
	panel.fill:SetLabel((sent > 0 or p.inTrade > 0) and L["Fill next 6"] or L["Fill 6"])
	panel.fill:SetEnabled(#TF.EmptySlots() > 0 and p.left > 0)
	panel.status:SetText(status)
	DrawLists()
	panel.partnerList:SetShown(partner ~= nil and #work > 0)
end

local function Create()
	if panel or not TradeFrame then
		return
	end
	panel = CreateFrame("Frame", "CraftWiseTradeFill", TradeFrame)
	local height = 52 + TF.ROWS * 20 + 150
	panel:SetSize(TF.WIDTH, height)
	panel:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 4, -30)
	panel:SetFrameLevel((TradeFrame:GetFrameLevel() or 1) + 5)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.title = Style.Text(panel, "BodyBold", "text")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText(L["To send"])
	panel.partner = Style.Text(panel, "Small", "text3")
	panel.partner:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -30)
	local y = -(52 + TF.ROWS * 20)
	panel.more = Style.Text(panel, "Small", "text3")
	panel.more:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)

	panel.search = CreateFrame("EditBox", nil, panel)
	panel.search:SetSize(130, 22)
	panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 16)
	panel.search:SetAutoFocus(false)
	panel.search:SetFontObject(Style.Fonts.Small)
	panel.search:SetTextInsets(6, 6, 0, 0)
	panel.search.border = Style.Border(panel.search, Style.C.ruleStrong)
	panel.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		TF.AddTyped()
	end)
	panel.search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	panel.qty = CreateFrame("EditBox", nil, panel)
	panel.qty:SetSize(44, 22)
	panel.qty:SetPoint("LEFT", panel.search, "RIGHT", 6, 0)
	panel.qty:SetAutoFocus(false)
	panel.qty:SetNumeric(true)
	panel.qty:SetMaxLetters(5)
	panel.qty:SetFontObject(Style.Fonts.Small)
	panel.qty:SetTextInsets(6, 6, 0, 0)
	panel.qty.border = Style.Border(panel.qty, Style.C.ruleStrong)
	panel.add = Style.ActionButton(panel, L["Add"], 56, 22)
	panel.add:SetPoint("LEFT", panel.qty, "RIGHT", 6, 0)
	panel.add:SetScript("OnClick", TF.AddTyped)
	panel.hint = Style.Text(panel, "Small", "text3")
	panel.hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 42)
	panel.hint:SetText(L["Name in your bags, quantity (empty = all stacks)"])

	panel.basket = Style.ActionButton(panel, L["Basket"], 70, 22)
	panel.basket:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 60)
	panel.basket:SetScript("OnClick", function()
		ns.SendList.AddBasket()
	end)
	panel.sellAH = Style.ActionButton(panel, L["Sell on AH"], 86, 22)
	panel.sellAH:SetPoint("LEFT", panel.basket, "RIGHT", 6, 0)
	panel.sellAH:SetScript("OnClick", function()
		ns.SendList.AddSellAH()
	end)
	panel.clear = Style.ActionButton(panel, L["Clear"], 56, 22)
	panel.clear:SetPoint("LEFT", panel.sellAH, "RIGHT", 6, 0)
	panel.clear:SetScript("OnClick", function()
		ns.SendList.Clear()
	end)

	panel.listName = CreateFrame("EditBox", nil, panel)
	panel.listName:SetSize(130, 22)
	panel.listName:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 88)
	panel.listName:SetAutoFocus(false)
	panel.listName:SetFontObject(Style.Fonts.Small)
	panel.listName:SetTextInsets(6, 6, 0, 0)
	panel.listName.border = Style.Border(panel.listName, Style.C.ruleStrong)
	panel.listName:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	panel.save = Style.ActionButton(panel, L["Save list"], 76, 22)
	panel.save:SetPoint("LEFT", panel.listName, "RIGHT", 6, 0)
	panel.save:SetScript("OnClick", function()
		local name = ns.SendList.Save(panel.listName:GetText())
		status = name and (L["Saved as %s"]):format(name) or L["Type a name for the list"]
		TF.Update()
	end)
	for i = 1, TF.SAVED do
		local b = Style.ActionButton(panel, "", 60, 20)
		b:SetPoint("TOPLEFT", panel, "TOPLEFT", 12 + (i - 1) * 64, y - 114)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, mouse)
			if not self.listName then
				return
			end
			if mouse == "RightButton" then
				ns.SendList.Delete(self.listName)
			else
				ns.SendList.Load(self.listName)
			end
		end)
		savedButtons[i] = b
	end
	panel.partnerList = Style.ActionButton(panel, L["Use for this partner"], 130, 20)
	panel.partnerList:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 138)
	panel.partnerList:SetScript("OnClick", function()
		local name = panel.listName:GetText()
		name = ns.SendList.Get(name) and name or ns.SendList.Names()[1]
		if partner and name and ns.SendList.SetPartner(partner, name) then
			status = (L["%s loads when %s trades with you"]):format(name, partner)
		else
			status = L["Save the list first"]
		end
		TF.Update()
	end)

	panel.progress = Style.Text(panel, "Small", "text2")
	panel.progress:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 164)
	panel.fill = Style.PrimaryButton(panel, L["Fill 6"], 110, 26)
	panel.fill:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y - 160)
	panel.fill:SetScript("OnClick", function()
		local n, why = TF.Fill()
		status = n > 0 and (L["Placed %d. Press Trade when you are ready."]):format(n) or (why or "")
		if n > 0 and why then
			status = status .. " " .. why
		end
		TF.Update()
	end)
	panel.status = Style.Text(panel, "Small", "text2")
	panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 188)
	panel.status:SetWidth(TF.WIDTH - 24)
	panel.status:SetJustifyH("LEFT")
	panel:SetHeight(-y + 210)
	panel:Hide()
	TF.panel = panel
end

ns.On("TRADE_SHOW", function()
	Create()
	OnOpen()
end)
ns.On("TRADE_CLOSED", OnClosed)
ns.On("TRADE_PLAYER_ITEM_CHANGED", function()
	TF.Update()
end)
ns.On("TRADE_UPDATE", function()
	TF.Update()
end)
ns.Listen("BAGS_CHANGED", function()
	if #pending > 0 then
		Settle()
	end
	TF.Update()
end)
ns.Listen("SEND_LIST_CHANGED", function(kind)
	if kind ~= "sent" then
		sent = 0
	end
	TF.Update()
end)
