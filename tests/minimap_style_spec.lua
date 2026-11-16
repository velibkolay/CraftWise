-- Interface › Minimap (#321 part 1): square minimap, addon buttons shown on mouse-over, compartment
-- button hidden. Every switch off means nothing is hooked or touched.
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function setup()
	local ns, stub = LoadAddon()
	-- Blizzard's cluster and the pieces of it the module looks at.
	local hooks = { secure = 0 }
	MinimapCluster = { }
	function MinimapCluster:UpdateMinimapConfig() Minimap.mask = "round" end
	MinimapCompassTexture = CreateFrame("Frame"); MinimapCompassTextureUnderlay = CreateFrame("Frame")
	AddonCompartmentFrame = CreateFrame("Frame")
	function AddonCompartmentFrame:UpdateDisplay() self:Show() end
	local orig = hooksecurefunc
	function hooksecurefunc(...) hooks.secure = hooks.secure + 1; return orig(...) end
	function Minimap:SetMaskTexture(path) self.mask = path end
	Minimap.children = {}
	function Minimap:GetChildren() return unpack(self.children) end
	MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop")
	function MinimapBackdrop:GetChildren() return end
	function MinimapBackdrop:GetName() return "MinimapBackdrop" end
	return ns, stub, hooks
end

local function button(name, kind)
	local b = CreateFrame("Button", name, Minimap)
	function b:GetName() return name end
	function b:GetObjectType() return kind or "Button" end
	function b:GetAlpha() return self.alpha or 1 end
	table.insert(Minimap.children, b)
	return b
end

it("minimap style: every switch is off by default and off touches and hooks nothing", function()
	local ns, _, hooks = setup()
	local s = ns.MinimapStyle.Settings()
	eq(s.squareMinimap, false); eq(s.hideButtons, false); eq(s.hideCompartment, false)
	local b = button("LibDBIcon10_Test")
	ns.MinimapStyle.Apply()
	eq(hooks.secure, 0, "no hooksecurefunc")
	eq(Minimap.hooks, nil, "no HookScript on the minimap")
	eq(Minimap.mask, nil, "mask untouched")
	eq(b.alpha, nil, "button untouched")
	eq(AddonCompartmentFrame.shown, nil, "compartment untouched")
	eq(_G.GetMinimapShape, nil)
end)

it("minimap style: square sets the mask, hides Blizzard's frame art and holds through a config update", function()
	local ns = setup()
	local Mini = ns.MinimapStyle
	Mini.Set("squareMinimap", true)
	eq(Minimap.mask, WHITE)
	eq(MinimapCompassTexture.shown, false); eq(MinimapCompassTextureUnderlay.shown, false)
	eq(GetMinimapShape(), "SQUARE")
	-- the rotateMinimap CVar made Blizzard run its own update: the square is put back
	MinimapCluster:UpdateMinimapConfig()
	eq(Minimap.mask, WHITE, "mask kept")
	eq(MinimapCompassTexture.shown, false)
	-- off: Blizzard's own function restores its mask
	Mini.Set("squareMinimap", false)
	eq(Minimap.mask, "round")
	eq(GetMinimapShape, nil)
end)

it("minimap style: buttons fade out, show while the mouse is on the minimap or a button, come back when off", function()
	local ns = setup()
	local Mini = ns.MinimapStyle
	local lib = button("LibDBIcon10_Test")
	local zoom = button("MinimapZoomIn"); Minimap.ZoomIn = zoom -- Blizzard's own (a parentKey)
	local landing = button("ExpansionLandingPageMinimapButton")
	Mini.Set("hideButtons", true)
	eq(lib.alpha, 0, "addon button hidden")
	eq(zoom.alpha, nil, "Blizzard's own button left alone")
	eq(landing.alpha, nil)
	-- mouse enters the minimap
	for _, fn in ipairs(Minimap.hooks.OnEnter) do fn(Minimap) end
	eq(lib.alpha, 1)
	-- mouse still over the button (not the minimap): stays
	local driver = Mini.driverForTest()
	Minimap.mouseOver, lib.mouseOver = false, true
	driver.scripts.OnUpdate(driver, 1)
	eq(lib.alpha, 1, "button under the mouse stays shown")
	-- mouse gone
	lib.mouseOver = false
	driver.scripts.OnUpdate(driver, 1)
	eq(lib.alpha, 0); eq(driver.scripts.OnUpdate, nil, "the timer stops")
	-- a collector moved the button to its own frame: it is given back
	Minimap.children = { zoom, landing }
	Mini.Scan()
	eq(lib.alpha, 1)
	-- off restores
	Minimap.children = { lib }
	lib.alpha = nil
	Mini.Set("hideButtons", true)
	eq(lib.alpha, 0)
	Mini.Set("hideButtons", false)
	eq(lib.alpha, 1)
end)

it("minimap style: the compartment button stays hidden while on and Blizzard decides again when off", function()
	local ns = setup()
	local Mini = ns.MinimapStyle
	Mini.Set("hideCompartment", true)
	eq(AddonCompartmentFrame.shown, false)
	AddonCompartmentFrame:UpdateDisplay() -- Blizzard's own update shows it
	eq(AddonCompartmentFrame.shown, false, "hidden again")
	Mini.Set("hideCompartment", false)
	eq(AddonCompartmentFrame.shown, true)
end)

it("minimap style: Leatrix Plus loaded is reported for the Settings note", function()
	local ns = setup()
	eq(ns.MinimapStyle.LeatrixLoaded(), false)
	C_AddOns = { IsAddOnLoaded = function(name) return name == "Leatrix_Plus" end }
	eq(ns.MinimapStyle.LeatrixLoaded(), true)
end)
