-- Interface › small ones (#321 part 5): volume slider, Wowhead link, keep audio synced.
local function setup()
	local ns, stub = LoadAddon()
	local hooks = { secure = 0, post = 0 }
	local orig = hooksecurefunc
	function hooksecurefunc(...) hooks.secure = hooks.secure + 1; return orig(...) end
	TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) hooks.post = hooks.post + 1; hooks.item = fn end }
	Enum.TooltipDataType = { Item = 0, Unit = 2 }
	C_CVar.GetCVarDefault = function(k) return k == "Sound_OutputDriverIndex" and "0" or nil end
	C_QuestLog = { SetSelectedQuest = function() end, GetTitleForQuestID = function(id) return "Test Quest " .. id end }
	stub.cvars.Sound_MasterVolume = "0.50"
	stub.cvars.Sound_OutputDriverIndex = "3"
	return ns, stub, hooks
end

it("interface extras: off builds, hooks and registers nothing", function()
	local ns, stub, hooks = setup()
	ns.InterfaceExtras.Apply()
	eq(hooks.secure, 0); eq(hooks.post, 0)
	eq(CraftWiseWowheadLink, nil)
	eq(ns.InterfaceExtras.SyncAudio(), false)
	eq(stub.cvars.Sound_OutputDriverIndex, "3")
end)

it("interface extras: volume reads and writes Sound_MasterVolume in steps of 0.05, kept to 0..1", function()
	local ns, stub = setup()
	local X = ns.InterfaceExtras
	X.Set("volumeSlider", true)
	eq(X.Volume(), 0.5)
	eq(X.SetVolume(0.73), 0.75); eq(stub.cvars.Sound_MasterVolume, "0.75")
	X.SetVolume(2); eq(stub.cvars.Sound_MasterVolume, "1.00")
	X.SetVolume(-1); eq(stub.cvars.Sound_MasterVolume, "0.00")
end)

it("interface extras: the Wowhead URL format", function()
	local ns = setup()
	local X = ns.InterfaceExtras
	eq(X.WowheadURL("item", 2318), "https://www.wowhead.com/forever/item=2318")
	eq(X.WowheadURL("quest", 123), "https://www.wowhead.com/forever/quest=123")
	eq(X.WowheadURL("npc", 5), nil, "only items and quests")
	eq(X.WowheadURL("item", "x"), nil)
end)

it("interface extras: the link box follows the hovered item and the selected quest", function()
	local ns, stub, hooks = setup()
	local X = ns.InterfaceExtras
	X.Set("wowheadLink", true)
	eq(hooks.post, 1)
	hooks.item(GameTooltip, { id = 2318 })
	eq(CraftWiseWowheadLink.url, "https://www.wowhead.com/forever/item=2318")
	eq(CraftWiseWowheadLink.edit.text, "https://www.wowhead.com/forever/item=2318")
	C_QuestLog.SetSelectedQuest(777)
	eq(CraftWiseWowheadLink.url, "https://www.wowhead.com/forever/quest=777")
	-- typing in the box does not change the URL
	CraftWiseWowheadLink.edit.text = "typed"
	CraftWiseWowheadLink.edit.scripts.OnTextChanged(CraftWiseWowheadLink.edit)
	eq(CraftWiseWowheadLink.edit.text, "https://www.wowhead.com/forever/quest=777")
	X.Set("wowheadLink", false)
	eq(CraftWiseWowheadLink.shown, false)
	C_QuestLog.SetSelectedQuest(5)
	eq(CraftWiseWowheadLink.url, "https://www.wowhead.com/forever/quest=777", "off: no longer follows")
end)

it("interface extras: audio synced sets the device option to its default on a device event, not in a cinematic", function()
	local ns, stub = setup()
	local X = ns.InterfaceExtras
	X.Set("audioSync", true)
	stub.Fire("VOICE_CHAT_OUTPUT_DEVICES_UPDATED")
	eq(stub.cvars.Sound_OutputDriverIndex, "0")
	stub.cvars.Sound_OutputDriverIndex = "3"
	CinematicFrame = { IsShown = function() return true end }
	eq(X.SyncAudio(), false); eq(stub.cvars.Sound_OutputDriverIndex, "3")
	CinematicFrame = nil
	X.Set("audioSync", false)
	stub.Fire("SOUND_DEVICE_UPDATE")
	eq(stub.cvars.Sound_OutputDriverIndex, "3", "off: events ignored")
end)
