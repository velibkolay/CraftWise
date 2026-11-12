-- Records window (#137): what CraftWise recorded, in tabs (Snapshot; Ledger and Auctions moved to the main
-- window's Sell section, #155, Crates and Fishing log to Gather, #156, Market and Where to buy to Look up ›
-- Items, #157). Everything that was
-- only printed to chat by a slash command gets a view here; the slash commands stay as another way in.
-- The window is split like the profit window: State (constants, tab registry, helpers), one file per tab
-- (its columns, controls and Model), Frame (widgets, refresh, opening). The files share internals through
-- ns.RW and load in the order CraftWise.toc lists them: a file only uses what the files before it export.
--
-- A tab is { key, label, columns = list | function(st), search = hint text | nil, buttons = function(st) ->
-- { { key, label, width, selected, onClick, tip } }, Model = function(st) -> model, onOpen = function(st) }.
-- A model is { summary = text, rows = { row }, empty = text }; a row is { itemID, icon, name, sub,
-- cells = { [column key] = text }, tip = { line | { left, right } }, onClick = function(row, mouse) }.
-- Models are plain data so the specs can check them without widgets.
local _, ns = ...
local Style, L = ns.Style, ns.L
local C = Style.colors

local RW = {
	WIDTH = 860,
	HEIGHT = 560,
	PAD = 16,
	ROW_HEIGHT = 30,
	HEADER_Y = -150, -- top of the column header row
}
RW.LIST_TOP = RW.HEADER_Y - 22
RW.VISIBLE_ROWS = math.floor((RW.HEIGHT + RW.LIST_TOP - 40) / RW.ROW_HEIGHT)
RW.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

RW.tabs, RW.byKey = {}, {}
-- Per tab: offset (scroll), query (search text); plus what a tab keeps (fishing water, ...).
RW.state = { tab = nil, offsets = {}, queries = {} }

function RW.Register(tab)
	RW.tabs[#RW.tabs + 1] = tab
	RW.byKey[tab.key] = tab
end

-- The tab shown: the one last opened (CraftWiseDB.settings.recordsTab), else the first.
function RW.CurrentTab()
	local key = RW.state.tab or (ns.db and ns.db.settings.recordsTab)
	return RW.byKey[key] and key or (RW.tabs[1] and RW.tabs[1].key)
end

function RW.SetTab(key)
	if not RW.byKey[key] then
		return
	end
	RW.state.tab = key
	if ns.db then
		ns.db.settings.recordsTab = key
	end
end

function RW.Query(key)
	return RW.state.queries[key or RW.CurrentTab()] or ""
end

function RW.SetQuery(key, text)
	RW.state.queries[key] = text or ""
	RW.state.offsets[key] = 0
end

function RW.Columns(tab)
	if type(tab.columns) == "function" then
		return tab.columns(RW.state)
	end
	return tab.columns
end

----------------------------------------------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------------------------------------------

function RW.Muted(text)
	return C.muted .. text .. "|r"
end

-- Money, "-" when unknown.
function RW.Money(copper)
	if copper == nil then
		return RW.Muted("-")
	end
	return ns.FormatMoney(copper)
end

-- Money with a sign, for changes.
function RW.Signed(copper)
	if copper == nil then
		return RW.Muted("?")
	end
	if copper > 0 then
		return C.good .. "+|r" .. ns.FormatMoney(copper)
	elseif copper < 0 then
		return C.bad .. "-|r" .. ns.FormatMoney(-copper)
	end
	return ns.FormatMoney(0)
end

-- "3h", "2d" (ns.Market.FormatAge); nil without a time.
function RW.Ago(t, now)
	if not t then
		return nil
	end
	local seconds = (now or time()) - t
	if ns.Market and ns.Market.FormatAge then
		local ok, text = pcall(ns.Market.FormatAge, math.max(0, seconds))
		if ok then
			return text
		end
	end
	return ("%dm"):format(math.floor(math.max(0, seconds) / 60))
end

-- Item name in its quality colour (from a link without brackets), else the plain name, else "item <id>".
-- stored = { name, link } the caller kept (a ledger entry, an auction).
function RW.ItemText(itemID, stored)
	stored = stored or {}
	local name, link = nil, nil
	if itemID and ns.ItemInfoNow then
		name, link = ns.ItemInfoNow(itemID)
	end
	link = link or stored.link
	if type(link) == "string" and link:find("|h[", 1, true) then
		return (link:gsub("|h%[(.-)%]|h", "|h%1|h"))
	end
	return name or stored.name or (itemID and ("item " .. tostring(itemID))) or "?"
end

function RW.ItemIcon(itemID)
	local icon = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
	return icon or RW.QUESTION_ICON
end

-- Items the client hasn't loaded: ask once per item, refresh the window when they arrive.
local requested = {}
function RW.LoadNames(ids)
	local missing = {}
	for _, id in ipairs(ids) do
		if id and not requested[id] then
			requested[id] = true
			if not (ns.ItemInfoNow and ns.ItemInfoNow(id)) then
				missing[#missing + 1] = id
			end
		end
	end
	if #missing > 0 and ns.WithItemNames then
		ns.WithItemNames(missing, function()
			if RW.Refresh then
				RW.Refresh()
			end
		end)
	end
end

ns.RW = RW
