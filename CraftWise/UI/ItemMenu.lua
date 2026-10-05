-- Item menu (issue #12): Keep / Junk / Sell on AH / Normal for one item, opened by clicking a row in the Bags
-- view, or on an item in the game's bags (Blizzard, Bagnon, Baganator) with the click chosen in
-- the settings: middle click (default) or Alt + right-click.
-- Middle click: Blizzard's bag buttons only listen to left and right clicks, and neither Bagnon nor
-- Baganator uses it, so nothing else happens. Alt + click is "highlight similar items" in Baganator.
local _, ns = ...
local Style = ns.Style
local L = ns.L

local menu
local OPTIONS = {
	{ key = "keep", label = "Keep", note = "Left out of the advice and selling" },
	{ key = "junk", label = "Junk", note = "Sold with \"Sell junk\" at a vendor" },
	{ key = "auction", label = "Sell on AH", note = "Always advised for the auction house, grouped first in the selling part of a bag sort" },
	{ key = "normal", label = "Normal", note = "CraftWise advises vendor or AH" },
	{ key = "recipes", label = "Recipes using this", note = "Opens the Profit view with every recipe of yours that uses it" },
}

local function State(itemID)
	if ns.db.junk and ns.db.junk[itemID] then
		return "junk"
	elseif ns.db.sellAH and ns.db.sellAH[itemID] then
		return "auction"
	elseif ns.db.keep[itemID] then
		return "keep"
	end
	return "normal"
end

function ns.SetItemState(itemID, state)
	ns.db.junk = ns.db.junk or {}
	ns.db.sellAH = ns.db.sellAH or {}
	ns.db.keep[itemID] = state == "keep" or nil
	ns.db.junk[itemID] = state == "junk" or nil
	ns.db.sellAH[itemID] = state == "auction" or nil
	ns.Notify("BAGS_CHANGED")
	ns.Notify("JUNK_CHANGED")
end

local function IsQuestItem(itemID)
	return C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID)) == 12
end

local function Build()
	menu = CreateFrame("Frame", "CraftWiseItemMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetSize(210, 30 + #OPTIONS * 28)
	menu:EnableMouse(true)
	menu:SetClampedToScreen(true)
	Style.Panel(menu)
	table.insert(UISpecialFrames, "CraftWiseItemMenu")
	menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	menu.title:SetPoint("TOPLEFT", 10, -8)
	menu.title:SetPoint("RIGHT", -10, 0)
	menu.title:SetJustifyH("LEFT")
	menu.title:SetWordWrap(false)
	menu.buttons = {}
	for i, opt in ipairs(OPTIONS) do
		local b = Style.Button(menu, 190, 24, L[opt.label])
		b:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 28)
		b:SetScript("OnClick", function()
			if opt.key == "recipes" then
				if menu.itemID then
					ns.ShowRecipesUsing(menu.itemID)
				end
			elseif menu.itemID and not (menu.quest and (opt.key == "junk" or opt.key == "auction")) then
				ns.SetItemState(menu.itemID, opt.key)
			end
			menu:Hide()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(L[opt.label])
			GameTooltip:AddLine(menu.quest and (opt.key == "junk" or opt.key == "auction") and L["Quest items can't be sold"] or L[opt.note],
				0.8, 0.8, 0.8, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self)
			GameTooltip:Hide()
			self:SetSelected(self.current)
		end)
		menu.buttons[opt.key] = b
	end
	menu:Hide()
end

-- Opens the menu for an item next to the cursor (or an anchor frame).
function ns.ShowItemMenu(itemID, anchor)
	if not (itemID and ns.db) then
		return
	end
	if not menu then
		Build()
	end
	menu.itemID = itemID
	menu.quest = IsQuestItem(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	menu.title:SetText(name)
	local state = menu.quest and "keep" or State(itemID)
	local usedByMe = false
	for _, e in ipairs(ns.UsedIn(itemID)) do
		usedByMe = usedByMe or e.professionID ~= nil
	end
	for key, b in pairs(menu.buttons) do
		b.current = key == state
		b:SetSelected(b.current)
		if key == "recipes" then
			b:SetAlpha(usedByMe and 1 or 0.4)
		else
			b:SetAlpha(menu.quest and key ~= "keep" and 0.4 or 1)
		end
	end
	menu:ClearAllPoints()
	if anchor then
		menu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
	else
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale() or 1
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 8, y / scale + 8)
	end
	menu:Show()
end

function ns.HideItemMenu()
	if menu then
		menu:Hide()
	end
end

-- Bag and slot of a bag item button: Blizzard's (GetBagID) or Bagnon's (.bag).
local function BagSlot(frame)
	for _ = 1, 3 do
		if not frame then
			return nil
		end
		local id = frame.GetID and frame:GetID()
		if frame.GetBagID and id then
			local ok, bag = pcall(frame.GetBagID, frame)
			if ok and bag then
				return bag, id
			end
		end
		if type(frame.bag) == "number" and id then
			return frame.bag, id
		end
		frame = frame.GetParent and frame:GetParent()
	end
end

-- The chosen click on an item in the bags opens the menu; a click elsewhere closes it.
local function MenuClick(button)
	local mode = ns.db and ns.db.settings.menuClick or "middle"
	if mode == "middle" then
		return button == "MiddleButton"
	elseif mode == "altright" then
		return button == "RightButton" and IsAltKeyDown()
	end
	return false
end

ns.On("GLOBAL_MOUSE_DOWN", function(_, button)
	if menu and menu:IsShown() and not menu:IsMouseOver() then
		menu:Hide()
	end
	if not MenuClick(button) or not GetMouseFoci then
		return
	end
	local focus = GetMouseFoci()
	local bag, slot = BagSlot(focus and focus[1])
	if not bag or bag < 0 or bag > ns.LAST_BAG then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if info and info.itemID then
		ns.ShowItemMenu(info.itemID)
	end
end)
