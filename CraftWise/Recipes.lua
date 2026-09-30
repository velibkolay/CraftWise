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

-- Profession icon as the game shows it (spellbook professions), matched by name.
function ns.ProfessionIconFromClient(name)
	if not (GetProfessions and GetProfessionInfo and name) then
		return nil
	end
	local list = { GetProfessions() }
	for i = 1, 6 do
		local index = list[i]
		if index then
			local profName, icon = GetProfessionInfo(index)
			if profName == name then
				return icon
			end
		end
	end
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
	prof.icon = ns.ProfessionIconFromClient(base.professionName) or prof.icon
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

-- Bundled data (Data/*.lua, generated from the Forever client's own DB2 tables by
-- cjber/skillup-forever, GPL-3.0): reagents, outputs, vendor prices, item sell prices.

-- Gathering professions have no crafts worth a profit table (their tab becomes a guide later).
ns.GATHERING = { [182] = true, [186] = true, [356] = true, [393] = true } -- Herbalism, Mining, Fishing, Skinning

-- Fallback icons per parent skill line, when the client doesn't give one.
local FALLBACK_ICONS = {
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", -- First Aid
	[164] = "Interface\\Icons\\Trade_BlackSmithing",
	[165] = "Interface\\Icons\\Trade_LeatherWorking",
	[171] = "Interface\\Icons\\Trade_Alchemy",
	[182] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow", -- Herbalism
	[185] = "Interface\\Icons\\INV_Misc_Food_15", -- Cooking
	[186] = "Interface\\Icons\\Trade_Mining",
	[197] = "Interface\\Icons\\Trade_Tailoring",
	[202] = "Interface\\Icons\\Trade_Engineering",
	[333] = "Interface\\Icons\\Trade_Engraving", -- Enchanting
	[356] = "Interface\\Icons\\Trade_Fishing",
	[393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", -- Skinning
}

function ns.ProfessionIcon(professionID)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	return (prof and prof.icon) or FALLBACK_ICONS[ns.SkillLineOf(professionID)] or 134400
end

function ns.IsGathering(professionID)
	return ns.GATHERING[ns.SkillLineOf(professionID)] or false
end

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

-- Only first-hand data decides how a recipe is learned: the trainer window (fee, required skill)
-- recorded in game. Recipe sources, requirements and skill-up thresholds wait for reliable Forever
-- data (issue #11); nothing is estimated.
local function Trainer(recipeID)
	local seen = ns.db and ns.db.trainer[recipeID]
	if seen then
		return seen.fee, seen.required
	end
end

-- Status of a recipe for this character, and the skill it needs:
--   "known"      learned
--   "trainable"  seen at a trainer (second return: required skill, third: skill too low)
--   "unlearned"  not learned, source not known yet
function ns.RecipeStatus(prof, recipeID, recipe)
	if recipe.learned then
		return "known"
	end
	local _, required = Trainer(recipeID)
	if required then
		return "trainable", required, required > (prof.skill or 0)
	end
	return "unlearned"
end

-- Cost to learn, from the trainer window. Returns copper and "trainer", or nil.
function ns.LearnCost(recipeID)
	local fee = Trainer(recipeID)
	if fee then
		return fee, "trainer"
	end
end

local function IsSpellKnown(recipeID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, recipeID)
		return ok and known or false
	end
	return false
end

-- Skill-up colour of a learned recipe, as the client reports it: "orange" | "yellow" | "green" |
-- "grey". Unlearned recipes are "red" when a trainer said the skill is too low, otherwise nil.
local CLIENT_COLORS = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
function ns.SkillUpColor(recipe, tooLow)
	if recipe.learned then
		return CLIENT_COLORS[recipe.difficulty]
	end
	return tooLow and "red" or nil
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
	result.skillColor = ns.SkillUpColor(recipe, tooLow)
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
