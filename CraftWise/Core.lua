local addonName, ns = ...
ns.name = addonName

-- Event dispatch: modules call ns.On(event, fn); several handlers per event are allowed.
local handlers = {}
local frame = CreateFrame("Frame")
ns.eventFrame = frame

-- Events this client doesn't know are recorded instead of raising an error at load time.
ns.unknownEvents = {}
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
	trainer = {}, -- [recipeID] = { fee = copper, required = skill }
	keep = {}, -- [itemID] = true: items you keep; left out of bag advice and totals
	junk = {}, -- [itemID] = true: items marked as junk, sold with one click at a vendor
	dismissed = {}, -- [itemID] = true: upgrade suggestions you turned off (issue #16)
	skillups = {}, -- [recipeID][skill] = { n, ups, d }: crafts recorded in game (issue #15)
	music = { enabled = true, channel = "Master", professions = {}, position = {} }, -- issue #17
	minimap = { hide = false, angle = 215 },
	settings = { includeUnlearned = true, hideUnpriced = false, sortKey = "profit", sortDesc = true,
		view = "profit", learnFitsSkill = false, learnSortKey = "required", learnSortDesc = false,
		bagSortKey = "bestValue", bagSortDesc = true, showKept = true,
		upgradeSortKey = "gain", upgradeSortDesc = true, showDismissed = false,
		ahMinPercent = 20, ahMinCopper = 10, bagsMatsOnly = false }, -- Bags: AH only when it pays this much more than a vendor
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

SLASH_CRAFTWISE1 = "/cw"
SLASH_CRAFTWISE2 = "/craftwise"
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
