-- Main window: a page for every sub-page that has not moved into the window yet (#153, spec "Where
-- everything lands"). Each says so and opens the feature where it lives today (profit window, Records
-- window, farm window, settings panel), so nothing loses its UI home in between. A real page registered
-- later with the same key (UI/Main/Pages/<Page>.lua, #154-#157) replaces its bridge; when the last one is
-- replaced this file goes.
local _, ns = ...
local M = ns.Main
local L = ns.L

-- The old profit window on one of its views.
local function ProfitView(view)
	return function()
		ns.db.settings.view = view
		local PF = ns.PF
		if PF and PF.frame and PF.frame:IsShown() then
			PF.Refresh()
		elseif ns.ToggleProfitFrame then
			ns.ToggleProfitFrame()
		end
	end
end

-- The Records window on one of its tabs (RW.Ledger, RW.Auctions, ...).
local function RecordsTab(name)
	return function()
		local tab = ns.RW and ns.RW[name]
		if tab and ns.ShowRecords then
			ns.ShowRecords(tab.key)
		end
	end
end

local PROFIT, RECORDS = L["profit window"], L["Records window"]

local function Open(where)
	return (L["Open in the %s"]):format(where)
end

-- key, section, label, order, buttons = { { label, onClick(panel, button) } }
local BRIDGES = {
	{ "craft", "make", L["Craft"], 1, { { Open(PROFIT), ProfitView("profit") } } },
	{ "learn", "make", L["Learn"], 2, { { Open(PROFIT), ProfitView("learn") } } },
	{ "level", "make", L["Level up"], 3, { { Open(PROFIT), ProfitView("level") } } },
	{ "bags", "sell", L["Bags"], 1, { { Open(PROFIT), ProfitView("bags") } } },
	{ "auctions", "sell", L["Auctions"], 2, { { Open(RECORDS), RecordsTab("Auctions") } } },
	{ "ledger", "sell", L["Ledger"], 3, { { Open(RECORDS), RecordsTab("Ledger") } } },
	{ "farm", "gather", L["Farm"], 1, {
		{ L["History in the farm window"], function()
			if ns.FarmHistory and ns.FarmHistory.Open then
				ns.FarmHistory.Open()
			end
		end },
		{ L["Farm tracker"], function()
			if CraftWise_FarmToggle then
				CraftWise_FarmToggle()
			end
		end },
	} },
	{ "fishing", "gather", L["Fishing"], 2, {
		{ L["Spots in the profit window"], ProfitView("fishing") },
		{ L["Log in the Records window"], RecordsTab("FishingLog") },
	} },
	{ "crates", "gather", L["Crates"], 3, { { Open(RECORDS), RecordsTab("Crates") } } },
	{ "items", "lookup", L["Items"], 1, {
		{ L["Market in the Records window"], RecordsTab("Market") },
		{ L["Where to buy in the Records window"], RecordsTab("Where") },
	} },
	{ "upgrades", "lookup", L["Upgrades"], 2, { { Open(PROFIT), ProfitView("upgrades") } } },
	{ "music", "music", L["Music"], 1, { { Open(PROFIT), ProfitView("music") } } },
	{ M.SETTINGS, nil, L["Settings"], 1, {
		{ L["Settings panel"], function(_, button)
			if ns.ToggleSettings then
				ns.ToggleSettings(button)
			end
		end },
		{ L["AH rule"], function(_, button)
			if ns.ToggleAHRule then
				ns.ToggleAHRule(button)
			end
		end },
		{ L["Snapshot in the Records window"], RecordsTab("Snapshot") },
	} },
}

M.BRIDGES = BRIDGES

for _, b in ipairs(BRIDGES) do
	local key, section, label, order, buttons = b[1], b[2], b[3], b[4], b[5]
	M.RegisterPage({
		key = key, section = section, label = label, order = order, bridge = true, kind = "custom",
		Build = function(body)
			body.panel = M.Panel(body)
			body.panel:SetAllPoints(body)
		end,
		Refresh = function(body)
			local list = {}
			for i, def in ipairs(buttons) do
				list[i] = { label = def[1], onClick = def[2] }
			end
			body.panel:Set({
				title = (L["%s has not moved here yet."]):format(label),
				body = L["Until it does, the button opens it where it lives today."],
				buttons = list,
			})
		end,
	})
end
