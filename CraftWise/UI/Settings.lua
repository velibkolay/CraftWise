-- Settings panel: opened with the gear button in the CraftWise window or /craftwise settings.
-- Item tooltip section: on/off, always or only with Shift, and each line on/off.
-- Profit prices (#26 phase 2): price basis and the auction house profit uses.
-- Reagent cost per view (#47): AH or paid cost.
-- Loot toast (#114) and farm tracker (#126) on/off.
-- Two columns (#137): the right one holds every switch a slash command has (loot toast move/test/duration/value,
-- farm lock/idle/scale/history, fishing session gap and own-catch minimum, minimap button).
local _, ns = ...
local Style = ns.Style
local C = Style.colors
local L = ns.L

local panel

local function T()
	return ns.db.tooltip
end

-- A setting with - / +: label, value text (set in render), change(dir) with dir -1 or 1, then a re-render.
local steppers = {}
local function Stepper(x, y, label, change)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", x, y - 5)
	text:SetWidth(150)
	text:SetJustifyH("LEFT")
	text:SetText(label)
	local down = Style.Button(panel, 24, 22, "-")
	down:SetPoint("TOPLEFT", x + 156, y)
	local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	value:SetPoint("LEFT", down, "RIGHT", 4, 0)
	value:SetWidth(52)
	local up = Style.Button(panel, 24, 22, "+")
	up:SetPoint("LEFT", value, "RIGHT", 4, 0)
	local s = { value = value, down = down, up = up }
	local function click(dir)
		return function()
			change(dir)
			panel.render()
		end
	end
	down:SetScript("OnClick", click(-1))
	up:SetScript("OnClick", click(1))
	steppers[#steppers + 1] = s
	return s
end

local function Build(parent)
	panel = CreateFrame("Frame", "CraftWiseSettings", parent or UIParent, "BackdropTemplate")
	panel:SetFrameStrata("DIALOG")
	panel:SetSize(632, 240)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	Style.Panel(panel)
	table.insert(UISpecialFrames, "CraftWiseSettings")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Settings"])
	local close = Style.CloseButton(panel, function()
		panel:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)

	local head = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	head:SetPoint("TOPLEFT", 12, -34)
	head:SetText(C.muted .. L["Item tooltips"] .. "|r")

	panel.enabled = Style.Check(panel, L["Show CraftWise in item tooltips"], T().enabled, function(v)
		T().enabled = v
		panel.render()
	end)
	panel.enabled:SetPoint("TOPLEFT", 12, -54)

	panel.always = Style.Button(panel, 130, 22, L["Always"])
	panel.always:SetPoint("TOPLEFT", 12, -80)
	panel.shift = Style.Button(panel, 130, 22, L["Only with Shift"])
	panel.shift:SetPoint("LEFT", panel.always, "RIGHT", 8, 0)
	panel.always:SetScript("OnClick", function()
		T().mode = "always"
		panel.render()
	end)
	panel.shift:SetScript("OnClick", function()
		T().mode = "shift"
		panel.render()
	end)

	local linesHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	linesHead:SetPoint("TOPLEFT", 12, -112)
	linesHead:SetText(C.muted .. L["Lines"] .. "|r")
	panel.lines = {}
	for i, line in ipairs(ns.TOOLTIP_LINES) do
		local check = Style.Check(panel, L[line.label], T().lines[line.key], function(v)
			T().lines[line.key] = v
		end)
		check:SetPoint("TOPLEFT", 12, -112 - i * 24)
		panel.lines[line.key] = check
	end

	-- Item menu click in the bags.
	local clickHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	local y = -112 - (#ns.TOOLTIP_LINES + 1) * 24 - 4
	clickHead:SetPoint("TOPLEFT", 12, y)
	clickHead:SetText(C.muted .. L["Keep / Junk menu in your bags"] .. "|r")
	panel.clicks = {}
	local choices = { { "middle", L["Middle click"] }, { "altright", L["Alt + right"] }, { "off", L["Off"] } }
	for i, c in ipairs(choices) do
		local b = Style.Button(panel, 88, 22, c[2])
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 92, y - 18)
		b:SetScript("OnClick", function()
			ns.db.settings.menuClick = c[1]
			panel.render()
		end)
		panel.clicks[c[1]] = b
	end

	-- Profit prices: basis and house. A neutral house is selectable once something was recorded there.
	y = y - 52
	local priceHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	priceHead:SetPoint("TOPLEFT", 12, y)
	priceHead:SetText(C.muted .. L["Profit prices"] .. "|r")
	panel.basis = {}
	for i, c in ipairs({ { "typical", L["Typical"] }, { "current", L["Current lowest"] } }) do
		local b = Style.Button(panel, 142, 22, c[2])
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 150, y - 18)
		b:SetScript("OnClick", function()
			ns.db.settings.priceBasis = c[1]
			panel.render()
			ns.Notify("PRICES_CHANGED")
		end)
		panel.basis[c[1]] = b
	end
	panel.houses = {}
	for i, choice in ipairs(ns.Market.CHOICES) do
		local b = Style.Button(panel, 70, 22, "")
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 74, y - 46)
		b:SetScript("OnClick", function()
			if choice ~= "faction" and not ns.Market.HasData((ns.Market.HouseFor(choice))) then
				return -- "no data": nothing recorded at that house yet
			end
			ns.db.settings.priceHouse = choice
			panel.render()
			ns.Notify("PRICES_CHANGED")
		end)
		panel.houses[choice] = b
	end
	panel.houseHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.houseHint:SetPoint("TOPLEFT", 12, y - 74)
	panel.houseHint:SetWidth(292)
	panel.houseHint:SetJustifyH("LEFT")

	-- Reagent cost per view (#47): AH (cheapest of vendor and AH) or paid cost from the ledger.
	local basisY = y - 100
	local basisHead = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	basisHead:SetPoint("TOPLEFT", 12, basisY)
	basisHead:SetText(C.muted .. L["Reagent cost"] .. "|r")
	local viewLabels = { profit = L["Profit"], learn = L["Learn"], level = L["Level"], upgrades = L["Upgrades"] }
	panel.costBasis = {}
	for i, view in ipairs(ns.COST_BASIS_VIEWS) do
		local rowY = basisY - 18 - (i - 1) * 26
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 12, rowY - 5)
		label:SetText(viewLabels[view])
		panel.costBasis[view] = {}
		for j, c in ipairs({ { "ah", L["AH"] }, { "paid", L["Paid cost"] } }) do
			local b = Style.Button(panel, 100, 22, c[2])
			b:SetPoint("TOPLEFT", 96 + (j - 1) * 106, rowY)
			b:SetScript("OnClick", function()
				ns.db.settings.costBasis[view] = c[1]
				panel.render()
				ns.Notify("PRICES_CHANGED")
			end)
			panel.costBasis[view][c[1]] = b
		end
	end
	panel.basisHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.basisHint:SetPoint("TOPLEFT", 12, basisY - 18 - #ns.COST_BASIS_VIEWS * 26)
	panel.basisHint:SetWidth(292)
	panel.basisHint:SetJustifyH("LEFT")
	panel.basisHint:SetText(C.muted .. L["Paid cost: what you paid for the units you hold (Records > Ledger); a reagent without one uses AH. Intermediates you can craft cost the cheaper of crafting and buying, unless they have a paid cost."] .. "|r")

	-- Right column (#137): every switch a slash command has (loot toast, farm tracker, fishing, minimap).
	local RX, RW_ = 332, 288
	local function Head(y, text)
		local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		h:SetPoint("TOPLEFT", RX, y)
		h:SetText(C.muted .. text .. "|r")
		return h
	end
	local function Hint(y, text)
		local h = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		h:SetPoint("TOPLEFT", RX, y)
		h:SetWidth(RW_)
		h:SetJustifyH("LEFT")
		if text then
			h:SetText(C.muted .. text .. "|r")
		end
		return h
	end

	-- Fast auto-loot (Loot.lua, #41).
	Head(-34, L["Loot"])
	panel.fastLoot = Style.Check(panel, L["Fast auto-loot"], ns.Loot.Enabled(), function(v)
		ns.Loot.SetEnabled(v)
		panel.render()
	end)
	panel.fastLoot:SetPoint("TOPLEFT", RX, -54)
	panel.lootHint = Hint(-76)

	-- Loot toast (LootToast.lua, #114): on/off, value, move, test, reset, duration.
	local toastY = -112
	Head(toastY, L["Loot toast"])
	panel.lootToast = Style.Check(panel, L["Show what you loot"], ns.LootToast.Enabled(), function(v)
		ns.LootToast.Slash(v and "on" or "off")
		panel.render()
	end)
	panel.lootToast:SetPoint("TOPLEFT", RX, toastY - 18)
	panel.toastValue = Style.Check(panel, L["With value"], ns.db.lootToast.value ~= false, function(v)
		ns.db.lootToast.value = v
		panel.render()
	end)
	panel.toastValue:SetPoint("TOPLEFT", RX + 170, toastY - 18)
	panel.toastMove = Style.Button(panel, 90, 22, L["Move"])
	panel.toastMove:SetPoint("TOPLEFT", RX, toastY - 42)
	panel.toastMove:SetScript("OnClick", function()
		ns.LootToast.Slash(ns.db.lootToast.locked == false and "lock" or "unlock")
		panel.render()
	end)
	panel.toastTest = Style.Button(panel, 70, 22, L["Test"])
	panel.toastTest:SetPoint("LEFT", panel.toastMove, "RIGHT", 6, 0)
	panel.toastTest:SetScript("OnClick", function()
		ns.LootToast.Slash("test")
	end)
	panel.toastReset = Style.Button(panel, 110, 22, L["Reset position"])
	panel.toastReset:SetPoint("LEFT", panel.toastTest, "RIGHT", 6, 0)
	panel.toastReset:SetScript("OnClick", function()
		ns.LootToast.Slash("reset")
	end)
	panel.toastDuration = Stepper(RX, toastY - 72, L["Lines stay"], function(dir)
		local T = ns.LootToast
		local v = math.max(T.MIN_DURATION, math.min(T.MAX_DURATION, T.Duration() + dir))
		ns.db.lootToast.duration = v
	end)

	-- Farm tracker (Farm.lua, #126): on/off, autostart, lock, idle pause, scale, window, history.
	local farmY = toastY - 104
	Head(farmY, L["Farm tracker"])
	panel.farm = Style.Check(panel, L["Farm tracker"], ns.Farm.Enabled(), function(v)
		ns.Farm.Slash(v and "on" or "off")
		panel.render()
	end)
	panel.farm:SetPoint("TOPLEFT", RX, farmY - 18)
	panel.farmAuto = Style.Check(panel, L["Start on first loot"], ns.Farm.AutoStart(), function(v)
		ns.Farm.Slash(v and "autostart on" or "autostart off")
		panel.render()
	end)
	panel.farmAuto:SetPoint("TOPLEFT", RX + 150, farmY - 18)
	panel.farmLock = Style.Check(panel, L["Lock window"], ns.db.farm.locked and true or false, function(v)
		ns.Farm.Slash(v and "lock" or "unlock")
		panel.render()
	end)
	panel.farmLock:SetPoint("TOPLEFT", RX, farmY - 40)
	panel.farmIdle = Stepper(RX, farmY - 66, L["Pause when idle"], function(dir)
		local v = ns.Farm.IdleMinutes() + dir * (ns.Farm.IdleMinutes() + dir >= 10 and 5 or 1)
		ns.db.farm.idleMinutes = math.max(0, math.min(ns.Farm.MAX_IDLE, v))
	end)
	panel.farmScale = Stepper(RX, farmY - 94, L["Window scale"], function(dir)
		local cur = tonumber(ns.db.farm.scale) or 1
		local v = math.floor((cur + dir * 0.1) * 10 + 0.5) / 10
		v = math.max(ns.Farm.MIN_SCALE, math.min(ns.Farm.MAX_SCALE, v))
		ns.Farm.Slash(("scale %g"):format(v))
	end)
	panel.farmWindow = Style.Button(panel, 110, 22, L["Farm window"])
	panel.farmWindow:SetPoint("TOPLEFT", RX, farmY - 124)
	panel.farmWindow:SetScript("OnClick", function()
		ns.Farm.Slash("toggle")
	end)
	panel.farmHistory = Style.Button(panel, 110, 22, L["Farm history"])
	panel.farmHistory:SetPoint("LEFT", panel.farmWindow, "RIGHT", 6, 0)
	panel.farmHistory:SetScript("OnClick", function()
		if ns.FarmHistory then
			ns.FarmHistory.Open()
		end
	end)
	panel.farmHint = Hint(farmY - 152, L["Gold per hour while farming, valued with CraftWise prices. Also: the Farm button or a key binding."])

	-- Fishing (FishingTables.lua #86, FishingZones.lua #88): session gap and own-catch minimum.
	local fishY = farmY - 190
	Head(fishY, L["Fishing"])
	panel.fishGap = Stepper(RX, fishY - 22, L["Session gap"], function(dir)
		ns.db.settings.fishingSessionGap = math.max(1, math.min(60, ns.Fishing.SessionGap() + dir))
	end)
	panel.fishOwnMin = Stepper(RX, fishY - 50, L["Own catches count from"], function(dir)
		local cur = ns.FishingZones.OwnMin()
		local step = cur + dir * 10 >= 10 and 10 or 1
		ns.db.settings.fishingOwnMin = math.max(1, math.min(1000, cur + dir * step))
		if ns.RefreshProfitFrame then
			ns.RefreshProfitFrame()
		end
	end)
	Hint(fishY - 74, L["Gap: catches closer than this are one session (per hour). Below the count, a zone shows the local reference."])

	-- Other.
	local otherY = fishY - 110
	Head(otherY, L["Other"])
	panel.minimap = Style.Check(panel, L["Minimap button"], not ns.db.minimap.hide, function(v)
		if (not ns.db.minimap.hide) ~= v then
			ns.ToggleMinimapButton()
		end
		panel.render()
	end)
	panel.minimap:SetPoint("TOPLEFT", RX, otherY - 18)
	panel.records = Style.Button(panel, 110, 22, L["Records"])
	panel.records:SetPoint("TOPLEFT", RX + 150, otherY - 16)
	panel.records:SetScript("OnClick", function()
		ns.ToggleRecords()
	end)
	panel:SetHeight(math.max(-otherY + 56, 640))

	function panel.render()
		for key, b in pairs(panel.clicks) do
			b:SetSelected((ns.db.settings.menuClick or "middle") == key)
		end
		local t = T()
		panel.enabled:SetChecked(t.enabled)
		panel.always:SetSelected(t.mode ~= "shift")
		panel.shift:SetSelected(t.mode == "shift")
		for key, check in pairs(panel.lines) do
			check:SetChecked(t.lines[key])
			check:SetAlpha(t.enabled and 1 or 0.4)
		end
		panel.always:SetAlpha(t.enabled and 1 or 0.4)
		panel.shift:SetAlpha(t.enabled and 1 or 0.4)
		local basis, house = ns.PriceSettings()
		for key, b in pairs(panel.basis) do
			b:SetSelected(key == basis)
		end
		local missing = {}
		for _, choice in ipairs(ns.Market.CHOICES) do
			local b = panel.houses[choice]
			local key, label = ns.Market.HouseFor(choice)
			local has = key and ns.Market.HasData(key)
			b:SetLabel(label or L["Own faction"])
			b:SetSelected(choice == house)
			b:SetAlpha((has or choice == "faction") and 1 or 0.4)
			if not has then
				missing[#missing + 1] = label or L["Own faction"]
			end
		end
		local hint = L["Auction house for profit."]
		if #missing > 0 then
			hint = hint .. " " .. L["No data yet:"] .. " " .. table.concat(missing, ", ")
		end
		panel.houseHint:SetText(C.muted .. hint .. "|r")
		for view, buttons in pairs(panel.costBasis) do
			local basis = ns.CostBasis(view)
			for key, b in pairs(buttons) do
				b:SetSelected(key == basis)
			end
		end
		panel.fastLoot:SetChecked(ns.Loot.Enabled())
		local toast = ns.db.lootToast
		panel.lootToast:SetChecked(ns.LootToast.Enabled())
		panel.toastValue:SetChecked(toast.value ~= false)
		panel.toastMove:SetLabel(toast.locked == false and L["Lock"] or L["Move"])
		panel.toastMove:SetSelected(toast.locked == false)
		panel.toastDuration.value:SetText(("%gs"):format(ns.LootToast.Duration()))
		panel.farm:SetChecked(ns.Farm.Enabled())
		panel.farmAuto:SetChecked(ns.Farm.AutoStart())
		panel.farmAuto:SetAlpha(ns.Farm.Enabled() and 1 or 0.4)
		panel.farmLock:SetChecked(ns.db.farm.locked and true or false)
		local idle = ns.Farm.IdleMinutes()
		panel.farmIdle.value:SetText(idle > 0 and (idle .. " min") or L["never"])
		panel.farmScale.value:SetText(("%.1f"):format(tonumber(ns.db.farm.scale) or 1))
		panel.fishGap.value:SetText(ns.Fishing.SessionGap() .. " min")
		panel.fishOwnMin.value:SetText(tostring(ns.FishingZones.OwnMin()))
		panel.minimap:SetChecked(not ns.db.minimap.hide)
		local other = ns.Loot.Conflict()
		panel.fastLoot:SetAlpha(other and 0.4 or 1)
		panel.lootHint:SetText(C.muted .. (other and (other .. " " .. L["is loaded, so CraftWise does not loot."])
			or L["Records recipe sources, then loots. Hold Shift to loot by hand."]) .. "|r")
	end
	panel:Hide()
end

function ns.ToggleSettings(anchor)
	if not panel then
		Build(anchor and anchor:GetParent())
	end
	if panel:IsShown() then
		panel:Hide()
		return
	end
	panel:ClearAllPoints()
	if anchor then
		panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	else
		panel:SetPoint("CENTER")
	end
	panel.render()
	panel:Show()
end
