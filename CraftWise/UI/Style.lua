-- Shared colours and small widget helpers so every CraftWise frame looks the same.
local _, ns = ...

local Style = {}
ns.Style = Style

Style.colors = {
	bg = { 0.055, 0.063, 0.086, 0.97 },
	panel = { 0.086, 0.098, 0.13, 1 },
	border = { 0.20, 0.24, 0.32, 1 },
	accent = { 0.25, 0.52, 0.95, 1 },
	accentHover = { 0.33, 0.60, 1.00, 1 },
	tab = { 0.12, 0.14, 0.19, 1 },
	tabHover = { 0.16, 0.19, 0.26, 1 },
	stripe = { 1, 1, 1, 0.025 },
	hover = { 1, 1, 1, 0.07 },
	muted = "|cff8a93a6",
	good = "|cff4fd18b",
	bad = "|cffff5a5a",
	warn = "|cffffc24d",
	info = "|cff8ab4ff",
	white = "|cffffffff",
}

local WHITE = "Interface\\Buttons\\WHITE8x8"

function Style.Fill(texture, color)
	texture:SetTexture(WHITE)
	texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

-- Flat panel with a 1px border.
function Style.Panel(frame, bg, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	bg, border = bg or Style.colors.bg, border or Style.colors.border
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Flat button with a label; selected buttons use the accent colour.
function Style.Button(parent, width, height, text)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, height)
	Style.Panel(b, Style.colors.tab, Style.colors.border)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER")
	b.label:SetText(text or "")
	function b:SetSelected(selected)
		self.selected = selected
		local c = selected and Style.colors.accent or Style.colors.tab
		self:SetBackdropColor(c[1], c[2], c[3], c[4])
	end
	function b:SetLabel(t)
		self.label:SetText(t)
	end
	b:SetScript("OnEnter", function(self)
		local c = self.selected and Style.colors.accentHover or Style.colors.tabHover
		self:SetBackdropColor(c[1], c[2], c[3], c[4])
	end)
	b:SetScript("OnLeave", function(self)
		self:SetSelected(self.selected)
	end)
	return b
end

-- Small checkbox with a label on its right. onChange(checked) fires on click.
function Style.Check(parent, label, checked, onChange)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(22, 22)
	c:SetChecked(checked)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", c, "RIGHT", 2, 1)
	c.text:SetText(label)
	c:SetScript("OnClick", function(self)
		onChange(self:GetChecked() and true or false)
	end)
	return c
end
