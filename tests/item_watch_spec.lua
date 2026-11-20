-- Items watch list (#165, part 1): db.watch, ns.ItemWatch, the item menu's Watch line, the Items card's
-- toggle and the Watched chip staying in step. Invented items only.
local NOW = os.time({ year = 2026, month = 11, day = 12, hour = 15 })
local LEATHER, SALT, BOOTS = 990101, 990102, 990103

local function Load()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.items[LEATHER] = { name = "Testleather", sellPrice = 150, stack = 20 }
	stub.items[SALT] = { name = "Testsalt", sellPrice = 12, stack = 20 }
	stub.items[BOOTS] = { name = "Testboots", sellPrice = 70, stack = 1 }
	C_Item.GetItemNameByID = function(id) return stub.items[id] and stub.items[id].name end
	stub.Fire("PLAYER_LOGIN")
	return ns, stub, ns.Main
end

local function list(ns)
	return table.concat(ns.ItemWatch.List(), ",")
end

it("ItemWatch: saved shape is db.watch[itemID] = Unix time; account wide; nothing stored for unwatched items", function()
	local ns, stub = Load()
	eq(type(ns.db.watch), "table"); eq(next(ns.db.watch), nil, "empty by default")
	eq(ns.ItemWatch.IsWatched(SALT), false)
	eq(ns.ItemWatch.Toggle(SALT), true)
	eq(ns.db.watch[SALT], NOW)
	stub.clock = NOW + 60
	ns.ItemWatch.Set(LEATHER, true)
	ns.ItemWatch.Set(LEATHER, true) -- again: the added time stays
	stub.clock = NOW + 120
	ns.ItemWatch.Set(LEATHER, true)
	eq(ns.db.watch[LEATHER], NOW + 60)
	eq(ns.ItemWatch.AddedAt(LEATHER), NOW + 60)
	eq(list(ns), SALT .. "," .. LEATHER, "oldest first")
	eq(ns.ItemWatch.Toggle(SALT), false)
	eq(ns.db.watch[SALT], nil, "no false values stored")
	eq(list(ns), tostring(LEATHER))
	eq(ns.charDB.watch, nil, "not per character")
	eq(ns.ItemWatch.Set("x", true), false, "only item IDs")
end)

it("ItemWatch: every change fires ITEM_WATCH_CHANGED once; no change fires nothing", function()
	local ns = Load()
	local seen = {}
	ns.Listen("ITEM_WATCH_CHANGED", function(id, on) seen[#seen + 1] = id .. ":" .. tostring(on) end)
	ns.ItemWatch.Toggle(BOOTS); ns.ItemWatch.Set(BOOTS, true); ns.ItemWatch.Toggle(BOOTS)
	eq(table.concat(seen, " "), BOOTS .. ":true " .. BOOTS .. ":false")
end)

it("ItemWatch: the item menu's Watch line toggles and flips its label", function()
	local ns = Load()
	ns.ShowItemMenu(SALT)
	local menu = CraftWiseItemMenu
	eq(menu.buttons.watch.shown, true)
	eq(menu.buttons.watch.label.text, "Watch")
	menu.buttons.watch.scripts.OnClick(menu.buttons.watch)
	eq(ns.ItemWatch.IsWatched(SALT), true)
	eq(menu.shown, false, "closes after the choice")
	ns.ShowItemMenu(SALT)
	eq(menu.buttons.watch.label.text, "Stop watching")
	eq(menu.buttons.salt, nil)
	menu.buttons.watch.scripts.OnClick(menu.buttons.watch)
	eq(ns.ItemWatch.IsWatched(SALT), false)
	eq(ns.db.watch[SALT], nil)
	-- a quest item can be watched too
	C_Item.GetItemInfoInstant = function() return SALT, nil, nil, nil, nil, 12 end
	ns.ShowItemMenu(SALT)
	eq(menu.buttons.watch.shown, true)
end)

it("ItemWatch: menu, Items card toggle and Watched chip stay in step", function()
	local ns, _, M = Load()
	local I = M.Items
	I.Select(SALT)
	M.Open("items")
	local body = M.SlotsOf("items").body
	local card = body.card
	eq(card.watch.shown, true); eq(card.watch.on, false)
	-- menu -> card
	ns.ShowItemMenu(SALT)
	CraftWiseItemMenu.buttons.watch.scripts.OnClick(CraftWiseItemMenu.buttons.watch)
	eq(card.watch.on, true, "the card follows the menu")
	eq(list(ns), tostring(SALT))
	-- chip lists it
	I.SetChip("watched")
	eq(#I.ListModel(NOW).rows, 1); eq(I.ListModel(NOW).rows[1].itemID, SALT)
	-- card -> menu and chip
	card.watch.scripts.OnClick(card.watch)
	eq(card.watch.on, false); eq(ns.ItemWatch.IsWatched(SALT), false)
	eq(#I.ListModel(NOW).rows, 0)
	eq(I.ListModel(NOW).empty, "Watch an item from its card and it shows here.")
	ns.ShowItemMenu(SALT)
	eq(CraftWiseItemMenu.buttons.watch.label.text, "Watch")
	-- two items, chip sorted by name
	ns.ItemWatch.Set(SALT, true); ns.ItemWatch.Set(BOOTS, true)
	local rows = I.ListModel(NOW).rows
	eq(rows[1].itemID, BOOTS); eq(rows[2].itemID, SALT)
	-- survives a reload of the saved table
	eq(CraftWiseDB.watch[BOOTS] ~= nil and CraftWiseDB.watch[SALT] ~= nil, true)
end)

----------------------------------------------------------------------------------------------------
-- Two-way (#244): removals are kept as tombstones and CraftWiseSync.watch / .watchGone merge in at login.
----------------------------------------------------------------------------------------------------

it("ItemWatch: unwatching keeps a tombstone (db.watchGone), watching again drops it", function()
	local ns, stub = Load()
	eq(next(ns.db.watchGone), nil, "empty by default")
	ns.ItemWatch.Set(SALT, true)
	eq(ns.db.watchGone[SALT], nil)
	stub.clock = NOW + 30
	ns.ItemWatch.Set(SALT, false)
	eq(ns.db.watch[SALT], nil)
	eq(ns.db.watchGone[SALT], NOW + 30)
	ns.ItemWatch.Set(SALT, false) -- again: the removal time stays
	stub.clock = NOW + 60
	ns.ItemWatch.Set(SALT, false)
	eq(ns.db.watchGone[SALT], NOW + 30)
	ns.ItemWatch.Set(SALT, true)
	eq(ns.db.watch[SALT], NOW + 60)
	eq(ns.db.watchGone[SALT], nil)
end)

it("ItemWatch.MergeSync: the newest change per item wins, a tie keeps the item", function()
	local ns, stub = Load()
	local seen = {}
	ns.Listen("ITEM_WATCH_CHANGED", function(id, on) seen[#seen + 1] = id .. ":" .. tostring(on) end)
	ns.db.watch[LEATHER] = NOW - 100 -- own, older than the removal below
	ns.db.watch[SALT] = NOW - 100 -- own, newer than the removal below
	ns.db.watchGone[BOOTS] = NOW - 50 -- own removal
	local changed = ns.ItemWatch.MergeSync({
		v = 1,
		watch = { [BOOTS] = NOW - 50, [990104] = NOW - 10 }, -- a tie with the removal; a new item
		watchGone = { [LEATHER] = NOW - 40, [SALT] = NOW - 150, [990105] = NOW - 20 },
	})
	eq(changed, 3, "boots back (tie), item 990104 new, leather removed")
	eq(ns.db.watch[LEATHER], nil); eq(ns.db.watchGone[LEATHER], NOW - 40)
	eq(ns.db.watch[SALT], NOW - 100, "the older removal loses"); eq(ns.db.watchGone[SALT], nil)
	eq(ns.db.watch[BOOTS], NOW - 50); eq(ns.db.watchGone[BOOTS], nil)
	eq(ns.db.watch[990104], NOW - 10)
	eq(ns.db.watchGone[990105], NOW - 20, "a removal of an item never seen is kept")
	table.sort(seen)
	eq(table.concat(seen, " "), table.concat({ LEATHER .. ":false", BOOTS .. ":true", "990104:true" }, " "))
	-- again: nothing changes
	eq(ns.ItemWatch.MergeSync({ v = 1, watch = { [BOOTS] = NOW - 50 }, watchGone = { [LEATHER] = NOW - 40 } }), 0)
	-- an own change newer than the file stays
	stub.clock = NOW + 500
	ns.ItemWatch.Set(BOOTS, false)
	eq(ns.ItemWatch.MergeSync({ v = 1, watch = { [BOOTS] = NOW - 50 } }), 0)
	eq(ns.ItemWatch.IsWatched(BOOTS), false)
end)

it("ItemWatch.MergeSync: bad entries are skipped, old tombstones are dropped, no file is fine", function()
	local ns = Load()
	eq(ns.ItemWatch.MergeSync(nil), 0)
	eq(ns.ItemWatch.MergeSync({}), 0)
	eq(ns.ItemWatch.MergeSync({ watch = { x = NOW, [0] = NOW, [-3] = NOW, [5.5] = NOW, [990106] = "soon", [990107] = 12 } }), 0)
	eq(next(ns.db.watch), nil)
	ns.db.watchGone[990108] = NOW - 181 * 86400
	ns.db.watchGone[990109] = NOW - 10 * 86400
	ns.ItemWatch.MergeSync({ watch = { [990110] = NOW } })
	eq(ns.db.watchGone[990108], nil, "older than 180 days")
	eq(ns.db.watchGone[990109], NOW - 10 * 86400)
	eq(ns.db.watch[990110], NOW)
end)

it("ItemWatch: login merges CraftWiseSync.watch and lets go of it; another format version is ignored", function()
	local ns, stub = LoadAddon()
	stub.clock = NOW
	time = function(t) if t then return os.time(t) end return stub.clock end
	CraftWiseSync = { v = 1, written = NOW, machine = "Mac", market = {}, watch = { [SALT] = NOW - 5 }, watchGone = { [LEATHER] = NOW - 5 } }
	ns.db.watch[LEATHER] = NOW - 100
	stub.Fire("PLAYER_LOGIN")
	eq(ns.ItemWatch.IsWatched(SALT), true)
	eq(ns.ItemWatch.IsWatched(LEATHER), false)
	eq(CraftWiseSync.watch, nil); eq(CraftWiseSync.watchGone, nil)
end)
