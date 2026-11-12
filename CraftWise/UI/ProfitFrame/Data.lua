-- Profit table window: what the list shows. View choice, search and view filters, profession tabs, sort order.
local _, ns = ...
local PF = ns.PF
local state, Settings, View, ItemName = PF.state, PF.Settings, PF.View, PF.ItemName

-- Rows after the search box and the view's filters; also returns how many the filters hid.
local function FilteredRows()
	local s = Settings()
	if View() == "level" then
		local all, skill = {}, nil
		if state.professionID then
			all, skill = ns.LevelingRows(state.professionID)
		end
		state.levelSkill = skill
		local query = state.query:lower()
		local out = {}
		for _, r in ipairs(all) do
			if query == "" or (r.name or ""):lower():find(query, 1, true) then
				out[#out + 1] = r
			end
		end
		return out, 0
	end
	local learnView = View() == "learn"
	local all = state.professionID and ns.BuildRows(state.professionID, learnView or s.includeUnlearned, View()) or {}
	local query = state.query:lower()
	local out, hidden = {}, 0
	-- The search matches recipe names and reagent names ("which recipes use Light Leather").
	local function ReagentMatch(r)
		for _, line in ipairs(r.reagents or {}) do
			if ItemName(line.itemID):lower():find(query, 1, true) then
				return true
			end
		end
		return false
	end
	for _, r in ipairs(all) do
		local keep = query == "" or (r.name or ""):lower():find(query, 1, true) or ReagentMatch(r)
		if keep and learnView then
			if r.status == "known" then
				keep = false
			elseif s.learnFitsSkill and (not r.required or r.tooLow) then
				-- fits your skill only when the requirement is known and met
				keep, hidden = false, hidden + 1
			end
		elseif keep and s.hideUnpriced and not r.profit then
			keep, hidden = false, hidden + 1
		end
		if keep then
			if learnView then
				r.where = ns.RecipeWhere(r.recipeID)
				r.whereText = r.where[1] and r.where[1].text or nil
				r.whereLabel = r.where[1] and r.where[1].origin == "seen" and r.where[1].label or nil
			end
			out[#out + 1] = r
		end
	end
	return out, hidden
end

local function ProfessionIDs()
	local ids = {}
	for id, prof in pairs(ns.charDB.professions) do
		if prof.name and next(prof.recipes) and not ns.IsGathering(id) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		return (ns.charDB.professions[a].name or "") < (ns.charDB.professions[b].name or "")
	end)
	return ids
end

local function SortSettings()
	local s = Settings()
	if View() == "learn" then
		return s.learnSortKey or "required", s.learnSortDesc
	elseif View() == "level" then
		return s.levelSortKey or "perPoint", s.levelSortDesc or false
	end
	return s.sortKey, s.sortDesc
end

PF.FilteredRows, PF.ProfessionIDs, PF.SortSettings = FilteredRows, ProfessionIDs, SortSettings
