-- Junk (issue #12): items the player marked as junk in the Bags view or with Alt + right-click in the bags are
-- sold with one click on a "Sell junk" button in the merchant window. Marks are kept per item ID,
-- so the next copy you loot is junk too. One item per short step, each slot re-checked first.
local _, ns = ...

local Junk = {}
ns.Junk = Junk

local STEP = 0.2 -- seconds between sales
local job -- { slots, index, elapsed, sold, copper }
local button, merchantOpen = nil, false

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

local function UpdateButton()
	if not button then
		return
	end
	local slots = Junk.Slots()
	local copper = 0
	for _, s in ipairs(slots) do
		copper = copper + Value(s)
	end
	button.count, button.copper = #slots, copper
	button:SetLabel(job and ns.L["Selling..."] or (ns.L["Sell junk"] .. (#slots > 0 and (" (" .. #slots .. ")") or "")))
	button:SetAlpha(#slots > 0 and 1 or 0.5)
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
	-- The slot may have changed since the list was made: only sell what is still marked junk.
	local item = C_Container.GetContainerItemInfo(s.bag, s.slot)
	if item and item.itemID == s.itemID and not item.isLocked and ns.db.junk[s.itemID] then
		C_Container.UseContainerItem(s.bag, s.slot)
		job.sold = job.sold + 1
		job.copper = job.copper + Value(s)
	end
end

function Junk.Sell()
	if job or not merchantOpen then
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
	button = ns.Style.Button(MerchantFrame, 110, 24, ns.L["Sell junk"])
	if MerchantSellAllJunkButton then
		button:SetPoint("RIGHT", MerchantSellAllJunkButton, "LEFT", -8, 0)
	else
		button:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 12, 34)
	end
	button:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 5)
	button:SetScript("OnClick", Junk.Sell)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("CraftWise: sell junk")
		GameTooltip:AddLine(("%d marked %s, %s"):format(self.count or 0, (self.count or 0) == 1 and "stack" or "stacks",
			ns.FormatMoney(self.copper or 0)), 1, 1, 1)
		GameTooltip:AddLine("Mark items: middle-click them in your bags, or click them in CraftWise > Bags.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		self:SetSelected(false)
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
