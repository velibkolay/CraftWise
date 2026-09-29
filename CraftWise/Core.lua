local addonName, ns = ...
ns.name = addonName

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		CraftWiseDB = CraftWiseDB or { version = 1 }
		CraftWiseCharDB = CraftWiseCharDB or { recipes = {} }
		ns.db, ns.charDB = CraftWiseDB, CraftWiseCharDB
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

SLASH_CRAFTWISE1 = "/cw"
SLASH_CRAFTWISE2 = "/craftwise"
SlashCmdList.CRAFTWISE = function(msg)
	if ns.ToggleProfitFrame then
		ns.ToggleProfitFrame()
	end
end
