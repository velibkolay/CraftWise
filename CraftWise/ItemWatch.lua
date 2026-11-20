-- Items watch list (issue #165, part 1; the spec is Look up › Items in #150).
-- Saved shape (account wide, CraftWiseDB, read later by the companion for the site's favourites):
--   db.watch     = { [itemID] = addedAt }     addedAt = Unix time (seconds) the item was watched.
--   db.watchGone = { [itemID] = removedAt }   tombstones (#244): the item was unwatched at that time. They
--                  keep a removal from being undone by the other machine or the site; dropped after 180 days.
-- Two-way (#244, two machines #237): the companion uploads the changes of this list, merges the other machine's
-- and the site's changes into one list and writes it to CraftWiseSync.watch / .watchGone (the data addon
-- CraftWise_Sync); Watch.MergeSync reads those at login. Per item the newest change wins; on the same
-- second "watched" wins, so an item is never lost to a tie.
-- Account wide like keep / junk / sellAH / dismissed: the site's favourites are per account too, and an
-- item is watched whichever character looks at it. Absent = not watched (no false values are stored).
-- API: ns.ItemWatch = { List, IsWatched, Toggle, Set, AddedAt }; Look up › Items (chip and card toggle)
-- and the item menu use it. Changes fire ns.Notify("ITEM_WATCH_CHANGED", itemID, watched).
local _, ns = ...

local Watch = {}
ns.ItemWatch = Watch

local function Store(create)
	if not ns.db then
		return nil
	end
	if create and type(ns.db.watch) ~= "table" then
		ns.db.watch = {}
	end
	return ns.db.watch
end

local function Gone(create)
	if not ns.db then
		return nil
	end
	if create and type(ns.db.watchGone) ~= "table" then
		ns.db.watchGone = {}
	end
	return ns.db.watchGone
end

local GONE_KEEP = 180 * 86400

function Watch.IsWatched(itemID)
	local w = Store()
	return w ~= nil and w[itemID] ~= nil
end

-- Unix time the item was watched, or nil.
function Watch.AddedAt(itemID)
	local w = Store()
	return w and w[itemID] or nil
end

-- Item IDs, oldest first (ties by ID).
function Watch.List()
	local ids = {}
	local w = Store()
	if w then
		for id in pairs(w) do
			ids[#ids + 1] = id
		end
		table.sort(ids, function(a, b)
			local ta, tb = tonumber(w[a]) or 0, tonumber(w[b]) or 0
			if ta ~= tb then
				return ta < tb
			end
			return a < b
		end)
	end
	return ids
end

-- Sets the state; returns it. Watching an item already watched keeps its added time.
function Watch.Set(itemID, on)
	if type(itemID) ~= "number" or not ns.db then
		return false
	end
	local w = Store(true)
	on = on and true or false
	if on == (w[itemID] ~= nil) then
		return on
	end
	local gone = Gone(true)
	if on then
		w[itemID] = time()
		gone[itemID] = nil
	else
		w[itemID] = nil
		gone[itemID] = time()
	end
	ns.Notify("ITEM_WATCH_CHANGED", itemID, on)
	return on
end

local function IsTime(t)
	return type(t) == "number" and t >= 1600000000 and t == math.floor(t)
end

-- Merges the watch list of CraftWiseSync (file.watch = { [itemID] = time watched }, file.watchGone =
-- { [itemID] = time unwatched }, written by the companion) into the own one: per item the newest change wins,
-- on the same second "watched" wins. Own changes the companion has not uploaded yet win when they are newer.
-- Returns how many items changed. Running it again changes nothing.
function Watch.MergeSync(file)
	if type(file) ~= "table" or not ns.db then
		return 0
	end
	local w, gone = Store(true), Gone(true)
	local changed = 0
	local function Apply(itemID, t, on)
		if type(itemID) ~= "number" or itemID < 1 or itemID ~= math.floor(itemID) or not IsTime(t) then
			return
		end
		local mine = w[itemID] or gone[itemID]
		local mineOn = w[itemID] ~= nil
		if mine and (t < mine or (t == mine and (mineOn or not on))) then
			return -- the own state is newer, or the same
		end
		w[itemID], gone[itemID] = nil, nil
		if on then
			w[itemID] = t
		else
			gone[itemID] = t
		end
		if on ~= mineOn then
			changed = changed + 1
			ns.Notify("ITEM_WATCH_CHANGED", itemID, on)
		end
	end
	if type(file.watchGone) == "table" then
		for itemID, t in pairs(file.watchGone) do
			Apply(itemID, t, false)
		end
	end
	if type(file.watch) == "table" then
		for itemID, t in pairs(file.watch) do
			Apply(itemID, t, true)
		end
	end
	local limit = time() - GONE_KEEP
	for itemID, t in pairs(gone) do
		if type(t) ~= "number" or t < limit then
			gone[itemID] = nil
		end
	end
	return changed
end

-- At login (and /reload) the loading screen is up: merge what the companion wrote.
ns.On("PLAYER_LOGIN", function()
	local file = _G.CraftWiseSync
	if type(file) == "table" and file.v == 1 then
		Watch.MergeSync(file)
	end
	if type(file) == "table" then
		file.watch, file.watchGone = nil, nil
	end
end)

function Watch.Toggle(itemID)
	return Watch.Set(itemID, not Watch.IsWatched(itemID))
end
