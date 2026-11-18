-- Bags full (#352): the cheapest Junk slot to delete (stacks counted) or a stack merge, only on a click and
-- behind a confirm dialog. Specs: Loot.Suggest (order, prices, never-suggested items), the confirm step, the
-- delete guard, the panel and the chat line, the Bags page.
local LEATHER, LINEN, BOOTS, KEEPER, QUEST, PLAIN = 2318, 2589, 400, 500, 600, 700

local function setup(opts)
	opts = opts or {}
	local ns, stub = LoadAddon()
	stub.items[LEATHER] = { name = "Light Leather", sellPrice = 5 }
	stub.items[LINEN] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[BOOTS] = { name = "Old Boots", sellPrice = 70, stack = 1 }
	stub.items[KEEPER] = { name = "Kept Thing", sellPrice = 1 }
	stub.items[QUEST] = { name = "Quest Thing", sellPrice = 1 }
	stub.items[PLAIN] = { name = "Unmarked Thing", sellPrice = 1 }
	stub.itemClass[QUEST] = 12
	stub.bags[0] = opts.bag0 or {}
	stub.free = {}
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.popups, stub.deleted, stub.picked = {}, {}, {}
	StaticPopupDialogs = {}
	StaticPopup_Show = function(which, a1, a2, data) stub.popups[#stub.popups + 1] = { which = which, a1 = a1, a2 = a2, data = data } end
	local pick = C_Container.PickupContainerItem
	C_Container.PickupContainerItem = function(bag, slot)
		stub.picked[#stub.picked + 1] = { bag, slot }
		pick(bag, slot)
	end
	DeleteCursorItem = function()
		local c = stub.cursor
		stub.deleted[#stub.deleted + 1] = stub.bags[c.bag][c.slot].itemID
		stub.bags[c.bag][c.slot] = false
		stub.cursor = nil
	end
	return ns, stub
end

local function stack(id, n) return { itemID = id, stackCount = n, quality = 1 } end

it("the cheapest slot wins: a partial stack of 3 beats a full stack of 20 of the same item", function()
	local ns = setup({ bag0 = { stack(LEATHER, 20), stack(LEATHER, 3), stack(BOOTS, 1) } })
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(BOOTS)
	local plan = ns.Loot.Suggest()
	eq(plan.kind, "delete"); eq(plan.slot, 2); eq(plan.count, 3); eq(plan.value, 15)
	eq(plan.text, "Delete Light Leather x3 (worth 15c)")
end)

it("two different items: the lower slot value wins, not the lower unit price", function()
	local ns = setup({ bag0 = { stack(LINEN, 1), stack(LEATHER, 20) } }) -- 13c against 100c
	ns.ToggleJunk(LINEN); ns.ToggleJunk(LEATHER)
	eq(ns.Loot.Suggest().itemID, LINEN)
	local ns2 = setup({ bag0 = { stack(LINEN, 2), stack(LEATHER, 2) } }) -- 26c against 10c
	ns2.ToggleJunk(LINEN); ns2.ToggleJunk(LEATHER)
	eq(ns2.Loot.Suggest().itemID, LEATHER)
end)

it("ties: the slot with fewer items goes first", function()
	local ns, stub = setup({ bag0 = { stack(LINEN, 4), stack(LEATHER, 2) } })
	stub.items[LEATHER].sellPrice = 26 -- 52c for 2 items; linen 4 x 13c = 52c
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(LINEN)
	local plan = ns.Loot.Suggest()
	eq(plan.itemID, LEATHER); eq(plan.count, 2)
end)

it("a zero vendor price counts as worth 0 and goes first, and says so", function()
	local ns, stub = setup({ bag0 = { stack(LINEN, 1), stack(LEATHER, 5) } })
	stub.items[LEATHER].sellPrice = 0
	ns.ToggleJunk(LINEN); ns.ToggleJunk(LEATHER)
	local plan = ns.Loot.Suggest()
	eq(plan.itemID, LEATHER); eq(plan.value, 0); eq(plan.noPrice, true)
	assert(plan.text:find("no vendor price", 1, true), plan.text)
end)

it("an item whose price is not loaded yet is left out", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 1), stack(LINEN, 9) } })
	stub.items[LEATHER].sellPrice = nil
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(LINEN)
	eq(ns.Loot.Suggest().itemID, LINEN, "the unpriced item is not guessed at")
	local ns2, stub2 = setup({ bag0 = { stack(LEATHER, 1) } })
	stub2.items[LEATHER].sellPrice = nil
	ns2.ToggleJunk(LEATHER)
	eq(ns2.Loot.Suggest(), nil, "nothing else to offer")
end)

it("never suggests Keep, quest items, unmarked items or anything outside the plain bags", function()
	local ns, stub = setup({ bag0 = { stack(KEEPER, 1), stack(QUEST, 1), stack(PLAIN, 1), stack(LEATHER, 1) } })
	stub.bags[5] = { stack(BOOTS, 1) } -- reagent bag
	stub.bags[1] = { stack(BOOTS, 1) }; stub.bagFamily[1] = 8 -- a special bag
	ns.db.junk[KEEPER], ns.db.keep[KEEPER] = true, true -- Keep wins over a stale junk mark
	ns.db.junk[QUEST] = true
	ns.db.junk[BOOTS] = true
	eq(ns.Loot.Suggest(), nil)
	ns.ToggleJunk(LEATHER)
	eq(ns.Loot.Suggest().itemID, LEATHER)
end)

it("two partial stacks of one item: suggests stacking them first, 2 slots -> 1", function()
	local ns = setup({ bag0 = { stack(LINEN, 8), stack(LEATHER, 1), stack(LINEN, 5) } })
	ns.ToggleJunk(LEATHER)
	local plan = ns.Loot.Suggest()
	eq(plan.kind, "merge"); eq(plan.text, "Stack Linen Cloth: 2 slots -> 1")
	eq(plan.from.slot, 3); eq(plan.to.slot, 1)
end)

it("stacks that can't free a slot are not offered", function()
	local ns = setup({ bag0 = { stack(LINEN, 15), stack(LINEN, 15) } }) -- 30 of max 20: 2 slots either way
	eq(ns.Loot.Suggest(), nil)
end)

it("not worth it: the loot is worth less than the cheapest junk slot", function()
	local ns = setup({ bag0 = { stack(LINEN, 20) } })
	ns.ToggleJunk(LINEN) -- 260c
	local plan = ns.Loot.Suggest(50)
	eq(plan.notWorth, true)
	assert(plan.text:find("not worth it, the loot is worth less", 1, true), plan.text)
	eq(ns.Loot.Suggest(500).notWorth, nil)
	eq(ns.Loot.Suggest(nil).notWorth, nil, "an unknown loot value is no comparison")
end)

it("the setting turns the suggestion off", function()
	local ns = setup({ bag0 = { stack(LINEN, 20) } })
	ns.ToggleJunk(LINEN)
	assert(ns.Loot.Suggest())
	ns.Loot.SetSuggestEnabled(false)
	eq(ns.Loot.Suggest(), nil)
	ns.Loot.SetSuggestEnabled(true)
	assert(ns.Loot.Suggest())
end)

it("a click asks first: nothing is picked up or deleted until the dialog is accepted", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3), stack(LINEN, 20) } })
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(LINEN)
	local plan = ns.Loot.Suggest()
	assert(ns.Loot.Click(plan))
	eq(#stub.popups, 1); eq(stub.popups[1].which, "CRAFTWISE_DELETE_JUNK")
	eq(stub.popups[1].a1, "Light Leather x3", "names the item and the count")
	eq(stub.popups[1].a2, "worth 15c", "and the value")
	eq(#stub.deleted, 0); eq(#stub.picked, 0); eq(stub.cursor, nil)
	StaticPopupDialogs["CRAFTWISE_DELETE_JUNK"].OnAccept(nil, stub.popups[1].data)
	eq(#stub.deleted, 1, "one item")
	eq(stub.deleted[1], LEATHER)
	eq(stub.bags[0][1], false); eq(stub.bags[0][2].itemID, LINEN)
end)

it("cancelling the dialog deletes nothing", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3) } })
	ns.ToggleJunk(LEATHER)
	ns.Loot.Click(ns.Loot.Suggest())
	eq(#stub.deleted, 0); eq(#stub.picked, 0)
	eq(StaticPopupDialogs["CRAFTWISE_DELETE_JUNK"].OnCancel, nil, "cancel has no handler that could delete")
end)

it("the delete re-checks the slot: changed count, Keep since, item on the cursor", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3) } })
	ns.ToggleJunk(LEATHER)
	local plan = ns.Loot.Suggest()
	stub.bags[0][1].stackCount = 4
	eq(ns.Loot.Delete(plan), false)
	stub.bags[0][1].stackCount = 3
	ns.ToggleKeep(LEATHER)
	eq(ns.Loot.Delete(plan), false, "marked Keep since")
	ns.ToggleJunk(LEATHER)
	stub.cursor = { bag = 0, slot = 1 }
	eq(ns.Loot.Delete(plan), false, "something is on the cursor")
	stub.cursor = nil
	eq(#stub.deleted, 0)
	eq(ns.Loot.Delete(plan), true)
	eq(#stub.deleted, 1)
end)

it("one item per click: a second delete needs a new click", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3), stack(BOOTS, 1) } })
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(BOOTS)
	ns.Loot.Click(ns.Loot.Suggest())
	StaticPopupDialogs["CRAFTWISE_DELETE_JUNK"].OnAccept(nil, stub.popups[1].data)
	eq(#stub.deleted, 1); eq(#stub.popups, 1, "no second dialog by itself")
end)

it("stacking moves one stack per click, never by itself", function()
	local ns, stub = setup({ bag0 = { stack(LINEN, 8), stack(LINEN, 5) } })
	local plan = ns.Loot.Suggest()
	eq(#stub.picked, 0)
	assert(ns.Loot.Click(plan))
	eq(#stub.picked, 2)
	eq(stub.picked[1][2], 2); eq(stub.picked[2][2], 1)
end)

it("DeleteCursorItem is called from one place only: the confirm dialog's accept path", function()
	local calls, delete = {}, {}
	local toc = io.open("CraftWise/CraftWise.toc")
	for line in toc:lines() do
		if not line:match("^%s*#") and line:match("%S") then
			local path = "CraftWise/" .. line:gsub("\\", "/"):gsub("%s+$", "")
			local f = path:match("%.lua$") and io.open(path)
			if f then
				local n = 0
				for l in f:lines() do
					n = n + 1
					local code = l:gsub("%-%-.*$", "")
					if code:find("DeleteCursorItem", 1, true) then
						calls[#calls + 1] = path .. ":" .. n
					end
					if code:find("Loot.Delete", 1, true) or code:find("C_Container.DeleteItem", 1, true)
						or code:find("C_Item.DeleteItem", 1, true) then
						delete[#delete + 1] = path .. ":" .. n .. ":" .. code
					end
				end
				f:close()
			end
		end
	end
	toc:close()
	eq(#calls, 1, "calls: " .. table.concat(calls, ", "))
	assert(calls[1]:find("Loot.lua", 1, true), calls[1])
	-- Loot.Delete is defined once and called once, inside the dialog's OnAccept (nothing else reaches it).
	local defs, uses = 0, 0
	for _, d in ipairs(delete) do
		if d:find("function Loot.Delete", 1, true) then defs = defs + 1 else uses = uses + 1 end
	end
	eq(defs, 1); eq(uses, 1, table.concat(delete, "\n"))
end)

it("the full-bag message suggests it: one chat line, the panel, the button asks first", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3), stack(LINEN, 20) } })
	ERR_INV_FULL = "Inventory is full."
	ns.ToggleJunk(LEATHER); ns.ToggleJunk(LINEN)
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 1)
	assert(stub.printed[1]:find("Delete Light Leather x3 (worth 15c)", 1, true), stub.printed[1])
	local panel = CraftWiseBagFull
	assert(panel and panel:IsShown(), "panel shown")
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 1, "the panel is already up: no second line")
	panel.act.scripts.OnClick(panel.act)
	eq(#stub.popups, 1); eq(#stub.deleted, 0)
end)

it("with free slots the full-bag message adds nothing", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3) } })
	ERR_INV_FULL = "Inventory is full."
	ns.ToggleJunk(LEATHER)
	stub.free[0] = 2
	stub.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	eq(#stub.printed, 0)
end)

it("fast auto-loot with full bags: the one message carries the suggestion and the comparison", function()
	local ns, stub = setup({ bag0 = { stack(LINEN, 20) } })
	ERR_INV_FULL = "Inventory is full."
	ns.ToggleJunk(LINEN) -- 260c
	stub.cv = { autoLootDefault = true }
	C_CVar.GetCVarBool = function(k) return stub.cv[k] end
	Enum.LootMethod = { Masterlooter = 2 }
	C_PartyInfo = { GetLootMethod = function() return 0 end }
	stub.loot = { { link = "item:" .. LEATHER } } -- 5c
	GetNumLootItems = function() return #stub.loot end
	GetLootSlotLink = function(i) return stub.loot[i] and stub.loot[i].link end
	GetLootSlotInfo = function() return "tex", "name", 1, nil, 1, false end
	LootSlot = function() end
	stub.Fire("LOOT_READY", true)
	eq(#stub.printed, 1)
	assert(stub.printed[1]:find("Bags are full. Left in the loot window", 1, true), stub.printed[1])
	assert(stub.printed[1]:find("Delete Linen Cloth x20", 1, true), stub.printed[1])
	assert(stub.printed[1]:find("not worth it", 1, true), stub.printed[1])
end)

it("the Bags page shows the suggestion and its button only while no slot is free", function()
	local ns, stub = setup({ bag0 = { stack(LEATHER, 3) } })
	ns.ToggleJunk(LEATHER)
	local P = ns.Main.pages.bags.P
	local model = P.Model({ prices = {} })
	assert(model.footer:find("Delete Light Leather x3", 1, true), model.footer)
	eq(P.free.kind, "delete")
	stub.free[0] = 1
	model = P.Model({ prices = {} })
	eq(P.free, nil)
	assert(not model.footer:find("Delete Light Leather", 1, true))
end)
