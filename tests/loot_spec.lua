-- Fast auto-loot (issue #41): record before loot, auto-loot rule, BoP, full bags, other addons, source fallback.
local RECIPE_ITEM, PLAIN_ITEM = 5789, 2589
local function npc(id) return ("Creature-0-3-1-1-%d-000012345A"):format(id) end

local function setup(opts)
	opts = opts or {}
	local ns, stub = LoadAddon()
	stub.itemClass[RECIPE_ITEM] = 9
	stub.items[RECIPE_ITEM] = { name = "Pattern: Test Cloak" }
	stub.items[PLAIN_ITEM] = { name = "Linen Cloth" }
	stub.cv = { autoLootDefault = true }
	stub.modifier = false
	stub.addons = {}
	stub.looted, stub.errors, stub.recordedAtLoot = {}, {}, {}
	stub.free = opts.free or 10
	stub.lootMethod = 0
	stub.dead = {}
	Enum.LootMethod = { Masterlooter = 2 }
	C_CVar.GetCVarBool = function(k) return stub.cv[k] end
	IsModifiedClick = function(k) return k == "AUTOLOOTTOGGLE" and stub.modifier end
	C_AddOns = { IsAddOnLoaded = function(n) return stub.addons[n] end }
	C_PartyInfo = { GetLootMethod = function() return stub.lootMethod end }
	C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and stub.free or 0, 0 end
	UnitIsDead = function(u) return stub.dead[u] end
	GetLootSlotInfo = function(i)
		local s = stub.loot[i]
		if not s or not s.link and not s.coin then return nil end
		return "tex", "name", 1, s.currency, 1, s.locked, false, nil, nil, s.coin
	end
	LootSlot = function(i)
		stub.looted[#stub.looted + 1] = i
		stub.recordedAtLoot[i] = ns.db.sources[RECIPE_ITEM] ~= nil
		stub.loot[i].link, stub.loot[i].coin, stub.loot[i].currency = nil, nil, nil
	end
	ERR_INV_FULL = "Inventory is full."
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	return ns, stub
end

local function drop()
	return { { link = "item:" .. PLAIN_ITEM }, { link = "item:" .. RECIPE_ITEM, sources = { npc(46), 1 } }, { coin = true } }
end

it("records the recipe before looting, then loots every slot", function()
	local ns, stub = setup()
	stub.loot = drop()
	stub.Fire("LOOT_READY"); stub.Fire("LOOT_OPENED")
	eq(#stub.looted, 3)
	eq(stub.recordedAtLoot[1], true, "recorded before the first LootSlot")
	eq(ns.db.sources[RECIPE_ITEM].loot["Creature:46"].n, 1, "LOOT_OPENED does not count it twice")
end)

it("without the autoloot payload, follows the auto-loot setting XOR the toggle modifier", function()
	local cases = { { true, false, 3 }, { true, true, 0 }, { false, false, 0 }, { false, true, 3 } }
	for _, c in ipairs(cases) do
		local _, stub = setup()
		stub.cv.autoLootDefault, stub.modifier = c[1], c[2]
		stub.loot = drop()
		stub.Fire("LOOT_READY")
		eq(#stub.looted, c[3], ("setting %s modifier %s"):format(tostring(c[1]), tostring(c[2])))
	end
end)

it("follows the LOOT_READY autoloot payload, not the modifier read at LOOT_READY (#57)", function()
	-- Shift held at the click, released before LOOT_READY: the client says false, the XOR rule now says true.
	local _, stub = setup()
	stub.cv.autoLootDefault, stub.modifier = true, false
	stub.loot = drop()
	stub.Fire("LOOT_READY", false)
	eq(#stub.looted, 0, "payload false: nothing looted")
	-- Auto-loot off, Shift held at the click and released: the client says true, the XOR rule now says false.
	local _, stub2 = setup()
	stub2.cv.autoLootDefault, stub2.modifier = false, false
	stub2.loot = drop()
	stub2.Fire("LOOT_READY", true)
	eq(#stub2.looted, 3, "payload true: looted")
end)

it("without fast loot the LOOT_OPENED path still records", function()
	local ns, stub = setup()
	ns.db.settings.fastLoot = false
	stub.loot = drop()
	stub.Fire("LOOT_READY"); stub.Fire("LOOT_OPENED")
	eq(#stub.looted, 0)
	eq(ns.db.sources[RECIPE_ITEM].loot["Creature:46"].n, 1)
end)

it("is on by default", function()
	local ns = setup()
	eq(ns.db.settings.fastLoot, true)
end)

it("does not touch locked slots (group loot) or a master-loot window", function()
	local _, stub = setup()
	stub.loot = { { link = "item:" .. PLAIN_ITEM, locked = true }, { link = "item:" .. PLAIN_ITEM } }
	stub.Fire("LOOT_READY")
	eq(#stub.looted, 1); eq(stub.looted[1], 2)
	local _, stub2 = setup()
	stub2.lootMethod = 2
	stub2.loot = drop()
	stub2.Fire("LOOT_READY")
	eq(#stub2.looted, 0)
end)

it("never confirms a bind-on-pickup dialog", function()
	local ns, stub = setup()
	local confirmed = false
	ConfirmLootSlot = function() confirmed = true end
	stub.loot = drop()
	stub.Fire("LOOT_READY"); stub.Fire("LOOT_BIND_CONFIRM", 1)
	eq(confirmed, false)
	eq(ns.eventFrame.events.LOOT_BIND_CONFIRM, nil)
end)

it("full bags: coins are looted, items stay, one message names them", function()
	local _, stub = setup({ free = 0 })
	stub.loot = drop()
	stub.Fire("LOOT_READY")
	eq(#stub.looted, 1); eq(stub.looted[1], 3)
	eq(#stub.printed, 1)
	assert(stub.printed[1]:find("Bags are full"), stub.printed[1])
	assert(stub.printed[1]:find("Linen Cloth") or stub.printed[1]:find("item:"), stub.printed[1])
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 1, "one message per window")
end)

it("a full-bag error from the client mid-loot gives one message", function()
	local _, stub = setup()
	stub.loot = drop()
	stub.Fire("LOOT_READY")
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 1)
	stub.Fire("LOOT_CLOSED")
	stub.loot = drop()
	stub.Fire("LOOT_READY"); stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 2, "next window warns again")
end)

it("another auto-loot addon: CraftWise does not loot and says so once", function()
	local ns, stub = setup()
	stub.addons.SpeedyAutoLoot = true
	stub.loot = drop()
	stub.Fire("LOOT_READY"); stub.Fire("LOOT_CLOSED")
	stub.loot = drop()
	stub.Fire("LOOT_READY")
	eq(#stub.looted, 0)
	eq(#stub.printed, 1)
	assert(stub.printed[1]:find("SpeedyAutoLoot"))
	eq(ns.Loot.Conflict(), "SpeedyAutoLoot")
end)

it("source fallback: dead mouseover or target creature when GetLootSourceInfo gives nothing", function()
	local ns, stub = setup()
	stub.loot = { { link = "item:" .. RECIPE_ITEM } }
	stub.guids.target, stub.dead.target = npc(77), true
	stub.Fire("LOOT_READY")
	eq(ns.db.sources[RECIPE_ITEM].loot["Creature:77"].n, 1)
	-- a living target is no source
	local ns2, stub2 = setup()
	stub2.loot = { { link = "item:" .. RECIPE_ITEM } }
	stub2.guids.target = npc(78)
	stub2.Fire("LOOT_READY")
	eq(ns2.db.sources[RECIPE_ITEM], nil)
end)

it("source fallback also works when GetLootSourceInfo does not exist, on the LOOT_OPENED path", function()
	local ns, stub = setup()
	GetLootSourceInfo = nil
	ns.db.settings.fastLoot = false
	stub.loot = { { link = "item:" .. RECIPE_ITEM } }
	stub.guids.mouseover, stub.dead.mouseover = npc(5), true
	stub.Fire("LOOT_READY"); stub.Fire("LOOT_OPENED")
	eq(ns.db.sources[RECIPE_ITEM].loot["Creature:5"].n, 1)
end)
