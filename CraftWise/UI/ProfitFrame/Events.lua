-- Profit table window: refresh on addon events while the window is open.
local _, ns = ...
local PF = ns.PF
local View, ItemView, Refresh = PF.View, PF.ItemView, PF.Refresh

ns.Listen("RECIPES_CHANGED", Refresh)
ns.Listen("PRICES_CHANGED", Refresh)
ns.Listen("SKILLUPS_CHANGED", function()
	if PF.frame and PF.frame:IsShown() and View() == "level" then
		Refresh()
	end
end)
ns.On("SKILL_LINES_CHANGED", function()
	if PF.frame and PF.frame:IsShown() and View() == "level" then
		Refresh()
	end
end)
ns.Listen("BAGS_CHANGED", function()
	if PF.frame and PF.frame:IsShown() and ItemView() then
		Refresh()
	end
end)
ns.Listen("MUSIC_CHANGED", function()
	if PF.frame and PF.frame:IsShown() and View() == "music" then
		Refresh()
	end
end)
ns.Listen("UPGRADES_CHANGED", function()
	if PF.frame and PF.frame:IsShown() and View() == "upgrades" then
		Refresh()
	end
end)
ns.On("AUCTION_HOUSE_CLOSED", Refresh) -- Auctionator prices may have changed during a scan
