local function setup()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.items[2318] = { name = "Light Leather" }
	stub.items[5001] = { name = "Murloc Scale Belt", sellPrice = 30 }
	stub.items[5002] = { name = "Fine Leather Belt", sellPrice = 10 }
	stub.items[5003] = { name = "Bound Thing", sellPrice = 5, bindType = 1 }
	stub.items[5004] = { name = "Old Gloves", sellPrice = 5 }
	stub.ah[5001] = 100
	stub.ah[5003] = 1000 -- soulbound: can't be sold on the AH
	local function r(name, n, out, d)
		return { info = { name = name, learned = true, relativeDifficulty = d }, schematic = stub.Schematic({ { 2318, n } }, out) }
	end
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[6702] = r("Murloc Scale Belt", 2, 5001, 1), -- yellow 95 / grey 125: 1st quarter at 100
		[3763] = r("Fine Leather Belt", 4, 5002, 2), -- yellow 85 / grey 115: 3rd quarter at 100
		[3756] = r("Old Gloves", 1, 5004, 3), -- grey 100: hidden
		[99999] = r("Bound Thing", 1, 5003, 0), -- no thresholds, client says orange
	} }
	ns.Thresholds = { [6702] = { 95, 125 }, [3763] = { 85, 115 }, [3756] = { 70, 100 }, [3759] = { 80, 110 } }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.Fire("SKILL_LINES_CHANGED")
	ns.db.vendor[2318] = 10
	ns.db.skillups = {
		[6702] = { [96] = { n = 4, ups = 4, d = 1 }, [97] = { n = 2, ups = 1, d = 1 } },
		[3759] = { [95] = { n = 6, ups = 3, d = 2 } }, -- yellow 80 / grey 110: 3rd quarter at 95
	}
	return ns, stub
end

local function byID(rows)
	local t = {}
	for _, r in ipairs(rows) do t[r.recipeID] = r end
	return t
end

it("places a skill between the yellow and grey threshold in quarters", function()
	local ns = setup()
	local S = ns.Leveling.Stage
	eq(S(95, 95, 125), 1); eq(S(100, 95, 125), 1); eq(S(105, 95, 125), 2); eq(S(110, 95, 125), 3)
	eq(S(100, 85, 115), 3); eq(S(114, 85, 115), 4)
	eq(S(94, 95, 125), nil); eq(S(125, 95, 125), nil)
end)

it("estimates the chance: orange always, grey never, else own crafts, then all crafts at the same stage", function()
	local ns = setup()
	local p, info = ns.Leveling.Chance(6702, 1, 100)
	eq(info.kind, "recipe"); eq(info.n, 6); eq(p, 5 / 6)
	p, info = ns.Leveling.Chance(3763, 2, 100)
	eq(info.kind, "stage"); eq(info.n, 6); eq(p, 0.5)
	p, info = ns.Leveling.Chance(3763, 2, 84)
	eq(info.kind, "orange"); eq(p, 1)
	p, info = ns.Leveling.Chance(3756, 3, 100)
	eq(info.kind, "grey"); eq(p, 0)
	p, info = ns.Leveling.Chance(99999, 0, 100)
	eq(info.kind, "orange"); eq(p, 1)
	p, info = ns.Leveling.Chance(3763, 2, 110) -- 4th quarter: nothing recorded there
	eq(p, nil); eq(info.kind, "nodata")
	p, info = ns.Leveling.Chance(99998, 1, 100) -- no thresholds, 6 yellow crafts recorded
	eq(info.kind, "color"); eq(p, 5 / 6)
	p, info = ns.Leveling.Chance(99998, 2, 100) -- 6 green crafts: 3 points
	eq(info.kind, "color"); eq(p, 0.5)
end)

it("ranks known recipes by money per skill-up: (reagents - sale) / chance", function()
	local ns = setup()
	local rows, skill = ns.LevelingRows(165)
	eq(skill, 100)
	local t = byID(rows)
	eq(t[3756], nil) -- grey: no points
	-- Murloc: 2 leather = 20c; AH 100 - 5% = 95 (beats vendor 30 by the AH rule); net -75; 5/6 chance
	eq(t[6702].cost, 20); eq(t[6702].saleValue, 95); eq(t[6702].saleSource, "auction")
	eq(t[6702].net, -75); eq(t[6702].perPoint, -90)
	-- Fine Leather Belt: 40c, vendor 10, net 30, 50% -> 60 per point, 2 crafts per point
	eq(t[3763].saleSource, "vendor"); eq(t[3763].perPoint, 60); eq(t[3763].craftsPerPoint, 2)
	-- soulbound output: AH ignored, vendor 5; orange
	eq(t[99999].saleSource, "vendor"); eq(t[99999].perPoint, 5)
end)

it("shows the Level view sorted best first, with the maths in the tooltip", function()
	local ns, stub = setup()
	ns.db.settings.view = "level"
	ns.ToggleProfitFrame()
	local shown = {}
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.recipeID then
			shown[#shown + 1] = f
		end
	end
	local names = {}
	for _, f in ipairs(shown) do
		names[#names + 1] = f.data.name
		f.scripts.OnEnter(f)
		f.scripts.OnLeave(f)
	end
	eq(table.concat(names, ","), "Murloc Scale Belt,Bound Thing,Fine Leather Belt")
	-- sort by every column without errors
	for _, f in ipairs(stub.frames) do
		if f.scripts.OnClick and not f.data and not f.scripts.OnDragStart and f.label then f.scripts.OnClick(f) end
	end
	ns.db.settings.levelSortKey, ns.db.settings.levelSortDesc = nil, nil
	ns.RefreshProfitFrame()
end)
