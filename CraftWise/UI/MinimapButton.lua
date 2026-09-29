-- Minimap button (drag to move around the minimap) and the addon compartment entry.
-- Left-click toggles the profit window; right-click hides the button (/cw minimap brings it back).
local _, ns = ...

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local button

local function Settings()
	ns.db.minimap = ns.db.minimap or { hide = false, angle = 215 }
	return ns.db.minimap
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

local function Tooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("CraftWise", 1, 1, 1)
	GameTooltip:AddLine("Left-click: profit table", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Drag: move button", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Right-click: hide button (/cw minimap)", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function Build()
	button = CreateFrame("Button", "CraftWiseMinimapButton", Minimap)
	button:SetSize(31, 31)
	-- Above the minimap and any border art drawn on top of it.
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			Settings().hide = true
			button:Hide()
			ns.Print("minimap button hidden - /cw minimap shows it again")
		else
			ns.ToggleProfitFrame()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", Tooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
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

-- Addon compartment (the addon list button next to the minimap on the modern client).
-- The TOC names this global in AddonCompartmentFunc.
function CraftWise_OnAddonCompartmentClick()
	ns.ToggleProfitFrame()
end
