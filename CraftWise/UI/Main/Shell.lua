-- Main window shell (#153; spec in #150: "Main window shell", "States", "Where everything lands"):
-- sections, the page registry, what the window remembers, the layout seam and the state rules. No frames
-- here; UI/Main/States.lua, List.lua and Frame.lua draw. The files share their internals through ns.Main
-- (like ns.PF) and load in the order CraftWise.toc lists them: a file only uses what the files before it
-- export. Pages live in UI/Main/Pages/<Page>.lua, one file per page.
--
-- A page is registered with M.RegisterPage{
--   key, section ("make" | "sell" | "gather" | "lookup" | "music"; nil for the settings page), label,
--   order (within its section), title (heading in the states; default label),
--   kind = "list" (hero card + list, the default) | "custom" (the page draws its own body),
--   profession = true   uses the shared profession choice; the First run state applies
--   prices = true       uses AH prices: the header shows the AH status; No prices and Stale apply
--   pricesOptional = true   with prices: the AH status shows, but No prices doesn't replace the page
--                           (pages that also work without the AH, e.g. Look up › Items)
--   events = { "BAGS_CHANGED", ... }   ns.Notify names that refresh the page while it shows
--   Model(ctx) -> model           list pages: { rows, hero, empty, footer, footerRight, listTitle,
--                                  listNote }; rows are plain tables (itemID, icon, name, cells = {}, key)
--   columns = list | function(ctx) -> list of { key, label, width (nil = takes what is left), align,
--                                  sort (true = the header sorts by row[key]), text(row) -> text, color }
--   rowHeight, InitRow(row, data, ctx), SortRows(rows, key, desc),
--   Open(content, data, ctx) + OpenHeight(data, ctx)   rows that open in place
--   Hero(card, hero, ctx, slot)   draws into the hero card's middle (rails); label, name (nameColor),
--                                  sub, figure (figureColor), figureLabel (above it) and figureUnit (after
--                                  it) are filled by the shell from model.hero. slot = the page's own
--                                  frame over the middle (hidden while other pages show). hero.full = true:
--                                  the middle is the whole card inside its padding; hero.bare = true:
--                                  no card, the slot is the whole hero area (the page draws its cards).
--                                  Also on model.hero: labelColor, nameFont (a Style.Fonts key), flap (the
--                                  dog-ear colour); the shell resets them on every draw
--   noHeader = true               no header row (group rows carry the rule, board "Bags")
--   OnClick(row, ctx)             a left click on a row of a page without Open
--   rail columns: a column with rail = function(row, ctx) -> { value, max, selected, zeroAt, low, high,
--                                  point } draws a rail in its cell (List.lua); point = a tick with its
--                                  range (low .. high) as a thin line instead of a bar
--   RowTooltip(owner, row, ctx)   hover tooltip of a row instead of the item's GameTooltip (the row is
--                                  marked cwOwnTooltip, so Tooltip.lua adds no second CraftWise section)
--   Tools(slot, ctx), ListTools(slot, ctx), FooterTools(slot, ctx)   build once; Update*(slot, ctx)
--   Build(body, ctx), Refresh(body, ctx)   custom pages
--   Docked layout (#161, Docked.lua; ctx.metrics.docked, M.IsDocked(ctx)): list rows draw in two lines
--   from DockedRow(row, ctx) -> view (List.lua, M.DockedView: name, rail, note, result, sub, group,
--   line, tag, ...; without it from row.view or the columns), DockedInitRow(b, row, ctx, view) adds what
--   the view can't say; DockedHero(card, hero, ctx, slot) draws the stacked hero's middle (else Hero
--   does, reading ctx.metrics); hero.middle = its height there. The page tools move into the list
--   header (dockedListToolsWidth: room the list tools take right of the title, default 190). Custom
--   pages draw both layouts in Refresh.
-- }
-- A page model that raises shows the Error state; the other pages keep working.
local _, ns = ...
local L = ns.L

local M = {}
ns.Main = M

M.SETTINGS = "settings" -- the gear's page; not a section tab
M.SECTIONS = {
	{ key = "make", label = L["Make"] },
	{ key = "sell", label = L["Sell"] },
	{ key = "gather", label = L["Gather"] },
	{ key = "lookup", label = L["Look up"] },
	{ key = "music", label = L["Music"] },
}
M.sectionByKey = {}
for _, s in ipairs(M.SECTIONS) do
	M.sectionByKey[s.key] = s
end

M.STALE_SECONDS = 24 * 3600 -- spec "Stale": newest scan at the profit house older than 24 h

----------------------------------------------------------------------------------------------------
-- What the window remembers: db.settings.ui (section, sub-page per section, profession, layout).
-- Fresh install opens as Window (Veli, 12 Nov).
----------------------------------------------------------------------------------------------------

M.UI_DEFAULTS = {
	section = "make", -- a section key or M.SETTINGS
	pages = {}, -- [section] = the sub-page last shown there
	profession = nil, -- professionID chosen on the Make pages, or "all" (Make > Craft lists every profession, #211)
	sort = {}, -- [page key] = { key, desc }: the list sort last chosen (#197)
	layout = "window", -- "window", "dockLeft" or "dockRight" (Docked.lua, #161)
	escape = true, -- Close with Escape (Settings > Look)
	locked = false, -- Lock position (Settings > Look)
	scale = 1, -- Scale (Settings > Look)
	size = {}, -- [layout key] = { width, height }: the size dragged to (#280; docked layouts keep the width only)
	-- pos = { point, relativePoint, x, y } once the window was moved
}

function M.UI()
	local settings = ns.db.settings
	settings.ui = type(settings.ui) == "table" and settings.ui or {}
	local ui = settings.ui
	for k, v in pairs(M.UI_DEFAULTS) do
		if ui[k] == nil then
			ui[k] = type(v) == "table" and {} or v
		end
	end
	return ui
end

----------------------------------------------------------------------------------------------------
-- Page registry
----------------------------------------------------------------------------------------------------

M.pages = {}
M.listeners = {} -- ns.Notify names the shell listens to for pages

function M.RegisterPage(def)
	assert(type(def) == "table" and type(def.key) == "string", "CraftWise Main: a page needs a key")
	if def.key == M.SETTINGS then
		def.section = nil
	else
		assert(M.sectionByKey[def.section], "CraftWise Main: unknown section " .. tostring(def.section))
	end
	local old = M.pages[def.key]
	if old and not old.bridge then
		error("CraftWise Main: page registered twice: " .. def.key, 2)
	end
	def.label = def.label or def.key
	def.title = def.title or def.label
	def.order = def.order or (old and old.order) or 100
	def.kind = def.kind or "list"
	M.pages[def.key] = def
	for _, name in ipairs(def.events or {}) do
		if not M.listeners[name] then
			M.listeners[name] = true
			ns.Listen(name, function()
				local page = M.CurrentPage()
				for _, n in ipairs(page and page.events or {}) do
					if n == name then
						M.Refresh()
						return
					end
				end
			end)
		end
	end
	if M.Refresh then
		M.Refresh()
	end
	return def
end

function M.Page(key)
	return M.pages[key]
end

-- The pages of a section in their order.
function M.SectionPages(section)
	local list = {}
	for _, page in pairs(M.pages) do
		if page.section == section then
			list[#list + 1] = page
		end
	end
	table.sort(list, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.key < b.key
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- Navigation
----------------------------------------------------------------------------------------------------

-- The section shown (a section key or M.SETTINGS) and its page.
function M.CurrentSection()
	local ui = M.UI()
	if ui.section == M.SETTINGS and M.pages[M.SETTINGS] then
		return M.SETTINGS
	end
	return M.sectionByKey[ui.section] and ui.section or M.SECTIONS[1].key
end

function M.CurrentPage()
	local section = M.CurrentSection()
	if section == M.SETTINGS then
		return M.pages[M.SETTINGS]
	end
	local list = M.SectionPages(section)
	local key = M.UI().pages[section]
	for _, page in ipairs(list) do
		if page.key == key then
			return page
		end
	end
	return list[1]
end

-- Shows a section on its last sub-page.
function M.SelectSection(section)
	local ui = M.UI()
	if section ~= M.SETTINGS and not M.sectionByKey[section] then
		return false
	end
	if section ~= M.SETTINGS then
		ui.lastSection = section
	end
	ui.section = section
	M.Refresh()
	return true
end

-- Shows a page (and its section).
function M.ShowPage(key)
	local page = M.pages[key]
	if not page then
		return false
	end
	local ui = M.UI()
	if page.section then
		ui.pages[page.section] = key
		ui.lastSection = page.section
		ui.section = page.section
	else
		ui.section = M.SETTINGS
	end
	M.Refresh()
	return true
end

-- The gear: the settings page, and back to the section it was opened from.
function M.ToggleSettings()
	local ui = M.UI()
	if M.CurrentSection() == M.SETTINGS then
		return M.SelectSection(ui.lastSection or M.SECTIONS[1].key)
	end
	return M.SelectSection(M.SETTINGS)
end

----------------------------------------------------------------------------------------------------
-- Profession (Make pages share it)
----------------------------------------------------------------------------------------------------

-- Crafting professions the character has (with or without recipes cached), by name.
function M.ProfessionIDs()
	local ids = {}
	for id, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.name and not (ns.IsGathering and ns.IsGathering(id)) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids, function(a, b)
		local pa, pb = ns.charDB.professions[a], ns.charDB.professions[b]
		return (pa.name or "") < (pb.name or "")
	end)
	return ids
end

-- The chosen profession: the one remembered, else the first with recipes, else the first. id, entry.
function M.Profession()
	local ids = M.ProfessionIDs()
	local profs = ns.charDB and ns.charDB.professions or {}
	local chosen = M.UI().profession
	if chosen and profs[chosen] then
		for _, id in ipairs(ids) do
			if id == chosen then
				return id, profs[id]
			end
		end
	end
	for _, id in ipairs(ids) do
		if next(profs[id].recipes or {}) then
			return id, profs[id]
		end
	end
	if ids[1] then
		return ids[1], profs[ids[1]]
	end
	return nil
end

-- Does this page show every profession at once (#211)? Only pages with allowAll, when "all" was chosen.
function M.ShowsAll(page)
	return page ~= nil and page.allowAll == true and M.UI().profession == "all"
end

function M.SetProfession(id)
	M.UI().profession = id
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Layout seam. "window" is registered by Frame.lua; the docked layouts (#161) register theirs with
-- docked = true. A layout is { label, docked, metrics = { ... }, Apply(frame, metrics) }. The saved layout
-- stays as it is when it is not registered (yet): the window layout is used meanwhile.
----------------------------------------------------------------------------------------------------

M.layouts, M.layoutOrder = {}, {}

function M.RegisterLayout(key, def)
	def.key = key
	if not M.layouts[key] then
		M.layoutOrder[#M.layoutOrder + 1] = key
	end
	M.layouts[key] = def
	if def.docked then
		-- The minimap button's Shift-click (UI/MinimapButton.lua) calls this name once it exists.
		ns.ToggleDock = M.ToggleDock
	end
	return def
end

function M.LayoutKey()
	local key = M.UI().layout
	if M.layouts[key] then
		return key
	end
	return "window"
end

function M.Layout()
	return M.layouts[M.LayoutKey()]
end

-- Switches the layout in place (no reload). Returns false for a layout nobody registered.
function M.SetLayout(key)
	if not M.layouts[key] then
		return false
	end
	local ui = M.UI()
	if M.layouts[key].docked then
		ui.lastDocked = key
	end
	ui.layout = key
	if M.ApplyLayout then
		M.ApplyLayout()
	end
	ns.Notify("MAIN_LAYOUT_CHANGED", key)
	return true
end

----------------------------------------------------------------------------------------------------
-- Size (#280): the window is dragged bigger at its bottom right corner, the docked sheet at its inner
-- edge. The size is saved per layout in db.settings.ui.size and put on the layout's metrics (m.width,
-- m.height) when the layout is applied, so every page and list reads it from ctx.metrics as before.
-- m.baseWidth / m.baseHeight are the layout's own size: the smallest it can get.
----------------------------------------------------------------------------------------------------

M.DOCKED_MAX_SHARE = 0.5 -- a docked sheet takes at most this much of the screen width

-- The room a frame at `scale` has on the screen, in its own units: width, height (1920 x 1080 when the
-- client can't say).
function M.ScreenRoom(scale)
	scale = tonumber(scale) or 1
	if scale <= 0 then
		scale = 1
	end
	local w = UIParent and UIParent.GetWidth and UIParent:GetWidth() or nil
	local h = UIParent and UIParent.GetHeight and UIParent:GetHeight() or nil
	return math.floor((tonumber(w) or 1920) / scale), math.floor((tonumber(h) or 1080) / scale)
end

-- Width and height the layout's metrics `m` allow: at least the layout's own size, at most the screen (a
-- docked sheet: its share of it). A docked layout has no height of its own: nil.
local function Base(m)
	if rawget(m, "baseWidth") == nil then
		m.baseWidth, m.baseHeight = m.width, m.docked and nil or m.height
	end
	return m.baseWidth, m.baseHeight
end

function M.ClampSize(m, width, height, scale)
	local roomW, roomH = M.ScreenRoom(scale)
	local minW = Base(m)
	local maxW = m.docked and math.floor(roomW * M.DOCKED_MAX_SHARE) or roomW
	local w = math.max(minW, math.min(maxW, math.floor((tonumber(width) or minW) + 0.5)))
	if m.docked or not m.baseHeight then
		return w, nil
	end
	local h = math.max(m.baseHeight, math.min(math.max(roomH, m.baseHeight), math.floor((tonumber(height) or m.baseHeight) + 0.5)))
	return w, h
end

-- The bounds to give the client's resize: min width, min height, max width, max height.
function M.SizeBounds(m, scale)
	local roomW, roomH = M.ScreenRoom(scale)
	local minW, minH = Base(m)
	return minW, minH, math.max(roomW, minW), math.max(roomH, minH or 0)
end

-- The saved size of the layout, clamped, or its own size.
function M.SavedSize(key, m)
	key = key or M.LayoutKey()
	m = m or M.layouts[key].metrics
	local saved = M.UI().size[key]
	if type(saved) ~= "table" then
		return Base(m)
	end
	return M.ClampSize(m, saved.width, saved.height, M.UI().scale)
end

-- Puts the current layout's saved size on its metrics (before the layout is applied).
function M.ApplySize()
	local layout = M.Layout()
	local m = layout.metrics
	local w, h = M.SavedSize(layout.key, m)
	m.width = w
	if h then
		m.height = h
	end
	return w, h
end

-- Takes a size the user dragged to: clamps it, puts it on the metrics. save = remember it too.
function M.SetSize(width, height, save)
	local layout = M.Layout()
	local m = layout.metrics
	local w, h = M.ClampSize(m, width, height, M.UI().scale)
	m.width = w
	if h then
		m.height = h
	end
	if save then
		M.UI().size[layout.key] = { width = w, height = h }
	end
	return w, h
end

-- Settings: forget every dragged size; the layouts go back to their own.
function M.ResetSize()
	M.UI().size = {}
	if M.ApplyLayout then
		M.ApplyLayout()
	end
end

function M.CanDock()
	for _, key in ipairs(M.layoutOrder) do
		if M.layouts[key].docked then
			return true
		end
	end
	return false
end

-- The dock button and Shift-click on the minimap: window <-> the docked layout used last (else the first
-- one registered). A closed window opens, so the Shift-click shows where it went.
local function Toggle()
	if M.Layout().docked then
		return M.SetLayout("window")
	end
	local last = M.UI().lastDocked
	if last and M.layouts[last] and M.layouts[last].docked then
		return M.SetLayout(last)
	end
	for _, key in ipairs(M.layoutOrder) do
		if M.layouts[key].docked then
			return M.SetLayout(key)
		end
	end
	return false
end

function M.ToggleDock()
	local done = Toggle()
	if done and M.Open and not (M.frame and M.frame:IsShown()) then
		M.Open()
	end
	return done
end

----------------------------------------------------------------------------------------------------
-- States (spec: States). Pure: the frames in States.lua and Frame.lua draw what these return.
----------------------------------------------------------------------------------------------------

-- "41 min", "2 h", "1 day", "3 days".
function M.AgeText(seconds)
	seconds = math.max(0, seconds or 0)
	if seconds < 3600 then
		return ("%d min"):format(math.floor(seconds / 60))
	elseif seconds < 24 * 3600 then
		return ("%d h"):format(math.floor(seconds / 3600))
	end
	local days = math.floor(seconds / (24 * 3600))
	return days == 1 and L["1 day"] or (L["%d days"]):format(days)
end

-- "3 d": the age an AH figure carries while prices are stale.
function M.ShortAge(seconds)
	return ("%d d"):format(math.floor(math.max(0, seconds or 0) / (24 * 3600)))
end

-- 1240 -> "1 240" (the spec's "1 240 of 3 800").
function M.Thousands(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

-- Auctionator's prices count as prices at the profit house (#157; Prices.lua falls back to them, labelled
-- "house unknown"). True when Auctionator answers and CraftWise has read a price from it (Market's export)
-- or one of the first M.AUCTIONATOR_PROBE scope items has one now. A yes is kept for the session (its
-- prices don't go away); a no is asked again after M.AUCTIONATOR_RECHECK seconds.
M.AUCTIONATOR_PROBE = 40
M.AUCTIONATOR_RECHECK = 10

function M.AuctionatorHasPrices(now)
	if not (ns.HasAuctionator and ns.HasAuctionator()) then
		return false
	end
	local a = M.state.auctionator
	if a.seen then
		return true
	end
	local market = ns.Market
	if market and market.HasAuctionatorExports and market.HasAuctionatorExports() then
		a.seen = true
		return true
	end
	now = now or time()
	if a.checkedAt and now - a.checkedAt < M.AUCTIONATOR_RECHECK then
		return false
	end
	a.checkedAt = now
	for _, itemID in ipairs(market and market.ScopeItemIDs and market.ScopeItemIDs(M.AUCTIONATOR_PROBE) or {}) do
		if ns.GetAuctionPrice(itemID) then
			a.seen = true
			return true
		end
	end
	return false
end

-- The AH behind the prices: { house, label, at, age, stale, hasData, auctionator, hasPrices,
-- scanning = { label, done, total }, synced = { machine } }. hasData: CraftWise recorded something at the
-- house (synced: the newest of it came from the other machine's file, #241); auctionator:
-- without that, Auctionator has prices; hasPrices: either (the "No prices" rule). Stale only looks at
-- CraftWise's own records (Auctionator's age is per item, on the tooltips).
function M.PriceStatus(now)
	now = now or time()
	local s = {}
	if ns.ProfitHouse then
		s.house, s.label = ns.ProfitHouse()
	end
	local market = ns.Market
	s.at = market and market.LastRecorded and s.house and market.LastRecorded(s.house) or nil
	-- The other machine's scan (#241) counts as data when it is newer; the header says it was synced, never "scanned".
	if market and market.LastSynced and s.house then
		local syncedAt, machine = market.LastSynced(s.house)
		if syncedAt and (not s.at or syncedAt > s.at) then
			s.at, s.synced = syncedAt, { machine = machine }
		end
	end
	s.hasData = s.at ~= nil
	s.auctionator = not s.hasData and M.AuctionatorHasPrices(now) or false
	s.hasPrices = s.hasData or s.auctionator
	s.age = s.at and math.max(0, now - s.at) or nil
	s.stale = s.age ~= nil and s.age > M.STALE_SECONDS
	s.scanning = market and market.ScanProgress and market.ScanProgress() or nil
	s.own = M.ScanModel(now) -- our own scan's phase, progress and result (#285)
	return s
end

-- The header's AH status: text and its kind ("scanning" | "stale" | "ok" | "auctionator" | "none"), nil
-- without a house.
function M.StatusText(status)
	local Style = ns.Style
	local own = status.own
	if own and own.text then
		if own.kind == "scanning" then
			return Style.Hex("live") .. own.text .. "|r", "scanning"
		elseif own.kind == "failed" then
			return own.text, "stale"
		end
		return own.text, "done"
	end
	if status.scanning then
		local p = status.scanning
		return Style.Hex("live") .. L["Scanning"] .. " " .. (p.label or "") .. "|r" .. Style.Hex("text2") .. " · "
			.. (L["%s of %s"]):format(M.Thousands(p.done), M.Thousands(p.total)) .. "|r", "scanning"
	end
	if not status.label then
		return nil
	end
	if not status.hasData then
		if status.auctionator then
			return status.label .. " · " .. L["Auctionator prices"], "auctionator"
		end
		return status.label .. " · " .. L["no AH data"], "none"
	end
	local synced = status.synced
	local from = synced and (synced.machine and (L["synced from %s"]):format(synced.machine) or L["synced"])
	if status.stale then
		if from then
			return status.label .. " · " .. from .. " " .. M.AgeText(status.age) .. " " .. L["ago"], "stale"
		end
		return status.label .. " · " .. (L["scanned %s ago"]):format(M.AgeText(status.age)), "stale"
	end
	return status.label .. " · " .. (from and from .. " " or "") .. Style.Hex("text2") .. M.AgeText(status.age) .. "|r " .. L["ago"], "ok"
end

----------------------------------------------------------------------------------------------------
-- Scan AH (#6, #285): the button in the header while an auction house is open, and what the scan says while
-- it runs. The models are pure (they read Market only); Frame.lua draws them in the header (status line,
-- progress line, button) and on a small bar at the auction house. A click asks the server for the whole list
-- once, never by itself. Only numbers the client gives; the one estimate (≈ left) is computed from the
-- progress measured so far and labelled as such.
----------------------------------------------------------------------------------------------------

M.SCAN_DONE_SECONDS = 10 -- the summary of a finished scan stays this long

-- 754 -> "12:34" (rounded up: the countdown of the cooldown).
function M.Countdown(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- 23.9 -> "0:23" (rounded down: time that has passed).
function M.Clock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- What a failed scan says (a line for the chat and the tooltip); `detail` is the client's error text.
function M.ScanFailText(reason, detail)
	local market = ns.Market
	if reason == "timeout" then
		local text = (L["No list arrived within %d s. Another addon may have scanned in the last 15 minutes (the server then sends nothing), the game's auction house throttle held the request back, or a slow or busy connection delayed the list (a list that still arrives within 15 minutes of the request is read and stored). Nothing has been stored yet; try again after the countdown, or use Try again anyway."])
			:format(market and market.OWN_WAIT_SECONDS or 0)
		if type(detail) == "table" then
			text = text .. " " .. (L["Throttle events after the request: sent %d, queued %d, dropped %d."])
				:format(detail.sent or 0, detail.queued or 0, detail.dropped or 0)
		end
		return text
	elseif reason == "notready" then
		return (L["The auction house wasn't ready for a request within %d s: other addons' queries were still going. Nothing was sent, so no waiting time was used; try again."])
			:format(market and market.OWN_READY_SECONDS or 0)
	elseif reason == "dropped" then
		return L["The game dropped the request before it was sent (its auction house throttle). Nothing was stored and the 15 minutes were not used: click again."]
	elseif reason == "closed" then
		return L["The auction house closed before the list was read. Nothing was stored."]
	elseif reason == "changed" then
		return L["The list changed while it was being read. Nothing was stored."]
	end
	return (L["The game refused the scan request: %s"]):format(tostring(detail or "?"))
end

-- The same in a few words, for the header.
local function ScanFailShort(reason, timeout)
	if reason == "timeout" then
		return (L["no list within %s"]):format(M.Clock(timeout))
	elseif reason == "notready" then
		return L["the auction house wasn't ready"]
	elseif reason == "dropped" then
		return L["the game dropped the request"]
	elseif reason == "closed" then
		return L["the auction house was closed"]
	elseif reason == "changed" then
		return L["the list changed"]
	end
	return L["the game refused the request"]
end

-- Seconds left, worked out from what was measured so far: only after 3 s and 5 % of the work, never for a
-- finished or unknown phase.
local function Eta(done, total, since, now)
	if not (done and total and since and total > 0) or done >= total then
		return nil
	end
	local spent = now - since
	if spent < 3 or done / total < 0.05 then
		return nil
	end
	return math.ceil(spent * (total - done) / done)
end

-- What the own scan shows right now, nil when there is nothing to show (idle, or a finished scan's summary
-- has been up for M.SCAN_DONE_SECONDS):
--   { state, kind = "scanning" | "done" | "failed", text, hint, fraction (0..1 or nil), eta (seconds or nil) }
function M.ScanModel(now)
	now = now or time()
	local market = ns.Market
	if not (market and market.OwnScan) then
		return nil
	end
	local s = market.OwnScan(now)
	local st = s.state
	local model = { state = st }
	if st == "ready" then
		local elapsed, timeout = s.elapsed or 0, s.readyTimeout or 0
		model.kind = "scanning"
		model.text = (L["Waiting for the auction house to be ready · %s / %s"]):format(M.Clock(elapsed), M.Clock(timeout))
		model.fraction = timeout > 0 and math.min(elapsed / timeout, 1) or 0
		model.hint = L["The game is still answering other addons' queries. Nothing has been sent yet."]
	elseif st == "requested" or st == "waiting" then
		local elapsed, timeout = s.elapsed or 0, s.timeout or 0
		model.kind = "scanning"
		local format = s.queued and L["Queued by the game, not sent yet · %s / %s"] or L["Waiting for the server · %s / %s"]
		model.text = format:format(M.Clock(elapsed), M.Clock(timeout))
		model.fraction = timeout > 0 and math.min(elapsed / timeout, 1) or 0
		model.hint = s.queued and L["The game's request throttle is holding it back. Keep the auction house open."]
			or L["Keep the auction house open."]
	elseif st == "reading" or st == "loading" or st == "storing" then
		local p = market.ScanProgress and market.ScanProgress()
		local done, total = p and p.done or 0, p and p.total or s.rows or 0
		model.kind = "scanning"
		model.fraction = total > 0 and math.min(done / total, 1) or 0
		local format = st == "reading" and L["Reading the list · %s of %s · %d %%"]
			or st == "loading" and L["Loading item data · %s of %s · %d %%"]
			or L["Storing prices · %s of %s · %d %%"]
		model.text = format:format(M.Thousands(done), M.Thousands(total), math.floor(model.fraction * 100))
		model.hint = st == "storing" and L["Closing the auction house is safe now."] or L["Keep the auction house open."]
		model.eta = Eta(done, total, s.phaseAt, now)
	elseif st == "done" and s.finishedAt and now - s.finishedAt <= M.SCAN_DONE_SECONDS then
		local last = s.last or {}
		model.kind = "done"
		model.fraction = 1
		model.text = (L["Scan done · %s rows · %s items · %s"]):format(M.Thousands(last.rows or 0),
			M.Thousands((last.items or 0) + (last.lastOnly or 0)), M.Clock(s.finishedAt - (s.requestedAt or s.finishedAt)))
		if (last.unread or 0) > 0 then
			model.text = model.text .. " · " .. (L["%s items not read"]):format(M.Thousands(last.unread))
		end
		model.hint = L["Everything is stored. The button now counts down to the next scan."]
	elseif st == "failed" then
		model.kind = "failed"
		model.text = (L["Scan failed · %s"]):format(ScanFailShort(s.error, s.timeout))
		model.hint = M.ScanFailText(s.error, s.detail)
		model.retry = s.cooldown <= 0 -- a dropped or never sent request used no cooldown
	else
		return nil
	end
	return model
end

-- { show, label, enabled, state, tip = { title, lines... } } of the header's scan button.
--   ready        "Scan AH"                         enabled
--   cooldown     "Next scan in 12:34"              disabled; the tooltip says why it counts
--   requested / waiting   "Waiting · 0:23 / 2:00"
--   reading / storing     "Reading · 24 %" / "Storing · 27 %"
function M.ScanButton(now)
	now = now or time()
	local market = ns.Market
	local model = { show = false, enabled = false, tip = {} }
	if not (market and market.OwnScan and market.CurrentHouse and market.CurrentHouse()) then
		return model
	end
	local s = market.OwnScan(now)
	if s.block == "unsupported" or s.block == "nodata" then
		return model
	end
	model.show, model.state = true, s.state
	local tip = model.tip
	local scan = M.ScanModel(now)
	tip[1] = L["Scan the auction house"]
	if s.state == "ready" then
		model.label = (L["Getting ready · %s"]):format(M.Clock(s.elapsed or 0))
	elseif s.state == "requested" or s.state == "waiting" then
		model.label = (L["Waiting · %s / %s"]):format(M.Clock(s.elapsed or 0), M.Clock(s.timeout or 0))
	elseif s.state == "reading" or s.state == "loading" or s.state == "storing" then
		local pct = math.floor((scan and scan.fraction or 0) * 100)
		model.label = ((s.state == "reading" and L["Reading · %d %%"] or s.state == "loading" and L["Loading · %d %%"]
			or L["Storing · %d %%"])):format(pct)
	elseif s.cooldown > 0 then
		model.label = (L["Next scan in %s"]):format(M.Countdown(s.cooldown))
	else
		model.label, model.enabled = L["Scan AH"], true
	end
	if scan and scan.kind == "scanning" then
		tip[#tip + 1] = scan.text
		tip[#tip + 1] = scan.hint
		if scan.eta then
			tip[#tip + 1] = (L["≈ %s left (worked out from the progress so far)"]):format(M.Clock(scan.eta))
		end
	elseif s.cooldown > 0 then
		tip[#tip + 1] = (L["Next scan in %s."]):format(M.Countdown(s.cooldown))
		tip[#tip + 1] = L["The server allows one full list per account every 15 minutes. The countdown starts when the request is sent, not when the list arrives, so it runs after a failed scan or a closed auction house too. A list another addon asked for counts as well."]
		if scan and scan.kind == "failed" then
			tip[#tip + 1] = ns.Style.Hex("danger") .. scan.hint .. "|r"
		elseif scan and scan.kind == "done" then
			tip[#tip + 1] = scan.text
		end
	else
		tip[#tip + 1] = L["Asks for every auction at once (one request, only when you click). The game may stutter or lag while the list arrives."]
		if scan and scan.kind == "failed" then
			tip[#tip + 1] = ns.Style.Hex("danger") .. scan.hint .. "|r"
		end
	end
	if s.retryable and s.cooldown > 0 then
		model.retry = {
			label = L["Try again anyway"],
			tip = { L["Try again anyway"],
				L["Asks for the list again without waiting for the countdown. The server may send nothing if it counted the first request. If the first list still arrives, it is stored."] },
		}
	end
	local last = s.last
	if last then
		tip[#tip + 1] = (L["Last own scan %s ago: %s rows, %s items."]):format(M.AgeText(now - (last.t or now)),
			M.Thousands(last.rows), M.Thousands((last.items or 0) + (last.lastOnly or 0)))
	end
	return model
end

-- The header's AH status tooltip (#157: Records › Market's per-house scan summary moved here): a title and
-- one line per house CraftWise recorded at (faction houses first): its last full scan and how many items
-- have a price there, then Auctionator's prices read so far. Pure apart from reading Market.
function M.ScanSummary(now)
	now = now or time()
	local title = L["Auction houses"]
	local market = ns.Market
	local ok, sum = false, nil
	if market and market.SnapshotSummary then
		ok, sum = pcall(market.SnapshotSummary)
	end
	if not (ok and sum and sum.houses) then
		return title, { L["Market data not loaded."] }
	end
	local houses = {}
	for key, h in pairs(sum.houses) do
		h.key = key
		houses[#houses + 1] = h
	end
	table.sort(houses, function(a, b)
		if (a.kind == "faction") ~= (b.kind == "faction") then
			return a.kind == "faction"
		end
		return (a.label or "") < (b.label or "")
	end)
	local profit = ns.ProfitHouse and ns.ProfitHouse()
	local function Items(n)
		return M.Thousands(n) .. " " .. (n == 1 and L["item"] or L["items"])
	end
	local lines = {}
	for _, h in ipairs(houses) do
		local scan = h.lastFullScan and (L["full scan %s ago"]):format(M.AgeText(now - h.lastFullScan)) or L["no full scan"]
		if h.lastSynced then
			scan = scan .. " · " .. (h.lastSyncedMachine and (L["synced from %s"]):format(h.lastSyncedMachine) or L["synced"])
				.. " " .. M.AgeText(now - h.lastSynced) .. " " .. L["ago"]
		end
		lines[#lines + 1] = ("%s%s: %s · %s, %s %s"):format(h.label or "?", h.key == profit and (" (" .. L["profit"] .. ")") or "",
			scan, Items(h.items), M.Thousands(h.withHistory), L["with history"])
	end
	if #lines == 0 then
		lines[1] = L["No auction house visited yet: open one and CraftWise records what you browse and scan."]
	end
	local a = sum.auctionator
	if a and (a.items or 0) > 0 then
		lines[#lines + 1] = ("%s: %s %s"):format(a.label or "Auctionator", Items(a.items), L["read"])
	end
	return title, lines
end

-- "Horde AH" -> "Horde auction house", "Booty Bay" -> "Booty Bay auction house".
local function HouseName(label)
	if not label then
		return L["the auction house"]
	end
	return (label:gsub(" AH$", "")) .. " " .. L["auction house"]
end

-- The copy of the states (final per the spec and the "States" board).
function M.StateCopy(state, ctx)
	if state == "firstRun" then
		local name = ctx.prof and ctx.prof.name
		return {
			title = name and (L["Open your %s window once."]):format(name) or L["Open your profession window once."],
			body = L["CraftWise reads your recipes from it. Profits appear here right after."],
		}
	elseif state == "noPrices" then
		return {
			title = L["No auction house visited yet."],
			body = (L["Open the %s and browse or run a scan. Until then, profits use vendor prices where an item has one."])
				:format(HouseName(ctx.prices and ctx.prices.label)),
			button = L["Show vendor-only profits"],
		}
	elseif state == "stale" then
		return {
			title = (L["Prices are %s old."]):format(M.AgeText(ctx.prices and ctx.prices.age)),
			body = L["Profits may be off. Scan at the auction house to refresh."],
		}
	elseif state == "error" then
		return {
			title = (L["%s could not be built."]):format(ctx.page and ctx.page.title or "?"),
			body = L["Your saved data is untouched; the other pages still work."],
			reload = L["Reload UI"],
			show = L["Show error text"],
		}
	end
end

M.NO_PRICE = "no price" -- spec "Unknown price": in C.text3; the result shows M.DASH
M.DASH = "—"

-- "no price" in C.text3, for a cell without a price.
function M.NoPriceText()
	return ns.Style.Hex("text3") .. L[M.NO_PRICE] .. "|r"
end

M.state = { vendorOnly = {}, sort = {}, auctionator = {} } -- this session: Show vendor-only profits, sort per page,
-- what M.AuctionatorHasPrices found

-- The state that replaces a page's body: "firstRun" | "noPrices" | nil. No prices: neither CraftWise's
-- records nor Auctionator have prices at the profit house (M.PriceStatus().hasPrices).
function M.BlockingState(page, ctx)
	if page.profession and not (ctx.prof and next(ctx.prof.recipes or {})) then
		return "firstRun"
	end
	if page.prices and not page.pricesOptional and not (ctx.prices and ctx.prices.hasPrices) and not M.state.vendorOnly[page.key] then
		return "noPrices"
	end
	return nil
end

-- What a page gets: { page, professionID, prof, prices, layout, metrics, vendorOnly }.
function M.Context(page, now)
	local ctx = { page = page, layout = M.LayoutKey(), metrics = M.Layout() and M.Layout().metrics or {} }
	if page and page.profession then
		ctx.professionID, ctx.prof = M.Profession() -- with "all": the first profession with recipes, for the states
		ctx.all = M.ShowsAll(page) or nil
	end
	if page and page.prices then
		ctx.prices = M.PriceStatus(now)
		ctx.vendorOnly = M.state.vendorOnly[page.key] or false
	end
	return ctx
end

-- Runs a page function; a raise becomes ok = false and the error text (the Error state).
function M.Call(fn, ...)
	if not fn then
		return true, nil
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		return false, tostring(res)
	end
	return true, res
end

----------------------------------------------------------------------------------------------------
-- List helpers (pure): column positions and sorting.
----------------------------------------------------------------------------------------------------

M.COLUMN_GAP = 12

-- x and width of each column inside a row of `width` with `pad` on both sides.
--   col.width  the column's width (its minimum when it can grow).
--   no width   the flexible column (the first one): it takes what the others leave, at least col.min (40).
--   col.grow   the width a column wants when there is room (text that is cut at col.width, #280): it gets
--              the room before the flexible column does, in column order, up to that width.
-- `baseWidth` is the layout's own width: the growing columns and a fixed "name" column only get what the
-- window was dragged past it (without it they get nothing), so the default look stays; the flexible column
-- always takes what is left.
function M.ColumnLayout(columns, width, pad, gap, baseWidth)
	gap = gap or M.COLUMN_GAP
	local flex
	for i, col in ipairs(columns) do
		if not col.width and not flex then
			flex = i
		end
	end
	local inner = width - 2 * pad - gap * math.max(#columns - 1, 0)
	local widths, used, nameAt = {}, 0, nil
	for i, col in ipairs(columns) do
		widths[i] = col.width or (i == flex and (col.min or 40)) or 0
		used = used + widths[i]
		if col.key == "name" and not nameAt then
			nameAt = i
		end
	end
	local free = inner - used
	if not flex and baseWidth then
		free = math.min(free, math.max(width - baseWidth, 0))
	end
	if free > 0 then
		-- Columns that want more only get what the window was dragged past its own width (baseWidth).
		local room = baseWidth and math.min(free, math.max(width - baseWidth, 0)) or 0
		for i, col in ipairs(columns) do
			local want = col.grow and col.grow - widths[i] or 0
			if want > 0 and room > 0 then
				local take = math.min(want, room)
				widths[i] = widths[i] + take
				room = room - take
				free = free - take
			end
		end
	end
	if free > 0 then
		local at = flex or (baseWidth and nameAt)
		if at then
			widths[at] = widths[at] + free
		end
	end
	local out, x = {}, pad
	for i = 1, #columns do
		out[i] = { x = x, width = widths[i] }
		x = x + widths[i] + gap
	end
	return out
end

-- The sort of a page this session: key, desc (the page's default sort until a header is clicked).
function M.Sort(page)
	local s = M.state.sort[page.key]
	if not s then
		local saved = M.UI().sort[page.key]
		if type(saved) == "table" and saved.key then
			for _, col in ipairs(page.columns or {}) do
				if col.sort and col.key == saved.key then
					s = { key = saved.key, desc = saved.desc and true or false }
					break
				end
			end
		end
	end
	if s then
		return s.key, s.desc
	end
	if page.sort then
		return page.sort.key, page.sort.desc
	end
	return nil
end

-- A header click: sort by the column, again to reverse.
function M.ClickSort(page, key)
	local cur, desc = M.Sort(page)
	local s = { key = key, desc = true }
	if cur == key then
		s.desc = not desc
	end
	M.state.sort[page.key] = s
	M.UI().sort[page.key] = { key = s.key, desc = s.desc } -- remembered across sessions (#197)
	M.Refresh()
end

-- Back to the page's default sort (forgets the chosen one).
function M.ResetSort(pageKey)
	M.state.sort[pageKey] = nil
	M.UI().sort[pageKey] = nil
end

-- Sorts rows by row[key] (nil last), ties by name; the page's own SortRows when it has one.
function M.SortRows(page, rows)
	local key, desc = M.Sort(page)
	if not key then
		return rows
	end
	if page.SortRows then
		page.SortRows(rows, key, desc)
		return rows
	end
	table.sort(rows, function(a, b)
		local va, vb = a[key], b[key]
		if va == vb or (va == nil and vb == nil) then
			return tostring(a.name or "") < tostring(b.name or "")
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		end
		if type(va) ~= type(vb) then
			va, vb = tostring(va), tostring(vb)
		end
		if type(va) == "string" then
			va, vb = va:lower(), vb:lower()
		end
		if desc then
			return va > vb
		end
		return va < vb
	end)
	return rows
end

-- The identity of a row across refreshes (the open row stays open).
function M.RowKey(row)
	return row.key or row.recipeID or row.itemID or row.name
end

-- Filled by Frame.lua.
function M.Refresh() end
