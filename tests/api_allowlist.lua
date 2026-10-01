-- Client functions CraftWise uses that Blizzard's generated API docs don't list, each with how it
-- was verified for WoW: Forever. Add an entry only with evidence: Blizzard's own Forever UI code
-- calls it (Gethe/wow-ui-source, branch forever; deprecation fallbacks don't count, they can be
-- switched off), or it was seen working in the Forever client.
local UI = "Blizzard Forever UI: "
local GAME = "seen working in the Forever beta client"
return {
	functions = {
		["C_TradeSkillUI.GetAllRecipeIDs"] = GAME .. " (592 Leatherworking recipes read, 2026-09-30)",
		["C_TradeSkillUI.GetRecipeSourceText"] = UI .. "Blizzard_ProfessionsRecipeSchematicForm.lua",
		["C_TradeSkillUI.IsTradeSkillGuild"] = UI .. "Blizzard_ProfessionsRecipeList.lua",
		["C_TradeSkillUI.IsTradeSkillLinked"] = UI .. "Blizzard_ProfessionsFrame.lua",
		CreateFrame = UI .. "everywhere; " .. GAME,
		GetInventoryItemID = UI .. "Mainline/PaperDollFrame.lua; " .. GAME .. " (Upgrades view)",
		GetInventoryItemLink = UI .. "Mainline/ContainerFrame.lua",
		GetInventorySlotInfo = UI .. "SecureAuraHeader.lua; " .. GAME .. " (Upgrades view)",
		GetMerchantItemID = UI .. "Vanilla/MerchantFrame.lua; " .. GAME .. " (vendor prices recorded)",
		GetMerchantItemInfo = UI .. "Vanilla/MerchantFrame.lua",
		GetMerchantNumItems = UI .. "Vanilla/MerchantFrame.lua; " .. GAME,
		GetNumTrainerServices = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME .. " (trainer fees recorded)",
		GetTrainerServiceCost = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME,
		GetTrainerServiceInfo = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME,
		GetTrainerServiceSkillReq = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME,
		GetTrainerServiceTypeFilter = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME,
		SetTrainerServiceTypeFilter = UI .. "Mainline/Blizzard_TrainerUI.lua; " .. GAME,
		GetProfessions = UI .. "Cata/SpellBookProfessions.lua; " .. GAME .. " (profession icons)",
		GetProfessionInfo = UI .. "Cata/SpellBookProfessions.lua; " .. GAME,
		PlaySoundFile = GAME .. " (Music tab songs, 2026-10-01)",
		StopSound = UI .. "Blizzard_HousingDashboardInitiatives.lua; " .. GAME .. " (music stops with the cast)",
	},
	events = {},
	-- Lua / FrameXML globals that are not client API calls.
	lua = {},
}
