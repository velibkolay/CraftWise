-- Character snapshot for Claude (issue #63): what this character is, where it stands, what it wears,
-- knows, holds and is questing on, written to the account-wide CraftWiseDB.snapshots["<realm>-<name> <surname>"]
-- so a Claude session can read it from WTF/Account/<account>/SavedVariables/CraftWise.lua.
-- Written by `/craftwise snapshot` and on PLAYER_LOGOUT (logout, /reload, quit); the file on disk is
-- only current after one of those. Overwritten each time, no history. Field reference: docs/snapshot.md.
--
-- Rules: only client data about this character (no chat, no other players). Every section is read in
-- its own pcall; a section whose API the client doesn't have is left out and named in `skipped`, a
-- section that fails is named in `errors`. Nothing is expanded, collapsed or selected: quest log and
-- reputation are read as the client lists them right now (rows under collapsed headers are not
-- listed by the API and are reported as such, never guessed).
local _, ns = ...

local S = {}
ns.Snapshot = S

S.VERSION = 1

-- Equipment slots in paper-doll order. A slot the client doesn't know is skipped.
local SLOTS = {
	{ "HEADSLOT", "Head" }, { "NECKSLOT", "Neck" }, { "SHOULDERSLOT", "Shoulder" }, { "BACKSLOT", "Back" },
	{ "CHESTSLOT", "Chest" }, { "SHIRTSLOT", "Shirt" }, { "TABARDSLOT", "Tabard" }, { "WRISTSLOT", "Wrist" },
	{ "HANDSSLOT", "Hands" }, { "WAISTSLOT", "Waist" }, { "LEGSSLOT", "Legs" }, { "FEETSLOT", "Feet" },
	{ "FINGER0SLOT", "Ring 1" }, { "FINGER1SLOT", "Ring 2" }, { "TRINKET0SLOT", "Trinket 1" },
	{ "TRINKET1SLOT", "Trinket 2" }, { "MAINHANDSLOT", "Main hand" }, { "SECONDARYHANDSLOT", "Off hand" },
	{ "RANGEDSLOT", "Ranged" },
}

-- Secondary professions by parent skill line: Cooking, First Aid, Fishing. The rest are primary.
local SECONDARY = { [185] = true, [129] = true, [356] = true }

-- Happiness values of C_PetInfo.GetPetHappiness, as Blizzard's Forever UI names them
-- (Blizzard_FrameXML/PetHappiness.lua: Attitude = { Mad = 1, Neutral = 2, Happy = 3 }).
local HAPPINESS = { [1] = "unhappy", [2] = "content", [3] = "happy" }

local function Round(v, places)
	if type(v) ~= "number" then
		return nil
	end
	local m = 10 ^ (places or 4)
	return math.floor(v * m + 0.5) / m
end

-- "<realm>-<name> <surname>", the key the ledger and the fishing log use too (#77).
function S.Key()
	return ns.CharKey()
end

----------------------------------------------------------------------------------------------------
-- Sections. Each returns its table, or nil plus the reason it was skipped.
----------------------------------------------------------------------------------------------------

function S.Character()
	if not (UnitName and UnitLevel) then
		return nil, "UnitName/UnitLevel not available"
	end
	-- name and surname apart (#77); surname missing for a character without one.
	local _, name, surname = ns.CharName()
	-- Level, XP, rested and money: live, except at logout, where the client returns 0 and the values
	-- last seen in the world are used (#123, ns.PlayerValue in Core.lua); missing when none was seen.
	local Value = ns.PlayerValue
	local c = { name = name, surname = surname, level = Value("level", UnitLevel("player")) }
	c.realm = GetRealmName and GetRealmName() or nil
	if UnitFactionGroup then
		c.faction = UnitFactionGroup("player")
	end
	if UnitRace then
		c.race = UnitRace("player")
	end
	if UnitClass then
		c.class = UnitClass("player")
	end
	if UnitXP and UnitXPMax then
		c.xp, c.xpMax = Value("xp", UnitXP("player")), Value("xpMax", UnitXPMax("player"))
	end
	if GetXPExhaustion then
		local rested = GetXPExhaustion() -- nil = no rested XP (Blizzard's ExpBar.lua reads it so)
		if ns.loggingOut then
			c.rested = Value("rested", rested)
		else
			c.rested = rested or 0
		end
	end
	if GetMoney then
		c.money = Value("money", GetMoney())
	end
	-- guild: name; false = not in a guild; missing = the client hasn't sent the guild yet.
	if IsInGuild and not IsInGuild() then
		c.guild = false
	elseif GetGuildInfo then
		c.guild = GetGuildInfo("player")
	end
	return c
end

function S.Location()
	local l = {}
	if GetRealZoneText then
		l.zone = GetRealZoneText()
	end
	-- "" = the client names no subzone where the character stands (kept, #78).
	if GetSubZoneText then
		local sub = GetSubZoneText()
		l.subzone = type(sub) == "string" and sub or nil
	end
	-- The text over the minimap (subzone, else zone), as Blizzard's Forever Minimap_Update shows it.
	if GetMinimapZoneText then
		local text = GetMinimapZoneText()
		l.minimapZone = type(text) == "string" and text ~= "" and text or nil
	end
	if IsResting then
		l.resting = IsResting() and true or false
	end
	if C_Map and C_Map.GetBestMapForUnit then
		local mapID = C_Map.GetBestMapForUnit("player")
		l.mapID = mapID
		if mapID and C_Map.GetMapInfo then
			local info = C_Map.GetMapInfo(mapID)
			l.map = info and info.name or nil
		end
		-- Position on that map, 0..1 from the top left; the client gives none in instances.
		if mapID and C_Map.GetPlayerMapPosition then
			local pos = C_Map.GetPlayerMapPosition(mapID, "player")
			if pos then
				local x, y = pos.x, pos.y
				if (x == nil or y == nil) and pos.GetXY then
					x, y = pos:GetXY()
				end
				l.x, l.y = Round(x), Round(y)
			end
		end
	end
	if next(l) == nil then
		return nil, "zone and map APIs not available"
	end
	return l
end

function S.Equipment()
	if not (GetInventorySlotInfo and GetInventoryItemID) then
		return nil, "GetInventorySlotInfo/GetInventoryItemID not available"
	end
	local U = ns.Upgrades or {}
	local out, empty = {}, {}
	for _, s in ipairs(SLOTS) do
		local ok, slot = pcall(GetInventorySlotInfo, s[1])
		if ok and slot then
			local itemID = GetInventoryItemID("player", slot)
			if itemID then
				local e = { slot = s[2], id = itemID }
				e.link = GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil
				e.ilvl = U.ItemLevel and U.ItemLevel(e.link or itemID) or nil
				local stats = ns.ItemStats and ns.ItemStats(e.link or itemID) or nil
				if stats then
					e.armor = stats.RESISTANCE0_NAME or 0 -- the stats list only what the item has
					local main = U.MainStatsText and U.MainStatsText(stats)
					e.stats = main ~= "" and main or nil
				end
				if GetInventoryItemDurability then
					local cur, max = GetInventoryItemDurability(slot)
					if cur and max then
						e.dur, e.durMax = cur, max
					end
				end
				out[#out + 1] = e
			else
				empty[#empty + 1] = s[2]
			end
		end
	end
	return { items = out, empty = empty }
end

-- From the profession cache (Recipes.lua: recipes filled when a profession window opens; skill, max
-- skill, name and icon refreshed from the client's list at login and on SKILL_LINES_CHANGED, #65)
-- plus the client's profession list read now (GetProfessions/GetProfessionInfo, no scan), which also
-- has gathering professions and Fishing. `scanned` = when the recipe cache was last filled.
function S.Professions()
	local list, byLine = {}, {}
	for professionID, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		local line = ns.SkillLineOf and ns.SkillLineOf(professionID) or professionID
		local known = {}
		for recipeID, r in pairs(prof.recipes or {}) do
			if r.learned and type(recipeID) == "number" then
				known[#known + 1] = recipeID
			end
		end
		-- Known recipe IDs (#107), ascending, as one "id,id,..." string: a character with every recipe of
		-- two crafts known lists over 1,000, and names for all of them would not fit the snapshot's size
		-- (measured in snapshot_spec). Names of recently learned recipes are in `recipesLearned`.
		table.sort(known)
		local p = { name = prof.name, skill = prof.skill, max = prof.maxSkill, line = line,
			kind = SECONDARY[line] and "secondary" or "primary", recipesKnown = #known, scanned = prof.scannedAt,
			known = known[1] and table.concat(known, ",") or nil }
		-- Only skill from the client's list (#65 refresh), no profession window read yet.
		if not prof.scannedAt and next(prof.recipes or {}) == nil then
			p.cached, p.recipesKnown = false, nil
		end
		list[#list + 1] = p
		byLine[line] = p
	end
	if GetProfessions and GetProfessionInfo then
		local indices = { GetProfessions() }
		for i = 1, 6 do
			local index = indices[i]
			if index then
				local name, _, skill, max, _, _, line = GetProfessionInfo(index)
				line = line and ns.SkillLineOf and ns.SkillLineOf(line, name) or line
				local p = line and byLine[line]
				if p then
					p.skill, p.max = skill or p.skill, max or p.max
				elseif name then
					p = { name = name, skill = skill, max = max, line = line,
						kind = SECONDARY[line] and "secondary" or "primary", cached = false }
					list[#list + 1] = p
					if line then
						byLine[line] = p
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "primary"
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return list
end

-- Recipes learned recently (#107), newest first, from CraftWiseCharDB.learned (Recipes.lua):
-- { id, name, profession, t, how = "event" | "scan", after }. how "scan": learned between after and t.
function S.RecipesLearned()
	if not ns.charDB then
		return nil, "character data not loaded"
	end
	local log = ns.charDB.learned or {} -- empty: none seen learned since this was installed
	local profByLine = {}
	for professionID, prof in pairs(ns.charDB.professions or {}) do
		profByLine[ns.SkillLineOf and ns.SkillLineOf(professionID) or professionID] = prof
	end
	local out = {}
	for i = #log, 1, -1 do
		local e = log[i]
		local prof = e.line and profByLine[e.line]
		local cached = prof and prof.recipes and prof.recipes[e.id]
		out[#out + 1] = { id = e.id, t = e.t, how = e.how, after = e.after,
			name = (cached and cached.name) or (e.line and ns.BundledName and ns.BundledName(e.line, e.id)) or nil,
			profession = prof and prof.name or nil }
	end
	return out
end

function S.Quests()
	local Q = C_QuestLog
	if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo) then
		return nil, "C_QuestLog.GetNumQuestLogEntries/GetInfo not available"
	end
	local shown, numQuests = Q.GetNumQuestLogEntries()
	local list, collapsed, hidden = {}, {}, 0
	local header
	for index = 1, shown or 0 do
		local info = Q.GetInfo(index)
		if info then
			if info.isHeader then
				header = info.title
				if info.isCollapsed then
					collapsed[#collapsed + 1] = info.title
				end
			elseif info.isHidden then
				hidden = hidden + 1
			elseif info.questID then
				local id = info.questID
				local q = { id = id, title = info.title, level = info.level, zone = header }
				if info.suggestedGroup and info.suggestedGroup > 0 then
					q.group = info.suggestedGroup
				end
				if Q.IsComplete then
					q.complete = Q.IsComplete(id) and true or false
				end
				if Q.IsFailed then
					q.failed = Q.IsFailed(id) and true or false
				end
				if Q.GetQuestObjectives then
					local objs = {}
					for _, o in ipairs(Q.GetQuestObjectives(id) or {}) do
						objs[#objs + 1] = { text = o.text, have = o.numFulfilled, need = o.numRequired, done = o.finished and true or false }
					end
					q.objectives = objs
				end
				list[#list + 1] = q
			end
		end
	end
	-- inLog: quests the client counts; read: quests listed here. They differ when headers are
	-- collapsed (those quests are not listed) or hidden quests are counted.
	return { list = list, inLog = numQuests, read = #list, collapsedHeaders = collapsed, hidden = hidden }
end

function S.Reputations()
	local R = C_Reputation
	if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then
		return nil, "C_Reputation.GetNumFactions/GetFactionDataByIndex not available"
	end
	local list, collapsed = {}, {}
	local header
	for index = 1, R.GetNumFactions() or 0 do
		local f = R.GetFactionDataByIndex(index)
		if f then
			if not f.isHeader or f.isHeaderWithRep then
				list[#list + 1] = {
					id = f.factionID, name = f.name, header = header,
					reaction = f.reaction, standing = f.reaction and _G["FACTION_STANDING_LABEL" .. f.reaction] or nil,
					value = f.currentStanding, min = f.currentReactionThreshold, max = f.nextReactionThreshold,
					atWar = f.atWarWith or nil,
				}
			end
			if f.isHeader then
				header = f.name -- the rows below sit under the header listed last
				if f.isCollapsed then
					collapsed[#collapsed + 1] = f.name
				end
			end
		end
	end
	return { list = list, collapsedHeaders = collapsed }
end

-- Hunter pet while it is summoned; missing otherwise (dismissed, dead, stabled, not a hunter).
function S.Pet()
	if not HasPetUI then
		return nil, "HasPetUI not available"
	end
	local hasUI, isHunterPet = HasPetUI()
	if not (hasUI and isHunterPet) then
		return nil, "no hunter pet out"
	end
	local p = { name = UnitName and UnitName("pet") or nil, level = UnitLevel and UnitLevel("pet") or nil }
	if UnitCreatureFamily then
		p.family = UnitCreatureFamily("pet")
	end
	if C_PetInfo and C_PetInfo.GetPetHappiness then
		local happiness = C_PetInfo.GetPetHappiness()
		if happiness then
			p.happiness, p.happinessText = happiness, HAPPINESS[happiness]
		end
	end
	if C_PetInfo and C_PetInfo.GetPetLoyalty then
		p.loyalty = C_PetInfo.GetPetLoyalty()
	end
	return p
end

local function CopyCounts(items, names)
	local out = {}
	for itemID, n in pairs(items or {}) do
		out[itemID] = n
		if names[itemID] == nil and ns.ItemInfoNow then
			names[itemID] = (ns.ItemInfoNow(itemID)) or nil
		end
	end
	return out
end

-- What Holdings.lua counts (#49): bags read live, bank and mail as last seen (t = when).
function S.Holdings()
	local H = ns.Holdings
	if not (H and H.Carried) then
		return nil, "Holdings not loaded"
	end
	local names = {}
	local h = { bags = CopyCounts(H.Carried(), names), names = names }
	local store = ns.charDB and ns.charDB.holdings or {}
	if store.bank then
		h.bank = { t = store.bank.t, items = CopyCounts(store.bank.items, names) }
	end
	if store.mail then
		h.mail = { t = store.mail.t, mails = store.mail.mails, items = CopyCounts(store.mail.items, names) }
	end
	local notCounted = {}
	if not store.bank then
		notCounted[#notCounted + 1] = "bank (not opened yet)"
	end
	if not store.mail then
		notCounted[#notCounted + 1] = "mail (mailbox not opened yet)"
	end
	if H.HasAccountBank and H.HasAccountBank() then
		notCounted[#notCounted + 1] = "account bank (not read)"
	end
	h.notCounted = notCounted
	return h
end

-- Ledger totals (#46): today and since the last reset, no entries.
function S.Ledger()
	local L = ns.Ledger
	if not (L and L.Summary) then
		return nil, "Ledger not loaded"
	end
	local out = {}
	for _, view in ipairs({ "today", "reset" }) do
		local s = L.Summary(view)
		if s then
			out[view] = { since = s.since, startMoney = s.startMoney, money = s.money, change = s.change,
				spent = s.spent, received = s.received, net = s.net, other = s.other }
		end
	end
	if next(out) == nil then
		return nil, "no ledger for this character yet"
	end
	return out
end

-- Known flight paths (#68): recorded when a flight master's map opens (FlightPaths.lua).
function S.FlightPaths()
	if not (ns.FlightPaths and ns.FlightPaths.Snapshot) then
		return nil, "FlightPaths not loaded"
	end
	return ns.FlightPaths.Snapshot()
end

-- Fishing log per zone (#69): catches, value per catch, items, last 90 days.
function S.Fishing()
	if not (ns.Fishing and ns.Fishing.SnapshotSummary) then
		return nil, "Fishing not loaded"
	end
	return ns.Fishing.SnapshotSummary()
end

-- Fishing zones by value per catch (#88): own catches or the local reference, top zones only.
function S.FishingZones()
	if not (ns.FishingZones and ns.FishingZones.SnapshotRanking) then
		return nil, "FishingZones not loaded"
	end
	return ns.FishingZones.SnapshotRanking()
end

-- Auctions (#81): listed, sold awaiting mail with expected gold, returning by mail, uncertain.
function S.Auctions()
	if not (ns.Auctions and ns.Auctions.SnapshotSummary) then
		return nil, "Auctions not loaded"
	end
	return ns.Auctions.SnapshotSummary()
end

-- Market data (#90): per house the last full scan and item counts; prices and names stay in
-- CraftWiseMarketDB (account-wide, same file), so they aren't copied into every character's snapshot.
function S.Market()
	if not (ns.Market and ns.Market.SnapshotSummary) then
		return nil, "Market not loaded"
	end
	return ns.Market.SnapshotSummary()
end

-- Waylaid crates by cost per Merchant's Favor (#91), and the Favor balance with the merchants that take it.
function S.Crates()
	if not (ns.Crates and ns.Crates.SnapshotCrates) then
		return nil, "Crates not loaded"
	end
	return ns.Crates.SnapshotCrates()
end

function S.Favor()
	if not (ns.Crates and ns.Crates.SnapshotFavor) then
		return nil, "Crates not loaded"
	end
	return ns.Crates.SnapshotFavor()
end

S.SECTIONS = {
	{ "char", S.Character }, { "location", S.Location }, { "equipment", S.Equipment },
	{ "professions", S.Professions }, { "recipesLearned", S.RecipesLearned }, { "quests", S.Quests }, { "reputations", S.Reputations },
	{ "pet", S.Pet }, { "holdings", S.Holdings }, { "ledger", S.Ledger }, { "flightPaths", S.FlightPaths },
	{ "fishing", S.Fishing }, { "fishingZones", S.FishingZones }, { "auctions", S.Auctions },
	{ "market", S.Market },
	{ "crates", S.Crates }, { "favor", S.Favor },
}

----------------------------------------------------------------------------------------------------
-- Build and save
----------------------------------------------------------------------------------------------------

function S.Build()
	local snap = { v = S.VERSION, t = time() }
	local skipped, errors = {}, {}
	for _, section in ipairs(S.SECTIONS) do
		local key, fn = section[1], section[2]
		local ok, result, why = pcall(fn)
		if not ok then
			errors[key] = tostring(result)
		elseif result == nil then
			skipped[key] = why or "not available"
		else
			snap[key] = result
		end
	end
	if next(skipped) then
		snap.skipped = skipped
	end
	if next(errors) then
		snap.errors = errors
	end
	return snap
end

-- Builds and stores the snapshot. Returns it and its key, or nil before the DB is loaded.
function S.Save()
	if not ns.db then
		return nil
	end
	local key = S.Key()
	if not key then
		return nil
	end
	local snap = S.Build()
	ns.db.snapshots = ns.db.snapshots or {}
	ns.db.snapshots[key] = snap
	return snap, key
end

-- /craftwise snapshot
function S.Slash()
	local ok, snap = pcall(S.Save)
	if not (ok and snap) then
		ns.Print("snapshot failed: " .. tostring(ok and "character not loaded yet" or snap))
		return
	end
	ns.Print("snapshot saved, /reload to write it to disk")
	local missing = {}
	for key in pairs(snap.skipped or {}) do
		missing[#missing + 1] = key
	end
	for key in pairs(snap.errors or {}) do
		missing[#missing + 1] = key .. " (error)"
	end
	if #missing > 0 then
		table.sort(missing)
		ns.Print("not in this snapshot: " .. table.concat(missing, ", "))
	end
end

-- Logout, /reload and quit: refresh so the file on disk is current. Never raises. The client returns 0
-- for money and XP by now; char and ledger use the values last seen in the world (#123).
ns.On("PLAYER_LOGOUT", function()
	pcall(S.Save)
end)
