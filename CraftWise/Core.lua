local addonName, ns = ...
ns.name = addonName

-- Event dispatch: modules call ns.On(event, fn); several handlers per event are allowed.
local handlers = {}
local frame = CreateFrame("Frame")
ns.eventFrame = frame

-- Events this client doesn't know are recorded instead of raising an error at load time.
ns.unknownEvents = {}
-- Last bag ID the player carries: backpack 0, bags 1-4, reagent bag 5 (Enum.BagIndex.ReagentBag;
-- Forever has the reagent bag slot, seen 2026-10-06 with Big Bear Meat in it).
ns.LAST_BAG = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(frame.RegisterEvent, frame, event)
		if not ok then
			ns.unknownEvents[#ns.unknownEvents + 1] = event
		end
	end
	table.insert(handlers[event], fn)
end

function ns.Fire(event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	ns.Fire(event, ...)
end)

-- Callbacks between modules (e.g. "RECIPES_CHANGED" -> UI refresh), not game events.
local callbacks = {}
function ns.Listen(name, fn)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end
function ns.Notify(name, ...)
	for _, fn in ipairs(callbacks[name] or {}) do
		fn(...)
	end
end

local DB_DEFAULTS = {
	version = 1,
	vendor = {}, -- [itemID] = unit price in copper seen at a merchant
	sources = {}, -- [recipe itemID] = { vendors, loot, quests } seen in game (SourceRecorder.lua, issue #37)
	merchants = {}, -- [npcID] = full inventory of a merchant this account opened (Merchant.lua, issue #66)
	trainer = {}, -- [recipeID] = { fee = copper, required = skill }
	keep = {}, -- [itemID] = true: items you keep; left out of bag advice and totals
	junk = {}, -- [itemID] = true: items marked as junk, sold with one click at a vendor
	sellAH = {}, -- [itemID] = true: items marked to sell on the auction house
	dismissed = {}, -- [itemID] = true: upgrade suggestions you turned off (issue #16)
	skillups = {}, -- [recipeID][skill] = { n, ups, d }: crafts recorded in game (issue #15)
	snapshots = {}, -- ["<realm>-<name>"] = character snapshot for Claude (Snapshot.lua, issue #63)
	music = { enabled = true, channel = "Master", professions = {}, position = {} }, -- issue #17
	minimap = { hide = false, angle = 215 },
	-- CraftWise section in item tooltips (Tooltip.lua); mode "always" or "shift".
	tooltip = { enabled = true, mode = "always", lines = { status = true, advice = true, usedIn = true, skillups = true, market = true, tracked = true, soldBy = true } },
	settings = { includeUnlearned = true, hideUnpriced = false, sortKey = "profit", sortDesc = true,
		view = "profit", learnFitsSkill = false, learnSortKey = "required", learnSortDesc = false,
		bagSortKey = "bestValue", bagSortDesc = true, showKept = true,
		upgradeSortKey = "gain", upgradeSortDesc = true, showDismissed = false,
		upgradeSection = "craft", -- Upgrades view: "craft" (Craftable, #16) | "ah" (General / AH, #50)
		ahMinPercent = 20, ahMinCopper = 10, bagsMatsOnly = false,
		menuClick = "middle", -- item menu in the bags: "middle" | "altright" | "off"
		-- Profit prices (#26 phase 2): basis "typical" | "current" (lowest), house "faction" (own) |
		-- "BootyBay" | "Gadgetzan" | "Everlook".
		priceBasis = "typical", priceHouse = "faction",
		ledgerView = "reset",
		-- Reagent cost per view (#47): "ah" | "paid" (paid cost from the ledger, else AH per reagent).
		costBasis = { profit = "ah", learn = "ah", level = "ah", upgrades = "ah" } }, -- /craftwise ledger: "reset" (since last reset) | "today" | "login" (#46) -- ahMin*: Bags, AH only when it pays this much more than a vendor
}
local CHAR_DEFAULTS = {
	version = 1,
	professions = {}, -- [professionID] = { name, skill, maxSkill, recipes = { [recipeID] = recipe } }
}

local function ApplyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = {}
				ApplyDefaults(target[k], v)
			else
				target[k] = v
			end
		elseif type(v) == "table" and type(target[k]) == "table" then
			ApplyDefaults(target[k], v)
		end
	end
end

ns.On("ADDON_LOADED", function(_, loaded)
	if loaded ~= addonName then
		return
	end
	CraftWiseDB = CraftWiseDB or {}
	CraftWiseCharDB = CraftWiseCharDB or {}
	ApplyDefaults(CraftWiseDB, DB_DEFAULTS)
	ApplyDefaults(CraftWiseCharDB, CHAR_DEFAULTS)
	ns.db, ns.charDB = CraftWiseDB, CraftWiseCharDB
	ns.db.debug = { unknownEvents = ns.unknownEvents }
	ns.Notify("DB_READY")
end)

function ns.Print(msg)
	print("|cff4fb3ffCraftWise|r: " .. tostring(msg))
end

----------------------------------------------------------------------------------------------------
-- Items in chat (#59): a clickable link when the client has one, else the name, else "item <id>".
-- Items not in the client's cache are requested first; ns.WithItemNames prints once they arrive.
----------------------------------------------------------------------------------------------------

ns.ITEM_WAIT_SECONDS = 2 -- prints with what is known after this, even if an item never arrives

-- A link that chat shows as a clickable item (|Hitem:...|h[Name]|h).
local function ChatLink(link)
	return type(link) == "string" and link:find("|Hitem:", 1, true) and link or nil
end

-- What the client knows about an item right now: name, chat link (each nil when not cached).
function ns.ItemInfoNow(itemID)
	local name, link
	if C_Item and C_Item.GetItemInfo then
		name, link = C_Item.GetItemInfo(itemID)
	end
	if not name and C_Item and C_Item.GetItemNameByID then
		name = C_Item.GetItemNameByID(itemID)
	end
	return name, ChatLink(link)
end

-- Text for an item in chat. stored = { name, link } kept by the caller (e.g. a ledger entry), used
-- when the client has nothing better; "item <id>" only when nothing is known.
function ns.ItemChatText(itemID, stored)
	local name, link = ns.ItemInfoNow(itemID)
	stored = stored or {}
	return link or ChatLink(stored.link) or name or stored.name or ("item " .. tostring(itemID))
end

local itemWaits = {} -- { need = { [itemID] = true }, fn, timer, done }

local function FinishWait(job)
	if job.done then
		return
	end
	job.done = true
	if job.timer then
		job.timer:Cancel()
	end
	for i, j in ipairs(itemWaits) do
		if j == job then
			table.remove(itemWaits, i)
			break
		end
	end
	job.fn()
end

-- Runs fn once the client has every item in itemIDs, or after ns.ITEM_WAIT_SECONDS. known(itemID)
-- may say an item needs no request (the caller has a stored name). Runs fn right away when nothing
-- is missing. Blizzard's Forever UI answers C_Item.RequestLoadItemDataByID with ITEM_DATA_LOAD_RESULT
-- (Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua); success = false (no such item) ends the wait too.
function ns.WithItemNames(itemIDs, fn, known)
	local need, missing = {}, {}
	for _, itemID in ipairs(itemIDs or {}) do
		if not need[itemID] and not (known and known(itemID)) and not ns.ItemInfoNow(itemID) then
			need[itemID] = true
			missing[#missing + 1] = itemID
		end
	end
	if #missing == 0 or not (C_Item and C_Item.RequestLoadItemDataByID) then
		fn()
		return
	end
	local job = { need = need, fn = fn }
	itemWaits[#itemWaits + 1] = job
	job.timer = C_Timer.NewTimer(ns.ITEM_WAIT_SECONDS, function()
		FinishWait(job)
	end)
	for _, itemID in ipairs(missing) do
		if not job.done then
			pcall(C_Item.RequestLoadItemDataByID, itemID)
		end
	end
end

ns.On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
	for i = #itemWaits, 1, -1 do
		local job = itemWaits[i]
		if job and job.need[itemID] then
			job.need[itemID] = nil
			if next(job.need) == nil then
				FinishWait(job)
			end
		end
	end
end)

SLASH_CRAFTWISE1 = "/craftwise"
SlashCmdList.CRAFTWISE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local minPercent, minCopper = msg:match("^ahmin%s+(%d+)%s*(%d*)$")
	if minPercent then
		ns.db.settings.ahMinPercent = tonumber(minPercent)
		if minCopper ~= "" then
			ns.db.settings.ahMinCopper = tonumber(minCopper)
		end
		ns.Print(("AH is advised when it pays %d%% and at least %s more than a vendor."):format(
			ns.db.settings.ahMinPercent, ns.FormatMoney(ns.db.settings.ahMinCopper or 0)))
		ns.Notify("BAGS_CHANGED")
		return
	end
	local marketArg = msg:match("^market%s*(.*)$")
	if marketArg and ns.Market then
		ns.Market.Slash(marketArg)
		return
	end
	local whereArg = msg:match("^where%s*(.*)$")
	if whereArg and ns.Merchant then
		ns.Merchant.Slash(whereArg)
		return
	end
	local ledgerArg = msg:match("^ledger%s*(.*)$")
	if ledgerArg and ns.Ledger then
		ns.Ledger.Slash(ledgerArg)
		return
	end
	if msg == "snapshot" then
		if ns.Snapshot then
			ns.Snapshot.Slash()
		end
		return
	end
	if msg == "settings" or msg == "config" then
		ns.ToggleSettings()
		return
	end
	if msg == "party" then
		if ns.Music then
			ns.Music.ToggleParty()
		end
		return
	end
	if msg == "minimap" then
		ns.ToggleMinimapButton()
		return
	end
	if msg == "debug" then
		local n = 0
		for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
			local count = 0
			for _ in pairs(prof.recipes) do
				count = count + 1
			end
			ns.Print(("%s %d/%d: %d recipes cached"):format(prof.name or "?", prof.skill or 0, prof.maxSkill or 0, count))
			n = n + 1
		end
		if n == 0 then
			ns.Print("no professions cached yet - open a profession window once")
		end
		ns.Print("Auctionator: " .. (ns.HasAuctionator() and "found" or "not found"))
		if #ns.unknownEvents > 0 then
			ns.Print("unknown events: " .. table.concat(ns.unknownEvents, ", "))
		end
		if ns.CraftsRecorded then
			ns.Print(("skill-up log: %d crafts recorded"):format(ns.CraftsRecorded()))
		end
		if ns.Merchant then
			ns.Print(("merchants recorded: %d"):format(ns.Merchant.Count()))
		end
		local d = ns.db and ns.db.debug and ns.db.debug.trainer
		if d then
			ns.Print(("last trainer: %s services, %d recorded, event %s"):format(tostring(d.services), d.recorded or 0, tostring(d.event)))
		end
		return
	end
	if ns.ToggleProfitFrame then
		ns.ToggleProfitFrame()
	end
end
