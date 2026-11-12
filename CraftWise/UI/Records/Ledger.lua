-- Records window, Ledger tab (`/craftwise ledger`, #46): what you bought and sold since the last reset,
-- today or since login (the same setting the slash command uses), or one line per day. Reset asks for a
-- second click.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local Money, Signed, Muted = RW.Money, RW.Signed, RW.Muted

local ITEM_COLUMNS = {
	{ key = "name", label = L["ITEM"], width = 250 },
	{ key = "bought", label = L["BOUGHT"], width = 60, align = "RIGHT" },
	{ key = "spent", label = L["SPENT"], width = 105, align = "RIGHT" },
	{ key = "sold", label = L["SOLD"], width = 60, align = "RIGHT" },
	{ key = "received", label = L["RECEIVED"], width = 105, align = "RIGHT" },
	{ key = "where", label = L["BOUGHT AT"], width = 150 },
}
local DAY_COLUMNS = {
	{ key = "name", label = L["DAY"], width = 150 },
	{ key = "start", label = L["START"], width = 110, align = "RIGHT" },
	{ key = "spent", label = L["SPENT"], width = 100, align = "RIGHT" },
	{ key = "received", label = L["RECEIVED"], width = 100, align = "RIGHT" },
	{ key = "net", label = L["NET"], width = 100, align = "RIGHT" },
	{ key = "change", label = L["MONEY CHANGE"], width = 110, align = "RIGHT" },
}

local tab = { key = "ledger", label = L["Ledger"] }

-- "items" with the view in CraftWiseDB.settings.ledgerView, or "days".
function tab.Mode(st)
	return st.ledgerDays and "days" or "items"
end

function tab.columns(st)
	return tab.Mode(st) == "days" and DAY_COLUMNS or ITEM_COLUMNS
end

-- Reset: the first click arms it, a second one within RW.ARM_SECONDS resets.
function tab.ClickReset(st, now)
	now = now or time()
	if st.ledgerArmed and now - st.ledgerArmed <= RW.ARM_SECONDS then
		st.ledgerArmed = nil
		ns.Ledger.Reset()
		st.ledgerDays = nil
		if ns.db then
			ns.db.settings.ledgerView = "reset"
		end
		return "reset"
	end
	st.ledgerArmed = now
	return "armed"
end

function tab.buttons(st)
	local view = ns.Ledger.View()
	local out = {}
	for _, v in ipairs({ { "reset", L["Since reset"] }, { "today", L["Today"] }, { "login", L["Since login"] } }) do
		out[#out + 1] = { key = v[1], label = v[2], width = 92, selected = not st.ledgerDays and view == v[1],
			onClick = function()
				st.ledgerDays = nil
				ns.db.settings.ledgerView = v[1]
			end }
	end
	out[#out + 1] = { key = "days", label = L["Per day"], width = 80, selected = st.ledgerDays and true or false,
		onClick = function()
			st.ledgerDays = true
		end, tip = L["One line per day: money at the start, bought, sold, net and the money change."] }
	local armed = st.ledgerArmed and time() - st.ledgerArmed <= RW.ARM_SECONDS
	out[#out + 1] = { key = "resetLedger", label = armed and L["Click again"] or L["Reset"], width = 92, warn = armed,
		onClick = function()
			tab.ClickReset(st)
		end, tip = L["Starts \"since reset\" now. Nothing is deleted: Today and the days stay. Asks for a second click."] }
	return out
end

local function ItemRows(sum)
	local rows, ids = {}, {}
	for _, r in ipairs(sum.items) do
		ids[#ids + 1] = r.itemID
		local where = {}
		for label in pairs(r.sources) do
			where[#where + 1] = label
		end
		table.sort(where)
		rows[#rows + 1] = { itemID = r.itemID, icon = RW.ItemIcon(r.itemID), name = RW.ItemText(r.itemID, { name = r.name, link = r.link }),
			cells = {
				bought = r.bought > 0 and tostring(r.bought) or Muted("-"),
				spent = r.bought > 0 and Money(r.spent) or Muted("-"),
				sold = (r.sold ~= 0 or r.received ~= 0) and tostring(r.sold) or Muted("-"),
				received = (r.sold ~= 0 or r.received ~= 0) and Money(r.received) or Muted("-"),
				where = #where > 0 and table.concat(where, ", ") or Muted("-"),
			} }
	end
	RW.LoadNames(ids)
	return rows
end

function tab.Model(st)
	local L_ = ns.Ledger
	if tab.Mode(st) == "days" then
		local days = L_.Days()
		local rows = {}
		for _, d in ipairs(days) do
			rows[#rows + 1] = { icon = "Interface\\Icons\\INV_Misc_Note_01", name = d.day,
				sub = d.other and d.other ~= 0 and Muted(L["not from logged trades"] .. " ") .. Signed(d.other) or nil,
				cells = { start = Money(d.startMoney), spent = Money(d.spent), received = Money(d.received), net = Signed(d.net),
					change = Signed(d.change) } }
		end
		return { rows = rows, summary = ("|cffffffff%s|r  ·  %d %s"):format(L["Ledger per day"], #rows, L["days recorded"])
			.. "\n" .. Muted(L["A day ends with the money the next recorded day started with. Not from logged trades: loot, quests, repairs, fees, AH sales by mail."]),
			empty = L["No day recorded yet for this character."] }
	end
	local sum = L_.Summary()
	if not sum then
		return { rows = {}, summary = Muted(L["Nothing recorded for this character yet."]),
			empty = L["The ledger starts once the client shows this character's money."] }
	end
	local line1 = ("|cffffffff%s|r %s  ·  %s %s  ·  %s %s  ·  %s %s"):format(L["Ledger"], sum.label,
		L["start"], Money(sum.startMoney), L["now"], Money(sum.money), L["money change"], Signed(sum.change))
	local line2 = ("%s %s  ·  %s %s  ·  %s %s"):format(L["spent"], Money(sum.spent), L["received"], Money(sum.received),
		L["net"], Signed(sum.net))
	if sum.other then
		if sum.other == 0 then
			line2 = line2 .. Muted("  ·  " .. L["net matches the money change"])
		else
			line2 = line2 .. "  ·  " .. Muted(L["not from logged trades:"] .. " ") .. Signed(sum.other)
		end
	end
	return { rows = ItemRows(sum), summary = line1 .. "\n" .. line2,
		empty = L["No purchase or sale recorded in this view."] }
end

RW.Register(tab)
RW.Ledger = tab
