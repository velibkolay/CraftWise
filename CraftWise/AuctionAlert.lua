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
		PlaySound(SOUNDKIT[Alert.SOUND])
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

ns.Listen("AUCTION_SALE", Alert.OnSale)
