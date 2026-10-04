-- Settings panel: opened with the gear button in the CraftWise window or /cw settings.
-- Item tooltip section: on/off, always or only with Shift, and each line on/off.
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
	panel:SetSize(300, 240)
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
	panel:SetHeight(-(y - 18) + 36)

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
