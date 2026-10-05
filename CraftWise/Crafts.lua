-- Skill-up recorder (issue #15). Every craft is logged with the skill it was made at and whether it
-- gave a point, so skill-up chances can be measured in game instead of taken from the community
-- formula (not official, not verified for Forever). Totals live in CraftWiseDB.skillups:
--   [recipeID] = { [skill] = { n = crafts, ups = skill points gained, d = client difficulty } }
local _, ns = ...

local SETTLE = 2.5 -- seconds a craft waits for its skill update before it counts as no skill-up

local tracked = {} -- [professionID] = skill last seen
local pending = {} -- crafts waiting for their skill update, oldest first
local unclaimed -- { prof, amount, time }: a skill update that arrived before its craft event

local function Now()
	return GetTime and GetTime() or 0
end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- Current skill per profession, from the client's profession list.
local function ClientSkills()
	local skills = {}
	if not (GetProfessions and GetProfessionInfo) then
		return skills
	end
	local list = { GetProfessions() }
	for i = 1, 6 do
		local index = list[i]
		if index then
			local ok, _, _, skill, _, _, _, skillLine = pcall(GetProfessionInfo, index)
			if ok and skillLine and skill and not Secret(skill) then
				skills[skillLine] = skill
			end
		end
	end
	return skills
end

local function RecipeOwner(recipeID)
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.recipes[recipeID] then
			return professionID, prof.recipes[recipeID]
		end
	end
end

local function Store(craft, gained)
	if not ns.db then
		return
	end
	ns.db.skillups = ns.db.skillups or {}
	local byRecipe = ns.db.skillups[craft.recipeID] or {}
	ns.db.skillups[craft.recipeID] = byRecipe
	local entry = byRecipe[craft.skill] or { n = 0, ups = 0 }
	byRecipe[craft.skill] = entry
	entry.n = entry.n + 1
	entry.ups = entry.ups + (gained > 0 and 1 or 0)
	entry.d = craft.difficulty or entry.d
	ns.Notify("SKILLUPS_CHANGED", craft.recipeID)
end

-- Compare client skills with what we last saw and hand gains to the oldest waiting craft.
function ns.CheckSkills()
	for prof, skill in pairs(ClientSkills()) do
		local before = tracked[prof]
		tracked[prof] = skill
		if before and skill > before then
			local gain = skill - before
			for i, craft in ipairs(pending) do
				if craft.prof == prof then
					table.remove(pending, i)
					Store(craft, gain)
					gain = 0
					break
				end
			end
			if gain > 0 then
				unclaimed = { prof = prof, amount = gain, time = Now() }
			end
		end
	end
end

-- Crafts older than SETTLE without a skill update gave no point.
function ns.SettleCrafts(now)
	now = now or Now()
	ns.CheckSkills()
	local i = 1
	while pending[i] do
		if now - pending[i].time >= SETTLE then
			Store(table.remove(pending, i), 0)
		else
			i = i + 1
		end
	end
end

function ns.OnCraft(recipeID)
	local prof, recipe = RecipeOwner(recipeID)
	if not prof then
		return
	end
	ns.CheckSkills()
	local now = Now()
	local craft = { recipeID = recipeID, prof = prof, skill = tracked[prof], difficulty = recipe.difficulty, time = now }
	if unclaimed and unclaimed.prof == prof and now - unclaimed.time <= SETTLE then
		craft.skill = (craft.skill or 0) - unclaimed.amount
		local amount = unclaimed.amount
		unclaimed = nil
		if craft.skill > 0 then
			Store(craft, amount)
		end
		return
	end
	if not craft.skill then
		return -- skill unknown: can't say at which skill this craft was made
	end
	pending[#pending + 1] = craft
	if C_Timer and C_Timer.After then
		C_Timer.After(SETTLE + 0.1, function()
			ns.SettleCrafts()
		end)
	end
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
	if unit ~= "player" or not spellID or Secret(spellID) then
		return
	end
	ns.OnCraft(spellID)
end)

for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_LIST_UPDATE", "CHAT_MSG_SKILL", "PLAYER_ENTERING_WORLD" }) do
	ns.On(event, function()
		ns.CheckSkills()
	end)
end

-- Live skill of a profession as the client reports it (nil until seen).
function ns.LiveSkill(professionID)
	return tracked[professionID] or ClientSkills()[professionID]
end

-- Bundled yellow and grey thresholds (client DB2, Data/Thresholds.lua).
function ns.RecipeThresholds(recipeID)
	local t = ns.Thresholds and ns.Thresholds[recipeID]
	if t then
		return t[1], t[2]
	end
end

-- Recorded crafts of a recipe: at one skill, or all skills added up.
function ns.SkillUpStats(recipeID, skill)
	local byRecipe = ns.db and ns.db.skillups and ns.db.skillups[recipeID]
	if not byRecipe then
		return 0, 0
	end
	if skill then
		local e = byRecipe[skill]
		return e and e.n or 0, e and e.ups or 0
	end
	local n, ups = 0, 0
	for _, e in pairs(byRecipe) do
		n, ups = n + e.n, ups + e.ups
	end
	return n, ups
end

function ns.CraftsRecorded()
	local n = 0
	for recipeID in pairs(ns.db and ns.db.skillups or {}) do
		n = n + (ns.SkillUpStats(recipeID))
	end
	return n
end
