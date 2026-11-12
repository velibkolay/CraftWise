-- Loot feed (#135): containers opened from the bags. Their contents count once, whether the client writes a
-- receipt line (LOOT_ITEM_SELF or LOOT_ITEM_PUSHED_SELF) or not, in any order; quest reward pushes never count.
-- The farm tracker replaces a container looted this session by its contents; the loot toast shows them.
local ORE, GEM, FISH, REDGILL, RUBY, CRATE = 2770, 1206, 9001, 9010, 9011, 9004
local T0 = 1794000000

local function link(id, name)
	return ("|cffffffff|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(id, name)
end

local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	LOOT_ITEM_SELF = "You receive loot: %s."
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
	LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
	stub.items[ORE] = { name = "Copper Ore", sellPrice = 5 }
	stub.items[GEM] = { name = "Malachite", sellPrice = 25 }
	stub.items[FISH] = { name = "Raw Fish", sellPrice = 2 }
	stub.items[REDGILL] = { name = "Bloated Redgill" } -- no price of its own
	stub.items[RUBY] = { name = "Star Ruby", sellPrice = 1000 }
	stub.items[CRATE] = { name = "Battered Crate" }
	stub.names.player, stub.realm = "Veli", "Forever-EU"
	stub.clock = T0
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.zone = "Elwynn Forest"
	stub.money = 0
	stub.fishing = false
	IsFishingLoot = function() return stub.fishing end
	-- stub.loot = { { link, qty, coin } }
	GetLootSlotInfo = function(i)
		local s = stub.loot[i]
		if not s or not s.link and not s.coin then return nil end
		return "tex", "name", s.qty or 1, nil, 1, false, false, nil, nil, s.coin
	end
	stub.Fire("PLAYER_ENTERING_WORLD")
	return ns, stub
end

local function line(stub, id, n, pushed)
	local single, multiple = LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE
	if pushed then
		single, multiple = LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE
	end
	local l = link(id, stub.items[id].name)
	local text = n and n > 1 and multiple:format(l, n) or single:format(l)
	stub.Fire("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1-SELF")
end

local function coin(stub, copper)
	stub.money = stub.money + copper
	stub.Fire("PLAYER_MONEY")
	stub.Fire("CHAT_MSG_MONEY", "You loot some coin")
end

local function advance(stub, seconds)
	stub.clock = stub.clock + seconds
	stub.now = stub.now + seconds
end

-- A loot window: slots { { id, n } | { copper } }, read on LOOT_READY, then LOOT_OPENED (isFromItem).
local function open(stub, slots, fromItem)
	stub.loot = {}
	for _, sl in ipairs(slots) do
		if sl.copper then
			stub.loot[#stub.loot + 1] = { coin = true }
		else
			stub.loot[#stub.loot + 1] = { link = link(sl.id, stub.items[sl.id].name), qty = sl.n or 1 }
		end
	end
	stub.Fire("LOOT_READY", false)
	stub.Fire("LOOT_OPENED", false, fromItem or false)
end

local function clear(stub, slot)
	stub.Fire("LOOT_SLOT_CLEARED", slot)
end

local function close(stub)
	stub.Fire("LOOT_CLOSED")
end

-- A mob's loot window, looted with its usual receipt lines.
local function mob(stub, id, n)
	open(stub, { { id = id, n = n } }, false)
	clear(stub, 1)
	line(stub, id, n)
	close(stub)
end

-- The opened container sits locked in the bags while its window is open.
local function holding(stub, id)
	stub.bags[0] = { { itemID = ORE }, { itemID = id, isLocked = true, hasLoot = true, hyperlink = link(id, stub.items[id].name) } }
end

local function counts(ns)
	return ns.Farm.Counts(ns.Farm.Current())
end

local function feed(ns)
	local got = {}
	ns.LootFeed.Subscribe(function(kind, data)
		got[#got + 1] = { kind = kind, data = data }
	end)
	return got
end

it("parses pushed lines apart from loot lines; a pushed line outside a container window (quest reward) never counts", function()
	local ns, stub = setup()
	local F = ns.LootFeed
	local l, n = F.ParsePushed("You receive item: " .. link(GEM, "Malachite") .. "x3.")
	eq(F.ItemID(l), GEM); eq(n, 3)
	eq(F.ParsePushed("You receive loot: " .. link(GEM, "Malachite") .. "."), nil)
	eq(F.ParseLoot("You receive item: " .. link(GEM, "Malachite") .. "."), nil)
	line(stub, GEM, 1, true) -- quest reward
	eq(ns.Farm.Current(), nil, "no session started by a quest reward")
	eq(#ns.LootToast.Lines(), 0)
	-- A pushed line while a mob's window is open, even for an item in that window: not loot.
	open(stub, { { id = GEM } }, false)
	line(stub, GEM, 1, true)
	close(stub)
	eq(ns.Farm.Current(), nil)
	-- And while a container's window is open, an item that isn't in it: a quest reward too.
	holding(stub, CRATE)
	open(stub, { { id = RUBY } }, true)
	line(stub, GEM, 2, true)
	clear(stub, 1)
	close(stub)
	eq(counts(ns)[GEM], nil, "the pushed gem isn't counted"); eq(counts(ns)[RUBY], 1)
end)

it("a container dropped by a mob this session: its contents count, the container leaves the list; no chat line needed", function()
	local ns, stub = setup()
	local Farm = ns.Farm
	mob(stub, CRATE, 1)
	eq(counts(ns)[CRATE], 1)
	advance(stub, 20)
	holding(stub, CRATE)
	open(stub, { { id = RUBY }, { id = FISH, n = 3 } }, true)
	clear(stub, 1)
	clear(stub, 2)
	close(stub)
	local c = counts(ns)
	eq(c[CRATE], nil, "the container is replaced by its contents"); eq(c[RUBY], 1); eq(c[FISH], 3)
	local t = Farm.Totals(Farm.Current(), stub.clock)
	eq(t.items, 1000 + 6)
	-- The loot toast shows the contents too.
	local shown = {}
	for _, l in ipairs(ns.LootToast.Lines()) do shown[l.itemID or "money"] = l.count end
	eq(shown[RUBY], 1); eq(shown[FISH], 3)
	-- The log keeps the crate's drop and adds the contents.
	local e = Farm.LogEntries(Farm.Current())
	eq(#e, 3); eq(e[3].itemID, CRATE)
end)

it("no double count: a slot cleared and its receipt line, in either order, loot or pushed form", function()
	for _, case in ipairs({ { "clear first", "self" }, { "line first", "self" }, { "clear first", "pushed" },
		{ "line first", "pushed" }, { "line only", "self" }, { "line only", "pushed" }, { "line after close", "self" },
		{ "line before LOOT_OPENED", "self" } }) do
		local ns, stub = setup()
		local got = feed(ns)
		local order, form = case[1], case[2]
		local pushed = form == "pushed"
		holding(stub, CRATE)
		stub.loot = { { link = link(RUBY, "Star Ruby") }, { link = link(FISH, "Raw Fish"), qty = 2 } }
		stub.Fire("LOOT_READY", false)
		if order == "line before LOOT_OPENED" then
			line(stub, RUBY, 1, pushed)
			eq(#got, 0, "waits for LOOT_OPENED")
		end
		stub.Fire("LOOT_OPENED", false, true)
		if order == "clear first" then
			clear(stub, 1); line(stub, RUBY, 1, pushed); clear(stub, 2); line(stub, FISH, 2, pushed)
		elseif order == "line first" then
			line(stub, RUBY, 1, pushed); clear(stub, 1); line(stub, FISH, 2, pushed); clear(stub, 2)
		elseif order == "line only" then
			line(stub, RUBY, 1, pushed); line(stub, FISH, 2, pushed)
		elseif order == "line after close" then
			clear(stub, 1)
			close(stub)
			line(stub, RUBY, 1, pushed); line(stub, FISH, 2, pushed)
		else
			clear(stub, 1); clear(stub, 2)
		end
		close(stub)
		local c = counts(ns)
		eq(c[RUBY], 1, order .. ", " .. form .. ": ruby once"); eq(c[FISH], 2, order .. ", " .. form .. ": fish once")
		local items, opened = 0, 0
		for _, g in ipairs(got) do
			if g.kind == "item" then
				items = items + g.data.count
				eq(g.data.container, CRATE); eq(g.data.opening, 1)
			elseif g.kind == "opened" then
				opened = opened + 1
				eq(g.data.container, CRATE); eq(g.data.items[FISH], 2); eq(g.data.link, link(CRATE, "Battered Crate"))
			end
		end
		eq(items, 3, order .. ", " .. form); eq(opened, 1)
		eq(got[1].kind, "opened", "the opening comes before its items")
	end
end)

it("bags full: what stays in the window isn't counted; opening it again is the same opening", function()
	local ns, stub = setup()
	mob(stub, CRATE, 2)
	holding(stub, CRATE)
	open(stub, { { id = RUBY }, { id = GEM } }, true)
	clear(stub, 1) -- the gem doesn't fit
	close(stub)
	eq(counts(ns)[RUBY], 1); eq(counts(ns)[GEM], nil); eq(counts(ns)[CRATE], 1)
	advance(stub, 30)
	stub.loot = { { link = link(GEM, "Malachite") } }
	stub.Fire("LOOT_READY", false)
	stub.Fire("LOOT_OPENED", false, true)
	clear(stub, 1)
	close(stub)
	eq(counts(ns)[GEM], 1); eq(counts(ns)[CRATE], 1, "the second crate is still in the list")
	-- The next crate of the stack, emptied: a new opening.
	open(stub, { { id = FISH } }, true)
	clear(stub, 1)
	close(stub)
	eq(counts(ns)[CRATE], nil); eq(counts(ns)[FISH], 1)
end)

it("a container from before the session: its contents are this session's loot, nothing is removed", function()
	local ns, stub = setup()
	holding(stub, REDGILL)
	open(stub, { { id = RUBY } }, true)
	clear(stub, 1)
	close(stub)
	local s = ns.Farm.Current()
	assert(s, "the contents start a session")
	eq(counts(ns)[RUBY], 1); eq(counts(ns)[REDGILL], nil)
	eq(ns.Farm.Totals(s, stub.clock).fish, nil, "not fishing: it wasn't caught this session")
	-- A mob's loot right after, with the same item, still counts (its window ends the container's).
	mob(stub, RUBY, 1)
	eq(counts(ns)[RUBY], 2)
end)

it("a container caught this session (#135, Veli's Bloated Redgill): contents in the list and the fishing block", function()
	local ns, stub = setup()
	local Farm = ns.Farm
	stub.fishing = true
	open(stub, { { id = REDGILL } }, false)
	clear(stub, 1)
	line(stub, REDGILL, 1)
	close(stub)
	stub.fishing = false
	eq(#ns.db.fishing["Forever-EU-Veli"].catches, 1)
	advance(stub, 15)
	holding(stub, REDGILL)
	open(stub, { { id = RUBY }, { copper = 75 } }, true)
	clear(stub, 2)
	coin(stub, 75)
	clear(stub, 1)
	close(stub) -- Forever wrote no line for the ruby
	local c = counts(ns)
	eq(c[REDGILL], nil); eq(c[RUBY], 1, "the Star Ruby counts")
	local f = Farm.Totals(Farm.Current(), stub.clock).fish
	eq(f.opened, 1); eq(f.items, 1000); eq(f.coin, 75); eq(f.unknownUnits, 0, "the redgill left the fishing items")
	eq(f.best.itemID, RUBY)
	local o = ns.db.fishing["Forever-EU-Veli"].opened[1]
	eq(o.item, REDGILL); eq(o.items[RUBY], 1)
	local e = Farm.LogEntries(Farm.Current())
	eq(e[1].itemID, RUBY); eq(e[1].fish, true, "contents of the caught container")
	eq(e[2].copper, 75); eq(e[2].fish, true, "coin from the caught container")
end)

it("fast auto-loot (#41) takes a container's slots: they are read first", function()
	local ns, stub = setup()
	C_CVar.GetCVarBool = function(k) return k == "autoLootDefault" end
	IsModifiedClick = function() return false end
	C_AddOns = { IsAddOnLoaded = function() return false end }
	C_PartyInfo = { GetLootMethod = function() return 0 end }
	C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 10 or 0, 0 end
	LootSlot = function(i) stub.loot[i].link, stub.loot[i].coin = nil, nil end
	holding(stub, CRATE)
	stub.loot = { { link = link(RUBY, "Star Ruby") }, { link = link(GEM, "Malachite"), qty = 2 } }
	stub.Fire("LOOT_READY", true)
	stub.Fire("LOOT_OPENED", true, true)
	clear(stub, 2)
	clear(stub, 1)
	close(stub)
	eq(counts(ns)[RUBY], 1); eq(counts(ns)[GEM], 2)
end)

it("mob loot is unchanged: loot lines count, with or without LOOT_SLOT_CLEARED, and only once", function()
	local ns, stub = setup()
	mob(stub, ORE, 3)
	open(stub, { { id = GEM } }, false)
	close(stub)
	line(stub, GEM, 1) -- the line after the window closed
	line(stub, ORE, 2) -- no window at all (a roll won)
	eq(counts(ns)[ORE], 5); eq(counts(ns)[GEM], 1)
	-- A container's window then a quick line well after it closed: the line is loot of its own.
	holding(stub, CRATE)
	open(stub, { { id = GEM } }, true)
	clear(stub, 1)
	close(stub)
	advance(stub, ns.LootFeed.CONTAINER_SECONDS + 1)
	line(stub, GEM, 1)
	eq(counts(ns)[GEM], 3)
end)
