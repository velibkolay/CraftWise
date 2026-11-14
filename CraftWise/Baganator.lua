-- Baganator integration (optional; does nothing without Baganator). Uses Baganator's public API:
--  * junk plugin "CraftWise": Baganator shows its junk coin on items you marked as junk
--    (pick "CraftWise" under Baganator's junk settings if another plugin is selected)
--  * corner widget "CraftWise: marks": the folded corner of BagIcons.lua on the slot's top right
--    (gold: sell on AH; grey: junk, and the slot's icon dimmed). Baganator settings > Icons: place
--    it in a corner if it isn't shown
--  * sort mode "CraftWise": Baganator's sort button sorts the backpack the CraftWise way
local _, ns = ...

local registered = false

local function Register()
	local api = _G.Baganator and _G.Baganator.API
	if registered or not api then
		return
	end
	registered = true
	if api.RegisterJunkPlugin then
		pcall(api.RegisterJunkPlugin, "CraftWise", "craftwise", function(_, _, itemID)
			return itemID and ns.db and ns.db.junk and ns.db.junk[itemID] or false
		end)
	end
	if api.RegisterCornerWidget then
		pcall(api.RegisterCornerWidget, "CraftWise: marks", "craftwise_marks", ns.Timed("Baganator: corner widget", function(corner, details)
			local mark = details and ns.SlotMark(details.itemID)
			local parent = corner.GetParent and corner:GetParent()
			ns.SetSlotDim(parent, mark == "junk")
			if not mark then
				return false
			end
			local c = ns.Style.Color(mark == "junk" and "text3" or "coinGold")
			corner:SetVertexColor(c[1], c[2], c[3], 1)
			return true
		end), function(itemButton)
			local t = itemButton:CreateTexture(nil, "OVERLAY")
			t:SetTexture(ns.Style.Media.fold)
			t:SetSize(ns.SLOT_CORNER, ns.SLOT_CORNER)
			return t
		end, { corner = "top_right", priority = 1 }, true)
	end
	if api.RegisterContainerSort and api.Constants and api.Constants.ContainerType then
		local backpack = api.Constants.ContainerType.Backpack
		pcall(api.RegisterContainerSort, "CraftWise", "craftwise", function(_, containerType)
			if containerType == backpack and ns.BagSort then
				ns.BagSort.Start()
			end
		end)
	end
end

ns.On("PLAYER_LOGIN", Register)

ns.Listen("JUNK_CHANGED", function()
	local api = _G.Baganator and _G.Baganator.API
	if api and api.RequestItemButtonsRefresh then
		pcall(api.RequestItemButtonsRefresh)
	end
end)
