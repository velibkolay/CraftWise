-- Items watch list (issue #165, part 1; the spec is Look up › Items in #150).
-- Saved shape (account wide, CraftWiseDB, read later by the companion for the site's favourites):
--   db.watch = { [itemID] = addedAt }   addedAt = Unix time (seconds) the item was watched.
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
	w[itemID] = on and time() or nil
	ns.Notify("ITEM_WATCH_CHANGED", itemID, on)
	return on
end

function Watch.Toggle(itemID)
	return Watch.Set(itemID, not Watch.IsWatched(itemID))
end
