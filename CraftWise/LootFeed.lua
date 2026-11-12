-- Loot feed (#126): the one place that tells what the player just looted, for every module that shows
-- or counts it (LootToast.lua, Farm.lua). Detection moved here unchanged from the loot toast (#114):
--
--   * Items: CHAT_MSG_LOOT lines of the player's own receipts, read with the client's own format strings
--     LOOT_ITEM_SELF_MULTIPLE and LOOT_ITEM_SELF ("You receive loot: %sx%d." / "You receive loot: %s." in
--     English; every locale's client has its own), so only items that actually reached the bags count,
--     with or without the loot window and whoever loots (Loot.lua, Blizzard, another addon). Items pushed
--     without looting (quest rewards, LOOT_ITEM_PUSHED_SELF) and other players' loot are left out.
--     The text may be a secret value on 12.x clients (Market.lua's OnLoot has the same note): such a line
--     is skipped, the item still reaches the bags.
--   * Coin: the money the player gained (PLAYER_MONEY, GetMoney before and after), passed on only when a
--     CHAT_MSG_MONEY (the client's "You loot ..." / "Your share of the loot is ...") arrives within
--     MONEY_PAIR_SECONDS of it, in either order. The amount is the exact copper difference; the message
--     text is never parsed, so no locale's coin wording matters. Vendor sales, mail and quest rewards
--     change the money without that message and are not passed on.
--
-- Subscribers: ns.LootFeed.Subscribe(fn); fn("item", { link, count, itemID }) or fn("money", { copper }).
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

function F.ItemID(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

function F.OnLoot(_, text)
	local link, count = F.ParseLoot(text)
	local itemID = link and F.ItemID(link)
	if itemID then
		F.Emit("item", { link = link, count = count or 1, itemID = itemID })
	end
end

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

ns.On("CHAT_MSG_LOOT", F.OnLoot)
ns.On("CHAT_MSG_MONEY", F.OnMoneyMessage)
ns.On("PLAYER_MONEY", F.OnMoney)
ns.On("PLAYER_LOGIN", NoteMoney)
ns.On("PLAYER_ENTERING_WORLD", NoteMoney)
