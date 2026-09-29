-- Reads every recipe of the open profession window (learned and unlearned) and caches
-- it per character, so the profit table works with the window closed.
-- Findings behind this approach: issue #1.
local _, ns = ...

local function SafeCall(fn, ...)
	if not fn then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
end

-- Reagents and output of one recipe. Returns nil when the client has no schematic.
function ns.ReadSchematic(recipeID)
	local schematic = SafeCall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
	if not (schematic and schematic.reagentSlotSchematics) then
		return nil
	end
	local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local first = slot.reagents and slot.reagents[1]
		if basic == nil or slot.reagentType == basic then
			if not (first and first.itemID and first.itemID > 0 and (slot.quantityRequired or 0) > 0) then
				return nil -- an unreadable slot would make the recipe look cheaper than it is
			end
			table.insert(reagents, { itemID = first.itemID, quantity = slot.quantityRequired })
		end
	end
	local output
	if schematic.outputItemID and schematic.outputItemID > 0 then
		local min = schematic.quantityMin or 1
		local max = schematic.quantityMax or min
		output = { itemID = schematic.outputItemID, quantity = (min + max) / 2 }
	end
	return reagents, output
end

local function ProfessionContext()
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
		return nil
	end
	if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
		return nil
	end
	local base = SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
	if not (base and base.professionID and base.professionName) then
		return nil
	end
	return base
end

-- Scans the open profession. Returns the cached profession table, or nil if nothing to scan.
function ns.ScanProfession()
	if not ns.charDB then
		return nil
	end
	local base = ProfessionContext()
	if not base then
		return nil
	end
	local ids = SafeCall(C_TradeSkillUI.GetAllRecipeIDs)
	if not ids or #ids == 0 then
		return nil
	end
	local profs = ns.charDB.professions
	local prof = profs[base.professionID] or { recipes = {} }
	profs[base.professionID] = prof
	prof.name = base.professionName
	prof.skill = base.skillLevel or prof.skill
	prof.maxSkill = base.maxSkillLevel or prof.maxSkill
	prof.scannedAt = time and time() or nil

	for _, recipeID in ipairs(ids) do
		local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
		if info and not info.isDummyRecipe then
			local recipe = prof.recipes[recipeID] or {}
			recipe.name = info.name or recipe.name
			recipe.icon = info.icon or recipe.icon
			recipe.learned = info.learned and true or false
			recipe.difficulty = info.relativeDifficulty
			local reagents, output = ns.ReadSchematic(recipeID)
			if reagents then
				recipe.reagents = reagents
				recipe.output = output
				recipe.noItemOutput = output == nil or nil
			end
			if not recipe.learned then
				local source = SafeCall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
				if type(source) == "string" and source ~= "" then
					recipe.source = source
				end
			end
			prof.recipes[recipeID] = recipe
		end
	end
	ns.Notify("RECIPES_CHANGED", base.professionID)
	return prof
end

-- The window fires list updates in bursts; scan once per burst.
local pending = false
local function RequestScan()
	if pending then
		return
	end
	pending = true
	local function run()
		pending = false
		ns.ScanProfession()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, run)
	else
		run()
	end
end

ns.On("TRADE_SKILL_SHOW", RequestScan)
ns.On("TRADE_SKILL_LIST_UPDATE", RequestScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", RequestScan)

-- Bundled data (Data/*.lua, generated from the Forever client's DB2 and CMaNGOS classic-db by
-- cjber/skillup-forever, GPL-3.0) fills what the client can't tell us with the window closed.

-- Parent skill line of a cached profession (enUS name lookup), falling back to its ID.
function ns.SkillLineOf(professionID)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	local byName = prof and prof.name and ns.ProfessionSkillLines and ns.ProfessionSkillLines[prof.name]
	return byName or professionID
end

-- Reagents and output from bundled data. Output false in the data means "no item" (enchants).
function ns.BundledRecipe(recipeID)
	local data = ns.RecipeData and ns.RecipeData[recipeID]
	if not data then
		return nil
	end
	return data.reagents, data.output or nil, data.output == false
end

-- Recipe names by ID for one skill line, built once from RecipeNames[skillLine][name] = id.
local namesByID = {}
local function BundledName(skillLine, recipeID)
	if not namesByID[skillLine] then
		local map = {}
		for name, id in pairs(ns.RecipeNames and ns.RecipeNames[skillLine] or {}) do
			if id then
				map[id] = name
			end
		end
		namesByID[skillLine] = map
	end
	return namesByID[skillLine][recipeID]
end

local function Trainer(recipeID)
	local seen = ns.db and ns.db.trainer[recipeID]
	if seen then
		return seen.fee, seen.required, "seen"
	end
	local bundled = ns.TrainerFees and ns.TrainerFees[recipeID]
	if bundled then
		return bundled[1], bundled[2], "bundled"
	end
end

local function RecipeItemSource(recipeID)
	return ns.RecipeSources and ns.RecipeSources[recipeID]
end

-- Status of a recipe for this character, and the skill it needs:
--   "known"      learned
--   "trainable"  a trainer teaches it and the skill is high enough
--   "vendor"     a recipe item sold by a vendor
--   "drop"       a recipe item from mob drops or world drops
--   "quest"      a recipe item from a quest
--   "unlearned"  no source known
-- The second return is the required skill; the third is true when the skill is too low.
function ns.RecipeStatus(prof, recipeID, recipe)
	if recipe.learned then
		return "known"
	end
	local skill = prof.skill or 0
	local _, required = Trainer(recipeID)
	if required then
		return "trainable", required, required > skill
	end
	local source = RecipeItemSource(recipeID)
	if source then
		local status = source.vendors and "vendor" or source.quests and "quest" or "drop"
		return status, source.skill, (source.skill or 0) > skill
	end
	return "unlearned"
end

-- Cost to learn: trainer fee, else the recipe item's vendor price, else its AH price.
-- Returns copper and where it came from ("trainer" | "vendor" | "auction"), or nil.
function ns.LearnCost(recipeID)
	local fee = Trainer(recipeID)
	if fee then
		return fee, "trainer"
	end
	local source = RecipeItemSource(recipeID)
	if source then
		if source.price then
			return source.price, "vendor"
		end
		local ah = ns.GetAuctionPrice(source.item)
		if ah then
			return ah, "auction"
		end
	end
end

-- Vendor NPC names for a recipe item, filtered to the player's faction.
function ns.RecipeVendors(recipeID)
	local source = RecipeItemSource(recipeID)
	if not (source and source.vendors and ns.SourceNPCs) then
		return {}
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
	local names = {}
	for _, npc in ipairs(source.vendors) do
		local info = ns.SourceNPCs[npc]
		if info and (info[2] == "" or mine == nil or info[2] == mine) then
			table.insert(names, info[1])
		end
	end
	return names
end

local function IsSpellKnown(recipeID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, recipeID)
		return ok and known or false
	end
	return false
end

local function MakeRow(prof, recipeID, recipe, prices)
	local status, required, tooLow = ns.RecipeStatus(prof, recipeID, recipe)
	local learnCost, learnSource
	if not recipe.learned then
		learnCost, learnSource = ns.LearnCost(recipeID)
	end
	local result = ns.Profit.Evaluate({
		reagents = recipe.reagents,
		output = recipe.output,
		learned = recipe.learned,
		learnCost = learnCost,
	}, prices)
	result.recipeID = recipeID
	result.name = recipe.name
	result.icon = recipe.icon
	result.status = status
	result.required = required
	result.tooLow = tooLow
	result.learnSource = learnSource
	result.source = recipe.source
	result.difficulty = recipe.difficulty
	result.noItemOutput = recipe.noItemOutput or result.noItemOutput
	result.outputItemID = recipe.output and recipe.output.itemID
	result.bundledOnly = recipe.bundledOnly
	return result
end

-- Rows for the profit table of one profession. Cached recipes come first-hand from the client;
-- with includeUnlearned, bundled recipes of the same skill line that the client never listed are
-- added too, so "what could I learn" works even if the client only lists learned recipes.
function ns.BuildRows(professionID, includeUnlearned)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	if not prof then
		return {}
	end
	local prices = { buy = ns.GetBuyPrice, sell = ns.GetSellValue }
	local rows = {}
	for recipeID, recipe in pairs(prof.recipes) do
		if recipe.learned or includeUnlearned then
			if not recipe.reagents then
				local reagents, output, noItem = ns.BundledRecipe(recipeID)
				if reagents then
					recipe = setmetatable({ reagents = reagents, output = output, noItemOutput = noItem or nil },
						{ __index = recipe })
				end
			end
			table.insert(rows, MakeRow(prof, recipeID, recipe, prices))
		end
	end
	if includeUnlearned and ns.RecipeData then
		local skillLine = ns.SkillLineOf(professionID)
		for recipeID, data in pairs(ns.RecipeData) do
			if data.skillLine == skillLine and not prof.recipes[recipeID] and data.reagents then
				local learned = IsSpellKnown(recipeID)
				local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
					or BundledName(skillLine, recipeID)
					or ("Recipe #" .. recipeID)
				if not learned then
					local output = data.output or nil
					local icon = output and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(output.itemID)
					table.insert(rows, MakeRow(prof, recipeID, {
						name = name,
						icon = icon,
						learned = false,
						reagents = data.reagents,
						output = output,
						noItemOutput = data.output == false or nil,
						bundledOnly = true,
					}, prices))
				end
			end
		end
	end
	return rows
end
