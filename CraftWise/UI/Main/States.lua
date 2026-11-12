-- Main window: the shared pieces of the six states (spec "States", board "States"). The rules and the
-- copy are in Shell.lua (M.BlockingState, M.StatusText, M.StateCopy); this file draws them:
--   M.Panel     First run, No prices, Error (and the bridge pages): icon, title, line, buttons, error text
--   M.StaleCard the "Prices are 3 days old." card above the hero card
--   M.Skeleton  a figure that is still missing while a scan runs: a bar stepping between two tones
-- Scanning and Stale in the header (status text, orange progress line) are drawn by Frame.lua.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

----------------------------------------------------------------------------------------------------
-- Panel: the body of a page that can't show its list. Left aligned, vertically centred (board: 28 in).
----------------------------------------------------------------------------------------------------

local PANEL_PAD, PANEL_TEXT_WIDTH = 28, 420
local MAX_BUTTONS = 3

local Panel = {}

-- spec = { icon = true (the W key, First run), title, titleColor (default "text"), body,
--   buttons = { { label, onClick, tip } }, text = error text (Show error text fills the box with it) }
function Panel:Set(spec)
	self.spec = spec
	self.icon:SetShown(spec.icon and true or false)
	self.title:SetText(spec.title or "")
	local tc = Style.Color(spec.titleColor or "text")
	self.title:SetTextColor(tc[1], tc[2], tc[3], 1)
	self.body:SetText(spec.body or "")
	self.body:SetShown((spec.body or "") ~= "")
	self.title:ClearAllPoints()
	if spec.icon then
		self.title:SetPoint("TOPLEFT", self.icon, "BOTTOMLEFT", 0, -8)
	else
		self.title:SetPoint("TOPLEFT", self.inner, "TOPLEFT", 0, 0)
	end
	local x = 0
	for i = 1, MAX_BUTTONS do
		local b, def = self.buttons[i], (spec.buttons or {})[i]
		b.def = def
		if def then
			b:SetLabel(def.label)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.body:IsShown() and self.body or self.title, "BOTTOMLEFT", x, -12)
			x = x + (b.cwWidth or b:GetWidth() or 0) + 8
			b:Show()
		else
			b:Hide()
		end
	end
	self.errorHolder:Hide()
	self:Show()
end

-- Fits the panel to a layout: the docked sheet is 380 wide (#161), so its text column narrows to it.
function Panel:Fit(m)
	local pad = m and m.docked and m.pad or PANEL_PAD
	local text = m and m.docked and (m.width - 2 * pad) or PANEL_TEXT_WIDTH
	self.inner:ClearAllPoints()
	self.inner:SetPoint("LEFT", self, "LEFT", pad, 0)
	self.inner:SetSize(text + (m and m.docked and 0 or 120), 1)
	self.title:SetWidth(m and m.docked and text or 0)
	self.title:SetWordWrap(m and m.docked and true or false)
	self.body:SetWidth(text)
	self.errorHolder:SetSize(m and m.docked and text or PANEL_TEXT_WIDTH + 100, 84)
	self.fitWidth = text
end

-- Show error text: the client has no clipboard API, so the text sits selected in an edit box.
function Panel:ShowErrorText()
	local box = self.errorBox
	self.errorHolder:Show()
	box:SetText(self.spec and self.spec.text or "")
	box:Show()
	box:SetFocus()
	box:HighlightText()
end

function M.Panel(parent)
	local p = CreateFrame("Frame", nil, parent)
	for k, f in pairs(Panel) do
		p[k] = f
	end
	p.inner = CreateFrame("Frame", nil, p)
	p.inner:SetPoint("LEFT", p, "LEFT", PANEL_PAD, 0)
	p.inner:SetSize(PANEL_TEXT_WIDTH + 120, 1)
	p.icon = Style.KeyIcon(p.inner, 36)
	p.icon:SetPoint("TOPLEFT", p.inner, "TOPLEFT", 0, 0)
	p.title = Style.Text(p.inner, "Brand", "text") -- 16 ExtraBold (board)
	p.title:SetJustifyH("LEFT")
	p.body = Style.Text(p.inner, "Body", "text2")
	p.body:SetJustifyH("LEFT")
	p.body:SetWidth(PANEL_TEXT_WIDTH)
	p.body:SetWordWrap(true)
	p.body:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
	p.buttons = {}
	for i = 1, MAX_BUTTONS do
		local b = Style.LineButton(p.inner, "", nil, 26)
		b:SetScript("OnClick", function(self)
			if self.def and self.def.onClick then
				self.def.onClick(p, self)
			end
		end)
		b:HookScript("OnEnter", function(self)
			if self.def and self.def.tip then
				Style.ShowTip(self, self.def.label, self.def.tip)
			end
		end)
		b:HookScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
		b:Hide()
		p.buttons[i] = b
	end
	-- Error text box: 1 unit border, the text selected.
	local holder = CreateFrame("Frame", nil, p.inner)
	holder:SetSize(PANEL_TEXT_WIDTH + 100, 84)
	holder:SetPoint("TOPLEFT", p.buttons[1], "BOTTOMLEFT", 0, -12)
	Style.Border(holder, C.ruleStrong)
	local box = CreateFrame("EditBox", nil, holder)
	box:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -6)
	box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 6)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(Style.Fonts.Small)
	box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	holder:Hide()
	p.errorHolder, p.errorBox = holder, box
	p:Hide()
	return p
end

-- The Error state for a page whose model or drawing raised.
function M.ErrorSpec(page, err)
	local copy = M.StateCopy("error", { page = page })
	local line = tostring(err or ""):match("^[^\n]*") or ""
	return {
		title = copy.title,
		titleColor = "danger",
		body = line .. (line ~= "" and " " or "") .. copy.body,
		text = tostring(err or ""),
		buttons = {
			{ label = copy.reload, onClick = function()
				if C_UI and C_UI.Reload then
					C_UI.Reload()
				end
			end },
			{ label = copy.show, onClick = function(panel)
				panel:ShowErrorText()
			end },
		},
	}
end

----------------------------------------------------------------------------------------------------
-- Stale card: above the hero card while the newest scan at the profit house is over 24 h old.
-- Board "States": cut 10, bold title in C.danger, the line in C.text2, padding 10 x 12.
----------------------------------------------------------------------------------------------------

M.STALE_CARD_HEIGHT = 46

function M.StaleCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	card:SetHeight(M.STALE_CARD_HEIGHT)
	card.sheet = Style.Sheet(card, C.card, C.cardFlap, 10, false)
	card.title = Style.Text(card, "BodyBold", "danger")
	card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
	card.body = Style.Text(card, "Small", "text2")
	card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
	function card:SetStatus(status)
		local copy = M.StateCopy("stale", { prices = status })
		self.title:SetText(copy.title)
		self.body:SetText(copy.body)
	end
	card:Hide()
	return card
end

----------------------------------------------------------------------------------------------------
-- Skeleton bars: a missing figure while a scan runs, stepping between two tones every 450 ms. The tones
-- are the "States" board's (#2A2C30, #33353A).
----------------------------------------------------------------------------------------------------

M.SKELETON_TONES = { { 0x2A / 255, 0x2C / 255, 0x30 / 255 }, { 0x33 / 255, 0x35 / 255, 0x3A / 255 } }
M.SKELETON_STEP = 0.45

local skeletons = setmetatable({}, { __mode = "k" })
local ticker = CreateFrame("Frame")
local phase, elapsed = 1, 0

local function Paint(tex)
	local c = M.SKELETON_TONES[phase]
	tex:SetVertexColor(c[1], c[2], c[3], 1)
end

local function Tick(_, dt)
	elapsed = elapsed + (dt or 0)
	if elapsed < M.SKELETON_STEP then
		return
	end
	elapsed = 0
	phase = 3 - phase
	local any = false
	for tex in pairs(skeletons) do
		if tex:IsShown() then
			any = true
			Paint(tex)
		end
	end
	if not any then
		ticker:SetScript("OnUpdate", nil)
	end
end

-- A skeleton bar (8 tall) inside parent; the caller anchors it. Shown bars step while any is shown.
function M.Skeleton(parent, width, height)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(Style.WHITE)
	tex:SetSize(width or 60, height or 8)
	skeletons[tex] = true
	Paint(tex)
	M.WakeSkeletons()
	return tex
end

-- Starts the stepping again (the window calls it on every refresh); it stops by itself when no bar shows.
function M.WakeSkeletons()
	if next(skeletons) then
		ticker:SetScript("OnUpdate", Tick)
	end
end

-- For the specs: the tone a skeleton shows now, and one step forward.
function M.SkeletonPhase()
	return phase
end

function M.StepSkeletons()
	elapsed = M.SKELETON_STEP
	Tick(nil, 0)
end
