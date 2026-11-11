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
		GetMerchantItemCostInfo = UI .. "Mainline/MerchantFrame.lua (MerchantFrame_UpdateAltCurrency)",
		GetMerchantItemCostItem = UI .. "Mainline/MerchantFrame.lua (returns texture, value, link, currencyName)",
		GetNumLootItems = UI .. "Mainline/LootFrame.lua",
		GetLootSlotLink = UI .. "Mainline/LootFrame.lua",
		-- Not called by Blizzard's Forever UI and not in its API docs. Long-standing client API (all clients);
		-- not yet seen working in Forever: see docs/ingame-checks.md "Source recorder". If absent, nothing is recorded.
		GetLootSourceInfo = "UNVERIFIED in Forever, first in-game check in docs/ingame-checks.md (Source recorder)",
		GetLootSlotInfo = UI .. "Mainline/LootFrame.lua (LootFrameMixin:Open; returns texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin)",
		LootSlot = UI .. "Mainline/LootFrame.lua (item OnClick)",
		IsModifiedClick = UI .. "Mainline/ContainerFrame.lua (IsModifiedClick(\"AUTOLOOTTOGGLE\")); Blizzard_SettingsDefinitions_Frame/Controls.lua registers the AUTOLOOTTOGGLE modifier",
		GetQuestID = UI .. "Mainline/QuestFrame.lua",
		GetInboxNumItems = UI .. "Blizzard_MailFrame/MailFrame.lua (InboxFrame_Update: numItems, totalItems)",
		GetInboxItem = UI .. "Blizzard_MailFrame/MailFrame.lua (OpenMail_Update: name, itemID, texture, count, quality, canUse, isCurrency)",
		GetQuestItemLink = UI .. "Mainline/QuestInfo.lua",
		GetNumQuestChoices = UI .. "Mainline/QuestInfo.lua",
		GetNumQuestRewards = UI .. "Mainline/QuestInfo.lua",
		GetTitleText = UI .. "Mainline/QuestFrame.lua",
		GetNumBuybackItems = UI .. "Mainline/MerchantFrame.lua (MerchantFrame_UpdateMerchantInfo, MerchantFrame_UpdateBuybackInfo)",
		GetMerchantFilter = UI .. "Mainline/MerchantFrame.lua (FilterDropdown IsSelected: GetMerchantFilter() == filter, LE_LOOT_FILTER_ALL)",
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
		GetGuildInfo = UI .. "Blizzard_UIPanels_Game/Mainline/TabardFrame.lua, Blizzard_HardcoreUI/HardcoreUI.lua (GetGuildInfo(\"player\"): guildName, rankName, rank)",
		GetInventoryItemDurability = UI .. "Blizzard_FrameXML/Mainline/EquipmentManager.lua (durability, maxDurability = GetInventoryItemDurability(slot))",
		HasPetUI = UI .. "Blizzard_UIPanels_Game/Mainline/PaperDollFrame.lua, Blizzard_FrameXML/PetHappiness.lua (hasPetUI, isHunterPet)",
		GetTaxiMapID = UI .. "Blizzard_FlightMap/Blizzard_FlightMap.lua (FlightMapMixin:OnShow: mapID = GetTaxiMapID(), then C_TaxiMap.GetAllTaxiNodes(mapID) in FM_FlightPathDataProvider.lua)",
		PlaySoundFile = GAME .. " (Music tab songs, 2026-10-01)",
		StopSound = UI .. "Blizzard_HousingDashboardInitiatives.lua; " .. GAME .. " (music stops with the cast)",
	},
	events = {},
	-- Lua / FrameXML globals that are not client API calls.
	lua = {},
}
