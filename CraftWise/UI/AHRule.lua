-- AH rule panel (issue #12): when the Bags view advises the AH over a vendor. Two settings, each
-- with - / +: how many percent more the AH must pay, and the minimum copper it must pay more.
local _, ns = ...
local Style = ns.Style
local C = Style.colors
local L = ns.L

local COPPER_STEPS = { 0, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000 }
local PERCENT_STEP = 5
local DEFAULT_PERCENT, DEFAULT_COPPER = 20, 10

local panel

local function S()
	return ns.db.settings
end

local function StepCopper(current, dir)
	current = current or 0
	if dir > 0 then
		for _, v in ipairs(COPPER_STEPS) do
			if v > current then
				return v
			end
		end
		return COPPER_STEPS[#COPPER_STEPS]
	end
	for i = #COPPER_STEPS, 1, -1 do
		if COPPER_STEPS[i] < current then
			return COPPER_STEPS[i]
		end
	end
	return 0
end
ns.StepCopper = StepCopper

local function Changed()
	ns.Notify("BAGS_CHANGED")
	if ns.RefreshProfitFrame then
		ns.RefreshProfitFrame()
	end
	panel.render()
end

local function Row(parent, y, label, onDown, onUp)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", 12, y)
	text:SetWidth(150)
	text:SetJustifyH("LEFT")
	text:SetText(label)
	local down = Style.Button(parent, 24, 22, "-")
	down:SetPoint("TOPLEFT", 166, y + 4)
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	value:SetPoint("LEFT", down, "RIGHT", 6, 0)
	value:SetWidth(70)
	local up = Style.Button(parent, 24, 22, "+")
	up:SetPoint("LEFT", value, "RIGHT", 6, 0)
	down:SetScript("OnClick", onDown)
	up:SetScript("OnClick", onUp)
	return value, down, up
end

local function Build(parentFrame)
	panel = CreateFrame("Frame", "CraftWiseAHRule", parentFrame, "BackdropTemplate")
	panel:SetFrameStrata("DIALOG")
	panel:SetSize(330, 176)
	panel:EnableMouse(true)
	Style.Panel(panel)
	table.insert(UISpecialFrames, "CraftWiseAHRule")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["AH rule"])
	local close = Style.CloseButton(panel, function()
		panel:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)
	local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", 12, -30)
	intro:SetPoint("RIGHT", -12, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText(C.muted .. "Advise the AH only when it pays more than a vendor by both:|r")

	panel.percent = Row(panel, -58, L["At least this % more"], function()
		S().ahMinPercent = math.max(0, (S().ahMinPercent or DEFAULT_PERCENT) - PERCENT_STEP)
		Changed()
	end, function()
		S().ahMinPercent = math.min(1000, (S().ahMinPercent or DEFAULT_PERCENT) + PERCENT_STEP)
		Changed()
	end)
	panel.copper = Row(panel, -88, L["And at least this much more"], function()
		S().ahMinCopper = StepCopper(S().ahMinCopper, -1)
		Changed()
	end, function()
		S().ahMinCopper = StepCopper(S().ahMinCopper, 1)
		Changed()
	end)

	panel.example = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.example:SetPoint("TOPLEFT", 12, -118)
	panel.example:SetPoint("RIGHT", -12, 0)
	panel.example:SetJustifyH("LEFT")

	local reset = Style.Button(panel, 110, 22, L["Defaults"])
	reset:SetPoint("BOTTOMRIGHT", -12, 10)
	reset:SetScript("OnClick", function()
		S().ahMinPercent, S().ahMinCopper = DEFAULT_PERCENT, DEFAULT_COPPER
		Changed()
	end)

	function panel.render()
		local p, c = S().ahMinPercent or DEFAULT_PERCENT, S().ahMinCopper or 0
		panel.percent:SetText(("+%d%%"):format(p))
		panel.copper:SetText(c > 0 and ns.FormatMoney(c) or "0")
		-- Example: what the AH must pay (after the cut) for a stack worth 1 silver at a vendor.
		local need = math.max(100 * (1 + p / 100), 100 + c)
		panel.example:SetText(C.muted .. ("Example: vendor pays %s - the AH must pay at least %s after the 5%% cut."):format(
			ns.FormatMoney(100), ns.FormatMoney(math.ceil(need))) .. "|r")
	end
	panel:Hide()
end

function ns.ToggleAHRule(anchor)
	if not panel then
		Build(anchor and anchor:GetParent() or UIParent)
	end
	if panel:IsShown() then
		panel:Hide()
		return
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	panel.render()
	panel:Show()
end
