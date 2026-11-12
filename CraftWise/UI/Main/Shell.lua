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
--   events = { "BAGS_CHANGED", ... }   ns.Notify names that refresh the page while it shows
--   Model(ctx) -> model           list pages: { rows, hero, empty, footer, footerRight, listTitle,
--                                  listNote }; rows are plain tables (itemID, icon, name, cells = {}, key)
--   columns = list | function(ctx) -> list of { key, label, width (nil = takes what is left), align,
--                                  sort (true = the header sorts by row[key]), text(row) -> text, color }
--   rowHeight, InitRow(row, data, ctx), SortRows(rows, key, desc),
--   Open(content, data, ctx) + OpenHeight(data, ctx)   rows that open in place
--   Hero(card, hero, ctx, slot)   draws into the hero card's middle (rails); label/name/sub/figure are
--                                  filled by the shell from model.hero. slot = the page's own frame
--                                  over the middle (hidden while other pages show). hero.full = true:
--                                  the middle is the whole card inside its padding; hero.bare = true:
--                                  no card, the slot is the whole hero area (the page draws its cards)
--   noHeader = true               no header row (group rows carry the rule, board "Bags")
--   OnClick(row, ctx)             a left click on a row of a page without Open
--   Tools(slot, ctx), ListTools(slot, ctx), FooterTools(slot, ctx)   build once; Update*(slot, ctx)
--   Build(body, ctx), Refresh(body, ctx)   custom pages
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
	profession = nil, -- professionID chosen on the Make pages
	layout = "window", -- "window"; the docked layouts register their own keys (#161)
	escape = true, -- Close with Escape (Settings > Look)
	locked = false, -- Lock position (Settings > Look)
	scale = 1, -- Scale (Settings > Look)
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

function M.CanDock()
	for _, key in ipairs(M.layoutOrder) do
		if M.layouts[key].docked then
			return true
		end
	end
	return false
end

-- The dock button and Shift-click on the minimap: window <-> the docked layout used last (else the first
-- one registered).
function M.ToggleDock()
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

-- The AH behind the prices: { house, label, at, age, stale, hasData, scanning = { label, done, total } }.
function M.PriceStatus(now)
	now = now or time()
	local s = {}
	if ns.ProfitHouse then
		s.house, s.label = ns.ProfitHouse()
	end
	local market = ns.Market
	s.at = market and market.LastRecorded and s.house and market.LastRecorded(s.house) or nil
	s.hasData = s.at ~= nil
	s.age = s.at and math.max(0, now - s.at) or nil
	s.stale = s.age ~= nil and s.age > M.STALE_SECONDS
	s.scanning = market and market.ScanProgress and market.ScanProgress() or nil
	return s
end

-- The header's AH status: text and its kind ("scanning" | "stale" | "ok" | "none"), nil without a house.
function M.StatusText(status)
	local Style = ns.Style
	if status.scanning then
		local p = status.scanning
		return Style.Hex("live") .. L["Scanning"] .. " " .. (p.label or "") .. "|r" .. Style.Hex("text2") .. " · "
			.. (L["%s of %s"]):format(M.Thousands(p.done), M.Thousands(p.total)) .. "|r", "scanning"
	end
	if not status.label then
		return nil
	end
	if not status.hasData then
		return status.label .. " · " .. L["no AH data"], "none"
	end
	if status.stale then
		return status.label .. " · " .. (L["scanned %s ago"]):format(M.AgeText(status.age)), "stale"
	end
	return status.label .. " · " .. Style.Hex("text2") .. M.AgeText(status.age) .. "|r " .. L["ago"], "ok"
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

M.state = { vendorOnly = {}, sort = {} } -- this session: Show vendor-only profits, sort per page

-- The state that replaces a page's body: "firstRun" | "noPrices" | nil.
function M.BlockingState(page, ctx)
	if page.profession and not (ctx.prof and next(ctx.prof.recipes or {})) then
		return "firstRun"
	end
	if page.prices and not (ctx.prices and ctx.prices.hasData) and not M.state.vendorOnly[page.key] then
		return "noPrices"
	end
	return nil
end

-- What a page gets: { page, professionID, prof, prices, layout, metrics, vendorOnly }.
function M.Context(page, now)
	local ctx = { page = page, layout = M.LayoutKey(), metrics = M.Layout() and M.Layout().metrics or {} }
	if page and page.profession then
		ctx.professionID, ctx.prof = M.Profession()
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

-- x and width of each column inside a row of `width` with `pad` on both sides; one column without a
-- width takes what the others leave (at least 40).
function M.ColumnLayout(columns, width, pad, gap)
	gap = gap or M.COLUMN_GAP
	local fixed, flex = 0, nil
	for i, col in ipairs(columns) do
		if col.width then
			fixed = fixed + col.width
		elseif not flex then
			flex = i
		end
	end
	local inner = width - 2 * pad - gap * math.max(#columns - 1, 0)
	local out, x = {}, pad
	for i, col in ipairs(columns) do
		local w = col.width or (i == flex and math.max(inner - fixed, 40)) or 0
		out[i] = { x = x, width = w }
		x = x + w + gap
	end
	return out
end

-- The sort of a page this session: key, desc (the page's default sort until a header is clicked).
function M.Sort(page)
	local s = M.state.sort[page.key]
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
	if cur == key then
		M.state.sort[page.key] = { key = key, desc = not desc }
	else
		M.state.sort[page.key] = { key = key, desc = true }
	end
	M.Refresh()
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
