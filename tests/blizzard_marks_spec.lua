-- Marks and lines on the client's frames (#160): tooltip section, skill-up chance figure, Sell junk
-- button, bag slot corners. Invented data only.
local DANGER = "|cffFF7A63"

local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[100] = { name = "Linen Cloth", sellPrice = 13 }
	stub.items[400] = { name = "Old Boots", sellPrice = 70 }
	stub.items[900] = { name = "Darkshore Grouper", sellPrice = 2 }
	stub.ah[900] = 17
	stub.ah[100] = 50
	stub.bags[0] = {
		{ itemID = 100, stackCount = 20, quality = 1 },
		{ itemID = 400, stackCount = 1, quality = 1 },
		{ itemID = 400, stackCount = 1, quality = 1 },
	}
	C_Container.UseContainerItem = function(bag, slot) stub.bags[bag][slot] = false end
	MerchantFrame = CreateFrame("Frame", "MerchantFrame")
	return ns, stub
end

local function tip()
	local t = CreateFrame("GameTooltip")
	t.lines, t.pairs = {}, {}
	function t:AddLine(text) table.insert(self.lines, text) end
	function t:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
		table.insert(self.pairs, { l, r, lr, lg, lb, rr, rg, rb })
	end
	function t:Show() end
	return t
end

local function pair(t, label)
	for _, p in ipairs(t.pairs) do
		if p[1]:find(label, 1, true) then return p end
	end
end

it("tooltip section: W key header in keyGold, labels grey 0.75, values white", function()
	local ns = setup()
	local t = tip()
	assert(ns.AddTooltipLines(t, 900))
	eq(t.lines[1], " ")
	eq(t.lines[2], "|T" .. ns.Style.Media.keyW .. ":12|t |cffE8B94BCraftWise|r")
	local sell = pair(t, "Sell")
	assert(sell, "sell line")
	eq(sell[3], 0.75); eq(sell[6], 1)
end)

it("tooltip sell line: the better way is white, the other grey; 'Sell ×N' for stacks", function()
	local ns, stub = setup()
	local t = tip()
	ns.AddTooltipLines(t, 900) -- AH 16c net vs vendor 2c: auction wins
	local p = pair(t, "Sell")
	assert(p[2]:find("|cffffffffAH ", 1, true), p[2])
	assert(p[2]:find("|cffA7AAA6Vendor ", 1, true), p[2])
	stub.items[900].sellPrice = 40 -- vendor 40c beats AH 16c
	t = tip()
	ns.AddTooltipLines(t, 900)
	p = pair(t, "Sell")
	assert(p[2]:find("|cffA7AAA6AH ", 1, true), p[2])
	assert(p[2]:find("|cffffffffVendor ", 1, true), p[2])
	C_Item.GetItemCount = function() return 20 end
	t = tip()
	ns.AddTooltipLines(t, 100) -- 20 in the bag
	assert(pair(t, "Sell ×20"), "stack count")
end)

it("tooltip AH price age: grey up to 24 h, C.danger over it", function()
	local ns, stub = setup()
	stub.ahAge[900] = 0
	local t = tip()
	ns.AddTooltipLines(t, 900)
	local p = pair(t, "AH price")
	assert(p[2]:find("today", 1, true) and not p[2]:find(DANGER, 1, true), p[2])
	stub.ahAge[900] = 3
	t = tip()
	ns.AddTooltipLines(t, 900)
	p = pair(t, "AH price")
	assert(p[2]:find(DANGER .. "3d old|r", 1, true), p[2])
	-- a market scan time is exact
	local text, stale = ns.SaleAgeText({ quote = { t = time() - 3 * 3600 } })
	eq(text, "3h old"); eq(stale, false)
	text, stale = ns.SaleAgeText({ quote = { t = time() - 86400 - 60 } })
	eq(stale, true)
	text, stale = ns.SaleAgeText({ quote = { t = time() - 86400 } })
	eq(stale, false) -- exactly 24 h is not over it
end)

it("tooltip: 'Only with Shift' hides the whole section including the header", function()
	local ns = setup()
	ns.db.tooltip.mode = "shift"
	local t = tip()
	eq(ns.AddTooltipLines(t, 900), false)
	eq(#t.lines, 0); eq(#t.pairs, 0)
end)

local function chanceRow()
	local ns, stub = setup()
	ns.RecipeData = nil
	return ns, stub
end

it("skill-up chance: measured white, formula grey with ~, in the figure font", function()
	local ns, stub = chanceRow()
	local text = ns.RecipeChanceText
	-- Leveling.Chance is exercised in leveling_spec; here the colours and the font
	local real = ns.Leveling.Chance
	ns.Leveling.Chance = function() return 0.58, { kind = "recipe" } end
	eq(text(1, 1, 100), "|cffECEDEA58%|r")
	ns.Leveling.Chance = function() return 0.41, { kind = "formula" } end
	eq(text(1, 1, 100), "|cffA7AAA6~41%|r")
	ns.Leveling.Chance = function() return 0, { kind = "formula" } end
	eq(text(1, 1, 100), nil)
	ns.Leveling.Chance = real
	local src = io.open("CraftWise/UI/RecipeChance.lua"):read("*a")
	assert(not src:find("4fd18c", 1, true) and not src:find("ffb347", 1, true), "old green/orange")
end)

it("skill-up chance label: CraftWiseFontFigure, right edge 4 units in", function()
	local ns, stub = chanceRow()
	local scroll, cb = {}, nil
	ScrollUtil = { AddInitializedFrameCallback = function(_, fn, owner) cb = { fn = fn, owner = owner } end }
	ProfessionsFrame = { CraftingPage = { RecipeList = { ScrollBox = scroll } } }
	ns.Leveling.Chance = function() return 0.5, { kind = "recipe" } end
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 165, skillLevel = 100 } end
	stub.Fire("TRADE_SKILL_SHOW")
	local b = CreateFrame("Button")
	b.Label = false
	local node = { GetData = function() return { recipeInfo = { recipeID = 1, learned = true, relativeDifficulty = 1 } } end }
	cb.fn(cb.owner, b, node)
	local label = ns.RecipeChanceLabels[b]
	eq(label.fontObject, ns.Style.Fonts.Figure)
	eq(label.fontObject, CraftWiseFontFigure)
	local pt = label.points[1]
	eq(pt[1], "RIGHT"); eq(pt[3], "RIGHT"); eq(pt[4], -4)
end)

local function merchant(ns, stub)
	stub.Fire("MERCHANT_SHOW")
	return ns.Junk.button
end

it("Sell junk: folded action button, 28 tall, 'Sell junk · amount', hidden when nothing is junk", function()
	local ns, stub = setup()
	local b = merchant(ns, stub)
	eq(b.shown, false) -- nothing marked
	ns.SetItemState(400, "junk")
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(b.shown, true)
	eq(b.label.text, "Sell junk · 1s 40c")
	eq(b.height, 28)
	eq(b.sheet.fill.hex, ns.Style.C.action.hex)
	eq(b.sheet.cut, 10)
	eq(b.disabled, false)
	ns.SetItemState(400, "normal")
	stub.Fire("BAG_UPDATE_DELAYED")
	eq(b.shown, false)
end)

it("Sell junk: amount shows at most two units", function()
	local ns = setup()
	eq(ns.Junk.ShortMoney(1234567), "123g 45s")
	eq(ns.Junk.ShortMoney(35 * 100), "35s")
	eq(ns.Junk.ShortMoney(7), "7c")
end)

it("Sell junk: progress with an orange diamond while selling", function()
	local ns, stub = setup()
	ns.SetItemState(400, "junk")
	local b = merchant(ns, stub)
	eq(b.nokta.shown, false)
	assert(ns.Junk.Sell())
	eq(b.nokta.shown, true)
	eq(b.nokta.vertexColor[1], ns.Style.C.live[1])
	eq(b.progress.text, "Selling 1 of 2")
	eq(b.disabled, true)
	b.scripts.OnUpdate(b, 0.3)
	eq(b.progress.text, "Selling 2 of 2")
	for _ = 1, 4 do
		if not ns.Junk.Running() then break end
		b.scripts.OnUpdate(b, 0.3)
	end
	eq(ns.Junk.Running(), false)
	eq(b.nokta.shown, false); eq(b.progress.shown, false)
end)

it("Sell junk: disabled in combat with a tooltip saying why, and Sell refuses", function()
	local ns, stub = setup()
	ns.SetItemState(400, "junk")
	local b = merchant(ns, stub)
	stub.Fire("PLAYER_REGEN_DISABLED")
	eq(b.disabled, true); eq(b.alpha, 0.5)
	eq(ns.Junk.Sell(), false)
	local shown
	local show = ns.Style.ShowTip
	ns.Style.ShowTip = function(owner, title, ...) shown = { owner = owner, title = title, lines = { ... } } end
	b.scripts.OnEnter(b)
	ns.Style.ShowTip = show
	eq(shown.owner, b); eq(shown.title, "Sell junk")
	eq(shown.lines[2], "Unavailable in combat. It works again when combat ends.")
	b.scripts.OnLeave(b)
	stub.Fire("PLAYER_REGEN_ENABLED")
	eq(b.disabled, false); eq(b.alpha, 1)
	assert(ns.Junk.Sell())
end)

it("Sell junk: combat stops a running sale, the rest stays marked", function()
	local ns, stub = setup()
	ns.SetItemState(400, "junk")
	local b = merchant(ns, stub)
	assert(ns.Junk.Sell())
	stub.Fire("PLAYER_REGEN_DISABLED")
	eq(ns.Junk.Running(), false)
	eq(ns.db.junk[400], true)
	eq(b.disabled, true)
end)

it("bag slot corners: 13 units top right, gold for Sell on AH, grey for junk (icon dimmed to 55 %)", function()
	local ns, stub = setup()
	local btn = CreateFrame("Button")
	btn.icon = CreateFrame("Frame")
	ns.SetItemState(100, "auction")
	ns.ApplySlotMark(btn, 100)
	local c = ns.SlotCorners[btn]
	eq(c.width, 13); eq(c.height, 13)
	eq(c.points[1][1], "TOPRIGHT"); eq(c.points[1][3], "TOPRIGHT")
	eq(c.vertexColor[1], ns.Style.C.coinGold[1]); eq(c.vertexColor[3], ns.Style.C.coinGold[3])
	eq(btn.icon.desaturated, nil)
	ns.SetItemState(400, "junk")
	ns.ApplySlotMark(btn, 400)
	eq(c.vertexColor[1], ns.Style.C.text3[1]); eq(c.vertexColor[3], ns.Style.C.text3[3])
	eq(btn.icon.desaturated, true); eq(btn.icon.alpha, 0.55)
	ns.ApplySlotMark(btn, 100) -- back to AH: no longer dimmed
	eq(btn.icon.desaturated, false); eq(btn.icon.alpha, 1)
	ns.ToggleKeep(100)
	ns.ApplySlotMark(btn, 100) -- keep has no mark
	eq(c.shown, false)
	ns.ApplySlotMark(btn, 999) -- unmarked
	eq(c.shown, false)
end)
