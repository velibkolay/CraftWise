-- Baganator integration (optional; does nothing without Baganator). Uses Baganator's public API:
--  * junk plugin "CraftWise": Baganator shows its junk coin on items you marked as junk
--    (pick "CraftWise" under Baganator's junk settings if another plugin is selected)
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
