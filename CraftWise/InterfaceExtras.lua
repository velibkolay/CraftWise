-- Interface › small ones (#321 part 5): a master volume slider on the minimap, a Wowhead link box and
-- "keep audio synced". Every switch is off by default (db.settings.interface: volumeSlider, wowheadLink,
-- audioSync); while off nothing is hooked, registered or built.
--
-- Built from Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`), nothing from another
-- addon:
--   Volume: Blizzard_SettingsDefinitions_Shared/Audio.lua sets the master volume with the CVar
--     Sound_MasterVolume, range 0 to 1, step 0.05 (volumeMinValue, volumeMaxValue, volumeStep);
--     Blizzard_SharedXML/Mainline/Sound.lua (AdjustMasterVolume) reads and writes the same CVar.
--     The slider sits on the minimap (at its bottom edge, inside it).
--   Wowhead link: the client has no clipboard API, so the URL is in a selectable edit box (Ctrl+C).
--     Item: the Item tooltip post call (TooltipDataProcessor.AddTooltipPostCall, data.id); quest: the
--     selected quest, C_QuestLog.SetSelectedQuest(questID), which QuestMapFrame_ShowQuestDetails calls
--     (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua).
--     URL: https://www.wowhead.com/forever/item=<id> and .../quest=<id>.
--   Keep audio synced: Audio.lua's output device option is the CVar Sound_OutputDriverIndex and it refreshes
--     on VOICE_CHAT_OUTPUT_DEVICES_UPDATED; SOUND_DEVICE_UPDATE is the sound event of SoundDocumentation.
--     On either event the CVar is set to its default (C_CVar.GetCVarDefault: the system's default device),
--     the same change the options dropdown makes. Blizzard's UI has no function that restarts the sound
--     system, so none is called; whether setting the CVar is enough is an in-game check.
local _, ns = ...

local X = {}
ns.InterfaceExtras = X

local installed = {}

local function Settings()
	local s = ns.db and ns.db.settings
	if not s then
		return {}
	end
	s.interface = s.interface or {}
	return s.interface
end

function X.Settings()
	return Settings()
end

local function On(key)
	return Settings()[key] == true
end

----------------------------------------------------------------------------------------------------
-- Volume
----------------------------------------------------------------------------------------------------

local VOL_MIN, VOL_MAX, VOL_STEP = 0, 1, 0.05

function X.Volume()
	return tonumber(C_CVar.GetCVar("Sound_MasterVolume")) or 1
end

function X.SetVolume(v)
	v = math.max(VOL_MIN, math.min(VOL_MAX, tonumber(v) or 1))
	v = math.floor(v / VOL_STEP + 0.5) * VOL_STEP
	C_CVar.SetCVar("Sound_MasterVolume", ("%.2f"):format(v))
	return v
end

local slider

local function BuildSlider()
	local Style = ns.Style
	slider = Style.Slider(Minimap, 110, VOL_MIN, VOL_MAX, VOL_STEP, function(v)
		X.SetVolume(v)
	end)
	slider:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 8)
	slider:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
	slider:SetScript("OnEnter", function(self)
		Style.ShowTip(self, ns.L["Master volume"], ns.L["Drag to change; the same setting as Options > Audio."])
	end)
	slider:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(_, delta)
		slider:SetValueQuietly(X.SetVolume(X.Volume() + delta * VOL_STEP))
	end)
end

local function RefreshSlider()
	if slider then
		slider:SetShown(On("volumeSlider"))
		slider:SetValueQuietly(X.Volume())
	end
end

-- The CVar changed somewhere else (the options, a key binding).
ns.On("CVAR_UPDATE", function(_, name)
	if name == "Sound_MasterVolume" and On("volumeSlider") then
		RefreshSlider()
	end
end)

----------------------------------------------------------------------------------------------------
-- Wowhead link
----------------------------------------------------------------------------------------------------

function X.WowheadURL(kind, id)
	id = tonumber(id)
	if not id or (kind ~= "item" and kind ~= "quest") then
		return nil
	end
	return ("https://www.wowhead.com/forever/%s=%d"):format(kind, id)
end

local box

local function BuildBox()
	local Style = ns.Style
	local C = Style.C
	box = CreateFrame("Frame", "CraftWiseWowheadLink", UIParent)
	box:SetSize(360, 46)
	box:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
	box:SetFrameStrata("MEDIUM")
	box.sheet = Style.Sheet(box, C.sheet, C.flap, 10, true)
	box.label = Style.Text(box, "Caption", "text3")
	box.label:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -7)
	box.label:SetPoint("TOPRIGHT", box, "TOPRIGHT", -34, -7)
	box.label:SetJustifyH("LEFT")
	box.edit = CreateFrame("EditBox", nil, box)
	box.edit:SetAutoFocus(false)
	box.edit:SetFontObject(Style.Fonts.Small)
	box.edit:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	box.edit:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 7)
	box.edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 7)
	box.edit:SetHeight(18)
	-- Selectable, not editable: whatever is typed, the URL comes back.
	box.edit:SetScript("OnTextChanged", function(self)
		if self:GetText() ~= box.url then
			self:SetText(box.url or "")
		end
	end)
	box.edit:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box.edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box.close = Style.LineButton(box, "x", 20, 20)
	box.close:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
	box.close:SetScript("OnClick", function()
		box:Hide()
	end)
	box:Hide()
end

-- Shows the link for a thing: kind "item" | "quest", its id and a name for the label.
function X.ShowLink(kind, id, name)
	if not On("wowheadLink") then
		return nil
	end
	local url = X.WowheadURL(kind, id)
	if not url then
		return nil
	end
	if not box then
		BuildBox()
	end
	box.url = url
	box.label:SetText("Wowhead · " .. (kind == "quest" and ns.L["Quest"] or ns.L["Item"]) .. (name and (" · " .. name) or ""))
	box.edit:SetText(url)
	box:Show()
	return url
end

local function OnItemTooltip(tooltip, data)
	if tooltip == GameTooltip and data and data.id and On("wowheadLink") then
		local name = ns.ItemInfoNow(data.id)
		X.ShowLink("item", data.id, name)
	end
end

local function OnQuestSelected(questID)
	if questID and questID ~= 0 and On("wowheadLink") then
		X.ShowLink("quest", questID, C_QuestLog.GetTitleForQuestID(questID))
	end
end

local function HookLink()
	if installed.link then
		return
	end
	installed.link = true
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	end
	if C_QuestLog and C_QuestLog.SetSelectedQuest then
		hooksecurefunc(C_QuestLog, "SetSelectedQuest", OnQuestSelected)
	end
end

----------------------------------------------------------------------------------------------------
-- Keep audio synced
----------------------------------------------------------------------------------------------------

local sync

-- The output device changed: set the device option to its default again (the system's default device).
function X.SyncAudio()
	if not On("audioSync") then
		return false
	end
	if (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown()) then
		return false -- never in the middle of a cinematic
	end
	local default = C_CVar.GetCVarDefault("Sound_OutputDriverIndex")
	if default == nil then
		return false
	end
	C_CVar.SetCVar("Sound_OutputDriverIndex", default)
	return true
end

local function HookSync()
	if not sync then
		sync = CreateFrame("Frame")
		sync:SetScript("OnEvent", function()
			X.SyncAudio()
		end)
	end
	sync:RegisterEvent("VOICE_CHAT_OUTPUT_DEVICES_UPDATED")
	sync:RegisterEvent("SOUND_DEVICE_UPDATE")
end

----------------------------------------------------------------------------------------------------

function X.Apply()
	if On("volumeSlider") and not slider and Minimap then
		BuildSlider()
	end
	RefreshSlider()
	if On("wowheadLink") then
		HookLink()
	elseif box then
		box:Hide()
	end
	if On("audioSync") then
		HookSync()
	elseif sync then
		sync:UnregisterAllEvents()
	end
end

function X.Set(key, value)
	Settings()[key] = value and true or false
	X.Apply()
end

ns.On("PLAYER_LOGIN", function()
	if On("volumeSlider") or On("wowheadLink") or On("audioSync") then
		X.Apply()
	end
end)
