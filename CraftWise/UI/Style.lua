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
		if self.icon then
			self.icon:SetAlpha(selected and 1 or 0.6)
		end
	end
	-- Icon left of the label; the label shifts right to make room.
	function b:SetIcon(texture)
		if not self.icon then
			self.icon = self:CreateTexture(nil, "ARTWORK")
			self.icon:SetSize(16, 16)
			self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			self.label:ClearAllPoints()
			self.label:SetPoint("CENTER", 10, 0)
			self.icon:SetPoint("RIGHT", self.label, "LEFT", -6, 0)
		end
		self.icon:SetTexture(texture)
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

-- Flat checkbox: bordered square, accent fill when checked, label on the right.
-- onChange(checked) fires on click. The label is part of the click area.
function Style.Check(parent, label, checked, onChange)
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(18)
	local box = CreateFrame("Frame", nil, c, "BackdropTemplate")
	box:SetSize(16, 16)
	box:SetPoint("LEFT")
	Style.Panel(box, Style.colors.tab, { 0.40, 0.46, 0.58, 1 })
	local fill = box:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 3, -3)
	fill:SetPoint("BOTTOMRIGHT", -3, 3)
	Style.Fill(fill, Style.colors.accent)
	c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
	c.text:SetText(label)
	c:SetWidth(22 + (c.text:GetStringWidth() or 90))
	function c:SetChecked(v)
		self.checked = v and true or false
		fill:SetShown(self.checked)
	end
	function c:GetChecked()
		return self.checked
	end
	c:SetChecked(checked)
	c:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		onChange(self.checked)
	end)
	c:SetScript("OnEnter", function()
		box:SetBackdropBorderColor(Style.colors.accentHover[1], Style.colors.accentHover[2], Style.colors.accentHover[3], 1)
	end)
	c:SetScript("OnLeave", function()
		box:SetBackdropBorderColor(0.40, 0.46, 0.58, 1)
	end)
	return c
end

-- Flat close button: an "x" that turns red on hover.
function Style.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetText("|cff8a93a6x|r")
	b:SetScript("OnEnter", function(self)
		self.text:SetText("|cffff5a5ax|r")
	end)
	b:SetScript("OnLeave", function(self)
		self.text:SetText("|cff8a93a6x|r")
	end)
	b:SetScript("OnClick", onClick)
	return b
end
