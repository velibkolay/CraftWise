-- Fast auto-loot (issue #41). When auto-loot applies, a loot window is recorded first (SourceRecorder.lua, so
-- a dropped recipe is never lost) and then looted slot by slot with LootSlot, without Blizzard's loot
-- animation. It acts only on a window the player opened by clicking (LOOT_READY): no input automation.
--
--   * Whether auto-loot applies is the client's own decision, taken at click time: the `autoloot` payload of
--     LOOT_READY (bool, Nilable = false in Blizzard's Forever API docs). Recomputing it at LOOT_READY is wrong
--     when the player has already let go of Shift by then (#57). Only when the payload is missing does this
--     file fall back to the rule itself: auto-loot setting (CVar autoLootDefault) XOR the auto-loot toggle
--     modifier held (Shift by default), the same rule as Blizzard's Settings panel.
--   * Bind-on-pickup items are looted with LootSlot like any other; the client then asks (LOOT_BIND_CONFIRM) and
--     Blizzard's dialog handles it. This file never confirms anything.
--   * Locked slots (group loot rolls, master loot) are not touched; with a master looter this file does nothing.
--   * No free bag slot: items are left in the window, coins and currency are still taken, one message names
--     what is left. The same message appears once if the client reports a full bag part-way.
--   * Switched off (Settings, "Fast auto-loot") or while another auto-loot addon is loaded, so two addons never
--     loot at once. Then the window opens as usual and SourceRecorder records on LOOT_OPENED.
local _, ns = ...

local Loot = {}
ns.Loot = Loot

-- Addons that loot by themselves. Compared by the folder name the client reports as loaded.
Loot.OTHER_ADDONS = { "SpeedyAutoLoot", "Speedy_AutoLoot", "FastLoot", "FasterLoot", "QuickAutoLoot", "AutoLootPlus" }

local MAX_NAMED = 3

local function Settings()
	return ns.db and ns.db.settings
end

function Loot.Enabled()
	local s = Settings()
	return not s or s.fastLoot ~= false
end

function Loot.SetEnabled(on)
	local s = Settings()
	if s then
		s.fastLoot = on and true or false
	end
end

-- The loaded addon that already auto-loots, or nil.
function Loot.Conflict()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded) then
		return nil
	end
	for _, name in ipairs(Loot.OTHER_ADDONS) do
		if C_AddOns.IsAddOnLoaded(name) then
			return name
		end
	end
end

-- Does auto-loot apply to this window? Setting XOR toggle modifier, read now. Only the fallback for a
-- LOOT_READY without its `autoloot` payload: by the time the event fires the modifier may already be released.
function Loot.AutoLootApplies()
	local setting = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("autoLootDefault") or false
	local modifier = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") or false
	return (setting and true or false) ~= (modifier and true or false)
end

-- Is CraftWise the one that loots this window? Prints the one-time note when another addon takes over.
function Loot.Active()
	if not Loot.Enabled() then
		return false
	end
	local other = Loot.Conflict()
	if other then
		local s = Settings()
		if s and s.fastLootNoted ~= other then
			s.fastLootNoted = other
			ns.Print(("Fast auto-loot is off while %s is loaded, so only one addon loots. Disable one of them."):format(other))
		end
		return false
	end
	return true
end

local function IsMasterLoot()
	local method = C_PartyInfo and C_PartyInfo.GetLootMethod and C_PartyInfo.GetLootMethod()
	local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
	return master ~= nil and method == master
end

local function FreeSlots()
	local free = 0
	for bag = 0, ns.LAST_BAG or 5 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

-- What is still in the window: item names (coins and currency have no link), and how many slots.
local function Remaining()
	local names = {}
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		if link then
			names[#names + 1] = link:match("%[(.-)%]") or link
		end
	end
	return names
end

local warned = false

local function WarnFull()
	if warned then
		return
	end
	warned = true
	local names = Remaining()
	local text = "Bags are full."
	if #names > 0 then
		local shown = {}
		for i = 1, math.min(#names, MAX_NAMED) do
			shown[i] = names[i]
		end
		text = text .. " Left in the loot window: " .. table.concat(shown, ", ")
		if #names > MAX_NAMED then
			text = text .. (" and %d more"):format(#names - MAX_NAMED)
		end
		text = text .. "."
	end
	ns.Print(text)
end

local busy = false

-- autoloot: LOOT_READY's payload, the client's decision at click time (#57).
local function OnReady(_, autoloot)
	-- Fishing log (#69): read the window before anything can leave it, whoever loots it.
	if ns.Fishing and ns.Fishing.Capture then
		ns.Fishing.Capture()
	end
	if autoloot == nil then
		autoloot = Loot.AutoLootApplies()
	end
	if busy or not Loot.Active() or not autoloot or IsMasterLoot() then
		return
	end
	if not (GetNumLootItems and GetLootSlotInfo and LootSlot) then
		return
	end
	busy, warned = true, false
	-- 1. Record before anything leaves the window.
	if ns.Sources and ns.Sources.RecordLoot then
		ns.Sources.RecordLoot()
	end
	-- 2. Loot. Last slot first: slots keep their index until the window closes, this is just the usual order.
	local full = FreeSlots() == 0
	local skipped = false
	for slot = GetNumLootItems(), 1, -1 do
		local texture, _, _, currencyID, _, locked, _, _, _, isCoin = GetLootSlotInfo(slot)
		if texture and not locked then
			if full and not (isCoin or currencyID) then
				skipped = true
			else
				LootSlot(slot)
			end
		end
	end
	if skipped then
		WarnFull()
	end
end

ns.On("LOOT_READY", OnReady)
ns.On("LOOT_CLOSED", function()
	busy = false
end)
ns.On("UI_ERROR_MESSAGE", function(_, _, message)
	if busy and not warned and ERR_INV_FULL and not (issecretvalue and issecretvalue(message)) and message == ERR_INV_FULL then
		WarnFull()
	end
end)

ns.Listen("DB_READY", function()
	local s = Settings()
	if s and s.fastLoot == nil then
		s.fastLoot = true
	end
end)
