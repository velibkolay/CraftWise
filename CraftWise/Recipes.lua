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

-- A profession worth a cache entry: a skill line other than 0 and a name (#78). The client can report
-- line 0 with an empty name (seen in Veli's CraftWiseCharDB, scanned 2026-11-02): the "? 0/0" tab.
function ns.IsProfessionEntry(professionID, name)
	return type(professionID) == "number" and professionID ~= 0 and type(name) == "string" and name ~= ""
end

local function ProfessionContext()
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
		return nil
	end
	if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
		return nil
	end
	local base = SafeCall(C_TradeSkillUI.GetBaseProfessionInfo)
	if not (base and ns.IsProfessionEntry(base.professionID, base.professionName)) then
		return nil
	end
	return base
end

-- Recipes learned recently (#107), newest last, in CraftWiseCharDB.learned:
--   { id = recipeID, t, how = "event" | "scan", after, line }
-- how "event": NEW_RECIPE_LEARNED fired at t (the time it was learned). how "scan": a profession scan at
-- t found it learned and the scan before (at `after`) had it unlearned or not listed, so it was learned
-- between after and t. A recipe is listed once (the first time it was seen learned). line = its skill line.
ns.LEARNED_MAX = 20

function ns.NoteLearned(recipeID, how, t, after, line)
	if not (ns.charDB and type(recipeID) == "number") then
		return false
	end
	ns.charDB.learned = ns.charDB.learned or {}
	local log = ns.charDB.learned
	for _, e in ipairs(log) do
		if e.id == recipeID then
			return false
		end
	end
	log[#log + 1] = { id = recipeID, t = t, how = how, after = after, line = line }
	while #log > ns.LEARNED_MAX do
		table.remove(log, 1)
	end
	return true
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
	-- The window can announce a new profession before its recipe list follows (#44). Recipes whose
	-- bundled skill line is another profession's are never filed here; a list that has only foreign
	-- recipes means base profession and list disagree, so nothing is scanned (the next event retries).
	local line = ns.SkillLineOf(base.professionID, base.professionName)
	local mine, matched, foreign = {}, 0, 0
	for _, recipeID in ipairs(ids) do
		local recipeLine = ns.RecipeSkillLine(recipeID)
		if recipeLine == nil then
			mine[#mine + 1] = recipeID
		elseif recipeLine == line then
			mine[#mine + 1] = recipeID
			matched = matched + 1
		else
			foreign = foreign + 1
		end
	end
	if foreign > 0 and matched == 0 then
		return nil, "mismatch"
	end
	ids = mine
	local profs = ns.charDB.professions
	-- An entry the skill refresh (#65) made before the window was ever opened, under another key of
	-- the same skill line, is taken over so the profession is not listed twice.
	if not profs[base.professionID] then
		for otherID, other in pairs(profs) do
			if ns.SkillLineOf(otherID, other.name) == line and next(other.recipes or {}) == nil then
				profs[otherID] = nil
				other.recipes = {}
				profs[base.professionID] = other
				break
			end
		end
	end
	local prof = profs[base.professionID] or { recipes = {} }
	profs[base.professionID] = prof
	-- Learned since the last scan (#107): only against a scan that read recipes, so the first scan
	-- of a profession doesn't list everything known as new.
	local after = next(prof.recipes) ~= nil and prof.scannedAt or nil
	prof.name = base.professionName
	prof.skill = base.skillLevel or prof.skill
	prof.maxSkill = base.maxSkillLevel or prof.maxSkill
	prof.icon = ns.ProfessionIconFromClient(base.professionName) or prof.icon
	prof.scannedAt = time and time() or nil

	for _, recipeID in ipairs(ids) do
		local info = SafeCall(C_TradeSkillUI.GetRecipeInfo, recipeID)
		if info and not info.isDummyRecipe then
			local recipe = prof.recipes[recipeID] or {}
			local was = recipe.learned
			recipe.name = info.name or recipe.name
			recipe.icon = info.icon or recipe.icon
			recipe.learned = info.learned and true or false
			if after and recipe.learned and not was then
				ns.NoteLearned(recipeID, "scan", prof.scannedAt, after, line)
			end
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
local pending, retried = false, false
local function RequestScan()
	if pending then
		return
	end
	pending = true
	local function run()
		pending = false
		local _, why = ns.ScanProfession()
		if why == "mismatch" and not retried and C_Timer and C_Timer.After then
			retried = true -- one retry for a window that was still switching; later events retry too
			pending = true
			C_Timer.After(1, function()
				pending = false
				ns.ScanProfession()
			end)
		elseif why ~= "mismatch" then
			retried = false
		end
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

-- A recipe learned (pattern used, trainer), window open or not (#107): logged with the time, and the
-- cached recipe marked learned so the profit view and the snapshot show it before the next scan.
-- Whether Forever fires this for every way of learning is an in-game check (docs/ingame-checks.md).
ns.On("NEW_RECIPE_LEARNED", function(_, recipeID)
	if not (ns.charDB and type(recipeID) == "number") then
		return
	end
	local line = ns.RecipeLine(recipeID)
	ns.NoteLearned(recipeID, "event", time(), nil, line)
	for professionID, prof in pairs(ns.charDB.professions or {}) do
		local recipe = prof.recipes and prof.recipes[recipeID]
		if recipe and not recipe.learned and (line == nil or ns.SkillLineOf(professionID) == line) then
			recipe.learned = true
			ns.Notify("RECIPES_CHANGED", professionID)
		end
	end
end)

-- Skill, max skill, name and icon of every profession the character has (primary, secondary,
-- gathering, Fishing), from the client's profession list (#65): no window needed, so learning Expert
-- or skilling Fishing shows at once. Recipes are not touched; they still come from the window. A
-- profession not cached yet gets an entry with no recipes (no tab: tabs need recipes). Returns true
-- when something changed; then PROFESSIONS_CHANGED is sent.
local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function CachedKey(profs, line)
	for professionID, prof in pairs(profs) do
		if ns.SkillLineOf(professionID, prof.name) == line then
			return professionID
		end
	end
end

function ns.RefreshProfessionSkills()
	if not (ns.charDB and GetProfessions and GetProfessionInfo) then
		return false
	end
	local profs = ns.charDB.professions
	local indices = { GetProfessions() }
	local changed = false
	for i = 1, 6 do -- primary 1, primary 2, archaeology, fishing, cooking, first aid; nil where none
		local index = indices[i]
		if index then
			local ok, name, icon, skill, maxSkill, _, _, skillLine = pcall(GetProfessionInfo, index)
			if ok and name and skillLine and not (Secret(name) or Secret(skill) or Secret(maxSkill) or Secret(skillLine))
				and ns.IsProfessionEntry(skillLine, name) then
				local line = ns.SkillLineOf(skillLine, name)
				local key = CachedKey(profs, line)
				if not key then
					key = line
					profs[key] = { recipes = {} }
					changed = true
				end
				local prof = profs[key]
				prof.recipes = prof.recipes or {}
				local new = { name = name, icon = icon, skill = skill, maxSkill = maxSkill }
				for field, value in pairs(new) do
					if prof[field] ~= value then
						prof[field] = value
						changed = true
					end
				end
			end
		end
	end
	if changed then
		ns.Notify("PROFESSIONS_CHANGED")
	end
	return changed
end

ns.On("PLAYER_LOGIN", function()
	ns.RefreshProfessionSkills()
end)
ns.On("SKILL_LINES_CHANGED", function()
	ns.RefreshProfessionSkills()
end)

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
-- The client's professionID is already the parent skill line (165 for Leatherworking, seen in game),
-- which works on every client language. The English name map is only a fallback for other IDs.
local KNOWN_SKILL_LINES = {}
for _, id in pairs(ns.ProfessionSkillLines or {}) do
	KNOWN_SKILL_LINES[id] = true
end
for id in pairs(ns.GATHERING) do
	KNOWN_SKILL_LINES[id] = true
end
-- One profession can sit under two skill line IDs: the First Aid recipe items require line 2942, the
-- recipes themselves sit in 129 (#31, #25). Both are First Aid.
local LINE_ALIASES = { [2942] = 129 }
function ns.SkillLineOf(professionID, name)
	if KNOWN_SKILL_LINES[professionID] then
		return professionID
	end
	if LINE_ALIASES[professionID] then
		return LINE_ALIASES[professionID]
	end
	local prof = ns.charDB and ns.charDB.professions[professionID]
	name = name or (prof and prof.name)
	local byName = name and ns.ProfessionSkillLines and ns.ProfessionSkillLines[name]
	return byName or professionID
end

-- Skill line of a recipe from the bundled client data (nil when the data doesn't know the recipe).
function ns.RecipeSkillLine(recipeID)
	local data = ns.RecipeData and ns.RecipeData[recipeID]
	local line = data and data.skillLine
	return line and (LINE_ALIASES[line] or line) or nil
end

-- Does this recipe belong to this cached profession? Unknown recipes pass: nothing is guessed.
function ns.RecipeBelongs(professionID, recipeID)
	local line = ns.RecipeSkillLine(recipeID)
	return line == nil or line == ns.SkillLineOf(professionID)
end

-- Skill line of a recipe: bundled data first, else the cached profession that lists it.
function ns.RecipeLine(recipeID)
	local line = ns.RecipeSkillLine(recipeID)
	if line then
		return line
	end
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.recipes[recipeID] then
			return ns.SkillLineOf(professionID)
		end
	end
	local rec = ns.db and ns.db.trainer[recipeID]
	return rec and rec.line or nil
end

-- Login clean-up (#44): a recipe filed under a profession it doesn't belong to moves to the cached
-- profession that owns it (kept there if that one already has it), otherwise it is dropped. Entries
-- with no name and no recipes (the "?" 0/0 tab) go, and so does every entry under skill line 0 or with
-- an empty name (#78). Recorded crafts (db.skillups) are not touched.
function ns.CleanProfessions()
	local profs = ns.charDB and ns.charDB.professions
	if not profs then
		return 0
	end
	local moves, changed = {}, 0
	for professionID, prof in pairs(profs) do
		for recipeID in pairs(prof.recipes or {}) do
			if not ns.RecipeBelongs(professionID, recipeID) then
				moves[#moves + 1] = { from = professionID, recipeID = recipeID }
			end
		end
	end
	for _, m in ipairs(moves) do
		local recipe = profs[m.from].recipes[m.recipeID]
		profs[m.from].recipes[m.recipeID] = nil
		local line = ns.RecipeSkillLine(m.recipeID)
		for targetID, target in pairs(profs) do
			if targetID ~= m.from and ns.SkillLineOf(targetID) == line then
				target.recipes = target.recipes or {}
				target.recipes[m.recipeID] = target.recipes[m.recipeID] or recipe
				break
			end
		end
		changed = changed + 1
	end
	for professionID, prof in pairs(profs) do
		if professionID == 0 or prof.name == "" or (prof.name == nil and next(prof.recipes or {}) == nil) then
			profs[professionID] = nil
			changed = changed + 1
		end
	end
	if changed > 0 then
		ns.Notify("RECIPES_CHANGED")
	end
	return changed
end
ns.Listen("DB_READY", ns.CleanProfessions)

-- Reagents and output from bundled data. Output false in the data means "no item" (enchants).
function ns.BundledRecipe(recipeID)
	local data = ns.RecipeData and ns.RecipeData[recipeID]
	if not data then
		return nil
	end
	return data.reagents, data.output or nil, data.output == false
end

-- Reagents and output a trainer showed for this recipe (#83, Trainer.lua): first-hand client data.
function ns.RecordedRecipe(recipeID)
	local rec = ns.db and ns.db.trainer[recipeID]
	if not (rec and rec.reagents) then
		return nil
	end
	return rec.reagents, rec.output, rec.noItemOutput or false
end

-- Recipe data when the profession window gave none: bundled data first, else recorded at a trainer.
-- Fourth return: "bundled" | "recorded".
function ns.RecipeFallback(recipeID)
	local reagents, output, noItem = ns.BundledRecipe(recipeID)
	if reagents then
		return reagents, output, noItem, "bundled"
	end
	reagents, output, noItem = ns.RecordedRecipe(recipeID)
	if reagents then
		return reagents, output, noItem, "recorded"
	end
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
ns.BundledName = BundledName

-- How a recipe is learned. Two sources, both verified:
--   1. the trainer window, recorded in game (db.trainer)
--   2. ns.SourceData (issue #11). skill and item come from client DB2 (Data/Sources.lua, generated by
--      tools/gen_sources.py). Vendors, drops, quests and trainer fee still come from wowhead.com/forever or
--      Veli's manual entry and are not bundled yet.
-- Schema of ns.SourceData[recipeID]:
--   { skill = required skill, item = recipe item ID,
--     trainer = { fee = copper },
--     vendors = { { name, zone, faction = "A"|"H"|nil, price = copper, currency = "Merchant's Favor" } },
--     drops = { { name, zone, chance = percent } }, world = true,
--     quests = { { name, faction } } }
-- Nothing is estimated: missing fields stay missing.
local function Trainer(recipeID)
	local seen = ns.db and ns.db.trainer[recipeID]
	if seen then
		return seen.fee, seen.required
	end
	local data = ns.SourceData and ns.SourceData[recipeID]
	if data and data.trainer then
		return data.trainer.fee, data.skill
	end
end

-- Bundled data merged with what you saw in game (SourceRecorder.lua): recorded > manual entry > QuestieDB.
local function SourceEntry(recipeID)
	if ns.Sources then
		return ns.Sources.Merged(recipeID)
	end
	return ns.SourceData and ns.SourceData[recipeID]
end

-- Status of a recipe for this character, and the skill it needs:
--   "known" | "trainable" | "vendor" | "drop" | "quest" | "unlearned" (source not known yet)
-- Second return: required skill (nil if unknown). Third: skill too low.
function ns.RecipeStatus(prof, recipeID, recipe)
	if recipe.learned then
		return "known"
	end
	local skill = prof.skill or 0
	local _, required = Trainer(recipeID)
	if required then
		return "trainable", required, required > skill
	end
	local data = SourceEntry(recipeID)
	if data then
		local status = data.vendors and "vendor" or data.quests and "quest" or (data.drops or data.world) and "drop" or "unlearned"
		return status, data.skill, data.skill and data.skill > skill or false
	end
	return "unlearned"
end

-- Cost to learn: trainer fee, else vendor price (gold), else the recipe item's AH price.
-- Returns copper and "trainer" | "vendor" | "auction", or nil. For "auction" a third value: the price
-- label at the profit house and basis (#40), e.g. "typical · Horde AH".
function ns.LearnCost(recipeID)
	local fee = Trainer(recipeID)
	if fee then
		return fee, "trainer"
	end
	local data = SourceEntry(recipeID)
	if not data then
		return nil
	end
	for _, v in ipairs(data.vendors or {}) do
		if v.price and not v.currency and not v.costs then
			return v.price, "vendor"
		end
	end
	if data.item then
		local quote = ns.AuctionQuote(data.item)
		if quote then
			return quote.copper, "auction", quote.label
		end
	end
end

-- Where to get a recipe, as short lines for the Learn view ("Trainer", "Vendor: Name (Zone)", ...).
-- Own faction and neutral vendors first; the other faction's are kept and tagged.
function ns.RecipeWhere(recipeID)
	local lines = {}
	if Trainer(recipeID) then
		local seen = ns.db and ns.db.trainer[recipeID]
		lines[#lines + 1] = { kind = "trainer", text = "Trainer", origin = seen and "seen" or "static",
			label = seen and "seen by you" or "bundled data" }
	end
	local data = SourceEntry(recipeID)
	if data then
		local faction = UnitFactionGroup and UnitFactionGroup("player")
		local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
		local own, other = {}, {}
		for _, v in ipairs(data.vendors or {}) do
			local cost = v.currency and ("%s %s"):format(v.price or "?", v.currency) or (v.price and ns.FormatMoney(v.price))
			if v.costs then
				local parts = { v.price and ns.FormatMoney(v.price) or nil }
				for _, c in ipairs(v.costs) do
					parts[#parts + 1] = ("%d %s"):format(c.amount, c.name)
				end
				cost = table.concat(parts, " + ")
			end
			local text = ("Vendor: %s%s%s"):format(v.name or "?", v.zone and (" (" .. v.zone .. ")") or "", cost and (" - " .. cost) or "")
			local isOwn = not v.faction or mine == nil or v.faction == mine
			table.insert(isOwn and own or other, { kind = "vendor", text = text, faction = v.faction, own = isOwn,
				origin = v.seen and "seen" or "static", label = ns.Sources and ns.Sources.Label(v) or "bundled data" })
		end
		for _, e in ipairs(own) do
			lines[#lines + 1] = e
		end
		for _, e in ipairs(other) do
			lines[#lines + 1] = e
		end
		for _, d in ipairs(data.drops or {}) do
			local chance = d.chance and (" %.1f%%"):format(d.chance) or ""
			local name = d.name or (d.key and d.key:gsub(":", " #")) or "?"
			lines[#lines + 1] = { kind = "drop", text = ("Drop: %s%s%s"):format(name, d.zone and (" (" .. d.zone .. ")") or "", chance),
				origin = d.seen and "seen" or "static", label = ns.Sources and ns.Sources.Label(d) or "bundled data" }
		end
		if data.world then
			lines[#lines + 1] = { kind = "drop", text = "World drop", origin = "static", label = data.src or "bundled data" }
		end
		for _, q in ipairs(data.quests or {}) do
			lines[#lines + 1] = { kind = "quest", text = "Quest: " .. (q.name or "?"), origin = q.seen and "seen" or "static",
				label = ns.Sources and ns.Sources.Label(q) or "bundled data" }
		end
		if data.item then
			local quote = ns.AuctionQuote(data.item)
			if quote then
				lines[#lines + 1] = { kind = "auction", text = "AH: " .. ns.FormatMoney(quote.copper), origin = "auction", label = quote.label }
			end
		end
	end
	return lines
end

local function IsSpellKnown(recipeID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, recipeID)
		return ok and known or false
	end
	return false
end

-- Marks cached recipes learned right after training, without reopening the profession window.
local function MarkLearned(recipeID)
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		local recipe = prof.recipes[recipeID]
		if recipe and not recipe.learned then
			recipe.learned = true
			return true
		end
	end
	return false
end

function ns.RefreshLearned(recipeID)
	local changed = false
	if recipeID then
		changed = MarkLearned(recipeID)
	end
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		for id, recipe in pairs(prof.recipes) do
			if not recipe.learned and IsSpellKnown(id) then
				recipe.learned, changed = true, true
			end
		end
	end
	if changed then
		ns.Notify("RECIPES_CHANGED")
	end
	return changed
end

ns.On("NEW_RECIPE_LEARNED", function(_, recipeID)
	ns.RefreshLearned(recipeID)
end)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", function(_, spellID)
	ns.RefreshLearned(type(spellID) == "number" and spellID or nil)
end)
ns.On("TRAINER_UPDATE", function()
	ns.RefreshLearned()
end)

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
	local learnCost, learnSource, learnLabel
	if not recipe.learned then
		learnCost, learnSource, learnLabel = ns.LearnCost(recipeID)
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
	result.learnSource, result.learnLabel = learnSource, learnLabel
	result.source = recipe.source
	result.difficulty = recipe.difficulty
	result.skillColor = ns.SkillUpColor(recipe, tooLow)
	result.noItemOutput = recipe.noItemOutput or result.noItemOutput
	result.outputItemID = recipe.output and recipe.output.itemID
	result.outputQuantity = recipe.output and recipe.output.quantity
	result.bundledOnly = recipe.bundledOnly
	result.recordedInGame = recipe.recordedInGame -- recipe data from a trainer window (#83)
	-- Skill-up thresholds come from the bundled data only; a recipe it lacks has none (never guessed).
	result.thresholdsUnknown = not (ns.RecipeThresholds and ns.RecipeThresholds(recipeID)) or nil
	return result
end

-- Recipes this character knows that make an item (#47: craft-or-buy for intermediate reagents):
-- { { reagents, output, recipeID }, ... }. Only learned recipes of this character (decision 1 on #47);
-- reagents from the profession window, else the bundled data. Rebuilt when recipes change.
local makers
function ns.KnownRecipesFor(itemID)
	if not makers then
		makers = {}
		for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
			for recipeID, recipe in pairs(prof.recipes) do
				if recipe.learned then
					local reagents, output = recipe.reagents, recipe.output
					if not reagents then
						reagents, output = ns.RecipeFallback(recipeID)
					end
					local id = output and output.itemID
					if id and reagents then
						makers[id] = makers[id] or {}
						table.insert(makers[id], { recipeID = recipeID, reagents = reagents, output = output })
					end
				end
			end
		end
	end
	return makers[itemID]
end
ns.Listen("RECIPES_CHANGED", function()
	makers = nil
end)
ns.Listen("DB_READY", function()
	makers = nil
end)

-- Rows for the profit table of one profession. Cached recipes come first-hand from the client;
-- with includeUnlearned, bundled recipes of the same skill line that the client never listed are
-- added too, so "what could I learn" works even if the client only lists learned recipes, and so are
-- recipes a trainer showed that neither lists (#83, marked recordedInGame).
-- view: the window view asking ("profit" | "learn" | "level"); it picks the reagent cost basis (#47).
function ns.BuildRows(professionID, includeUnlearned, view)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	if not prof then
		return {}
	end
	local prices = ns.ReagentPrices(view or "profit")
	local rows = {}
	for recipeID, recipe in pairs(prof.recipes) do
		if (recipe.learned or includeUnlearned) and ns.RecipeBelongs(professionID, recipeID) then
			if not recipe.reagents then
				local reagents, output, noItem, origin = ns.RecipeFallback(recipeID)
				if reagents then
					recipe = setmetatable({ reagents = reagents, output = output, noItemOutput = noItem or nil,
						recordedInGame = origin == "recorded" or nil }, { __index = recipe })
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
	if includeUnlearned then
		local skillLine = ns.SkillLineOf(professionID)
		for recipeID, rec in pairs(ns.db and ns.db.trainer or {}) do
			if rec.line == skillLine and rec.reagents and not prof.recipes[recipeID]
				and not (ns.RecipeData and ns.RecipeData[recipeID]) and not IsSpellKnown(recipeID) then
				local output = rec.output
				local icon = rec.icon or (output and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(output.itemID))
				table.insert(rows, MakeRow(prof, recipeID, {
					name = rec.name or ("Recipe #" .. recipeID),
					icon = icon,
					learned = false,
					reagents = rec.reagents,
					output = output,
					noItemOutput = rec.noItemOutput or nil,
					recordedInGame = true,
				}, prices))
			end
		end
	end
	return rows
end
