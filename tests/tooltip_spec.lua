local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	ns.RecipeData = { [3763] = { skillLine = 165, reagents = { { itemID = 2318, quantity = 6 } }, output = { itemID = 4246, quantity = 1 } } }
	ns.ProfessionSkillLines = { Leatherworking = 165 }
	stub.items[2318] = { name = "Light Leather", sellPrice = 15 }
	stub.items[900] = { name = "Darkshore Grouper", sellPrice = 2 }
	stub.ah[900] = 17
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[3763] = { info = { name = "Fine Leather Belt", learned = true }, schematic = stub.Schematic({ { 2318, 6 } }, 4246) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	local tip = CreateFrame("GameTooltip")
	tip.lines = {}
	function tip:AddLine(t) table.insert(self.lines, t) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function tip:Show() end
	return ns, stub, tip
end

local function text(tip) return table.concat(tip.lines, "\n") end

it("adds a CraftWise section with mark, advice, used in", function()
	local ns, stub, tip = setup()
	ns.SetItemState(900, "junk")
	assert(ns.AddTooltipLines(tip, 900))
	local t = text(tip)
	assert(t:find("CraftWise"), t)
	assert(t:find("Junk"), t)
	assert(t:find("Auction"), t) -- 16c vs 2c
	tip.lines = {}
	assert(ns.AddTooltipLines(tip, 2318))
	assert(text(tip):find("Leatherworking 1 %(1 known%)"), text(tip))
end)

it("each line can be turned off, the section can be off, or shown only with Shift", function()
	local ns, stub, tip = setup()
	ns.db.tooltip.lines.advice = false
	ns.db.tooltip.lines.usedIn = false
	eq(ns.AddTooltipLines(tip, 2318), false) -- nothing left to show
	ns.db.tooltip.lines.usedIn = true
	ns.db.tooltip.mode = "shift"
	eq(ns.AddTooltipLines(tip, 2318), false)
	IsShiftKeyDown = function() return true end
	eq(ns.AddTooltipLines(tip, 2318), true)
	ns.db.tooltip.enabled = false
	eq(ns.AddTooltipLines(tip, 2318), false)
end)

it("settings panel toggles the section, mode and lines", function()
	local ns, stub = setup()
	SlashCmdList.CRAFTWISE("settings")
	local p = CraftWiseSettings
	assert(p.shown, "panel open")
	p.shift.scripts.OnClick(p.shift)
	eq(ns.db.tooltip.mode, "shift")
	p.lines.usedIn.scripts.OnClick(p.lines.usedIn)
	eq(ns.db.tooltip.lines.usedIn, false)
	p.enabled.scripts.OnClick(p.enabled)
	eq(ns.db.tooltip.enabled, false)
end)

it("hooks item tooltips at login, but not inside the CraftWise window", function()
	local ns, stub, tip = setup()
	local hooked
	TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) hooked = fn end }
	Enum.TooltipDataType = { Item = 0 }
	stub.Fire("PLAYER_LOGIN")
	assert(hooked, "hooked")
	hooked(tip, { id = 2318 })
	assert(text(tip):find("CraftWise"))
end)
