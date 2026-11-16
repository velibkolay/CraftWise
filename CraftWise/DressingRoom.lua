-- Interface › Dressing room (#321 part 4): buttons on the dressing room (DressUpFrame) to undress the
-- model, to show only the items you tried on, and to pause or play the model's animation. Switches (off
-- by default): db.settings.interface.dressStrip (undress and try-ons only) and dressAnim (pause / play).
-- While off nothing is hooked and no button exists.
--
-- Built from Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`), nothing from another
-- addon:
--   Blizzard_UIPanels_Game/Mainline/DressUpFrames.lua: DressUpFrame, DressUpFrame.ModelScene,
--     ModelScene:GetPlayerActor(), DressUpVisualLink(forcedFrame, link, ...) (every item try-on goes through
--     it and ends in playerActor:TryOn(link)), DressUpFrame_Show(frame, ids, forcePlayerRefresh, link)
--     (the Reset button calls it with forcePlayerRefresh).
--   Blizzard_APIDocumentationGenerated/FrameAPIModelSceneFrameActorDocumentation.lua:
--     actor:Undress(includeWeapons), actor:TryOn(link), actor:SetPaused(paused, affectsGlobalPause).
--
-- "Try-ons only" re-applies the items tried on by link since the dressing room was opened or reset; items
-- that arrive another way (the wardrobe's appearances, a set) are not tracked, so they are not kept.
local _, ns = ...

local DR = {}
ns.DressingRoom = DR

local installed = {}
local tried = {} -- links tried on since the frame opened or was reset
local buttons

local function Settings()
	local s = ns.db and ns.db.settings
	if not s then
		return {}
	end
	s.interface = s.interface or {}
	return s.interface
end

function DR.Settings()
	return Settings()
end

local function On(key)
	return Settings()[key] == true
end

local function Actor()
	local frame = DressUpFrame
	return frame and frame.ModelScene and frame.ModelScene:GetPlayerActor()
end

function DR.Tried()
	return tried
end

-- Undress button: everything off, weapons too.
function DR.Undress()
	local actor = Actor()
	if actor then
		actor:Undress(true)
		return true
	end
	return false
end

-- Try-ons only: undress, then put back only what was tried on.
function DR.TriedOnly()
	local actor = Actor()
	if not actor or #tried == 0 then
		return false
	end
	actor:Undress(true)
	for _, link in ipairs(tried) do
		actor:TryOn(link)
	end
	return true
end

-- Pause or play the model's animation. Returns the new state (true = paused).
function DR.TogglePause()
	local actor = Actor()
	if not actor then
		return nil
	end
	DR.paused = not DR.paused
	actor:SetPaused(DR.paused, false)
	return DR.paused
end

local function Refresh()
	if not buttons then
		return
	end
	buttons.undress:SetShown(On("dressStrip"))
	buttons.tried:SetShown(On("dressStrip"))
	buttons.pause:SetShown(On("dressAnim"))
	buttons.pause:SetLabel(DR.paused and ns.L["Play"] or ns.L["Pause"])
end

local function Build()
	local Style = ns.Style
	local host = DressUpFrame
	buttons = {}
	local function make(key, text, onClick, x)
		local b = Style.LineButton(host, text, nil, 22)
		b:SetPoint("TOPLEFT", host.ModelScene, "TOPLEFT", x, -8)
		b:SetFrameLevel(host.ModelScene:GetFrameLevel() + 10)
		b:SetScript("OnClick", onClick)
		buttons[key] = b
		return b
	end
	make("undress", ns.L["Undress"], function() DR.Undress() end, 8)
	make("tried", ns.L["Try-ons only"], function()
		DR.TriedOnly()
	end, 80)
	make("pause", ns.L["Pause"], function()
		DR.TogglePause()
		Refresh()
	end, 190)
end

local function Reset()
	for i = #tried, 1, -1 do
		tried[i] = nil
	end
	DR.paused = false
	Refresh()
end

function DR.Apply()
	local any = On("dressStrip") or On("dressAnim")
	if any and DressUpFrame and not installed.frame then
		installed.frame = true
		hooksecurefunc("DressUpVisualLink", function(_, link)
			if (On("dressStrip")) and type(link) == "string" then
				for _, have in ipairs(tried) do
					if have == link then
						return
					end
				end
				tried[#tried + 1] = link
			end
		end)
		hooksecurefunc("DressUpFrame_Show", function(_, _, forcePlayerRefresh)
			if forcePlayerRefresh then
				Reset()
			end
		end)
		DressUpFrame:HookScript("OnHide", Reset)
		Build()
	end
	Refresh()
end

function DR.Set(key, value)
	Settings()[key] = value and true or false
	DR.Apply()
end

ns.On("PLAYER_LOGIN", function()
	if On("dressStrip") or On("dressAnim") then
		DR.Apply()
	end
end)
