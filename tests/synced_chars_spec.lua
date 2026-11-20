-- #243: the other machine's characters (CraftWiseSync.chars) shown read-only: Settings › Other machine and
-- the Crafted page's characters. Invented data only.
local NOW = 1794000000

local function Load()
	local ns, stub = LoadAddon()
	time = function(t)
		if t then return os.time(t) end
		return stub.clock or NOW
	end
	stub.clock = NOW
	stub.names.player, stub.surnames.player = "Testperson", "Tanner"
	stub.realm = "TestRealm"
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	return ns, stub
end

local function Char(over)
	local c = {
		machine = "Mac", uploaded = NOW - 100,
		info = { name = "Velikopter", level = 12, t = NOW - 7200 },
		snapshot = { t = NOW - 7200, data = { char = { money = 123456 },
			holdings = { bags = { ["2589"] = 20, ["2592"] = 5 }, bank = { t = NOW, items = { ["2589"] = 100 } } },
			farm = { sessions = { { seconds = 600, coin = 5000, items = 7000, zone = "Barrens" } } } } },
		fishing = { t = NOW, data = { catches = 85 } },
		ledger = { { t = NOW - 86400, k = "ahbuy", i = 2589, q = 20, m = 2000 }, { t = NOW - 3600, k = "vsell", i = 2589, q = 1, m = 500 },
			{ t = NOW - 40 * 86400, k = "ahbuy", i = 1, q = 1, m = 99999 } },
		crafted = { { r = 2149, d = 20261115, n = 3, i = 3, p = 300, k = 3 }, { r = 2149, d = 20261114, n = 2, i = 2, p = 100, k = 2 } },
	}
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end

it("lists the other machine's characters with machine, name and age; an empty machine reads 'other machine'", function()
	local ns = Load()
	CraftWiseSync = { v = 1, chars = { ["R-Velikopter Mac"] = Char(), ["R-Nameless Alt"] = Char({ machine = false, info = { name = "Nameless" } }) } }
	local list = ns.Synced.List(NOW)
	eq(#list, 2)
	eq(list[1].label, "Mac \194\183 Velikopter \194\183 2 h ago")
	assert(list[2].label:find("^other machine"), list[2].label)
	CraftWiseSync = nil
	eq(#ns.Synced.List(NOW), 0)
end)

it("own data wins: a key this account has is never shown from the file, and nothing is written into the saved data", function()
	local ns = Load()
	local own = ns.CharKey()
	CraftWiseSync = { v = 1, chars = { [own] = Char(), ["R-Other Alt"] = Char(), ["R-Has Snap"] = Char() } }
	ns.db.snapshots["R-Has Snap"] = { t = NOW }
	local keys = ns.Synced.Chars()
	assert(keys["R-Other Alt"] and not keys[own] and not keys["R-Has Snap"])
	ns.Synced.CraftChars(); ns.Synced.Lines(NOW)
	assert(ns.db.snapshots["R-Other Alt"] == nil and ns.db.fishing["R-Other Alt"] == nil)
	assert(not (ns.db.crafted and ns.db.crafted.chars["R-Other Alt"]))
	CraftWiseSync = nil
end)

it("holdings, ledger (30 days), fishing and farm come from the synced documents", function()
	local ns = Load()
	local e = Char()
	local h = ns.Synced.Holdings(e)
	eq(h.money, 123456); eq(h.bags, 25); eq(h.bank, 100); eq(h.mail, nil)
	local led = ns.Synced.Ledger(e, NOW)
	eq(led.spent, 2000); eq(led.received, 500); eq(led.n, 2)
	eq(ns.Synced.Fishing(e), 85)
	eq(ns.Synced.Farm(e).zone, "Barrens")
	CraftWiseSync = { v = 1, chars = { ["R-Velikopter Mac"] = e } }
	eq(#ns.Synced.Lines(NOW), 3)
	CraftWiseSync = nil
	eq(#ns.Synced.Lines(NOW), 0)
end)

it("Settings › Other machine shows the characters, read-only", function()
	local ns = Load()
	CraftWiseSync = { v = 1, chars = { ["R-Velikopter Mac"] = Char() } }
	local Set = ns.Main.Settings
	local g = Set.Group("machine")
	eq(g.rows[2].key, "chars")
	local text = g.rows[2].text()
	assert(text and text:find("Mac \194\183 Velikopter \194\183 2 h ago", 1, true), tostring(text))
	assert(text:find("bank 100", 1, true) and text:find("mail \226\128\148", 1, true), text)
	CraftWiseSync = nil
end)

it("the Crafted page counts the other machine's crafts, labelled; own crafts of the same key win", function()
	local ns = Load()
	local CL = ns.CraftLog
	CraftWiseSync = { v = 1, chars = { ["R-Velikopter Mac"] = Char() } }
	local c = CL.Counts(2149, NOW)
	eq(c.total, 5)
	eq(#c.chars, 1)
	eq(CL.CharLabel("R-Velikopter Mac"), "Mac \194\183 Velikopter")
	eq(CL.Characters()[1], "R-Velikopter Mac")
	eq(CL.List(NOW, "R-Velikopter Mac")[1].total, 5)
	assert(ns.db.crafted.chars["R-Velikopter Mac"] == nil, "never stored")
	ns.db.crafted.chars["R-Velikopter Mac"] = { [2149] = { days = { [20261115] = { 1, 1, 0, 0 } } } }
	eq(CL.Counts(2149, NOW).total, 1)
	CraftWiseSync = nil
end)
