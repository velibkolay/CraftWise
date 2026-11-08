-- What the character holds, from the places CraftWise can see (#49):
--   bags and reagent bag   read live (containers 0 .. ns.LAST_BAG)
--   bank                   snapshot taken while the bank is open (character bank tabs)
--   mail                   snapshot of the attachments while the mailbox is open
-- Nothing is assumed for a place CraftWise hasn't seen: a bank never opened counts 0 and is listed as
-- not counted. Snapshots are per character (CraftWiseCharDB.holdings) and keep the time they were taken.
local _, ns = ...

local Holdings = {}
ns.Holdings = Holdings

-- Bumped whenever a counted place may have changed (bags, bank scan, mail scan): callers that cache
-- results built from the holdings compare it (Balance.lua).
Holdings.version = 0
local function Changed()
	Holdings.version = Holdings.version + 1
end

-- Attachments per mail: Blizzard's Forever MailFrame.lua (ATTACHMENTS_MAX_RECEIVE = 16).
local MAIL_ATTACHMENTS = 16

local function Store()
	local char = ns.charDB
	if not char then
		return nil
	end
	char.holdings = char.holdings or {}
	return char.holdings
end

local function AddContainer(counts, bag)
	for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID then
			counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
		end
	end
end

-- Carried items by itemID: backpack, bags 1-4 and the reagent bag.
function Holdings.Carried()
	local counts = {}
	if C_Container and C_Container.GetContainerNumSlots then
		for bag = 0, ns.LAST_BAG do
			AddContainer(counts, bag)
		end
	end
	return counts
end

-- Character bank containers as the client names them (Enum.BagIndex): CharacterBankTab_1..n, or
-- Bank / BankBag_n on clients with the older layout. Account bank tabs are not counted.
function Holdings.BankBags()
	local bags = {}
	for name, index in pairs(Enum and Enum.BagIndex or {}) do
		if type(index) == "number" and (name:match("^CharacterBankTab_%d+$") or name == "Bank" or name:match("^BankBag_%d+$")) then
			bags[#bags + 1] = index
		end
	end
	table.sort(bags)
	return bags
end

-- The client has account bank tabs (Enum.BagIndex.AccountBankTab_n). CraftWise doesn't read them;
-- the tooltip lists them as not counted.
function Holdings.HasAccountBank()
	for name in pairs(Enum and Enum.BagIndex or {}) do
		if name:match("^AccountBankTab_%d+$") then
			return true
		end
	end
	return false
end

local bankOpen = false

function Holdings.ScanBank()
	local store = Store()
	if not (store and bankOpen and C_Container and C_Container.GetContainerNumSlots) then
		return
	end
	local counts = {}
	for _, bag in ipairs(Holdings.BankBags()) do
		AddContainer(counts, bag)
	end
	store.bank = { t = time(), items = counts }
	Changed()
end

function Holdings.ScanMail()
	local store = Store()
	if not (store and GetInboxNumItems and GetInboxItem) then
		return
	end
	local counts = {}
	local mails = GetInboxNumItems() or 0
	for index = 1, mails do
		for slot = 1, MAIL_ATTACHMENTS do
			local _, itemID, _, count = GetInboxItem(index, slot)
			if itemID then
				counts[itemID] = (counts[itemID] or 0) + (count or 1)
			end
		end
	end
	store.mail = { t = time(), items = counts, mails = mails }
	Changed()
end

ns.On("BANKFRAME_OPENED", function()
	bankOpen = true
	Holdings.ScanBank()
end)
ns.On("BANKFRAME_CLOSED", function()
	bankOpen = false
end)
ns.On("PLAYERBANKSLOTS_CHANGED", function()
	Holdings.ScanBank()
end)
ns.On("BAG_UPDATE", function()
	if bankOpen then
		Holdings.ScanBank()
	end
end)
ns.On("BAG_UPDATE_DELAYED", Changed)
ns.On("MAIL_SHOW", function()
	Holdings.ScanMail()
end)
ns.On("MAIL_INBOX_UPDATE", function()
	Holdings.ScanMail()
end)

-- A counter for one tooltip: count(itemID) -> total held over every counted place, and the parts.
-- Carried items are read once when the counter is made.
function Holdings.Counter()
	local carried = Holdings.Carried()
	local store = Store() or {}
	local bank = store.bank and store.bank.items
	local mail = store.mail and store.mail.items
	return function(itemID)
		local parts = { bags = carried[itemID] or 0, bank = bank and (bank[itemID] or 0), mail = mail and (mail[itemID] or 0) }
		return parts.bags + (parts.bank or 0) + (parts.mail or 0), parts
	end
end

-- Which places were counted: { { key, label, counted, age (seconds) } } in a fixed order.
function Holdings.Places(now)
	now = now or time()
	local store = Store() or {}
	local places = { { key = "bags", label = "bags and reagent bag", counted = true } }
	for _, key in ipairs({ "bank", "mail" }) do
		local snap = store[key]
		places[#places + 1] = { key = key, label = key, counted = snap ~= nil, age = snap and snap.t and (now - snap.t) or nil }
	end
	return places
end

-- "bags and reagent bag, bank (2h ago)" and "mail (open your mailbox once)" for the tooltip.
function Holdings.PlacesText(now)
	local counted, missing = {}, {}
	for _, p in ipairs(Holdings.Places(now)) do
		if p.counted then
			counted[#counted + 1] = p.age and ("%s (%s ago)"):format(p.label, ns.Market.FormatAge(p.age)) or p.label
		else
			missing[#missing + 1] = p.key == "bank" and "bank (open it once)" or "mail (open your mailbox once)"
		end
	end
	if Holdings.HasAccountBank() then
		missing[#missing + 1] = "account bank (not read)"
	end
	return table.concat(counted, ", "), #missing > 0 and table.concat(missing, ", ") or nil
end
