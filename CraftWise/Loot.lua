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
--   * Bags full (#352): the message also says how to free a slot, in this order: stack two partial stacks of one
--     item into fewer slots, else delete the cheapest slot of an item YOU marked Junk, or an unmarked grey one (vendor price x count,
--     prices from the client only; an item whose price is not loaded is left out; no price at all = worth 0 and
--     first; Keep, quest items, the reagent bag, the bank and special bags are never touched). A small panel
--     shows it with one button. Nothing moves or deletes without a click, one item per click; deleting asks
--     first in CraftWise's own confirm dialog (item, count, value). DeleteCursorItem is a restricted function
--     (hardware event, `restricted` in tests/forever_api.lua) and is called in exactly one place, that dialog's
--     OnAccept path, the way Blizzard's DELETE_ITEM dialog does (Blizzard_StaticPopup_Game/GameDialogDefs.lua,
--     branch forever). Settings > Bags and loot > "Suggest a junk item to delete when bags are full".
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

----------------------------------------------------------------------------------------------------
-- Bags full (#352): what to do about it
----------------------------------------------------------------------------------------------------

local NUM_BAGS = 4 -- backpack and the four bag slots; the reagent bag (5) and every special bag stay out

function Loot.SuggestEnabled()
	local s = Settings()
	return not s or s.junkSuggest ~= false
end

function Loot.SetSuggestEnabled(on)
	local s = Settings()
	if s then
		s.junkSuggest = on and true or false
	end
end

local function PlainBag(bag)
	if bag == 0 then
		return true
	end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	return family == 0
end

-- Free slots of the plain bags (the ones a suggestion can touch).
function Loot.PlainFree()
	local free = 0
	for bag = 0, NUM_BAGS do
		if PlainBag(bag) then
			free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		end
	end
	return free
end

-- Every filled slot of the plain bags: { bag, slot, itemID, count, locked }.
function Loot.Scan()
	local slots = {}
	for bag = 0, NUM_BAGS do
		if PlainBag(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				local item = C_Container.GetContainerItemInfo(bag, slot)
				if item and item.itemID then
					slots[#slots + 1] = { bag = bag, slot = slot, itemID = item.itemID, count = item.stackCount or 1,
						locked = item.isLocked, quality = item.quality }
				end
			end
		end
	end
	return slots
end

local function ItemName(itemID)
	return (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. tostring(itemID))
end

local function MaxStack(itemID)
	local max = C_Item.GetItemInfo and select(8, C_Item.GetItemInfo(itemID))
	return type(max) == "number" and max or nil
end

local function IsQuest(itemID)
	return C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID)) == 12
end

-- Junk for this suggestion (Veli, #352): an item marked Junk, or a grey (poor quality) item nobody marked.
-- An explicit mark wins: Keep or Sell on AH is never suggested ("Normal" clears marks, so it reads as unmarked).
-- Quest items never qualify.
local function Qualifies(itemID, quality)
	local db = ns.db
	if not db or (db.keep and db.keep[itemID]) or IsQuest(itemID) then
		return false
	end
	if db.junk and db.junk[itemID] then
		return true
	end
	return quality == 0 and not (db.sellAH and db.sellAH[itemID])
end

local function Coins(copper)
	return ns.FormatMoney(copper, true)
end

-- Two partial stacks of one item that fit into fewer slots: the smallest moves onto the largest one with room.
-- { kind = "merge", itemID, name, before, after, from = {bag, slot}, to = {bag, slot}, text, button }
local function MergePlan(slots)
	local partial, ids = {}, {}
	for _, s in ipairs(slots) do
		local max = MaxStack(s.itemID)
		if max and max > 1 and s.count < max and not s.locked then
			if not partial[s.itemID] then
				partial[s.itemID] = { max = max }
				ids[#ids + 1] = s.itemID
			end
			table.insert(partial[s.itemID], s)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local list = partial[id]
		if #list >= 2 then
			local total = 0
			for _, s in ipairs(list) do
				total = total + s.count
			end
			local after = math.ceil(total / list.max)
			if after < #list then
				table.sort(list, function(a, b)
					if a.count ~= b.count then
						return a.count < b.count
					end
					return a.bag * 1000 + a.slot < b.bag * 1000 + b.slot
				end)
				local from, to = list[1], list[#list]
				local name = ItemName(id)
				return { kind = "merge", itemID = id, name = name, before = #list, after = after,
					from = { bag = from.bag, slot = from.slot }, to = { bag = to.bag, slot = to.slot },
					text = ("Stack %s: %d slots -> %d"):format(name, #list, after), button = "Stack" }
			end
		end
	end
end

-- The cheapest slot of an item marked Junk. Prices come from the client (ns.GetVendorSellPrice); an item whose
-- price is not loaded yet is left out (the call requests it). Price 0 = worth 0, first. Ties: fewer items
-- first (a partial stack before a full one), then item, bag, slot. Second result: how many wait for a price.
local function Order(c)
	return c.bag * 1000 + c.slot
end

local function DeletePlan(slots, lootValue)
	local best, pending = nil, 0
	for _, s in ipairs(slots) do
		if Qualifies(s.itemID, s.quality) and not s.locked then
			local each = ns.GetVendorSellPrice(s.itemID)
			if each == nil then
				pending = pending + 1
			else
				local c = { bag = s.bag, slot = s.slot, itemID = s.itemID, count = s.count, value = each * s.count,
					noPrice = each == 0 }
				if not best or c.value < best.value
					or (c.value == best.value and (c.count < best.count
						or (c.count == best.count and (c.itemID < best.itemID
							or (c.itemID == best.itemID and Order(c) < Order(best)))))) then
					best = c
				end
			end
		end
	end
	if not best then
		return nil, pending
	end
	best.kind, best.name = "delete", ItemName(best.itemID)
	best.text = ("Delete %s x%d (%s)"):format(best.name, best.count,
		best.noPrice and "no vendor price, worth nothing" or ("worth " .. Coins(best.value)))
	best.button = "Delete..."
	if lootValue and lootValue < best.value then
		best.notWorth = true
		best.text = best.text .. ": not worth it, the loot is worth less (" .. Coins(lootValue) .. ")"
	end
	best.lootValue = lootValue
	return best, pending
end

-- What to suggest now, or nil: a merge first (loses nothing), else the cheapest Junk slot. lootValue: copper
-- value of what did not fit, when known.
function Loot.Suggest(lootValue)
	if not Loot.SuggestEnabled() or not (C_Container and C_Container.GetContainerNumSlots) then
		return nil
	end
	local slots = Loot.Scan()
	return MergePlan(slots) or (DeletePlan(slots, lootValue))
end

----------------------------------------------------------------------------------------------------
-- Acting on it: one click, one item
----------------------------------------------------------------------------------------------------

local function InCombat()
	return UnitAffectingCombat and UnitAffectingCombat("player") and true or false
end

local function Cursor()
	return GetCursorInfo and GetCursorInfo() and true or false
end

local panel

local function HidePanel()
	if panel then
		panel:Hide()
	end
end

-- Stack: moves the smallest partial stack onto the other, checked first. Only from a button's click.
function Loot.Merge(plan)
	if not plan or plan.kind ~= "merge" then
		return false
	end
	if InCombat() or Cursor() then
		ns.Print("Can't stack right now (combat, or an item is on the cursor).")
		return false
	end
	local a = C_Container.GetContainerItemInfo(plan.from.bag, plan.from.slot)
	local b = C_Container.GetContainerItemInfo(plan.to.bag, plan.to.slot)
	if not (a and b and a.itemID == plan.itemID and b.itemID == plan.itemID and not a.isLocked and not b.isLocked) then
		ns.Print("The bags changed, nothing was moved.")
		return false
	end
	C_Container.PickupContainerItem(plan.from.bag, plan.from.slot)
	C_Container.PickupContainerItem(plan.to.bag, plan.to.slot)
	if Cursor() then
		ClearCursor()
	end
	HidePanel()
	ns.Notify("BAGS_CHANGED")
	return true
end

local function EnsureDialog()
	if not StaticPopupDialogs or StaticPopupDialogs["CRAFTWISE_DELETE_JUNK"] then
		return
	end
	StaticPopupDialogs["CRAFTWISE_DELETE_JUNK"] = {
		text = "CraftWise: delete %s (%s)? This cannot be undone.",
		button1 = ACCEPT or "Accept",
		button2 = CANCEL or "Cancel",
		-- The only way to a delete: the click on this dialog's button (a hardware event).
		OnAccept = function(_, data)
			Loot.Delete(data and data.plan)
		end,
		timeout = 0,
		exclusive = 1,
		hideOnEscape = 1,
		showAlert = 1,
	}
end
EnsureDialog()

-- The button's click: shows the confirm dialog naming the item, the count and the value. Deletes nothing.
function Loot.RequestDelete(plan)
	if not plan or plan.kind ~= "delete" or not StaticPopup_Show then
		return false
	end
	if InCombat() then
		ns.Print("Can't delete in combat.")
		return false
	end
	EnsureDialog()
	local value = plan.noPrice and "no vendor price, worth nothing" or ("worth " .. Coins(plan.value))
	StaticPopup_Show("CRAFTWISE_DELETE_JUNK", ("%s x%d"):format(plan.name, plan.count), value, { plan = plan })
	return true
end

-- Runs from the dialog's OnAccept only. Re-checks the slot, then picks it up and deletes it.
function Loot.Delete(plan)
	if not plan or plan.kind ~= "delete" then
		return false
	end
	local item = C_Container.GetContainerItemInfo(plan.bag, plan.slot)
	if not (item and item.itemID == plan.itemID and (item.stackCount or 1) == plan.count and not item.isLocked
		and Qualifies(plan.itemID, item.quality)) then
		ns.Print("The bags changed, nothing was deleted.")
		return false
	end
	if InCombat() or Cursor() then
		ns.Print("Nothing deleted (combat, or an item is on the cursor).")
		return false
	end
	C_Container.PickupContainerItem(plan.bag, plan.slot)
	if not Cursor() then
		return false
	end
	DeleteCursorItem()
	if Cursor() then
		ClearCursor()
	end
	ns.Print(("Deleted %s x%d."):format(plan.name, plan.count))
	HidePanel()
	ns.Notify("BAGS_CHANGED")
	return true
end

-- What a button does: stack, or ask before deleting.
function Loot.Click(plan)
	if not plan then
		return false
	end
	if plan.kind == "merge" then
		return Loot.Merge(plan)
	end
	return Loot.RequestDelete(plan)
end

----------------------------------------------------------------------------------------------------
-- The small panel (Origami, like the loot toast)
----------------------------------------------------------------------------------------------------

local function BuildPanel()
	if panel then
		return panel
	end
	local Style = ns.Style
	local C = Style.C
	panel = CreateFrame("Frame", "CraftWiseBagFull", UIParent)
	panel:SetFrameStrata("HIGH")
	panel:SetSize(340, 86)
	panel:SetPoint("CENTER", UIParent, "CENTER", 300, 20)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel.sheet = Style.Sheet(panel, C.sheet, C.flap, 8, true)
	panel.title = Style.Text(panel, "BodyBold", "text")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText("Bags are full")
	panel.body = Style.Text(panel, "Body", "text2")
	panel.body:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
	panel.body:SetWidth(316)
	panel.body:SetJustifyH("LEFT")
	panel.act = Style.ActionButton(panel, "Delete...", 110, 22)
	panel.act:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
	panel.act:SetScript("OnClick", function()
		Loot.Click(panel.plan)
	end)
	panel.close = Style.LineButton(panel, "Dismiss", 70, 22)
	panel.close:SetPoint("RIGHT", panel.act, "LEFT", -8, 0)
	panel.close:SetScript("OnClick", HidePanel)
	return panel
end

function Loot.ShowPanel(plan)
	if not (plan and CreateFrame and ns.Style) then
		return
	end
	BuildPanel()
	panel.plan = plan
	panel.body:SetText(plan.text)
	panel.act:SetLabel(plan.button)
	panel:Show()
end

function Loot.PanelPlan()
	return panel and panel:IsShown() and panel.plan or nil
end

-- The suggestion for the moment the client said "full": shows the panel and returns the text for the chat
-- line. Called by the full-bag message only, never by a timer.
function Loot.Announce(lootValue)
	local plan = Loot.Suggest(lootValue)
	if plan then
		Loot.ShowPanel(plan)
		return plan.text
	end
end

-- Closes the panel once a slot frees up by other means.
ns.On("BAG_UPDATE_DELAYED", function()
	if panel and panel:IsShown() and Loot.PlainFree() > 0 then
		HidePanel()
	end
end)

-- What is left in the window is worth this much (copper), or nil when any item has no known value: no
-- comparison on a guess.
local function LeftValue()
	local total = 0
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		if link then
			local itemID = tonumber(link:match("item:(%d+)"))
			local quantity = select(3, GetLootSlotInfo(slot)) or 1
			local v = itemID and ns.GetSellValue and ns.GetSellValue(itemID)
			if not (v and v.copper) then
				return nil
			end
			total = total + v.copper * quantity
		end
	end
	return total
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
	local suggestion = Loot.Announce(LeftValue())
	if suggestion then
		text = text .. " " .. suggestion .. "."
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
	-- Loot feed (#135): a container's slots are read before they are looted.
	if ns.LootFeed and ns.LootFeed.Capture then
		ns.LootFeed.Capture()
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
	if ERR_INV_FULL and not (issecretvalue and issecretvalue(message)) and message == ERR_INV_FULL then
		if busy then
			if not warned then
				WarnFull()
			end
		elseif Loot.PlainFree() == 0 and not Loot.PanelPlan() then
			-- Buying, mail or a window we did not auto-loot (#352): the same suggestion, once per message.
			local suggestion = Loot.Announce(nil)
			if suggestion then
				ns.Print("Bags are full. " .. suggestion .. ".")
			end
		end
	end
end)

ns.Listen("DB_READY", function()
	local s = Settings()
	if s and s.fastLoot == nil then
		s.fastLoot = true
	end
end)
