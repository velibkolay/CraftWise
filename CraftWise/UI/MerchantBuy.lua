-- Merchant window: buy a typed quantity, and the basket's vendor lines (#201).
--   * A small panel next to MerchantFrame. Alt+click a merchant item to pick it (the panel follows the last
--     item Alt-clicked: no click on the item button changes what Blizzard does), type a quantity, read the
--     total, press Buy. Gold, stock and bag room are checked first; if one fails the panel says why and
--     nothing is bought.
--   * Below it, the basket's vendor lines (Basket.Plan) that this merchant sells, each with its Buy button.
--   * Both buttons call Basket.Purchase, the same stack-sized purchase the Basket page uses. Every purchase
--     starts from the player's click; nothing buys on open, on a timer or on its own.
local _, ns = ...
local L, Style = ns.L, ns.Style

local MB = {}
ns.MerchantBuy = MB

MB.WIDTH = 252
MB.MAX_LINES = 8
MB.ITEM_BUTTONS = 12 -- MerchantItem1ItemButton ... MerchantItem12ItemButton

local panel
local picked -- itemID the typed quantity is for
local rows = {} -- the basket line rows
local hooked = {}

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

local function Money(copper)
	return ns.FormatMoney(copper, true)
end

-- Typed quantity of the picked item: { itemID, quantity } or nil.
function MB.Typed()
	local q = panel and ns.Basket.ParseQuantity(panel.box:GetText())
	if picked and q then
		return { itemID = picked, quantity = q }
	end
end

-- What the panel says about the typed purchase: returns canBuy, text (the total, or why not).
function MB.Describe(line)
	if not picked then
		return false, L["Alt+click an item to pick it."]
	end
	if not line then
		return false, L["Type a quantity."]
	end
	local ok, why, _, quantity, total = ns.Basket.Check(line, true)
	if ok then
		return true, (L["%d for %s"]):format(quantity, Money(total))
	end
	return false, why
end

function MB.Pick(itemID)
	picked = itemID
	MB.Update()
end

function MB.Buy()
	local line = MB.Typed()
	if not line then
		return nil
	end
	local bought, why = ns.Basket.Purchase(line, true)
	if bought then
		ns.Print((L["Bought %d × %s."]):format(bought, ItemName(line.itemID)))
	end
	if why then
		ns.Print(why .. ".")
	end
	MB.Update()
	return bought, why
end

-- Basket vendor lines this merchant sells: { { itemID, quantity } }, at most MAX_LINES.
function MB.BasketLines()
	if #ns.Basket.Entries() == 0 then
		return {}
	end
	local out = {}
	for _, l in ipairs(ns.Basket.Plan().split.vendor) do
		if ns.Basket.MerchantSlot(l.itemID) then
			out[#out + 1] = l
			if #out == MB.MAX_LINES then
				break
			end
		end
	end
	return out
end

local function Row(i)
	local r = rows[i]
	if r then
		return r
	end
	r = CreateFrame("Frame", nil, panel)
	r:SetSize(MB.WIDTH - 24, 24)
	r.text = Style.Text(r, "Small", "text")
	r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.text:SetWidth(MB.WIDTH - 24 - 70)
	r.text:SetJustifyH("LEFT")
	r.buy = Style.ActionButton(r, L["Buy"], 60, 22)
	r.buy:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.buy:SetScript("OnClick", function(self)
		local line = self:GetParent().line
		if not line then
			return
		end
		local bought, why = ns.Basket.Buy(line)
		if bought then
			ns.Print((L["Bought %d × %s."]):format(bought, ItemName(line.itemID)))
		end
		if why then
			ns.Print(why .. ".")
		end
		MB.Update()
	end)
	rows[i] = r
	return r
end

-- The basket line rows created so far (for the specs).
function MB.Rows()
	return rows
end

function MB.Update()
	if not (panel and ns.Basket.MerchantOpen()) then
		return
	end
	local line = MB.Typed()
	local ok, text = MB.Describe(line)
	panel.item:SetText(picked and ItemName(picked) or L["Buy a quantity"])
	panel.status:SetText(text)
	panel.buy:SetEnabled(ok)
	local y = -118
	local lines = MB.BasketLines()
	panel.basketTitle:SetShown(#lines > 0)
	for i = 1, math.max(#lines, #rows) do
		local l = lines[i]
		local r = l and Row(i) or rows[i]
		if r then
			r.line = l
			r:SetShown(l ~= nil)
			if l then
				local can, why = ns.Basket.CanBuy(l)
				r.text:SetText((L["%d × %s"]):format(l.quantity, ItemName(l.itemID)))
				r.buy:SetEnabled(can)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y - 20)
				y = y - 26
			end
		end
	end
	panel:SetHeight(-y + (#lines > 0 and 30 or 12))
end

local function Create()
	if panel or not MerchantFrame then
		return
	end
	panel = CreateFrame("Frame", "CraftWiseMerchantBuy", MerchantFrame)
	panel:SetSize(MB.WIDTH, 130)
	panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, -30)
	panel:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 5)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.title = Style.Text(panel, "Small", "text3")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText("CraftWise")
	panel.item = Style.Text(panel, "Body", "text")
	panel.item:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -28)
	panel.item:SetWidth(MB.WIDTH - 24)
	panel.item:SetJustifyH("LEFT")
	panel.box = CreateFrame("EditBox", nil, panel)
	panel.box:SetSize(80, 24)
	panel.box:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -52)
	panel.box:SetAutoFocus(false)
	panel.box:SetNumeric(true)
	panel.box:SetMaxLetters(4)
	panel.box:SetFontObject(Style.Fonts.Small)
	panel.box:SetTextInsets(8, 8, 0, 0)
	panel.box.border = Style.Border(panel.box, Style.C.ruleStrong)
	panel.box:SetScript("OnTextChanged", MB.Update)
	panel.box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	panel.box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	panel.buy = Style.ActionButton(panel, L["Buy"], 70, 24)
	panel.buy:SetPoint("LEFT", panel.box, "RIGHT", 8, 0)
	panel.buy:SetScript("OnClick", MB.Buy)
	panel.status = Style.Text(panel, "Small", "text2")
	panel.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -82)
	panel.status:SetWidth(MB.WIDTH - 24)
	panel.status:SetJustifyH("LEFT")
	panel.basketTitle = Style.Text(panel, "Small", "text3")
	panel.basketTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -118)
	panel.basketTitle:SetText(L["Basket: sold here"])
	MB.panel = panel
end

-- Alt+click on a merchant item button picks it. The button's ID is the merchant slot of the current page.
local function HookButtons()
	for i = 1, MB.ITEM_BUTTONS do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		if button and not hooked[button] then
			hooked[button] = true
			button:HookScript("OnClick", ns.Timed("MerchantBuy: item click", function(self)
				if IsAltKeyDown() and ns.Basket.MerchantOpen() then
					local id = GetMerchantItemID(self:GetID())
					if id then
						MB.Pick(id)
					end
				end
			end))
		end
	end
end

ns.On("MERCHANT_SHOW", function()
	Create()
	HookButtons()
	if panel then
		picked = nil
		panel.box:SetText("")
		MB.Update()
	end
end)
-- BASKET_CHANGED also fires on open and close; BAGS_CHANGED when a purchase lands (money, room, lines).
ns.Listen("BASKET_CHANGED", MB.Update)
ns.Listen("BAGS_CHANGED", MB.Update)
