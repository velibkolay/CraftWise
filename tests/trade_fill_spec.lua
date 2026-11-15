-- Trade window fill (#299): send lists, the plan against the bags, filling up to 6 slots from one click,
-- split stacks, the next batch after a completed trade, and that accepting is never done by the addon.

local function Setup(bagItems)
	local ns, stub = LoadAddon()
	for _, it in ipairs(bagItems) do
		stub.items[it.itemID] = { name = it.name }
	end
	stub.bags[0] = {}
	for i, it in ipairs(bagItems) do
		stub.bags[0][i] = { itemID = it.itemID, stackCount = it.count, isBound = it.bound }
	end
	TradeFrame = CreateFrame("Frame", "TradeFrame")
	local said = {}
	ns.Print = function(msg) said[#said + 1] = msg end
	return ns, stub, said
end

local function Bits(n, base)
	local out = {}
	for i = 1, n do
		out[i] = { itemID = (base or 100) + i, name = "Cloth" .. i, count = 20 }
	end
	return out
end

-- The trade completes: what was placed leaves the bags and the trade window is empty.
local function Complete(stub)
	for _, t in pairs(stub.trade) do
		local info = stub.bags[t.from.bag][t.from.slot]
		if t.count >= info.stackCount then
			stub.bags[t.from.bag][t.from.slot] = false
		else
			info.stackCount = info.stackCount - t.count
		end
	end
	stub.trade = {}
	stub.Fire("TRADE_CLOSED")
end

it("a send list: items, quantities, saved lists, partner lists; nothing is stored for an empty save", function()
	local ns = Setup(Bits(3))
	local S = ns.SendList
	eq(S.Save("empty"), nil, "an empty list is not saved")
	eq(S.Add(101, nil), true); eq(S.Add(102, 15), true); eq(S.Add(102, 7), true, "adding again sets the quantity")
	eq(#S.Work(), 2); eq(S.Find(102).qty, 7)
	eq(S.Add(103, 0), true); eq(S.Find(103).qty, nil, "0 means all stacks")
	eq(S.Save("  to Mac char  "), "to Mac char")
	S.Clear(); eq(#S.Work(), 0)
	eq(S.Load("to Mac char"), true); eq(#S.Work(), 3)
	S.Remove(101); eq(#S.Work(), 2)
	eq(S.Load("nope"), false)
	eq(S.SetPartner("Macchar", "to Mac char"), true); eq(S.PartnerList("Macchar"), "to Mac char")
	eq(S.SetPartner("Macchar", "unknown list"), false)
	eq(S.Delete("to Mac char"), true); eq(S.PartnerList("Macchar"), nil, "deleting a list drops its partner links")
end)

it("the plan: largest stacks first, a quantity takes whole stacks then a part, bound stacks are left out", function()
	local items = { { itemID = 200, name = "Wool", count = 5 }, { itemID = 200, name = "Wool", count = 20 }, { itemID = 200, name = "Wool", count = 20, bound = true },
		{ itemID = 300, name = "Ore", count = 3 } }
	local ns = Setup(items)
	local S = ns.SendList
	S.Add(200, nil); S.Add(300, 5)
	local units, short, bound = S.Plan()
	eq(#units, 3); eq(units[1].count, 20); eq(units[1].take, 20); eq(units[2].count, 5); eq(units[3].itemID, 300)
	eq(bound, 1, "the soulbound stack is counted, not planned")
	eq(#short, 1); eq(short[1].itemID, 300); eq(short[1].missing, 2, "5 wanted, 3 in the bags")
	S.Add(200, 22)
	units = S.Plan()
	eq(units[1].take, 20); eq(units[2].take, 2); eq(units[2].count, 5, "the second stack is split to 2")
end)

it("Fill 6 puts the next up to 6 stacks into the empty slots, one click, skipping occupied slots", function()
	local ns, stub, said = Setup(Bits(8))
	for i = 1, 8 do ns.SendList.Add(100 + i, nil) end
	stub.tradePartner = "Macchar"
	stub.Fire("TRADE_SHOW")
	stub.trade[2] = { name = "something", count = 1, from = { bag = 0, slot = 99 } }
	local n, why = ns.TradeFill.Fill()
	eq(n, 5, "slot 2 was taken: five placed"); eq(why, nil)
	for _, slot in ipairs({ 1, 3, 4, 5, 6 }) do
		assert(stub.trade[slot], "slot " .. slot)
	end
	eq(stub.trade[1].from.slot, 1); eq(stub.trade[3].from.slot, 2)
	eq(stub.cursor, nil, "nothing is left on the cursor")
	n, why = ns.TradeFill.Fill()
	eq(n, 0); eq(why, "The trade window is full")
	eq(stub.accepted, 0, "never accepts")
	eq(ns.TradeFill.Partner(), "Macchar")
end)

it("after a completed trade: the progress, the quantities shrink, and Fill next 6 places the rest", function()
	local ns, stub = Setup(Bits(8))
	for i = 1, 8 do ns.SendList.Add(100 + i, i == 1 and 20 or nil) end
	stub.Fire("TRADE_SHOW")
	eq(ns.TradeFill.Fill(), 6)
	eq(ns.TradeFill.ProgressText(), "sent 0 of 8 stacks")
	Complete(stub)
	eq(ns.TradeFill.ProgressText(), "sent 6 of 8 stacks")
	eq(ns.SendList.Find(101), nil, "a listed quantity that went out leaves the list")
	stub.Fire("TRADE_SHOW")
	local panel = ns.TradeFill.panel
	eq(panel.fill.label and panel.fill.label:GetText() or panel.fill:GetText(), "Fill next 6")
	eq(ns.TradeFill.Fill(), 2)
	Complete(stub)
	eq(ns.TradeFill.ProgressText(), "sent 8 of 8 stacks")
	stub.Fire("TRADE_SHOW")
	local n, why = ns.TradeFill.Fill()
	eq(n, 0); eq(why, "Nothing left to send")
end)

it("a trade that was cancelled sends nothing: the stacks are still in the bags and are offered again", function()
	local ns, stub = Setup(Bits(3))
	for i = 1, 3 do ns.SendList.Add(100 + i, nil) end
	stub.Fire("TRADE_SHOW")
	eq(ns.TradeFill.Fill(), 3)
	stub.trade = {}
	stub.Fire("TRADE_CLOSED") -- cancelled: the bags are untouched
	eq(ns.TradeFill.Progress().sent, 0)
	stub.Fire("TRADE_SHOW")
	eq(ns.TradeFill.Fill(), 3)
end)

it("a part of a stack is split on the cursor and dropped in the slot; the rest stays", function()
	local ns, stub = Setup({ { itemID = 400, name = "Linen", count = 20 } })
	ns.SendList.Add(400, 15)
	stub.Fire("TRADE_SHOW")
	eq(ns.TradeFill.Fill(), 1)
	eq(stub.trade[1].count, 15)
	Complete(stub)
	eq(stub.bags[0][1].stackCount, 5)
	eq(ns.SendList.Find(400), nil)
end)

it("when the client keeps the item on the cursor, the cursor is cleared and the fill stops with the reason", function()
	local ns, stub = Setup(Bits(3))
	for i = 1, 3 do ns.SendList.Add(100 + i, nil) end
	stub.Fire("TRADE_SHOW")
	stub.tradeNoDrop = true
	local n, why = ns.TradeFill.Fill()
	eq(n, 0); eq(why, "the trade window did not take it: one slot per click")
	eq(stub.cursor, nil)
	stub.tradeNoDrop = false
	eq(ns.TradeFill.Fill(), 3, "the next click works")
end)

it("no trade open, or something on the cursor: nothing is touched", function()
	local ns, stub = Setup(Bits(2))
	ns.SendList.Add(101, nil)
	local n, why = ns.TradeFill.Fill()
	eq(n, 0); eq(why, "Open a trade first")
	stub.Fire("TRADE_SHOW")
	stub.cursor = { bag = 0, slot = 2 }
	n, why = ns.TradeFill.Fill()
	eq(n, 0); eq(why, "Put down what is on the cursor first")
	eq(stub.trade[1], nil)
end)

it("a saved list for the trade partner loads by itself when that character opens a trade", function()
	local ns, stub = Setup(Bits(2))
	ns.SendList.Add(101, nil); ns.SendList.Save("to Mac char"); ns.SendList.SetPartner("Macchar", "to Mac char")
	ns.SendList.Clear()
	stub.tradePartner = "Macchar"
	stub.Fire("TRADE_SHOW")
	eq(#ns.SendList.Work(), 1)
	ns.SendList.Clear(); stub.tradePartner = "Other"
	stub.Fire("TRADE_SHOW")
	eq(#ns.SendList.Work(), 0)
end)

it("typed search adds the first bag item whose name matches, with an optional quantity", function()
	local ns, stub = Setup({ { itemID = 500, name = "Mageweave Cloth", count = 20 }, { itemID = 501, name = "Silk Cloth", count = 20 } })
	stub.Fire("TRADE_SHOW")
	local panel = ns.TradeFill.panel
	panel.search:SetText("silk"); panel.qty:SetText("7")
	ns.TradeFill.AddTyped()
	eq(ns.SendList.Find(501).qty, 7); eq(ns.SendList.Find(500), nil)
	panel.search:SetText("zzz")
	ns.TradeFill.AddTyped()
	eq(#ns.SendList.Work(), 1)
end)

it("the addon never accepts a trade: no AcceptTrade anywhere in the send code", function()
	for _, path in ipairs({ "CraftWise/SendList.lua", "CraftWise/UI/TradeFill.lua" }) do
		local f = io.open(path, "r")
		if f then
			local text = f:read("*a")
			f:close()
			-- Only the comment may say it.
			text = text:gsub("%-%-[^\n]*", "")
			eq(text:find("AcceptTrade", 1, true), nil, path)
		end
	end
end)
