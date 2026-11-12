-- Main window, Sell › Auctions (#155; spec in #150 "Sell", board "Sell › Auctions"): three cards (On its
-- way, If all listed sell, Returning), then one list: Item, Qty, Status, When, Buyout, You get. Replaces
-- Records › Auctions. Sources: Auctions.lua (A.List, A.Expected, A.IfSold, A.DurationText, the owned
-- list's age) and ns.HeroCards.AuctionTotals; this file only draws them. Row data (P.Rows) is kept apart
-- from the drawing.
--
-- You get = buyout − the house's cut (A.Expected / A.IfSold: only where the cut is confirmed or measured)
-- + the deposit back (the sale mail returns it: Blizzard's invoice maths, docs/ingame-checks.md). A
-- deposit CraftWise didn't see is left out and the cell's tip says so.
--
-- When: "ends in 11 h" for a listing. For a sale or a return the spec's "mail in 41 min" needs the
-- mail delay of WoW: Forever, which is not verified (#155, open question); until it is (MAIL_DELAY), the
-- line says how long ago it sold or expired.
local _, ns = ...
local M = ns.Main
local S = M.Sell
local Style, L = ns.Style, ns.L
local C = Style.C

local P = {}

P.MAIL_DELAY = nil -- seconds from a sale or an expiry to its mail; nil = not verified for Forever

-- Status per record state; order of the list: sold, listed, uncertain, returning.
P.STATUS = {
	sold = { key = "sold", text = L["Sold"], color = "text", order = 1 },
	active = { key = "listed", text = L["Listed"], color = "live", order = 2, live = true },
	gone = { key = "uncertain", text = L["Uncertain"], color = "text3", order = 3 },
	expired = { key = "returning", text = L["Returning"], color = "text2", order = 4 },
	cancelled = { key = "returning", text = L["Returning"], color = "text2", order = 4 },
}

-- What a record pays into the mailbox: youGet, why (nil youGet), depositKnown.
function P.YouGet(rec)
	local A = ns.Auctions
	local payout, why
	if rec.st == "active" then
		payout, why = A.IfSold(rec)
	elseif rec.st == "sold" then
		payout, why = A.Expected(rec)
	else
		return nil, nil, false
	end
	if not payout then
		return nil, why, false
	end
	return payout + (rec.dep or 0), nil, rec.dep ~= nil
end

local function Ago(seconds)
	return (L["%s ago"]):format(M.AgeText(seconds))
end

-- "ends in 11 h", "time is up", "sold 19 min ago" (or "mail in 41 min"), "expired · 2 min ago".
function P.WhenText(rec, now)
	if rec.st == "active" then
		if rec.exp and now >= rec.exp then
			return L["time is up"]
		elseif rec.exp then
			return (L["ends in %s"]):format(M.AgeText(rec.exp - now))
		end
		local dur = rec.durText or ns.Auctions.DurationText(rec.dur)
		return dur and (L["listed for %s"]):format(dur:lower()) or M.DASH
	end
	local at, word
	if rec.st == "sold" then
		at, word = rec.soldT, L["sold"]
	elseif rec.st == "expired" then
		at, word = rec.expT, L["expired"]
	elseif rec.st == "cancelled" then
		at, word = rec.cancelT, L["cancelled"]
	else
		at, word = rec.goneT or rec.seen, L["sold or cancelled"]
	end
	if not at then
		return word
	end
	if P.MAIL_DELAY and rec.st ~= "gone" and now < at + P.MAIL_DELAY then
		local mail = (L["mail in %s"]):format(M.AgeText(at + P.MAIL_DELAY - now))
		return rec.st == "sold" and mail or (word .. " · " .. mail)
	end
	if rec.st == "sold" then
		return word .. " " .. Ago(now - at)
	end
	return word .. " · " .. Ago(now - at)
end

-- Rows from A.List(): { key, itemID, name, quality, qty, status, statusText, statusColor, live, when,
-- buyout, buyoutNote, youGet, youGetWhy, depositKnown, deposit, rec }.
function P.Rows(list, now)
	local rows, ids = {}, {}
	for index, rec in ipairs(list or {}) do
		local st = P.STATUS[rec.st]
		if st then
			local name, quality = S.ItemName(rec.i, { name = rec.n, link = rec.l })
			local youGet, why, depositKnown = P.YouGet(rec)
			local buyout, buyoutNote
			if rec.unit and rec.unit > 0 then
				buyout = rec.unit * rec.q
			elseif rec.untracked and rec.ownedBuyout and rec.ownedBuyout > 0 then
				buyoutNote = L["not recorded"]
			else
				buyoutNote = L["no buyout"]
			end
			rows[#rows + 1] = {
				key = rec.id and ("id" .. rec.id) or ("rec" .. index), itemID = rec.i, name = name, quality = quality,
				qty = rec.q, state = rec.st, status = st.key, statusText = st.text, statusColor = st.color, live = st.live, order = st.order,
				when = P.WhenText(rec, now), at = rec.exp or rec.soldT or rec.expT or rec.cancelT or rec.goneT or rec.t or 0,
				buyout = buyout, buyoutNote = buyoutNote, youGet = youGet, youGetWhy = why, depositKnown = depositKnown,
				deposit = rec.dep, uncertain = rec.uncertain and rec.candidates or nil, why = rec.why,
			}
			if rec.i and not rec.n and not rec.l then -- a name kept with the record needs no request
				ids[#ids + 1] = rec.i
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		if a.at ~= b.at then
			-- listings: ending soonest first; the rest: newest first
			if a.status == "listed" then
				return a.at < b.at
			end
			return a.at > b.at
		end
		return a.name < b.name
	end)
	return rows, ids
end

-- The three cards: ns.HeroCards.AuctionTotals plus the deposits back of the counted rows.
function P.Cards(totals, rows)
	local deposits = { sold = 0, listed = 0 }
	local lost, lostKnown = 0, true
	for _, r in ipairs(rows) do
		if r.youGet and r.depositKnown and deposits[r.status] then
			deposits[r.status] = deposits[r.status] + r.deposit
		end
		if r.status == "returning" then
			if r.deposit then
				lost = lost + r.deposit
			else
				lostKnown = false
			end
		end
	end
	local function plus(copper, extra)
		return copper and (copper + extra) or nil
	end
	local way, all, back = totals.onItsWay, totals.ifAllSell, totals.returning
	local wayCaption = (L["%d sold, after cut and deposit back"]):format(way.count)
	if way.notCounted > 0 then
		wayCaption = wayCaption .. " · " .. (L["%d not counted"]):format(way.notCounted)
	end
	local left = {}
	if all.noBuyout > 0 then
		left[#left + 1] = (L["%d without a buyout"]):format(all.noBuyout)
	end
	if all.notRecorded > 0 then
		left[#left + 1] = (L["%d with price not recorded"]):format(all.notRecorded)
	end
	if all.unknownCut > 0 then
		left[#left + 1] = (L["%d with cut unverified"]):format(all.unknownCut)
	end
	local allCaption = (L["%d listed"]):format(all.count)
	if #left > 0 then
		allCaption = allCaption .. " · " .. table.concat(left, ", ") .. " " .. L["not counted"]
	end
	local backCaption
	if back.count > 0 then
		local expired, cancelled = false, false
		for _, r in ipairs(rows) do
			if r.status == "returning" then
				if r.state == "cancelled" then
					cancelled = true
				else
					expired = true
				end
			end
		end
		backCaption = expired and cancelled and L["expired or cancelled"] or cancelled and L["cancelled"] or L["expired"]
		if lostKnown then
			backCaption = backCaption .. ", " .. (L["deposit lost %s"]):format(ns.FormatCoins(lost))
		end
	end
	return {
		{ key = "way", label = L["On its way · in the mail"], copper = plus(way.copper, deposits.sold), caption = wayCaption },
		{ key = "all", label = L["If all listed sell"], copper = plus(all.copper, deposits.listed), caption = allCaption },
		{ key = "back", label = L["Returning"], count = back.units, unit = back.units == 1 and L["item"] or L["items"],
			caption = backCaption },
	}
end

-- The sub bar's line: "<character> · owned list read 12 min ago".
function P.OwnedText(ownedAt, now)
	local who = ns.CharName and ns.CharName() or nil
	local read = ownedAt and (L["owned list read %s"]):format(Ago(now - ownedAt)) or L["owned list not read yet"]
	return who and (who .. " · " .. read) or read
end

-- Footer: You get with the house's cut when every counted listing shares one.
function P.FooterText(note)
	local cut = note and note ~= "each house's cut" and ("the " .. note) or L["the house's cut"]
	return (L["You get: buyout minus %s, plus the deposit back. Posting happens in Blizzard's auction house or another addon; CraftWise reads it."])
		:format(cut)
end

function P.Model(ctx)
	local A = ns.Auctions
	local now = time()
	local rows, ids = P.Rows(A and A.List() or {}, now)
	S.LoadNames(ids)
	local model = { rows = rows, empty = L["No auction listed, sold or returning. Post one and it shows here."] }
	local totals = ns.HeroCards.AuctionTotals()
	if totals then
		model.hero = { bare = true, height = 80, cards = P.Cards(totals, rows) }
		model.footer = P.FooterText(totals.ifAllSell.note)
	else
		model.footer = P.FooterText(nil)
	end
	return model
end

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

P.columns = {
	{ key = "icon", icon = true, width = 22 },
	{ key = "name", label = L["Item"], width = 200, color = function(r) return S.QualityColor(r.quality) end },
	{ key = "qty", label = L["Qty"], width = 40, align = "RIGHT", font = "Figure", color = function() return "text2" end },
	{ key = "statusText", label = L["Status"], width = 130, font = "Small", color = function(r) return r.statusColor end,
		tip = function(r)
			if r.uncertain then
				return { L["Uncertain"], (L["Matched by name among %d auctions of this item."]):format(r.uncertain) }
			elseif r.status == "uncertain" and r.why then
				return { L["Uncertain"], r.why }
			end
		end },
	{ key = "when", label = L["When"], font = "Caption", color = function() return "text2" end },
	{ key = "buyout", label = L["Buyout"], width = 90, align = "RIGHT", font = "Figure",
		color = function(r) return r.buyout and "text" or "text3" end,
		text = function(r) return r.buyout and ns.FormatCoins(r.buyout) or r.buyoutNote end },
	{ key = "youGet", label = L["You get"], width = 90, align = "RIGHT", font = "FigureBold",
		text = function(r) return r.youGet and ns.FormatCoins(r.youGet) or M.DASH end,
		tip = function(r)
			if r.status == "returning" then
				return { L["Nothing to get"], L["The item comes back by mail; the deposit is lost."] }
			elseif not r.youGet and r.youGetWhy then
				return { L["Not counted"], r.youGetWhy }
			elseif r.youGet and not r.depositKnown then
				return { L["Deposit back unknown"], L["CraftWise didn't see this auction's deposit; it is not included."] }
			end
		end },
}
local STATUS_COLUMN = 4

-- Listed: the orange diamond before the word (spec: it is running).
function P.InitRow(b, data)
	local cell = b.cells[STATUS_COLUMN]
	b.cwLive = b.cwLive or Style.Nokta(b, C.live)
	if data.live then
		b.cwLive:SetSize(8, 8)
		b.cwLive:ClearAllPoints()
		b.cwLive:SetPoint("CENTER", cell, "LEFT", 4, 0)
		b.cwLive:Show()
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", b.cwLive, "CENTER", 10, 0)
	else
		b.cwLive:Hide()
	end
end

-- Hero: three cards side by side (board), each a folded C.card with label, figure and caption.
function P.Hero(card, hero, ctx, slot)
	local inner = S.HeroInner(ctx) + 2 * ((ctx.metrics and ctx.metrics.heroPadX) or 16)
	local gap = 10
	local w = (inner - 2 * gap) / 3
	slot.cards = slot.cards or {}
	for i, def in ipairs(hero.cards) do
		local c = slot.cards[i]
		if not c then
			c = CreateFrame("Frame", nil, slot)
			c.sheet = Style.Sheet(c, C.card, C.cardFlap, 14, false)
			c.stat = S.Stat(c, true)
			c.stat:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -12)
			c.stat:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -14, 12)
			slot.cards[i] = c
		end
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", slot, "TOPLEFT", (i - 1) * (w + gap), 0)
		c:SetSize(w, hero.height or 80)
		c.key = def.key
		local figure = def.count and tostring(def.count) or S.Coins(def.copper)
		c.stat:Set(def.label, figure, def.caption, nil, def.count and def.unit or nil)
		c:Show()
	end
end

function P.Tools(slot)
	slot.owned = Style.Text(slot, "Caption", "text3")
	slot.owned:SetJustifyH("RIGHT")
	slot.owned:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
end

function P.UpdateTools(slot)
	local summary = ns.Auctions and ns.Auctions.Summary()
	slot.owned:SetText(P.OwnedText(summary and summary.ownedListAt, time()))
end

-- /craftwise auctions opens this page.
function P.OpenFromSlash()
	return ns.OpenMainWindow and ns.OpenMainWindow("auctions") or false
end
ns.OpenAuctionsPage = P.OpenFromSlash

M.RegisterPage({
	key = "auctions", section = "sell", label = L["Auctions"], order = 2, events = { "AUCTIONS_CHANGED" },
	columns = P.columns, Model = P.Model, InitRow = P.InitRow, Hero = P.Hero,
	Tools = P.Tools, UpdateTools = P.UpdateTools,
	P = P,
})
