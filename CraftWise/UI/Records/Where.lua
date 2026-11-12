-- Records window, Where to buy tab (`/craftwise where <item>`, #66): every merchant you opened that sells an
-- item, cheapest first, with the price per character standing, stock and when it was seen; restocks in the
-- tooltip. Search by name, item ID or link; the item menu (bags or Bags view) opens it for one item.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local Muted = RW.Muted

local MERCHANT_ICON = "Interface\\Icons\\INV_Misc_Bag_10"

local tab = { key = "where", label = L["Where to buy"], search = L["Item name, ID or link"] }

tab.columns = {
	{ key = "name", label = L["MERCHANT"], width = 220 },
	{ key = "place", label = L["WHERE"], width = 190 },
	{ key = "price", label = L["PRICE"], width = 150 },
	{ key = "stock", label = L["STOCK"], width = 80, align = "RIGHT" },
	{ key = "seen", label = L["SEEN"], width = 90, align = "RIGHT" },
}

local function PlaceText(m)
	local place = m.zone or "?"
	if m.sub and m.sub ~= m.zone then
		place = place .. ", " .. m.sub
	end
	if m.x and m.y then
		place = place .. Muted((" (%.1f, %.1f)"):format(m.x, m.y))
	end
	return place
end

-- Item IDs the query means: an ID or link, else recorded items whose name contains it (at most
-- RW.WHERE_MAX), and how many more matched.
function tab.Items(query)
	query = (query or ""):match("^%s*(.-)%s*$")
	if query == "" then
		return {}, 0
	end
	local itemID = tonumber(query:match("item:(%d+)") or query:match("^(%d+)$"))
	if itemID then
		return { itemID }, 0
	end
	local found = ns.Merchant.FindItems(query)
	local more = math.max(0, #found - RW.WHERE_MAX)
	for i = #found, RW.WHERE_MAX + 1, -1 do
		found[i] = nil
	end
	return found, more
end

local function SellerRow(itemID, s, now)
	local Me = ns.Merchant
	local m, item = s.merchant, s.item
	local price = s.chars and s.chars[1] and Me.CharPricesText(s.chars, item, true, 2) or Me.PriceText(item)
	local tip = { { L["Item"], RW.ItemText(itemID, { name = item.name }) } }
	if s.chars and s.chars[1] then
		tip[#tip + 1] = { L["Prices"], Me.CharPricesText(s.chars, item) }
		tip[#tip + 1] = { L["Faction"], m.faction and (m.faction.name or "?") or Me.StandingText(m) }
	else
		tip[#tip + 1] = { L["Standing"], Me.StandingText(m) }
	end
	if item.known then
		tip[#tip + 1] = L["Already known."]
	elseif item.unusable then
		tip[#tip + 1] = L["Not usable by this character."]
	end
	for _, r in ipairs(Me.Restocks(item)) do
		tip[#tip + 1] = (L["Count rose %d -> %d between %s and %s (may be another layer)."]):format(r.from, r.to,
			date("%m-%d %H:%M", r.after), date("%m-%d %H:%M", r.before))
	end
	return { itemID = itemID, icon = MERCHANT_ICON, name = m.name or ("NPC " .. tostring(s.npcID)),
		sub = Muted(RW.ItemText(itemID, { name = item.name })),
		cells = { place = PlaceText(m), price = price, stock = Me.StockText(item) or Muted("-"),
			seen = Me.FormatAge(now - (item.t or m.t or now)) }, tip = tip }
end

function tab.Model()
	local Me = ns.Merchant
	local query = RW.Query("where")
	local items, more = tab.Items(query)
	local now = time()
	local rows, parts = {}, {}
	for _, itemID in ipairs(items) do
		for _, s in ipairs(Me.Sellers(itemID)) do
			rows[#rows + 1] = SellerRow(itemID, s, now)
		end
		local base, stack = Me.BasePrice(itemID)
		if base then
			parts[#parts + 1] = ("%s: %s %s%s"):format(RW.ItemText(itemID), L["base price at Neutral"], ns.FormatMoney(base),
				(stack or 1) > 1 and (" " .. L["for"] .. " " .. stack) or "")
		end
	end
	RW.LoadNames(items)
	local line1 = ("|cffffffff%s|r  ·  %d %s"):format(L["Where to buy"], Me.Count(), L["merchants recorded on this account"])
	if more > 0 then
		line1 = line1 .. "  ·  " .. (L["%d more items match, be more specific"]):format(more)
	end
	local line2 = #parts > 0 and table.concat(parts, "  ·  ")
		or Muted(L["Type an item name, or use the item menu on an item in your bags (Where to buy)."])
	local empty
	if query == "" then
		empty = L["Search for an item to see who sells it."]
	elseif #items == 0 then
		empty = (L["No merchant you opened sells an item named \"%s\"."]):format(query)
	else
		empty = L["No merchant you opened sells it."]
	end
	return { rows = rows, summary = line1 .. "\n" .. line2, empty = empty }
end

-- Opens the tab for one item (item menu).
function ns.ShowWhereToBuy(itemID)
	if ns.ShowRecords then
		ns.ShowRecords("where", tostring(itemID))
	end
end

RW.Register(tab)
RW.Where = tab
