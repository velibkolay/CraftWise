-- Junk (issue #12): items the player marked as junk in the Bags view or with Alt + right-click in the bags are
-- sold with one click on a "Sell junk" button in the merchant window. Marks are kept per item ID,
-- so the next copy you loot is junk too. One item per short step, each slot re-checked first.
local _, ns = ...

local Junk = {}
ns.Junk = Junk

local STEP = 0.2 -- seconds between sales
local job -- { slots, index, elapsed, sold, copper }
local button, merchantOpen = nil, false
local inCombat = false

-- Bag slots holding marked junk that a vendor buys.
function Junk.Slots()
	local slots = {}
	local junk = ns.db and ns.db.junk or {}
	for bag = 0, ns.LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local item = C_Container.GetContainerItemInfo(bag, slot)
			if item and item.itemID and junk[item.itemID] and not item.hasNoValue and not item.isLocked then
				slots[#slots + 1] = { bag = bag, slot = slot, itemID = item.itemID, count = item.stackCount or 1 }
			end
		end
	end
	return slots
end

local function Value(s)
	local each = ns.GetVendorSellPrice(s.itemID)
	return each and each * s.count or 0
end

-- "35s", "12g 40s": plain digits, at most two units (spec: Money).
local function ShortMoney(copper)
	local parts = {}
	for part in ns.FormatMoney(copper, true):gmatch("%S+") do
		parts[#parts + 1] = part
		if #parts == 2 then
			break
		end
	end
	return table.concat(parts, " ")
end
Junk.ShortMoney = ShortMoney

local function InCombat()
	return inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end
Junk.InCombat = InCombat

-- "Selling 3 of 5" and the orange diamond next to the button, only while a job runs.
local function UpdateProgress()
	if not button then
		return
	end
	local selling = job ~= nil
	button.progress:SetShown(selling)
	button.nokta:SetShown(selling)
	if selling then
		button.progress:SetText(("Selling %d of %d"):format(math.max(1, math.min(job.index - 1, #job.slots)), #job.slots))
	end
end

local function UpdateButton()
	if not button then
		return
	end
	if job then
		-- Mid-sale the label keeps the amount it started with; the button waits.
		button:Disable()
		button:SetAlpha(0.5)
		UpdateProgress()
		return
	end
	local slots = Junk.Slots()
	local copper = 0
	for _, s in ipairs(slots) do
		copper = copper + Value(s)
	end
	button.count, button.copper = #slots, copper
	button:SetLabel(ns.L["Sell junk"] .. " · " .. ShortMoney(copper))
	-- Nothing marked: nothing to show.
	button:SetShown(#slots > 0)
	if InCombat() then
		button:Disable()
		button:SetAlpha(0.5)
	else
		button:Enable()
		button:SetAlpha(1)
	end
	UpdateProgress()
end

local function Finish()
	if job and job.sold > 0 then
		ns.Print(("Sold %d junk %s for %s."):format(job.sold, job.sold == 1 and "item" or "items",
			ns.FormatMoney(job.copper)))
	end
	job = nil
	if button then
		button:SetScript("OnUpdate", nil)
	end
	UpdateButton()
end

local function Step(_, elapsed)
	if not job then
		return
	end
	job.elapsed = job.elapsed + (elapsed or 0)
	if job.elapsed < STEP then
		return
	end
	job.elapsed = 0
	if not merchantOpen then
		return Finish()
	end
	local s = job.slots[job.index]
	if not s then
		return Finish()
	end
	job.index = job.index + 1
	UpdateProgress()
	-- The slot may have changed since the list was made: only sell what is still marked junk.
	local item = C_Container.GetContainerItemInfo(s.bag, s.slot)
	if item and item.itemID == s.itemID and not item.isLocked and ns.db.junk[s.itemID] then
		C_Container.UseContainerItem(s.bag, s.slot)
		job.sold = job.sold + 1
		job.copper = job.copper + Value(s)
	end
end

function Junk.Sell()
	if job or not merchantOpen or InCombat() then
		return false
	end
	local slots = Junk.Slots()
	if #slots == 0 then
		ns.Print("No junk to sell. Mark items: middle-click them in your bags, or click them in CraftWise > Bags.")
		return false
	end
	job = { slots = slots, index = 1, elapsed = STEP, sold = 0, copper = 0 }
	button:SetScript("OnUpdate", Step)
	Step(nil, 0)
	UpdateButton()
	return true
end

function Junk.Running()
	return job ~= nil
end

local function CreateButton()
	if button or not MerchantFrame then
		return
	end
	-- Folded C.action, cut 10, 28 tall, bottom left above the tabs (spec: On Blizzard frames).
	button = ns.Style.ActionButton(MerchantFrame, ns.L["Sell junk"], nil, 28)
	button:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 12, 34)
	button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 5)
	button:SetScript("OnClick", Junk.Sell)
	button.nokta = ns.Style.Nokta(button, "live")
	button.nokta:MoveTo(button, "RIGHT", 14, 0, true)
	button.progress = ns.Style.Text(button, "Small", "text2")
	button.progress:SetPoint("LEFT", button, "RIGHT", 26, 0)
	local fold = button:GetScript("OnEnter")
	button:SetScript("OnEnter", function(self)
		if fold then
			fold(self)
		end
		local lines = { ("%d marked %s, %s"):format(self.count or 0, (self.count or 0) == 1 and "stack" or "stacks",
			ShortMoney(self.copper or 0)) }
		if InCombat() then
			lines[#lines + 1] = "Unavailable in combat. It works again when combat ends."
		else
			lines[#lines + 1] = "Mark items: middle-click them in your bags, or click them in CraftWise > Bags."
		end
		ns.Style.ShowTip(self, "Sell junk", unpack(lines))
	end)
	local unfold = button:GetScript("OnLeave")
	button:SetScript("OnLeave", function(self)
		if unfold then
			unfold(self)
		end
		ns.Style.HideTip(self)
	end)
	Junk.button = button
end

ns.On("MERCHANT_SHOW", function()
	merchantOpen = true
	CreateButton()
	UpdateButton()
end)
ns.On("MERCHANT_CLOSED", function()
	merchantOpen = false
	if job then
		Finish()
	end
end)
ns.Listen("BAGS_CHANGED", function()
	if merchantOpen then
		UpdateButton()
	end
end)

-- Combat: the button waits, a running sale stops (the rest stays marked).
ns.On("PLAYER_REGEN_DISABLED", function()
	inCombat = true
	if job then
		Finish()
	end
	UpdateButton()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	inCombat = false
	if merchantOpen then
		UpdateButton()
	end
end)
