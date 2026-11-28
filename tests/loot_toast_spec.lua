-- Loot toast (issue #114): parsing the client's loot lines, coin pairing, stacking, expiry, value, settings.
local ORE, CLOTH, HIDE = 2770, 2589, 2318

local function near(a, b, msg)
	assert(math.abs(a - b) < 1e-6, (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a))
end

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
	eq(T.Lines()[1].itemID, CLOTH, "the merged line keeps its place")
	eq(T.Lines()[2].itemID, ORE)
	eq(T.Lines()[2].count, 5)
	eq(T.Lines()[2].t, 102, "its timer restarts")
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

local function rowsOf(stub)
	local out = {}
	for _, f in ipairs(stub.frames) do
		if f.name and f.value and f.icon then
			out[#out + 1] = f
		end
	end
	return out
end

it("floating lines: icon 18, '+name' 14 OUTLINE in the quality colour, '+N name', no strips", function()
	local ns, stub = setup()
	local T, C = ns.LootToast, ns.Style.C
	stub.items[ORE].quality = 2
	loot(stub, ORE, "Copper Ore", 1)
	stub.now = 100.5
	loot(stub, CLOTH, "Linen Cloth", 3)
	local rows = rowsOf(stub)
	eq(#rows, 2)
	for _, row in ipairs(rows) do
		assert(not row.sheet, "no Origami strip")
		eq(row.icon.width, 18)
		eq(row.name.font[2], 14); eq(row.name.font[3], "OUTLINE")
		eq(row.value.font[3], "OUTLINE")
	end
	eq(rows[1].name.text, "+3 Linen Cloth", "the newest line is the first row")
	eq(rows[2].name.text, "+Copper Ore", "one item: no number")
	eq(rows[2].name.textColor[1], C.qUncommon[1])
	eq(T.Head(T.Lines()[1], T.LineParts(T.Lines()[1])), "+3 Linen Cloth")
	eq(rows[2].name.lastPoint[2], rows[2].icon, "the name sits right of the icon")
	eq(rows[2].name.lastPoint[4], 6)
end)

it("the value follows the name on the same line, muted: plain '12s 40c AH' text, no coin colours", function()
	local ns, stub = setup({ auctionator = true })
	local C = ns.Style.C
	stub.ah[ORE] = 100
	loot(stub, ORE, "Copper Ore", 3)
	local row = rowsOf(stub)[1]
	eq(row.value.text, ns.FormatCoins(285):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " AH")
	assert(not row.value.text:find("|c", 1, true))
	eq(row.value.textColor[1], C.text2[1])
	eq(row.value.lastPoint[2], row.name, "anchored to the name")
	eq(row.value.lastPoint[4], 8)
	loot(stub, HIDE, "Light Leather", 4)
	eq(rowsOf(stub)[1].value.shown, false, "no value, no value text")
	SlashCmdList.CRAFTWISE("loottoast value off")
	loot(stub, ORE, "Copper Ore", 1)
	eq(rowsOf(stub)[1].value.shown, false, "value off")
end)

it("a long name is cut before the value is: the name's width is what the area leaves after icon and value", function()
	local ns, stub = setup({ auctionator = true })
	stub.ah[ORE] = 100
	loot(stub, ORE, "Copper Ore", 3)
	local row = rowsOf(stub)[1]
	-- the stub measures every text 80 wide: 252 - 24 (icon + gap) - (80 + 8) = 140 room, the 80 wide name fits
	eq(row.name.width, 80)
	eq(row.value.shown, true)
	local name = row.name
	name.GetStringWidth = function() return 400 end
	loot(stub, ORE, "Copper Ore", 1)
	eq(name.width, 140, "cut to what is left, the value keeps its 80")
	eq(row.value.lastPoint[2], name)
end)

it("coin: '+coins' in gold, no icon, at the left; test lines say test", function()
	local ns, stub = setup()
	local T, C = ns.LootToast, ns.Style.C
	T.ShowMoney(12345)
	local row = rowsOf(stub)[1]
	eq(row.name.text, "+" .. ns.FormatCoins(12345):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	eq(row.name.textColor[1], C.coinGold[1])
	eq(row.icon.shown, false)
	eq(row.name.lastPoint[2], row, "starts at the left of the row")
	eq(row.value.shown, false)
	T.Clear()
	T.Add({ key = "money", copper = 5, count = 0, test = true }, GetTime())
	T.Render(GetTime())
	eq(rowsOf(stub)[1].value.text, "test")
end)

it("lines of other features: detail and profit after the name, clickable", function()
	local ns, stub = setup()
	local T = ns.LootToast
	local clicked
	T.ShowCustom({ key = "alert", text = "Silk Cloth", detail = "8 or more", copper = 500, icon = 1, onClick = function() clicked = true end })
	local row = rowsOf(stub)[1]
	eq(row.name.text, "Silk Cloth", "not a gain: no +")
	assert(row.value.text:find("8 or more", 1, true) and row.value.text:find("per craft", 1, true), row.value.text)
	row.scripts.OnMouseUp(row)
	eq(clicked, true)
	-- as wide as its text, not cut at the area's width: icon 24 + name + 8 + value (the stub measures 80 each)
	T.Clear()
	local long = T.ShowCustom({ key = "restock", text = "Raptor Hide Harness may be back at Tunkk (Stranglethorn Vale)", icon = 1 })
	row = rowsOf(stub)[1]
	eq(row.name.text, long.text)
	local name = row.name
	name.GetStringWidth = function() return 400 end
	T.Render(GetTime())
	eq(name.width, 400, "not cut at 252")
	eq(row.width, 24 + 400, "the row is as wide as its content")
	name.GetStringWidth = function() return 900 end
	T.Render(GetTime())
	eq(name.width, 480 - 24, "a cap far wider than the area")
	-- loot lines are still capped at the area and cut before the value
	T.Clear()
	loot(stub, ORE, "Copper Ore", 1)
	row = rowsOf(stub)[1]
	eq(row.name.text, "+Copper Ore")
	row.name.GetStringWidth = function() return 900 end
	T.Render(GetTime())
	eq(row.name.width, 252 - 24 - 88, "cut before the value: icon 24, value 80 + 8")
end)

it("lines float up at (200 - 18) / life, fade in over 0.2 s, fade out over the fade", function()
	local ns, stub = setup()
	local T = ns.LootToast
	eq(T.Life(), 5)
	loot(stub, ORE, "Copper Ore", 1)
	local line = T.Lines()[1]
	eq(line.y, 0)
	local row = rowsOf(stub)[1]
	eq(row.lastPoint[1], "BOTTOMLEFT"); eq(row.lastPoint[2], anchor()); eq(row.lastPoint[5], 0)
	eq(row.alpha, 0, "starts invisible")
	T.Render(100.1)
	near(row.alpha, 0.5); near(line.y, 182 / 5 * 0.1)
	T.Render(102)
	eq(row.alpha, 1); near(line.y, 182 / 5 * 2)
	near(row.lastPoint[5], 182 / 5 * 2)
	T.Render(104.5)
	near(row.alpha, 0.5, "half way through the 1 s fade")
	T.Render(105)
	eq(#T.Lines(), 0, "gone at duration + fade")
	eq(anchor():GetScript("OnUpdate"), nil, "and nothing runs")
	SlashCmdList.CRAFTWISE("loottoast duration 9")
	eq(T.Life(), 10)
end)

it("a new line starts at the bottom and pushes the older ones up to keep 22 apart", function()
	local ns, stub = setup()
	local T = ns.LootToast
	loot(stub, ORE, "Copper Ore", 1)
	stub.now = 100.1
	loot(stub, CLOTH, "Linen Cloth", 1)
	local l = T.Lines()
	eq(l[1].y, 0); near(l[2].y, 22)
	stub.now = 100.2
	loot(stub, HIDE, "Light Leather", 1)
	eq(l[1].y, 0); near(l[2].y, 22); near(l[3].y, 44)
	T.Render(101)
	near(l[1].y, 0.8 * 36.4); near(l[2].y, l[1].y + 22); near(l[3].y, l[2].y + 22)
end)

it("merging updates the line in place: same place and height, timer restarted, slower so it still reaches the top as it fades", function()
	local ns, stub = setup()
	local T = ns.LootToast
	loot(stub, ORE, "Copper Ore", 2)
	stub.now = 101
	loot(stub, CLOTH, "Linen Cloth", 1)
	stub.now = 102
	T.Render(102)
	local l = T.Lines()
	local ore, cloth = l[2], l[1]
	local oreY, clothY = ore.y, cloth.y
	assert(oreY > 50, "the ore line is well up")
	loot(stub, ORE, "Copper Ore", 1)
	eq(#l, 2); eq(l[2], ore); eq(l[1], cloth, "order unchanged")
	eq(ore.count, 3); eq(ore.t, 102)
	eq(ore.y, oreY, "no jump"); eq(cloth.y, clothY, "nothing else moves")
	eq(T.LineAlpha(ore, 102), 1, "no new fade-in")
	T.Render(104.5) -- half of the new life: half of the way left
	assert(ore.y >= oreY + (182 - oreY) / 2 - 1e-6 and ore.y < 182, "on its way up, no jump back (the cloth line below may push it a little)")
	T.Render(106.999)
	assert(math.abs(ore.y - 182) < 0.1, "reaches the top just as its life ends: " .. ore.y)
	T.Render(107)
	eq(#l, 0)
end)

it("a merged line pushed into the top by a faster newer line fades out instead of popping", function()
	local ns, stub = setup()
	local T = ns.LootToast
	loot(stub, ORE, "Copper Ore", 1)
	stub.now = 101
	loot(stub, CLOTH, "Linen Cloth", 1)
	stub.now = 102
	loot(stub, ORE, "Copper Ore", 1)
	local ore = T.Lines()[2]
	-- walk through the rest of the life: the alpha never jumps by more than a frame's worth of fade
	local last = 1
	for i = 1, 400 do
		local now = 102 + i * 0.01
		T.Render(now)
		if ore.y and #T.Lines() == 2 then
			local a = T.LineAlpha(ore, now)
			assert(last - a < 0.1, "popped at " .. now .. ": " .. last .. " -> " .. a)
			last = a
		end
	end
	T.Render(106)
	assert(#T.Lines() == 0 or T.Lines()[2] ~= ore or T.LineAlpha(ore, 106) < 0.25)
	-- a line at the top is invisible, whatever its timer says
	local l = { t = 100, born = 100, y = 182 }
	eq(T.LineAlpha(l, 101), 0)
	l.y = 182 - 182 * 1 / 5 / 2 -- half way through the fade space
	near(T.LineAlpha(l, 101), 0.5)
end)

it("a line of another feature is cut to the space left of the screen's right edge", function()
	local ns, stub = setup()
	local T = ns.LootToast
	T.ShowCustom({ key = "r", text = "Raptor Hide Harness may be back at Tunkk", icon = 1 })
	local name = rowsOf(stub)[1].name
	name.GetStringWidth = function() return 700 end
	UIParent.GetRight = function() return 1000 end
	anchor().GetLeft = function() return 800 end
	T.Render(GetTime())
	eq(name.width, 1000 - 800 - 4 - 24, "what is left of the screen")
	anchor().GetLeft = function() return 990 end
	T.Render(GetTime())
	eq(name.width, 120 - 24, "never narrower than the floor")
end)

it("a line pushed to the top is removed there; at most 8 lines fit", function()
	local ns, stub = setup()
	local T = ns.LootToast
	for i = 1, T.MAX_LINES do
		stub.now = 100 + i * 0.01
		T.ShowCustom({ key = "k" .. i, text = "Line " .. i, icon = 1 })
	end
	T.Render(100.1)
	eq(#T.Lines(), 8)
	local l = T.Lines()
	assert(l[8].y <= T.HEIGHT - T.TOP_MARGIN, "8 x 22 apart still fits")
	l[8].y = 190
	T.Render(100.2)
	eq(#T.Lines(), 7, "past the top margin: gone")
end)

it("Move: the whole 260 x 200 area shows as a dark box with a 1 unit outline and a label", function()
	local ns = setup()
	local T, C = ns.LootToast, ns.Style.C
	SlashCmdList.CRAFTWISE("loottoast unlock")
	local a = anchor()
	eq(a.width, 260); eq(a.height, 200)
	eq(a.handle.vertexColor[1], C.sheet[1]); eq(a.handle.vertexColor[4], 0.6)
	eq(a.outline.border.top.vertexColor[1], C.text[1])
	assert(a.label.text:find("drag", 1, true))
end)
