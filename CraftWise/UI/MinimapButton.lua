-- Minimap button and the addon compartment entry (#159, spec "Minimap button"; Origami look).
-- 34 round: the client's minimap button border as the ring, the W key (cw-key-w, 64 x 64) at 20 inside.
-- Click opens CraftWise, right-click toggles the farm tracker, Shift-click docks or undocks the main window
-- (once the docked layout exists, #161), drag moves it around the minimap. Hover: the inverse tooltip.
-- Hiding the button: Settings ("Minimap button") or /craftwise minimap. It is a named child of the
-- minimap, so MinimapButtonButton and similar collectors pick it up like any other button.
local _, ns = ...
local Style = ns.Style

local SIZE, ICON = 34, 20
local SCALE = SIZE / 31 -- the client's ring art is laid out for a 31 unit button
local button

local function Settings()
	ns.db.minimap = ns.db.minimap or { hide = false, angle = 215 }
	return ns.db.minimap
end

-- What the clicks do. The main window (#153) and the docked layout (#161) plug in here when they exist:
-- ns.ToggleMainWindow() and ns.ToggleDock(); until then the profit window opens and Shift-click does what
-- a click does.
function ns.ToggleCraftWise()
	if ns.ToggleMainWindow then
		return ns.ToggleMainWindow()
	end
	return ns.ToggleProfitFrame()
end

function ns.CanDock()
	return ns.ToggleDock ~= nil
end

-- mouse: "LeftButton" | "RightButton"; shift: Shift held. Returns what it did, for the specs.
function ns.MinimapClick(mouse, shift)
	if mouse == "RightButton" then
		CraftWise_FarmToggle()
		return "farm"
	end
	if shift and ns.CanDock() then
		ns.ToggleDock()
		return "dock"
	end
	ns.ToggleCraftWise()
	return "open"
end

-- The tooltip's lines: one per thing the button does (Shift-click only once docking exists).
function ns.MinimapTipLines()
	local lines = { "Click: open", "Right-click: farm tracker" }
	if ns.CanDock() then
		lines[#lines + 1] = "Shift-click: dock / undock"
	end
	lines[#lines + 1] = "Drag: move"
	return lines
end

local function Place()
	local angle = math.rad(Settings().angle or 215)
	local radius = (Minimap:GetWidth() / 2) + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not (mx and cx) then
		return
	end
	Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	Place()
end

local function Build()
	button = CreateFrame("Button", "CraftWiseMinimapButton", Minimap)
	button:SetSize(SIZE, SIZE)
	-- Above the minimap and any border art drawn on top of it.
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- The ring's centre in the client's art sits at (17, -15) of a 31 unit button; scaled to 34.
	local cx, cy = 17 * SCALE, -15 * SCALE
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20 * SCALE, 20 * SCALE)
	bg:SetPoint("CENTER", button, "TOPLEFT", cx, cy)
	button.icon = Style.KeyIcon(button, ICON, "ARTWORK")
	button.icon:SetPoint("CENTER", button, "TOPLEFT", cx, cy)
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button.border:SetSize(53 * SCALE, 53 * SCALE)
	button.border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

	button:SetScript("OnClick", function(_, mouse)
		Style.HideTip(button)
		ns.MinimapClick(mouse, IsShiftKeyDown())
	end)
	button:SetScript("OnDragStart", function(self)
		Style.HideTip(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		Style.ShowTip(self, "CraftWise", unpack(ns.MinimapTipLines()))
	end)
	button:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	Place()
end

function ns.UpdateMinimapButton()
	if not (ns.db and Minimap) then
		return
	end
	if not button then
		Build()
	end
	button:SetShown(not Settings().hide)
end

function ns.ToggleMinimapButton()
	Settings().hide = not Settings().hide
	ns.UpdateMinimapButton()
end

ns.Listen("DB_READY", ns.UpdateMinimapButton)

-- Addon compartment (the addon list button next to the minimap). The TOC names this global in
-- AddonCompartmentFunc; its icon is the TOC's IconTexture, the same W key (#166).
function CraftWise_OnAddonCompartmentClick()
	ns.ToggleCraftWise()
end
