-- Issue #77: the per-character key includes the Forever surname (ns.CharKey/ns.CharName), and the
-- old "<realm>-<name>" entries (ledger, snapshot, fishing log) move to the current character only when
-- the old snapshot's class and race match it; otherwise they stay, marked legacy, with one message.
local NOW = os.time({ year = 2026, month = 11, day = 11, hour = 12 })
local REALM = "CAMWOW EU4 Realm 8 PvP"
local OLD = REALM .. "-Velikopter"
local TANNER = REALM .. "-Velikopter Tanner"
local WRIGHT = REALM .. "-Velikopter Wright"

-- Loads the addon with saved tables; the character is set only after ADDON_LOADED (as at a real
-- load, the migration may have to wait for PLAYER_LOGIN), then logs in.
local function Login(surname, race, class, saved)
	saved = saved or {}
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	ns.printed = {}
	ns.Print = function(msg) ns.printed[#ns.printed + 1] = tostring(msg) end
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", surname, REALM
	function UnitRace() return race, race, 2 end
	function UnitClass() return class, class:upper(), 3 end
	stub.held = { [2589] = 2 } -- the 2 Linen Cloth the old ledger position holds
	C_Item.GetItemCount = function(id) return stub.held[id] or 0 end
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

-- What the SavedVariables held before #77: both characters wrote to OLD.
local function OldSaved(snapClass, snapRace)
	local db = {
		fishing = { [OLD] = { catches = { { t = NOW - 3600, zone = "Durotar", items = { [6291] = 1 } } }, opened = {} } },
		snapshots = {},
	}
	if snapClass then
		db.snapshots[OLD] = { v = 1, t = NOW - 7200, char = { name = "Velikopter", realm = REALM, class = snapClass, race = snapRace } }
	end
	local market = { ledger = {
		entries = { { t = NOW - 600, c = OLD, k = "vbuy", i = 2589, q = 2, m = 30, w = "Vendor" },
			{ t = NOW - 500, c = REALM .. "-Someone", k = "vbuy", i = 2589, q = 1, m = 15, w = "Vendor" } },
		chars = { [OLD] = { reset = { t = NOW - 86400, money = 5000 }, days = { ["2026-11-10"] = 4000 }, pos = { [2589] = { held = 2, known = 2, cost = 30, transit = 0 } } },
			[REALM .. "-Someone"] = { days = {}, pos = {} } },
	} }
	return { db = db, market = market }
end

it("key: realm, name and surname joined with the client's separator", function()
	local ns, stub = Login("Tanner", "Orc", "Hunter")
	eq(ns.CharKey(), TANNER)
	local full, first, surname = ns.CharName()
	eq(full, "Velikopter Tanner"); eq(first, "Velikopter"); eq(surname, "Tanner")
	Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "~" } }
	eq(ns.CharKey(), REALM .. "-Velikopter~Tanner", "the client's constant wins")
	Constants = nil
	eq(ns.Ledger.CharKey(), TANNER, "ledger uses the same key")
	eq(ns.Snapshot.Key(), TANNER, "snapshot uses the same key")
	eq(ns.Fishing.CharKey(), TANNER, "fishing uses the same key")
	stub.names.player = nil
	eq(ns.CharKey(), nil, "no key while the client doesn't know the name")
end)

it("key: a character without a surname keeps <realm>-<name>", function()
	local ns, stub = Login(nil, "Orc", "Hunter")
	eq(ns.CharKey(), REALM .. "-Velikopter")
	local full, first, surname = ns.CharName()
	eq(full, "Velikopter"); eq(first, "Velikopter"); eq(surname, nil)
	stub.surnames.player = ""
	eq(ns.CharKey(), REALM .. "-Velikopter", "an empty surname counts as none")
	eq(ns.MigrateCharKey(), "none")
end)

it("two characters with the same first name keep their own ledger, snapshot and fishing log", function()
	local ns, stub = Login("Tanner", "Orc", "Hunter")
	stub.items[2589] = { name = "Linen Cloth", sellPrice = 13 }
	stub.held[2589] = 1
	ns.Ledger.Record("vbuy", 2589, 1, 15, "Vendor", 0)
	ns.Fishing.Log().catches[1] = { t = NOW, zone = "Durotar", items = { [6291] = 1 } }
	ns.Snapshot.Save()
	-- Same session table, other character (as the account-wide SavedVariables are on the next login).
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns, stub = Login("Wright", "Troll", "Mage", saved)
	stub.items[2589] = { name = "Linen Cloth", sellPrice = 13 }
	stub.held[2589] = 3
	ns.Ledger.Record("vbuy", 2589, 3, 45, "Vendor", 0)
	ns.Snapshot.Save()
	local chars = CraftWiseMarketDB.ledger.chars
	assert(chars[TANNER] and chars[WRIGHT], "one ledger character each")
	eq(chars[TANNER].pos[2589].cost, 15); eq(chars[WRIGHT].pos[2589].cost, 45)
	local byChar = {}
	for _, e in ipairs(CraftWiseMarketDB.ledger.entries) do byChar[e.c] = (byChar[e.c] or 0) + e.q end
	eq(byChar[TANNER], 1); eq(byChar[WRIGHT], 3); eq(byChar[OLD], nil)
	eq(#CraftWiseDB.fishing[TANNER].catches, 1)
	eq(#CraftWiseDB.fishing[WRIGHT].catches, 0, "Wright never fished")
	eq(CraftWiseDB.snapshots[TANNER].char.surname, "Tanner")
	eq(CraftWiseDB.snapshots[TANNER].char.class, "Hunter")
	eq(CraftWiseDB.snapshots[WRIGHT].char.name, "Velikopter")
	eq(CraftWiseDB.snapshots[WRIGHT].char.surname, "Wright")
	eq(CraftWiseDB.snapshots[WRIGHT].char.class, "Mage")
	eq(CraftWiseDB.snapshots[OLD], nil)
	eq(#ns.printed, 0, "nothing to migrate, nothing printed")
end)

it("migration: old entries move to the character whose class and race match the old snapshot", function()
	local ns = Login("Tanner", "Orc", "Hunter", OldSaved("Hunter", "Orc"))
	eq(ns.MigrateCharKey(), "moved")
	local db, ledger = CraftWiseDB, CraftWiseMarketDB.ledger
	eq(db.snapshots[OLD], nil); eq(db.snapshots[TANNER].char.class, "Hunter")
	eq(db.fishing[OLD], nil); eq(#db.fishing[TANNER].catches, 1)
	eq(ledger.chars[OLD], nil); eq(ledger.chars[TANNER].pos[2589].cost, 30)
	eq(ledger.chars[TANNER].reset.t, NOW - 86400, "the old reset point is kept")
	eq(ledger.chars[TANNER].days["2026-11-10"], 4000)
	eq(ledger.entries[1].c, TANNER)
	eq(ledger.entries[2].c, REALM .. "-Someone", "other characters' entries are untouched")
	assert(ledger.chars[REALM .. "-Someone"], "other characters are untouched")
	eq(db.snapshots[TANNER].legacy, nil); eq(ledger.chars[TANNER].legacy, nil)
	eq(#ns.printed, 1)
	assert(ns.printed[1]:find(OLD, 1, true) and ns.printed[1]:find("Velikopter Tanner", 1, true), ns.printed[1])
	-- The other character logs in later: nothing left under the old key, nothing claimed.
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Wright", "Troll", "Mage", saved)
	eq(ns.MigrateCharKey(), "none")
	eq(CraftWiseDB.fishing[WRIGHT], nil)
	eq(CraftWiseMarketDB.ledger.chars[WRIGHT].pos[2589], nil, "Wright gets none of the old position")
	eq(#ns.printed, 0)
end)

it("migration: class or race differ -> kept under the old key, marked legacy, printed once", function()
	local ns, stub = Login("Wright", "Troll", "Mage", OldSaved("Hunter", "Orc"))
	eq(ns.MigrateCharKey(), "legacy")
	local db, ledger = CraftWiseDB, CraftWiseMarketDB.ledger
	eq(db.snapshots[OLD].legacy, true); eq(db.fishing[OLD].legacy, true); eq(ledger.chars[OLD].legacy, true)
	eq(db.fishing[WRIGHT], nil, "nothing moved")
	eq(ledger.entries[1].c, OLD)
	eq(#ns.printed, 1)
	assert(ns.printed[1]:find("legacy", 1, true) and ns.printed[1]:find("Orc Hunter", 1, true), ns.printed[1])
	stub.Fire("PLAYER_ENTERING_WORLD", false, true)
	eq(#ns.printed, 1, "a zone change doesn't print again")
	-- Next login of the same character: still legacy, no second message.
	local saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Wright", "Troll", "Mage", saved)
	eq(ns.MigrateCharKey(), "legacy")
	eq(#ns.printed, 0, "printed once")
	-- The matching character logs in: the entries move to it and lose the mark.
	saved = { db = CraftWiseDB, market = CraftWiseMarketDB }
	ns = Login("Tanner", "Orc", "Hunter", saved)
	eq(ns.MigrateCharKey(), "moved")
	eq(CraftWiseDB.snapshots[OLD], nil); eq(CraftWiseDB.snapshots[TANNER].legacy, nil)
	eq(CraftWiseDB.fishing[TANNER].legacy, nil); eq(CraftWiseMarketDB.ledger.chars[TANNER].legacy, nil)
	eq(CraftWiseMarketDB.ledger.entries[1].c, TANNER)
end)

it("migration: no old snapshot -> owner unknown, kept as legacy", function()
	local ns = Login("Tanner", "Orc", "Hunter", OldSaved(nil))
	eq(ns.MigrateCharKey(), "legacy")
	eq(CraftWiseDB.fishing[OLD].legacy, true)
	eq(CraftWiseMarketDB.ledger.chars[OLD].legacy, true)
	eq(CraftWiseDB.fishing[TANNER], nil)
	assert(ns.printed[1] and ns.printed[1]:find("no snapshot", 1, true), tostring(ns.printed[1]))
end)

it("migration: ledger entries without a character table are marked legacy too", function()
	local saved = OldSaved(nil)
	saved.db.fishing = {}
	saved.market.ledger.chars[OLD] = nil
	local ns = Login("Tanner", "Orc", "Hunter", saved)
	eq(ns.MigrateCharKey(), "legacy")
	eq(CraftWiseMarketDB.ledger.chars[OLD].legacy, true)
	eq(CraftWiseMarketDB.ledger.entries[1].c, OLD)
	eq(#ns.printed, 1)
end)

it("migration waits while the client doesn't know the character, class or race", function()
	local saved = OldSaved("Hunter", "Orc")
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	ns.Print = function() end
	eq(ns.MigrateCharKey(), "pending", "no name yet")
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", REALM
	UnitClass, UnitRace = nil, nil
	eq(ns.MigrateCharKey(), "pending", "no class/race yet")
	eq(CraftWiseDB.fishing[OLD] ~= nil, true, "nothing touched while pending")
	function UnitRace() return "Orc", "Orc", 2 end
	function UnitClass() return "Hunter", "HUNTER", 3 end
	stub.Fire("PLAYER_LOGIN")
	eq(ns.MigrateCharKey(), "moved")
end)

it("migration merges into a ledger character the new key started before it ran", function()
	local saved = OldSaved("Hunter", "Orc")
	saved.market.ledger.chars[TANNER] = { reset = { t = NOW, money = 7000 }, session = { t = NOW, money = 7000 },
		days = { ["2026-11-11"] = 7000 }, pos = {} }
	saved.db.fishing[TANNER] = { catches = { { t = NOW, zone = "Barrens", items = {} } }, opened = {} }
	Login("Tanner", "Orc", "Hunter", saved)
	local c = CraftWiseMarketDB.ledger.chars[TANNER]
	eq(c.reset.t, NOW - 86400, "the older reset point wins")
	eq(c.session.t, NOW, "this session stays")
	eq(c.days["2026-11-11"], 7000); eq(c.days["2026-11-10"], 4000)
	eq(c.pos[2589].cost, 30)
	local catches = CraftWiseDB.fishing[TANNER].catches
	eq(#catches, 2); eq(catches[1].zone, "Durotar", "sorted by time")
end)

-- #382: since the 20 Nov client patch GetRealmName() sometimes returns "" and writes landed under
-- "-<name> <surname>". No key without a realm; the realm is remembered once the client tells it.
it("realm unknown (GetRealmName returns \"\"): no key, nothing is written under \"-name\"", function()
	local ns, stub = Login("Tanner", "Orc", "Hunter")
	stub.realm = ""
	-- a fresh session: the realm was never told
	local ns2, stub2 = LoadAddon()
	stub2.names.player, stub2.surnames.player, stub2.realm = "Velikopter", "Tanner", ""
	eq(ns2.RealmName(), nil)
	eq(ns2.CharKey(), nil, "no key while the realm is unknown")
	eq(ns2.Ledger.CharKey(), nil)
	eq(ns2.Snapshot.Key(), nil)
	eq(ns2.Fishing.CharKey(), nil)
	ns2.Ledger.Record("ahsell", 2589, 1, 15, "AH", 0)
	for key in pairs(CraftWiseDB.snapshots or {}) do assert(key:sub(1, 1) ~= "-", "snapshot key " .. key) end
	for key in pairs((CraftWiseMarketDB.ledger or { chars = {} }).chars) do assert(key:sub(1, 1) ~= "-", "ledger key " .. key) end
	eq(#(CraftWiseMarketDB.ledger and CraftWiseMarketDB.ledger.entries or {}), 0, "no ledger entry written")
	stub2.realm = REALM
	eq(ns2.CharKey(), TANNER, "the key appears when the client tells the realm")
	stub2.realm = ""
	eq(ns2.CharKey(), TANNER, "and the known realm is kept for this session")
	assert(ns ~= nil)
end)

it("repair: '-Name Surname' data moves into the real key at login, snapshot newest wins", function()
	local EMPTY = "-Velikopter Tanner"
	local saved = { db = {
		snapshots = {
			[EMPTY] = { v = 1, t = NOW - 100, char = { name = "Velikopter", surname = "Tanner", realm = "" } },
			[TANNER] = { v = 1, t = NOW - 5000, char = { name = "Velikopter", surname = "Tanner", realm = REALM } },
			["-Other Person"] = { v = 1, t = NOW, char = { name = "Other", realm = "" } },
		},
		fishing = { [EMPTY] = { catches = { { t = NOW - 10, zone = "Durotar", items = { [6291] = 1 } } }, opened = {} },
			[TANNER] = { catches = { { t = NOW - 20, zone = "Durotar", items = { [6291] = 2 } } }, opened = {} } },
		crafted = { chars = { [EMPTY] = { [1] = { days = { ["20261120"] = { crafts = 2 } } } },
			[TANNER] = { [1] = { days = { ["20261120"] = { crafts = 3 } } } } }, before = {} },
	}, market = { ledger = {
		entries = { { t = NOW - 60, c = EMPTY, k = "ahsell", i = 2589, q = 1, m = 50, w = "AH" } },
		chars = { [EMPTY] = { days = { ["2026-11-20"] = 50 }, pos = {} }, [TANNER] = { days = { ["2026-11-19"] = 10 }, pos = {} } },
	}, flips = { rows = { { t = NOW, c = EMPTY, i = 1, q = 1, cost = 1, got = 2 } } } } }
	local ns = Login("Tanner", "Orc", "Hunter", saved)
	local db, market = CraftWiseDB, CraftWiseMarketDB
	eq(db.snapshots[EMPTY], nil)
	eq(db.snapshots[TANNER].t, NOW - 100, "the newer snapshot won")
	eq(db.snapshots[TANNER].char.realm, REALM, "empty realm filled in")
	assert(db.snapshots["-Other Person"], "another name is never touched")
	eq(#db.fishing[TANNER].catches, 2); eq(db.fishing[EMPTY], nil)
	eq(db.crafted.chars[TANNER][1].days["20261120"].crafts, 5); eq(db.crafted.chars[EMPTY], nil)
	eq(market.ledger.chars[EMPTY], nil)
	eq(market.ledger.chars[TANNER].days["2026-11-19"], 10)
	eq(market.ledger.chars[TANNER].days["2026-11-20"], 50)
	eq(market.ledger.entries[1].c, TANNER)
	eq(market.flips.rows[1].c, TANNER)
	local said = false
	for _, m in ipairs(ns.printed) do if m:find("did not know the realm", 1, true) then said = true end end
	assert(said, "says it once in chat")
	eq(ns.RepairEmptyRealm(), nil, "nothing left to move")
end)

it("repair: merchant records fold '-Name Surname' into the real key, other characters untouched (#382)", function()
	local EMPTY = "-Velikopter Tanner"
	local OTHER = "-Other Person"
	local saved = { db = { merchants = {
		[1] = { name = "Vendor", char = EMPTY, items = {
			[10] = { p = 5, ps = { [4] = 5 }, pk = { [4] = EMPTY, [5] = OTHER },
				pc = { [EMPTY] = { p = 5, st = 4, t = NOW - 10 }, [TANNER] = { p = 6, st = 4, t = NOW - 500 },
					[OTHER] = { p = 7, st = 4, t = NOW } } },
			[11] = { p = 1, pc = { [EMPTY] = { p = 1, t = NOW - 900 }, [TANNER] = { p = 2, t = NOW - 5 } } },
		} },
		[2] = { name = "Elsewhere", char = OTHER, items = {} },
	} } }
	local ns = Login("Tanner", "Orc", "Hunter", saved)
	local m = CraftWiseDB.merchants
	eq(m[1].char, TANNER)
	eq(m[1].items[10].pk[4], TANNER)
	eq(m[1].items[10].pk[5], OTHER, "another character is untouched")
	eq(m[1].items[10].pc[EMPTY], nil)
	eq(m[1].items[10].pc[TANNER].p, 5, "the newer sighting won")
	eq(m[1].items[10].pc[OTHER].p, 7)
	eq(m[1].items[11].pc[TANNER].p, 2, "the newer full-key sighting stayed")
	eq(m[2].char, OTHER)
	local said = 0
	for _, line in ipairs(ns.printed) do if line:find("did not know the realm", 1, true) then said = said + 1 end end
	eq(said, 1, "one chat line")
	eq(ns.RepairEmptyRealm(), nil, "nothing left to move")
end)

it("AH house needs no realm: the Scan AH house is set while the client tells nothing (#382)", function()
	local ns, stub = LoadAddon()
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", ""
	stub.faction, stub.locale, stub.zone, stub.subzone = "Horde", "enUS", "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
	eq(ns.Market.CurrentHouse(), "H")
	eq(ns.Market.HouseFor("faction"), "H")
	eq((ns.Market.HouseFor("Gadgetzan")), "N:Gadgetzan")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(ns.Market.CurrentHouse(), nil)
end)

it("realm: with the client silent, the realm stored before is used: from the character's own keys, once", function()
	local saved = { db = {
		snapshots = { [TANNER] = { v = 1, t = NOW, char = { name = "Velikopter", surname = "Tanner", realm = REALM } } },
		fishing = { ["Other Realm-Velikopter Wright"] = { catches = {}, opened = {} } },
	}, market = {} }
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", ""
	eq(ns.RealmName(), REALM, "read from the key this character already has")
	eq(ns.CharKey(), TANNER)
	eq(ns.db.charRealms["Velikopter Tanner"], REALM, "kept")
	-- another character with no stored realm: unknown, no key
	stub.surnames.player = "Nobody"
	eq(ns.RealmName(), nil); eq(ns.CharKey(), nil)
	eq(ns.SetCharRealm("Typed Realm"), true)
	eq(ns.CharKey(), "Typed Realm-Velikopter Nobody")
end)

it("realm: two realms for one name are ambiguous: nothing is guessed", function()
	local saved = { db = {
		snapshots = { ["Realm A-Velikopter Tanner"] = { t = NOW, char = {} }, ["Realm B-Velikopter Tanner"] = { t = NOW, char = {} } },
	}, market = {} }
	local ns, stub = LoadAddon({ savedDB = saved.db, savedMarket = saved.market })
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", ""
	eq(ns.RealmName(), nil)
	eq(ns.CharKey(), nil)
end)

it("realm: a live realm, when the client still tells it, is stored and wins", function()
	local ns, stub = LoadAddon()
	stub.names.player, stub.surnames.player, stub.realm = "Velikopter", "Tanner", REALM
	eq(ns.RealmName(), REALM)
	stub.realm = ""
	eq(ns.RealmName(), REALM, "stored")
end)

it("house keys: old '<realm>|H' keys move to 'H', the newer entry wins, scans merge, auctions follow (#382)", function()
	local M0 = LoadAddon()
	local pack = M0.Market.EncodeEntry
	local R6, R8 = "CAMWOW EU4 Realm 6 PvP", REALM
	local old = pack({ last = { t = NOW - 3600, min = 100, qty = 5, listings = 1 } })
	local new = pack({ last = { t = NOW - 60, min = 90, qty = 5, listings = 1 } })
	local only8 = pack({ last = { t = NOW - 10, min = 7, qty = 1, listings = 1 } })
	local market = { v = 1,
		houses = { [R6 .. "|H"] = { realm = R6, kind = "faction", faction = "Horde", label = "Horde AH" },
			[R8 .. "|H"] = { realm = R8, kind = "faction", faction = "Horde", label = "Horde AH" },
			[R8 .. "|N:Gadgetzan"] = { realm = R8, kind = "neutral", label = "Gadgetzan", cut = { samples = 3, rate = 0.05 } } },
		scans = { [R6 .. "|H"] = { { t = NOW - 7200, kind = "full", items = 10 } }, [R8 .. "|H"] = { { t = NOW - 100, kind = "full", items = 20 } } },
		items = { [1] = { [R6 .. "|H"] = old, [R8 .. "|H"] = new }, [2] = { [R8 .. "|H"] = only8, [R8 .. "|N:Gadgetzan"] = old } },
		ownScan = { house = R8 .. "|H" },
		auctions = { v = 1, chars = { [TANNER] = { list = { { i = 1, h = R8 .. "|H", st = "active" } }, ownedHouse = R8 .. "|H" } } },
	}
	local ns = LoadAddon({ savedDB = {}, savedMarket = market })
	local db = CraftWiseMarketDB
	eq(db.houseKeysV, 2)
	assert(db.houses["H"] and db.houses["N:Gadgetzan"], "realm-less houses")
	eq(db.houses[R8 .. "|H"], nil); eq(db.houses[R6 .. "|H"], nil)
	eq(db.houses["N:Gadgetzan"].cut.samples, 3, "the measured cut is kept")
	eq(db.houses["H"].realm, nil)
	eq(ns.Market.Current(1, "H").min, 90, "the newer entry won")
	eq(db.items[1][R6 .. "|H"], nil)
	eq(ns.Market.Current(2, "H").min, 7)
	assert(db.items[2]["N:Gadgetzan"], "neutral entry moved")
	eq(#db.scans["H"], 2, "scans of both realms merged"); eq(db.scans[R8 .. "|H"], nil)
	eq(db.ownScan.house, "H")
	eq(db.auctions.chars[TANNER].ownedHouse, "H"); eq(db.auctions.chars[TANNER].list[1].h, "H")
	eq(ns.Market.HouseKeyOf(R6 .. "|N:BootyBay"), "N:BootyBay")
	eq(ns.Market.HouseKeyOf("junk"), nil)
end)

it("Link: off since the realm change: no prefix, no whispers, no hello, no errors (#382)", function()
	local ns, stub = LoadAddon()
	local prefixes, sent = 0, 0
	C_ChatInfo = C_ChatInfo or {}
	C_ChatInfo.RegisterAddonMessagePrefix = function() prefixes = prefixes + 1 end
	C_ChatInfo.SendAddonMessage = function() sent = sent + 1 end
	stub.Fire("PLAYER_LOGIN")
	stub.RunTimers()
	eq(ns.Link.ENABLED, false)
	eq(ns.Link.SyncNow(), 0)
	eq(ns.Link.Hello("kitchenchant"), false)
	ns.Link.Push()
	stub.Fire("CHAT_MSG_ADDON", ns.Link.PREFIX, "H	2	Realm", "WHISPER", "Someone")
	ns.printed = {}
	ns.Print = function(m) ns.printed[#ns.printed + 1] = m end
	ns.Link.Slash("sync")
	assert(ns.printed[1] and ns.printed[1]:find("off since the 20 Nov realm change", 1, true), tostring(ns.printed[1]))
	eq(prefixes, 0); eq(sent, 0)
end)
