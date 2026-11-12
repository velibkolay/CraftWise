-- Item menu (issue #12; Origami look #159): Keep / Junk / Sell on AH / Normal for one item, then Where to
-- buy and Price history. Opened from a row of the main window (right or middle click), or on an item
-- in the game's bags (Blizzard, Bagnon, Baganator) with the click chosen in the settings: middle click
-- (default) or Alt + right-click.
-- Middle click: Blizzard's bag buttons only listen to left and right clicks, and neither Bagnon nor
-- Baganator uses it, so nothing else happens. Alt + click is "highlight similar items" in Baganator.
-- Look (spec "Item menu"): a folded sheet 200 wide, cut 10, hard shadow, padding 8 vertical; title = item
-- name (FontBodyBold); rows 24; the current mark has the nokta and C.selected behind it; a rule. Quest items
-- show "Quest items can't be sold" in place of Junk and Sell on AH. Opens at the cursor, closes on Escape,
-- a click elsewhere or after a choice.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local L = ns.L

local menu
local WIDTH, ROW, PAD_Y, PAD_X, TITLE = 200, 24, 8, 12, 20
local NOKTA_X = PAD_X + 4 -- centre of the 8 unit nokta slot
local LABEL_X = PAD_X + 8 + 8
local RULE_GAP = 6

-- "rule" is the hairline; "quest" the line shown in place of Junk and Sell on AH for quest items.
-- "recipes" is not on the spec's menu: kept until Look up › Items gives "Used in" a way to the recipes
-- (the menu is its only UI home today; question on #159).
local OPTIONS = {
	{ key = "keep", label = "Keep", note = "Left out of the advice and selling" },
	{ key = "junk", label = "Junk", note = "Sold with \"Sell junk\" at a vendor", sells = true },
	{ key = "auction", label = "Sell on AH", note = "Always advised for the auction house, grouped first in the selling part of a bag sort", sells = true },
	{ key = "quest", label = "Quest items can't be sold", quest = true },
	{ key = "normal", label = "Normal", note = "CraftWise advises vendor or AH" },
	{ key = "rule" },
	{ key = "where", label = "Where to buy", note = "Merchants you opened that sell it" },
	{ key = "history", label = "Price history", note = "Auction house prices recorded for it" },
	-- Watch list (#165): the label flips once the item is watched; same toggle as the Items card.
	{ key = "watch", label = "Watch", undo = "Stop watching", watch = true,
		note = "Adds it to Look up › Items › Watched" },
	-- Gear only (#157, spec "Upgrades": dismiss from the item menu); the label flips once dismissed.
	{ key = "dismiss", label = "Don't suggest as upgrade", undo = "Suggest as upgrade again", gear = true,
		note = "Look up › Upgrades leaves it out (Settings › Bags and loot › Show dismissed upgrades lists it again)" },
	{ key = "recipes", label = "Recipes using this", note = "Opens Make › Craft with every recipe of yours that uses it" },
}
ns.ItemMenuOptions = OPTIONS
local MARKS = { keep = true, junk = true, auction = true, normal = true }

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

-- Where to buy and Price history open Look up › Items on the item (ns.ShowItemLookup, UI/Main/Pages/Items.lua,
-- which loads later; called on a click, so it exists by then).
function ns.OpenItemLookup(itemID, focus)
	return ns.ShowItemLookup and ns.ShowItemLookup(itemID, focus) or false
end

-- Gear an upgrade can be suggested for (Upgrades.lua's slots), or one already dismissed.
local function IsGear(itemID)
	if ns.db and ns.db.dismissed and ns.db.dismissed[itemID] then
		return true
	end
	local equipLoc = C_Item and C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(itemID))
	return equipLoc ~= nil and ns.EQUIP_SLOTS ~= nil and ns.EQUIP_SLOTS[equipLoc] ~= nil
end

-- Rows shown for an item, top to bottom: quest items swap Junk and Sell on AH for the quest line; the
-- upgrade line only shows for gear.
function ns.ItemMenuRows(quest, gear)
	local keys = {}
	for _, opt in ipairs(OPTIONS) do
		if not (quest and opt.sells) and not (opt.quest and not quest) and not (opt.gear and not gear) then
			keys[#keys + 1] = opt.key
		end
	end
	return keys
end

local function Paint(b)
	b.bg:SetShown((b.current or b.hover) and true or false)
	local bold = b.current
	b.label:SetFontObject(bold and Style.Fonts.BodyBold or Style.Fonts.Body)
	local c = b.opt.quest and C.text3 or C.text
	b.label:SetTextColor(c[1], c[2], c[3], 1)
end

local function Choose(opt)
	local itemID = menu.itemID
	if itemID then
		if opt.key == "recipes" then
			ns.ShowRecipesUsing(itemID)
		elseif opt.key == "where" or opt.key == "history" then
			ns.OpenItemLookup(itemID, opt.key)
		elseif opt.key == "watch" and ns.ItemWatch then
			ns.ItemWatch.Toggle(itemID)
		elseif opt.key == "dismiss" and ns.ToggleDismissed then
			ns.ToggleDismissed(itemID)
		elseif MARKS[opt.key] and not (menu.quest and (opt.key == "junk" or opt.key == "auction")) then
			ns.SetItemState(itemID, opt.key)
		end
	end
	menu:Hide()
end

local function Build()
	menu = CreateFrame("Frame", "CraftWiseItemMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetWidth(WIDTH)
	menu:EnableMouse(true)
	menu:SetClampedToScreen(true)
	menu.sheet = Style.Sheet(menu, C.sheet, C.flap, 10, true)
	table.insert(UISpecialFrames, "CraftWiseItemMenu")
	menu.title = Style.Text(menu, "BodyBold", "text")
	menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD_X, -(PAD_Y + 2))
	menu.title:SetPoint("RIGHT", menu, "RIGHT", -PAD_X - 10, 0)
	menu.title:SetJustifyH("LEFT")
	menu.title:SetWordWrap(false)
	menu.nokta = Style.Nokta(menu)
	menu.nokta:Hide()
	menu.buttons = {}
	for _, opt in ipairs(OPTIONS) do
		if opt.key == "rule" then
			menu.rule = Style.Rule(menu, "H", C.rule)
		else
			local b = CreateFrame("Button", nil, menu)
			b.opt = opt
			b:SetHeight(ROW)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints(b)
			Style.Fill(b.bg, C.selected)
			b.label = Style.Text(b, "Body", "text")
			b.label:SetPoint("LEFT", b, "LEFT", LABEL_X, 0)
			b.label:SetText(L[opt.label])
			if opt.quest then
				b:EnableMouse(false)
			else
				b:SetScript("OnClick", function()
					Choose(opt)
				end)
				b:SetScript("OnEnter", function(self)
					self.hover = true
					Paint(self)
					Style.ShowTip(self, self.label:GetText() or L[opt.label], L[opt.note])
				end)
				b:SetScript("OnLeave", function(self)
					self.hover = false
					Paint(self)
					Style.HideTip(self)
				end)
			end
			menu.buttons[opt.key] = b
		end
	end
	menu:SetScript("OnHide", function()
		Style.HideTip()
	end)
	menu:Hide()
end

-- Places the rows for this item and sizes the sheet; returns the height.
local function Layout(quest, gear)
	local shown = {}
	for _, key in ipairs(ns.ItemMenuRows(quest, gear)) do
		shown[key] = true
	end
	local y = -(PAD_Y + TITLE)
	for _, opt in ipairs(OPTIONS) do
		if opt.key == "rule" then
			y = y - RULE_GAP
			menu.rule:ClearAllPoints()
			menu.rule:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
			menu.rule:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, y)
			y = y - 1 - RULE_GAP
		else
			local b = menu.buttons[opt.key]
			if shown[opt.key] then
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
				b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, y)
				b:Show()
				y = y - ROW
			else
				b:Hide()
			end
		end
	end
	local height = -y + PAD_Y
	menu:SetHeight(height)
	return height
end

-- Opens the menu for an item at the cursor. `anchor` is accepted for old callers and ignored: the spec
-- opens the menu at the cursor wherever it was asked for.
function ns.ShowItemMenu(itemID, anchor) -- luacheck: ignore anchor
	if not (itemID and ns.db) then
		return
	end
	if not menu then
		Build()
	end
	menu.itemID = itemID
	menu.quest = IsQuestItem(itemID) and true or false
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
	menu.title:SetText(name)
	Layout(menu.quest, IsGear(itemID))
	local dismissed = ns.db.dismissed and ns.db.dismissed[itemID]
	local dismiss = menu.buttons.dismiss
	dismiss.label:SetText(L[dismissed and dismiss.opt.undo or dismiss.opt.label])
	local watch = menu.buttons.watch
	watch.label:SetText(L[ns.ItemWatch and ns.ItemWatch.IsWatched(itemID) and watch.opt.undo or watch.opt.label])
	local state = menu.quest and "keep" or State(itemID)
	local usedByMe = false
	for _, e in ipairs(ns.UsedIn(itemID)) do
		usedByMe = usedByMe or e.professionID ~= nil
	end
	menu.state = state
	for key, b in pairs(menu.buttons) do
		b.current = key == state
		b.hover = false
		Paint(b)
		if key == "recipes" then
			b:SetAlpha(usedByMe and 1 or 0.4)
		end
		if b.current then
			menu.nokta:MoveTo(b, "LEFT", NOKTA_X, 0, true)
		end
	end
	menu:ClearAllPoints()
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale() or 1
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 8, y / scale + 8)
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
