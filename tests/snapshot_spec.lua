-- Issue #63: character snapshot for Claude (/craftwise snapshot, refresh on PLAYER_LOGOUT).
local NOW = os.time({ year = 2026, month = 11, day = 10, hour = 20 })

-- The client APIs the snapshot reads that the shared stub doesn't have. Quest log and reputation
-- list rows like the client: children of a collapsed header are not listed.
local function ClientExtras(stub)
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.names.pet, stub.names.target = "Veli", "Grimfang", "Someone Else"
	stub.realm = "Forever-EU"
	stub.level = 24
	function UnitRace() return "Orc", "Orc", 2 end
	function UnitClass() return "Hunter", "HUNTER", 3 end
	function UnitXP() return 12000 end
	function UnitXPMax() return 18600 end
	stub.rested = 4200
	function GetXPExhaustion() return stub.rested end
	stub.guild = "Velikopter"
	function IsInGuild() return stub.guild ~= nil end
	function GetGuildInfo() return stub.guild, "Member", 3 end
	function IsResting() return true end
	stub.zone, stub.subzone = "The Barrens", "The Crossroads"
	C_Map = {
		GetBestMapForUnit = function() return 1413 end,
		GetMapInfo = function(id) return { mapID = id, name = ({ [1413] = "The Barrens", [1414] = "Kalimdor", [1415] = "Eastern Kingdoms" })[id] } end,
		GetPlayerMapPosition = function() return { x = 0.523456, y = 0.30111 } end,
	}
	-- Equipment links and durability.
	function GetInventoryItemLink(_, slot)
		local id = GetInventoryItemID("player", slot)
		return id and ("|cff1eff00|Hitem:" .. id .. "::::::::24:255::::::::::|h[" .. stub.items[id].name .. "]|h|r")
	end
	stub.durability = {}
	function GetInventoryItemDurability(slot) local d = stub.durability[slot]; if d then return d[1], d[2] end end
	-- Quest log rows: { header = true, title, collapsed } or { questID, title, level, group, complete, failed, hidden, objectives }
	stub.questLog = {}
	local function shownRows()
		local out, skip = {}, false
		for _, r in ipairs(stub.questLog) do
			if r.header then
				out[#out + 1] = r
				skip = r.collapsed
			elseif not skip then
				out[#out + 1] = r
			end
		end
		return out
	end
	local function questByID(id)
		for _, r in ipairs(stub.questLog) do if r.questID == id then return r end end
	end
	stub.uiChanges = 0
	local function changed() stub.uiChanges = stub.uiChanges + 1 end
	C_QuestLog = {
		GetNumQuestLogEntries = function()
			local n = 0
			for _, r in ipairs(stub.questLog) do if not r.header then n = n + 1 end end
			return #shownRows(), n
		end,
		GetInfo = function(i)
			local r = shownRows()[i]
			if not r then return nil end
			return { title = r.title, questLogIndex = i, questID = r.questID or 0, level = r.level or 0,
				suggestedGroup = r.group or 0, isHeader = r.header or false, isCollapsed = r.collapsed or false,
				isHidden = r.hidden or false }
		end,
		IsComplete = function(id) return questByID(id).complete or false end,
		IsFailed = function(id) return questByID(id).failed or false end,
		GetQuestObjectives = function(id) return questByID(id).objectives end,
		ExpandQuestHeader = changed, CollapseQuestHeader = changed, SetSelectedQuest = changed,
	}
	-- Reputation rows: FactionData as the client returns it.
	stub.factions = {}
	local function shownFactions()
		local out, skip = {}, false
		for _, f in ipairs(stub.factions) do
			if f.isHeader and not f.isChild then
				out[#out + 1] = f
				skip = f.isCollapsed
			elseif not skip then
				out[#out + 1] = f
			end
		end
		return out
	end
	C_Reputation = {
		GetNumFactions = function() return #shownFactions() end,
		GetFactionDataByIndex = function(i) return shownFactions()[i] end,
		ExpandFactionHeader = changed, CollapseFactionHeader = changed, ExpandAllFactionHeaders = changed,
		SetSelectedFaction = changed,
	}
	for i, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
		_G["FACTION_STANDING_LABEL" .. i] = label
	end
	-- Flight master map (#68): stub.taxi = { mapID, nodes = TaxiNodeInfo list, mapNodes = MapTaxiNodeInfo list }.
	stub.taxi = { mapID = 1414, nodes = {}, mapNodes = {} }
	function GetTaxiMapID() return stub.taxi.mapID end
	C_TaxiMap = {
		GetAllTaxiNodes = function(mapID) assert(mapID == stub.taxi.mapID, "taxi map ID"); return stub.taxi.nodes end,
		GetTaxiNodesForMap = function(mapID) assert(mapID == stub.taxi.mapID, "taxi map ID"); return stub.taxi.mapNodes end,
	}
	-- Hunter pet.
	stub.pet = true
	function HasPetUI() return stub.pet, stub.pet end
	function UnitCreatureFamily() return "Wolf", 1 end
	C_PetInfo = { GetPetHappiness = function() return 3, 125, 20 end, GetPetLoyalty = function() return "Loyalty Level 3" end }
end

local function Load()
	local ns, stub = LoadAddon()
	ClientExtras(stub)
	stub.money = 123456
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function Faction(id, name, reaction, value, lo, hi, extra)
	local f = { factionID = id, name = name, reaction = reaction, currentStanding = value,
		currentReactionThreshold = lo, nextReactionThreshold = hi, isHeader = false, isChild = false,
		isCollapsed = false, isHeaderWithRep = false, atWarWith = false }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end
local function Header(name, extra)
	return Faction(0, name, 0, 0, 0, 0, { isHeader = true, isCollapsed = extra and extra.collapsed or false })
end

-- TaxiNodeInfo as C_TaxiMap.GetAllTaxiNodes returns it (position is a Vector2DMixin: x, y, GetXY).
local function TaxiNode(id, name, x, y, state, extra)
	local n = { nodeID = id, name = name, state = state, slotIndex = id, textureKit = "", useSpecialIcon = false,
		isMapLayerTransition = false, position = { x = x, y = y, GetXY = function(self) return self.x, self.y end } }
	for k, v in pairs(extra or {}) do n[k] = v end
	return n
end
-- MapTaxiNodeInfo as C_TaxiMap.GetTaxiNodesForMap returns it.
local function MapNode(id, name, undiscovered)
	return { nodeID = id, name = name, isUndiscovered = undiscovered, faction = 1, atlasName = "", textureKit = "",
		position = { x = 0.5, y = 0.5 } }
end

-- A small character: two gear slots, a profession, two quests, three reputations, bags, bank and mail.
local function SmallCharacter(ns, stub)
	stub.items[6070] = { name = "Wolfshead Helm", level = 30, stats = { RESISTANCE0_NAME = 120, ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 4 } }
	stub.items[2361] = { name = "Battleworn Hammer", level = 2, stats = {} }
	stub.equipped.HEADSLOT, stub.equipped.MAINHANDSLOT = 6070, 2361
	stub.durability[1] = { 40, 50 }
	stub.items[2318] = { name = "Light Leather" }
	stub.items[2589] = { name = "Linen Cloth" }
	stub.items[4306] = { name = "Silk Cloth" }
	stub.bags[0] = { { itemID = 2318, stackCount = 12 }, { itemID = 2589, stackCount = 5 } }
	ns.charDB.holdings = { bank = { t = NOW - 3600, items = { [4306] = 20 } }, mail = { t = NOW - 60, items = { [2589] = 1 }, mails = 2 } }
	stub.profession = { id = 165, name = "Leatherworking", skill = 120, max = 150, recipes = {
		[1] = { info = { name = "Light Armor Kit", learned = true }, schematic = stub.Schematic({ { 2318, 1 } }, 2304) },
		[2] = { info = { name = "Not Yet", learned = false }, schematic = stub.Schematic({ { 2318, 2 } }, 2305) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.profession.skill = 125 -- skilled up since the scan; the client's profession list has it
	stub.questLog = {
		{ header = true, title = "The Barrens" },
		{ questID = 845, title = "The Zhevra", level = 14, objectives = {
			{ text = "Zhevra Hooves: 2/4", numFulfilled = 2, numRequired = 4, finished = false, type = "item" } } },
		{ questID = 855, title = "Centaur Bracers", level = 16, group = 0, complete = true, objectives = {} },
		{ header = true, title = "Durotar", collapsed = true },
		{ questID = 812, title = "Need for a Cure", level = 15, failed = true, objectives = {} },
	}
	stub.factions = {
		Header("Horde"),
		Faction(76, "Orgrimmar", 6, 9500, 9000, 21000),
		Faction(530, "Darkspear Trolls", 5, 3500, 3000, 9000),
		Header("Other", { collapsed = true }),
		Faction(470, "Ratchet", 4, 100, 0, 3000),
	}
	stub.taxi.nodes = {
		TaxiNode(25, "Crossroads, The Barrens", 0.5165, 0.5512, 0),
		TaxiNode(23, "Orgrimmar, Durotar", 0.5531, 0.3634, 1),
	}
	stub.taxi.mapNodes = { MapNode(25, "Crossroads, The Barrens", false), MapNode(23, "Orgrimmar, Durotar", false),
		MapNode(80, "Ratchet, The Barrens", true) }
	stub.Fire("TAXIMAP_OPENED", 1)
end

it("builds every section from the client", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	local snap = ns.Snapshot.Build()
	eq(snap.v, 1); eq(snap.t, NOW)
	eq(snap.skipped, nil, "skipped"); eq(snap.errors, nil, "errors")
	local c = snap.char
	eq(c.name, "Veli"); eq(c.realm, "Forever-EU"); eq(c.faction, "Horde"); eq(c.race, "Orc"); eq(c.class, "Hunter")
	eq(c.level, 24); eq(c.xp, 12000); eq(c.xpMax, 18600); eq(c.rested, 4200); eq(c.money, 123456); eq(c.guild, "Velikopter")
	local l = snap.location
	eq(l.zone, "The Barrens"); eq(l.subzone, "The Crossroads"); eq(l.mapID, 1413); eq(l.map, "The Barrens")
	eq(l.x, 0.5235); eq(l.y, 0.3011); eq(l.resting, true)
	local head = snap.equipment.items[1]
	eq(head.slot, "Head"); eq(head.id, 6070); eq(head.ilvl, 30); eq(head.armor, 120); eq(head.stats, "+5 AGI +4 STA")
	eq(head.dur, 40); eq(head.durMax, 50)
	assert(head.link:find("|Hitem:6070:", 1, true), "link")
	local weapon = snap.equipment.items[2]
	eq(weapon.slot, "Main hand"); eq(weapon.armor, 0); eq(weapon.stats, nil); eq(weapon.dur, nil)
	eq(#snap.equipment.empty, 16) -- 18 stub slots, 2 worn; Tabard isn't a stub slot and is skipped
	local p = snap.professions[1]
	eq(p.name, "Leatherworking"); eq(p.kind, "primary"); eq(p.skill, 125); eq(p.max, 150); eq(p.recipesKnown, 1)
	eq(p.scanned ~= nil, true)
	local q = snap.quests
	eq(q.inLog, 3); eq(q.read, 2); eq(q.collapsedHeaders[1], "Durotar"); eq(q.hidden, 0)
	eq(q.list[1].id, 845); eq(q.list[1].zone, "The Barrens"); eq(q.list[1].level, 14); eq(q.list[1].complete, false)
	eq(q.list[1].objectives[1].have, 2); eq(q.list[1].objectives[1].need, 4); eq(q.list[1].objectives[1].done, false)
	eq(q.list[1].objectives[1].text, "Zhevra Hooves: 2/4")
	eq(q.list[2].complete, true); eq(q.list[2].group, nil); eq(q.list[2].failed, false)
	local r = snap.reputations
	eq(#r.list, 2); eq(r.collapsedHeaders[1], "Other")
	eq(r.list[1].name, "Orgrimmar"); eq(r.list[1].standing, "Honored"); eq(r.list[1].value, 9500)
	eq(r.list[1].min, 9000); eq(r.list[1].max, 21000); eq(r.list[1].header, "Horde")
	eq(snap.pet.name, "Grimfang"); eq(snap.pet.family, "Wolf"); eq(snap.pet.level, 24)
	eq(snap.pet.happiness, 3); eq(snap.pet.happinessText, "happy"); eq(snap.pet.loyalty, "Loyalty Level 3")
	local h = snap.holdings
	eq(h.bags[2318], 12); eq(h.bank.items[4306], 20); eq(h.bank.t, NOW - 3600); eq(h.mail.mails, 2); eq(h.mail.items[2589], 1)
	eq(h.names[4306], "Silk Cloth"); eq(#h.notCounted, 0)
	eq(snap.ledger.today.money, 123456); eq(snap.ledger.reset.net, 0)
	eq(snap.ledger.today.items, nil) -- totals only, no entries
end)

it("/craftwise snapshot stores it account-wide under realm-name", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	local printed, realPrint = {}, print
	print = function(msg) printed[#printed + 1] = msg end
	SlashCmdList.CRAFTWISE("snapshot")
	print = realPrint
	local snap = CraftWiseDB.snapshots["Forever-EU-Veli"]
	assert(snap, "stored under realm-name")
	eq(snap.char.name, "Veli")
	assert(printed[1]:find("snapshot saved, /reload to write it to disk", 1, true), printed[1])
	eq(printed[2], nil)
end)

it("refreshes on logout and overwrites the old snapshot", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	ns.Snapshot.Save()
	stub.clock, stub.money = NOW + 600, 200000
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots["Forever-EU-Veli"]
	eq(snap.t, NOW + 600); eq(snap.char.money, 200000)
	local n = 0
	for _ in pairs(CraftWiseDB.snapshots) do n = n + 1 end
	eq(n, 1)
end)

it("skips what the client doesn't have, without errors", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	C_QuestLog, C_Reputation, HasPetUI, C_Map = nil, nil, nil, nil
	GetInventoryItemDurability, GetGuildInfo, GetXPExhaustion, C_PetInfo = nil, nil, nil, nil
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots["Forever-EU-Veli"]
	eq(snap.errors, nil)
	assert(snap.skipped.quests and snap.skipped.reputations and snap.skipped.pet, "skipped sections named")
	eq(snap.quests, nil); eq(snap.char.rested, nil); eq(snap.char.guild, nil) -- in a guild, name unknown
	eq(snap.location.mapID, nil); eq(snap.location.zone, "The Barrens")
	eq(snap.equipment.items[1].dur, nil); eq(snap.equipment.items[1].ilvl, 30)
	local printed, realPrint = {}, print
	print = function(msg) printed[#printed + 1] = msg end
	ns.Snapshot.Slash()
	print = realPrint
	assert(printed[2] and printed[2]:find("pet, quests, reputations", 1, true), tostring(printed[2]))
end)

it("a failing section is named in errors and the rest is still saved", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	C_QuestLog.GetInfo = function() error("boom") end
	stub.Fire("PLAYER_LOGOUT") -- must not raise
	local snap = CraftWiseDB.snapshots["Forever-EU-Veli"]
	assert(snap.errors.quests:find("boom", 1, true))
	eq(snap.char.name, "Veli"); eq(snap.reputations.list[1].name, "Orgrimmar")
end)

it("no pet out, not in a guild, no rested XP, nothing seen in bank or mail", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	stub.pet, stub.guild, stub.rested = false, nil, nil
	ns.charDB.holdings = {}
	local snap = ns.Snapshot.Build()
	eq(snap.pet, nil); eq(snap.skipped.pet, "no hunter pet out")
	eq(snap.char.guild, false); eq(snap.char.rested, 0)
	eq(snap.holdings.bank, nil); eq(#snap.holdings.notCounted, 2)
end)

it("reads without changing quest log or reputation UI state", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	ns.Snapshot.Build()
	eq(stub.uiChanges, 0)
end)

it("professions: refreshed cap after Expert, Fishing without a window (#65)", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub) -- Leatherworking scanned at 120/150, client list now 125/150
	stub.profession = nil -- window closed; the client's list holds Leatherworking and Fishing
	local client = {
		[1] = { "Leatherworking", 136247, 125, 225, 165 },
		[4] = { "Fishing", 136245, 149, 150, 356 },
	}
	GetProfessions = function() return 1, nil, nil, 4 end
	GetProfessionInfo = function(i) local p = client[i]; if p then return p[1], p[2], p[3], p[4], 0, 0, p[5] end end
	stub.Fire("SKILL_LINES_CHANGED")
	GetProfessions = nil -- only the cache now: the snapshot shows what the refresh stored
	local snap = ns.Snapshot.Build()
	eq(#snap.professions, 2)
	local lw, fishing = snap.professions[1], snap.professions[2]
	eq(lw.name, "Leatherworking"); eq(lw.skill, 125); eq(lw.max, 225); eq(lw.recipesKnown, 1); eq(lw.cached, nil)
	eq(fishing.name, "Fishing"); eq(fishing.kind, "secondary"); eq(fishing.skill, 149); eq(fishing.max, 150)
	eq(fishing.line, 356); eq(fishing.cached, false); eq(fishing.recipesKnown, nil); eq(fishing.scanned, nil)
end)

it("location: subzone and the minimap's zone text; no subzone is stored as \"\" (#78)", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	local l = ns.Snapshot.Build().location
	eq(l.subzone, "The Crossroads"); eq(l.minimapZone, "The Crossroads")
	stub.subzone = ""
	l = ns.Snapshot.Build().location
	eq(l.subzone, "", "kept, not dropped"); eq(l.minimapZone, "The Barrens")
	GetSubZoneText, GetMinimapZoneText = nil, nil
	l = ns.Snapshot.Build().location
	eq(l.subzone, nil); eq(l.minimapZone, nil); eq(l.zone, "The Barrens")
end)

it("records known flight paths when a flight master map opens, per character with time (#68)", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub) -- opened the Crossroads flight master on Kalimdor (1414)
	local kalimdor = CraftWiseCharDB.flightPaths[1414]
	assert(kalimdor, "stored per character")
	eq(kalimdor.t, NOW); eq(kalimdor.map, "Kalimdor"); eq(#kalimdor.nodes, 2)
	local xroads, org = kalimdor.nodes[1], kalimdor.nodes[2] -- sorted by name
	eq(xroads.id, 25); eq(xroads.name, "Crossroads, The Barrens"); eq(xroads.x, 0.5165); eq(xroads.y, 0.5512)
	eq(xroads.state, "current"); eq(xroads.current, true); eq(xroads.known, true); eq(xroads.transition, nil)
	eq(org.id, 23); eq(org.state, "reachable"); eq(org.current, nil); eq(org.known, true)
	-- Ratchet is on the map but undiscovered: the flight master doesn't list it, nothing is added
	for _, n in ipairs(kalimdor.nodes) do assert(n.id ~= 80, "undiscovered node not recorded") end
	-- Eastern Kingdoms flight master: its own entry; Kalimdor stays as last seen
	stub.clock = NOW + 3600
	stub.taxi.mapID = 1415
	stub.taxi.nodes = { TaxiNode(11, "Undercity, Tirisfal", 0.42, 0.33, 0), TaxiNode(12, "Tarren Mill, Hillsbrad", 0.6, 0.4, 2) }
	stub.taxi.mapNodes = {} -- no discovered flag from the map list: `known` stays missing
	stub.Fire("TAXIMAP_OPENED", 1)
	local ek = CraftWiseCharDB.flightPaths[1415]
	eq(ek.t, NOW + 3600); eq(ek.map, "Eastern Kingdoms"); eq(ek.nodes[1].name, "Tarren Mill, Hillsbrad")
	eq(ek.nodes[1].state, "unreachable"); eq(ek.nodes[1].known, nil); eq(ek.nodes[2].current, true)
	eq(CraftWiseCharDB.flightPaths[1414].t, NOW)
	-- back at a Kalimdor flight master with a new node learned: Kalimdor is overwritten
	stub.clock = NOW + 7200
	stub.taxi.mapID = 1414
	stub.taxi.nodes = {
		TaxiNode(25, "Crossroads, The Barrens", 0.5165, 0.5512, 0),
		TaxiNode(23, "Orgrimmar, Durotar", 0.5531, 0.3634, 1),
		TaxiNode(80, "Ratchet, The Barrens", 0.63, 0.37, 1),
	}
	stub.taxi.mapNodes = { MapNode(25, "Crossroads, The Barrens", false), MapNode(23, "Orgrimmar, Durotar", false),
		MapNode(80, "Ratchet, The Barrens", false) }
	stub.Fire("TAXIMAP_OPENED", 1)
	kalimdor = CraftWiseCharDB.flightPaths[1414]
	eq(kalimdor.t, NOW + 7200); eq(#kalimdor.nodes, 3); eq(kalimdor.nodes[3].name, "Ratchet, The Barrens")
	eq(kalimdor.nodes[3].known, true)
	-- snapshot: one entry per map, by map ID
	local snap = ns.Snapshot.Build()
	local maps = snap.flightPaths.maps
	eq(#maps, 2); eq(maps[1].mapID, 1414); eq(maps[1].map, "Kalimdor"); eq(maps[1].t, NOW + 7200); eq(#maps[1].nodes, 3)
	eq(maps[2].mapID, 1415); eq(maps[2].nodes[2].name, "Undercity, Tirisfal")
	assert(maps[1].nodes ~= kalimdor.nodes, "snapshot holds a copy")
end)

it("flight paths: nothing listed, no map ID or no API keeps what was seen, without errors (#68)", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	stub.clock = NOW + 60
	stub.taxi.nodes = {}
	stub.Fire("TAXIMAP_OPENED", 1)
	eq(CraftWiseCharDB.flightPaths[1414].t, NOW); eq(#CraftWiseCharDB.flightPaths[1414].nodes, 2)
	eq(CraftWiseDB.debug.taxi.why, "flight master listed no nodes")
	stub.taxi.mapID = nil
	stub.Fire("TAXIMAP_OPENED", 1)
	eq(CraftWiseDB.debug.taxi.why, "no taxi map ID")
	C_TaxiMap.GetAllTaxiNodes = function() error("boom") end
	stub.taxi.mapID = 1414
	stub.Fire("TAXIMAP_OPENED", 1)
	C_TaxiMap, GetTaxiMapID = nil, nil
	stub.Fire("TAXIMAP_OPENED", 1)
	eq(CraftWiseDB.debug.taxi.why, "C_TaxiMap.GetAllTaxiNodes/GetTaxiMapID not available")
	eq(#CraftWiseCharDB.flightPaths[1414].nodes, 2)
	-- a character that never opened a flight master: section skipped with the reason
	CraftWiseCharDB.flightPaths = nil
	local snap = ns.Snapshot.Build()
	eq(snap.flightPaths, nil); eq(snap.skipped.flightPaths, "no flight master map opened yet"); eq(snap.errors, nil)
end)

-- SavedVariables as the client writes them: one ["key"] = value per line, tab-indented.
local function Serialize(v, indent, out)
	indent = indent or ""
	out = out or {}
	if type(v) ~= "table" then
		out[#out + 1] = type(v) == "string" and ("%q"):format(v) or tostring(v)
		return out
	end
	out[#out + 1] = "{\n"
	local n = #v
	for i = 1, n do
		out[#out + 1] = indent .. "\t"
		Serialize(v[i], indent .. "\t", out)
		out[#out + 1] = ", -- [" .. i .. "]\n"
	end
	for k, val in pairs(v) do
		if not (type(k) == "number" and k >= 1 and k <= n) then
			out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "] = "
			Serialize(val, indent .. "\t", out)
			out[#out + 1] = ",\n"
		end
	end
	out[#out + 1] = indent .. "}"
	return out
end

it("a full character stays small and holds nothing about other players", function()
	local ns, stub = Load()
	SmallCharacter(ns, stub)
	-- Every slot worn, with stats and durability.
	local slot = 0
	for _, name in ipairs({ "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "SHIRTSLOT", "CHESTSLOT", "WAISTSLOT", "LEGSSLOT",
		"FEETSLOT", "WRISTSLOT", "HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT", "TRINKET0SLOT", "TRINKET1SLOT", "BACKSLOT",
		"MAINHANDSLOT", "SECONDARYHANDSLOT", "RANGEDSLOT" }) do
		slot = slot + 1
		local id = 10000 + slot
		stub.items[id] = { name = "Some Long Item Name of the Eagle " .. slot, level = 25,
			stats = { RESISTANCE0_NAME = 80, ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_INTELLECT_SHORT = 2 } }
		stub.equipped[name] = id
		stub.durability[slot] = { 55, 75 }
	end
	-- Full bags (5 bags, 80 different items), 100 bank items, 16 mails with attachments.
	stub.bags = {}
	local id = 20000
	for bag = 0, 4 do
		stub.bags[bag] = {}
		for s = 1, 16 do
			id = id + 1
			stub.items[id] = { name = "Bag Item Number " .. id }
			stub.bags[bag][s] = { itemID = id, stackCount = 20 }
		end
	end
	local bank, mail = {}, {}
	for i = 1, 100 do
		bank[30000 + i] = 15
		stub.items[30000 + i] = { name = "Bank Item Number " .. i }
	end
	for i = 1, 16 do mail[40000 + i] = 1; stub.items[40000 + i] = { name = "Mail Item " .. i } end
	ns.charDB.holdings = { bank = { t = NOW, items = bank }, mail = { t = NOW, items = mail, mails = 16 } }
	-- Full quest log: 25 quests in 5 zones, two objectives each.
	stub.questLog = {}
	for z = 1, 5 do
		stub.questLog[#stub.questLog + 1] = { header = true, title = "Zone Number " .. z }
		for i = 1, 5 do
			local qid = z * 100 + i
			stub.questLog[#stub.questLog + 1] = { questID = qid, title = "A Fairly Long Quest Title " .. qid, level = 20 + i,
				group = i == 5 and 3 or 0, objectives = {
					{ text = "Bloodscalp Tusks: 4/10", numFulfilled = 4, numRequired = 10, finished = false },
					{ text = "Gather the Venom Sacs: 2/6", numFulfilled = 2, numRequired = 6, finished = false } } }
		end
	end
	-- 50 reputations under 5 headers.
	stub.factions = {}
	for hdr = 1, 5 do
		stub.factions[#stub.factions + 1] = Header("Faction Group " .. hdr)
		for i = 1, 10 do
			stub.factions[#stub.factions + 1] = Faction(hdr * 100 + i, "Some Faction Name " .. i, 4, 1500, 0, 3000)
		end
	end
	-- Flight paths on both continents, 30 each.
	for m, mapID in ipairs({ 1414, 1415 }) do
		stub.taxi.mapID, stub.taxi.nodes, stub.taxi.mapNodes = mapID, {}, {}
		for i = 1, 30 do
			local nodeID = m * 100 + i
			stub.taxi.nodes[i] = TaxiNode(nodeID, "Some Flight Point Name, Some Zone " .. nodeID, 0.123456, 0.654321, i == 1 and 0 or 1)
			stub.taxi.mapNodes[i] = MapNode(nodeID, "x", false)
		end
		stub.Fire("TAXIMAP_OPENED", 1)
	end
	stub.Fire("PLAYER_LOGOUT")
	local snap = CraftWiseDB.snapshots["Forever-EU-Veli"]
	eq(snap.errors, nil); eq(snap.skipped, nil)
	eq(#snap.flightPaths.maps, 2); eq(#snap.flightPaths.maps[2].nodes, 30)
	eq(#snap.equipment.items, 18); eq(#snap.quests.list, 25); eq(#snap.reputations.list, 50)
	local text = "CraftWiseDB = " .. table.concat(Serialize({ snapshots = CraftWiseDB.snapshots }))
	print(("       full character snapshot: %d bytes as SavedVariables"):format(#text))
	assert(#text < 64 * 1024, "snapshot too large: " .. #text)
	eq(text:find("Someone Else", 1, true), nil)
end)
