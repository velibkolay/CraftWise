-- Settings page (#157; spec in #150 "Look up, Music, Settings", board "Settings"): the gear in the header.
-- A left list of groups, rows of label left and control right. It holds every option of the old settings
-- panel and the AH rule panel (both removed in #157 part 2), plus the new Look group and the Snapshot
-- group (was Records › Snapshot). The Background sliders (Look, Loot toast) write db.settings.alpha (#162).
-- Slash commands that change a setting open its group (ns.OpenSettings, Core.lua).
--
-- The groups are data (Set.Groups: rows of { kind, label, get, set, ... }); the drawing below turns each
-- kind into a control, so the docked layout (#161) can draw the same rows its own way. Kinds:
--   seg     segmented control: options = { { value, label, disabled } }, get() -> value, set(value)
--   check   checkbox: text, get() -> bool, set(bool)
--   checks  several checkboxes in one row: items = { { text, get, set } }
--   slider  min, max, step, get(), set(v), format(v) -> text
--   stepper − value +: get(), down(), up(), format(v)
--   buttons buttons = { { text, onClick, on() } }
--   text    text() -> string (and its colour), a line of information
--   grid    items() -> { { left, right, color } } in two columns (Snapshot)
-- A row may have sub (a caption under the label, string or function), disabled() and visible().
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local Set = {}
M.Settings = Set

Set.NAV_WIDTH = 170
Set.LABEL_WIDTH = 200
Set.ROW_HEIGHT = 38
Set.SCALE_MIN, Set.SCALE_MAX, Set.SCALE_STEP = 0.7, 1.3, 0.05

local function S()
	return ns.db.settings
end

local function Changed(...)
	for _, name in ipairs({ ... }) do
		ns.Notify(name)
	end
	M.Refresh()
end

----------------------------------------------------------------------------------------------------
-- Actions with more than one step
----------------------------------------------------------------------------------------------------

-- Look › Reset window positions: the main window, the farm tracker and the loot toast go back to their
-- default places.
function Set.ResetPositions()
	M.UI().pos = nil
	if M.ApplyLayout then
		M.ApplyLayout()
	end
	if ns.FarmFrame and ns.FarmFrame.ResetPosition then
		ns.FarmFrame.ResetPosition()
	end
	if ns.LootToast and ns.LootToast.ResetPosition then
		ns.LootToast.ResetPosition()
	end
end

function Set.SetScale(v)
	v = math.max(Set.SCALE_MIN, math.min(Set.SCALE_MAX, tonumber(v) or 1))
	v = math.floor(v * 100 + 0.5) / 100
	M.UI().scale = v
	if M.ApplyLayout then
		M.ApplyLayout()
	end
end

-- Tooltips: Always / Only with Shift / Off over tooltip.enabled and tooltip.mode.
function Set.TooltipMode()
	local t = ns.db.tooltip
	if not t.enabled then
		return "off"
	end
	return t.mode == "shift" and "shift" or "always"
end

function Set.SetTooltipMode(v)
	local t = ns.db.tooltip
	t.enabled = v ~= "off"
	if v ~= "off" then
		t.mode = v
	end
end

-- Loot toast: Off / Lines / With value over lootToast.enabled and lootToast.value.
function Set.ToastMode()
	local t = ns.db.lootToast
	if not ns.LootToast.Enabled() then
		return "off"
	end
	return t.value ~= false and "value" or "lines"
end

function Set.SetToastMode(v)
	local t = ns.db.lootToast
	t.enabled = v ~= "off"
	if v ~= "off" then
		t.value = v == "value"
	else
		ns.LootToast.Clear()
		ns.LootToast.Render(GetTime and GetTime() or 0)
	end
end

-- AH rule (issue #12): Defaults and the - / + steps of the old AH rule panel.
local DEFAULT_PERCENT, DEFAULT_COPPER, PERCENT_STEP = 20, 10, 5
Set.AH_RULE_DEFAULTS = { percent = DEFAULT_PERCENT, copper = DEFAULT_COPPER }
Set.COPPER_STEPS = { 0, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000 }

-- The next copper step up (dir 1) or down (dir -1) from current.
function Set.StepCopper(current, dir)
	current = current or 0
	local steps = Set.COPPER_STEPS
	if dir > 0 then
		for _, v in ipairs(steps) do
			if v > current then
				return v
			end
		end
		return steps[#steps]
	end
	for i = #steps, 1, -1 do
		if steps[i] < current then
			return steps[i]
		end
	end
	return 0
end

-- "Vendor pays 1s; the AH must pay at least 1s 20c after the 5% cut."
function Set.AHRuleExample()
	local p, c = S().ahMinPercent or DEFAULT_PERCENT, S().ahMinCopper or 0
	local need = math.max(100 * (1 + p / 100), 100 + c)
	return (L["Example: a vendor pays %s; the AH must pay at least %s after the 5%% cut."]):format(
		ns.FormatMoney(100, true), ns.FormatMoney(math.ceil(need), true))
end

-- Snapshot: save now and keep the outcome for the line under the buttons.
function Set.SaveSnapshot()
	local ok, snap = pcall(ns.Snapshot.Save)
	if ok and snap then
		Set.snapshotNote = { L["Snapshot saved. Reload the UI or log out to write it to disk."], "text2" }
	else
		Set.snapshotNote = { L["Snapshot failed:"] .. " " .. tostring(ok and L["character not loaded yet"] or snap), "danger" }
	end
	M.Refresh()
	return ok and snap ~= nil
end

function Set.SnapshotLine(now)
	local Sn = ns.Snapshot
	local key = Sn.Key()
	local snap = key and ns.db.snapshots and ns.db.snapshots[key]
	if snap and snap.t then
		return (L["Last saved %s (%s ago) · %s"]):format(date("%Y-%m-%d %H:%M", snap.t), M.AgeText((now or time()) - snap.t), key)
	end
	return key and L["Not saved yet for this character."] or L["Character not loaded yet."]
end

function Set.SnapshotItems()
	local Sn = ns.Snapshot
	local key = Sn.Key()
	local snap = key and ns.db.snapshots and ns.db.snapshots[key]
	local out = {}
	for _, section in ipairs(Sn.SECTIONS) do
		local name = section[1]
		local right, color
		if not snap then
			right, color = M.DASH, "text3"
		elseif snap.errors and snap.errors[name] then
			right, color = L["error"], "danger"
		elseif snap.skipped and snap.skipped[name] then
			right, color = L["skipped"], "text3"
		elseif snap[name] ~= nil then
			right, color = L["saved"], "text"
		else
			right, color = L["not in it"], "text3"
		end
		out[#out + 1] = { left = name, right = right, color = color,
			tip = snap and ((snap.errors and snap.errors[name]) or (snap.skipped and snap.skipped[name])) or nil }
	end
	return out
end

----------------------------------------------------------------------------------------------------
-- The groups (spec table "Settings")
----------------------------------------------------------------------------------------------------

local function Pct(v)
	return ("%d %%"):format(math.floor((v or 0) * 100 + 0.5))
end

-- Look › Background per window and Loot toast › Background (#162): db.settings.alpha[window] from
-- ALPHA_MIN to 1 in steps of 5 %, applied while dragging (Style.ApplyWindowAlpha).
Set.ALPHA_MIN, Set.ALPHA_STEP = 0.2, 0.05

function Set.SetAlpha(window, v)
	v = math.max(Set.ALPHA_MIN, math.min(1, tonumber(v) or Style.WINDOW_ALPHA[window]))
	Style.SetWindowAlpha(window, v)
	if window == "toast" then
		-- The strips are drawn by the toast: redraw the ones on screen, or show the test lines when none are.
		local T = ns.LootToast
		if #T.Lines() == 0 and T.Enabled() then
			T.Test()
		end
		T.Render(GetTime and GetTime() or 0)
	end
end

local function AlphaRow(key, label, window)
	return { key = key, kind = "slider", label = label, min = Set.ALPHA_MIN, max = 1, step = Set.ALPHA_STEP,
		get = function() return Style.WindowAlpha(window) end,
		set = function(v) Set.SetAlpha(window, v) end, format = Pct }
end

local function Minutes(v)
	return ("%d min"):format(v or 0)
end

local function LayoutOptions()
	local out = {}
	for _, key in ipairs(M.layoutOrder) do
		out[#out + 1] = { value = key, label = M.layouts[key].label or key }
	end
	return out
end

local VIEW_LABELS = { profit = "Craft", learn = "Learn", level = "Level up", upgrades = "Upgrades" }

local function Groups()
	local Mk, F, FF, T = ns.Market, ns.Farm, ns.FarmFrame, ns.LootToast
	local groups = {}

	groups[#groups + 1] = { key = "look", label = L["Look"], rows = {
		{ key = "layout", kind = "seg", label = L["Layout"], options = LayoutOptions,
			get = function() return M.LayoutKey() end, set = function(v) M.SetLayout(v) end },
		{ key = "scale", kind = "slider", label = L["Scale"], min = Set.SCALE_MIN, max = Set.SCALE_MAX, step = Set.SCALE_STEP,
			onRelease = true, get = function() return tonumber(M.UI().scale) or 1 end, set = Set.SetScale, format = Pct },
		AlphaRow("bgMain", L["Background · Main window"], "main"),
		AlphaRow("bgFarm", L["Background · Farm tracker"], "farm"),
		AlphaRow("bgToast", L["Background · Loot toast"], "toast"),
		{ key = "fade", kind = "check", label = L["Farm tracker away from the mouse"], text = L["Fade to 40 % until hovered"],
			get = function() return FF.FadeEnabled() end, set = function(v) FF.SetFade(v) end },
		{ key = "windows", kind = "checks", label = L["Windows"], items = {
			{ key = "lock", text = L["Lock position"], get = function() return M.UI().locked and true or false end,
				set = function(v) M.UI().locked = v and true or false end },
			{ key = "escape", text = L["Close with Escape"], get = function() return M.UI().escape and true or false end,
				set = function(v)
					M.UI().escape = v and true or false
					M.ApplyEscape()
				end },
		} },
		{ key = "minimap", kind = "check", label = L["Minimap button"], text = L["Show"],
			get = function() return not ns.db.minimap.hide end,
			set = function(v)
				if (not ns.db.minimap.hide) ~= v then
					ns.ToggleMinimapButton()
				end
			end },
		{ key = "reset", kind = "buttons", label = "", buttons = {
			{ key = "reset", text = L["Reset window positions"], onClick = Set.ResetPositions },
		} },
	} }

	local priceRows = {
		{ key = "basis", kind = "seg", label = L["Profit prices"],
			options = { { value = "typical", label = L["Typical"] }, { value = "current", label = L["Current lowest"] } },
			get = function() return (ns.PriceSettings()) end,
			set = function(v)
				S().priceBasis = v
				Changed("PRICES_CHANGED")
			end },
		{ key = "house", kind = "seg", label = L["Auction house for profit"],
			options = function()
				local out = {}
				for _, choice in ipairs(Mk.CHOICES) do
					local key, label = Mk.HouseFor(choice)
					local has = choice == "faction" or (key and Mk.HasData(key))
					out[#out + 1] = { value = choice, label = label or L["Own faction"], disabled = not has }
				end
				return out
			end,
			sub = function()
				local missing = {}
				for _, choice in ipairs(Mk.CHOICES) do
					local key, label = Mk.HouseFor(choice)
					if not (key and Mk.HasData(key)) then
						missing[#missing + 1] = label or L["Own faction"]
					end
				end
				return #missing > 0 and (L["No data yet:"] .. " " .. table.concat(missing, ", ")) or nil
			end,
			get = function() return select(2, ns.PriceSettings()) end,
			set = function(v)
				local key = Mk.HouseFor(v)
				if v ~= "faction" and not (key and Mk.HasData(key)) then
					return false -- nothing recorded at that house yet
				end
				S().priceHouse = v
				Changed("PRICES_CHANGED")
			end },
	}
	for i, view in ipairs(ns.COST_BASIS_VIEWS) do
		priceRows[#priceRows + 1] = { key = "cost_" .. view, kind = "seg",
			label = L["Reagent cost"] .. " · " .. L[VIEW_LABELS[view] or view],
			sub = i == 1 and L["Paid cost: what you paid for the units you hold (Sell › Ledger); else AH."] or nil,
			options = { { value = "ah", label = L["AH"] }, { value = "paid", label = L["Paid cost"] } },
			get = function() return ns.CostBasis(view) end,
			set = function(v)
				S().costBasis[view] = v
				Changed("PRICES_CHANGED")
			end }
	end
	groups[#groups + 1] = { key = "prices", label = L["Prices"], rows = priceRows }

	local tipRows = {
		{ key = "tooltip", kind = "seg", label = L["Show CraftWise in item tooltips"],
			options = { { value = "always", label = L["Always"] }, { value = "shift", label = L["Only with Shift"] },
				{ value = "off", label = L["Off"] } },
			get = Set.TooltipMode, set = Set.SetTooltipMode },
	}
	for i, line in ipairs(ns.TOOLTIP_LINES) do
		tipRows[#tipRows + 1] = { key = "line_" .. line.key, kind = "check", label = i == 1 and L["Lines"] or "",
			text = L[line.label],
			disabled = function() return not ns.db.tooltip.enabled end,
			get = function() return ns.db.tooltip.lines[line.key] and true or false end,
			set = function(v) ns.db.tooltip.lines[line.key] = v and true or false end }
	end
	groups[#groups + 1] = { key = "tooltips", label = L["Tooltips"], rows = tipRows }

	groups[#groups + 1] = { key = "bags", label = L["Bags and loot"], rows = {
		{ key = "menuClick", kind = "seg", label = L["Keep / Junk menu"],
			options = { { value = "middle", label = L["Middle click"] }, { value = "altright", label = L["Alt + right"] },
				{ value = "off", label = L["Off"] } },
			get = function() return S().menuClick or "middle" end,
			set = function(v) S().menuClick = v end },
		{ key = "slotMarks", kind = "check", label = L["Bag slot marks"], text = L["Sell on AH and junk corners"],
			get = function() return ns.SlotMarksOn() end,
			set = function(v)
				S().slotMarks = v and true or false
				ns.Notify("JUNK_CHANGED")
			end },
		{ key = "showDismissed", kind = "check", label = L["Upgrades"], text = L["Show dismissed upgrades"],
			get = function() return S().showDismissed and true or false end,
			set = function(v)
				S().showDismissed = v and true or false
				ns.Notify("UPGRADES_CHANGED")
			end },
		{ key = "fastLoot", kind = "check", label = L["Fast auto-loot"], text = L["On"],
			sub = function()
				local other = ns.Loot.Conflict()
				return other and (other .. " " .. L["is loaded, so CraftWise does not loot."])
					or L["Records recipe sources, then loots. Hold Shift to loot by hand."]
			end,
			disabled = function() return ns.Loot.Conflict() ~= nil end,
			get = function() return ns.Loot.Enabled() end, set = function(v) ns.Loot.SetEnabled(v) end },
	} }

	groups[#groups + 1] = { key = "toast", label = L["Loot toast"], rows = {
		{ key = "mode", kind = "seg", label = L["Loot toast"],
			options = { { value = "off", label = L["Off"] }, { value = "lines", label = L["Lines"] }, { value = "value", label = L["With value"] } },
			get = Set.ToastMode, set = Set.SetToastMode },
		{ key = "duration", kind = "slider", label = L["Lines stay"], min = T.MIN_DURATION, max = T.MAX_DURATION, step = 1,
			get = function() return T.Duration() end,
			set = function(v) ns.db.lootToast.duration = math.floor(v + 0.5) end,
			format = function(v) return ("%d s"):format(v) end },
		AlphaRow("background", L["Background"], "toast"),
		{ key = "position", kind = "buttons", label = L["Position"], buttons = {
			{ key = "move", text = function() return ns.db.lootToast.locked == false and L["Lock"] or L["Move"] end,
				on = function() return ns.db.lootToast.locked == false end,
				onClick = function() T.Slash(ns.db.lootToast.locked == false and "lock" or "unlock") end },
			{ key = "test", text = L["Test"], onClick = function() T.Slash("test") end },
			{ key = "reset", text = L["Reset position"], onClick = function() T.ResetPosition() end },
		} },
	} }

	groups[#groups + 1] = { key = "loops", label = L["Vendor loops"], rows = {
		{ key = "on", kind = "check", label = L["Loop alert"], text = L["On"],
			sub = L["After prices change, one toast for vendor profits and loops that are new or clearly better. Click opens Make › Craft with Vendor check."],
			get = function() return ns.Loops.Enabled() end,
			set = function(v) S().loopAlert = v and true or false end },
		{ key = "min", kind = "stepper", label = L["Smallest profit per craft"],
			sub = L["Finds below this are not announced; 0 announces anything above 0."],
			disabled = function() return not ns.Loops.Enabled() end,
			get = function() return ns.Loops.MinProfit() end,
			down = function()
				S().loopAlertMin = Set.StepCopper(S().loopAlertMin, -1)
				Changed()
			end,
			up = function()
				S().loopAlertMin = Set.StepCopper(S().loopAlertMin, 1)
				Changed()
			end,
			format = function(v) return v > 0 and ns.FormatCoins(v) or "0" end },
	} }

	groups[#groups + 1] = { key = "farm", label = L["Farm tracker"], rows = {
		{ key = "on", kind = "check", label = L["Farm tracker"], text = L["On"],
			get = function() return F.Enabled() end, set = function(v) F.Slash(v and "on" or "off") end },
		{ key = "autoStart", kind = "check", label = L["Start on first loot"], text = L["On"],
			disabled = function() return not F.Enabled() end,
			get = function() return F.AutoStart() end, set = function(v) F.Slash(v and "autostart on" or "autostart off") end },
		{ key = "idle", kind = "slider", label = L["Pause when idle"], min = 0, max = F.MAX_IDLE, step = 1,
			get = function() return F.IdleMinutes() end,
			set = function(v) ns.db.farm.idleMinutes = math.max(0, math.min(F.MAX_IDLE, math.floor(v + 0.5))) end,
			format = function(v) return v > 0 and Minutes(v) or L["never"] end },
		{ key = "lock", kind = "check", label = L["Lock"], text = L["Lock position"],
			get = function() return ns.db.farm.locked and true or false end,
			set = function(v) F.Slash(v and "lock" or "unlock") end },
		{ key = "mini", kind = "check", label = L["Mini mode"], text = L["Show as a strip"],
			get = function() return FF.IsMini() end, set = function(v) FF.SetMini(v) end },
		{ key = "scale", kind = "slider", label = L["Scale"], min = F.MIN_SCALE, max = F.MAX_SCALE, step = 0.1,
			get = function() return tonumber(ns.db.farm.scale) or 1 end,
			set = function(v)
				ns.db.farm.scale = math.floor(math.max(F.MIN_SCALE, math.min(F.MAX_SCALE, v)) * 10 + 0.5) / 10
				FF.ApplyScale()
			end,
			format = Pct },
	} }

	groups[#groups + 1] = { key = "fishing", label = L["Fishing"], rows = {
		{ key = "gap", kind = "slider", label = L["Session gap"], min = 1, max = 60, step = 1,
			sub = L["Catches closer than this are one session (per hour)."],
			get = function() return ns.Fishing.SessionGap() end,
			set = function(v) S().fishingSessionGap = math.max(1, math.min(60, math.floor(v + 0.5))) end,
			format = Minutes },
		{ key = "ownMin", kind = "stepper", label = L["Own catches count from"],
			sub = L["Below this count a zone shows the local reference."],
			get = function() return ns.FishingZones.OwnMin() end,
			down = function()
				local cur = ns.FishingZones.OwnMin()
				S().fishingOwnMin = math.max(1, cur - (cur > 10 and 10 or 1))
				Changed()
			end,
			up = function()
				local cur = ns.FishingZones.OwnMin()
				S().fishingOwnMin = math.min(1000, cur + (cur >= 10 and 10 or 1))
				Changed()
			end,
			format = function(v) return tostring(v) end },
	} }

	groups[#groups + 1] = { key = "ahrule", label = L["AH rule"], rows = {
		{ key = "text", kind = "text", label = "", text = function() return L["Sell › Bags advises the AH only when it pays more than a vendor by both:"] end },
		{ key = "percent", kind = "stepper", label = L["At least this % more"],
			get = function() return S().ahMinPercent or DEFAULT_PERCENT end,
			down = function()
				S().ahMinPercent = math.max(0, (S().ahMinPercent or DEFAULT_PERCENT) - PERCENT_STEP)
				Changed("BAGS_CHANGED")
			end,
			up = function()
				S().ahMinPercent = math.min(1000, (S().ahMinPercent or DEFAULT_PERCENT) + PERCENT_STEP)
				Changed("BAGS_CHANGED")
			end,
			format = function(v) return ("+%d %%"):format(v) end },
		{ key = "copper", kind = "stepper", label = L["And at least this much more"],
			get = function() return S().ahMinCopper or 0 end,
			down = function()
				S().ahMinCopper = Set.StepCopper(S().ahMinCopper, -1)
				Changed("BAGS_CHANGED")
			end,
			up = function()
				S().ahMinCopper = Set.StepCopper(S().ahMinCopper, 1)
				Changed("BAGS_CHANGED")
			end,
			format = function(v) return v > 0 and ns.FormatCoins(v) or "0" end },
		{ key = "example", kind = "text", label = "", text = function() return Set.AHRuleExample() end },
		{ key = "defaults", kind = "buttons", label = "", buttons = {
			{ key = "defaults", text = L["Defaults"], onClick = function()
				S().ahMinPercent, S().ahMinCopper = DEFAULT_PERCENT, DEFAULT_COPPER
				Changed("BAGS_CHANGED")
			end },
		} },
	} }

	groups[#groups + 1] = { key = "snapshot", label = L["Snapshot"], rows = {
		{ key = "buttons", kind = "buttons", label = L["Character snapshot"], buttons = {
			{ key = "save", text = L["Save snapshot"], onClick = Set.SaveSnapshot,
				tip = L["Writes the character snapshot into CraftWiseDB. Also done on every logout and reload."] },
			{ key = "reload", text = L["Reload UI"], onClick = function()
				if C_UI and C_UI.Reload then
					C_UI.Reload()
				end
			end, tip = L["Reloads the interface: the client writes the saved variables (and the snapshot) to disk."] },
		} },
		{ key = "last", kind = "text", label = L["Last saved"], text = function()
			local note = Set.snapshotNote
			if note then
				return Set.SnapshotLine() .. "\n" .. note[1], note[2]
			end
			return Set.SnapshotLine()
		end },
		{ key = "holds", kind = "grid", label = L["What it holds"], items = Set.SnapshotItems },
	} }
	return groups
end

Set.Groups = Groups

function Set.Group(key)
	for _, g in ipairs(Groups()) do
		if g.key == key then
			return g
		end
	end
end

function Set.Current()
	local key = M.UI().settingsGroup
	return Set.Group(key) and key or "look"
end

function Set.SelectGroup(key)
	if Set.Group(key) then
		M.UI().settingsGroup = key
		M.Refresh()
	end
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

local function Value(v)
	if type(v) == "function" then
		return v()
	end
	return v
end

local function Paint(fs, color)
	local c = Style.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], 1)
end

-- Builds the control of a row once; row.update() puts the current value on it.
local Controls = {}

function Controls.seg(holder, def)
	-- Built again when the number of options changes (a docked layout registered by #161, say).
	local function Make(opts)
		local labels = {}
		for i, o in ipairs(opts) do
			labels[i] = o.label
		end
		if holder.control then
			holder.control:Hide()
		end
		local seg = Style.Segmented(holder, labels, function(index)
			local o = Value(def.options)[index] -- as it is now (a house may have data since)
			if o and not o.disabled then
				def.set(o.value)
			end
			M.Refresh()
		end)
		seg:SetPoint("LEFT", holder, "LEFT", 0, 0)
		holder.control, holder.opts = seg, opts
		return seg
	end
	Make(Value(def.options))
	return function()
		local now = Value(def.options)
		local seg = holder.control
		if #now ~= #seg.buttons then
			seg = Make(now)
		end
		holder.opts = now
		for i, o in ipairs(now) do
			local b = seg.buttons[i]
			b:SetLabel(o.label)
			b:SetAlpha(o.disabled and 0.4 or 1)
		end
		local cur = def.get()
		local index
		for i, o in ipairs(now) do
			if o.value == cur then
				index = i
			end
		end
		seg:SetSelected(index)
	end
end

function Controls.check(holder, def)
	local box = Style.Checkbox(holder, def.text or "", false, function(v)
		def.set(v)
		M.Refresh()
	end)
	box:SetPoint("LEFT", holder, "LEFT", 0, 0)
	holder.control = box
	return function()
		box:SetChecked(def.get())
	end
end

function Controls.checks(holder, def)
	local boxes, x = {}, 0
	for i, item in ipairs(def.items) do
		local box = Style.Checkbox(holder, item.text, false, function(v)
			item.set(v)
			M.Refresh()
		end)
		box:SetPoint("LEFT", holder, "LEFT", x, 0)
		x = x + (box:GetWidth() or 100) + 18
		boxes[i] = box
	end
	holder.control, holder.boxes = boxes[1], boxes
	return function()
		for i, item in ipairs(def.items) do
			boxes[i]:SetChecked(item.get())
		end
	end
end

function Controls.slider(holder, def)
	local s = Style.Slider(holder, 180, def.min, def.max, def.step, function(v)
		if def.onRelease then
			-- Look › Scale resizes the window under the mouse: applied when the drag ends.
			holder.pending = v
			holder.value:SetText(def.format and def.format(v) or tostring(v))
			return
		end
		def.set(v)
		holder.value:SetText(def.format and def.format(def.get()) or tostring(def.get()))
	end)
	s:SetPoint("LEFT", holder, "LEFT", 0, 0)
	if def.onRelease then
		s:SetScript("OnMouseUp", function()
			if holder.pending then
				local v = holder.pending
				holder.pending = nil
				def.set(v)
				M.Refresh()
			end
		end)
	end
	holder.value = Style.Text(holder, "Figure", "text")
	holder.value:SetPoint("LEFT", s, "RIGHT", 10, 0)
	holder.control = s
	return function()
		s:SetValueQuietly(def.get())
		holder.value:SetText(def.format and def.format(def.get()) or tostring(def.get()))
	end
end

function Controls.stepper(holder, def)
	local down = Style.LineButton(holder, "−", 24)
	down:SetPoint("LEFT", holder, "LEFT", 0, 0)
	holder.value = Style.Text(holder, "Figure", "text")
	holder.value:SetPoint("LEFT", down, "RIGHT", 8, 0)
	holder.value:SetWidth(72)
	holder.value:SetJustifyH("CENTER")
	local up = Style.LineButton(holder, "+", 24)
	up:SetPoint("LEFT", holder.value, "RIGHT", 8, 0)
	down:SetScript("OnClick", function()
		def.down()
		M.Refresh()
	end)
	up:SetScript("OnClick", function()
		def.up()
		M.Refresh()
	end)
	holder.control, holder.down, holder.up = holder.value, down, up
	return function()
		holder.value:SetText(def.format and def.format(def.get()) or tostring(def.get()))
	end
end

function Controls.buttons(holder, def)
	local list, x = {}, 0
	for i, bd in ipairs(def.buttons) do
		local b = Style.LineButton(holder, Value(bd.text), nil, 26)
		b:SetPoint("LEFT", holder, "LEFT", x, 0)
		b:SetScript("OnClick", function()
			bd.onClick()
			M.Refresh()
		end)
		if bd.tip then
			b:HookScript("OnEnter", function(self)
				Style.ShowTip(self, Value(bd.text), bd.tip)
			end)
			b:HookScript("OnLeave", function(self)
				Style.HideTip(self)
			end)
		end
		list[i] = b
		x = x + (b.cwWidth or 100) + 8
	end
	holder.control, holder.buttons = list[1], list
	return function()
		local bx = 0
		for i, bd in ipairs(def.buttons) do
			local b = list[i]
			b:SetLabel(Value(bd.text))
			b:SetOn(bd.on and bd.on() or false)
			b:ClearAllPoints()
			b:SetPoint("LEFT", holder, "LEFT", bx, 0)
			bx = bx + (b.cwWidth or 100) + 8
		end
	end
end

function Controls.text(holder, def)
	holder.text = Style.Text(holder, "Small", "text2")
	holder.text:SetPoint("LEFT", holder, "LEFT", 0, 0)
	holder.text:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
	holder.text:SetJustifyH("LEFT")
	holder.text:SetWordWrap(true)
	holder.control = holder.text
	return function()
		local text, color = def.text()
		holder.text:SetText(text or "")
		Paint(holder.text, color or "text2")
	end
end

Set.GRID_ROW = 18

function Controls.grid(holder, def)
	holder.cells = {}
	holder.control = holder
	return function()
		local items = def.items()
		local half = math.ceil(#items / 2)
		local colW = 220
		for i, it in ipairs(items) do
			local c = holder.cells[i]
			if not c then
				c = CreateFrame("Frame", nil, holder)
				c:SetSize(colW - 12, Set.GRID_ROW)
				c.left = Style.Text(c, "Small", "text2")
				c.left:SetPoint("LEFT", c, "LEFT", 0, 0)
				c.right = Style.Text(c, "Small", "text")
				c.right:SetPoint("RIGHT", c, "RIGHT", 0, 0)
				c.right:SetJustifyH("RIGHT")
				c:EnableMouse(true)
				c:SetScript("OnEnter", function(self)
					if self.tip then
						Style.ShowTip(self, self.left:GetText(), self.tip)
					end
				end)
				c:SetScript("OnLeave", function(self)
					Style.HideTip(self)
				end)
				holder.cells[i] = c
			end
			local col, row = i > half and 1 or 0, (i - 1) % half
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", holder, "TOPLEFT", col * colW, -row * Set.GRID_ROW)
			c.left:SetText(it.left)
			c.right:SetText(it.right)
			Paint(c.right, it.color)
			c.tip = it.tip
			c:Show()
		end
		for i = #items + 1, #holder.cells do
			holder.cells[i]:Hide()
		end
		holder:SetHeight(math.max(half, 1) * Set.GRID_ROW)
		holder.rows = half
	end
end

local function RowHeight(def, holder)
	if def.kind == "grid" then
		return math.max((holder.rows or 9) * Set.GRID_ROW + 12, Set.ROW_HEIGHT)
	end
	if def.kind == "text" then
		local text = def.text()
		local lines = 1
		for _ in tostring(text or ""):gmatch("\n") do
			lines = lines + 1
		end
		return math.max(Set.ROW_HEIGHT, 14 * lines + 16)
	end
	return def.sub and Set.ROW_HEIGHT + 8 or Set.ROW_HEIGHT
end

-- One row: label (with its sub-line) left, the control right, a hairline under it.
local function BuildRow(parent, def)
	local r = CreateFrame("Frame", nil, parent)
	r.def = def
	r.hair = Style.Rule(r, "H", C.rule)
	r.hair:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.hair:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.label = Style.Text(r, "Body", "text")
	r.label:SetJustifyH("LEFT")
	r.label:SetWidth(Set.LABEL_WIDTH)
	r.label:SetText(def.label or "")
	r.sub = Style.Text(r, "Caption", "text3")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(true)
	r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
	r.holder = CreateFrame("Frame", nil, r)
	r.holder:SetPoint("TOPLEFT", r, "TOPLEFT", Set.LABEL_WIDTH + 16, 0)
	r.holder:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.update = Controls[def.kind](r.holder, def)
	return r
end

local function BuildGroup(body, group)
	local g = CreateFrame("Frame", nil, body.content)
	g:SetAllPoints(body.content)
	g.title = Style.Text(g, "Section", "text")
	g.title:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
	g.title:SetText(group.label)
	g.rule = g:CreateTexture(nil, "ARTWORK")
	Style.Fill(g.rule, C.text)
	g.rule:SetHeight(2)
	g.rule:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -22)
	g.rule:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, -22)
	g.rows = {}
	for i, def in ipairs(group.rows) do
		g.rows[i] = BuildRow(g, def)
		g.rows[def.key] = g.rows[i]
	end
	return g
end

local function UpdateGroup(g)
	local y = 26
	for _, r in ipairs(g.rows) do
		local def = r.def
		local visible = not def.visible or def.visible()
		r:SetShown(visible)
		if visible then
			r.update()
			local sub = Value(def.sub)
			r.sub:SetText(sub or "")
			r.sub:SetShown(sub ~= nil and sub ~= "")
			r.sub:SetWidth(Set.LABEL_WIDTH)
			local disabled = def.disabled and def.disabled() or false
			r.holder:SetAlpha(disabled and 0.4 or 1)
			r.disabled = disabled
			local h = RowHeight(def, r.holder)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y)
			r:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, -y)
			r:SetHeight(h)
			r.label:ClearAllPoints()
			if sub and sub ~= "" then
				r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -8)
			else
				r.label:SetPoint("LEFT", r, "LEFT", 0, 0)
			end
			if def.kind == "grid" then
				r.holder:ClearAllPoints()
				r.holder:SetPoint("TOPLEFT", r, "TOPLEFT", Set.LABEL_WIDTH + 16, -10)
				r.holder:SetPoint("RIGHT", r, "RIGHT", 0, 0)
				r.label:ClearAllPoints()
				r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -10)
			end
			y = y + h
		end
	end
end

local function Build(body)
	-- Board "Settings": a rule under the header, the group list 170 wide on the left.
	local top = -16 -- the page starts 16 below the header (no sub bar); the board's list starts at it
	body.rule = Style.Rule(body, "H", C.rule)
	body.rule:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
	body.rule:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -top)
	local nav = CreateFrame("Frame", nil, body)
	body.nav = nav
	nav:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
	nav:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	nav:SetWidth(Set.NAV_WIDTH)
	nav.bg = nav:CreateTexture(nil, "BACKGROUND")
	nav.bg:SetAllPoints(nav)
	Style.Fill(nav.bg, C.ground) -- spec: C.ground is the settings nav
	nav.rule = Style.Rule(body, "V", C.rule)
	nav.rule:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	nav.rule:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0)
	nav.buttons = {}
	nav.nokta = Style.Nokta(nav)
	for i, group in ipairs(Groups()) do
		local b = CreateFrame("Button", nil, nav)
		b.key = group.key
		b:SetHeight(30)
		b:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -10 - (i - 1) * 30)
		b:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, -10 - (i - 1) * 30)
		b.label = Style.Text(b, "BodyBold", "text3")
		b.label:SetPoint("LEFT", b, "LEFT", 16, 0)
		b.label:SetText(group.label)
		b:SetScript("OnClick", function(self)
			Set.SelectGroup(self.key)
		end)
		nav.buttons[i] = b
		nav.buttons[group.key] = b
	end
	body.content = CreateFrame("Frame", nil, body)
	body.content:SetPoint("TOPLEFT", body, "TOPLEFT", Set.NAV_WIDTH + 24, -top - 16)
	body.content:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 16)
	body.groups = {}
	Set.body = body
end

----------------------------------------------------------------------------------------------------
-- Provisional (#161 Q2): the docked Settings page. One scrolling list of every group: the group's title
-- as a group header (2 unit C.text rule, as on Bags), each row's label over its control, segmented
-- controls across the row. The same group data and controls as the window (Controls above).
----------------------------------------------------------------------------------------------------

Set.DOCKED_GROUP = 40 -- a group header row
Set.DOCKED_LABEL = 16 -- the label line above a control
Set.DOCKED_CHECK_GAP = 18

local function BuildDockedRow(parent, def)
	local r = CreateFrame("Frame", nil, parent)
	r.def = def
	r.hair = Style.Rule(r, "H", C.rule)
	r.hair:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.hair:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.label = Style.Text(r, "Body", "text")
	r.label:SetJustifyH("LEFT")
	r.label:SetText(def.label or "")
	r.sub = Style.Text(r, "Caption", "text3")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(true)
	r.holder = CreateFrame("Frame", nil, r)
	r.update = Controls[def.kind](r.holder, def)
	return r
end

local function BuildDocked(body)
	local d = { groups = {} }
	body.dock = d
	d.scroll = M.Docked.Scroll(body)
	for i, group in ipairs(Groups()) do
		local g = { key = group.key, rows = {} }
		g.head = CreateFrame("Frame", nil, d.scroll.child)
		g.head.title = Style.Text(g.head, "Section", "text")
		g.head.title:SetPoint("BOTTOMLEFT", g.head, "BOTTOMLEFT", 0, 8)
		g.head.title:SetText(group.label)
		g.head.rule = g.head:CreateTexture(nil, "ARTWORK")
		Style.Fill(g.head.rule, C.text)
		g.head.rule:SetHeight(2)
		g.head.rule:SetPoint("BOTTOMLEFT", g.head, "BOTTOMLEFT", 0, 0)
		g.head.rule:SetPoint("BOTTOMRIGHT", g.head, "BOTTOMRIGHT", 0, 0)
		for j, def in ipairs(group.rows) do
			g.rows[j] = BuildDockedRow(d.scroll.child, def)
			g.rows[def.key] = g.rows[j]
		end
		d.groups[i] = g
		d.groups[group.key] = g
	end
	return d
end

-- Height of a docked control (under its label) and its layout across `width`.
local function DockedControl(r, width)
	local def, holder = r.def, r.holder
	local kind = def.kind
	if kind == "seg" then
		holder.control:Stretch(width) -- wide controls take the row
		return 24
	elseif kind == "check" then
		return 18
	elseif kind == "checks" then
		-- side by side while they fit, else one per line
		local x, y = 0, 0
		for _, box in ipairs(holder.boxes or {}) do
			local w = box:GetWidth() or 100
			if x > 0 and x + w > width then
				x, y = 0, y + 22
			end
			box:ClearAllPoints()
			box:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y)
			x = x + w + Set.DOCKED_CHECK_GAP
		end
		return y + 18
	elseif kind == "slider" then
		return 18
	elseif kind == "stepper" then
		return 24
	elseif kind == "buttons" then
		return 26
	elseif kind == "text" then
		local fs = holder.text
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		fs:SetWidth(width)
		local h = fs:GetStringHeight()
		if type(h) ~= "number" or h <= 0 then
			local lines = 1
			for _ in tostring(fs:GetText() or ""):gmatch("\n") do
				lines = lines + 1
			end
			h = lines * 14
		end
		return h
	elseif kind == "grid" then
		-- one column across the row
		local n = 0
		for _, c in ipairs(holder.cells or {}) do
			if c:IsShown() then
				c:ClearAllPoints()
				c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -n * Set.GRID_ROW)
				c:SetWidth(width)
				n = n + 1
			end
		end
		holder.rows = n
		return math.max(n, 1) * Set.GRID_ROW
	end
	return 24
end

local function DockedRefresh(body, ctx)
	local m = ctx.metrics
	for _, part in ipairs({ body.rule, body.nav, body.nav.rule, body.content }) do
		part:Hide()
	end
	local d = body.dock or BuildDocked(body)
	local scroll = d.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	scroll.child:SetWidth(m.width)
	scroll:Show()
	local pad, width = m.pad, m.width - 2 * m.pad
	local y = 0
	for _, g in ipairs(d.groups) do
		g.head:ClearAllPoints()
		g.head:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", pad, -y)
		g.head:SetSize(width, Set.DOCKED_GROUP)
		y = y + Set.DOCKED_GROUP
		for _, r in ipairs(g.rows) do
			local def = r.def
			local visible = not def.visible or def.visible()
			r:SetShown(visible)
			if visible then
				r.update()
				local disabled = def.disabled and def.disabled() or false
				r.holder:SetAlpha(disabled and 0.4 or 1)
				r.disabled = disabled
				local h = 10
				local hasLabel = (def.label or "") ~= ""
				r.label:ClearAllPoints()
				r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -h)
				r.label:SetWidth(width)
				r.label:SetShown(hasLabel)
				if hasLabel then
					h = h + Set.DOCKED_LABEL
				end
				local sub = Value(def.sub)
				local hasSub = sub ~= nil and sub ~= ""
				r.sub:SetText(sub or "")
				r.sub:SetShown(hasSub)
				r.sub:SetWidth(width)
				if hasSub then
					r.sub:ClearAllPoints()
					r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -h)
					h = h + 14
				end
				h = h + 4
				local ch = DockedControl(r, width)
				r.holder:ClearAllPoints()
				r.holder:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -h)
				r.holder:SetSize(width, ch)
				h = h + ch + 10
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", scroll.child, "TOPLEFT", pad, -y)
				r:SetSize(width, h)
				y = y + h
			end
		end
	end
	scroll:SetContentHeight(y + 16)
end

-- For the specs: a docked row frame (built on the first docked draw).
function Set.DockedRowOf(groupKey, rowKey)
	local g = Set.body and Set.body.dock and Set.body.dock.groups[groupKey]
	return g and g.rows[rowKey]
end

local function Refresh(body, ctx)
	if M.IsDocked(ctx) then
		return DockedRefresh(body, ctx)
	end
	if body.dock then
		body.dock.scroll:Hide()
	end
	for _, part in ipairs({ body.rule, body.nav, body.nav.rule, body.content }) do
		part:Show()
	end
	local current = Set.Current()
	local nav = body.nav
	for _, group in ipairs(Groups()) do
		local b = nav.buttons[group.key]
		local on = group.key == current
		Paint(b.label, on and "text" or "text3")
		b.label:ClearAllPoints()
		b.label:SetPoint("LEFT", b, "LEFT", on and 16 + 15 or 16, 0)
		if on then
			nav.nokta:MoveTo(b, "LEFT", 16 + 5.5, 0, body.lastGroup == current)
		end
	end
	body.lastGroup = current
	for key, g in pairs(body.groups) do
		g:SetShown(key == current)
	end
	local g = body.groups[current]
	if not g then
		g = BuildGroup(body, Set.Group(current))
		body.groups[current] = g
	end
	g:Show()
	UpdateGroup(g)
end

-- For the specs: the row frame of a group (built when the group was shown).
function Set.RowOf(groupKey, rowKey)
	local g = Set.body and Set.body.groups[groupKey]
	return g and g.rows[rowKey]
end

-- Opens the Settings page on a group (slash commands: /craftwise ahmin, loottoast, farm lock, ...).
function ns.OpenSettings(group)
	if group and Set.Group(group) then
		M.UI().settingsGroup = group
	end
	return M.Open and M.Open(M.SETTINGS) or false
end

M.RegisterPage({
	key = M.SETTINGS, label = L["Settings"], kind = "custom",
	events = { "PRICES_CHANGED", "UPGRADES_CHANGED", "JUNK_CHANGED" },
	Build = Build,
	Refresh = Refresh,
})
