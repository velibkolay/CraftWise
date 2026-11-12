-- Farm sessions as plain data (#137, #156): the finished sessions (Farm.History, newest first) and the
-- session that is open now, for Gather › Farm (UI/Main/Pages/Farm.lua), which draws them. The numbers of a
-- finished session are the ones it kept when it ended (Farm.Summary); the open session is valued now
-- (Farm.Totals). No frames here: the old History panel beside the farm tracker is gone, its home is the page.
local _, ns = ...
local L = ns.L
local Farm = ns.Farm

local FH = {}
ns.FarmHistory = FH

FH.CURRENT = "current" -- row key of the open session

-- "1:48" (hours:minutes, board "Gather › Farm").
function FH.Duration(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- "Wed 11 · 21:04".
function FH.Started(t)
	t = t or 0
	return ("%s %d · %s"):format(date("%a", t), tonumber(date("%d", t)) or 0, date("%H:%M", t))
end

----------------------------------------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------------------------------------

-- One row per finished session, newest first:
-- { key, index, start, started, zone, zonesMore, fishing, seconds, time, total, gph, coin, items, unknown }
function FH.ListRows(history)
	local out = {}
	for i, h in ipairs(history or {}) do
		local more = (h.zonesMore or 0) + math.max(#(h.zones or {}) - 1, 0)
		out[i] = { key = h.start and ("h" .. h.start) or ("i" .. i), index = i, start = h.start, started = FH.Started(h.start),
			zone = h.zone or L["unknown zone"], zonesMore = more, fishing = h.fish ~= nil, seconds = h.seconds or 0,
			time = FH.Duration(h.seconds), coin = h.coin or 0, items = h.items or 0,
			total = (h.coin or 0) + (h.items or 0), gph = h.gph, unknown = h.unknown or 0 }
	end
	return out
end

-- The open session as a row (same fields), with state = "running" | "paused" | "idle"; nil without one.
function FH.SessionRow(s, now)
	if not s then
		return nil
	end
	local t = Farm.Totals(s, now)
	local zone = s.zone or (t.zones[1] and t.zones[1].zone)
	return { key = FH.CURRENT, current = true, start = s.start, started = FH.Started(s.start), zone = zone or L["unknown zone"],
		zonesMore = math.max(#t.zones - 1, 0), fishing = t.fish ~= nil, seconds = t.seconds, time = FH.Duration(t.seconds),
		coin = t.coin, items = t.items, total = t.total, gph = t.gph, unknown = t.unknownItems,
		state = Farm.Running(s) and "running" or (s.autoPaused and "idle" or "paused") }
end

----------------------------------------------------------------------------------------------------
-- Opened rows
----------------------------------------------------------------------------------------------------

-- A finished session opened: { top = { { itemID, name, n, value } }, zones = { { zone, time, gph } }, zonesMore,
--   split = { coin, ah, vendor, vendorOnly, vendorUnknown, stale, unknown }, fish, logLines, logDropped,
--   log (entries, newest first; nil when not kept), logNote }
function FH.Detail(h)
	local d = { top = {}, zones = {}, zonesMore = h.zonesMore or 0,
		split = { coin = h.coin or 0, ah = h.ah or 0, vendor = (h.items or 0) - (h.ah or 0), vendorOnly = h.vendor,
			vendorUnknown = h.vendorUnknown, stale = h.stale or 0, unknown = h.unknown or 0 },
		fish = h.fish, logDropped = h.logDropped }
	for i, t in ipairs(h.top or {}) do
		d.top[i] = { itemID = t.id, name = t.name or ("item " .. tostring(t.id)), n = t.n or 0, value = t.value }
	end
	for i, z in ipairs(h.zones or {}) do
		d.zones[i] = { zone = z.zone, seconds = z.seconds, time = FH.Duration(z.seconds), gph = z.gph }
	end
	if h.log and #h.log > 0 then
		d.log = Farm.LogEntries(h)
		d.logLines = #d.log
		d.logNote = (L["%d loot lines kept"]):format(#d.log)
	elseif (h.logLines or 0) > 0 then
		d.logLines = h.logLines
		d.logNote = (L["Loot log not kept: only the newest %d sessions keep theirs (%d lines)."]):format(Farm.HISTORY_LOGS, h.logLines)
	else
		d.logNote = L["No loot log for this session."]
	end
	return d
end

-- The open session opened: like FH.Detail, plus items = every looted item valued now (Farm.Totals rows:
-- itemID, n, value, source, stale, age, label, noAuction), the ones a click can remove from the session.
function FH.SessionDetail(s, now)
	local t = Farm.Totals(s, now)
	local d = { items = t.rows, zones = {}, zonesMore = 0,
		split = { coin = t.coin, ah = t.ah, vendor = t.items - t.ah, vendorOnly = t.vendor, vendorUnknown = t.vendorUnknown,
			stale = t.stale, unknown = t.unknownUnits },
		fish = t.fish, logDropped = s.logDropped, current = true }
	for i, z in ipairs(t.zones) do
		d.zones[i] = { zone = z.zone, seconds = z.seconds, time = FH.Duration(z.seconds), gph = z.gph }
	end
	d.log = Farm.LogEntries(s)
	d.logLines = #d.log
	d.logNote = #d.log > 0 and (L["%d loot lines"]):format(#d.log) or L["Nothing looted yet."]
	return d
end

----------------------------------------------------------------------------------------------------
-- Opening: Gather › Farm, optionally with a finished session (index) opened
----------------------------------------------------------------------------------------------------

function FH.Open(index)
	if ns.OpenFarmPage then
		local rows = index and FH.ListRows(Farm.History()) or nil
		return ns.OpenFarmPage(rows and rows[index] and rows[index].key or nil)
	end
	return false
end
