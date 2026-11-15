-- "Used in": which recipes take an item as a reagent. Built from the client's own recipe data:
-- the recipes this character's professions list (cached from the profession window) plus the
-- bundled Forever DB2 reagent table (Data/Recipes.lua). Nothing guessed.
local _, ns = ...

local index -- [itemID] = { { recipeID, skillLine, quantity } }
local building -- { index, seen, cursor } while UsedInStep is part way (#202)

local function Add(b, itemID, recipeID, skillLine, quantity)
	local seen = b.seen[itemID]
	if not seen then
		seen = {}
		b.seen[itemID] = seen
		b.index[itemID] = {}
	end
	if seen[recipeID] then
		return
	end
	seen[recipeID] = true
	table.insert(b.index[itemID], { recipeID = recipeID, skillLine = skillLine, quantity = quantity })
end

-- One slice of building the index: the recipes of your professions as the profession window lists them (a
-- few hundred at most, in the first call), then up to maxRecipes more of the bundled reagent table. Returns
-- true once the index is complete. Without maxRecipes it does all of it.
function ns.UsedInStep(maxRecipes)
	if index then
		return true
	end
	if not building then
		building = { index = {}, seen = {} }
		for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
			local skillLine = ns.SkillLineOf(professionID)
			for recipeID, recipe in pairs(prof.recipes) do
				if ns.RecipeBelongs(professionID, recipeID) then
					for _, r in ipairs(recipe.reagents or {}) do
						Add(building, r.itemID, recipeID, skillLine, r.quantity)
					end
				end
			end
		end
	end
	local b = building
	local data = ns.RecipeData or {}
	local recipeID = b.cursor
	for _ = 1, maxRecipes or math.huge do
		local entry
		recipeID, entry = next(data, recipeID)
		if recipeID == nil then
			index, building = b.index, nil
			return true
		end
		for _, r in ipairs(entry.reagents or {}) do
			Add(b, r.itemID, recipeID, entry.skillLine, r.quantity)
		end
	end
	b.cursor = recipeID
	return false
end

-- Is the index built? Callers that must not pay for building it check this and wait for it.
function ns.UsedInReady()
	return index ~= nil
end

ns.Listen("RECIPES_CHANGED", function()
	index, building = nil, nil
end)

local englishNames
local function ProfessionName(skillLine)
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if ns.SkillLineOf(professionID) == skillLine and prof.name then
			return prof.name, professionID
		end
	end
	if not englishNames then
		englishNames = {}
		for name, id in pairs(ns.ProfessionSkillLines or {}) do
			englishNames[id] = name
		end
	end
	return englishNames[skillLine] or ("Profession " .. tostring(skillLine)), nil
end

local ORDER = { known = 1, learnable = 2, other = 3 }

-- Recipes using an item, best first: ones you know, then ones you can learn, then other professions.
-- Entry: { recipeID, name, quantity, profession, professionID (yours) , state, required, tooLow }
function ns.UsedIn(itemID)
	while not index do
		ns.UsedInStep()
	end
	local out = {}
	for _, e in ipairs(index[itemID] or {}) do
		local profName, professionID = ProfessionName(e.skillLine)
		local prof = professionID and ns.charDB.professions[professionID]
		local recipe = prof and prof.recipes[e.recipeID]
		local entry = {
			recipeID = e.recipeID, quantity = e.quantity, profession = profName, professionID = professionID,
			name = recipe and recipe.name or ns.BundledName(e.skillLine, e.recipeID)
				or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.recipeID)) or ("Recipe #" .. e.recipeID),
		}
		if recipe and recipe.learned then
			entry.state = "known"
		elseif prof then
			entry.state = "learnable"
			local _, required, tooLow = ns.RecipeStatus(prof, e.recipeID, recipe or {})
			entry.required, entry.tooLow = required, tooLow
		else
			entry.state = "other"
		end
		out[#out + 1] = entry
	end
	table.sort(out, function(a, b)
		if a.state ~= b.state then
			return ORDER[a.state] < ORDER[b.state]
		end
		if a.profession ~= b.profession then
			return a.profession < b.profession
		end
		if (a.required or 0) ~= (b.required or 0) then
			return (a.required or 0) < (b.required or 0)
		end
		return a.name < b.name
	end)
	return out
end

-- Per profession: how many recipes use the item and how many of them you know.
-- { { profession, professionID, count, known, mine } }, your professions first.
function ns.UsedInSummary(itemID)
	local groups, order = {}, {}
	for _, e in ipairs(ns.UsedIn(itemID)) do
		local g = groups[e.profession]
		if not g then
			g = { profession = e.profession, professionID = e.professionID, count = 0, known = 0, mine = e.state ~= "other" }
			groups[e.profession] = g
			order[#order + 1] = g
		end
		g.count = g.count + 1
		if e.state == "known" then
			g.known = g.known + 1
		end
	end
	table.sort(order, function(a, b)
		if a.mine ~= b.mine then
			return a.mine
		end
		if a.known ~= b.known then
			return a.known > b.known
		end
		return a.count > b.count
	end)
	return order
end
