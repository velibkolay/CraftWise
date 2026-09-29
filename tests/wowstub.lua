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
function CreateFrame()
	local f = setmetatable({ events = {}, scripts = {} }, frameMeta)
	table.insert(stub.frames, f)
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
	local item = stub.items[id]
	if not item then return nil end
	return item.name, nil, 1, 1, 1, "", "", 20, "", nil, item.sellPrice
end
C_Item = { GetItemInfo = GetItemInfo, RequestLoadItemDataByID = noop }

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

-- Trainer: stub.trainer = { { name, kind, fee, required, tooltipID } }
stub.trainer = {}
function GetNumTrainerServices() return #stub.trainer end
function GetTrainerServiceInfo(i) return stub.trainer[i].name, stub.trainer[i].kind end
function GetTrainerServiceCost(i) return stub.trainer[i].fee end
function GetTrainerServiceSkillReq(i) return "Leatherworking", stub.trainer[i].required, true end
C_TooltipInfo = { GetTrainerService = function(i)
	local id = stub.trainer[i].tooltipID
	return id and { id = id } or nil
end }

return stub
