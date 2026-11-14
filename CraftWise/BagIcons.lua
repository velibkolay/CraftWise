-- Marks on bag slots (issues #12, #160): a folded corner on the slot's top right, 13 units.
-- Sell on AH: C.coinGold corner. Junk: C.text3 corner and the slot's icon desaturated and dimmed to 55 %.
-- Keep has no mark (it is the default). Works on the game's bags, Bagnon and Baganator (Baganator.lua
-- calls ns.ApplySlotMark too). Only marks are added; the client's slot art is left alone.
local _, ns = ...

ns.SLOT_CORNER = 13
ns.JUNK_DIM = 0.55

local function IsAH(itemID)
	return itemID and ns.db and ns.db.sellAH and ns.db.sellAH[itemID] or false
end

local function IsJunk(itemID)
	return itemID and ns.db and ns.db.junk and ns.db.junk[itemID] or false
end

-- Settings › Bags and loot › Bag slot marks (#157): on unless switched off.
function ns.SlotMarksOn()
	return not (ns.db and ns.db.settings and ns.db.settings.slotMarks == false)
end

-- "ah", "junk" or nil for an item (nil for every item while the marks are off).
function ns.SlotMark(itemID)
	if not ns.SlotMarksOn() then
		return nil
	end
	if IsJunk(itemID) then
		return "junk"
	elseif IsAH(itemID) then
		return "ah"
	end
end

local MARK_COLOR = { ah = "coinGold", junk = "text3" }

local corners = setmetatable({}, { __mode = "k" }) -- [button] = corner texture
ns.SlotCorners = corners
local dimmed = setmetatable({}, { __mode = "k" }) -- [button] = true while we hold its icon dimmed
ns.SlotDimmed = dimmed

local function Corner(button)
	local t = corners[button]
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(ns.Style.Media.fold)
		t:SetSize(ns.SLOT_CORNER, ns.SLOT_CORNER)
		t:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		corners[button] = t
	end
	return t
end

local function IconOf(button)
	local icon = button.icon or button.Icon
	if type(icon) == "table" and icon.SetDesaturated then
		return icon
	end
end

-- Junk: the slot's icon desaturated and dimmed to 55 %; back to normal when the mark goes.
function ns.SetSlotDim(button, dim)
	local icon = button and IconOf(button)
	if not icon then
		return
	end
	if dim then
		icon:SetDesaturated(true)
		icon:SetAlpha(ns.JUNK_DIM)
		dimmed[button] = true
	elseif dimmed[button] then
		icon:SetDesaturated(false)
		icon:SetAlpha(1)
		dimmed[button] = nil
	end
end

-- Mark a slot for `mark` ("ah", "junk" or nil), or clear it.
function ns.SetSlotMark(button, mark)
	if not button then
		return
	end
	local t = corners[button]
	if mark then
		t = Corner(button)
		local c = ns.Style.Color(MARK_COLOR[mark])
		t:SetVertexColor(c[1], c[2], c[3], 1)
		t:Show()
	elseif t then
		t:Hide()
	end
	ns.SetSlotDim(button, mark == "junk")
end

function ns.ApplySlotMark(button, itemID)
	ns.SetSlotMark(button, ns.SlotMark(itemID))
end

-- Blizzard bags: every item button of the combined bag and the single bag frames.
local function UpdateButton(button)
	if not (button and button.GetBagID) then
		return
	end
	local ok, bag = pcall(button.GetBagID, button)
	local slot = button:GetID()
	if not ok or not bag or not slot then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	ns.ApplySlotMark(button, info and info.itemID)
end

local function UpdateContainer(frame)
	if frame and frame.Items then
		for _, button in ipairs(frame.Items) do
			UpdateButton(button)
		end
	end
end

local function ContainerFrames(fn)
	fn(ContainerFrameCombinedBags)
	for i = 1, 13 do
		fn(_G["ContainerFrame" .. i])
	end
end

local function HookBlizzard()
	ContainerFrames(function(frame)
		if frame and frame.Update then
			hooksecurefunc(frame, "Update", ns.Timed("BagIcons: bag frame Update", UpdateContainer))
		end
	end)
end

-- Bagnon: marks are drawn after its UpdateBorder.
local function HookBagnon()
	local Bagnon = _G.Bagnon or _G.Bagnonium
	if not (Bagnon and Bagnon.Item and Bagnon.Item.UpdateBorder) then
		return nil
	end
	hooksecurefunc(Bagnon.Item, "UpdateBorder", ns.Timed("BagIcons: Bagnon UpdateBorder", function(item)
		local cached = item.IsCached and item:IsCached()
		ns.ApplySlotMark(item, not cached and item.info and item.info.itemID or nil)
	end))
	return Bagnon
end

local bagnon
ns.On("PLAYER_LOGIN", function()
	HookBlizzard()
	bagnon = HookBagnon()
end)

-- Marking or unmarking redraws the marks. Blizzard's frames are not re-run from here (that could
-- taint the bag buttons); only our corner and the icon's tint are set.
ns.Listen("JUNK_CHANGED", function()
	if bagnon and bagnon.Frames and bagnon.Frames.Update then
		pcall(bagnon.Frames.Update, bagnon.Frames)
	end
	ContainerFrames(UpdateContainer)
end)
