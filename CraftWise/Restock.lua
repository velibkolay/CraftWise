-- Vendor restock reminders (issue #289): "remind me when <item> may be back at <vendor>". A reminder is a
-- vendor (NPC id, name, zone, map and coordinates as Merchant.lua recorded them), an item and a due time.
-- The time is what the player picks (1 / 2 / 6 / 12 hours, or a number of hours by slash command), or the
-- one the stock log of that item supports (Merchant.Learned: "restocked within ..."); no restock time is
-- ever assumed. Stored account-wide in CraftWiseDB.reminders (a list, oldest first):
--   { id, npcID, vendor, zone, map, x, y, itemID, item, set, due }
-- Due reminders fire once: a line in the loot toast's place (clicking it sets the waypoint, Merchant.Waypoint)
-- and a chat line, with the sale-alert sound when that is on. A reminder that came due while offline fires at
-- login. The check runs every CHECK_SECONDS and at login; it only reads the clock.
local _, ns = ...

local R = {}
ns.Restock = R

R.CHOICES = { 1, 2, 6, 12 } -- hours offered next to a learned time
R.CHECK_SECONDS = 30
R.LOGIN_DELAY = 5 -- seconds after login before the first check, so the toast can draw
R.MAX_HOURS = 24 * 14
R.DURATION = 20 -- seconds a due line stays

local function Store()
	if not ns.db then
		return nil
	end
	ns.db.reminders = ns.db.reminders or {}
	return ns.db.reminders
end

function R.List()
	return Store() or {}
end

local function Merchant(npcID)
	return ns.db and ns.db.merchants and ns.db.merchants[npcID]
end

local function ItemName(itemID, m)
	local name = ns.ItemInfoNow and select(1, ns.ItemInfoNow(itemID))
	if name then
		return name
	end
	local item = m and ((m.items and m.items[itemID]) or (m.gone and m.gone[itemID]))
	return item and item.name or nil
end

-- The time choices for a vendor and item: the learned one first when the stock log has it, then the
-- fixed hours. { { seconds, label, learned = true | nil } }.
function R.Choices(npcID, itemID)
	local out = {}
	local m = Merchant(npcID)
	local source = m and ((m.items and m.items[itemID]) or (m.gone and m.gone[itemID]))
	local learned = source and ns.Merchant.Learned(source)
	if learned then
		out[1] = { seconds = learned.within, learned = true,
			label = (ns.L["Learned: %s"]):format(ns.Merchant.Span(learned.within)) }
	end
	for _, h in ipairs(R.CHOICES) do
		out[#out + 1] = { seconds = h * 3600, label = (ns.L["%d h"]):format(h) }
	end
	return out
end

function R.Find(npcID, itemID)
	for i, r in ipairs(R.List()) do
		if r.npcID == npcID and r.itemID == itemID then
			return r, i
		end
	end
end

-- Sets a reminder (replacing one for the same vendor and item). Returns the record, or nil and why.
function R.Add(npcID, itemID, seconds, now)
	local list = Store()
	local m = Merchant(npcID)
	if not (list and m and itemID) then
		return nil, ns.L["That vendor is not recorded"]
	end
	if not (seconds and seconds >= 60 and seconds <= R.MAX_HOURS * 3600) then
		return nil, ns.L["Choose a time between 1 minute and 14 days"]
	end
	now = now or time()
	local old, index = R.Find(npcID, itemID)
	if old then
		table.remove(list, index)
	end
	local id = 1
	for _, r in ipairs(list) do
		id = math.max(id, (r.id or 0) + 1)
	end
	local rec = { id = id, npcID = npcID, vendor = m.name or ("NPC " .. npcID), zone = m.zone,
		map = m.map, x = m.x, y = m.y, itemID = itemID, item = ItemName(itemID, m),
		set = now, due = now + math.floor(seconds) }
	list[#list + 1] = rec
	ns.Notify("REMINDERS_CHANGED")
	return rec
end

function R.Remove(id)
	local list = R.List()
	for i, r in ipairs(list) do
		if r.id == id then
			table.remove(list, i)
			ns.Notify("REMINDERS_CHANGED")
			return true
		end
	end
	return false
end

-- Reminders due at `now`, oldest due first.
function R.Due(now)
	local out = {}
	for _, r in ipairs(R.List()) do
		if r.due <= now then
			out[#out + 1] = r
		end
	end
	table.sort(out, function(a, b)
		return a.due < b.due
	end)
	return out
end

local function Name(r)
	return r.item or ("item " .. tostring(r.itemID))
end

-- "Raptor Hide Harness may be back at Tunkk (Hammerfall)".
function R.Text(r)
	local place = r.zone and (r.vendor .. " (" .. r.zone .. ")") or r.vendor
	return (ns.L["%s may be back at %s"]):format(Name(r), place)
end

-- "Raptor Hide Harness at Tunkk · in 2h 5m" for lists.
function R.Line(r, now)
	local left = r.due - (now or time())
	local when = left <= 0 and ns.L["due"] or (ns.L["in %s"]):format(ns.Merchant.Span(left))
	return ("%s at %s · %s"):format(Name(r), r.vendor, when)
end

local function Chime()
	local A = ns.AuctionAlert
	if A and A.SoundEnabled() and SOUNDKIT and SOUNDKIT[A.SOUND] and PlaySound then
		PlaySound(SOUNDKIT[A.SOUND])
	end
end

function R.Waypoint(r)
	return ns.Merchant.Waypoint({ merchant = { map = r.map, x = r.x, y = r.y, name = r.vendor } })
end

-- Fires every due reminder once and removes it. Returns how many fired.
function R.Check(now)
	if not ns.db then
		return 0
	end
	local due = R.Due(now or time())
	for _, r in ipairs(due) do
		R.Remove(r.id)
		local located = r.map and r.x and r.y
		if ns.Print then
			ns.Print(R.Text(r) .. (located and (" · " .. ns.L["click the line on screen for a waypoint"]) or ""))
		end
		if ns.LootToast and ns.LootToast.ShowCustom then
			ns.LootToast.ShowCustom({
				key = "restock:" .. r.id, itemID = r.itemID,
				icon = r.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID) or nil,
				text = R.Text(r), detail = located and ns.L["Waypoint"] or nil, duration = R.DURATION,
				onClick = function()
					local ok, why = R.Waypoint(r)
					if ns.Print then
						ns.Print(ok and (ns.L["Waypoint set at %s."]):format(r.vendor) or ((why or ns.L["No waypoint"]) .. "."))
					end
				end,
			})
		end
	end
	if #due > 0 then
		Chime()
	end
	return #due
end

local ticker
function R.Start()
	if ticker or not (C_Timer and C_Timer.NewTicker) then
		return
	end
	ticker = C_Timer.NewTicker(R.CHECK_SECONDS, function()
		R.Check()
	end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
	R.Start()
	if C_Timer and C_Timer.After then
		C_Timer.After(R.LOGIN_DELAY, function()
			R.Check()
		end)
	else
		R.Check()
	end
end)

-- The NPC id of the merchant window that is open, or nil.
function R.OpenMerchant()
	if not (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() and UnitGUID and ns.Sources and ns.Sources.ParseGUID) then
		return nil
	end
	local kind, npcID = ns.Sources.ParseGUID(UnitGUID("npc"))
	return kind == "Creature" and npcID or nil
end

-- `/craftwise remind`: no argument lists the reminders; `remind remove <n>` deletes the n-th;
-- `remind <hours> <item link, id or name>` sets one at the open merchant, else at the nearest recorded
-- vendor that lists the item.
function R.Slash(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	local list = R.List()
	if arg == "" then
		if #list == 0 then
			ns.Print("no restock reminders. /craftwise remind <hours> <item> sets one.")
			return
		end
		for i, r in ipairs(list) do
			ns.Print(("%d. %s"):format(i, R.Line(r)))
		end
		return
	end
	local n = tonumber(arg:match("^remove%s+(%d+)$") or arg:match("^delete%s+(%d+)$"))
	if n then
		local r = list[n]
		if r and R.Remove(r.id) then
			ns.Print(("removed: %s"):format(R.Line(r)))
		else
			ns.Print(("no reminder %d"):format(n))
		end
		return
	end
	local hours, rest = arg:match("^([%d%.]+)%s*h?%s+(.+)$")
	hours = tonumber(hours)
	if not (hours and rest) then
		ns.Print("usage: /craftwise remind <hours> <item link, id or name> | remind remove <n>")
		return
	end
	local itemID = tonumber(rest) or tonumber(rest:match("item:(%d+)"))
	if not itemID then
		itemID = (ns.Merchant.FindItems(rest))[1]
	end
	if not itemID then
		ns.Print(("no recorded item named \"%s\""):format(rest))
		return
	end
	local npcID = R.OpenMerchant()
	if not npcID then
		local all = ns.Merchant.BuyAtAll(itemID)
		local entry = all and (all.nearest or all.entries[1])
		npcID = entry and entry.npcID
	end
	if not npcID then
		ns.Print("no recorded vendor for that item; open the vendor first")
		return
	end
	local status = ns.Merchant.ListingText(ns.Merchant.ListingStatus(npcID, itemID))
	if status then
		ns.Print(("%s: %s"):format(Merchant(npcID).name or ("NPC " .. npcID), status))
	end
	local rec, why = R.Add(npcID, itemID, hours * 3600)
	ns.Print(rec and ("reminder set: " .. R.Line(rec)) or (why .. "."))
end
