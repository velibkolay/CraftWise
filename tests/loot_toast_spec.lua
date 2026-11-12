-- Loot toast (issue #114): parsing the client's loot lines, coin pairing, stacking, expiry, value, settings.
local ORE, CLOTH, HIDE = 2770, 2589, 2318

local function link(id, name, color)
	return ("|cff%s|Hitem:%d::::::::20:::::|h[%s]|h|r"):format(color or "ffffff", id, name)
end

local function setup(opts)
	local ns, stub = LoadAddon(opts)
	-- The client's English format strings (GlobalStrings); other locales have their own.
	LOOT_ITEM_SELF = "You receive loot: %s."
	LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	stub.items[ORE] = { name = "Copper Ore", icon = 135232, sellPrice = 5 }
	stub.items[CLOTH] = { name = "Linen Cloth", icon = 132889, sellPrice = 13 }
	stub.items[HIDE] = { name = "Light Leather", icon = 134256 } -- no sell price, no AH price
	stub.printed = {}
	ns.Print = function(m) stub.printed[#stub.printed + 1] = m end
	stub.now = 100
	return ns, stub
end

local function loot(stub, id, name, count)
	local text = count and count > 1 and LOOT_ITEM_SELF_MULTIPLE:format(link(id, name), count)
		or LOOT_ITEM_SELF:format(link(id, name))
	stub.Fire("CHAT_MSG_LOOT", text, "", "", "", "", "", 0, 0, "", 0, 1, "Player-1-SELF")
end

local function anchor()
	return CraftWiseLootToastAnchor
end

it("parses the player's own loot lines with the client's format strings", function()
	local ns = setup()
	local T = ns.LootToast
	local l, n = T.ParseLoot("You receive loot: " .. link(ORE, "Copper Ore") .. ".")
	eq(T.ItemID(l), ORE); eq(n, 1)
	l, n = T.ParseLoot("You receive loot: " .. link(ORE, "Copper Ore") .. "x12.")
	eq(T.ItemID(l), ORE); eq(n, 12, "the multiple form wins over the single one")
	eq(T.ParseLoot("Grunt receives loot: " .. link(ORE, "Copper Ore") .. "."), nil, "someone else's loot")
	eq(T.ParseLoot("You receive item: " .. link(ORE, "Copper Ore") .. "."), nil, "pushed items are not loot")
	eq(T.ParseLoot(nil), nil)
	issecretvalue = function(v) return v == "SECRET" end
	eq(T.ParseLoot("SECRET"), nil, "a secret value is skipped, not compared")
end)

it("follows another locale's format, positional arguments and magic characters included", function()
	local ns = setup()
	local T = ns.LootToast
	LOOT_ITEM_SELF = "Beute (erhalten): %s."
	LOOT_ITEM_SELF_MULTIPLE = "Beute (erhalten): %2$d x %1$s."
	local l, n = T.ParseLoot("Beute (erhalten): 3 x " .. link(CLOTH, "Leinenstoff") .. ".")
	eq(T.ItemID(l), CLOTH); eq(n, 3)
	l, n = T.ParseLoot("Beute (erhalten): " .. link(CLOTH, "Leinenstoff") .. ".")
	eq(T.ItemID(l), CLOTH); eq(n, 1)
	eq(T.ParseLoot("You receive loot: " .. link(CLOTH, "Linen Cloth") .. "."), nil, "no English fallback")
	LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = nil, nil
	eq(T.ParseLoot("Beute (erhalten): x."), nil, "a client without the strings shows nothing")
end)

it("a loot line becomes a toast line: icon, name in its quality colour without brackets, ×count", function()
	local ns, stub = setup()
	local T = ns.LootToast
	stub.items[ORE].quality = 2
	loot(stub, ORE, "Copper Ore", 4)
	local line = T.Lines()[1]
	eq(#T.Lines(), 1)
	eq(line.itemID, ORE); eq(line.count, 4); eq(line.icon, 135232)
	local p = T.LineParts(line)
	eq(p.name, "Copper Ore", "brackets dropped, no link codes")
	eq(p.color, ns.Style.C.qUncommon, "quality 2 = C.qUncommon")
	eq(p.count, "×4")
	eq(T.LineParts(T.Add({ key = "item:" .. CLOTH, itemID = CLOTH, link = link(CLOTH, "Linen Cloth"), count = 1 }, 100)).count,
		"×1", "a single item shows ×1, as on the board")
	stub.items[9999] = { name = "Odd Relic", quality = 7 }
	eq(T.LineParts({ key = "item:9999", itemID = 9999, count = 1 }).color, ns.Style.C.text,
		"a quality without a constant falls back to C.text; the name comes from the client without a link")
	assert(anchor(), "the anchor frame is built on the first loot")
	assert(anchor():GetScript("OnUpdate"), "fades are driven while lines are shown")
end)

it("lines stack newest first, the same item adds to its line while shown, at most 8 lines", function()
	local ns, stub = setup()
	local T = ns.LootToast
	loot(stub, ORE, "Copper Ore", 2)
	stub.now = 101
	loot(stub, CLOTH, "Linen Cloth", 1)
	eq(T.Lines()[1].itemID, CLOTH)
	stub.now = 102
	loot(stub, ORE, "Copper Ore", 3)
	eq(#T.Lines(), 2, "merged")
	eq(T.Lines()[1].itemID, ORE, "the merged line moves to the top")
	eq(T.Lines()[1].count, 5)
	eq(T.Lines()[1].t, 102, "its timer restarts")
	stub.now = 106.5 -- ore line fading (4 s shown): a new ore loot is a new line
	loot(stub, ORE, "Copper Ore", 1)
	eq(#T.Lines(), 2, "the faded cloth line is gone, the fading ore line stays")
	eq(T.Lines()[1].count, 1); eq(T.Lines()[2].count, 5)
	for i = 1, 10 do
		T.Add({ key = "item:" .. (9000 + i), itemID = 9000 + i, count = 1 }, stub.now)
	end
	eq(#T.Lines(), T.MAX_LINES)
	eq(T.Lines()[1].itemID, 9010, "newest kept"); eq(T.Lines()[8].itemID, 9003, "oldest dropped")
end)

it("each line fades on its own timer: 4 s shown, 1 s fade, then removed", function()
	local ns, stub = setup()
	local T = ns.LootToast
	loot(stub, ORE, "Copper Ore", 1)
	stub.now = 102
	loot(stub, CLOTH, "Linen Cloth", 1)
	local ore, cloth = T.Lines()[2], T.Lines()[1]
	eq(T.Alpha(ore, 104), 1)
	eq(T.Alpha(ore, 104.5), 0.5)
	eq(T.Alpha(cloth, 104.5), 1, "the newer line is still fully shown")
	T.Render(105)
	eq(#T.Lines(), 1, "the ore line is gone at 5 s")
	eq(T.Lines()[1], cloth)
	T.Render(106.75)
	eq(#T.Lines(), 1)
	assert(math.abs(T.Alpha(cloth, 106.75) - 0.25) < 1e-9)
	T.Render(107)
	eq(#T.Lines(), 0)
	eq(anchor():GetScript("OnUpdate"), nil, "nothing runs once every line is gone")
end)

it("value: AH after the cut or vendor, whichever CraftWise uses, times the count; omitted when unknown", function()
	local ns, stub = setup({ auctionator = true })
	local T = ns.LootToast
	stub.ah[ORE] = 100 -- 95 after the 5% cut, beats vendor 5
	eq(T.Value(ORE, 3), 285)
	eq(select(2, T.Value(ORE, 3)), "auction")
	eq(T.Value(CLOTH, 2), 26, "vendor")
	eq(T.Value(HIDE, 4), nil, "no price, no value")
	loot(stub, ORE, "Copper Ore", 3)
	local p = T.LineParts(T.Lines()[1])
	eq(p.money, ns.FormatCoins(285)); eq(p.source, "AH")
	loot(stub, HIDE, "Light Leather", 4)
	p = T.LineParts(T.Lines()[1])
	eq(p.money, nil); eq(p.source, nil)
	SlashCmdList.CRAFTWISE("loottoast value off")
	eq(ns.db.lootToast.value, false)
	eq(T.LineParts(T.Lines()[2]).money, nil, "value switched off")
end)

it("coin: a money gain paired with CHAT_MSG_MONEY, in either order, exact copper", function()
	local ns, stub = setup()
	local T = ns.LootToast
	stub.money = 1000
	stub.Fire("PLAYER_ENTERING_WORLD")
	stub.money = 1234
	stub.Fire("PLAYER_MONEY")
	eq(#T.Lines(), 0, "money alone is not shown yet")
	stub.now = 101
	stub.Fire("CHAT_MSG_MONEY", "You loot 2 Silver, 34 Copper")
	eq(#T.Lines(), 1)
	eq(T.Lines()[1].key, "money"); eq(T.Lines()[1].copper, 234)
	local p = T.LineParts(T.Lines()[1])
	eq(p.name, "Coin"); eq(p.money, ns.FormatCoins(234)); eq(p.count, nil)
	eq(p.source, nil, "coins have no source word")
	-- message first, then the money
	stub.now = 102
	stub.Fire("CHAT_MSG_MONEY", "Your share of the loot is 1 Copper.")
	stub.money = 1244
	stub.Fire("PLAYER_MONEY")
	eq(#T.Lines(), 1, "a second coin loot adds to the coin line")
	eq(T.Lines()[1].copper, 244)
end)

it("coin: vendor sales, mail and spending don't show; a stale message doesn't pair", function()
	local ns, stub = setup()
	local T = ns.LootToast
	stub.money = 5000
	stub.Fire("PLAYER_LOGIN")
	stub.money = 6000
	stub.Fire("PLAYER_MONEY") -- vendor sale, no loot message
	stub.now = 103
	stub.Fire("CHAT_MSG_MONEY", "You loot 5 Copper") -- 3 s later: not the same event
	eq(#T.Lines(), 0)
	stub.now = 106
	stub.money = 6005
	stub.Fire("PLAYER_MONEY")
	eq(#T.Lines(), 0, "the message is stale by now")
	stub.Fire("CHAT_MSG_MONEY", "You loot 5 Copper")
	eq(#T.Lines(), 1); eq(T.Lines()[1].copper, 5)
	stub.now = 107
	stub.Fire("CHAT_MSG_MONEY", "x")
	stub.money = 5000
	stub.Fire("PLAYER_MONEY") -- spending money
	eq(T.Lines()[1].copper, 5)
end)

it("settings: defaults, on/off, duration, lock/unlock, reset", function()
	local ns, stub = setup()
	local T = ns.LootToast
	local s = ns.db.lootToast
	eq(s.enabled, true); eq(s.duration, 4); eq(s.fade, 1); eq(s.value, true); eq(s.locked, true)
	SlashCmdList.CRAFTWISE("LootToast off")
	eq(s.enabled, false)
	loot(stub, ORE, "Copper Ore", 1)
	eq(#T.Lines(), 0, "off: nothing shown")
	SlashCmdList.CRAFTWISE("loottoast on")
	loot(stub, ORE, "Copper Ore", 1)
	eq(#T.Lines(), 1)
	SlashCmdList.CRAFTWISE("loottoast off")
	eq(#T.Lines(), 0, "switching off clears the lines")
	SlashCmdList.CRAFTWISE("loottoast on")
	SlashCmdList.CRAFTWISE("loottoast duration 7.5")
	eq(s.duration, 7.5)
	loot(stub, ORE, "Copper Ore", 1)
	eq(T.Alpha(T.Lines()[1], 107), 1, "longer duration keeps it shown")
	SlashCmdList.CRAFTWISE("loottoast duration 0")
	SlashCmdList.CRAFTWISE("loottoast duration abc")
	eq(s.duration, 7.5, "invalid durations are refused")
	assert(stub.printed[#stub.printed]:find("Usage", 1, true))
	SlashCmdList.CRAFTWISE("loottoast unlock")
	eq(s.locked, false)
	eq(anchor().handle.shown, true, "unlocked: the drag handle shows")
	eq(anchor().outline.shown, true, "and the outline")
	SlashCmdList.CRAFTWISE("loottoast lock")
	eq(s.locked, true)
	eq(anchor().handle.shown, false); eq(anchor().outline.shown, false)
	s.pos = { point = "TOP", relPoint = "TOP", x = 1, y = 2 }
	SlashCmdList.CRAFTWISE("loottoast reset")
	eq(s.pos, nil)
	eq(anchor().lastPoint[1], T.DEFAULT_POS.point)
	local before = #stub.printed
	SlashCmdList.CRAFTWISE("loottoast")
	assert(#stub.printed > before and stub.printed[before + 1]:find("Loot toast on", 1, true), "status")
end)

it("dragging saves the position and the next session puts the anchor there", function()
	local ns = setup()
	SlashCmdList.CRAFTWISE("loottoast unlock")
	local a = anchor()
	a.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 40, -80 end
	a:GetScript("OnDragStop")(a)
	local pos = ns.db.lootToast.pos
	eq(pos.point, "TOPLEFT"); eq(pos.x, 40); eq(pos.y, -80)
	local saved = CraftWiseDB
	local ns2, stub2 = LoadAddon({ savedDB = saved })
	LOOT_ITEM_SELF = "You receive loot: %s."
	stub2.items[ORE] = { name = "Copper Ore" }
	stub2.Fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(link(ORE, "Copper Ore")))
	eq(#ns2.LootToast.Lines(), 1)
	local p = anchor().lastPoint
	eq(p[1], "TOPLEFT"); eq(p[3], "TOPLEFT"); eq(p[4], 40); eq(p[5], -80)
end)

it("test shows three lines labelled test: two bag items with their values and a coin line; real loot doesn't merge into them", function()
	local ns, stub = setup()
	local T = ns.LootToast
	stub.bags[0] = { { itemID = ORE, stackCount = 7, hyperlink = link(ORE, "Copper Ore"), iconFileID = 135232 },
		{ itemID = ORE, stackCount = 2, hyperlink = link(ORE, "Copper Ore") },
		{ itemID = CLOTH, stackCount = 1, hyperlink = link(CLOTH, "Linen Cloth") },
		{ itemID = HIDE, stackCount = 3, hyperlink = link(HIDE, "Light Leather") } }
	SlashCmdList.CRAFTWISE("loottoast test")
	eq(#T.Lines(), 3, "two distinct items and the coin line")
	eq(T.Lines()[1].key, "money")
	eq(T.Lines()[3].count, 7)
	local p = T.LineParts(T.Lines()[3])
	eq(p.money, ns.FormatCoins(35)); eq(p.source, "vendor"); eq(p.test, true)
	for i = 1, 3 do eq(T.LineParts(T.Lines()[i]).test, true, "line " .. i .. " labelled test") end
	loot(stub, ORE, "Copper Ore", 1)
	eq(#T.Lines(), 4, "a real loot is its own line")
	eq(T.Lines()[1].test, nil)
	eq(T.LineParts(T.Lines()[1]).test, nil)
end)

it("strips: 28 tall, cut 8 with a hard shadow, 6 apart, newest on top with the turkuaz flap", function()
	local ns, stub = setup()
	local T, C = ns.LootToast, ns.Style.C
	loot(stub, ORE, "Copper Ore", 1)
	stub.now = 100.5
	loot(stub, CLOTH, "Linen Cloth", 2)
	stub.now = 101
	loot(stub, HIDE, "Light Leather", 1)
	local rows = {}
	for _, f in ipairs(stub.frames) do if f.sheet and f.name and f.count then rows[#rows + 1] = f end end
	eq(#rows, 3)
	for i, row in ipairs(rows) do
		eq(row.height, 28)
		eq(row.sheet.cut, 8)
		assert(row.sheet.shadow, "hard shadow")
		eq(row.lastPoint[5], -(i - 1) * 34, "line " .. i .. " sits 28 + 6 below the one above")
		eq(row.lastPoint[2], anchor())
	end
	eq(rows[1].name.text, "Light Leather", "newest on top")
	eq(rows[1].sheet.flap, C.nokta, "the newest line's flap is turkuaz")
	eq(rows[2].sheet.flap, C.flap); eq(rows[3].sheet.flap, C.flap)
	eq(rows[1].sheet.pieces.c.vertexColor[4], 1, "the turkuaz flap ignores the background alpha")
	eq(rows[1].icon.width, 18)
	eq(rows[2].count.text, "×2"); eq(rows[2].count.shown, true)
	eq(rows[1].test.shown, false, "no test label on real loot")
end)

it("lines step down in alpha (1, 0.75, 0.5) on top of their own timer", function()
	local ns, stub = setup()
	local T = ns.LootToast
	eq(T.StepAlpha(1), 1); eq(T.StepAlpha(2), 0.75); eq(T.StepAlpha(3), 0.5); eq(T.StepAlpha(6), 0.5)
	for i = 1, 4 do
		stub.now = 100 + i * 0.1
		loot(stub, 9000 + i, "Thing " .. i, 1)
	end
	T.Render(100.4)
	local alphas = {}
	for _, f in ipairs(stub.frames) do if f.sheet and f.name then alphas[#alphas + 1] = f.alpha end end
	eq(alphas[1], 1); eq(alphas[2], 0.75); eq(alphas[3], 0.5); eq(alphas[4], 0.5)
	-- 4.6 s later the oldest line (looted at 100.1) is half way through its 1 s fade: 0.5 x 0.6
	assert(math.abs(T.LineAlpha(4, T.Lines()[4], 104.5) - 0.5 * 0.6) < 1e-9)
end)

it("background alpha: 0.70 by default, db.settings.alpha.toast when set, only on the strips' fill", function()
	local ns, stub = setup()
	local T = ns.LootToast
	eq(T.BackgroundAlpha(), 0.70)
	ns.db.settings.alpha = { toast = 0.4 }
	eq(T.BackgroundAlpha(), 0.4)
	loot(stub, ORE, "Copper Ore", 1)
	local row
	for _, f in ipairs(stub.frames) do if f.sheet and f.name then row = f end end
	eq(row.sheet.alpha, 0.4)
	eq(row.sheet.pieces.a.vertexColor[4], 0.4, "the fill")
	eq(row.alpha, 1, "the line itself (icon, text) stays at its step alpha")
	ns.db.settings.alpha = { toast = 3 }
	eq(T.BackgroundAlpha(), 1, "clamped")
	ns.db.settings.alpha = { toast = "x" }
	eq(T.BackgroundAlpha(), 0.70)
end)

it("Move: a white handle and a 1 unit outline over three lines' place", function()
	local ns = setup()
	local T, C = ns.LootToast, ns.Style.C
	SlashCmdList.CRAFTWISE("loottoast unlock")
	local a = anchor()
	eq(a.width, T.WIDTH); eq(a.height, 16)
	eq(a.handle.vertexColor[1], C.text[1])
	eq(a.outline.height, 3 * 28 + 2 * 6)
	eq(a.outline.border.top.vertexColor[1], C.text[1])
	assert(a.label.text:find("drag", 1, true))
end)
