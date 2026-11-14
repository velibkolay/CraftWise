-- Merchant window buy (#201): the typed quantity, the checks before a purchase, the split into stack-sized
-- calls, the panel next to MerchantFrame and the basket's vendor lines on it.
local HIDE, THREAD = 2318, 2320

local function Setup()
	local ns, stub = LoadAddon()
	stub.items[HIDE] = { name = "Testhide", stack = 20 }
	stub.items[THREAD] = { name = "Testthread", stack = 20 }
	MerchantFrame = CreateFrame("Frame", "MerchantFrame")
	local calls = {}
	BuyMerchantItem = function(index, n) calls[#calls + 1] = index .. ":" .. n end
	GetMerchantItemMaxStack = function() return 20 end
	stub.merchant = { { itemID = HIDE, price = 10 }, { itemID = THREAD, price = 20 } }
	stub.money = 100000
	stub.bags[0] = {}
	stub.free[0] = 30
	local said = {}
	ns.Print = function(msg) said[#said + 1] = msg end
	return ns, stub, calls, said
end

it("the typed quantity: whole numbers from 1 to the basket maximum, nothing else", function()
	local ns = Setup()
	local P = ns.Basket.ParseQuantity
	eq(P("453"), 453); eq(P(" 7 "), 7); eq(P("12.9"), 12)
	eq(P(""), nil); eq(P("abc"), nil); eq(P("0"), nil); eq(P("-3"), nil)
	eq(P("999999"), ns.Basket.MAX_COUNT)
end)

it("a quantity is split into stack-sized calls that add up to exactly the quantity", function()
	local ns = Setup()
	local C = ns.Basket.Chunks
	eq(table.concat(C(453, 20), ","), "20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,20,13")
	eq(table.concat(C(40, 20), ","), "20,20")
	eq(table.concat(C(1, 20), ","), "1")
	eq(#C(0, 20), 0)
	eq(table.concat(C(5, 0), ","), "1,1,1,1,1", "a missing stack size buys one at a time")
	local sum = 0
	for _, n in ipairs(C(9999, 20)) do sum = sum + n end
	eq(sum, 9999)
end)

it("checks before buying: gold, the merchant's stock and bag room; a failure buys nothing", function()
	local ns, stub, calls = Setup()
	stub.Fire("MERCHANT_SHOW")
	local B = ns.Basket
	local line = { itemID = THREAD, quantity = 50 }
	local ok, _, _, q, total = B.Check(line, true)
	eq(ok, true); eq(q, 50); eq(total, 1000)
	stub.money = 999
	local n, why = B.Purchase(line, true)
	eq(n, nil); eq(why, "Not enough gold"); eq(#calls, 0)
	stub.money = 100000
	stub.merchant[2].available = 30
	n, why = B.Purchase(line, true)
	eq(n, nil); eq(why, "Only 30 left at this merchant"); eq(#calls, 0, "typed more than the stock: nothing")
	stub.merchant[2].available = nil
	stub.free[0] = 2 -- room for 40
	n, why = B.Purchase(line, true)
	eq(n, nil); eq(why, "Bags have room for 40"); eq(#calls, 0)
	stub.bags[0] = { { itemID = THREAD, stackCount = 15 } } -- 5 more fit into the open stack
	n = B.Purchase(line, true)
	eq(n, nil, "45 fit, 50 asked: still nothing")
	eq(#calls, 0)
	stub.free[0] = 3
	n = B.Purchase(line, true)
	eq(n, 50); eq(table.concat(calls, ","), "2:20,2:20,2:10")
	stub.bagFamily[0] = 8 -- a special bag: its free slots don't count
	calls = {}
	stub.free[0] = 30
	n, why = B.Purchase(line, true)
	eq(n, nil); eq(why, "Bags have room for 5")
	-- unknown stack size: the bag check is skipped, the rest still holds
	stub.bagFamily[0] = nil
	stub.items[THREAD].stack = nil
	stub.free[0] = 0
	eq(B.Purchase({ itemID = THREAD, quantity = 3 }, true), 3)
end)

it("a purchase never buys more than typed, and stops when the merchant closes mid-way", function()
	local ns, stub = Setup()
	stub.Fire("MERCHANT_SHOW")
	local seen = {}
	BuyMerchantItem = function(index, n)
		seen[#seen + 1] = n
		if #seen == 2 then stub.Fire("MERCHANT_CLOSED") end
	end
	local n, why = ns.Basket.Purchase({ itemID = HIDE, quantity = 70 }, true)
	eq(n, 40); eq(why, "The merchant closed"); eq(#seen, 2)
	stub.Fire("MERCHANT_CLOSED")
	n, why = ns.Basket.Purchase({ itemID = HIDE, quantity = 5 }, true)
	eq(n, nil); eq(#seen, 2, "closed merchant: no call")
end)

it("the panel: Alt+click picks the item, the typed quantity shows its total, one Buy click buys it", function()
	local ns, stub, calls, said = Setup()
	local button = CreateFrame("Button", "MerchantItem2ItemButton", MerchantFrame)
	button:SetID(2)
	local alt = false
	IsAltKeyDown = function() return alt end
	stub.Fire("MERCHANT_SHOW")
	local MB, panel = ns.MerchantBuy, ns.MerchantBuy.panel
	assert(panel, "panel on the merchant frame")
	eq(panel.status:GetText(), "Alt+click an item to pick it.")
	-- without Alt a click does nothing
	for _, h in ipairs(button.hooks and button.hooks.OnClick or {}) do h(button) end
	eq(MB.Typed(), nil)
	alt = true
	for _, h in ipairs(button.hooks and button.hooks.OnClick or {}) do h(button) end
	panel.box:SetText("45")
	panel.box.scripts.OnTextChanged(panel.box)
	eq(panel.item:GetText(), "Testthread")
	assert(panel.status:GetText():find("45 for", 1, true), panel.status:GetText())
	eq(panel.buy.enabled ~= false, true)
	panel.buy.scripts.OnClick(panel.buy)
	eq(table.concat(calls, ","), "2:20,2:20,2:5")
	assert(said[1]:find("Bought 45", 1, true), said[1])
	-- a failing check says why and buys nothing
	calls = {}
	stub.money = 10
	panel.box:SetText("45")
	panel.box.scripts.OnTextChanged(panel.box)
	eq(panel.status:GetText(), "Not enough gold")
	panel.buy.scripts.OnClick(panel.buy)
	eq(#calls, 0)
end)

it("the panel lists the basket's vendor lines this merchant sells, each with its own Buy", function()
	local ns, stub, calls = Setup()
	stub.Fire("MERCHANT_SHOW")
	local MB = ns.MerchantBuy
	eq(#MB.BasketLines(), 0, "empty basket: no lines, no plan work")
	ns.Basket.Plan = function()
		return { split = { vendor = { { itemID = THREAD, quantity = 50 }, { itemID = 424242, quantity = 4 } } } }
	end
	ns.Basket.Entries = function() return { {} } end
	local lines = MB.BasketLines()
	eq(#lines, 1); eq(lines[1].itemID, THREAD)
	MB.Update()
	-- Buy on the row: one click, the line's quantity, stack-sized
	local row = MB.Rows()[1]
	eq(row.line.itemID, THREAD); eq(row.text:GetText(), "50 × Testthread"); eq(row.buy.enabled, true)
	eq(MB.Rows()[2], nil)
	row.buy.scripts.OnClick(row.buy)
	eq(table.concat(calls, ","), "2:20,2:20,2:10")
end)

it("Forever has no GetMerchantItemInfo global: the merchant slot, CanBuy and Buy read C_MerchantFrame.GetItemInfo", function()
	local ns, stub, calls = Setup()
	eq(GetMerchantItemInfo, nil, "the stub must not hand out the Vanilla global")
	stub.Fire("MERCHANT_SHOW")
	local info = ns.MerchantItemInfo(2)
	eq(info.price, 20); eq(info.stack, 1); eq(info.available, -1); eq(info.extended, false)
	eq(ns.MerchantItemInfo(9), nil)
	local slot = ns.Basket.MerchantSlot(THREAD)
	eq(slot.index, 2); eq(slot.price, 20); eq(slot.stack, 1)
	eq(ns.Basket.CanBuy({ itemID = THREAD, quantity = 5 }), true)
	eq(ns.Basket.Buy({ itemID = THREAD, quantity = 25 }), 25)
	eq(table.concat(calls, ","), "2:20,2:5")
	eq(ns.Basket.MerchantSlot(424242), nil)
end)

it("Max: crafts the held reagents allow, counting only reagents no vendor sells", function()
	local ns = Setup()
	local CLAM, SPICE = 1, 2
	local held = { [CLAM] = 597, [SPICE] = 3 }
	local function Held(id) return held[id] or 0 end
	local vendor = { [SPICE] = true }
	local function HasVendor(id) return vendor[id] == true end
	local M = ns.Basket.MaxCrafts
	eq(M({ { itemID = CLAM, quantity = 1 }, { itemID = SPICE, quantity = 1 } }, Held, HasVendor), 597)
	eq(M({ { itemID = CLAM, quantity = 2 }, { itemID = SPICE, quantity = 1 } }, Held, HasVendor), 298)
	held[CLAM] = 1
	eq(M({ { itemID = CLAM, quantity = 2 } }, Held, HasVendor), 0, "a missing reagent allows none")
	vendor[CLAM] = true
	eq(M({ { itemID = CLAM, quantity = 1 }, { itemID = SPICE, quantity = 1 } }, Held, HasVendor), nil, "all sold by a vendor: no Max")
	eq(M({}, Held, HasVendor), nil)
	held[CLAM] = 50000; vendor[CLAM] = nil
	eq(M({ { itemID = CLAM, quantity = 1 } }, Held, HasVendor), ns.Basket.MAX_COUNT)
end)

it("the count box: Enter or focus loss applies a valid number, Escape or nonsense restores the old one", function()
	local ns = Setup()
	local content = CreateFrame("Frame")
	local pool = ns.Main.Pool(content)
	local applied = {}
	local box = pool:CountBox(7, function(n) applied[#applied + 1] = n end)
	eq(box:GetText(), "7")
	box:SetText("25")
	box.scripts.OnEditFocusLost(box)
	eq(applied[1], 25)
	box:SetText("7")
	box.scripts.OnEditFocusLost(box)
	eq(#applied, 1, "unchanged: nothing applied")
	box:SetText("99999")
	box.scripts.OnEditFocusLost(box)
	eq(applied[2], ns.Basket.MAX_COUNT, "clamped")
	box:SetText("0")
	box.scripts.OnEditFocusLost(box)
	eq(#applied, 2); eq(box:GetText(), "7", "zero restores")
	box:SetText("30")
	box.scripts.OnEscapePressed(box)
	box.scripts.OnEditFocusLost(box)
	eq(#applied, 2); eq(box:GetText(), "7", "Escape restores")
end)
