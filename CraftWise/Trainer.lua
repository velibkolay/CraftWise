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
	local recorded = 0
	local okCount, count = pcall(GetNumTrainerServices)
	diag.services = okCount and count or ("error: " .. tostring(count))
	if not okCount then
		return 0
	end
	for index = 1, count do
		local name, kind = GetTrainerServiceInfo(index)
		if name and kind ~= "header" then
			local recipeID = TooltipRecipeID(index)
			local via = recipeID and "tooltip"
			if not recipeID then
				names = names or NameIndex()
				recipeID = names[name] or nil
				via = recipeID and "name" or nil
			end
			if #diag.samples < 8 then
				local okTip, tip = pcall(function()
					return C_TooltipInfo and C_TooltipInfo.GetTrainerService(index)
				end)
				local tipID = okTip and tip and tip.id or nil
				if tipID and issecretvalue and issecretvalue(tipID) then
					tipID = "secret"
				end
				diag.samples[#diag.samples + 1] = { name = name, kind = kind, tooltipID = tipID, matched = recipeID, via = via }
			end
			if recipeID then
				local _, required = GetTrainerServiceSkillReq(index)
				ns.db.trainer[recipeID] = { fee = GetTrainerServiceCost(index) or 0, required = required or 0 }
				recorded = recorded + 1
			end
		end
	end
	diag.recorded = recorded
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
