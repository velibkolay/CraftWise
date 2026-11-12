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
function frameMeta.SetTexture(self, t) self.texture = t end
function frameMeta.SetText(self, t) self.text = t end
function frameMeta.GetText(self) return self.text end
function frameMeta.GetChecked(self) return self.checked end
function frameMeta.SetChecked(self, v) self.checked = v end
local function widget() return setmetatable({ events = {}, scripts = {} }, frameMeta) end
function frameMeta.CreateFontString() return widget() end
function frameMeta.GetStringWidth() return 80 end
function frameMeta.GetFrameLevel() return 2 end
function frameMeta.CreateTexture() return widget() end
-- Anchors and sizes are recorded so specs can work out where a region sits (tests/style_spec.lua).
function frameMeta.SetPoint(self, ...)
	self.lastPoint = { ... }
	self.points = self.points or {}
	table.insert(self.points, { ... })
end
function frameMeta.ClearAllPoints(self) self.points = {} end
function frameMeta.SetAllPoints(self, rel) self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } } end
function frameMeta.SetSize(self, w, h) self.width, self.height = w, h end
function frameMeta.SetWidth(self, w) self.width = w end
function frameMeta.SetHeight(self, h) self.height = h end
function frameMeta.SetVertexColor(self, r, g, b, a) self.vertexColor = { r, g, b, a } end
function frameMeta.SetTextColor(self, r, g, b, a) self.textColor = { r, g, b, a } end
function frameMeta.SetFont(self, path, size, flags) self.font = { path, size, flags } end
function frameMeta.GetFont(self) if self.font then return unpack(self.font) end end
function frameMeta.SetFontObject(self, f) self.fontObject = f end
function frameMeta.SetAlpha(self, a) self.alpha = a end
-- Mouse over a frame: specs set f.mouseOver.
function frameMeta.IsMouseOver(self) return self.mouseOver == true end
function frameMeta.SetDesaturated(self, v) self.desaturated = v and true or false end
function frameMeta.IsDesaturated(self) return self.desaturated == true end
function frameMeta.Disable(self) self.disabled = true end
function frameMeta.Enable(self) self.disabled = false end
function frameMeta.IsEnabled(self) return self.disabled ~= true end
-- Combat: stub.inCombat
function UnitAffectingCombat() return stub.inCombat == true end

-- Font objects (CreateFont): named ones become globals, as in the client.
function CreateFont(name)
	local f = widget()
	f.name = name
	if name then _G[name] = f end
	return f
end

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
date = os.date
-- hooksecurefunc([table,] name, hook): the hook runs after the original with the same arguments.
function hooksecurefunc(t, name, hook)
	if type(t) == "string" then t, name, hook = _G, t, name end
	local orig = t[name]
	t[name] = function(...)
		local r = { orig(...) }
		hook(...)
		return unpack(r)
	end
end
-- Money: stub.money (copper).
stub.money = 0
function GetMoney() return stub.money end
Enum = { CraftingReagentType = { Basic = 1, Modifying = 2 }, BagIndex = { ReagentBag = 5 } }

-- Items: [itemID] = { name, sellPrice }
stub.items = {}
function GetItemInfo(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	local item = stub.items[id]
	if not item then return nil end
	return item.name, item.link or ("item:" .. id), item.quality or 1, item.level or 1, item.minLevel or 1, "", "", 20,
		item.equipLoc or "", nil, item.sellPrice, item.classID, item.subClassID, item.bindType
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

stub.schematics = {} -- [recipe spellID] = schematic the client returns without the profession window
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
		if stub.schematics[id] then return stub.schematics[id] end -- any recipe spell, window closed (#83)
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
stub.buyback = 0 -- entries on the merchant's buyback tab
function GetNumBuybackItems() return stub.buyback end
function GetMerchantNumItems() return #stub.merchant end
function GetMerchantItemID(i) return stub.merchant[i].itemID end
function GetMerchantItemInfo(i)
	local m = stub.merchant[i]
	return "item", nil, m.price, m.stack or 1, m.available or -1, true, true, m.extended
end
-- m.costs = { { amount, link, currencyName } } for extended costs
function GetMerchantItemCostInfo(i) return #(stub.merchant[i].costs or {}) end
function GetMerchantItemCostItem(i, n)
	local c = stub.merchant[i].costs[n]
	return "tex", c[1], c[2], c[3]
end

-- Loot window: stub.loot = { { link, sources = { guid, qty, ... } } }
stub.loot = {}
function GetNumLootItems() return #stub.loot end
function GetLootSlotLink(i) return stub.loot[i].link end
function GetLootSourceInfo(i) return unpack(stub.loot[i].sources or {}) end

-- Quest window: stub.quest = { id, title, choices = { link }, rewards = { link } }
stub.quest = { id = 0, choices = {}, rewards = {} }
function GetQuestID() return stub.quest.id end
function GetTitleText() return stub.quest.title end
function GetNumQuestChoices() return #stub.quest.choices end
function GetNumQuestRewards() return #stub.quest.rewards end
function GetQuestItemLink(kind, i) return (kind == "choice" and stub.quest.choices or stub.quest.rewards)[i] end

stub.names = {} -- unit token -> name
stub.surnames = {} -- unit token -> Forever surname (#77): UnitName returns name, surname
function UnitName(unit) return stub.names[unit], stub.surnames[unit] end

-- Trainer: stub.trainer = { { name, kind, fee, required, tooltipID, icon, skill } }; the list honours the
-- type filter. skill: the required skill's name ("Leatherworking" when nil, none when false).
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
function GetTrainerServiceInfo(i) local s = visibleServices()[i]; return s.name, s.kind, s.icon end
function GetTrainerServiceCost(i) return visibleServices()[i].fee end
function GetTrainerServiceSkillReq(i)
	local s = visibleServices()[i]
	if s.skill == false then return nil, 0, false end
	return s.skill or "Leatherworking", s.required, true
end
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
-- classID by itemID: stub.itemClass[id] = 2 weapon / 4 armor / 7 trade goods / 9 recipe;
-- subclassID by itemID: stub.itemSubclass[id] (for recipes Enum.ItemRecipeSubclass)
stub.itemClass = {}
stub.itemSubclass = {}
C_Item.GetItemInfoInstant = function(id)
	if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
	local item = stub.items[id]
	return id, nil, nil, item and item.equipLoc or "", item and item.icon, stub.itemClass[id], stub.itemSubclass[id]
end
C_Item.GetItemNameByID = function(id) return stub.items[id] and stub.items[id].name end
-- The client's (localized) class and subclass names: stub.classNames[classID], stub.subclassNames[classID][subclassID].
stub.classNames, stub.subclassNames = {}, {}
C_Item.GetItemClassInfo = function(classID) return stub.classNames[classID] end
C_Item.GetItemSubClassInfo = function(classID, subclassID)
	local subs = stub.subclassNames[classID]
	return subs and subs[subclassID], false
end
C_Item.GetItemMaxStackSizeByID = function(id) return stub.items[id] and stub.items[id].stack end

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
stub.noProficiency = {} -- [itemID] = true: C_PlayerInfo.CanUseItem says no (armour or weapon type)
C_PlayerInfo = { CanUseItem = function(id) return not stub.noProficiency[id] end }
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

-- Where the player stands (house detection).
stub.faction, stub.realm, stub.zone, stub.subzone, stub.locale = "Horde", "PvP", "Orgrimmar", "", "enUS"
function UnitFactionGroup() return stub.faction end
function GetRealmName() return stub.realm end
function GetRealZoneText() return stub.zone end
function GetSubZoneText() return stub.subzone end
-- Blizzard's Minimap_Update text: the subzone, else the zone.
function GetMinimapZoneText() return stub.subzone ~= "" and stub.subzone or stub.zone end
function GetLocale() return stub.locale end
stub.guids = {} -- unit token -> GUID
function UnitGUID(unit) return stub.guids[unit] or "Player-1-SELF" end

-- Auction house. stub.replicate = { { itemID, count, buyout, link, owner, name } } (the client's list is
-- 0-based). stub.commodity[itemID] = { rows = { { unitPrice, quantity, owners } }, total, full }.
-- stub.itemSearch[itemID or "itemID:suffix"] = { rows = { { buyoutAmount, quantity } }, total, full }.
stub.replicate, stub.commodity, stub.itemSearch, stub.browse = {}, {}, {}, {}
stub.missingItems = {}
C_Item.DoesItemExistByID = function(id) return not stub.missingItems[id] end
local function SearchOf(key)
	local suffix = key.itemSuffix
	return stub.itemSearch[(suffix and suffix ~= 0) and (key.itemID .. ":" .. suffix) or key.itemID] or { rows = {} }
end
C_AuctionHouse = {
	GetNumReplicateItems = function() return #stub.replicate end,
	GetReplicateItemInfo = function(i)
		local r = stub.replicate[i + 1]
		local complete = r.link ~= nil
		if r.hasAllInfo ~= nil then complete = r.hasAllInfo end
		return r.name, r.texture, r.count, r.quality or 1, true, 1, nil, 0, 0, r.buyout, 0, nil, nil, r.owner, r.owner, 0, r.itemID, complete
	end,
	GetReplicateItemLink = function(i) return stub.replicate[i + 1].link end,
	GetNumCommoditySearchResults = function(id) return #(stub.commodity[id] or { rows = {} }).rows end,
	GetCommoditySearchResultInfo = function(id, i) return stub.commodity[id].rows[i] end,
	GetCommoditySearchResultsQuantity = function(id) return (stub.commodity[id] or {}).total or 0 end,
	HasFullCommoditySearchResults = function(id) return (stub.commodity[id] or {}).full ~= false end,
	GetNumItemSearchResults = function(key) return #SearchOf(key).rows end,
	GetItemSearchResultInfo = function(key, i) return SearchOf(key).rows[i] end,
	GetItemSearchResultsQuantity = function(key) return SearchOf(key).total or 0 end,
	HasFullItemSearchResults = function(key) return SearchOf(key).full ~= false end,
	GetBrowseResults = function() return stub.browse end,
	-- Purchases (restricted in game). stub.auctions[auctionID] = AuctionInfo.
	StartCommoditiesPurchase = noop,
	ConfirmCommoditiesPurchase = noop,
	PlaceBid = noop,
	GetAuctionInfoByID = function(id) return stub.auctions[id] end,
	-- Browse searches (Upgrades, #50): every query is kept in stub.browseQueries.
	SendBrowseQuery = function(query) table.insert(stub.browseQueries, query) end,
	IsThrottledMessageSystemReady = function() return stub.throttleReady end,
	HasFullBrowseResults = function() return stub.browseFull ~= false end,
	RequestMoreBrowseResults = function() stub.moreRequests = stub.moreRequests + 1 end,
}
stub.browseQueries, stub.throttleReady, stub.moreRequests = {}, true, 0
-- Posting (#81, restricted in game; Auctions.lua only hooks them). ItemLocations in specs are
-- { itemID, link }. stub.deposit = what CalculateItem/CommodityDeposit return.
C_AuctionHouse.PostItem = function() return false end
C_AuctionHouse.PostCommodity = function() return false end
C_AuctionHouse.ConfirmPostItem = noop
C_AuctionHouse.ConfirmPostCommodity = noop
C_AuctionHouse.CalculateItemDeposit = function() return stub.deposit end
C_AuctionHouse.CalculateCommodityDeposit = function() return stub.deposit end
C_Item.GetItemID = function(location) return location and location.itemID end
C_Item.GetItemLink = function(location) return location and location.link end
-- Owned auctions: stub.owned = { OwnedAuctionInfo, ... }, stub.ownedFull (default true).
stub.owned = {}
C_AuctionHouse.GetNumOwnedAuctions = function() return #stub.owned end
C_AuctionHouse.GetOwnedAuctionInfo = function(i) return stub.owned[i] end
C_AuctionHouse.HasFullOwnedAuctionResults = function() return stub.ownedFull ~= false end
-- Values from Blizzard's AuctionHouseDocumentation.lua / AuctionHouseEnumsDocumentation.lua (forever).
Enum.AuctionStatus = { Active = 0, Sold = 1 }
Enum.AuctionHouseNotification = { BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2, AuctionOutbid = 3, AuctionSold = 4, AuctionExpired = 5 }
-- Mail (#81): stub.inbox[index] = { subject, money, invoice = { type, itemName, buyer, bid, buyout, deposit,
-- consignment, count }, items = { { itemID, count } } }. Taking only records the call; specs move
-- money and items themselves.
stub.inbox, stub.mailTakes = {}, {}
function GetInboxHeaderInfo(i)
	local m = stub.inbox[i]
	if not m then return nil end
	return nil, nil, "Auction House", m.subject, m.money or 0, 0, 30, m.items and #m.items or nil
end
function GetInboxInvoiceInfo(i)
	local v = stub.inbox[i] and stub.inbox[i].invoice
	if not v then return nil end
	return v.type, v.itemName, v.buyer, v.bid, v.buyout, v.deposit, v.consignment, 0, nil, nil, v.count
end
function TakeInboxMoney(i) table.insert(stub.mailTakes, { "money", i }) end
function TakeInboxItem(i, a) table.insert(stub.mailTakes, { "item", i, a }) end
function AutoLootMailItem(i) table.insert(stub.mailTakes, { "auto", i }) end
Enum.ItemClass = { Weapon = 2, Armor = 4, Recipe = 9 }
-- Values from Blizzard's ItemConstantsDocumentation.lua (Gethe/wow-ui-source, branch forever).
Enum.ItemRecipeSubclass = { Book = 0, Leatherworking = 1, Tailoring = 2, Engineering = 3, Blacksmithing = 4,
	Cooking = 5, Alchemy = 6, FirstAid = 7, Enchanting = 8, Fishing = 9, Jewelcrafting = 10, Inscription = 11 }
Enum.InventoryType = { IndexHeadType = 1, IndexNeckType = 2, IndexShoulderType = 3, IndexChestType = 5, IndexWaistType = 6,
	IndexLegsType = 7, IndexFeetType = 8, IndexWristType = 9, IndexHandType = 10, IndexFingerType = 11, IndexTrinketType = 12,
	IndexWeaponType = 13, IndexShieldType = 14, IndexRangedType = 15, IndexCloakType = 16, Index2HweaponType = 17,
	IndexRobeType = 20, IndexWeaponmainhandType = 21, IndexWeaponoffhandType = 22, IndexHoldableType = 23,
	IndexThrownType = 25, IndexRangedrightType = 26 }
Enum.AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 }
stub.auctions = {}

return stub
