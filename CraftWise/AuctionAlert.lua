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

-- Undercut (#427): somebody else lists at or below my unit price (Auctions.lua, A.Watch). One line, a sound of its own
-- (setting undercutSound, on the Master channel so it plays while the game runs in the background; the client's
-- "Sound in background" option has to be on), the taskbar icon blinking (FlashClientIcon) and a chat line.
-- Clicking the line opens Sell › Auctions. Nothing is bought, listed or cancelled.
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

-- Copper as plain text with at most two units ("12g 34s"), the page's rule; no colours, no icons.
function Alert.Plain(copper)
	copper = math.floor((copper or 0) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 and #parts < 2 then parts[#parts + 1] = s .. "s" end
	if c > 0 and #parts < 2 then parts[#parts + 1] = c .. "c" end
	return #parts > 0 and table.concat(parts, " ") or "0c"
end

-- info = { itemID, price, mine } (copper per unit). Returns the line.
function Alert.OnUndercut(info)
	if not (info and info.itemID and ns.db) then
		return nil
	end
	local L = ns.L
	local name = ns.Auctions.NameOf({ i = info.itemID }) or ("item " .. tostring(info.itemID))
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID) or nil
	local line
	if ns.LootToast and ns.LootToast.ShowCustom then
		line = ns.LootToast.ShowCustom({
			key = "undercut:" .. info.itemID, icon = icon, itemID = info.itemID,
			text = (L["Undercut: %s"]):format(name),
			-- No copper: the line's money figure reads as a profit ("+12g 30s"); both prices go in the detail.
			detail = (L["%s, yours %s"]):format(Alert.Plain(info.price), Alert.Plain(info.mine)),
			duration = Alert.DURATION,
			onClick = function()
				if ns.OpenAuctionsPage then
					ns.OpenAuctionsPage()
				end
			end,
		})
	end
	if ns.Auctions.Watch.SoundEnabled() then
		PlayUndercut()
	end
	if FlashClientIcon then
		FlashClientIcon()
	end
	ns.Print((L["Undercut: %s %s (yours %s)"]):format(name, Alert.Plain(info.price), Alert.Plain(info.mine)))
	return line
end

ns.Listen("AUCTION_SALE", Alert.OnSale)
