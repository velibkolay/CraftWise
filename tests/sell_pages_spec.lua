-- Sell section of the main window (#155, spec in #150 "Sell", boards "Sell › Bags", "Sell › Auctions",
-- "Sell › Ledger"): groups, hero, cards, period chips, Reset "Click again", empty states, and the old homes
-- (profit window Bags view, Records › Ledger and Auctions) gone. Invented data only.
local NOW = os.time({ year = 2026, month = 11, day = 12, hour = 15 })
local DAY = 86400
local HORDE = "PvP|H"
local LINEN, SWORD, BOOTS, GREY, ROCK, SALT = 990100, 990200, 990300, 990400, 990600, 990700
local LEATHER, HIDE, PANTS, CLOAK, BRACERS = 990801, 990802, 990803, 990804, 990805

local function has(text, s)
	assert(tostring(text):find(s, 1, true), ("missing %q in:\n%s"):format(s, tostring(text)))
end

local function Load(opts)
	local ns, stub = LoadAddon(opts)
	stub.clock = NOW
	time = function(t)
		if t then return os.time(t) end
		return stub.clock
	end
	stub.names.player, stub.surnames.player = "Testperson", "Sample"
	stub.money = 90000
	stub.Fire("PLAYER_LOGIN")
	stub.Fire("PLAYER_ENTERING_WORLD", true, false)
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 3600, kind = "full" } } -- AH status "1 h ago"
	return ns, stub, ns.Main
end

local function Rows(M, key)
	local out = {}
	for _, fr in ipairs(M.ListOf(key).box.frames) do
		out[#out + 1] = fr
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- Bags
----------------------------------------------------------------------------------------------------

local function Bags(opts)
	local ns, stub, M = Load({ auctionator = true })
	stub.items[LINEN] = { name = "Test Cloth", sellPrice = 13 }
	stub.items[SWORD] = { name = "Test Sword", sellPrice = 500 }
	stub.items[BOOTS] = { name = "Bound Test Boots", sellPrice = 300 }
	stub.items[GREY] = { name = "Test Scrap", sellPrice = 7 }
	stub.items[ROCK] = { name = "Odd Test Rock" }
	stub.items[SALT] = { name = "Test Salt", sellPrice = 10 }
	stub.itemClass[SWORD], stub.itemClass[BOOTS] = 2, 4
	stub.bags[0] = {
		{ itemID = LINEN, stackCount = 20, quality = 1 },
		{ itemID = SWORD, stackCount = 1, quality = 2 },
		{ itemID = LINEN, stackCount = 5, quality = 1 },
		{ itemID = ROCK, stackCount = 1, quality = 1 },
		{ itemID = SALT, stackCount = 4, quality = 1 },
	}
	stub.bags[1] = {
		{ itemID = BOOTS, stackCount = 1, quality = 2, isBound = true },
		{ itemID = GREY, stackCount = 3, quality = 0 },
	}
	stub.ah[LINEN], stub.ah[SWORD], stub.ah[BOOTS] = 50, 400, 9999
	ns.ToggleJunk(GREY)
	ns.ToggleKeep(SALT)
	if not (opts and opts.closed) then
		M.Open("bags")
	end
	return ns, stub, M
end

it("Bags: every item grouped by its best outcome; group rows with title, count and reason, total right", function()
	local ns, _, M = Bags()
	eq(ns.db.settings.showKept, true, "kept items show by default (as before)")
	ns.db.settings.showKept = false
	M.Refresh()
	eq(M.shown.page, "bags"); eq(M.shown.state, "list")
	local P = M.Page("bags").P
	local rows = P.Rows(ns.BagRows(), {})
	local shape = {}
	for _, r in ipairs(rows) do shape[#shape + 1] = r.group and ("[" .. r.groupKey .. "]") or tostring(r.itemID) end
	eq(table.concat(shape, " "), ("[auction] %d [vendor] %d %d [none] %d [junk] %d"):format(LINEN, SWORD, BOOTS, ROCK, GREY),
		"AH, vendor (by value), no price, junk; kept hidden")
	eq(rows[1].title, "Sell at the AH"); eq(rows[1].note, "1 item · AH beats vendor by your AH rule")
	eq(rows[1].total, 1187) -- 50 x 0.95 x 25, rounded down
	eq(rows[3].title, "Sell to a vendor"); eq(rows[3].note, "2 items · no AH price, or vendor pays more"); eq(rows[3].total, 800)
	eq(rows[8].title, "Junk"); eq(rows[8].note, "1 item · sold with Sell junk at any merchant"); eq(rows[8].total, 21)
	eq(rows[6].title, "No price"); eq(rows[6].total, nil)
	-- Show kept adds the Keep group before Junk, its items without a value
	local kept = P.Rows(ns.BagRows(), { showKept = true })
	eq(kept[#kept - 3].groupKey, "keep"); eq(kept[#kept - 3].note, "1 item · marked Keep, or quest items")
	eq(kept[#kept - 2].itemID, SALT); eq(kept[#kept - 2].value, nil); eq(kept[#kept - 2].mark, "Keep")
	-- drawn: no header row; the group rows carry the 2 unit C.text rule
	local list = M.ListOf("bags")
	eq(list.head.shown, false); eq(list.box.points[1][5], 0)
	local frames = Rows(M, "bags")
	local g = frames[1]
	eq(g.cwGroup.title.text, "Sell at the AH"); eq(g.cwGroup.title.fontObject, ns.Style.Fonts.Section)
	eq(g.cwGroup.note.text, "1 item · AH beats vendor by your AH rule")
	eq(g.cwGroup.total.text, ns.FormatCoins(1187))
	eq(g.cwGroup.rule.height, 2); eq(g.hair.shown, false); eq(g.cells[2].shown, false)
	local linen = frames[2]
	eq(linen.cells[2].text, "Test Cloth"); eq(linen.cells[3].text, "×25"); eq(linen.cells[6].text, ns.FormatCoins(1187))
	eq(linen.cells[6].fontObject, ns.Style.Fonts.FigureBold)
	has(linen.cells[4].text, ns.FormatCoins(47) .. " each"); has(linen.cells[4].text, "vendor " .. ns.FormatCoins(13) .. " each")
	eq(linen.hair.shown, true); eq(linen.cwGroup.title.shown, false)
	-- sword: quality colour; vendor note names the AH after cut
	local sword = frames[4]
	eq(sword.cells[2].textColor[1], ns.Style.C.qUncommon[1])
	has(sword.cells[4].text, "AH " .. ns.FormatCoins(380) .. " after cut")
end)

it("Bags: marks as line tags; My crafting materials and Show kept filter; hidden ones counted in the footer", function()
	local ns, _, M = Bags()
	ns.db.settings.showKept = false
	ns.db.sellAH = ns.db.sellAH or {}
	ns.db.sellAH[SWORD] = true
	ns.Notify("BAGS_CHANGED")
	local tags = {}
	for _, fr in ipairs(Rows(M, "bags")) do
		local r = fr.elementData.row
		if not r.group and fr.cwTag and fr.cwTag.shown then tags[r.itemID] = fr.cwTag.label.text end
	end
	eq(tags[SWORD], "AH", "marked Sell on AH: shown as Auction with an AH tag")
	eq(tags[GREY], "Junk"); eq(tags[LINEN], nil)
	local f = M.Frame()
	eq(f.foot.right.text, "1 hidden by the filters", "the kept item")
	local tools = M.SlotsOf("bags").tools
	eq(tools.kept.on, false)
	tools.kept.scripts.OnClick(tools.kept)
	eq(ns.db.settings.showKept, true); eq(tools.kept.on, true)
	eq(f.foot.right.text, "")
	local salt
	for _, fr in ipairs(Rows(M, "bags")) do
		if fr.elementData.row.itemID == SALT then salt = fr end
	end
	eq(salt.cwTag.label.text, "Keep"); eq(salt.icons[1].desaturated, true); eq(salt.cells[6].text, "")
	tools.mats.scripts.OnClick(tools.mats)
	eq(ns.db.settings.bagsMatsOnly, true)
	eq(#Rows(M, "bags"), 0, "no item is a material of a known recipe")
	eq(M.ListOf("bags").empty.text, "Every item is hidden by My crafting materials or Show kept.")
end)

it("Bags: hero 'What your bags would bring': total, AH / vendor / junk, the three-part bar", function()
	local ns, _, M = Bags()
	local f = M.Frame()
	eq(f.hero.shown, true); eq(f.hero.label.text, "What your bags would bring")
	eq(f.hero.sheet.cut, 14); eq(f.hero.figure.text, "", "the page draws the figure")
	local slot = M.SlotsOf("bags").hero
	eq(slot.total.text, ns.FormatCoins(2008)); eq(slot.total.fontObject, ns.Style.Fonts.FigureL)
	eq(slot.uncounted.text, "1 item without a price not counted")
	local labels, figures = {}, {}
	for i, stat in ipairs(slot.parts) do labels[i], figures[i] = stat.label.text, stat.figure.text end
	eq(table.concat(labels, "|"), "Sell at the AH, after cut|Sell to a vendor|Junk")
	eq(figures[1], ns.FormatCoins(1187)); eq(figures[2], ns.FormatCoins(800)); eq(figures[3], ns.FormatCoins(21))
	eq(slot.parts[2].square.vertexColor[1], ns.Style.C.coinGold[1], "legend square in coin gold")
	-- bar: white, coin gold, rule-strong; 2 unit gaps, as wide as the card's inside (880 - 44 - 32)
	local g = slot.bar.geometry
	eq(#g, 3); eq(g[1].key, "auction"); eq(g[2].key, "vendor"); eq(g[3].key, "junk")
	eq(g[1].x, 0); eq(g[2].x, g[1].width + 2); eq(g[3].x + g[3].width, 804)
	assert(math.abs(g[1].width - 800 * 1187 / 2008) <= 1, "AH share")
	eq(slot.bar.pieces[1].vertexColor[1], ns.Style.C.text[1]); eq(slot.bar.pieces[3].vertexColor[1], ns.Style.C.ruleStrong[1])
	eq(slot.bar.height, 6)
	-- the hero slot belongs to the page: hidden on another page
	M.ShowPage("ledger")
	eq(slot.shown, false)
end)

it("Bags: a click opens the item menu; Sort bags runs the sort; no price says why; footer names the bag click", function()
	local ns, stub, M = Bags()
	local opened
	ns.ShowItemMenu = function(id) opened = id end
	local list = M.ListOf("bags")
	local frames = Rows(M, "bags")
	eq(list:Click(frames[2], "LeftButton"), "click"); eq(opened, LINEN)
	opened = nil
	eq(list:Click(frames[1], "LeftButton"), "click"); eq(opened, nil, "a group row does nothing")
	local rock
	for _, fr in ipairs(frames) do if fr.elementData.row.itemID == ROCK then rock = fr end end
	eq(rock.cells[6].text, "—")
	has(rock.cells[4].text, "no price")
	rock.hits[6].scripts.OnEnter(rock.hits[6])
	eq(CraftWiseInverseTip.title.text, "No value")
	has(CraftWiseInverseTip.body.text, "no vendor price")
	eq(M.Frame().foot.left.text,
		"Click an item: Keep · Junk · Sell on AH · Where to buy · Price history. In your bags: middle-click.")
	local started = 0
	ns.BagSort.Start = function() started = started + 1 end
	local sort = M.SlotsOf("bags").tools.sort
	eq(sort.label.text, "Sort bags")
	sort.scripts.OnClick(sort)
	eq(started, 1)
	ns.BagSort.Running = function() return true end
	M.Refresh()
	eq(sort.label.text, "Sorting"); eq(sort.label.textColor[1], ns.Style.C.live[1], "orange while it runs")
end)

it("Bags: empty bags, no prices, stale ages and skeletons while scanning", function()
	local ns, stub, M = Bags({ closed = true })
	CraftWiseMarketDB.scans[HORDE] = { { t = NOW - 3 * DAY - 60, kind = "full" } }
	stub.ahAge[LINEN] = 3
	M.Open("bags")
	eq(M.Frame().notice.shown, true, "the stale card")
	local linen = Rows(M, "bags")[2]
	has(linen.cells[4].text, ns.Style.Hex("danger") .. "3 d|r")
	-- scanning: a missing value is a skeleton bar
	local P = M.Page("bags").P
	local fr = Rows(M, "bags")[7]
	eq(fr.elementData.row.itemID, ROCK)
	P.InitRow(fr, fr.elementData.row, { prices = { scanning = { done = 1, total = 2 } } })
	eq(fr.cwSkeleton.shown, true); eq(fr.cells[6].text, "")
	-- empty bags: no hero, the empty line
	stub.bags = {}
	ns.Notify("BAGS_CHANGED")
	eq(M.Frame().hero.shown, false)
	eq(M.ListOf("bags").empty.text, "Your bags are empty.")
	-- no AH observation and no Auctionator: the No prices state, vendor values on request
	CraftWiseMarketDB.scans[HORDE] = nil
	stub.DisableAuctionator()
	M.Refresh()
	eq(M.shown.state, "noPrices")
end)

----------------------------------------------------------------------------------------------------
-- Auctions
----------------------------------------------------------------------------------------------------

local function Auctions()
	local ns, stub, M = Load()
	AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE = "12 Hours", "24 Hours", "48 Hours"
	stub.items[PANTS] = { name = "Test Pants", quality = 2 }
	stub.items[CLOAK] = { name = "Test Cloak", quality = 2 }
	stub.items[LEATHER] = { name = "Test Leather" }
	stub.items[HIDE] = { name = "Test Hide" }
	stub.items[BRACERS] = { name = "Test Bracers", quality = 2 }
	local list = ns.Auctions.List()
	list[#list + 1] = { id = 1, i = PANTS, n = "Test Pants", q = 1, unit = 28500, dep = 500, st = "sold", soldT = NOW - 1140, h = HORDE }
	list[#list + 1] = { id = 2, i = CLOAK, n = "Test Cloak", q = 1, unit = 19600, st = "sold", soldT = NOW - 600, h = HORDE }
	list[#list + 1] = { id = 3, i = LEATHER, n = "Test Leather", q = 20, unit = 1000, dep = 300, st = "active", exp = NOW + 11 * 3600, h = HORDE }
	list[#list + 1] = { id = 4, i = HIDE, n = "Test Hide", q = 5, bid = 50, st = "active", exp = NOW + 5 * 3600, h = HORDE }
	list[#list + 1] = { id = 5, i = BRACERS, n = "Test Bracers", q = 1, unit = 9500, dep = 150, st = "expired", expT = NOW - 120, h = HORDE }
	list[#list + 1] = { id = 6, i = PANTS, n = "Test Pants", q = 1, unit = 1, st = "settled", settledT = NOW - 60, h = HORDE }
	return ns, stub, M
end

it("Auctions: three cards: on its way after cut and deposit back, if all listed sell, returning", function()
	local ns, _, M = Auctions()
	M.Open("auctions")
	eq(M.shown.state, "list")
	local f = M.Frame()
	eq(f.hero.shown, true); eq(f.hero.sheet.pieces.a.shown, false, "no card behind the three cards")
	local cards = M.SlotsOf("auctions").hero.cards
	eq(#cards, 3)
	-- 28500 - 1425 (5%) + 500 deposit, 19600 - 980 (deposit not seen)
	eq(cards[1].stat.label.text, "On its way · in the mail")
	eq(cards[1].stat.figure.text, ns.FormatCoins(27575 + 18620))
	eq(cards[1].stat.caption.text, "2 sold, after cut and deposit back")
	eq(cards[2].stat.label.text, "If all listed sell")
	eq(cards[2].stat.figure.text, ns.FormatCoins(19000 + 300))
	eq(cards[2].stat.caption.text, "2 listed · 1 without a buyout not counted")
	eq(cards[3].stat.label.text, "Returning"); eq(cards[3].stat.figure.text, "1"); eq(cards[3].stat.unit.text, "item")
	eq(cards[3].stat.caption.text, "expired, deposit lost " .. ns.FormatCoins(150))
	eq(cards[1].sheet.cut, 14); eq(cards[1].stat.figure.fontObject, ns.Style.Fonts.FigureL)
	-- cards and rows agree
	local P = M.Page("auctions").P
	local rows = P.Rows(ns.Auctions.List(), NOW)
	local sold = 0
	for _, r in ipairs(rows) do if r.status == "sold" then sold = sold + r.youGet end end
	eq(sold, 27575 + 18620)
	has(f.foot.left.text, "You get: buyout minus the 5% cut (confirmed), plus the deposit back.")
end)

it("Auctions: one list: Item, Qty, Status, When, Buyout, You get; sold, listed, returning; Listed is live", function()
	local ns, _, M = Auctions()
	M.Open("auctions")
	local list = M.ListOf("auctions")
	local heads = {}
	for i = 2, 7 do heads[#heads + 1] = list.headers[i].label.text end
	eq(table.concat(heads, ","), "Item,Qty,Status,When,Buyout,You get")
	local frames = Rows(M, "auctions")
	eq(#frames, 5, "settled auctions are done and leave the list")
	local got = {}
	for _, fr in ipairs(frames) do
		got[#got + 1] = table.concat({ fr.cells[2].text, fr.cells[3].text, fr.cells[4].text, fr.cells[5].text, fr.cells[6].text,
			fr.cells[7].text }, "|")
	end
	local C = ns.FormatCoins
	eq(got[1], "Test Cloak|1|Sold|sold 10 min ago|" .. C(19600) .. "|" .. C(18620))
	eq(got[2], "Test Pants|1|Sold|sold 19 min ago|" .. C(28500) .. "|" .. C(27575))
	eq(got[3], "Test Hide|5|Listed|ends in 5 h|no buyout|—")
	eq(got[4], "Test Leather|20|Listed|ends in 11 h|" .. C(20000) .. "|" .. C(19300))
	eq(got[5], "Test Bracers|1|Returning|expired · 2 min ago|" .. C(9500) .. "|—")
	eq(frames[3].cwLive.shown, true, "orange diamond on Listed"); eq(frames[3].cwLive.vertexColor[1], ns.Style.C.live[1])
	eq(frames[1].cwLive.shown, false)
	eq(frames[3].cells[4].textColor[1], ns.Style.C.live[1]); eq(frames[5].cells[4].textColor[1], ns.Style.C.text2[1])
	eq(frames[1].cells[2].textColor[1], ns.Style.C.qUncommon[1])
	-- reasons on hover
	frames[3].hits[7].scripts.OnEnter(frames[3].hits[7])
	eq(CraftWiseInverseTip.title.text, "Not counted"); eq(CraftWiseInverseTip.body.text, "no buyout")
	frames[1].hits[7].scripts.OnEnter(frames[1].hits[7])
	eq(CraftWiseInverseTip.title.text, "Deposit back unknown")
	frames[5].hits[7].scripts.OnEnter(frames[5].hits[7])
	eq(CraftWiseInverseTip.body.text, "The item comes back by mail; the deposit is lost.")
	-- the owned list line in the sub bar
	eq(M.SlotsOf("auctions").tools.owned.text, "Testperson Sample · owned list not read yet")
	CraftWiseMarketDB.auctions.chars[ns.CharKey()].ownedAt = NOW - 12 * 60
	M.Refresh()
	eq(M.SlotsOf("auctions").tools.owned.text, "Testperson Sample · owned list read 12 min ago")
	-- a listing without its end time names its duration; one past its end says so
	local P = M.Page("auctions").P
	eq(P.WhenText({ st = "active", dur = 2 }, NOW), "listed for 24 hours")
	eq(P.WhenText({ st = "active", exp = NOW - 5 }, NOW), "time is up")
	eq(P.WhenText({ st = "cancelled", cancelT = NOW - 3600 }, NOW), "cancelled · 1 h ago")
	P.MAIL_DELAY = 3600 -- once the delay is verified (#155): "mail in"
	eq(P.WhenText({ st = "sold", soldT = NOW - 19 * 60 }, NOW), "mail in 41 min")
	eq(P.WhenText({ st = "expired", expT = NOW - 2 * 60 }, NOW), "expired · mail in 58 min")
end)

it("Auctions: nothing recorded: no cards, the empty line", function()
	local _, _, M = Load()
	M.Open("auctions")
	eq(M.shown.state, "list")
	eq(M.Frame().hero.shown, false)
	eq(M.ListOf("auctions").empty.text, "No auction listed, sold or returning. Post one and it shows here.")
end)

----------------------------------------------------------------------------------------------------
-- Ledger
----------------------------------------------------------------------------------------------------

local function Ledger()
	local ns, stub, M = Load()
	stub.items[SALT] = { name = "Test Salt", sellPrice = 10 }
	stub.items[BOOTS] = { name = "Test Boots", sellPrice = 70, quality = 2 }
	local c = CraftWiseMarketDB.ledger.chars[ns.CharKey()]
	c.days = { ["2026-11-10"] = 50000, ["2026-11-11"] = 80000, ["2026-11-12"] = 70000 }
	c.reset = { t = NOW - 3 * DAY, money = 50000 }
	stub.clock = NOW - 26 * 3600 -- 11 Nov
	ns.Ledger.Record("vbuy", SALT, 5, 600, "Test Vendor")
	stub.clock = NOW - 3600 -- today
	ns.Ledger.Record("vbuy", SALT, 2, 240, "Test Vendor")
	ns.Ledger.Record("vsell", BOOTS, 1, 7000, "Test Vendor")
	stub.clock = NOW
	return ns, stub, M
end

it("Ledger: Per day by default: rows with today's nokta, Start, Spent, Received, a zero-centred rail", function()
	local ns, _, M = Ledger()
	M.Open("ledger")
	local chips = M.SlotsOf("ledger").tools.chips
	local labels = {}
	for _, key in ipairs({ "reset", "today", "login", "days" }) do labels[#labels + 1] = chips[key].label.text end
	eq(table.concat(labels, ","), "Since reset,Today,Since login,Per day")
	eq(chips.days.on, true); eq(chips.today.on, false)
	local list = M.ListOf("ledger")
	local heads = {}
	for i = 1, 5 do heads[#heads + 1] = list.headers[i].label.text end
	eq(table.concat(heads, ","), "Day,Start,Spent,Received,Money change")
	local frames = Rows(M, "ledger")
	eq(#frames, 3)
	local today, wed, tue = frames[1], frames[2], frames[3]
	eq(today.cells[1].text, "Today"); eq(today.cwToday.shown, true); eq(today.bg.shown, true, "C.selected behind today")
	eq(wed.cells[1].text, "Wed 11"); eq(wed.cwToday.shown, false); eq(tue.cells[1].text, "Tue 10")
	eq(today.cells[2].text, ns.FormatCoins(70000)); eq(today.cells[3].text, "−" .. ns.FormatCoins(240))
	eq(today.cells[4].text, "+" .. ns.FormatCoins(7000)); eq(wed.cells[4].text, "—")
	eq(today.cells[6].text, "+" .. ns.FormatCoins(20000))
	eq(wed.cells[6].text, ns.FormatCoins(-10000)); eq(wed.cells[6].textColor[1], ns.Style.C.danger[1], "a loss in red")
	-- rails on one shared scale (the largest change fills), zero at 30 %, today's bar in C.text
	eq(tue.cwRail.value, 30000); eq(tue.cwRail.maxAbs, 30000); eq(tue.cwRail.zeroAt, 0.3)
	eq(today.cwRail.selected, true); eq(wed.cwRail.value, -10000)
	-- hero: the recorded days summed
	local f = M.Frame()
	eq(f.hero.label.text, "Last 3 days")
	local slot = M.SlotsOf("ledger").hero
	eq(slot.change.figure.text, "+" .. ns.FormatCoins(40000)); eq(slot.change.caption.text, "money change · 3 days recorded")
	eq(slot.parts[1].label.text, "Spent"); eq(slot.parts[1].figure.text, ns.FormatCoins(840))
	eq(slot.parts[2].figure.text, ns.FormatCoins(7000))
	eq(slot.parts[3].label.text, "Not from logged trades"); eq(slot.parts[3].caption.text, "loot, quests, mail")
	eq(slot.parts[3].figure.text, "+" .. ns.FormatCoins(40000 - 6160))
	eq(f.foot.left.text, "A day ends with the money the next recorded day started with.")
end)

it("Ledger: Today, Since login and Since reset list the items: Item, Bought at, Bought, Sold, Net", function()
	local ns, _, M = Ledger()
	M.Open("ledger")
	local chips = M.SlotsOf("ledger").tools.chips
	chips.today.scripts.OnClick(chips.today)
	eq(ns.db.settings.ledgerView, "today", "the view /craftwise ledger uses"); eq(ns.db.settings.ledgerPerDay, false)
	eq(chips.today.on, true); eq(chips.days.on, false)
	local list = M.ListOf("ledger")
	local heads = {}
	for i = 2, 6 do heads[#heads + 1] = list.headers[i].label.text end
	eq(table.concat(heads, ","), "Item,Bought at,Bought,Sold,Net")
	local frames = Rows(M, "ledger")
	eq(#frames, 2)
	local boots, salt = frames[1].elementData.row, frames[2].elementData.row
	eq(boots.itemID, BOOTS); eq(salt.itemID, SALT)
	eq(frames[1].cells[5].text, "1  " .. ns.FormatCoins(7000)); eq(frames[1].cells[4].text, "—")
	eq(frames[2].cells[3].text, "vendor"); eq(frames[2].cells[4].text, "2  " .. ns.FormatCoins(240))
	eq(frames[2].cells[6].text, ns.FormatCoins(-240)); eq(frames[2].cells[6].textColor[1], ns.Style.C.danger[1])
	eq(frames[1].cells[2].textColor[1], ns.Style.C.qUncommon[1])
	eq(frames[1].cwRail and frames[1].cwRail.shown or false, false)
	local f = M.Frame()
	eq(f.hero.label.text, "Today")
	local slot = M.SlotsOf("ledger").hero
	eq(slot.change.figure.text, "+" .. ns.FormatCoins(20000))
	has(slot.change.caption.text, "start " .. ns.FormatCoins(70000))
	-- since reset includes 11 Nov
	chips.reset.scripts.OnClick(chips.reset)
	eq(#Rows(M, "ledger"), 2)
	eq(Rows(M, "ledger")[2].cells[4].text, "7  " .. ns.FormatCoins(840))
	eq(M.Frame().hero.label.text, "Since reset")
	chips.days.scripts.OnClick(chips.days)
	eq(ns.db.settings.ledgerPerDay, nil); eq(#Rows(M, "ledger"), 3)
end)

it("Ledger: Reset ledger asks twice: \"Click again\" for 3 s, then back; a second click within 3 s resets", function()
	local ns, stub, M = Ledger()
	M.Open("ledger")
	local reset = M.SlotsOf("ledger").footerTools.reset
	eq(reset.label.text, "Reset ledger"); eq(reset.height, 22)
	reset.scripts.OnClick(reset)
	eq(reset.label.text, "Click again"); eq(reset.label.textColor[1], ns.Style.C.danger[1])
	local before = CraftWiseMarketDB.ledger.chars[ns.CharKey()].reset.t
	-- 3 s pass: back to Reset ledger, nothing reset
	stub.clock = NOW + 4
	stub.RunTimers()
	eq(reset.label.text, "Reset ledger")
	eq(CraftWiseMarketDB.ledger.chars[ns.CharKey()].reset.t, before)
	-- a late second click only arms again
	local P = M.Page("ledger").P
	eq(P.ClickReset(NOW + 10), "armed")
	eq(P.ClickReset(NOW + 14), "armed", "4 s later: too late")
	eq(P.ClickReset(NOW + 16), "reset", "within 3 s")
	eq(CraftWiseMarketDB.ledger.chars[ns.CharKey()].reset.t, stub.clock, "since reset starts now")
	eq(ns.db.settings.ledgerView, "reset"); eq(M.Page("ledger").P.Period(), "reset")
	eq(reset.label.text, "Reset ledger")
end)

it("Ledger: empty states; /craftwise ledger and /craftwise auctions open their pages", function()
	local ns, stub, M = Load()
	CraftWiseMarketDB.ledger.chars[ns.CharKey()].days = {}
	M.Open("ledger")
	eq(M.Frame().hero.shown, false)
	eq(M.ListOf("ledger").empty.text, "No day recorded yet for this character.")
	M.Frame():Hide()
	SlashCmdList.CRAFTWISE("ledger today")
	eq(M.Frame():IsShown(), true); eq(M.shown.page, "ledger"); eq(M.Page("ledger").P.Period(), "today")
	eq(M.ListOf("ledger").empty.text, "No purchase or sale recorded in this period.")
	SlashCmdList.CRAFTWISE("auctions")
	eq(M.shown.page, "auctions")
	SlashCmdList.CRAFTWISE("ledger")
	eq(M.shown.page, "ledger"); eq(M.Page("ledger").P.Period(), "today", "plain /craftwise ledger keeps the period")
end)

----------------------------------------------------------------------------------------------------
-- Old homes
----------------------------------------------------------------------------------------------------

it("Sell pages replace their bridges; the profit window has no Bags view, Records no Ledger or Auctions tab", function()
	local ns, _, M = Load()
	for _, key in ipairs({ "bags", "auctions", "ledger" }) do
		eq(M.Page(key).bridge, nil, key)
		eq(M.Page(key).section, "sell")
	end
	local order = {}
	for _, p in ipairs(M.SectionPages("sell")) do order[#order + 1] = p.key end
	eq(table.concat(order, ","), "bags,auctions,ledger")
	eq(ns.PF, nil, "the profit window is gone (#154)")
	eq(ns.RW, nil, "the Records window is gone (#157)"); eq(CraftWiseRecordsFrame, nil)
end)
