-- Issue #92: item info (quality, icon, class, subclass, time) for every item with a price, next to
-- the names map of #90 in CraftWiseMarketDB.
local NOW = 1794000000
local DAY = 86400
local HORDE = "PvP|H"

local function B36(n)
	local out, d = "", "0123456789abcdefghijklmnopqrstuvwxyz"
	while n > 0 do local r = n % 36; out = d:sub(r + 1, r + 1) .. out; n = (n - r) / 36 end
	return out
end

local function Market(opts)
	local ns, stub = LoadAddon(opts)
	time = function() return stub.clock end
	stub.clock = NOW
	return ns.Market, stub, ns
end

local function OpenAH(stub, zone)
	stub.zone, stub.subzone = zone or "Orgrimmar", ""
	stub.Fire("AUCTION_HOUSE_SHOW")
end

-- rows: { itemID, count, buyout, name, quality, texture, hasAllInfo }
local function Scan(stub, list)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = { itemID = r[1], count = r[2], buyout = r[3], name = r[4], quality = r[5], texture = r[6],
			hasAllInfo = r[7], link = "item:" .. r[1], owner = "Seller" }
	end
	stub.replicate = out
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
end

-- An item the client has cached: name, quality, icon (GetItemInfoInstant), class, subclass, sell price
-- (default 5 copper).
local function Cached(stub, itemID, name, quality, icon, classID, subclassID, sellPrice)
	stub.items[itemID] = { name = name, quality = quality, icon = icon, classID = classID, sellPrice = sellPrice or 5 }
	stub.itemClass[itemID], stub.itemSubclass[itemID] = classID, subclassID
end

local function Requests(stub)
	local asked = {}
	C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
	return asked
end

it("#92: a full scan stores quality, icon, class, subclass and time for every item; the name stays in names", function()
	local M, stub = Market()
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500, "Silverleaf" } })
	eq(CraftWiseMarketDB.itemInfo[765], "1," .. B36(134190) .. ",7,9," .. B36(NOW) .. ",5", "q,i,c,s,t,p in base 36")
	local info = M.ItemInfo(765)
	eq(info.n, "Silverleaf"); eq(info.q, 1); eq(info.i, 134190); eq(info.c, 7); eq(info.s, 9); eq(info.t, NOW); eq(info.p, 5)
	eq(CraftWiseMarketDB.names[765], "Silverleaf", "names stays a plain name string")
end)

it("#92: an item the cache doesn't hold yet takes quality and icon from its complete full-scan row", function()
	local M, stub = Market()
	stub.itemClass[13926], stub.itemSubclass[13926] = 7, 7
	local asked = Requests(stub)
	OpenAH(stub)
	Scan(stub, { { 13926, 1, 90000, "Golden Pearl", 2, 134122 } })
	local info = M.ItemInfo(13926)
	eq(info.q, 2); eq(info.i, 134122); eq(info.c, 7); eq(info.s, 7); eq(info.n, "Golden Pearl")
	eq(info.p, nil, "no sell price without the loaded item")
	eq(#asked, 1, "loaded for the sell price (#120)"); eq(asked[1], 13926)
	Cached(stub, 13926, "Golden Pearl", 2, 134122, 7, 7, 2500)
	stub.Fire("GET_ITEM_INFO_RECEIVED", 13926, true)
	eq(M.ItemInfo(13926).p, 2500)
end)

it("#92: a row the client says is incomplete gives no quality; the item is requested and stored when it loads", function()
	local M, stub = Market()
	local asked = Requests(stub)
	OpenAH(stub)
	Scan(stub, { { 4500, 1, 900, nil, 1, nil, false } })
	eq(CraftWiseMarketDB.itemInfo[4500], nil, "no quality known: nothing stored")
	eq(M.ItemInfo(4500), nil)
	eq(#asked, 1); eq(asked[1], 4500)
	Cached(stub, 4500, "Traveler's Backpack", 3, 133633, 1, 0)
	stub.Fire("GET_ITEM_INFO_RECEIVED", 4500, true)
	local info = M.ItemInfo(4500)
	eq(info.q, 3); eq(info.i, 133633); eq(info.c, 1); eq(info.s, 0); eq(info.n, "Traveler's Backpack")
end)

it("#92: a failed load stores nothing; loads for other addons' items are ignored", function()
	local M, stub = Market()
	Requests(stub)
	OpenAH(stub)
	Scan(stub, { { 4500, 1, 900, nil, 1, nil, false } })
	stub.Fire("GET_ITEM_INFO_RECEIVED", 4500, false)
	eq(CraftWiseMarketDB.itemInfo[4500], nil)
	Cached(stub, 999, "Not Priced", 1, 1, 0, 0)
	stub.Fire("GET_ITEM_INFO_RECEIVED", 999, true)
	eq(CraftWiseMarketDB.itemInfo[999], nil, "only items with a price")
	eq(M.ItemInfo(999), nil)
end)

it("#92: missing items are requested in batches of 100, one batch per step", function()
	local M, stub = Market()
	local asked = Requests(stub)
	OpenAH(stub)
	local rows = {}
	for i = 1, 250 do rows[i] = { 30000 + i, 1, 100, nil, 1, nil, false } end
	local batches, pending = {}, {}
	local after = C_Timer.After
	C_Timer.After = function(seconds, fn)
		if seconds == 0.2 then pending[#pending + 1] = fn else fn() end
	end
	Scan(stub, rows)
	batches[1] = #asked
	while pending[1] do
		local fn = table.remove(pending, 1)
		fn()
		batches[#batches + 1] = #asked
	end
	C_Timer.After = after
	eq(batches[1], 100); eq(batches[2], 200); eq(batches[3], 250); eq(#batches, 3)
	eq(M.ItemInfo(30001), nil)
end)

it("#92: stored info isn't read again for 30 days; then the client's current values replace it", function()
	local M, stub = Market()
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500 } })
	stub.items[765].quality = 2
	stub.clock = NOW + 29 * DAY
	Scan(stub, { { 765, 4, 400 } })
	eq(M.ItemInfo(765).q, 1); eq(M.ItemInfo(765).t, NOW)
	stub.clock = NOW + 30 * DAY
	Scan(stub, { { 765, 3, 300 } })
	eq(M.ItemInfo(765).q, 2); eq(M.ItemInfo(765).t, NOW + 30 * DAY)
end)

it("#92: items from a browse list get their info when the AH closes", function()
	local M, stub = Market()
	Cached(stub, 2589, "Linen Cloth", 1, 132889, 7, 5)
	OpenAH(stub)
	stub.Fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", { { itemKey = { itemID = 2589 }, totalQuantity = 40, minPrice = 12 } })
	eq(M.ItemInfo(2589), nil)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	eq(M.ItemInfo(2589).i, 132889)
end)

it("#92: random-suffix records and Auctionator exports are keyed by item ID like names", function()
	local M, stub = Market({ auctionator = true })
	Cached(stub, 15211, "Militant Shortsword", 2, 135321, 2, 7)
	Cached(stub, 5, "Exported Item", 1, 134400, 7, 11)
	stub.itemClass[15211] = 2
	OpenAH(stub)
	stub.replicate = { { itemID = 15211, count = 1, buyout = 5000, link = "item:15211::::::1017", owner = "Seller" } }
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	assert(CraftWiseMarketDB.items["15211:1017"], "suffix record")
	eq(M.ItemInfo(15211).c, 2)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	M.ExportAuctionator(5, 999, 0)
	M.FillItemInfo()
	eq(M.ItemInfo(5).s, 11)
end)

it("#92: an unknown field stays empty and reads as missing", function()
	local M, stub = Market()
	stub.items[77] = { name = "No Icon", quality = 0 }
	OpenAH(stub)
	Scan(stub, { { 77, 1, 10 } })
	local packed = CraftWiseMarketDB.itemInfo[77]
	assert(packed:match("^0,,,,%w+,$"), packed)
	local info = M.ItemInfo(77)
	eq(info.q, 0, "poor quality is 0, not missing"); eq(info.i, nil); eq(info.c, nil); eq(info.s, nil); eq(info.p, nil)
end)

------------------------------------------------------------------------------------ #120

it("#120: the vendor sell price is stored with the info; 0 means vendors don't buy it", function()
	local M, stub = Market()
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9, 0)
	Cached(stub, 2589, "Linen Cloth", 1, 132889, 7, 5, 13)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500 }, { 2589, 20, 200 } })
	eq(M.ItemInfo(765).p, 0, "0 is a value, not missing")
	eq(M.ItemInfo(2589).p, 13)
	eq(CraftWiseMarketDB.itemInfoV, 2, "the format is marked")
end)

it("#120: without the loaded item, the sell price the client returned earlier is used, never the bundled table", function()
	local M, stub, ns = Market()
	stub.itemClass[3000], stub.itemSubclass[3000] = 7, 5
	stub.itemClass[3001], stub.itemSubclass[3001] = 7, 5
	ns.db.sellPrices[3000] = 40
	ns.ItemSellPrices = ns.ItemSellPrices or {}
	ns.ItemSellPrices[3001] = 77
	Requests(stub)
	OpenAH(stub)
	Scan(stub, { { 3000, 1, 900, "Seen Before", 1, 1 }, { 3001, 1, 900, "Bundled Only", 1, 1 } })
	eq(M.ItemInfo(3000).p, 40)
	eq(M.ItemInfo(3001).p, nil)
end)

it("#120: a format 1 string (no sell price) is read again at the next pass, though younger than 30 days", function()
	local saved = {
		v = 1, houses = {}, scans = {}, cutSamples = {}, scope = { items = {}, skillLines = {} },
		items = { [765] = { [HORDE] = "tmz8w0,2s,5,1||" } },
		names = { [765] = "Silverleaf" },
		itemInfo = { [765] = "1," .. B36(134190) .. ",7,9," .. B36(NOW - DAY) },
		auctionator = { items = {} },
	}
	local M, stub = Market({ savedMarket = saved })
	eq(M.ItemInfo(765).p, nil, "an old string reads without a sell price")
	eq(M.ItemInfo(765).t, NOW - DAY)
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9, 3)
	stub.Fire("PLAYER_LOGIN")
	stub.RunTimers()
	eq(M.ItemInfo(765).p, 3); eq(M.ItemInfo(765).t, NOW)
	stub.items[765].sellPrice = 4
	stub.clock = NOW + DAY
	M.FillItemInfo()
	eq(M.ItemInfo(765).p, 3, "complete info waits for the 30 days again")
end)

it("#120: the client's class and subclass names are recorded for every class and subclass seen", function()
	local M, stub = Market()
	stub.classNames[7], stub.classNames[2] = "Trade Goods", "Weapon"
	stub.subclassNames[7] = { [9] = "Herb", [5] = "Cloth" }
	stub.subclassNames[2] = { [7] = "One-Handed Swords" }
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9)
	Cached(stub, 2589, "Linen Cloth", 1, 132889, 7, 5)
	Cached(stub, 15211, "Militant Shortsword", 2, 135321, 2, 7)
	Cached(stub, 4500, "Unnamed Class", 1, 1, 15, 0)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500 }, { 2589, 20, 200 }, { 15211, 1, 5000 }, { 4500, 1, 10 } })
	local db = CraftWiseMarketDB
	eq(db.classNames[7], "Trade Goods"); eq(db.classNames[2], "Weapon")
	eq(db.subclassNames[7][9], "Herb"); eq(db.subclassNames[7][5], "Cloth"); eq(db.subclassNames[2][7], "One-Handed Swords")
	eq(db.classNames[15], nil, "no name from the client: nothing stored")
	eq(db.subclassNames[15], nil)
	eq(M.ItemInfo(765).c, 7)
end)

it("#120: class names are read once a session; a renamed class (other client language) replaces the old name", function()
	local _, stub = Market()
	local calls = 0
	stub.classNames[7] = "Handwerkswaren"
	stub.subclassNames[7] = { [9] = "Kräuter" }
	local orig = C_Item.GetItemClassInfo
	C_Item.GetItemClassInfo = function(c) calls = calls + 1; return orig(c) end
	CraftWiseMarketDB.classNames[7] = "Trade Goods"
	Cached(stub, 765, "Silberblatt", 1, 134190, 7, 9)
	Cached(stub, 785, "Maguskönigskraut", 1, 134190, 7, 9)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500 }, { 785, 2, 900 } })
	eq(CraftWiseMarketDB.classNames[7], "Handwerkswaren")
	eq(CraftWiseMarketDB.subclassNames[7][9], "Kräuter")
	eq(calls, 1, "one read per class and session")
end)

it("#92: an old saved file without itemInfo loads; login fills it from the cache, names untouched", function()
	local saved = {
		v = 1, houses = {}, scans = {}, cutSamples = {}, scope = { items = {}, skillLines = {} },
		items = { [765] = { [HORDE] = "tmz8w0,2s,5,1||" } },
		names = { [765] = "Silverleaf" },
		auctionator = { items = {} },
	}
	local M, stub = Market({ savedMarket = saved })
	Cached(stub, 765, "Silverleaf (renamed)", 1, 134190, 7, 9)
	eq(type(CraftWiseMarketDB.itemInfo), "table")
	stub.Fire("PLAYER_LOGIN")
	stub.RunTimers()
	eq(M.ItemInfo(765).i, 134190)
	eq(CraftWiseMarketDB.names[765], "Silverleaf", "an existing name isn't replaced")
end)

it("#92: logout fills info from the cache without requesting anything", function()
	local M, stub = Market()
	local asked = Requests(stub)
	OpenAH(stub)
	Scan(stub, { { 4500, 1, 900, nil, 1, nil, false } })
	local before = #asked
	Cached(stub, 4500, "Traveler's Backpack", 3, 133633, 1, 0)
	CraftWiseMarketDB.items[4501] = { [HORDE] = "tmz8w0,2s,5,1||" }
	stub.Fire("PLAYER_LOGOUT")
	eq(M.ItemInfo(4500).q, 3)
	eq(M.ItemInfo(4501), nil)
	eq(#asked, before)
end)

it("#92: info is dropped with the item's records, and the snapshot counts it", function()
	local M, stub = Market()
	Cached(stub, 765, "Silverleaf", 1, 134190, 7, 9)
	OpenAH(stub)
	Scan(stub, { { 765, 5, 500 } })
	eq(M.SnapshotSummary().itemInfo, 1)
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.clock = NOW + 31 * DAY
	CraftWiseMarketDB.prunedAt = nil
	M.Prune()
	eq(CraftWiseMarketDB.itemInfo[765], nil)
	eq(M.SnapshotSummary().itemInfo, 0)
end)

----------------------------------------------------------------------------------------- size

-- WoW's SavedVariables writer: tabs per depth, ["key"] = value, array items with -- [n].
local function SerializedSize(value)
	local size = 0
	local function write(v, depth)
		local kind = type(v)
		if kind == "string" then
			size = size + #v + 2
		elseif kind ~= "table" then
			size = size + #tostring(v)
		else
			size = size + 2
			local n = #v
			for i = 1, n do
				size = size + depth + 1
				write(v[i], depth + 1)
				size = size + #(", -- [" .. i .. "]\n")
			end
			for k, x in pairs(v) do
				if not (type(k) == "number" and k >= 1 and k <= n) then
					size = size + depth + 1 + #tostring(k) + (type(k) == "string" and 8 or 6)
					write(x, depth + 1)
					size = size + 2
				end
			end
			size = size + depth + 1
		end
	end
	write(value, 0)
	return size
end

local MB = 1000 * 1000

-- The #90 scan (10,000 items, about 30,000 rows, 1,100 in scope, one house) with item info: icon file
-- IDs in the range the client uses for item icons (132,000 to 7,000,000), classes and subclasses as
-- small numbers, quality 0 to 5.
it("#92 size: item info for 10,000 items", function()
	local M, stub = Market()
	for i = 1, 1100 do CraftWiseMarketDB.scope.items[20000 + i * 3] = true end
	local rows = {}
	for i = 1, 10000 do
		local itemID = 20000 + i * 3
		stub.itemClass[itemID], stub.itemSubclass[itemID] = i % 20, i % 13
		local icon = 132000 + (i * 6967) % 6868000
		local base = 50 + (i * 7919) % 300000
		for k = 1, 1 + i % 5 do
			local count = 1 + (i * k) % 20
			rows[#rows + 1] = { itemID = itemID, count = count, buyout = (base + k * 13) * count, link = "item:" .. itemID,
				name = ("Item Name Number %d"):format(i), quality = i % 6, texture = icon, owner = "Seller" }
		end
	end
	OpenAH(stub)
	stub.replicate = rows
	stub.Fire("REPLICATE_ITEM_LIST_UPDATE")
	stub.Fire("AUCTION_HOUSE_CLOSED")
	stub.Fire("PLAYER_LOGOUT")
	local n = 0
	for _ in pairs(CraftWiseMarketDB.itemInfo) do n = n + 1 end
	eq(n, 10000)
	local info = SerializedSize(CraftWiseMarketDB.itemInfo)
	local names = SerializedSize(CraftWiseMarketDB.names)
	local total = SerializedSize(CraftWiseMarketDB)
	print(("       measured: itemInfo for 10,000 items = %.2f MB (names %.2f MB, whole market file %.2f MB at 1 house)")
		:format(info / MB, names / MB, total / MB))
	assert(info < 0.5 * MB, ("%.2f MB"):format(info / MB))
	local sample = M.ItemInfo(20003)
	eq(sample.q, 1); eq(sample.c, 1); eq(sample.s, 1); eq(sample.i, 132000 + 6967)
end)
