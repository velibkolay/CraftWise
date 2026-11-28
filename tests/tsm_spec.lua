-- Optional TSM data through TSM_API (#434): guarded reads, price fallback order, scaling, the toggle.
local calls

local function InstallTSM(values, opts)
	opts = opts or {}
	calls = {}
	TSM_API = {
		ToItemString = function(item)
			if opts.errToItemString then error("boom") end
			return item
		end,
		GetCustomPriceValue = function(src, itemString)
			calls[#calls + 1] = src
			if opts.errValue then error("boom") end
			-- Like TSM: the evaluated string is rounded to a whole number.
			local name, mult = src:match("^(%w+) %* (%d+)$")
			local raw = values[itemString] and values[itemString][name or src]
			if not raw then return nil end
			return math.floor(raw * (tonumber(mult) or 1) + 0.5)
		end,
	}
end

local function Done() TSM_API = nil end

it("no TSM: nothing changes", function()
	local ns = LoadAddon()
	eq(ns.TSM.Loaded(), false); eq(ns.TSM.Enabled(), false)
	eq(ns.TSM.Value(5, "DBMarket"), nil); eq(ns.TSM.Demand(5), nil)
	eq(ns.AuctionQuote(5), nil); eq(#ns.TSMLines(5), 0)
end)

it("TSM erroring is swallowed", function()
	local ns = LoadAddon()
	InstallTSM({ ["i:5"] = { DBMarket = 100 } }, { errValue = true })
	eq(ns.TSM.Price(5), nil); eq(ns.TSM.Demand(5), nil); eq(ns.AuctionQuote(5), nil)
	InstallTSM({ ["i:5"] = { DBMarket = 100 } }, { errToItemString = true })
	eq(ns.TSM.Price(5), nil)
	Done()
end)

it("fallback order: DBRecent, DBMarket, DBMinBuyout", function()
	local ns = LoadAddon()
	InstallTSM({ ["i:1"] = { DBRecent = 300, DBMarket = 200, DBMinBuyout = 100 },
		["i:2"] = { DBMarket = 200, DBMinBuyout = 100 }, ["i:3"] = { DBMinBuyout = 100 }, ["i:4"] = { DBMarket = 0 } })
	local c, s = ns.TSM.Price(1); eq(c, 300); eq(s, "DBRecent")
	c, s = ns.TSM.Price(2); eq(c, 200); eq(s, "DBMarket")
	c, s = ns.TSM.Price(3); eq(c, 100); eq(s, "DBMinBuyout")
	eq(ns.TSM.Price(4), nil)
	local q = ns.AuctionQuote(1)
	eq(q.source, "tsm"); eq(q.copper, 300); eq(q.age, nil); eq(q.t, nil); eq(q.label, "TSM recent value")
	Done()
end)

it("Auctionator and our own scans come before TSM; TSM never enters history", function()
	local ns, stub = LoadAddon({ auctionator = true })
	InstallTSM({ ["i:1"] = { DBRecent = 300 }, ["i:2"] = { DBRecent = 90 } })
	stub.ah[1] = 250
	eq(ns.AuctionQuote(1).source, "auctionator"); eq(ns.AuctionQuote(1).copper, 250)
	stub.ah[1] = nil
	eq(ns.AuctionQuote(1).source, "tsm")
	local v = ns.GetSellValue(1)
	eq(v.source, "auction"); eq(v.age, nil); eq(v.copper, 285) -- 5% cut, "house unknown"
	eq(ns.AuctionQuote(2).source, "tsm"); eq(ns.Market.AuctionatorExport(2), nil)
	Done()
end)

it("the toggle turns every TSM read off", function()
	local ns = LoadAddon()
	InstallTSM({ ["i:1"] = { DBRecent = 300, DBRegionSoldPerDay = 20.6 } })
	eq(ns.TSM.Enabled(), true)
	ns.db.settings.useTSM = false
	eq(ns.TSM.Enabled(), false)
	eq(ns.AuctionQuote(1), nil); eq(ns.TSM.Demand(1), nil); eq(#ns.TSMLines(1), 0)
	eq(#calls, 0)
	Done()
end)

it("demand: already scaled numbers, labelled TSM region", function()
	local ns = LoadAddon()
	InstallTSM({ ["i:1"] = { DBRegionSoldPerDay = 20.6, DBRegionSaleRate = 0.54, DBRegionSaleAvg = 500 },
		["i:2"] = { DBRegionSoldPerDay = 0.6, DBRegionSaleRate = 0.16 } })
	local d = ns.TSM.Demand(1)
	eq(d.perDay, 20.6); eq(d.rate, 0.54); eq(d.avg, 500)
	eq(ns.TSM.DemandText(d), "21 sold a day, 54% sale rate")
	eq(ns.TSM.DemandText(ns.TSM.Demand(2)), "0.6 sold a day, 16% sale rate")
	local lines = ns.TSMLines(1)
	eq(lines[1][1], "TSM region"); eq(lines[2][1], "  TSM sells ~")
	Done()
end)

it("tooltip shows the TSM lines only with TSM data", function()
	local ns = LoadAddon()
	ns.db.tooltip.enabled = true
	InstallTSM({ ["i:7"] = { DBRegionSoldPerDay = 3 } })
	local tip = CreateFrame("GameTooltip")
	tip.lines = {}
	function tip:AddLine(t) table.insert(self.lines, t) end
	function tip:AddDoubleLine(l, r) table.insert(self.lines, l .. " | " .. r) end
	function tip:Show() end
	assert(ns.AddTooltipLines(tip, 7))
	assert(table.concat(tip.lines, "\n"):find("TSM region", 1, true))
	Done()
end)
