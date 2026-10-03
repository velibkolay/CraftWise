-- Junk icon on items you marked as junk, in the game's bags and in Bagnon (issue #12).
-- Uses the bag button's own JunkIcon (the coin Blizzard shows on grey items in the merchant view).
local _, ns = ...

local function IsJunk(itemID)
	return itemID and ns.db and ns.db.junk and ns.db.junk[itemID] or false
end

-- Blizzard bags: every item button of the combined bag and the single bag frames.
local refresh = false
local function UpdateButton(button)
	if not (button and button.JunkIcon and button.GetBagID) then
		return
	end
	local ok, bag = pcall(button.GetBagID, button)
	local slot = button:GetID()
	if not ok or not bag or not slot then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if IsJunk(info and info.itemID) then
		button.JunkIcon:Show()
	elseif refresh then
		-- Unmarked: back to Blizzard's own rule (grey items while a merchant is open).
		local poor = info and info.quality == 0 and not info.hasNoValue
		button.JunkIcon:SetShown(poor and MerchantFrame and MerchantFrame:IsShown() or false)
	end
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
			hooksecurefunc(frame, "Update", UpdateContainer)
		end
	end)
end

-- Bagnon: its item class decides the junk icon in UpdateBorder; show ours after it.
local function HookBagnon()
	local Bagnon = _G.Bagnon or _G.Bagnonium
	if not (Bagnon and Bagnon.Item and Bagnon.Item.UpdateBorder) then
		return nil
	end
	hooksecurefunc(Bagnon.Item, "UpdateBorder", function(item)
		if item.JunkIcon and not (item.IsCached and item:IsCached()) and IsJunk(item.info and item.info.itemID) then
			item.JunkIcon:Show()
		end
	end)
	return Bagnon
end

local bagnon
ns.On("PLAYER_LOGIN", function()
	HookBlizzard()
	bagnon = HookBagnon()
end)

-- Marking or unmarking redraws the icons. Blizzard's frames are not re-run from here (that could
-- taint the bag buttons); only the icon textures are set.
ns.Listen("JUNK_CHANGED", function()
	if bagnon and bagnon.Frames and bagnon.Frames.Update then
		pcall(bagnon.Frames.Update, bagnon.Frames)
	end
	refresh = true
	ContainerFrames(UpdateContainer)
	refresh = false
end)
