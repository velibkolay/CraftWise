-- Class trainer spells (issue #259): what a class trainer teaches, recorded first-hand, a planner over it
-- and the data behind "Train all". Nothing here is bundled: every service comes from the trainer window
-- the player opened on that class.
--
--   * Record (CS.Record, on TRAINER_SHOW / TRAINER_UPDATE, only at a trainer of type General, the class
--     and weapon trainers; profession trainers stay with Trainer.lua): per class, account-wide,
--     ns.db.classSpells[classFile] = { at, npc, visitLevel, services = { ["Name|Rank"] = rec } } with
--     rec = { name, rank, icon, level, cost, kind, id, skill, skillRank, abilities, at, npc }.
--       level      the required level: GetTrainerServiceInfo's fourth return, which Blizzard's Forever trainer
--                  window reads as `reqLevel` (Blizzard_TrainerUI.lua, ClassTrainerFrame_InitServiceButton)
--       cost       what the trainer showed this visit. The client's figure already carries the player's
--                  reputation discount; the base cost is not readable, so nothing is derived from it
--       kind       "available" | "unavailable" | "used" (already known) as of the visit
--       id         the taught spell, from the service tooltip when the client gives it (nil when secret)
--       abilities  names of required abilities (GetTrainerServiceAbilityReq)
--     A trainer lists what fits the level band, so the record grows as the player levels and visits.
--   * Planner (CS.Plan): what this character can learn now, at higher levels, and the total cost. Pure
--     over the record, the character's level and a "known" test (C_SpellBook.IsSpellKnown with the spell
--     id, else what the trainer showed as known).
--   * Train all (CS.TrainPlan, CS.TrainAll): every service the trainer marks available that the money
--     covers, bought with BuyTrainerService, one purchase per service, started by one click on the
--     confirmation (UI/TrainAll.lua). Nothing runs without that click.
--   * Cross-check (CS.CrossCheck): differences between the record and What's Training?'s tables, read
--     through its WT_API at run time when it is installed (never copied).
local _, ns = ...

local CS = {}
ns.ClassSpells = CS

CS.MAX_CONFIRM_LINES = 12

local trainerOpen = false

local function Store()
	ns.db.classSpells = ns.db.classSpells or {}
	return ns.db.classSpells
end

function CS.ClassFile()
	local _, file = UnitClass("player")
	return file
end

-- The class and weapon trainers (type General); profession trainers (Tradeskills) and pet trainers are
-- not recorded here.
function CS.IsClassTrainer()
	local trainerType = C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType()
	return trainerType ~= nil and Enum and Enum.TrainerType ~= nil and trainerType == Enum.TrainerType.General
end

function CS.TrainerOpen()
	return trainerOpen
end

-- The taught spell from the service tooltip, nil when the client gives none or hides it.
local function ServiceSpellID(index)
	if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
	local id = ok and data and data.id
	if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then
		return nil
	end
	return id
end

local function AbilityNames(index)
	if not (GetTrainerServiceNumAbilityReq and GetTrainerServiceAbilityReq) then
		return nil
	end
	local names = {}
	for i = 1, GetTrainerServiceNumAbilityReq(index) or 0 do
		local name = GetTrainerServiceAbilityReq(index, i)
		if type(name) == "string" and name ~= "" then
			names[#names + 1] = name
		end
	end
	return #names > 0 and names or nil
end

function CS.Key(name, rank)
	return name .. "|" .. (rank or "")
end

-- Reads the open class trainer into the record. Returns how many services were stored.
function CS.Record(event)
	if not (ns.db and GetNumTrainerServices and CS.IsClassTrainer()) then
		return 0
	end
	local file = CS.ClassFile()
	if not file then
		return 0
	end
	local okCount, count = pcall(GetNumTrainerServices)
	if not okCount or type(count) ~= "number" then
		return 0
	end
	local data = Store()[file]
	if not data then
		data = { services = {} }
		Store()[file] = data
	end
	local now = time and time() or nil
	local level = UnitLevel and UnitLevel("player") or nil
	local npc = UnitName and UnitName("npc") or nil
	local stored = 0
	for index = 1, count do
		local name, kind, icon, reqLevel, subText = GetTrainerServiceInfo(index)
		if type(name) == "string" and kind ~= "header" then
			local rank = type(subText) == "string" and subText ~= "" and subText or nil
			local key = CS.Key(name, rank)
			local rec = data.services[key] or {}
			local cost = GetTrainerServiceCost(index)
			local skill, skillRank = GetTrainerServiceSkillReq(index)
			rec.name, rec.rank, rec.icon, rec.kind = name, rank, icon, kind
			rec.level = type(reqLevel) == "number" and reqLevel or rec.level
			if type(cost) == "number" and (cost > 0 or kind ~= "used") then
				rec.cost = cost -- a known spell may show no price: keep what was seen before
			end
			rec.id = ServiceSpellID(index) or rec.id
			rec.skill = type(skill) == "string" and skill or nil
			rec.skillRank = rec.skill and skillRank or nil
			rec.abilities = AbilityNames(index)
			rec.at, rec.npc = now, npc
			data.services[key] = rec
			stored = stored + 1
		end
	end
	if stored > 0 then
		data.at, data.npc = now, npc
		data.visitLevel = math.max(data.visitLevel or 0, level or 0)
		ns.Notify("CLASSSPELLS_CHANGED")
	end
	return stored
end

----------------------------------------------------------------------------------------------------
-- Planner
----------------------------------------------------------------------------------------------------

-- Whether the player knows a recorded service: the spell when its id is recorded, else what the
-- trainer showed as already learned on the last visit.
function CS.IsKnown(rec)
	if rec.id and C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(rec.id) and true or false
	end
	return rec.kind == "used"
end

local function ByLevel(a, b)
	if (a.level or 0) ~= (b.level or 0) then
		return (a.level or 0) < (b.level or 0)
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	return (a.rank or "") < (b.rank or "")
end

-- What a character of `level` can learn from the record of its class.
--   { learnNow = {rec...}, later = {rec...}, known = {rec...}, total = copper of learnNow (priced ones),
--     unpriced = count of learnNow without a cost, visitLevel, at, npc, empty = true without a record }
-- known(rec) -> boolean; default CS.IsKnown.
function CS.Plan(data, level, known)
	known = known or CS.IsKnown
	local plan = { learnNow = {}, later = {}, known = {}, total = 0, unpriced = 0 }
	if not data or not data.services or next(data.services) == nil then
		plan.empty = true
		return plan
	end
	plan.visitLevel, plan.at, plan.npc = data.visitLevel, data.at, data.npc
	for key, rec in pairs(data.services) do
		local row = {}
		for k, v in pairs(rec) do
			row[k] = v
		end
		row.key = key
		if known(rec) then
			plan.known[#plan.known + 1] = row
		elseif (rec.level or 0) <= (level or 0) then
			plan.learnNow[#plan.learnNow + 1] = row
			if rec.cost then
				plan.total = plan.total + rec.cost
			else
				plan.unpriced = plan.unpriced + 1
			end
		else
			plan.later[#plan.later + 1] = row
		end
	end
	table.sort(plan.learnNow, ByLevel)
	table.sort(plan.later, ByLevel)
	table.sort(plan.known, ByLevel)
	return plan
end

-- The record of this character's class (nil before any visit).
function CS.Data()
	local file = CS.ClassFile()
	return file and ns.db and ns.db.classSpells and ns.db.classSpells[file] or nil
end

----------------------------------------------------------------------------------------------------
-- Train all
----------------------------------------------------------------------------------------------------

-- Reads the open trainer and decides what one click would buy: every service the client marks
-- "available" (level, skills and abilities are met), in list order, while the money lasts.
--   { lines = { { index, name, rank, cost } }, total, skipped = how many available ones the money
--     doesn't cover, money }   or nil, reason
function CS.TrainPlan()
	if not (trainerOpen and GetNumTrainerServices) then
		return nil, ns.L["Open a class trainer first"]
	end
	if not CS.IsClassTrainer() then
		return nil, ns.L["Train all works at class trainers"]
	end
	local money = GetMoney and GetMoney() or 0
	local plan = { lines = {}, total = 0, skipped = 0, money = money }
	local left = money
	for index = 1, GetNumTrainerServices() or 0 do
		local name, kind, _, _, subText = GetTrainerServiceInfo(index)
		if name and kind == "available" then
			local cost = GetTrainerServiceCost(index) or 0
			if cost <= left then
				left = left - cost
				plan.total = plan.total + cost
				plan.lines[#plan.lines + 1] = { index = index, name = name, rank = (type(subText) == "string" and subText ~= "") and subText or nil, cost = cost }
			else
				plan.skipped = plan.skipped + 1
			end
		end
	end
	if #plan.lines == 0 then
		return nil, plan.skipped > 0 and ns.L["You can't afford any of the available spells"] or ns.L["Nothing to learn at this trainer right now"], plan
	end
	return plan
end

-- The confirmation's lines: "Frostbolt Rank 2 · 1s 20c", at most CS.MAX_CONFIRM_LINES, then "+N more".
function CS.ConfirmLines(plan)
	local out = {}
	for i, line in ipairs(plan.lines) do
		if i > CS.MAX_CONFIRM_LINES then
			out[#out + 1] = (ns.L["+%d more"]):format(#plan.lines - CS.MAX_CONFIRM_LINES)
			break
		end
		out[#out + 1] = (line.rank and (line.name .. " " .. line.rank) or line.name) .. " · " .. (line.cost > 0 and ns.FormatCoins(line.cost) or ns.L["free"])
	end
	return out
end

-- Buys what the plan lists, each service re-read first (same name, still available, money left). From the
-- last service to the first, so a list that drops learned spells doesn't move the ones still to buy.
-- Returns the number bought, the copper spent and why it stopped early (nil when it did them all).
function CS.TrainAll(plan)
	if not (plan and BuyTrainerService) then
		return 0, 0, ns.L["Train all isn't available"]
	end
	local left = GetMoney and GetMoney() or 0
	local bought, spent = 0, 0
	for i = #plan.lines, 1, -1 do
		local line = plan.lines[i]
		if not trainerOpen then
			return bought, spent, ns.L["The trainer closed"]
		end
		local name, kind = GetTrainerServiceInfo(line.index)
		if name ~= line.name or kind ~= "available" then
			return bought, spent, ns.L["The trainer's list changed"]
		end
		if line.cost > left then
			return bought, spent, ns.L["Not enough money"]
		end
		BuyTrainerService(line.index)
		left = left - line.cost
		bought, spent = bought + 1, spent + line.cost
	end
	return bought, spent
end

----------------------------------------------------------------------------------------------------
-- Cross-check against What's Training?
----------------------------------------------------------------------------------------------------

local function Norm(name, rank)
	return ((name or "") .. "|" .. (rank or "")):lower()
end

-- The differences between the record (data) and What's Training?'s spells (WT_API.GetSpells()):
--   { differ = { text }, onlyWT = { text }, onlyOurs = { text }, matched = n }
-- Our figure is the cost the trainer showed (with the player's reputation discount); WT's `cost` is its own
-- price under the player's faction selection and `baseCost` its data file's. A cost differs when it
-- matches neither. WT spells above the highest level a visit covered, quest spells and tomes are left out:
-- the record can't have them.
function CS.CrossCheck(data, spells)
	local report = { differ = {}, onlyWT = {}, onlyOurs = {}, matched = 0 }
	local byId, byName = {}, {}
	for _, s in ipairs(spells or {}) do
		if type(s.id) == "number" then
			byId[s.id] = s
		end
		byName[Norm(s.name, s.subText)] = s
	end
	local used = {}
	local services = data and data.services or {}
	for _, rec in pairs(services) do
		local wt = (rec.id and byId[rec.id]) or byName[Norm(rec.name, rec.rank)]
		local label = rec.rank and (rec.name .. " " .. rec.rank) or rec.name
		if not wt then
			report.onlyOurs[#report.onlyOurs + 1] = label
		else
			used[wt] = true
			report.matched = report.matched + 1
			if rec.cost and wt.cost and rec.cost ~= wt.cost and rec.cost ~= wt.baseCost then
				report.differ[#report.differ + 1] = ("%s: cost recorded %s, What's Training? %s%s"):format(label,
					ns.FormatCoins(rec.cost), ns.FormatCoins(wt.cost),
					(wt.baseCost and wt.baseCost ~= wt.cost) and (" (base " .. ns.FormatCoins(wt.baseCost) .. ")") or "")
			end
			if rec.level and wt.level and rec.level > 1 and rec.level ~= wt.level then
				report.differ[#report.differ + 1] = ("%s: level recorded %d, What's Training? %d"):format(label, rec.level, wt.level)
			end
		end
	end
	local covered = data and data.visitLevel or 0
	for _, s in ipairs(spells or {}) do
		if not used[s] and not s.quest and not s.isItem and (s.level or 0) <= covered then
			local label = (s.subText and s.subText ~= "") and (s.name .. " " .. s.subText) or s.name
			report.onlyWT[#report.onlyWT + 1] = ("%s (level %d)"):format(label, s.level or 0)
		end
	end
	table.sort(report.differ)
	table.sort(report.onlyWT)
	table.sort(report.onlyOurs)
	return report
end

-- /craftwise trainercheck: prints the report when What's Training? is loaded and ready.
function CS.PrintCrossCheck()
	local api = _G["WT_API"]
	if not (api and api.GetSpells and api.IsReady and api.IsReady()) then
		ns.Print("trainercheck: What's Training? isn't loaded or isn't ready yet.")
		return nil
	end
	local data = CS.Data()
	if not data then
		ns.Print("trainercheck: nothing recorded for this class yet. Visit its trainer first.")
		return nil
	end
	local report = CS.CrossCheck(data, api.GetSpells())
	ns.Print(("trainercheck: %d recorded spells matched, %d differ, %d only in What's Training? (up to level %d), %d only recorded here"):format(
		report.matched, #report.differ, #report.onlyWT, data.visitLevel or 0, #report.onlyOurs))
	for _, group in ipairs({ report.differ, report.onlyWT, report.onlyOurs }) do
		for _, line in ipairs(group) do
			ns.Print("  " .. line)
		end
	end
	return report
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

-- Trainer.lua reads the window with every service type shown (it widens the filter for the read and puts
-- it back), on TRAINER_SHOW and on each TRAINER_UPDATE: the class record rides on that read.
local readTrainer = ns.RecordTrainer
function ns.RecordTrainer(event)
	local recorded = readTrainer(event)
	CS.Record(event)
	return recorded
end

ns.On("TRAINER_SHOW", function()
	trainerOpen = true
	ns.Notify("TRAINER_STATE")
end)
ns.On("TRAINER_CLOSED", function()
	trainerOpen = false
	ns.Notify("TRAINER_STATE")
end)
