-- Minimal WoW client stub for headless tests (Lua 5.1). Only what CraftWise touches.
local stub = {}

local function noop() end
local frameMeta = {}
-- Unknown methods (Capitalised) are no-ops; unknown fields are nil, as on real frames.
frameMeta.__index = function(t, k)
	if frameMeta[k] then return frameMeta[k] end
	if type(k) == "string" and k:match("^%u") then return noop end
	return nil
end
function frameMeta.RegisterEvent(self, e) self.events[e] = true end
function frameMeta.UnregisterEvent(self, e) self.events[e] = nil end
function frameMeta.SetScript(self, name, fn) self.scripts[name] = fn end
function frameMeta.GetScript(self, name) return self.scripts[name] end
function frameMeta.Show(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function frameMeta.Hide(self) self.shown = false end
function frameMeta.IsShown(self) return self.shown ~= false end
function frameMeta.SetShown(self, v) if v then self:Show() else self:Hide() end end
function frameMeta.SetText(self, t) self.text = t end
function frameMeta.GetText(self) return self.text end
function frameMeta.GetChecked(self) return self.checked end
function frameMeta.SetChecked(self, v) self.checked = v end
local function widget() return setmetatable({ events = {}, scripts = {} }, frameMeta) end
function frameMeta.CreateFontString() return widget() end
function frameMeta.GetStringWidth() return 80 end
function frameMeta.GetFrameLevel() return 2 end
function frameMeta.CreateTexture() return widget() end

stub.frames = {}
function CreateFrame(_, name)
	local f = setmetatable({ events = {}, scripts = {} }, frameMeta)
	table.insert(stub.frames, f)
	if name then _G[name] = f end -- named frames become globals, as in the client
	return f
end

-- Fire a game event at every frame that registered it.
function stub.Fire(event, ...)
	for _, f in ipairs(stub.frames) do
		if f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

UIParent = widget()
Minimap = widget()
function Minimap.GetWidth() return 140 end
function Minimap.GetCenter() return 100, 100 end
function Minimap.GetEffectiveScale() return 1 end
function GetCursorPosition() return 150, 100 end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
GameTooltip = widget()
UISpecialFrames = {}
function IsShiftKeyDown() return false end

C_Timer = { After = function(_, fn) fn() end }
SlashCmdList = {}
print = print
time = os.time
Enum = { CraftingReagentType = { Basic = 1, Modifying = 2 } }

-- Items: [itemID] = { name, sellPrice }
stub.items = {}
function GetItemInfo(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	local item = stub.items[id]
	if not item then return nil end
	return item.name, item.link or ("item:" .. id), item.quality or 1, item.level or 1, item.minLevel or 1, "", "", 20,
		item.equipLoc or "", nil, item.sellPrice
end
C_Item = { GetItemInfo = GetItemInfo, RequestLoadItemDataByID = noop }
GetItemInfo = nil -- like the Forever client: only C_Item.GetItemInfo

-- Auctionator: stub.ah[itemID] = copper, stub.ahAge[itemID] = days
stub.ah, stub.ahAge = {}, {}
function stub.EnableAuctionator()
	Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(caller, id)
			assert(type(caller) == "string", "caller name required")
			return stub.ah[id]
		end,
		GetAuctionAgeByItemID = function(_, id) return stub.ahAge[id] end,
	} } }
end
function stub.DisableAuctionator() Auctionator = nil end

-- Profession window: stub.profession = { id, name, skill, max, recipes = { [id] = { info, schematic, source } } }
stub.profession = nil
C_TradeSkillUI = {
	IsTradeSkillLinked = function() return false end,
	IsTradeSkillGuild = function() return false end,
	GetBaseProfessionInfo = function()
		local p = stub.profession
		if not p then return nil end
		return { professionID = p.id, professionName = p.name, skillLevel = p.skill, maxSkillLevel = p.max }
	end,
	GetAllRecipeIDs = function()
		local ids = {}
		for id in pairs(stub.profession and stub.profession.recipes or {}) do table.insert(ids, id) end
		table.sort(ids)
		return ids
	end,
	GetRecipeInfo = function(id)
		local r = stub.profession.recipes[id]
		return r and r.info
	end,
	GetRecipeSchematic = function(id)
		local r = stub.profession.recipes[id]
		return r and r.schematic
	end,
	GetRecipeSourceText = function(id)
		local r = stub.profession.recipes[id]
		return r and r.source
	end,
}

-- Builds a schematic from { {itemID, qty}, ... } and output itemID/quantity range.
function stub.Schematic(reagents, outputID, qmin, qmax)
	local slots = {}
	for _, r in ipairs(reagents) do
		table.insert(slots, { reagentType = 1, quantityRequired = r[2], reagents = { { itemID = r[1] } } })
	end
	return { reagentSlotSchematics = slots, outputItemID = outputID, quantityMin = qmin or 1, quantityMax = qmax or qmin or 1 }
end

-- Merchant: stub.merchant = { { itemID, price, stack, extended } }
stub.merchant = {}
function GetMerchantNumItems() return #stub.merchant end
function GetMerchantItemID(i) return stub.merchant[i].itemID end
function GetMerchantItemInfo(i)
	local m = stub.merchant[i]
	return "item", nil, m.price, m.stack or 1, -1, true, true, m.extended
end

-- Trainer: stub.trainer = { { name, kind, fee, required, tooltipID } }; the list honours the type filter
stub.trainer = {}
stub.trainerFilter = { available = 1, unavailable = 1, used = 1 }
local function visibleServices()
	local out = {}
	for _, s in ipairs(stub.trainer) do
		if s.kind == "header" or stub.trainerFilter[s.kind] == 1 then out[#out + 1] = s end
	end
	return out
end
function GetTrainerServiceTypeFilter(t) return stub.trainerFilter[t] == 1 and 1 or nil end
function SetTrainerServiceTypeFilter(t, v) stub.trainerFilter[t] = v end
function GetNumTrainerServices() return #visibleServices() end
function GetTrainerServiceInfo(i) local s = visibleServices()[i]; return s.name, s.kind end
function GetTrainerServiceCost(i) return visibleServices()[i].fee end
function GetTrainerServiceSkillReq(i) return "Leatherworking", visibleServices()[i].required, true end
C_TooltipInfo = { GetTrainerService = function(i)
	local id = visibleServices()[i].tooltipID
	return id and { id = id } or nil
end }


-- Bags: stub.bags[bag][slot] = { itemID, stackCount, quality, isBound, hasNoValue }
stub.bags = {}
C_Container = {
	GetContainerNumSlots = function(bag) return stub.bags[bag] and #stub.bags[bag] or 0 end,
	GetContainerItemInfo = function(bag, slot) return stub.bags[bag] and stub.bags[bag][slot] end,
}
-- classID by itemID: stub.itemClass[id] = 2 weapon / 4 armor / 7 trade goods
stub.itemClass = {}
C_Item.GetItemInfoInstant = function(id)
	local item = stub.items[id]
	return id, nil, nil, item and item.equipLoc or "", item and item.icon, stub.itemClass[id]
end
C_Item.GetItemNameByID = function(id) return stub.items[id] and stub.items[id].name end

-- Time and the player's profession list (skill per skill line).
stub.now = 1000
function GetTime() return stub.now end
function GetProfessions()
	if stub.profession then return 1 end
end
function GetProfessionInfo(index)
	local p = stub.profession
	if index == 1 and p then
		return p.name, 136247, p.skill, p.max, 0, 0, p.id
	end
end

-- Equipment: stub.equipped[slotName] = itemID; item stats from stub.items[id].stats.
stub.equipped = {}
stub.level = 20
local SLOT_IDS = { HEADSLOT = 1, NECKSLOT = 2, SHOULDERSLOT = 3, SHIRTSLOT = 4, CHESTSLOT = 5, WAISTSLOT = 6,
	LEGSSLOT = 7, FEETSLOT = 8, WRISTSLOT = 9, HANDSSLOT = 10, FINGER0SLOT = 11, FINGER1SLOT = 12,
	TRINKET0SLOT = 13, TRINKET1SLOT = 14, BACKSLOT = 15, MAINHANDSLOT = 16, SECONDARYHANDSLOT = 17, RANGEDSLOT = 18 }
function GetInventorySlotInfo(name)
	local id = SLOT_IDS[name]
	if not id then error("bad slot") end
	return id
end
function GetInventoryItemID(_, slot)
	for name, id in pairs(SLOT_IDS) do
		if id == slot then return stub.equipped[name] end
	end
end
function UnitLevel() return stub.level end
C_Item.GetItemStats = function(link)
	local id = tonumber(tostring(link):match("item:(%d+)"))
	return id and stub.items[id] and stub.items[id].stats
end
stub.counts = {}
C_Item.GetItemCount = function(id) return stub.counts[id] or 0 end
stub.cantUse = {}
C_TooltipInfo.GetItemByID = function(id)
	return { lines = { { leftText = "x", leftColor = stub.cantUse[id] and { r = 1, g = 0.1, b = 0.1 } or { r = 1, g = 1, b = 1 } } } }
end

-- Sound: stub.sounds = list of { file, channel, handle, stopped }
stub.sounds = {}
stub.missingFiles = {}
function PlaySoundFile(file, channel)
	if stub.missingFiles[file] then return false, nil end
	local h = #stub.sounds + 1
	stub.sounds[h] = { file = file, channel = channel, handle = h }
	return true, h
end
function StopSound(h) if stub.sounds[h] then stub.sounds[h].stopped = true end end
-- Timers from NewTimer wait until a spec runs them: stub.RunTimers()
stub.timers = {}
C_Timer.NewTimer = function(_, fn)
	local t = { fn = fn }
	function t:Cancel() self.cancelled = true end
	table.insert(stub.timers, t)
	return t
end
function stub.RunTimers()
	local list = stub.timers
	stub.timers = {}
	for _, t in ipairs(list) do if not t.cancelled then t.fn() end end
end
stub.spells = {}
C_Spell = { GetSpellInfo = function(id) return stub.spells[id] and { name = stub.spells[id] } end }

stub.cvars = { Sound_DialogVolume = "1", Sound_EnableDialog = "1" }
C_CVar = { GetCVar = function(k) return stub.cvars[k] end, SetCVar = function(k, v) stub.cvars[k] = tostring(v) end }

-- Bag moves: picking up a slot puts it on the cursor; dropping on a slot swaps (as in the client).
stub.bagFamily = {}
C_Container.GetContainerNumFreeSlots = function(bag) return 0, stub.bagFamily[bag] or 0 end
stub.cursor = nil
C_Container.PickupContainerItem = function(bag, slot)
	stub.bags[bag] = stub.bags[bag] or {}
	if stub.cursor then
		local from = stub.cursor
		stub.cursor = nil
		local a, b = stub.bags[from.bag][from.slot], stub.bags[bag][slot]
		stub.bags[from.bag][from.slot], stub.bags[bag][slot] = b or false, a
	else
		stub.cursor = { bag = bag, slot = slot }
	end
end
function GetCursorInfo() return stub.cursor and "item" or nil end
function ClearCursor() stub.cursor = nil end

return stub
