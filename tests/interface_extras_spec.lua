-- Interface › small ones (#321 part 5): volume slider and the Wowhead link box.
local function setup()
	local ns, stub = LoadAddon()
	local hooks = { secure = 0, post = 0 }
	local orig = hooksecurefunc
	function hooksecurefunc(...) hooks.secure = hooks.secure + 1; return orig(...) end
	TooltipDataProcessor = { AddTooltipPostCall = function() hooks.post = hooks.post + 1 end }
	Enum.TooltipDataType = { Item = 0, Unit = 2 }
	C_QuestLog = { SetSelectedQuest = function() end, GetTitleForQuestID = function(id) return "Test Quest " .. id end }
	stub.cvars.Sound_MasterVolume = "0.50"
	return ns, stub, hooks
end

local function questLog()
	QuestMapFrame = CreateFrame("Frame", "QuestMapFrame")
	QuestMapFrame.DetailsFrame = CreateFrame("Frame", nil, QuestMapFrame)
	return QuestMapFrame
end

it("interface extras: off builds, hooks and registers nothing", function()
	local ns, _, hooks = setup()
	questLog()
	ns.InterfaceExtras.Apply()
	eq(hooks.secure, 0); eq(hooks.post, 0)
	eq(CraftWiseWowheadLink, nil)
	eq(QuestMapFrame.hooks, nil)
	assert(not table.concat(ns.ItemMenuRows(false, false), ","):find("wowhead", 1, true), "no menu entry")
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

it("interface extras: the box opens only from a click: the item menu entry and the quest button; no tooltip or quest hook", function()
	local ns, _, hooks = setup()
	local X = ns.InterfaceExtras
	questLog()
	eq(X.ShowLink("item", 2318), nil, "off: nothing")
	X.Set("wowheadLink", true)
	eq(hooks.post, 0, "no tooltip post call"); eq(hooks.secure, 0, "no hook on C_QuestLog")
	eq(CraftWiseWowheadLink, nil, "nothing opens by itself")
	-- item menu: the entry is listed only with the switch on, and opens the box for that item
	local keys = table.concat(ns.ItemMenuRows(false, false), ",")
	assert(keys:find("history,wowhead,watch", 1, true), keys)
	ns.ShowItemMenu(2318)
	CraftWiseItemMenu.buttons.wowhead.scripts.OnClick(CraftWiseItemMenu.buttons.wowhead)
	eq(CraftWiseWowheadLink.url, "https://www.wowhead.com/forever/item=2318")
	eq(CraftWiseWowheadLink.edit.text, "https://www.wowhead.com/forever/item=2318")
end)

it("interface extras: the quest button opens the box for the shown quest and the box goes with the quest log", function()
	local ns, stub = setup()
	local X = ns.InterfaceExtras
	questLog()
	X.Set("wowheadLink", true)
	local button
	for _, f in ipairs(stub.frames) do
		if f.parent == QuestMapFrame.DetailsFrame and f.scripts.OnClick then button = f end
	end
	assert(button, "quest button")
	QuestMapFrame.DetailsFrame.questID = 777
	button.scripts.OnClick(button)
	eq(CraftWiseWowheadLink.url, "https://www.wowhead.com/forever/quest=777")
	eq(CraftWiseWowheadLink.shown, true)
	-- typing does not change the URL
	CraftWiseWowheadLink.edit.text = "typed"
	CraftWiseWowheadLink.edit.scripts.OnTextChanged(CraftWiseWowheadLink.edit)
	eq(CraftWiseWowheadLink.edit.text, "https://www.wowhead.com/forever/quest=777")
	-- the quest log closes: the box for a quest goes; one for an item stays
	QuestMapFrame.hooks.OnHide[1](QuestMapFrame)
	eq(CraftWiseWowheadLink.shown, false)
	X.ShowLink("item", 2318)
	QuestMapFrame.hooks.OnHide[1](QuestMapFrame)
	eq(CraftWiseWowheadLink.shown, true)
	X.Set("wowheadLink", false)
	eq(CraftWiseWowheadLink.shown, false); eq(button.shown, false)
end)
