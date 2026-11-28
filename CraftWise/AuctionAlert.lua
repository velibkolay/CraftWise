-- Sale alert (issue #235): when one of this character's auctions newly sells (or, if switched on, expires),
-- one line on screen in the loot toast's place and look, and an optional sound, so a sale isn't only
-- Blizzard's chat line. Auctions.lua announces each transition once per sale (AUCTION_SALE), however many
-- sources report it (event, chat, owned list), and never for a record that already was in that state.
--   * Sold: "Sold: <item>", "×5" or "some of 5" when a commodity sale doesn't say how many units, and
--     "You get" with the payout after the cut (A.Expected, the same maths as Sell › Auctions) when the
--     record knows it; no number otherwise.
--   * Expired: "Expired: <item>, ×5 returning by mail", off by default.
--   * Settings in db.settings: saleToast (default on), saleSound (default on), expiredToast (default off).
--   * Clicking the line opens Sell › Auctions. The page itself moves the row live (AUCTIONS_CHANGED).
local _, ns = ...

local Alert = {}
ns.AuctionAlert = Alert

Alert.DURATION = 8 -- seconds fully shown; several sales stack as lines
-- Blizzard's own AH buy dialog plays this when the gold changes hands (Blizzard_AuctionHouseBuyDialog.lua).
Alert.SOUND = "LOOT_WINDOW_COIN_SOUND"

local function Settings()
	return ns.db and ns.db.settings or {}
end

function Alert.SaleEnabled()
	return Settings().saleToast ~= false
end

function Alert.SoundEnabled()
	return Settings().saleSound ~= false
end

function Alert.ExpiredEnabled()
	return Settings().expiredToast == true
end

-- What a line says for a record: { text, detail, copper, source }.
function Alert.Parts(kind, rec)
	local L = ns.L
	local name = ns.Auctions.NameOf(rec) or ("item " .. tostring(rec.i))
	local q = rec.q or 1
	if kind == "expired" then
		return { text = (L["Expired: %s"]):format(name),
			detail = (q > 1 and ("×" .. q .. " · ") or "") .. L["returning by mail"] }
	end
	local parts = { text = (L["Sold: %s"]):format(name) }
	if rec.qtyUnknown then
		parts.detail = (L["some of %d"]):format(q)
	elseif q > 1 then
		parts.detail = "×" .. q
	end
	local payout = ns.Auctions.Expected(rec)
	if payout and payout > 0 then
		parts.copper, parts.source = payout, L["you get"]
	end
	return parts
end

local function PlayChime()
	if SOUNDKIT and SOUNDKIT[Alert.SOUND] and PlaySound then
		PlaySound(SOUNDKIT[Alert.SOUND], "Master")
	end
end

function Alert.OnSale(kind, rec)
	if not (rec and ns.db and ns.LootToast and ns.LootToast.ShowCustom) then
		return nil
	end
	if kind == "sold" then
		if not Alert.SaleEnabled() then
			return nil
		end
	elseif not Alert.ExpiredEnabled() then
		return nil
	end
	local parts = Alert.Parts(kind, rec)
	local icon = rec.i and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(rec.i) or nil
	Alert.count = (Alert.count or 0) + 1
	local line = ns.LootToast.ShowCustom({
		key = "auction:" .. Alert.count, icon = icon, itemID = rec.i,
		text = parts.text, detail = parts.detail, copper = parts.copper, sourceText = parts.source,
		duration = Alert.DURATION,
		onClick = function()
			if ns.OpenAuctionsPage then
				ns.OpenAuctionsPage()
			end
		end,
	})
	if kind == "sold" and Alert.SoundEnabled() then
		PlayChime()
	end
	return line
end

-- Undercut (#427): somebody else lists at or below my unit price (Auctions.lua, A.Watch). One card (#432, below), a sound of its own
-- (setting undercutSound, on the Master channel so it plays while the game runs in the background; the client's
-- "Sound in background" option has to be on), the taskbar icon blinking (FlashClientIcon) and a chat line.
-- Nothing is bought, listed or cancelled.
Alert.UNDERCUT_SOUNDS = { "ALARM_CLOCK_WARNING_3", "RAID_WARNING" } -- the first one the client has

local function PlayUndercut()
	if not (SOUNDKIT and PlaySound) then
		return
	end
	for _, name in ipairs(Alert.UNDERCUT_SOUNDS) do
		if SOUNDKIT[name] then
			PlaySound(SOUNDKIT[name], "Master")
			return
		end
	end
end

-- Copper as plain text with at most two units ("12g 34s"), the page's rule; no colours, no icons. A zero unit is skipped
-- and the next one taken ("12g 5c"): for an undercut the copper is worth keeping.
function Alert.Plain(copper)
	copper = math.floor((copper or 0) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 and #parts < 2 then parts[#parts + 1] = s .. "s" end
	if c > 0 and #parts < 2 then parts[#parts + 1] = c .. "c" end
	return #parts > 0 and table.concat(parts, " ") or "0c"
end

-- Two prices as text. When they differ but read the same in two units (a 1 copper undercut), both are written in full.
function Alert.PlainPair(a, b)
	local x, y = Alert.Plain(a), Alert.Plain(b)
	if x == y and a ~= b then
		x, y = ns.FormatMoney(a, true), ns.FormatMoney(b, true)
	end
	return x, y
end

----------------------------------------------------------------------------------------------------
-- Undercut cards (#432): one small card per undercut item that stays on screen until it is closed (the X or a
-- right-click) or the watch no longer sees the undercut (Auctions.lua drops it: re-posted, competitor gone, item
-- no longer listed). The same item updates its card in place. A stack of at most CARDS_MAX at an anchor of its own
-- (movable, unlock/lock in Settings), the rest as a "+N more" line. Left-click opens Sell › Auctions, hover says more.
-- The card state is plain data (Alert.cards); the frames below only draw it.
----------------------------------------------------------------------------------------------------

Alert.CARDS_MAX = 5
Alert.CARD_W, Alert.CARD_H, Alert.CARD_GAP = 240, 44, 4
Alert.DEFAULT_POS = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -250, y = -30 } -- left of the minimap, clear of the AH window

Alert.cards = {} -- newest first: { itemID, name, icon, price, mine, theirs, yours }

local function CardOf(itemID)
	for i, c in ipairs(Alert.cards) do
		if c.itemID == itemID then
			return c, i
		end
	end
end

-- Adds the card of an item, or updates it where it is. info = { itemID, price, mine, name, icon }.
function Alert.CardPut(info)
	local c = CardOf(info.itemID)
	if not c then
		c = { itemID = info.itemID }
		table.insert(Alert.cards, 1, c)
	end
	c.name, c.icon, c.price, c.mine, c.quality = info.name, info.icon, info.price, info.mine, info.quality
	c.theirs, c.yours = Alert.PlainPair(info.price, info.mine)
	Alert.CardsDraw()
	return c
end

-- The competitor's price moved but the undercut stands: the card says so, with no new alert. False when there is no card.
function Alert.CardUpdate(itemID, price)
	local c = CardOf(itemID)
	if not c then
		return false
	end
	c.price = price
	c.theirs, c.yours = Alert.PlainPair(price, c.mine)
	Alert.CardsDraw()
	return true
end

function Alert.CardDrop(itemID)
	local c, i = CardOf(itemID)
	if c then
		table.remove(Alert.cards, i)
		Alert.CardsDraw()
		return true
	end
	return false
end

function Alert.CardsClear()
	if #Alert.cards > 0 then
		Alert.cards = {}
		Alert.CardsDraw()
	end
end

-- Position and lock (db.settings.undercutPos / undercutLocked; locked unless the player unlocked it).
local anchor, frames, more

local function Settings2()
	return ns.db and ns.db.settings
end

function Alert.CardsLocked()
	local s = Settings2()
	return not s or s.undercutLocked ~= false
end

local function PlaceAnchor()
	local s = Settings2()
	local pos = s and s.undercutPos or Alert.DEFAULT_POS
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

local function ApplyLock()
	local locked = Alert.CardsLocked()
	anchor:EnableMouse(not locked)
	anchor.handle:SetShown(not locked)
	anchor.label:SetShown(not locked)
	anchor.outline:SetShown(not locked)
end

local function BuildAnchor()
	if anchor then
		return anchor
	end
	local Style = ns.Style
	local C = Style.C
	anchor = CreateFrame("Frame", "CraftWiseUndercutAnchor", UIParent)
	anchor:SetSize(Alert.CARD_W, Alert.CARDS_MAX * (Alert.CARD_H + Alert.CARD_GAP) + 16)
	anchor:SetFrameStrata("HIGH")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		local s = Settings2()
		if s and point then
			s.undercutPos = { point = point, relPoint = relPoint, x = x, y = y }
		end
	end)
	anchor.handle = anchor:CreateTexture(nil, "BACKGROUND")
	anchor.handle:SetAllPoints(anchor)
	Style.Fill(anchor.handle, C.sheet, 0.6)
	anchor.label = Style.Text(anchor, "Label", "text")
	anchor.label:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	anchor.label:SetText(ns.L["Undercut alerts · drag to move"])
	anchor.outline = CreateFrame("Frame", nil, anchor)
	anchor.outline:SetAllPoints(anchor)
	anchor.outline.border = Style.Border(anchor.outline, C.text)
	frames = {}
	PlaceAnchor()
	ApplyLock()
	return anchor
end

local function OpenPage()
	if ns.OpenAuctionsPage then
		ns.OpenAuctionsPage()
	end
end

local function BuildCard(i)
	local Style = ns.Style
	local C = Style.C
	local card = CreateFrame("Button", nil, anchor)
	card:SetSize(Alert.CARD_W, Alert.CARD_H)
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card.cwWindow = "alerts" -- the sheet follows db.settings.alpha.alerts (Settings › Undercut watch › Background)
	card.sheet = Style.Sheet(card, C.sheet, C.danger, 8, true) -- the fold in the danger colour: it reads as an undercut
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(28, 28)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	card.icon:SetPoint("LEFT", card, "LEFT", 8, 0)
	card.name = Style.Text(card, "Body", "text")
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 44, -7)
	card.name:SetPoint("RIGHT", card, "RIGHT", -24, 0)
	card.detail = Style.Text(card, "Caption", "text2")
	card.detail:SetJustifyH("LEFT")
	card.detail:SetWordWrap(false)
	card.detail:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 44, 7)
	card.detail:SetPoint("RIGHT", card, "RIGHT", -8, 0)
	card.close = CreateFrame("Button", nil, card)
	card.close:SetSize(24, 24) -- a hit box bigger than the glyph
	card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
	card.close.x = Style.Text(card.close, "Body", "text3")
	card.close.x:SetPoint("CENTER", card.close, "CENTER", 0, 0)
	card.close.x:SetText("×")
	card.close:SetScript("OnClick", function()
		Alert.CardDrop(card.itemID)
	end)
	card.close:SetScript("OnEnter", function(self)
		self.x:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
		Style.ShowTip(self, ns.L["Close"], ns.L["Closes this card. It comes back if somebody undercuts you again."])
	end)
	card.close:SetScript("OnLeave", function(self)
		self.x:SetTextColor(C.text3[1], C.text3[2], C.text3[3], 1)
		Style.HideTip(self)
	end)
	card:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			Alert.CardDrop(card.itemID)
		else
			OpenPage()
		end
	end)
	card:SetScript("OnEnter", function(self)
		Style.ShowTip(self, (ns.L["Undercut: %s"]):format(self.itemName or "?"),
			(ns.L["Somebody lists at %s; yours is %s."]):format(self.theirs or "?", self.yours or "?"),
			ns.L["Left-click opens Sell › Auctions. Right-click or × closes."])
	end)
	card:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	frames[i] = card
	return card
end

-- Draws the cards: newest at the top, at most CARDS_MAX, then "+N more".
function Alert.CardsDraw()
	if not (CreateFrame and UIParent and ns.Style) then
		return
	end
	BuildAnchor()
	local L = ns.L
	local n = math.min(#Alert.cards, Alert.CARDS_MAX)
	for i = 1, n do
		local c = Alert.cards[i]
		local f = frames[i] or BuildCard(i)
		f.itemID, f.itemName, f.theirs, f.yours = c.itemID, c.name, c.theirs, c.yours
		-- The name alone, in its quality colour ("Undercut:" is in the tooltip and the chat line); the competitor's price in danger red.
		f.name:SetText(c.name or "?")
		local q = c.quality and ns.Style.QualityColor and ns.Style.QualityColor(c.quality) or ns.Style.C.text
		f.name:SetTextColor(q[1], q[2], q[3], 1)
		f.detail:SetText(ns.Style.Hex("danger") .. c.theirs .. "|r" .. (L[", yours %s"]):format(c.yours))
		if c.icon then
			f.icon:SetTexture(c.icon)
		end
		f.icon:SetShown(c.icon ~= nil)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (Alert.CARD_H + Alert.CARD_GAP))
		f:Show()
	end
	for i = n + 1, #frames do
		frames[i].itemID = nil
		frames[i]:Hide()
	end
	if not more then
		more = CreateFrame("Button", nil, anchor)
		more:SetSize(Alert.CARD_W, 18)
		more.cwWindow = "alerts"
		more.sheet = ns.Style.Sheet(more, ns.Style.C.sheet, ns.Style.C.flap, 6, false)
		more.text = ns.Style.Text(more, "Caption", "text2")
		more.text:SetPoint("CENTER", more, "CENTER", 0, 0)
		more:SetScript("OnClick", OpenPage)
	end
	local extra = #Alert.cards - n
	more:SetShown(extra > 0)
	if extra > 0 then
		more.text:SetText((L["+%d more"]):format(extra))
		more:ClearAllPoints()
		more:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -n * (Alert.CARD_H + Alert.CARD_GAP))
	end
	anchor:SetShown(#Alert.cards > 0 or not Alert.CardsLocked())
end

-- The i-th card frame (specs).
function Alert.CardFrame(i)
	return frames and frames[i]
end

function Alert.SetCardsLocked(locked)
	local s = Settings2()
	if not s then
		return
	end
	s.undercutLocked = locked and true or false
	Alert.CardsDraw()
	ApplyLock()
end

function Alert.ResetPosition()
	local s = Settings2()
	if not s then
		return
	end
	s.undercutPos = nil
	if anchor then
		PlaceAnchor()
	end
end

-- A sample card, so the place can be seen (Settings › Undercut watch › Test); close it like any other.
function Alert.TestCard()
	return Alert.CardPut({ itemID = -1, name = ns.L["Sample item"], price = 123000, mine = 123400,
		icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(6948) or nil })
end

-- info = { itemID, price, mine } (copper per unit). Puts or updates the item's card (it stays until closed or the
-- watch drops it), plays the sound, flashes the taskbar icon and prints the chat line. Returns the card.
function Alert.OnUndercut(info)
	if not (info and info.itemID and ns.db) then
		return nil
	end
	local L = ns.L
	local theirs, mine = Alert.PlainPair(info.price, info.mine)
	local name = ns.Auctions.NameOf({ i = info.itemID }) or ("item " .. tostring(info.itemID))
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID) or nil
	local quality = ns.LootToast and ns.LootToast.Quality and ns.LootToast.Quality(info.itemID) or nil
	local card = Alert.CardPut({ itemID = info.itemID, name = name, icon = icon, quality = quality, price = info.price, mine = info.mine })
	if ns.Auctions.Watch.SoundEnabled() then
		PlayUndercut()
	end
	if FlashClientIcon then
		FlashClientIcon()
	end
	ns.Print((L["Undercut: %s %s (yours %s)"]):format(name, theirs, mine))
	return card
end

ns.Listen("AUCTION_SALE", Alert.OnSale)
