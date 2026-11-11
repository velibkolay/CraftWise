-- Records trainer fees and required skill per recipe while a profession trainer is open, plus the
-- recipe itself (#83): produced item, reagents with counts, the skill it needs and when it was seen.
-- Recipes the bundled DB2 export doesn't have (the Forever trainer belts of build 1.60.1.70790) are
-- built from this record; they are first-hand client data ("recorded in game"), never guessed.
-- APIs: GetTrainerServiceInfo / Cost / SkillReq and the service tooltip (C_TooltipInfo.GetTrainerService),
-- as Blizzard's Forever trainer UI uses them; the recipe through C_TradeSkillUI.GetRecipeSchematic
-- (ns.ReadSchematic). The trainer API itself has no output or reagent functions on Forever: Blizzard's
-- Forever trainer UI (Mainline/Blizzard_TrainerUI.lua) calls none and the API docs list none.
local _, ns = ...

-- Recipe IDs by exact name, across every cached profession. Ambiguous names map to false.
local function NameIndex()
	local index = {}
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for recipeID, recipe in pairs(prof.recipes) do
			if recipe.name then
				if index[recipe.name] == nil then
					index[recipe.name] = recipeID
				elseif index[recipe.name] ~= recipeID then
					index[recipe.name] = false
				end
			end
		end
	end
	return index
end

local function IsCachedRecipe(recipeID)
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.recipes[recipeID] then
			return true
		end
	end
	return false
end

-- Skill line of a trainer service's profession, from the skill it requires (the client's localized
-- name, matched against the cached professions first, then the enUS names of the bundled data).
local function LineOfSkill(skillName)
	if type(skillName) ~= "string" or skillName == "" then
		return nil
	end
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.name == skillName then
			return ns.SkillLineOf(professionID, prof.name)
		end
	end
	return ns.ProfessionSkillLines and ns.ProfessionSkillLines[skillName] or nil
end

-- The taught spell from the service tooltip, when the client exposes it (nil when secret).
local function TooltipID(index)
	if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	local id = ok and data and data.id
	if id and issecretvalue and issecretvalue(id) then
		return "secret"
	end
	return type(id) == "number" and id or nil
end

-- A tooltip spell is a recipe when the profession cache, the bundled data or an earlier trainer
-- record knows it, or (a recipe none has, #83) when the service requires a profession skill and the client returns a schematic
-- with reagents for the spell. Class trainer spells have neither, so they are never recorded.
-- Returns recipeID, reagents, output (the last two only when read here).
local function TooltipRecipe(id, skillLine)
	if type(id) ~= "number" then
		return nil
	end
	local seen = ns.db and ns.db.trainer[id]
	if IsCachedRecipe(id) or (ns.RecipeData and ns.RecipeData[id]) or (seen and seen.reagents) then
		return id
	end
	if skillLine then
		local reagents, output = ns.ReadSchematic(id)
		if reagents and #reagents > 0 then
			return id, reagents, output
		end
	end
end

function ns.RecordTrainer(event)
	-- Diagnostics (issue #3): what the trainer API returned, kept in SavedVariables.
	local diag = { event = event, api = GetNumTrainerServices and "ok" or "missing", samples = {} }
	if ns.db then
		ns.db.debug = ns.db.debug or {}
		ns.db.debug.trainer = diag
	end
	if not (ns.db and GetNumTrainerServices) then
		return 0
	end
	local names
	local recorded, withRecipe = 0, 0
	local okCount, count = pcall(GetNumTrainerServices)
	diag.services = okCount and count or ("error: " .. tostring(count))
	if not okCount then
		return 0
	end
	local now = time and time() or nil
	for index = 1, count do
		local name, kind, icon = GetTrainerServiceInfo(index)
		if name and kind ~= "header" then
			local skillName, required = GetTrainerServiceSkillReq(index)
			local skillLine = LineOfSkill(skillName)
			local tipID = TooltipID(index)
			local recipeID, reagents, output = TooltipRecipe(tipID, skillLine)
			local via = recipeID and "tooltip"
			if not recipeID then
				names = names or NameIndex()
				recipeID = names[name] or nil
				via = recipeID and "name" or nil
			end
			if #diag.samples < 8 then
				diag.samples[#diag.samples + 1] = { name = name, kind = kind, tooltipID = tipID, matched = recipeID, via = via, skill = skillName }
			end
			if recipeID then
				if not reagents then
					reagents, output = ns.ReadSchematic(recipeID)
				end
				local rec = { fee = GetTrainerServiceCost(index) or 0, required = required or 0, at = now }
				-- The recipe as the client describes it (#83). An unreadable schematic leaves it out:
				-- a partial reagent list would make the recipe look cheaper than it is.
				-- A recipe read on an earlier visit stays when this read fails.
				local old = ns.db.trainer[recipeID]
				if reagents and #reagents > 0 then
					rec.reagents = reagents
					rec.output = output
					rec.noItemOutput = output == nil or nil
					rec.recipeAt = now
					withRecipe = withRecipe + 1
				elseif old and old.reagents then
					rec.reagents, rec.output, rec.noItemOutput, rec.recipeAt = old.reagents, old.output, old.noItemOutput, old.recipeAt
				end
				rec.name = name
				rec.icon = icon
				rec.skill = type(skillName) == "string" and skillName or nil
				rec.line = ns.RecipeSkillLine(recipeID) or skillLine
				ns.db.trainer[recipeID] = rec
				recorded = recorded + 1
			end
		end
	end
	diag.recorded = recorded
	diag.withRecipe = withRecipe
	if recorded > 0 then
		ns.Notify("RECIPES_CHANGED")
	end
	return recorded
end

-- The trainer list only shows what its filter allows (by default not learned or too-high recipes).
-- On open, briefly show every service type, record, then restore the player's filter.
local FILTER_TYPES = { "available", "unavailable", "used" }
local expanding = false

local function RecordAll(event)
	if expanding or not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then
		return ns.RecordTrainer(event)
	end
	expanding = true
	local saved = {}
	local ok = pcall(function()
		for _, t in ipairs(FILTER_TYPES) do
			saved[t] = GetTrainerServiceTypeFilter(t) and 1 or 0
			SetTrainerServiceTypeFilter(t, 1)
		end
	end)
	ns.RecordTrainer(event)
	if ok then
		pcall(function()
			for _, t in ipairs(FILTER_TYPES) do
				SetTrainerServiceTypeFilter(t, saved[t])
			end
		end)
	end
	expanding = false
end

ns.On("TRAINER_SHOW", RecordAll)
ns.On("TRAINER_UPDATE", function(event)
	if not expanding then
		ns.RecordTrainer(event)
	end
end)
