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

-- Handlers that run after every ns.On handler of the event, whatever the load order: Market packs
-- its entries at PLAYER_LOGOUT once nothing reads prices any more (#105).
local lastHandlers = {}

local function Register(event)
	if not handlers[event] then
		handlers[event] = {}
		local ok = pcall(frame.RegisterEvent, frame, event)
		if not ok then
			ns.unknownEvents[#ns.unknownEvents + 1] = event
		end
	end
end

function ns.On(event, fn)
	Register(event)
	table.insert(handlers[event], fn)
end

function ns.OnLast(event, fn)
	Register(event)
	lastHandlers[event] = lastHandlers[event] or {}
	table.insert(lastHandlers[event], fn)
end

local function Run(list, event, ...)
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end

function ns.Fire(event, ...)
	local list, last = handlers[event], lastHandlers[event]
	if not list then
		return
	end
	if not last then
		Run(list, event, ...)
		return
	end
	-- A handler that raises must not skip the last ones; its error is raised again after them.
	local ok, err = pcall(Run, list, event, ...)
	Run(last, event, ...)
	if not ok then
		error(err, 0)
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
	basket = { entries = {} }, -- crafts to buy for { recipeID, professionID, count } (Basket.lua, #186)
	loopNotice = {}, -- [recipeID] = { profit, loop } of the vendor finds already announced (Loops.lua, #186)
	sources = {}, -- [recipe itemID] = { vendors, loot, quests } seen in game (SourceRecorder.lua, issue #37)
	merchants = {}, -- [npcID] = full inventory of a merchant this account opened (Merchant.lua, issue #66)
	crates = {}, -- [itemID] = Waylaid crate: tooltip lines, fill options, reward (Crates.lua, issue #91)
	-- [recipeID] = { fee = copper, required = skill, at, name, icon, skill = profession name, line,
	--   reagents, output, noItemOutput, recipeAt }: seen at a trainer (Trainer.lua; recipe fields #83)
	trainer = {},
	sellPrices = {}, -- [itemID] = vendor sell price per unit, as the client returned it (#83)
	keep = {}, -- [itemID] = true: items you keep; left out of bag advice and totals
	junk = {}, -- [itemID] = true: items marked as junk, sold with one click at a vendor
	sellAH = {}, -- [itemID] = true: items marked to sell on the auction house
	dismissed = {}, -- [itemID] = true: upgrade suggestions you turned off (issue #16)
	watch = {}, -- [itemID] = Unix time it was watched: Look up › Items watch list (ItemWatch.lua, #165); the companion reads it
	skillups = {}, -- [recipeID][skill] = { n, ups, d }: crafts recorded in game (issue #15)
	snapshots = {}, -- [ns.CharKey()] (= "<realm>-<name> <surname>", #77) = character snapshot for Claude (Snapshot.lua, issue #63)
	fishing = {}, -- [ns.CharKey()] = { catches, opened, seen, findFish }, 90 days (Fishing.lua, issues #69, #86)
	fishObjects = {}, -- [GameObject ID] = { name, t }: names the client gave for fishing loot sources (#86)
	music = { enabled = true, channel = "Master", professions = {}, position = {} }, -- issue #17
	minimap = { hide = false, angle = 215 },
	-- What was just looted, on screen (LootToast.lua, #114): seconds fully shown, then fade; pos = anchor.
	lootToast = { enabled = true, duration = 4, fade = 1, value = true, locked = true },
	-- Farm tracker (Farm.lua, #126): enabled = count loot, shown = window shown, autoStart = a session starts
	-- with the first loot, idleMinutes = pause after that long without loot (0 = never), scale, locked, pos,
	-- mini = the tracker as a strip (#164, same pos); fade = 40 % alpha while the mouse is away (#163). (The
	-- loot panel's `view` went with the panel, #156: the log and the item list are on Gather › Farm.)
	farm = { enabled = true, shown = true, autoStart = true, idleMinutes = 5, scale = 1, locked = false,
		mini = false, fade = false },
	farmLog = {}, -- [ns.CharKey()] = { current = session, history = finished sessions, newest first } (#126)
	-- CraftWise section in item tooltips (Tooltip.lua); mode "always" or "shift".
	tooltip = { enabled = true, mode = "always", lines = { status = true, advice = true, usedIn = true, skillups = true, market = true, tracked = true, soldBy = true } },
	-- Make chips (#154): includeUnlearned, hideUnpriced, vendorCheck (#185), learnFitsSkill; Sell › Bags chips (#155): showKept,
	-- bagsMatsOnly; Settings › Bags and loot: showDismissed. The main window keeps its own state (section,
	-- pages, layout) in settings.ui.
	settings = { includeUnlearned = true, hideUnpriced = false, vendorCheck = false, loopAlert = true, loopAlertMin = 0, learnFitsSkill = false, showKept = true,
		showDismissed = false, ahMinPercent = 20, ahMinCopper = 10, bagsMatsOnly = false,
		alpha = { main = 0.96, farm = 0.86, toast = 0.70 }, -- background alpha per window (#162), Settings > Look
		menuClick = "middle", -- item menu in the bags: "middle" | "altright" | "off"
		slotMarks = true, -- marks on bag slots (BagIcons.lua, #160); Settings › Bags and loot (#157)
		-- Profit prices (#26 phase 2): basis "typical" | "current" (lowest), house "faction" (own) |
		-- "BootyBay" | "Gadgetzan" | "Everlook".
		priceBasis = "typical", priceHouse = "faction",
		fishingSessionGap = 5, -- minutes: fishing catches closer than this are one session (value per hour, #86)
		fishingOwnMin = 50, -- Fishing zones (#88): own catches count from this n, below it the local reference shows
		ledgerView = "reset",
		-- Reagent cost per view (#47): "ah" | "paid" (paid cost from the ledger, else AH per reagent).
		costBasis = { profit = "ah", learn = "ah", level = "ah", upgrades = "ah" } }, -- /craftwise ledger: "reset" (since last reset) | "today" | "login" (#46) -- ahMin*: Bags, AH only when it pays this much more than a vendor
}
-- Settings only the old windows used (profit window, Records, #157): dropped from the saved file on load.
ns.RETIRED_SETTINGS = { "sortKey", "sortDesc", "view", "learnSortKey", "learnSortDesc", "bagSortKey", "bagSortDesc",
	"upgradeSortKey", "upgradeSortDesc", "upgradeSection", "fishSortKey", "fishSortDesc", "recordsTab" }

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
	for _, key in ipairs(ns.RETIRED_SETTINGS) do
		CraftWiseDB.settings[key] = nil
	end
	ns.db, ns.charDB = CraftWiseDB, CraftWiseCharDB
	ns.db.debug = { unknownEvents = ns.unknownEvents }
	ns.Notify("DB_READY")
	ns.MigrateCharKey() -- "pending" when the client doesn't know the character yet: retried below
end)

function ns.Print(msg)
	print("|cff4fb3ffCraftWise|r: " .. tostring(msg))
end

----------------------------------------------------------------------------------------------------
-- Character key (#77). Forever characters have a surname: UnitName("player") returns name, surname
-- ("Velikopter", "Tanner"; snapshot of 2026-11-11). Blizzard's Forever UI joins the two with
-- Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR (Blizzard_FrameXMLUtil/Camelot/
-- NameUtil.lua, loaded for the camelot game type; Blizzard_GlueXML/Mainline/CharacterServicesShared.lua).
-- The constant is a client table, not in the API docs; " " where a client lacks it (Syndicator on
-- Forever stores "Velikopter Tanner-PvP"). Every per-character key (ledger, snapshot, fishing log,
-- merchants) is ns.CharKey() = "<realm>-<name> <surname>", "<realm>-<name>" without a surname.
----------------------------------------------------------------------------------------------------

local function NameText(value)
	if value ~= nil and issecretvalue and issecretvalue(value) then
		return nil
	end
	return type(value) == "string" and value ~= "" and value or nil
end

local function SurnameSeparator()
	local consts = Constants and Constants.CharacterNameSeparatorConsts
	local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
	return type(sep) == "string" and sep ~= "" and sep or " "
end

-- Full name, first name, surname (nil without one); nil while the client doesn't know the name.
function ns.CharName()
	if not UnitName then
		return nil
	end
	local name, surname = UnitName("player")
	name, surname = NameText(name), NameText(surname)
	if not name then
		return nil
	end
	if surname then
		return name .. SurnameSeparator() .. surname, name, surname
	end
	return name, name, nil
end

function ns.CharKey()
	local full = ns.CharName()
	if not full then
		return nil
	end
	return (GetRealmName and NameText(GetRealmName()) or "") .. "-" .. full
end

-- Before #77 the key was "<realm>-<name>" without the surname, so characters with the same first name
-- shared one ledger, snapshot and fishing log. That old entry goes to the current character only when
-- the old snapshot's class and race match it; otherwise it stays under the old key, marked
-- legacy = true, and one message says what could not be assigned. The owner is never guessed.
-- Runs at load and again at login and on entering the world until the client knows the character.
-- Returns "moved", "legacy", "none" or "pending".
local migration -- result of this session, once settled

local function LedgerStore()
	local market = CraftWiseMarketDB
	local ledger = type(market) == "table" and market.ledger
	if type(ledger) == "table" and type(ledger.chars) == "table" and type(ledger.entries) == "table" then
		return ledger
	end
end

-- The ledger character of the old key merged into the one the current character started already
-- (only when something was recorded before the client knew the character): what the new one doesn't
-- have yet (days it hasn't seen, items without a position), and the older reset point.
local function MergeLedgerChar(into, from)
	for k, v in pairs(from) do
		if k == "days" or k == "pos" then
			into[k] = into[k] or {}
			for id, value in pairs(v) do
				if into[k][id] == nil then
					into[k][id] = value
				end
			end
		elseif into[k] == nil then
			into[k] = v
		end
	end
	if from.reset and into.reset and (from.reset.t or 0) < (into.reset.t or 0) then
		into.reset = from.reset
	end
end

local function AppendList(into, from)
	for _, e in ipairs(from or {}) do
		into[#into + 1] = e
	end
	table.sort(into, function(a, b) return (a.t or 0) < (b.t or 0) end)
end

function ns.MigrateCharKey()
	if migration then
		return migration
	end
	if not ns.db then
		return "pending"
	end
	local full, first, surname = ns.CharName()
	if not full then
		return "pending"
	end
	if not surname then
		migration = "none" -- the key has no surname, nothing changed
		return migration
	end
	local oldKey = (GetRealmName and NameText(GetRealmName()) or "") .. "-" .. first
	local newKey = ns.CharKey()
	local snapshots, fishing, ledger = ns.db.snapshots or {}, ns.db.fishing or {}, LedgerStore()
	local inLedger = ledger and ledger.chars[oldKey] ~= nil
	for _, e in ipairs(ledger and ledger.entries or {}) do
		inLedger = inLedger or e.c == oldKey
	end
	local found = {}
	if snapshots[oldKey] then found[#found + 1] = "snapshot" end
	if inLedger then found[#found + 1] = "ledger" end
	if fishing[oldKey] then found[#found + 1] = "fishing log" end
	if #found == 0 then
		migration = "none"
		return migration
	end
	local class = UnitClass and NameText((UnitClass("player")))
	local race = UnitRace and NameText((UnitRace("player")))
	if not (class and race) then
		return "pending"
	end
	local old = snapshots[oldKey] and snapshots[oldKey].char
	local oldClass, oldRace = old and old.class, old and old.race
	if oldClass and oldRace and oldClass == class and oldRace == race then
		local snap = snapshots[oldKey]
		snapshots[oldKey] = nil
		if snap then
			snap.legacy = nil
			if not snapshots[newKey] or (snapshots[newKey].t or 0) < (snap.t or 0) then
				snapshots[newKey] = snap
			end
		end
		local log = fishing[oldKey]
		fishing[oldKey] = nil
		if log then
			log.legacy = nil
			local into = fishing[newKey]
			if into then
				into.catches, into.opened = into.catches or {}, into.opened or {}
				AppendList(into.catches, log.catches)
				AppendList(into.opened, log.opened)
				into.seen = into.seen or {}
				AppendList(into.seen, log.seen)
			else
				fishing[newKey] = log
			end
		end
		if ledger then
			local c = ledger.chars[oldKey]
			ledger.chars[oldKey] = nil
			if c then
				c.legacy = nil
				if ledger.chars[newKey] then
					MergeLedgerChar(ledger.chars[newKey], c)
				else
					ledger.chars[newKey] = c
				end
			end
			for _, e in ipairs(ledger.entries) do
				if e.c == oldKey then
					e.c = newKey
				end
			end
		end
		ns.Print(("%s saved for %s before surnames were part of the key now belong to %s (same class and race)."):format(
			table.concat(found, ", "), oldKey, full))
		migration = "moved"
		return migration
	end
	if inLedger and not ledger.chars[oldKey] then -- entries only: the mark needs a place
		ledger.chars[oldKey] = { days = {}, pos = {} }
	end
	local newlyMarked = false
	for _, t in pairs({ snapshot = snapshots[oldKey], fishing = fishing[oldKey], ledger = inLedger and ledger.chars[oldKey] or nil }) do
		if not t.legacy then
			t.legacy = true
			newlyMarked = true
		end
	end
	if newlyMarked then
		local why = old and ("its snapshot is a %s %s, this character a %s %s"):format(
			tostring(oldRace), tostring(oldClass), race, class) or "no snapshot to compare class and race"
		ns.Print(("%s saved under %s (before surnames were part of the key) could not be assigned to %s: %s. Kept under the old key, marked legacy."):format(
			table.concat(found, ", "), oldKey, full, why))
	end
	migration = "legacy"
	return migration
end

----------------------------------------------------------------------------------------------------
-- Player values as last seen in the world (#123). During PLAYER_LOGOUT (logout, /reload, quit) the
-- Forever client returns 0 for GetMoney, UnitXP and UnitXPMax (a level 21 character's logout
-- snapshot had money 0, xp 0, xpMax 0), so what is saved then uses the values the client gave while
-- the character was in the world: money, xp, xpMax, rested (GetXPExhaustion, 0 = none), level, each
-- read again on the event that changes it. ns.loggingOut is true from PLAYER_LOGOUT on; Core.lua
-- loads first, so it is set before any other module's logout handler runs.
----------------------------------------------------------------------------------------------------

ns.lastSeen = {}
ns.loggingOut = false

local function SeeMoney()
	if GetMoney then
		ns.lastSeen.money = GetMoney()
	end
end

local function SeeXP()
	local s = ns.lastSeen
	if UnitXP and UnitXPMax then
		s.xp, s.xpMax = UnitXP("player"), UnitXPMax("player")
	end
end

local function SeeRested()
	if GetXPExhaustion then
		ns.lastSeen.rested = GetXPExhaustion() or 0 -- nil = no rested XP (Blizzard's ExpBar.lua reads it so)
	end
end

local function SeeLevel(level)
	level = level or (UnitLevel and UnitLevel("player"))
	if type(level) == "number" and level > 0 then
		ns.lastSeen.level = level
	end
end

function ns.SeePlayer()
	if ns.loggingOut then
		return
	end
	SeeMoney()
	SeeXP()
	SeeRested()
	SeeLevel()
end

-- A player value read live, except at logout: there a live 0 or nil gives way to the value last seen
-- in the world, and to nil (unknown) when none was seen. `key` is a field of ns.lastSeen.
function ns.PlayerValue(key, live)
	if not ns.loggingOut or (live ~= nil and live ~= 0) then
		return live
	end
	return ns.lastSeen[key]
end

ns.On("PLAYER_ENTERING_WORLD", function()
	ns.SeePlayer()
end)
ns.On("PLAYER_MONEY", function()
	if not ns.loggingOut then
		SeeMoney()
	end
end)
ns.On("PLAYER_XP_UPDATE", function(_, unit)
	if not ns.loggingOut and (unit == nil or unit == "player") then
		SeeXP()
	end
end)
-- The event carries the new level; UnitLevel may still return the old one while it runs.
ns.On("PLAYER_LEVEL_UP", function(_, level)
	if not ns.loggingOut then
		SeeLevel(level)
		SeeXP()
	end
end)
ns.On("UPDATE_EXHAUSTION", function()
	if not ns.loggingOut then
		SeeRested()
	end
end)
ns.On("PLAYER_LOGOUT", function()
	ns.loggingOut = true
end)

ns.On("PLAYER_LOGIN", function()
	ns.MigrateCharKey()
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	ns.MigrateCharKey()
end)

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

-- Slash commands are a second way in (#150 "Where everything lands"): each one opens its page in the main
-- window. ns.OpenSettings, ns.OpenItemsFromSlash, ns.OpenFishingPage, ns.OpenLedgerPage, ns.OpenAuctionsPage
-- and ns.OpenFarmPage come from the page files (UI/Main/Pages/), which load after this one.
local function Open(page)
	return ns.OpenMainWindow and ns.OpenMainWindow(page)
end

local function OpenSettings(group)
	return ns.OpenSettings and ns.OpenSettings(group)
end

local function OpenItems(arg, focus)
	return ns.OpenItemsFromSlash and ns.OpenItemsFromSlash(arg, focus)
end

-- /craftwise farm <arg>: the tracker's own commands act on the tracker (its home); the switches open
-- Settings › Farm tracker; history opens Gather › Farm.
local FARM_SETTINGS = { lock = true, unlock = true, on = true, off = true, scale = true, idle = true, autostart = true }

SlashCmdList.CRAFTWISE = function(input)
	local raw = (input or ""):match("^%s*(.-)%s*$")
	local msg = raw:lower()
	-- The argument as typed (item names and links keep their case); lower() keeps byte positions.
	local rawArg = raw:match("^%S+%s*(.-)$") or ""
	if msg:match("^ahmin%f[%A]") then
		local minPercent, minCopper = msg:match("^ahmin%s+(%d+)%s*(%d*)$")
		if minPercent then
			ns.db.settings.ahMinPercent = tonumber(minPercent)
			if minCopper ~= "" then
				ns.db.settings.ahMinCopper = tonumber(minCopper)
			end
			ns.Print(("AH is advised when it pays %d%% and at least %s more than a vendor."):format(
				ns.db.settings.ahMinPercent, ns.FormatMoney(ns.db.settings.ahMinCopper or 0)))
			ns.Notify("BAGS_CHANGED")
		end
		OpenSettings("ahrule")
		return
	end
	local marketArg = msg:match("^market%f[%A]%s*(.*)$")
	if marketArg and ns.Market then
		if marketArg ~= "" then
			ns.Market.Slash(rawArg)
		end
		OpenItems(rawArg, "history")
		return
	end
	local whereArg = msg:match("^where%f[%A]%s*(.*)$")
	if whereArg and ns.Merchant then
		if whereArg ~= "" then
			ns.Merchant.Slash(rawArg)
		end
		OpenItems(rawArg, "where")
		return
	end
	local toastArg = msg:match("^loottoast%f[%A]%s*(.*)$")
	if toastArg and ns.LootToast then
		ns.LootToast.Slash(toastArg)
		OpenSettings("toast")
		return
	end
	local farmArg = msg:match("^farm%f[%A]%s*(.*)$")
	if farmArg and ns.Farm then
		ns.Farm.Slash(farmArg)
		local word = farmArg:match("^(%a*)")
		if word == "history" then
			if ns.OpenFarmPage then
				ns.OpenFarmPage()
			end
		elseif FARM_SETTINGS[word] then
			OpenSettings("farm")
		end
		return
	end
	local ledgerArg = msg:match("^ledger%f[%A]%s*(.*)$")
	if ledgerArg and ns.Ledger then
		ns.Ledger.Slash(ledgerArg)
		if ns.OpenLedgerPage then
			ns.OpenLedgerPage(ledgerArg) -- Sell › Ledger on that period (#155)
		end
		return
	end
	if msg == "auctions" or msg == "auction" then
		if ns.Auctions then
			ns.Auctions.Slash()
		end
		if ns.OpenAuctionsPage then
			ns.OpenAuctionsPage() -- Sell › Auctions (#155)
		end
		return
	end
	local fishingArg = msg:match("^fishing%f[%A]%s*(.*)$")
	if fishingArg and ns.Fishing then
		ns.Fishing.Slash(fishingArg)
		local word = fishingArg:match("^(%a*)")
		if word == "gap" or word == "ownmin" then
			OpenSettings("fishing")
		else
			-- zones: Spots; [pools | open] [zone]: the Log on that water.
			local water = (word == "pools" or word == "pool") and "pool" or word == "open" and "open" or "all"
			if ns.OpenFishingPage then
				if word == "zones" then
					ns.OpenFishingPage("spots")
				else
					ns.OpenFishingPage("log", water)
				end
			end
		end
		return
	end
	if msg == "crates" or msg == "crate" then
		if ns.Crates then
			ns.Crates.Slash()
		end
		Open("crates")
		return
	end
	if msg == "snapshot" then
		if ns.Snapshot then
			ns.Snapshot.Slash()
		end
		OpenSettings("snapshot")
		return
	end
	if msg == "settings" or msg == "config" then
		OpenSettings(nil)
		return
	end
	-- The party key's command (#20, also a macro): stays an action; Music › Party! is its button.
	if msg == "party" then
		if ns.Music then
			ns.Music.ToggleParty()
		end
		return
	end
	if msg == "minimap" then
		ns.ToggleMinimapButton()
		OpenSettings("look")
		return
	end
	-- `/craftwise debug` and `debug style` stay slash-only.
	if msg == "debug style" then
		ns.Style.Preview()
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
			ns.Print(("last trainer: %s services, %d recorded (%d with output and reagents), event %s"):format(
				tostring(d.services), d.recorded or 0, d.withRecipe or 0, tostring(d.event)))
		end
		return
	end
	-- No command: the main window (#153).
	if ns.ToggleMainWindow then
		ns.ToggleMainWindow()
	end
end
