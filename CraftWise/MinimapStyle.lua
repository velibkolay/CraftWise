-- Interface › Minimap (#321 part 1): a square minimap, the addon buttons around it shown on mouse-over, and
-- the addon compartment button hidden. Every switch is off by default (db.settings.interface) and while it
-- is off nothing is hooked, nothing is touched.
--
-- Built from Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`), nothing from another
-- addon:
--   Blizzard_Minimap/Camelot/Minimap.lua: MinimapClusterMixin:UpdateMinimapConfig sets the round mask
--     ("ui-hud-minimap-frame-generic-mask") with Minimap:SetMaskTexture and draws the frame art in
--     MinimapCompassTexture / MinimapCompassTextureUnderlay. It runs again when the rotateMinimap CVar
--     changes, so a hook on it keeps the square in place (and calling it again puts Blizzard's look back).
--   Blizzard_Minimap/Mainline/Minimap.xml: Minimap, MinimapBackdrop, MinimapCluster, ExpansionLandingPage
--     MinimapButton (Blizzard's own children, left alone).
--   Blizzard_Minimap/Mainline/AddonCompartment.lua: AddonCompartmentMixin:UpdateDisplay shows or hides
--     AddonCompartmentFrame; a hook on it keeps the button hidden.
--   Blizzard_APIDocumentationGenerated/MinimapFrameAPIDocumentation.lua: Minimap:SetMaskTexture(asset).
--
-- Buttons: only frames that are children of Minimap or MinimapBackdrop and are not Blizzard's own are
-- touched, and only by alpha (never Hide, SetParent or a script of theirs). A collector such as
-- MinimapButtonButton moves a button to its own frame: from then on the button is not ours, it gets its
-- alpha back, and the collector's own button (a child of UIParent) is never looked at.
local _, ns = ...

local Mini = {}
ns.MinimapStyle = Mini

-- Client texture, referenced and not copied (the same one Style.lua fills with). Opaque white: as a mask
-- it shows the whole square and blips, the map and the ping all follow it.
local SQUARE_MASK = "Interface\\Buttons\\WHITE8x8"
local REVEAL_INTERVAL = 0.1

-- Blizzard's named minimap children that are not addon buttons.
local BLIZZARD_NAMES = {
	MinimapBackdrop = true,
	ExpansionLandingPageMinimapButton = true,
	GameTimeFrame = true,
	AddonCompartmentFrame = true,
}

local installed = {} -- hooks put in place this session (never more than once each)
local tracked = {} -- button -> alpha it had before we faded it
local revealed = true
local driver -- frame with the OnUpdate that follows the mouse

function Mini.Settings()
	local s = ns.db and ns.db.settings
	if not s then
		return {}
	end
	s.interface = s.interface or {}
	return s.interface
end

local function Enabled(key)
	return Mini.Settings()[key] == true
end

-- Leatrix Plus is loaded: both would act at once (Settings shows a note next to the switches).
function Mini.LeatrixLoaded()
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Leatrix_Plus") and true or false
end

----------------------------------------------------------------------------------------------------
-- Square
----------------------------------------------------------------------------------------------------

local border

local function BuildBorder()
	if border then
		return border
	end
	border = CreateFrame("Frame", nil, Minimap)
	border:SetAllPoints(Minimap)
	border:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
	border.edge = ns.Style.Border(border, ns.Style.C.ruleStrong)
	return border
end

function Mini.ApplySquare()
	if not Minimap then
		return
	end
	if Enabled("squareMinimap") then
		if MinimapCluster and not installed.config and MinimapCluster.UpdateMinimapConfig then
			installed.config = true
			hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", function()
				if Enabled("squareMinimap") then
					Mini.ApplySquare()
				end
			end)
		end
		Minimap:SetMaskTexture(SQUARE_MASK)
		if MinimapCompassTexture then
			MinimapCompassTexture:Hide()
		end
		if MinimapCompassTextureUnderlay then
			MinimapCompassTextureUnderlay:Hide()
		end
		BuildBorder():Show()
		-- The shape other addons ask for when they place their buttons on the edge.
		if not Mini.shapeSet then
			Mini.shapeSet = true
			Mini.oldShape = _G.GetMinimapShape
			_G.GetMinimapShape = function() return "SQUARE" end
		end
	else
		if border then
			border:Hide()
		end
		if Mini.shapeSet then
			Mini.shapeSet = false
			_G.GetMinimapShape = Mini.oldShape
			Mini.oldShape = nil
		end
		-- Blizzard's own function puts its mask and its frame art back.
		if installed.config and MinimapCluster and MinimapCluster.UpdateMinimapConfig then
			MinimapCluster:UpdateMinimapConfig()
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Addon buttons: faded out, shown while the mouse is over the minimap or one of them
----------------------------------------------------------------------------------------------------

local function IsBlizzardChild(parent, child)
	local name = child.GetName and child:GetName()
	if name and BLIZZARD_NAMES[name] then
		return true
	end
	-- parentKey children (ZoomIn, ZoomOut, ZoomHitArea ...) are fields of the parent.
	for _, v in pairs(parent) do
		if v == child then
			return true
		end
	end
	return false
end

-- Addon buttons that sit on the minimap right now.
function Mini.Buttons()
	local list = {}
	for _, parent in ipairs({ Minimap, MinimapBackdrop }) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if child ~= border and not IsBlizzardChild(parent, child) and child.GetObjectType then
					local kind = child:GetObjectType()
					if kind == "Button" or kind == "CheckButton" then
						list[#list + 1] = child
					end
				end
			end
		end
	end
	return list
end

local function SetAlphaOf(button, alpha)
	button:SetAlpha(alpha)
end

local function Release(button)
	local was = tracked[button]
	if was ~= nil then
		tracked[button] = nil
		SetAlphaOf(button, was)
	end
end

local function MouseOverAny()
	if Minimap:IsMouseOver() then
		return true
	end
	for button in pairs(tracked) do
		if button:IsMouseOver() then
			return true
		end
	end
	return false
end

local function Fade(show)
	revealed = show
	for button in pairs(tracked) do
		SetAlphaOf(button, show and tracked[button] or 0)
	end
end

local elapsed = 0
local function OnUpdate(_, dt)
	elapsed = elapsed + dt
	if elapsed < REVEAL_INTERVAL then
		return
	end
	elapsed = 0
	if not MouseOverAny() then
		Fade(false)
		driver:SetScript("OnUpdate", nil)
	end
end

-- Walks the buttons: new ones are taken, ones a collector moved away are given back.
function Mini.Scan()
	if not Enabled("hideButtons") then
		return
	end
	local now = {}
	for _, button in ipairs(Mini.Buttons()) do
		now[button] = true
		if tracked[button] == nil then
			tracked[button] = button:GetAlpha() or 1
		end
		if not revealed then
			SetAlphaOf(button, 0)
		end
	end
	for button in pairs(tracked) do
		if not now[button] then
			Release(button)
		end
	end
end

local function OnMinimapEnter()
	if not Enabled("hideButtons") then
		return
	end
	Mini.Scan()
	Fade(true)
	elapsed = 0
	driver:SetScript("OnUpdate", OnUpdate)
end

function Mini.ApplyButtons()
	if not Minimap then
		return
	end
	if Enabled("hideButtons") then
		if not installed.buttons then
			installed.buttons = true
			driver = CreateFrame("Frame")
			Minimap:HookScript("OnEnter", OnMinimapEnter)
		end
		Mini.Scan()
		if not driver:GetScript("OnUpdate") then
			Fade(false)
		end
	else
		for button in pairs(tracked) do
			Release(button)
		end
		revealed = true
		if driver then
			driver:SetScript("OnUpdate", nil)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Addon compartment button
----------------------------------------------------------------------------------------------------

function Mini.ApplyCompartment()
	local frame = AddonCompartmentFrame
	if not frame then
		return
	end
	if Enabled("hideCompartment") then
		if not installed.compartment and frame.UpdateDisplay then
			installed.compartment = true
			hooksecurefunc(frame, "UpdateDisplay", function()
				if Enabled("hideCompartment") then
					frame:Hide()
				end
			end)
		end
		frame:Hide()
	elseif installed.compartment then
		-- Blizzard decides again whether the button shows.
		frame:UpdateDisplay()
	end
end

----------------------------------------------------------------------------------------------------

function Mini.Apply()
	Mini.ApplySquare()
	Mini.ApplyButtons()
	Mini.ApplyCompartment()
end

-- The timer frame (specs drive its OnUpdate).
function Mini.driverForTest()
	return driver
end

-- Settings rows call this after a switch changed.
function Mini.Set(key, value)
	Mini.Settings()[key] = value and true or false
	Mini.Apply()
end

ns.Listen("DB_READY", function()
	if Enabled("squareMinimap") or Enabled("hideButtons") or Enabled("hideCompartment") then
		Mini.Apply()
	end
end)

-- Other addons create their buttons after we load: look again once the world is up and a little later.
ns.On("PLAYER_ENTERING_WORLD", function()
	if not Enabled("hideButtons") then
		return
	end
	Mini.Scan()
	C_Timer.After(3, Mini.Scan)
	C_Timer.After(10, Mini.Scan)
end)
