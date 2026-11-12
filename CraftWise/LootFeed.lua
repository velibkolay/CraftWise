-- Loot feed (#126): the one place that tells what the player just looted, for every module that shows
-- or counts it (LootToast.lua, Farm.lua, Fishing.lua's opened log). Detection moved here from the loot
-- toast (#114); containers opened from the bags added in #135:
--
--   * Items: CHAT_MSG_LOOT lines of the player's own receipts, read with the client's own format strings
--     LOOT_ITEM_SELF_MULTIPLE and LOOT_ITEM_SELF ("You receive loot: %sx%d." / "You receive loot: %s." in
--     English; every locale's client has its own), so only items that actually reached the bags count,
--     with or without the loot window and whoever loots (Loot.lua, Blizzard, another addon). Items pushed
--     without looting (quest rewards, LOOT_ITEM_PUSHED_SELF) and other players' loot are left out.
--     The text may be a secret value on 12.x clients (Market.lua's OnLoot has the same note): such a line
--     is skipped, the item still reaches the bags.
--   * Containers opened from the bags (#135): a loot window whose LOOT_OPENED says isFromItem (the payload
--     Blizzard's Forever LootFrame.lua uses for its container sound). Whether the client writes a chat line
--     for what such a window gives, and in which form (LOOT_ITEM_SELF or LOOT_ITEM_PUSHED_SELF), is not
--     relied on: the window's slots are read on LOOT_READY, before anything is looted (Loot.lua calls
--     Capture first), and two things tell that a slot reached the bags:
--       - LOOT_SLOT_CLEARED for the slot (Blizzard's LootFrame hides the slot's row on it), and
--       - a receipt line for the slot's item while the window is open, or within CONTAINER_SECONDS after it
--         closed and before the next loot window: LOOT_ITEM_SELF(_MULTIPLE) or LOOT_ITEM_PUSHED_SELF(_MULTIPLE).
--     Per item the window counts the larger of the two, never more than the window held, so it counts once
--     whether one, both or (for the line) neither arrive, in any order. A pushed line counts only this way,
--     for an item of an open container window: a quest reward pushed at any other time never counts. Lines
--     that come before LOOT_OPENED has said where the window came from wait for it.
--     The container is the locked bag slot whose item has loot (C_Container.GetContainerItemInfo isLocked
--     and hasLoot), as Fishing.lua found it before (#69). Opening the same container again after it was left
--     with items in it (bags full) is the same opening. Coin in a container counts like any coin (below).
--   * Coin: the money the player gained (PLAYER_MONEY, GetMoney before and after), passed on only when a
--     CHAT_MSG_MONEY (the client's "You loot ..." / "Your share of the loot is ...") arrives within
--     MONEY_PAIR_SECONDS of it, in either order. The amount is the exact copper difference; the message
--     text is never parsed, so no locale's coin wording matters. Vendor sales, mail and quest rewards
--     change the money without that message and are not passed on.
--
-- Subscribers: ns.LootFeed.Subscribe(fn); fn("item", { link, count, itemID, container, opening }),
-- fn("money", { copper }) or fn("opened", { container, link, items, coin, opening }).
--   "opened": once per container opening, on LOOT_OPENED, before its items: container = the opened item's
--   ID (nil when no locked bag slot was found), link its hyperlink, items = { [itemID] = units } the window
--   held, coin = the window had a coin slot, opening = a number for this opening.
--   "item" from a container window carries the same container and opening; other items have neither.
-- Each loot is emitted once; a subscriber that raises doesn't stop the others (its error is raised
-- again after them).
local _, ns = ...

local F = {}
ns.LootFeed = F

F.MONEY_PAIR_SECONDS = 2

local subscribers = {}

function F.Subscribe(fn)
	subscribers[#subscribers + 1] = fn
end

function F.Emit(kind, data)
	local firstErr
	for _, fn in ipairs(subscribers) do
		local ok, err = pcall(fn, kind, data)
		if not ok and not firstErr then
			firstErr = err
		end
	end
	if firstErr then
		error(firstErr, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Parsing
----------------------------------------------------------------------------------------------------

-- Lua pattern for a client format string, and the argument index of each capture. %s matches any text,
-- %d digits; positional forms (%1$s, %2$d) some locales use are honoured.
function F.Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local order = {}
	local s = fmt:gsub("%%(%d)%$([sd])", function(index, kind)
		order[#order + 1] = tonumber(index)
		return "\1" .. kind
	end)
	s = s:gsub("%%([sd])", function(kind)
		order[#order + 1] = #order + 1
		return "\1" .. kind
	end)
	s = s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	s = s:gsub("\1s", "(.+)"):gsub("\1d", "(%%d+)")
	return "^" .. s .. "$", order
end

local function Match(text, fmt)
	local pattern, order = F.Pattern(fmt)
	if not pattern then
		return nil
	end
	local caps = { text:match(pattern) }
	if #caps == 0 then
		return nil
	end
	local args = {}
	for i, index in ipairs(order) do
		args[index] = caps[i]
	end
	return args
end

-- Item link and count of one of the player's own loot lines, or nil (someone else's loot, another
-- message, a secret value). The multiple form first: the single one's %s would swallow "x2".
function F.ParseLoot(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return nil
	end
	local args = Match(text, LOOT_ITEM_SELF_MULTIPLE)
	if args and args[1] and args[2] then
		return args[1], tonumber(args[2])
	end
	args = Match(text, LOOT_ITEM_SELF)
	if args and args[1] then
		return args[1], 1
	end
	return nil
end

-- Item link and count of a line for an item pushed into the player's bags (LOOT_ITEM_PUSHED_SELF(_MULTIPLE),
-- "You receive item: %s." in English: quest rewards, and on some clients what a container gives), or nil.
function F.ParsePushed(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return nil
	end
	local args = Match(text, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
	if args and args[1] and args[2] then
		return args[1], tonumber(args[2])
	end
	args = Match(text, LOOT_ITEM_PUSHED_SELF)
	if args and args[1] then
		return args[1], 1
	end
	return nil
end

function F.ItemID(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

local function Safe(value)
	if value ~= nil and issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- Errors of subscribers during one event: the handler finishes, then the first one is raised.
local raised

local function Send(kind, data)
	local ok, err = pcall(F.Emit, kind, data)
	if not ok and not raised then
		raised = err
	end
end

local function Handler(fn)
	return function(...)
		raised = nil
		local ok, err = pcall(fn, ...)
		local e = raised or (not ok and err) or nil
		raised = nil
		if e then
			error(e, 0)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Loot windows (#135): what a container opened from the bags gives
----------------------------------------------------------------------------------------------------

F.CONTAINER_SECONDS = 3 -- a container window's receipt lines may come this long after it closed

-- The current or last loot window: { open, closedAt, slots = { [slot] = { itemID, n } | { coin } },
-- items = { [itemID] = units }, links, coin, fromItem (nil until LOOT_OPENED), cleared = { [slot] },
-- byClear / byLine / counted = { [itemID] = units }, held = { lines waiting for LOOT_OPENED },
-- container, opening }.
local win
local openings = 0
local lastOpening -- { bag, slot, itemID, id, win } of the last container opened

local function ReadWindow()
	local w = { open = true, slots = {}, items = {}, links = {}, coin = false, cleared = {}, byClear = {}, byLine = {},
		counted = {}, held = {} }
	if not (GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then
		return w
	end
	for slot = 1, Safe(GetNumLootItems()) or 0 do
		local link = Safe(GetLootSlotLink(slot))
		local itemID = F.ItemID(link)
		local _, _, quantity, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(slot)
		quantity, currencyID, isCoin = Safe(quantity), Safe(currencyID), Safe(isCoin)
		if isCoin == true then
			w.coin = true
			w.slots[slot] = { coin = true }
		elseif itemID and not currencyID then
			local n = math.max(1, tonumber(quantity) or 1)
			w.slots[slot] = { itemID = itemID, n = n }
			w.items[itemID] = (w.items[itemID] or 0) + n
			w.links[itemID] = link
		end
	end
	return w
end

-- The opened container: bag, slot, item ID and link of the locked bag slot whose item has loot.
function F.OpenedContainer()
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
		return nil
	end
	for bag = 0, ns.LAST_BAG or 5 do
		for slot = 1, Safe(C_Container.GetContainerNumSlots(bag)) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and Safe(info.itemID)
			if itemID and Safe(info.isLocked) and Safe(info.hasLoot) then
				return bag, slot, itemID, Safe(info.hyperlink)
			end
		end
	end
end

-- Passes on what is now known to have reached the bags from an item of a container window.
local function Credit(w, itemID)
	local want = math.min(w.items[itemID] or 0, math.max(w.byClear[itemID] or 0, w.byLine[itemID] or 0))
	local d = want - (w.counted[itemID] or 0)
	if d > 0 then
		w.counted[itemID] = want
		Send("item", { link = w.links[itemID], count = d, itemID = itemID, container = w.container, opening = w.opening })
	end
end

local function ApplyClear(w, slot)
	local s = w.slots[slot]
	if s and s.itemID then
		w.byClear[s.itemID] = (w.byClear[s.itemID] or 0) + s.n
		Credit(w, s.itemID)
	end
end

-- Items of the window not (yet) known to have left it.
local function Left(w)
	for itemID, n in pairs(w.items) do
		if (w.counted[itemID] or 0) < n then
			return true
		end
	end
	return false
end

local function Live(w)
	return w ~= nil and (w.open or (w.closedAt ~= nil and GetTime() - w.closedAt <= F.CONTAINER_SECONDS))
end

-- One receipt line: kind "self" (LOOT_ITEM_SELF) or "pushed" (LOOT_ITEM_PUSHED_SELF).
local function Line(kind, link, count, itemID)
	local w = win
	if Live(w) and w.items[itemID] then
		if w.fromItem == nil then
			w.held[#w.held + 1] = { kind, link, count, itemID }
			return
		end
		if w.fromItem then
			local take = math.min(count, math.max(0, w.items[itemID] - (w.byLine[itemID] or 0)))
			if take > 0 then
				w.byLine[itemID] = (w.byLine[itemID] or 0) + take
				w.links[itemID] = link or w.links[itemID]
				Credit(w, itemID)
			end
			count = count - take
			if count <= 0 then
				return
			end
		end
	end
	if kind == "self" then
		Send("item", { link = link, count = count, itemID = itemID })
	end
end

-- LOOT_OPENED tells where the window came from; until then its slots and lines wait.
local function Classify(w, fromItem)
	if w.fromItem ~= nil then
		return
	end
	w.fromItem = fromItem
	if fromItem then
		local bag, slot, itemID, link = F.OpenedContainer()
		local last = lastOpening
		if last and itemID and last.bag == bag and last.slot == slot and last.itemID == itemID and Left(last.win) then
			-- Opened again after it was left with items in it: the same opening.
			w.container, w.opening = itemID, last.id
			last.win = w
		else
			openings = openings + 1
			w.container, w.opening = itemID, openings
			lastOpening = { bag = bag, slot = slot, itemID = itemID, id = openings, win = w }
			local items = {}
			for id, n in pairs(w.items) do
				items[id] = n
			end
			Send("opened", { container = itemID, link = link, items = items, coin = w.coin, opening = openings })
		end
		for clearedSlot in pairs(w.cleared) do
			ApplyClear(w, clearedSlot)
		end
	end
	local held = w.held
	w.held = {}
	for _, l in ipairs(held) do
		Line(l[1], l[2], l[3], l[4])
	end
end

local function Capture()
	if win and win.open then
		return
	end
	local prev = win
	win = ReadWindow()
	if prev and prev.fromItem == nil then
		Classify(prev, false)
	end
end

-- Reads the loot window before anything leaves it; once per window. Loot.lua calls it on LOOT_READY before
-- fast auto-loot takes the slots. Never raises (an error is raised on the next frame).
function F.Capture()
	raised = nil
	local ok, err = pcall(Capture)
	local e = raised or (not ok and err) or nil
	raised = nil
	if e and C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			error(e, 0)
		end)
	end
end

F.OnReady = Handler(Capture)

F.OnOpened = Handler(function(_, _, isFromItem)
	if not (win and win.open) then
		Capture()
	end
	Classify(win, Safe(isFromItem) == true)
end)

F.OnSlotCleared = Handler(function(_, slot)
	local w = win
	slot = Safe(slot)
	if not (Live(w) and slot and w.slots[slot]) or w.cleared[slot] then
		return
	end
	w.cleared[slot] = true
	if w.fromItem then
		ApplyClear(w, slot)
	end
end)

F.OnClosed = Handler(function()
	local w = win
	if not (w and w.open) then
		return
	end
	w.open, w.closedAt = false, GetTime()
	Classify(w, false)
end)

F.OnLoot = Handler(function(_, text)
	local kind, link, count = "self", F.ParseLoot(text)
	if not link then
		kind, link, count = "pushed", F.ParsePushed(text)
	end
	local itemID = link and F.ItemID(link)
	if itemID then
		Line(kind, link, count or 1, itemID)
	end
end)

-- Coin: a money gain and a CHAT_MSG_MONEY within MONEY_PAIR_SECONDS, in either order.
local lastMoney, gain, moneyMsg -- gain = { copper, t }; moneyMsg = t of an unpaired CHAT_MSG_MONEY

local function Fresh(t, now)
	return t and now - t <= F.MONEY_PAIR_SECONDS
end

function F.OnMoney()
	local now, money = GetTime(), GetMoney()
	local before = lastMoney
	lastMoney = money
	if not before or money <= before then
		return
	end
	local copper = money - before
	if Fresh(moneyMsg, now) then
		moneyMsg, gain = nil, nil
		F.Emit("money", { copper = copper })
		return
	end
	if gain and Fresh(gain.t, now) then
		gain.copper = gain.copper + copper -- several changes before the message: one loot
	else
		gain = { copper = copper, t = now }
	end
end

function F.OnMoneyMessage()
	local now = GetTime()
	if gain and Fresh(gain.t, now) then
		local copper = gain.copper
		gain, moneyMsg = nil, nil
		F.Emit("money", { copper = copper })
		return
	end
	gain, moneyMsg = nil, now
end

local function NoteMoney()
	lastMoney = GetMoney()
end

ns.On("LOOT_READY", F.OnReady)
ns.On("LOOT_OPENED", F.OnOpened)
ns.On("LOOT_SLOT_CLEARED", F.OnSlotCleared)
ns.On("LOOT_CLOSED", F.OnClosed)
ns.On("CHAT_MSG_LOOT", F.OnLoot)
ns.On("CHAT_MSG_MONEY", F.OnMoneyMessage)
ns.On("PLAYER_MONEY", F.OnMoney)
ns.On("PLAYER_LOGIN", NoteMoney)
ns.On("PLAYER_ENTERING_WORLD", NoteMoney)

-- Fishing.lua loads before this file: its opened log (#69) reads container openings from here.
if ns.Fishing and ns.Fishing.OnFeed then
	F.Subscribe(ns.Fishing.OnFeed)
end
