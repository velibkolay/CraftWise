-- Performance measuring (#194): Settings > Debug > Record. While recording, Core.lua reports the run time
-- of every ns.On handler, ns.Listen callback and ns.Timed hook (BagIcons) to Perf.Record; a frame monitor
-- notes every slow frame and how much of it CraftWise handlers took; C_AddOnProfiler tells how the other
-- addons did over the same stretch. Off, nothing runs and nothing is kept (one upvalue test per handler).
-- The report is plain text: shown on the Debug group and in a box to copy (the client has no clipboard API).
local _, ns = ...

local Perf = {}
ns.Perf = Perf

Perf.SPIKE_MS = 30 -- a frame this long is logged as a slow frame
Perf.MAX_SPIKES = 8
Perf.TOP = 10 -- rows per list in the report
Perf.TOP_ADDONS = 8

local state -- nil while not recording
local report -- lines of the last finished recording, or nil

local function Now()
	return debugprofilestop()
end

local function Ms(v)
	return ("%.1f ms"):format(v or 0)
end

function Perf.IsRecording()
	return state ~= nil
end

----------------------------------------------------------------------------------------------------
-- Other addons: C_AddOnProfiler counts the ticks (frames) an addon's time went over a limit.
----------------------------------------------------------------------------------------------------

-- Enum.AddOnProfilerMetric (Blizzard_APIDocumentationGenerated/AddOnProfilerConstantsDocumentation.lua).
local function MetricIds()
	local E = Enum and Enum.AddOnProfilerMetric or {}
	return {
		session = E.SessionAverageTime or 0, recent = E.RecentAverageTime or 1, peak = E.PeakTime or 4,
		over5 = E.CountTimeOver5Ms or 6, over10 = E.CountTimeOver10Ms or 7, over50 = E.CountTimeOver50Ms or 8,
		over100 = E.CountTimeOver100Ms or 9,
	}
end

local function Profiler()
	return C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and C_AddOnProfiler or nil
end

local function LoadedAddons()
	local list = {}
	local A = C_AddOns
	local n = A and A.GetNumAddOns and A.GetNumAddOns() or 0
	for i = 1, n do
		local ok, name = pcall(A.GetAddOnName, i)
		if ok and type(name) == "string" and name ~= "" then
			local okLoaded, loaded = pcall(A.IsAddOnLoaded, name)
			if okLoaded and loaded then
				list[#list + 1] = name
			end
		end
	end
	if #list == 0 then
		list[1] = ns.name
	end
	return list
end

local function Metric(name, id)
	local P = Profiler()
	if not P then
		return 0
	end
	local ok, v = pcall(P.GetAddOnMetric, name, id)
	return ok and tonumber(v) or 0
end

local function AddonSnapshot()
	local ids, snap = MetricIds(), {}
	for _, name in ipairs(LoadedAddons()) do
		snap[name] = { over5 = Metric(name, ids.over5), over10 = Metric(name, ids.over10),
			over50 = Metric(name, ids.over50), over100 = Metric(name, ids.over100) }
	end
	return snap
end

-- Rows { name, over5, over10, over50, recent, peak } for the addons that had slow ticks during the
-- recording (CraftWise always), worst first.
local function AddonRows(before)
	local ids, rows = MetricIds(), {}
	for name, b in pairs(before) do
		local row = { name = name, over5 = Metric(name, ids.over5) - b.over5, over10 = Metric(name, ids.over10) - b.over10,
			over50 = Metric(name, ids.over50) - b.over50, over100 = Metric(name, ids.over100) - b.over100,
			recent = Metric(name, ids.recent), peak = Metric(name, ids.peak) }
		if name == ns.name or row.over5 > 0 or row.over10 > 0 then
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		if a.over100 ~= b.over100 then return a.over100 > b.over100 end
		if a.over50 ~= b.over50 then return a.over50 > b.over50 end
		if a.over10 ~= b.over10 then return a.over10 > b.over10 end
		if a.over5 ~= b.over5 then return a.over5 > b.over5 end
		return a.name < b.name
	end)
	return rows
end

local function TopLines(metricId, k)
	local P = C_AddOnProfiler
	local lines = {}
	if not (P and P.GetTopKAddOnsForMetric) then
		return lines
	end
	local ok, results = pcall(P.GetTopKAddOnsForMetric, metricId, k)
	if ok and type(results) == "table" then
		for i, r in ipairs(results) do
			lines[#lines + 1] = ("  %d. %s  %s"):format(i, tostring(r.addOnName), Ms(r.metricValue))
		end
	end
	return lines
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

-- Called by Core.lua for every timed run: kind "event" | "notify" | "hook".
function Perf.Record(kind, name, label, ms)
	local s = state
	if not s then
		return
	end
	if kind == "request" or kind == "skipped" then
		local r = s.requests[label]
		if not r then
			r = { label = label, sent = 0, skipped = 0 }
			s.requests[label] = r
		end
		if kind == "request" then
			r.sent = r.sent + 1
			s.sent = s.sent + 1
		else
			r.skipped = r.skipped + 1
			s.skipped = s.skipped + 1
		end
		return
	end
	local key = kind .. "\0" .. name .. "\0" .. tostring(label)
	local st = s.stats[key]
	if not st then
		st = { kind = kind, name = name, label = tostring(label), n = 0, total = 0, max = 0 }
		s.stats[key] = st
	end
	st.n = st.n + 1
	st.total = st.total + ms
	if ms > st.max then
		st.max = ms
	end
	-- Notify runs inside handlers (already counted there), so only handlers and hooks sum into the frame.
	if kind ~= "notify" then
		s.cw = s.cw + ms
		s.cwTotal = s.cwTotal + ms
		if ms > s.topMs then
			s.topMs, s.topName = ms, name .. " " .. tostring(label)
		end
	end
end

local function FrameTick(_, _)
	local s = state
	if not s then
		return
	end
	local now = Now()
	local dt = now - s.last
	s.last = now
	if not s.primed then
		s.primed = true -- the first frame holds the click that started the recording
		s.cw, s.topMs, s.topName = 0, 0, nil
		return
	end
	s.frames = s.frames + 1
	if dt > s.worst then
		s.worst = dt
	end
	if dt >= 33 then s.over33 = s.over33 + 1 end
	if dt >= 50 then s.over50 = s.over50 + 1 end
	if dt >= 100 then s.over100 = s.over100 + 1 end
	if dt >= Perf.SPIKE_MS then
		local spikes = s.spikes
		spikes[#spikes + 1] = { at = (now - s.t0) / 1000, ms = dt, cw = s.cw, top = s.topName, topMs = s.topMs }
		table.sort(spikes, function(a, b) return a.ms > b.ms end)
		spikes[Perf.MAX_SPIKES + 1] = nil
	end
	s.cw, s.topMs, s.topName = 0, 0, nil
end

local ticker = CreateFrame("Frame")
Perf.ticker = ticker
ticker:Hide()
ticker:SetScript("OnUpdate", FrameTick)

function Perf.Start()
	if state then
		return
	end
	state = { t0 = Now(), last = Now(), stats = {}, frames = 0, worst = 0, over33 = 0, over50 = 0, over100 = 0,
		spikes = {}, cw = 0, cwTotal = 0, topMs = 0, addons = AddonSnapshot(), requests = {}, sent = 0, skipped = 0 }
	ns.SetRecorder(Perf.Record)
	ticker:Show()
end

local function Sorted(list, key)
	table.sort(list, function(a, b)
		if a[key] ~= b[key] then return a[key] > b[key] end
		return (a.label or a.name) < (b.label or b.name)
	end)
	return list
end

local function Build(s, seconds)
	local lines = {}
	local function add(...) lines[#lines + 1] = ("%s"):format(...) end
	add(("CraftWise performance: recorded %.1f s, %d frames (%.0f fps)"):format(seconds, s.frames,
		seconds > 0 and s.frames / seconds or 0))
	add(("Frames: worst %s; over 33 ms: %d, over 50 ms: %d, over 100 ms: %d"):format(Ms(s.worst), s.over33, s.over50, s.over100))
	add(("CraftWise handlers and hooks together: %s (%.2f %% of the recording)"):format(Ms(s.cwTotal),
		seconds > 0 and s.cwTotal / (seconds * 10) or 0))

	if #s.spikes > 0 then
		add("")
		add(("Slowest frames (frame | CraftWise inside it | its slowest handler), over %d ms:"):format(Perf.SPIKE_MS))
		for _, sp in ipairs(s.spikes) do
			add(("  at %.1f s: %s | %s | %s"):format(sp.at, Ms(sp.ms), Ms(sp.cw),
				sp.top and ("%s (%s)"):format(sp.top, Ms(sp.topMs)) or "none"))
		end
	end

	local handlers, notifies, hooks, events = {}, {}, {}, {}
	for _, st in pairs(s.stats) do
		if st.kind == "event" then
			handlers[#handlers + 1] = st
			local e = events[st.name]
			if not e then
				e = { name = st.name, n = 0, total = 0, max = 0 }
				events[st.name] = e
			end
			e.n = e.n + st.n
			e.total = e.total + st.total
			if st.max > e.max then e.max = st.max end
		elseif st.kind == "notify" then
			notifies[#notifies + 1] = st
		else
			hooks[#hooks + 1] = st
		end
	end
	local function section(title, list, line)
		if #list == 0 then
			return
		end
		add("")
		add(title)
		Sorted(list, "total")
		for i = 1, math.min(Perf.TOP, #list) do
			add(line(list[i]))
		end
	end
	local evList = {}
	for _, e in pairs(events) do
		evList[#evList + 1] = e
	end
	section("Events, all CraftWise handlers together (total | count | longest single run):", evList, function(e)
		return ("  %s: %s | %dx | %s"):format(e.name, Ms(e.total), e.n, Ms(e.max))
	end)
	section("Handlers (event, registered at, total | count | longest):", handlers, function(h)
		return ("  %s %s: %s | %dx | %s"):format(h.name, h.label, Ms(h.total), h.n, Ms(h.max))
	end)
	section("Module callbacks (inside the handlers above):", notifies, function(h)
		return ("  %s %s: %s | %dx | %s"):format(h.name, h.label, Ms(h.total), h.n, Ms(h.max))
	end)
	section("Hooks and timers:", hooks, function(h)
		return ("  %s: %s | %dx | %s"):format(h.name, Ms(h.total), h.n, Ms(h.max))
	end)

	-- Item data loads CraftWise asked the client for (each answer is an event every addon handles).
	add("")
	add(("CraftWise asked the client to load %d items (%d more skipped: asked in the last %d s)"):format(s.sent, s.skipped,
		ns.ITEM_REQUEST_SECONDS or 0))
	local reqs = {}
	for _, r in pairs(s.requests) do
		reqs[#reqs + 1] = r
	end
	table.sort(reqs, function(a, b)
		if a.sent ~= b.sent then return a.sent > b.sent end
		return a.label < b.label
	end)
	for i = 1, math.min(Perf.TOP, #reqs) do
		add(("  %s: %d sent, %d skipped"):format(reqs[i].label, reqs[i].sent, reqs[i].skipped))
	end

	local rows = AddonRows(s.addons)
	if #rows > 0 then
		add("")
		add("Addons, ticks over 5 / 10 / 50 / 100 ms during the recording; recent average; peak since login:")
		local shown = 0
		for _, r in ipairs(rows) do
			if shown < Perf.TOP_ADDONS or r.name == ns.name then
				add(("  %s: %d / %d / %d / %d; %s; %s"):format(r.name, r.over5, r.over10, r.over50, r.over100, Ms(r.recent), Ms(r.peak)))
				shown = shown + 1
			end
		end
	end
	local ids = MetricIds()
	local top = TopLines(ids.recent, 5)
	if #top > 0 then
		add("")
		add("Top addons by recent average:")
		for _, l in ipairs(top) do add(l) end
	end
	top = TopLines(ids.peak, 5)
	if #top > 0 then
		add("")
		add("Top addons by peak since login:")
		for _, l in ipairs(top) do add(l) end
	end
	return lines
end

function Perf.Stop()
	local s = state
	if not s then
		return
	end
	local seconds = (Now() - s.t0) / 1000
	ns.SetRecorder(nil)
	ticker:Hide()
	state = nil
	report = Build(s, seconds)
	return report
end

function Perf.Toggle()
	if state then
		Perf.Stop()
	else
		Perf.Start()
	end
end

function Perf.Clear()
	report = nil
end

-- The report as one string, or nil.
function Perf.Text()
	return report and table.concat(report, "\n") or nil
end

-- What the Debug group shows: the state, or the report.
function Perf.Status()
	if state then
		return ("Recording... %.0f s. Open the bags and a vendor, then press Stop."):format((Now() - state.t0) / 1000)
	end
	return Perf.Text() or "Nothing recorded. Press Record, open the bags and a vendor, press Stop, then Copy report."
end

----------------------------------------------------------------------------------------------------
-- Copy box: the text sits selected in an edit box (the client has no clipboard API).
----------------------------------------------------------------------------------------------------

local popup

local function Popup()
	if popup then
		return popup
	end
	local Style = ns.Style
	local f = CreateFrame("Frame", "CraftWisePerfCopy", UIParent)
	f:SetSize(660, 440)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	Style.Fill(bg, Style.C.sheet)
	Style.Border(f, Style.C.ruleStrong)
	local title = Style.Text(f, "Small", "text2")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
	title:SetText("Performance report: Ctrl+C copies it, Esc closes")
	local scroll = CreateFrame("ScrollFrame", nil, f)
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(Style.Fonts.Small)
	box:SetTextColor(Style.C.text[1], Style.C.text[2], Style.C.text[3], 1)
	box:SetWidth(630)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	scroll:SetScrollChild(box)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, box:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
	end)
	f.box = box
	f:Hide()
	popup = f
	return f
end

function Perf.ShowCopy()
	local text = Perf.Text()
	if not text then
		ns.Print("nothing recorded yet")
		return false
	end
	local f = Popup()
	f.box:SetText(text)
	f:Show()
	f.box:SetFocus()
	f.box:HighlightText()
	return true
end
