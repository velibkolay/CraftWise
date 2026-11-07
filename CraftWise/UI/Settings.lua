-- Settings panel: opened with the gear button in the CraftWise window or /craftwise settings.
-- Item tooltip section: on/off, always or only with Shift, and each line on/off.
-- Profit prices (#26 phase 2): price basis and the auction house profit uses.
local _, ns = ...
local Style = ns.Style
local C = Style.colors
local L = ns.L

local panel

local function T()
	return ns.db.tooltip
end

local function Build(parent)
	panel = CreateFrame("Frame", "CraftWiseSettings", parent or UIParent, "BackdropTemplate")
	panel:SetFrameStrata("DIALOG")
	panel:SetSize(316, 240)
	panel:EnableMouse(true)
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
	panel:SetHeight(-(y - 74) + 44)

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
