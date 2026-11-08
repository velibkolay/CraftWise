-- General / AH section of the Upgrades view (issue #50). One click on "Search AH" (a hardware event,
-- auction house open) runs one browse search per equipment slot for gear this character can wear now
-- (required level up to its own). No background scanning: nothing runs without the click, and each
-- search waits for the client's throttle (C_AuctionHouse.IsThrottledMessageSystemReady). Results are
-- compared with what you wear by the #16 rule (Upgrades.lua). Prices are recorded by Market.lua:
-- items outside the market scope as `last` only (decision 1 on #50).
--
-- Per character, CraftWiseCharDB.ahGear = { t, house, complete, searched, failed,
--   items = { [itemKey] = { itemID, suffix, level, slot } } } from the latest run.
local _, ns = ...

local S = {}
ns.UpgradeSearch = S

local TIMEOUT_SECONDS = 15 -- a search without an answer is skipped
local MORE_PAGES = 3 -- extra result pages per slot; results come highest level first

-- One search per slot group. Filters are the client's own enums (Enum.ItemClass, Enum.InventoryType),
-- resolved at run time; a value the client doesn't have drops that filter rather than guess a number.
local QUERIES = {
	{ label = "Head", class = "Armor", types = { "IndexHeadType" } },
	{ label = "Neck", class = "Armor", types = { "IndexNeckType" } },
	{ label = "Shoulder", class = "Armor", types = { "IndexShoulderType" } },
	{ label = "Back", class = "Armor", types = { "IndexCloakType" } },
	{ label = "Chest", class = "Armor", types = { "IndexChestType", "IndexRobeType" } },
	{ label = "Wrist", class = "Armor", types = { "IndexWristType" } },
	{ label = "Hands", class = "Armor", types = { "IndexHandType" } },
	{ label = "Waist", class = "Armor", types = { "IndexWaistType" } },
	{ label = "Legs", class = "Armor", types = { "IndexLegsType" } },
	{ label = "Feet", class = "Armor", types = { "IndexFeetType" } },
	{ label = "Ring", class = "Armor", types = { "IndexFingerType" } },
	{ label = "Trinket", class = "Armor", types = { "IndexTrinketType" } },
	{ label = "Off hand", class = "Armor", types = { "IndexShieldType", "IndexHoldableType" } },
	{ label = "Weapon", class = "Weapon",
		types = { "IndexWeaponType", "Index2HweaponType", "IndexWeaponmainhandType", "IndexWeaponoffhandType" } },
	{ label = "Ranged", class = "Weapon", types = { "IndexRangedType", "IndexRangedrightType", "IndexThrownType" } },
}

local function Queries()
	local out = {}
	local classes = Enum and Enum.ItemClass
	local types = Enum and Enum.InventoryType
	if not (classes and types) then
		return out
	end
	for _, q in ipairs(QUERIES) do
		local classID = classes[q.class]
		local filters = {}
		for _, name in ipairs(q.types) do
			if classID and types[name] then
				filters[#filters + 1] = { classID = classID, inventoryType = types[name] }
			end
		end
		if #filters > 0 then
			out[#out + 1] = { label = q.label, filters = filters }
		end
	end
	return out
end

local ahOpen = false
local run -- the search in progress: { queries, index, pages, timer, items, failed, waiting }

function S.Running()
	return run ~= nil
end

-- "3/15 Shoulder" while a search runs.
function S.Progress()
	if not run then
		return nil
	end
	local q = run.queries[run.index]
	return run.index, #run.queries, q and q.label
end

function S.CanSearch()
	return ahOpen and ns.Market.CurrentHouse() ~= nil and C_AuctionHouse ~= nil and C_AuctionHouse.SendBrowseQuery ~= nil
end

local function Store(complete)
	if not (run and ns.charDB) then
		return
	end
	ns.charDB.ahGear = {
		t = time(), house = run.house, complete = complete, items = run.items,
		searched = run.index - 1, slots = #run.queries, failed = run.failed,
	}
end

local function Finish(complete)
	if not run then
		return
	end
	if run.timer then
		run.timer:Cancel()
	end
	Store(complete)
	local failed, searched, slots = #run.failed, run.index - 1, #run.queries
	run = nil
	if complete then
		ns.Print(("AH gear search done%s."):format(failed > 0 and (" (%d slot searches without an answer)"):format(failed) or ""))
	else
		ns.Print(("AH gear search stopped: auction house closed (%d of %d slots searched)."):format(searched, slots))
	end
	ns.Notify("UPGRADES_CHANGED")
end

-- Sends when the client's throttle allows it, else once AUCTION_HOUSE_THROTTLED_SYSTEM_READY fires.
local function WhenReady(fn)
	local ready = not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
	if ready then
		run.waiting = nil
		fn()
	else
		run.waiting = fn
	end
end

local SendNext

local function Advance()
	if not run then
		return
	end
	if run.timer then
		run.timer:Cancel()
		run.timer = nil
	end
	run.index, run.pages, run.awaiting = run.index + 1, 0, false
	SendNext()
end

local function StartTimer()
	if run.timer then
		run.timer:Cancel()
	end
	local current = run
	run.timer = C_Timer.NewTimer(TIMEOUT_SECONDS, function()
		if run == current and run.awaiting then
			run.failed[#run.failed + 1] = run.queries[run.index].label
			Advance()
		end
	end)
end

SendNext = function()
	if not run then
		return
	end
	local q = run.queries[run.index]
	if not q then
		return Finish(true)
	end
	ns.Notify("UPGRADES_CHANGED")
	WhenReady(function()
		local sortOrder = Enum.AuctionHouseSortOrder or {}
		C_AuctionHouse.SendBrowseQuery({
			searchString = "",
			sorts = {
				{ sortOrder = sortOrder.Level, reverseSort = true }, -- highest level first: likeliest upgrades
				{ sortOrder = sortOrder.Price, reverseSort = false },
			},
			minLevel = nil,
			maxLevel = run.level, -- items this character can wear now (decision 2 on #50)
			filters = {},
			itemClassFilters = q.filters,
		})
		run.awaiting = true
		StartTimer()
	end)
end

-- The equipment rows of a result batch go into the run; prices into the market data.
local function Collect(results)
	if not (run and results) then
		return
	end
	local q = run.queries[run.index]
	for _, row in ipairs(results) do
		local key = row.itemKey
		if key and key.itemID and (row.totalQuantity or 0) > 0 then
			local itemKey = ns.Market.ItemKey(key.itemID, key.itemSuffix)
			run.items[itemKey] = { itemID = key.itemID, suffix = key.itemSuffix ~= 0 and key.itemSuffix or nil,
				level = key.itemLevel ~= 0 and key.itemLevel or nil, slot = q and q.label }
		end
	end
	ns.Market.RecordGear(results)
end

local function MoreOrNext()
	if not run then
		return
	end
	if not C_AuctionHouse.HasFullBrowseResults() and run.pages < MORE_PAGES then
		run.pages = run.pages + 1
		WhenReady(function()
			C_AuctionHouse.RequestMoreBrowseResults()
			StartTimer()
		end)
	else
		Advance()
	end
end

-- Starts a search. Call from a click (hardware event) with the auction house open.
function S.Start()
	if run then
		return false, "running"
	end
	if not S.CanSearch() then
		ns.Print("Open the auction house first, then click Search AH.")
		return false, "closed"
	end
	local queries = Queries()
	if #queries == 0 then
		ns.Print("This client has no item class filters for the AH search.")
		return false, "no filters"
	end
	run = { queries = queries, index = 1, pages = 0, items = {}, failed = {}, house = ns.Market.CurrentHouse(),
		level = UnitLevel and UnitLevel("player") or nil }
	SendNext()
	return true
end

ns.On("AUCTION_HOUSE_SHOW", function()
	ahOpen = true
	ns.Notify("UPGRADES_CHANGED")
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
	ahOpen = false
	if run then
		Finish(false) -- keeps what was found; the run counts as incomplete
	else
		ns.Notify("UPGRADES_CHANGED")
	end
end)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
	if run and run.waiting then
		local fn = run.waiting
		run.waiting = nil
		fn()
	end
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	if run and run.awaiting then
		Collect(C_AuctionHouse.GetBrowseResults())
		MoreOrNext()
	end
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
	if run and run.awaiting then
		Collect(added)
		MoreOrNext()
	end
end)
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function()
	if run and run.awaiting then
		run.failed[#run.failed + 1] = run.queries[run.index].label
		Advance()
	end
end)

----------------------------------------------------------------------------------------------------
-- Rows of the General / AH section
----------------------------------------------------------------------------------------------------

-- One row per item found by the latest search that beats what you wear now, priced at the profit house.
function S.Rows()
	local gear = ns.charDB and ns.charDB.ahGear
	local out = {}
	if not gear then
		return out
	end
	local house, houseLabel = ns.ProfitHouse()
	local now = time()
	for itemKey, it in pairs(gear.items or {}) do
		local row = ns.Upgrades.Compare(it.itemID, { level = it.level })
		if row then
			row.section, row.itemKey, row.suffix = "ah", itemKey, it.suffix
			if it.suffix then
				row.mainStats = nil -- the base item's stats; the random enchant's are not known here
			end
			row.houseLabel = houseLabel
			local current = house and ns.Market.Current(itemKey, house)
			if current and current.listed and current.min then
				row.cost, row.costComplete = current.min, true
				row.qty, row.listings = current.qty, current.listings
				row.priceAge = math.max(0, now - current.t)
			else
				row.cost, row.costComplete = nil, false
				row.notAtHouse = true
			end
			out[#out + 1] = row
		end
	end
	return out
end

-- Latest run, for the summary: { t, age, houseLabel, complete, searched, slots, failed }.
function S.LastRun()
	local gear = ns.charDB and ns.charDB.ahGear
	if not gear then
		return nil
	end
	return { t = gear.t, age = gear.t and math.max(0, time() - gear.t), houseLabel = gear.house and ns.Market.HouseLabel(gear.house),
		complete = gear.complete, searched = gear.searched, slots = gear.slots, failed = gear.failed or {} }
end
