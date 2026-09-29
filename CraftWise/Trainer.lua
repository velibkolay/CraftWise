-- Records trainer fees and required skill per recipe while a profession trainer is open.
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

-- The service tooltip carries the taught spell when the client exposes it.
local function TooltipRecipeID(index)
	if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	local id = ok and data and data.id
	if id and issecretvalue and issecretvalue(id) then
		return nil
	end
	if id and IsCachedRecipe(id) then
		return id
	end
end

function ns.RecordTrainer()
	if not (ns.db and GetNumTrainerServices) then
		return 0
	end
	local names
	local recorded = 0
	for index = 1, GetNumTrainerServices() do
		local name, kind = GetTrainerServiceInfo(index)
		if name and kind ~= "header" then
			local recipeID = TooltipRecipeID(index)
			if not recipeID then
				names = names or NameIndex()
				recipeID = names[name] or nil
			end
			if recipeID then
				local _, required = GetTrainerServiceSkillReq(index)
				ns.db.trainer[recipeID] = { fee = GetTrainerServiceCost(index) or 0, required = required or 0 }
				recorded = recorded + 1
			end
		end
	end
	if recorded > 0 then
		ns.Notify("RECIPES_CHANGED")
	end
	return recorded
end

ns.On("TRAINER_SHOW", ns.RecordTrainer)
ns.On("TRAINER_UPDATE", ns.RecordTrainer)
