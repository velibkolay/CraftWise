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

-- How a recipe is learned. Two sources, both verified:
--   1. the trainer window, recorded in game (db.trainer)
--   2. ns.SourceData, a bundled dataset from Wowhead or manual entry (issue #11). Not shipped yet.
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

local function SourceEntry(recipeID)
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
-- Returns copper and "trainer" | "vendor" | "auction", or nil.
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
		if v.price and not v.currency then
			return v.price, "vendor"
		end
	end
	if data.item then
		local ah = ns.GetAuctionPrice(data.item)
		if ah then
			return ah, "auction"
		end
	end
end

-- Where to get a recipe, as short lines for the Learn view ("Trainer", "Vendor: Name (Zone)", ...).
-- Own faction and neutral vendors first; the other faction's are kept and tagged.
function ns.RecipeWhere(recipeID)
	local lines = {}
	if Trainer(recipeID) then
		lines[#lines + 1] = { kind = "trainer", text = "Trainer" }
	end
	local data = SourceEntry(recipeID)
	if data then
		local faction = UnitFactionGroup and UnitFactionGroup("player")
		local mine = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
		local own, other = {}, {}
		for _, v in ipairs(data.vendors or {}) do
			local cost = v.currency and ("%s %s"):format(v.price or "?", v.currency) or (v.price and ns.FormatMoney(v.price))
			local text = ("Vendor: %s%s%s"):format(v.name or "?", v.zone and (" (" .. v.zone .. ")") or "", cost and (" - " .. cost) or "")
			local isOwn = not v.faction or mine == nil or v.faction == mine
			table.insert(isOwn and own or other, { kind = "vendor", text = text, faction = v.faction, own = isOwn })
		end
		for _, e in ipairs(own) do
			lines[#lines + 1] = e
		end
		for _, e in ipairs(other) do
			lines[#lines + 1] = e
		end
		for _, d in ipairs(data.drops or {}) do
			local chance = d.chance and (" %.1f%%"):format(d.chance) or ""
			lines[#lines + 1] = { kind = "drop", text = ("Drop: %s%s%s"):format(d.name or "?", d.zone and (" (" .. d.zone .. ")") or "", chance) }
		end
		if data.world then
			lines[#lines + 1] = { kind = "drop", text = "World drop" }
		end
		for _, q in ipairs(data.quests or {}) do
			lines[#lines + 1] = { kind = "quest", text = "Quest: " .. (q.name or "?") }
		end
		if data.item then
			local ah = ns.GetAuctionPrice(data.item)
			if ah then
				lines[#lines + 1] = { kind = "auction", text = "AH: " .. ns.FormatMoney(ah) }
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
