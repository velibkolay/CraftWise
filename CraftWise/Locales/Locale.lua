-- Player-visible text (issue #13). Keys are the English text; a missing translation shows English.
-- Translations go in Locales/<locale>.lua and fill ns.L for their client locale only, e.g.
--   if GetLocale() ~= "deDE" then return end
--   local L = select(2, ...).L
--   L["Profit"] = "Gewinn"
local _, ns = ...

ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
