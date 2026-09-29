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

-- Status of a recipe for this character:
--   "known"      learned
--   "trainable"  a trainer teaches it and the skill is high enough
--   "later"      a trainer teaches it, skill too low (returns required skill)
--   "unlearned"  not learned, no trainer record (recipe item, quest, or trainer not visited)
function ns.RecipeStatus(prof, recipeID, recipe)
	if recipe.learned then
		return "known"
	end
	local t = ns.db and ns.db.trainer[recipeID]
	if t then
		if (t.required or 0) <= (prof.skill or 0) then
			return "trainable"
		end
		return "later", t.required
	end
	return "unlearned"
end

-- Learn cost if known (trainer fee). Recipe-item prices need a recipe-item mapping (future).
function ns.LearnCost(recipeID)
	local t = ns.db and ns.db.trainer[recipeID]
	return t and t.fee or nil
end

-- Rows for the profit table of one profession.
function ns.BuildRows(professionID, includeUnlearned)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	if not prof then
		return {}
	end
	local prices = { buy = ns.GetBuyPrice, sell = ns.GetSellValue }
	local rows = {}
	for recipeID, recipe in pairs(prof.recipes) do
		if recipe.learned or includeUnlearned then
			local status, required = ns.RecipeStatus(prof, recipeID, recipe)
			local result = ns.Profit.Evaluate({
				reagents = recipe.reagents,
				output = recipe.output,
				learned = recipe.learned,
				learnCost = ns.LearnCost(recipeID),
			}, prices)
			result.recipeID = recipeID
			result.name = recipe.name
			result.icon = recipe.icon
			result.status = status
			result.required = required
			result.source = recipe.source
			result.difficulty = recipe.difficulty
			result.noItemOutput = recipe.noItemOutput or result.noItemOutput
			result.outputItemID = recipe.output and recipe.output.itemID
			table.insert(rows, result)
		end
	end
	return rows
end
