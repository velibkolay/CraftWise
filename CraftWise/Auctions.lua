-- Auction tracker (issue #81): what this character has listed, what sold and how much gold is on its
-- way by mail, what expired, and what the sale mails paid. Only this account's own auctions.
--
-- Sources, all read only (nothing is queried, opened or clicked on the player's behalf):
--   Post      C_AuctionHouse.PostItem / PostCommodity (and ConfirmPost*) hooked for the details, the
--             auction is recorded when the client confirms it with AUCTION_HOUSE_AUCTION_CREATED.
--             PostItem prices are per unit: Blizzard's ItemSellFrame totals quantity * buyout.
--             A non-stacking item posted N times at once (multisell) gives N auctions of 1.
--   Owned     OWNED_AUCTIONS_UPDATED: the client's owned list (C_AuctionHouse.GetOwnedAuctionInfo, as
--             Blizzard's Auctions tab reads it) when it has one. It gives the auction ID, quantity, time
--             left and status (Enum.AuctionStatus: Active 0, Sold 1). CraftWise never sends the query.
--   Sold      AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION (AuctionSold / AuctionExpired, item name and
--             maybe the auction ID). Blizzard's Forever UI prints ERR_AUCTION_SOLD_S / ERR_AUCTION_EXPIRED_S
--             from it straight into the chat frame (Blizzard_Game EventImplementation.lua,
--             ChatFrameUtil.GetAuctionHouseNotificationText), so CHAT_MSG_SYSTEM may never carry the
--             text. CHAT_MSG_SYSTEM is read too, with patterns built from those global strings; the
--             same message from both sources counts once.
--   Expired   the AuctionExpired notification, the chat message and AUCTION_HOUSE_AUCTIONS_EXPIRED.
--   Cancelled AUCTION_CANCELED (auction ID).
--   Mail      TakeInboxMoney / AutoLootMailItem / TakeInboxItem hooked. A sale mail is an invoice of
--             type "seller" (GetInboxInvoiceInfo, as Blizzard's MailFrame.lua reads it): sale price,
--             deposit, house cut (consignment), count. It settles when the money arrives (PLAYER_MONEY).
--             A returned item is a mail whose subject matches AUCTION_EXPIRED_MAIL_SUBJECT or
--             AUCTION_REMOVED_MAIL_SUBJECT; it settles when the item is in the bags.
--
-- Storage: CraftWiseMarketDB.auctions = { v = 1, chars = { [ns.CharKey()] = { list, ownedAt, ownedHouse } } }
--   list = { auction, ... }, auction = {
--     id      auction ID (nil until the client names it)    i, n, l   item ID, name, link
--     q       units in this auction                          kind      "item" | "commodity"
--     unit    buyout per unit (nil = bid only)               bid       bid per unit (nil = buyout only)
--     dur     duration index (1-3), durText as the client names it, exp = expiry time when known
--     dep     deposit the client calculated for this post (postDeposit/postSize for a multisell)
--     t       posted (nil when first seen in the owned list: untracked = true)   h  house key (#26)
--     st      "active" | "sold" (awaiting mail) | "gone" (sold or cancelled, uncertain) |
--             "expired" | "cancelled" (item on its way back by mail) | "settled" (sale money taken) |
--             "returned" (returned item taken)
--     soldT, soldVia, expT, settledT, received, sale, cut, saleDeposit, returnedT,
--     uncertain + candidates   matched by item name among several open auctions of that item
--     qtyUnknown               a commodity sold message: some or all of q units, which is unknown
--   }
--   Cut samples go to CraftWiseMarketDB.cutSamples (#26 phase 3): { house, listed, received, cut,
--   deposit, t, i, q }, last 50. Sale money goes to the ledger as kind "ahsell" (#46).
--
-- Expected payout only where the cut is confirmed or measured (ns.CutInfo, Prices.lua): never assumed.
local _, ns = ...

local A = {}
ns.Auctions = A

local KEEP_DAYS = 30
local DAY_SECONDS = 86400
local PENDING_SECONDS = 30 -- a mail take waits this long for its money or items
local NOTE_SECONDS = 2 -- the same sold/expired message from two sources arrives within this
local INFER_AFTER_SECONDS = 60 -- a fresh post may not be in an owned list the client fetched earlier
local MAIL_ATTACHMENTS = 16
local CUT_SAMPLES_KEPT = 50

A.STATUS_TEXT = {
	active = "listed",
	sold = "sold, awaiting mail",
	gone = "sold or cancelled (uncertain)",
	expired = "expired, returned via mail",
	cancelled = "cancelled, returned via mail",
	settled = "sold, money collected",
	returned = "returned item collected",
}

local store -- CraftWiseMarketDB.auctions

----------------------------------------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------------------------------------

local function Char(key)
	key = key or ns.CharKey()
	if not (store and key) then
		return nil
	end
	local c = store.chars[key]
	if not c then
		c = { list = {} }
		store.chars[key] = c
	end
	c.list = c.list or {}
	return c
end

function A.List(charKey)
	local c = Char(charKey)
	return c and c.list or nil
end

local function Changed(rec)
	ns.Notify("AUCTIONS_CHANGED", rec)
end

-- Name as chat and mail show it: from the link (keeps a random suffix), else the client's name.
local function NameOf(rec)
	local fromLink = rec.l and rec.l:match("|h%[(.-)%]|h")
	if fromLink then
		return fromLink
	end
	if not rec.n and rec.i then
		rec.n = (ns.ItemInfoNow(rec.i))
	end
	return rec.n
end
A.NameOf = NameOf

local function ById(list, auctionID)
	if not auctionID then
		return nil
	end
	for _, rec in ipairs(list) do
		if rec.id == auctionID then
			return rec
		end
	end
	return nil
end

-- Every record passing test, oldest post first (records first seen in the owned list count as oldest).
local function Candidates(list, test)
	local found = {}
	for _, rec in ipairs(list) do
		if test(rec) then
			found[#found + 1] = rec
		end
	end
	table.sort(found, function(a, b)
		return (a.t or 0) < (b.t or 0)
	end)
	return found
end

-- Takes `n` units out of a record into a new record right after it; the original keeps the rest.
local function Split(list, rec, n)
	local part = {}
	for k, v in pairs(rec) do
		part[k] = v
	end
	part.q, part.split, part.id, part.dep = n, true, nil, nil
	rec.q = rec.q - n
	for index, r in ipairs(list) do
		if r == rec then
			table.insert(list, index + 1, part)
			break
		end
	end
	return part
end

-- A match among several candidates is flagged; `n` = how many there were.
local function MarkMatch(rec, n)
	if n and n > 1 then
		rec.uncertain, rec.candidates = true, n
	end
end

----------------------------------------------------------------------------------------------------
-- Durations, cut, expected payout
----------------------------------------------------------------------------------------------------

local DURATION_STRINGS = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }

-- The client's name of a duration index ("12 Hours"), nil when it has none.
function A.DurationText(index)
	local key = DURATION_STRINGS[index or 0]
	local text = key and _G[key]
	return type(text) == "string" and text ~= "" and text or nil
end

-- Hours of a duration index, read from the client's text; only on English clients (the text is the
-- only source; sources disagree on Forever's durations, #26). Owned lists give the exact time left.
function A.DurationHours(index)
	local text = A.DurationText(index)
	local locale = GetLocale and GetLocale()
	if not text or (locale ~= "enUS" and locale ~= "enGB") then
		return nil
	end
	return tonumber(text:match("^(%d+) [Hh]ours?$"))
end

local function HouseKind(house)
	return house and (house:find("|N:", 1, true) and "neutral" or "faction") or nil
end

-- Cut at a house: rate (nil = unverified) and ns.CutInfo's info (text, source).
function A.Cut(house)
	if not house then
		return nil, { source = "unverified", text = "cut unverified (house unknown)" }
	end
	local info = ns.CutInfo({ source = "market", house = house, houseKind = HouseKind(house) })
	return info.cut, info
end

-- Sale price of the whole record: price, or nil and why.
function A.SalePrice(rec)
	if rec.qtyUnknown then
		return nil, "units sold unknown"
	end
	if not rec.unit then
		return nil, rec.untracked and "price not recorded (listed before tracking)" or "bid only: sale price unknown"
	end
	if rec.bid then
		return nil, "bid and buyout: sale price unknown"
	end
	return rec.unit * rec.q
end

-- What the sale mail should bring: payout, cut text, sale price; payout nil with the reason when the
-- price or the cut isn't known. The cut is rounded to whole copper (the client's rounding is checked
-- against the sale mails' cut samples).
local function AfterCut(price, house)
	local cut, info = A.Cut(house)
	if not cut then
		return nil, info.text
	end
	return price - math.floor(price * cut + 0.5), info.text
end

function A.Expected(rec)
	local price, why = A.SalePrice(rec)
	if not price then
		return nil, why
	end
	local payout, note = AfterCut(price, rec.h)
	return payout, note, price
end

-- What a listed auction pays if it sells at its buyout (unit buyout x units), after the cut as in
-- A.Expected: payout, cut text, buyout total; payout nil with why: "no buyout" (bid only), "price not
-- recorded" (listed before tracking: the owned list's price may be per unit or per stack, #81) or the
-- cut text when the cut is unverified.
function A.IfSold(rec)
	if rec.untracked and not rec.unit then
		if not rec.ownedBuyout or rec.ownedBuyout <= 0 then
			return nil, "no buyout"
		end
		return nil, "price not recorded"
	end
	if not rec.unit or rec.unit <= 0 then
		return nil, "no buyout"
	end
	local price = rec.unit * rec.q
	local payout, note = AfterCut(price, rec.h)
	return payout, note, price
end

----------------------------------------------------------------------------------------------------
-- Posting
----------------------------------------------------------------------------------------------------

local pending -- the post the player started: { kind, i, n, l, q, unit, bid, dur, dep, h, left }

local function Call(fn, ...)
	if not fn then
		return nil
	end
	local ok, value = pcall(fn, ...)
	return ok and value or nil
end

local function StartPost(kind, location, duration, quantity, bid, buyout)
	pending = nil
	local itemID = C_Item and Call(C_Item.GetItemID, location)
	if not (itemID and quantity and quantity > 0) then
		return
	end
	local name, link = ns.ItemInfoNow(itemID)
	local itemLink = C_Item and Call(C_Item.GetItemLink, location)
	local deposit
	if kind == "commodity" then
		deposit = Call(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, quantity)
	else
		deposit = Call(C_AuctionHouse.CalculateItemDeposit, location, duration, quantity)
	end
	pending = { kind = kind, i = itemID, n = name, l = itemLink or link, q = quantity, unit = buyout,
		bid = bid, dur = duration, dep = deposit, h = ns.Market and ns.Market.CurrentHouse() or nil }
end

function A.OnPostItem(location, duration, quantity, bid, buyout)
	StartPost("item", location, duration, quantity, bid, buyout)
end

function A.OnPostCommodity(location, duration, quantity, unitPrice)
	StartPost("commodity", location, duration, quantity, nil, unitPrice)
end

local function StackSize(itemID)
	return C_Item and C_Item.GetItemMaxStackSizeByID and Call(C_Item.GetItemMaxStackSizeByID, itemID) or nil
end

-- AUCTION_HOUSE_AUCTION_CREATED: the post went through. Nothing is recorded without it.
function A.OnAuctionCreated(auctionID)
	local p = pending
	local c = Char()
	if not (p and c) then
		return
	end
	local multi = p.kind == "item" and p.q > 1 and StackSize(p.i) == 1
	local now = time()
	local rec = { id = auctionID, i = p.i, n = p.n, l = p.l, q = multi and 1 or p.q, unit = p.unit, bid = p.bid,
		kind = p.kind, dur = p.dur, durText = A.DurationText(p.dur), t = now, h = p.h, st = "active" }
	local hours = A.DurationHours(p.dur)
	if hours then
		rec.exp = now + hours * 3600
	end
	if multi then
		rec.postDeposit, rec.postSize = p.dep, p.q
		p.left = (p.left or p.q) - 1
		if p.left <= 0 then
			pending = nil
		end
	else
		rec.dep = p.dep
		pending = nil
	end
	c.list[#c.list + 1] = rec
	Changed(rec)
	return rec
end

function A.ForgetPost()
	pending = nil
end

----------------------------------------------------------------------------------------------------
-- Owned auctions list (only what the client already fetched)
----------------------------------------------------------------------------------------------------

local function IsSold(info)
	local status = Enum and Enum.AuctionStatus
	return status ~= nil and info.status == status.Sold
end

-- An entry of the owned list whose ID is known.
local function ApplyKnown(list, rec, info, now)
	if info.timeLeftSeconds then
		rec.exp = now + info.timeLeftSeconds
	end
	rec.l = rec.l or info.itemLink
	local quantity = info.quantity
	if IsSold(info) then
		if rec.st == "active" or rec.st == "gone" or rec.st == "expired" or rec.st == "sold" then
			if rec.st ~= "sold" then
				rec.soldT, rec.soldVia = now, "owned list"
			end
			rec.st, rec.why = "sold", nil
			if quantity and quantity < rec.q then
				-- The sold entry covers part of what was posted; the rest waits for the list to name it
				-- (adopted by a later read, or missing from it).
				local rest = Split(list, rec, rec.q - quantity)
				rest.st, rest.soldT, rest.soldVia, rest.qtyUnknown = "active", nil, nil, nil
			end
			rec.qtyUnknown, rec.uncertain, rec.candidates = nil, nil, nil -- confirmed by ID
		end
		return
	end
	-- Still listed.
	if rec.st == "gone" or rec.st == "expired" then
		rec.st, rec.why, rec.expT = "active", nil, nil
	elseif rec.st == "sold" and rec.qtyUnknown then
		-- The sold message was for some units of this commodity auction: the units no longer listed.
		if quantity and quantity < rec.q then
			local part = Split(list, rec, rec.q - quantity)
			part.st, part.qtyUnknown = "sold", nil
			rec.st, rec.soldT, rec.soldVia, rec.qtyUnknown = "active", nil, nil, nil
		else
			rec.st, rec.soldT, rec.soldVia, rec.qtyUnknown = "active", nil, nil, nil
		end
		return
	end
	if rec.st == "active" and quantity and quantity < rec.q then
		-- Units of a commodity auction were bought: they are sold, awaiting mail.
		local part = Split(list, rec, rec.q - quantity)
		part.st, part.soldT, part.soldVia = "sold", now, "owned list (quantity dropped)"
	end
end

-- An entry with an ID no record has: a post whose ID the client didn't name yet, a sold part split
-- off before, or an auction listed before tracking.
local function ApplyNew(list, info, house, now)
	local itemID = info.itemKey and info.itemKey.itemID
	local sold = IsSold(info)
	local found = Candidates(list, function(r)
		return not r.id and r.i == itemID and r.q == info.quantity and r.h == house
			and ((not sold and r.st == "active") or (sold and r.st == "sold"))
	end)
	local rec = found[1]
	if not rec then
		local name, link = ns.ItemInfoNow(itemID)
		rec = { i = itemID, n = name, l = info.itemLink or link, q = info.quantity, h = house, st = sold and "sold" or "active",
			-- The list's prices are kept as the client gives them; per unit or per stack is unverified, so
			-- no expected payout is built from them.
			untracked = true, seen = now, ownedBuyout = info.buyoutAmount, ownedBid = info.bidAmount }
		if sold then
			rec.soldT, rec.soldVia = now, "owned list"
		end
		list[#list + 1] = rec
	end
	rec.id = info.auctionID
	if info.timeLeftSeconds then
		rec.exp = now + info.timeLeftSeconds
	end
	rec.l = rec.l or info.itemLink
end

-- Reads the owned list the client has. With a full list at a known house, an auction of that house
-- that is missing from it was sold or cancelled (uncertain), or expired when its time was up.
function A.ReadOwned()
	local AH = C_AuctionHouse
	local c = Char()
	if not (c and AH and AH.GetNumOwnedAuctions and AH.GetOwnedAuctionInfo) then
		return
	end
	local house = ns.Market and ns.Market.CurrentHouse() or nil
	local full = AH.HasFullOwnedAuctionResults and AH.HasFullOwnedAuctionResults()
	local now = time()
	local entries, seen = {}, {}
	for index = 1, AH.GetNumOwnedAuctions() or 0 do
		local info = AH.GetOwnedAuctionInfo(index)
		if info and info.auctionID then
			entries[#entries + 1] = info
			seen[info.auctionID] = true
		end
	end
	local unknown = {}
	for _, info in ipairs(entries) do -- known IDs first, so split parts exist before new IDs look for them
		local rec = ById(c.list, info.auctionID)
		if rec then
			ApplyKnown(c.list, rec, info, now)
		else
			unknown[#unknown + 1] = info
		end
	end
	for _, info in ipairs(unknown) do
		ApplyNew(c.list, info, house, now)
	end
	if full and house then
		for _, rec in ipairs(c.list) do
			local listedLongEnough = not rec.t or now - rec.t >= INFER_AFTER_SECONDS
			if rec.st == "active" and rec.h == house and listedLongEnough and not (rec.id and seen[rec.id]) then
				if rec.exp and now >= rec.exp then
					rec.st, rec.expT, rec.why = "expired", now, "missing from the owned list after its expiry, no message seen"
				else
					rec.st, rec.goneT, rec.why = "gone", now, "missing from the owned list before its expiry, no message seen"
				end
			end
		end
	end
	c.ownedAt, c.ownedHouse = now, house
	Changed()
end

----------------------------------------------------------------------------------------------------
-- Sold and expired messages
----------------------------------------------------------------------------------------------------

-- Lua pattern of a client format string: "%s" captures text, "%d" digits; the rest is literal.
function A.PatternFrom(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local p = fmt:gsub("%%%d*%$?s", "\001"):gsub("%%%d*%$?d", "\002")
	p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. p .. "$"
end

local function MessagePatterns()
	return { sold = A.PatternFrom(ERR_AUCTION_SOLD_S), expired = A.PatternFrom(ERR_AUCTION_EXPIRED_S) }
end

-- Marks an auction sold or expired from a message. By ID when the message has one, else the oldest
-- open auction with that item name, flagged uncertain when there were several.
function A.MarkByMessage(kind, name, auctionID)
	local c = Char()
	if not c then
		return nil
	end
	local rec = ById(c.list, auctionID)
	local n = rec and 1 or 0
	if rec and not (rec.st == "active" or rec.st == "gone" or (kind == "sold" and rec.st == "sold")) then
		return nil -- already past this point
	end
	if not rec and name then
		local found = Candidates(c.list, function(r)
			return (r.st == "active" or r.st == "gone") and NameOf(r) == name
		end)
		rec, n = found[1], #found
	end
	if not rec then
		return nil
	end
	local before = { st = rec.st, soldT = rec.soldT, soldVia = rec.soldVia, expT = rec.expT, why = rec.why,
		qtyUnknown = rec.qtyUnknown, uncertain = rec.uncertain, candidates = rec.candidates }
	local now = time()
	if kind == "sold" then
		if rec.st ~= "sold" then
			rec.soldT, rec.soldVia = now, "message"
		end
		rec.st, rec.why = "sold", nil
		if rec.kind == "commodity" and rec.q > 1 and not auctionID then
			rec.qtyUnknown = true
		end
	else
		rec.st, rec.expT, rec.why = "expired", now, nil
	end
	MarkMatch(rec, n)
	Changed(rec)
	return rec, before
end

-- Puts a record back as it was before a message matched it by name (a later source named another).
local function Undo(rec, before)
	for _, k in ipairs({ "st", "soldT", "soldVia", "expT", "why", "qtyUnknown", "uncertain", "candidates" }) do
		rec[k] = before[k]
	end
end

-- The same message can reach us from several sources (event, chat, the expired event); each source
-- counts once per message. notes: { kind, name, at, sources = { [source] = true } }
local notes = {}
local function Note(kind, name, auctionID, source)
	local now = GetTime()
	for i = #notes, 1, -1 do
		if now - notes[i].at > NOTE_SECONDS then
			table.remove(notes, i)
		end
	end
	for _, note in ipairs(notes) do
		if note.kind == kind and (note.name == name or (auctionID and note.id == auctionID)) and not note.sources[source] then
			note.sources[source] = true
			if auctionID and not note.id then
				-- A later source names the auction: if the name picked another one, put that one back.
				note.id = auctionID
				local c = Char()
				local named = c and ById(c.list, auctionID)
				if named and named ~= note.rec then
					if note.rec then
						Undo(note.rec, note.before)
					end
					note.rec, note.before = A.MarkByMessage(kind, nil, auctionID)
				end
			end
			return nil
		end
	end
	local note = { kind = kind, name = name, id = auctionID, at = now, sources = { [source] = true } }
	notes[#notes + 1] = note
	note.rec, note.before = A.MarkByMessage(kind, name, auctionID)
	return note.rec
end

function A.OnNotification(notification, text, auctionID)
	local N = Enum and Enum.AuctionHouseNotification
	if not N or type(text) ~= "string" then
		return
	end
	if notification == N.AuctionSold then
		Note("sold", text, auctionID, "event")
	elseif notification == N.AuctionExpired then
		Note("expired", text, auctionID, "event")
	end
end

function A.OnSystemMessage(message)
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
		return
	end
	local patterns = MessagePatterns()
	local name = patterns.sold and message:match(patterns.sold)
	if name then
		Note("sold", name, nil, "chat")
		return
	end
	name = patterns.expired and message:match(patterns.expired)
	if name then
		Note("expired", name, nil, "chat")
	end
end

function A.OnAuctionsExpired(auctionID)
	local c = Char()
	local rec = c and ById(c.list, auctionID)
	if rec then
		Note("expired", NameOf(rec), auctionID, "expired event")
	end
end

function A.OnAuctionCanceled(auctionID)
	local c = Char()
	local rec = c and ById(c.list, auctionID)
	if rec and (rec.st == "active" or rec.st == "gone" or rec.st == "expired") then
		rec.st, rec.cancelT, rec.why, rec.uncertain, rec.candidates = "cancelled", time(), nil, nil, nil
		Changed(rec)
	end
end

----------------------------------------------------------------------------------------------------
-- Mail: sale money and returned items
----------------------------------------------------------------------------------------------------

local moneyTakes, moneyBase = {}, nil -- { money, name, sale, deposit, cut, count, at }
local itemTakes = {} -- { itemID, count, kind, before, at }

local function DropOld()
	local now = GetTime()
	for _, queue in ipairs({ moneyTakes, itemTakes }) do
		for i = #queue, 1, -1 do
			if now - queue[i].at > PENDING_SECONDS then
				table.remove(queue, i)
			end
		end
	end
	if not moneyTakes[1] then
		moneyBase = nil
	end
end

local function ReturnKind(subject)
	if type(subject) ~= "string" then
		return nil
	end
	local expired = A.PatternFrom(AUCTION_EXPIRED_MAIL_SUBJECT)
	if expired and subject:match(expired) then
		return "expired"
	end
	local removed = A.PatternFrom(AUCTION_REMOVED_MAIL_SUBJECT)
	if removed and subject:match(removed) then
		return "cancelled"
	end
	return nil
end

local function BagCount(itemID)
	return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0
end

-- Reads what a take on mail `index` is about to collect. Never opens, reads the text of or deletes a
-- mail (GetInboxText would mark it read).
local function TakeFrom(index, takesMoney, takesItems, attachment)
	if not (store and GetInboxHeaderInfo) then
		return
	end
	DropOld()
	local ok, _, _, _, subject, money = pcall(GetInboxHeaderInfo, index)
	if not ok then
		return
	end
	if takesMoney and type(money) == "number" and money > 0 and GetInboxInvoiceInfo then
		local okInvoice, invoiceType, itemName, _, bid, _, deposit, consignment, _, _, _, count = pcall(GetInboxInvoiceInfo, index)
		if okInvoice and invoiceType == "seller" and itemName then
			if not moneyTakes[1] then
				moneyBase = GetMoney()
			end
			moneyTakes[#moneyTakes + 1] = { money = money, name = itemName, sale = bid, deposit = deposit, cut = consignment,
				count = count and count > 0 and count or 1, at = GetTime() }
		end
	end
	local kind = takesItems and ReturnKind(subject)
	if kind and GetInboxItem then
		local first, last = attachment or 1, attachment or MAIL_ATTACHMENTS
		for slot = first, last do
			local _, itemID, _, count = GetInboxItem(index, slot)
			if itemID then
				local before = BagCount(itemID)
				for _, t in ipairs(itemTakes) do -- takes of the same item still on their way
					if t.itemID == itemID then
						before = before + t.count
					end
				end
				itemTakes[#itemTakes + 1] = { itemID = itemID, count = count or 1, kind = kind, before = before, at = GetTime() }
			end
		end
	end
end

function A.OnTakeMoney(index)
	TakeFrom(index, true, false)
end

function A.OnAutoLoot(index)
	TakeFrom(index, true, true)
end

function A.OnTakeItem(index, attachment)
	TakeFrom(index, false, true, attachment)
end

local function AddCutSample(rec, t, count)
	local market = CraftWiseMarketDB
	if not (market and rec.h and t.sale and t.sale > 0) then
		return
	end
	market.cutSamples = market.cutSamples or {}
	local samples = market.cutSamples
	samples[#samples + 1] = { house = rec.h, listed = t.sale, received = t.money, cut = t.cut, deposit = t.deposit,
		t = time(), i = rec.i, q = count }
	while #samples > CUT_SAMPLES_KEPT do
		table.remove(samples, 1)
	end
end

-- One sale mail's money arrived: settle the auction it paid for.
function A.SettleSale(t)
	local c = Char()
	if not c then
		return nil
	end
	local count = t.count or 1
	local tests = {
		function(r) return r.st == "sold" and not r.qtyUnknown and r.q == count end,
		function(r) return r.st == "sold" and r.q > count end,
		function(r) return r.st == "gone" and r.q == count end,
		function(r) return r.st == "active" and r.q == count end,
		function(r) return (r.st == "gone" or r.st == "active") and r.q > count end,
	}
	local found = {}
	for _, test in ipairs(tests) do
		found = Candidates(c.list, function(r)
			return NameOf(r) == t.name and test(r)
		end)
		if found[1] then
			break
		end
	end
	local rec = found[1]
	-- The house only counts for a cut sample when every candidate was posted there.
	local oneHouse = rec ~= nil
	for _, r in ipairs(found) do
		oneHouse = oneHouse and r.h == rec.h
	end
	if rec and rec.q > count then
		rec = Split(c.list, rec, count)
	end
	if not rec then
		rec = { n = t.name, q = count, untracked = true }
		c.list[#c.list + 1] = rec
	end
	if rec.st ~= "sold" then
		rec.soldVia = "mail"
	end
	local now = time()
	rec.st, rec.settledT, rec.received, rec.sale, rec.cut, rec.saleDeposit = "settled", now, t.money, t.sale, t.cut, t.deposit
	rec.qtyUnknown, rec.why = nil, nil
	MarkMatch(rec, #found)
	if rec.i and ns.Ledger then
		ns.Ledger.Record("ahsell", rec.i, count, t.money, rec.h)
	end
	if oneHouse then
		AddCutSample(rec, t, count)
	end
	Changed(rec)
	return rec
end

-- A returned item arrived in the bags: settle the expired or cancelled auction it came from.
function A.SettleReturn(t)
	local c = Char()
	if not c then
		return nil
	end
	local tests = {
		function(r) return r.st == t.kind and r.q == t.count end,
		function(r) return (r.st == "expired" or r.st == "cancelled") and r.q == t.count end,
		function(r) return (r.st == "gone" or r.st == "active") and r.q == t.count end,
		function(r) return (r.st == "expired" or r.st == "cancelled" or r.st == "gone" or r.st == "active") and r.q > t.count end,
	}
	local found = {}
	for _, test in ipairs(tests) do
		found = Candidates(c.list, function(r)
			return r.i == t.itemID and test(r)
		end)
		if found[1] then
			break
		end
	end
	local rec = found[1]
	if not rec then
		return nil
	end
	if rec.q > t.count then
		rec = Split(c.list, rec, t.count)
	end
	rec.st, rec.returnedT, rec.returnKind, rec.why = "returned", time(), t.kind, nil
	MarkMatch(rec, #found)
	Changed(rec)
	return rec
end

function A.CheckMoney()
	DropOld()
	if not moneyBase then
		return
	end
	local gained = GetMoney() - moneyBase
	while moneyTakes[1] and gained >= moneyTakes[1].money do
		local t = table.remove(moneyTakes, 1)
		gained, moneyBase = gained - t.money, moneyBase + t.money
		A.SettleSale(t)
	end
	if not moneyTakes[1] then
		moneyBase = nil
	end
end

function A.CheckItems()
	DropOld()
	for i = 1, #itemTakes do
		local t = itemTakes[i]
		if t and BagCount(t.itemID) >= t.before + t.count then
			table.remove(itemTakes, i)
			A.SettleReturn(t)
			return A.CheckItems() -- the list changed; look again
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Pruning and summaries
----------------------------------------------------------------------------------------------------

local function LastTime(rec)
	return rec.settledT or rec.returnedT or rec.cancelT or rec.expT or rec.goneT or rec.soldT or rec.t or rec.seen or 0
end

-- Finished records and outcomes nobody collected go after 30 days; listed ones 30 days after expiry.
function A.Prune(now)
	if not store then
		return
	end
	now = now or time()
	local cutoff = now - KEEP_DAYS * DAY_SECONDS
	for _, c in pairs(store.chars) do
		local kept = {}
		for _, rec in ipairs(c.list or {}) do
			local old
			if rec.st == "active" then
				old = rec.exp and rec.exp < cutoff
			else
				old = LastTime(rec) < cutoff
			end
			if not old then
				kept[#kept + 1] = rec
			end
		end
		c.list = kept
	end
end

local function HouseLabel(house)
	return house and ns.Market and ns.Market.HouseLabel(house) or nil
end

-- One record for the snapshot and the chat list.
function A.Row(rec, now)
	now = now or time()
	local row = { id = rec.id, item = rec.i, name = NameOf(rec), q = rec.q, house = rec.h, houseLabel = HouseLabel(rec.h),
		status = rec.st, statusText = A.STATUS_TEXT[rec.st], posted = rec.t, expires = rec.exp, durText = rec.durText,
		unitBuyout = rec.unit, unitBid = rec.bid, deposit = rec.dep, untracked = rec.untracked, why = rec.why }
	if rec.uncertain then
		row.uncertain = ("matched by name among %d auctions of this item"):format(rec.candidates or 2)
	end
	if rec.st == "active" and rec.exp and now >= rec.exp then
		row.overdue = true -- time is up but no outcome seen yet
	end
	if rec.st == "sold" then
		row.soldAt, row.soldVia = rec.soldT, rec.soldVia
		if rec.qtyUnknown then
			row.unitsSold = "some or all"
		end
		row.expected, row.expectedNote, row.salePrice = A.Expected(rec)
		if not row.expected then
			row.expectedNote = row.expectedNote or "unknown"
		end
	end
	if rec.st == "expired" or rec.st == "cancelled" then
		row.at = rec.expT or rec.cancelT
	end
	if rec.st == "settled" then
		row.received, row.sale, row.cut, row.settledAt = rec.received, rec.sale, rec.cut, rec.settledT
	end
	return row
end

-- What is listed, sold awaiting mail (with expected gold), expired awaiting mail, and uncertain.
function A.Summary(charKey)
	local c = Char(charKey)
	if not c then
		return nil
	end
	local now = time()
	local s = { active = {}, sold = {}, returning = {}, uncertain = {}, expectedTotal = 0, expectedMissing = 0,
		listedTotal = 0, listedCounted = 0, listedNoBuyout = 0, listedUnknownCut = 0, listedUnpriced = 0,
		ownedListAt = c.ownedAt, ownedListHouse = c.ownedHouse }
	local notes = {}
	for _, rec in ipairs(c.list) do
		local row
		if rec.st == "active" then
			row = A.Row(rec, now)
			s.active[#s.active + 1] = row
			local payout, note = A.IfSold(rec)
			if payout then
				s.listedTotal, s.listedCounted = s.listedTotal + payout, s.listedCounted + 1
				notes[note] = true
			elseif note == "no buyout" then
				s.listedNoBuyout = s.listedNoBuyout + 1
			elseif note == "price not recorded" then
				s.listedUnpriced = s.listedUnpriced + 1
			else
				s.listedUnknownCut = s.listedUnknownCut + 1
			end
		elseif rec.st == "sold" then
			row = A.Row(rec, now)
			s.sold[#s.sold + 1] = row
			if row.expected then
				s.expectedTotal = s.expectedTotal + row.expected
			else
				s.expectedMissing = s.expectedMissing + 1
			end
		elseif rec.st == "expired" or rec.st == "cancelled" then
			s.returning[#s.returning + 1] = A.Row(rec, now)
		elseif rec.st == "gone" then
			s.uncertain[#s.uncertain + 1] = A.Row(rec, now)
		end
	end
	-- The cut the listed total is after: one text when every counted listing shares it.
	for note in pairs(notes) do
		s.listedNote = s.listedNote and "each house's cut" or note
	end
	return s
end

-- Snapshot section (#63); empty lists when nothing is recorded.
function A.SnapshotSummary()
	local s = A.Summary()
	if not s then
		return nil, "character not known yet"
	end
	return s
end

----------------------------------------------------------------------------------------------------
-- /craftwise auctions
----------------------------------------------------------------------------------------------------

local function Money(copper)
	return copper and ns.FormatMoney(copper) or "unknown"
end

local function Ago(t, now)
	if not t then
		return nil
	end
	local ok, text = pcall(ns.Market.FormatAge, now - t)
	return ok and text or nil
end

local function RowText(row, now)
	local item = ns.ItemChatText(row.item or 0, { name = row.name })
	if not row.item then
		item = row.name or "unknown item"
	end
	local parts = { ("%s x%d"):format(item, row.q or 0) }
	if row.houseLabel then
		parts[#parts + 1] = row.houseLabel
	end
	return parts
end

function A.Print()
	local s = A.Summary()
	if not s then
		ns.Print("auctions: nothing recorded for this character yet")
		return
	end
	local now = time()
	local ids = {}
	for _, list in ipairs({ s.active, s.sold, s.returning, s.uncertain }) do
		for _, row in ipairs(list) do
			if row.item then
				ids[#ids + 1] = row.item
			end
		end
	end
	ns.WithItemNames(ids, function()
		ns.Print(("Auctions: %d listed, %d sold awaiting mail, %d returning by mail, %d uncertain"):format(
			#s.active, #s.sold, #s.returning, #s.uncertain))
		if s.ownedListAt then
			ns.Print(("  owned list last read %s ago%s"):format(Ago(s.ownedListAt, now) or "?",
				s.ownedListHouse and (" at " .. (HouseLabel(s.ownedListHouse) or s.ownedListHouse)) or ""))
		end
		for _, row in ipairs(s.active) do
			local parts = RowText(row, now)
			if row.unitBuyout then
				parts[#parts + 1] = ("buyout %s each"):format(Money(row.unitBuyout))
			end
			if row.expires then
				parts[#parts + 1] = row.overdue and "time is up, outcome not seen yet" or ("ends in %s"):format(Ago(now, row.expires) or "?")
			end
			ns.Print("  listed: " .. table.concat(parts, ", "))
		end
		for _, row in ipairs(s.sold) do
			local parts = RowText(row, now)
			if row.unitsSold then
				parts[#parts + 1] = row.unitsSold .. " units sold"
			end
			if row.expected then
				parts[#parts + 1] = ("expected %s after %s"):format(Money(row.expected), row.expectedNote)
			else
				parts[#parts + 1] = "expected unknown: " .. tostring(row.expectedNote)
			end
			if row.uncertain then
				parts[#parts + 1] = row.uncertain
			end
			ns.Print("  sold, awaiting mail: " .. table.concat(parts, ", "))
		end
		for _, row in ipairs(s.returning) do
			ns.Print(("  %s: %s"):format(row.statusText, table.concat(RowText(row, now), ", ")))
		end
		for _, row in ipairs(s.uncertain) do
			ns.Print("  sold or cancelled (uncertain): " .. table.concat(RowText(row, now), ", "))
		end
		local total = ("  on its way: %s"):format(Money(s.expectedTotal))
		if s.expectedMissing > 0 then
			total = total .. (" plus %d sale%s with unknown payout"):format(s.expectedMissing, s.expectedMissing == 1 and "" or "s")
		end
		ns.Print(total)
		if #s.active > 0 then
			local listed = s.listedCounted > 0 and ("%s after %s"):format(Money(s.listedTotal), s.listedNote) or "unknown"
			local left = {}
			if s.listedNoBuyout > 0 then
				left[#left + 1] = ("%d without buyout"):format(s.listedNoBuyout)
			end
			if s.listedUnknownCut > 0 then
				left[#left + 1] = ("%d with cut unverified"):format(s.listedUnknownCut)
			end
			if s.listedUnpriced > 0 then
				left[#left + 1] = ("%d with price not recorded"):format(s.listedUnpriced)
			end
			if #left > 0 then
				listed = ("%s (not counted: %s)"):format(listed, table.concat(left, ", "))
			end
			ns.Print("  if all listed sell: " .. listed)
		end
	end)
end

function A.Slash()
	A.Print()
end

----------------------------------------------------------------------------------------------------
-- Events and hooks
----------------------------------------------------------------------------------------------------

ns.Listen("DB_READY", function()
	CraftWiseMarketDB = CraftWiseMarketDB or {}
	local db = CraftWiseMarketDB
	db.auctions = db.auctions or {}
	store = db.auctions
	store.v = store.v or 1
	store.chars = store.chars or {}
	db.cutSamples = db.cutSamples or {}
end)

ns.On("PLAYER_LOGIN", function()
	A.Prune()
end)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function(_, auctionID)
	A.OnAuctionCreated(auctionID)
end)
ns.On("AUCTION_HOUSE_POST_ERROR", A.ForgetPost)
ns.On("AUCTION_HOUSE_CLOSED", A.ForgetPost)
ns.On("OWNED_AUCTIONS_UPDATED", A.ReadOwned)
ns.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", function(_, notification, text, auctionID)
	A.OnNotification(notification, text, auctionID)
end)
ns.On("CHAT_MSG_SYSTEM", function(_, message)
	A.OnSystemMessage(message)
end)
ns.On("AUCTION_HOUSE_AUCTIONS_EXPIRED", function(_, auctionID)
	A.OnAuctionsExpired(auctionID)
end)
ns.On("AUCTION_CANCELED", function(_, auctionID)
	A.OnAuctionCanceled(auctionID)
end)
ns.On("PLAYER_MONEY", A.CheckMoney)
ns.On("BAG_UPDATE_DELAYED", A.CheckItems)

-- The calls the player starts (Blizzard's UI or another addon). Hooks only read the arguments.
if hooksecurefunc then
	local AH = C_AuctionHouse
	if AH then
		if AH.PostItem then
			hooksecurefunc(AH, "PostItem", function(...) A.OnPostItem(...) end)
		end
		if AH.ConfirmPostItem then
			hooksecurefunc(AH, "ConfirmPostItem", function(...) A.OnPostItem(...) end)
		end
		if AH.PostCommodity then
			hooksecurefunc(AH, "PostCommodity", function(...) A.OnPostCommodity(...) end)
		end
		if AH.ConfirmPostCommodity then
			hooksecurefunc(AH, "ConfirmPostCommodity", function(...) A.OnPostCommodity(...) end)
		end
	end
	if TakeInboxMoney then
		hooksecurefunc("TakeInboxMoney", function(...) A.OnTakeMoney(...) end)
	end
	if AutoLootMailItem then
		hooksecurefunc("AutoLootMailItem", function(...) A.OnAutoLoot(...) end)
	end
	if TakeInboxItem then
		hooksecurefunc("TakeInboxItem", function(...) A.OnTakeItem(...) end)
	end
end
