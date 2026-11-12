-- Records window, Crates tab (`/craftwise crates`, #91): Waylaid crates by cost per Merchant's Favor (crate
-- bought + cheapest bundle to fill it), the crates you hold, and your Favor balance. Opening the tab looks at
-- the bags and the auction house records for crates, as the slash command does.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local C = ns.Style.colors
local Muted = RW.Muted

local tab = { key = "crates", label = L["Crates"] }

tab.columns = {
	{ key = "name", label = L["CRATE"], width = 220 },
	{ key = "perFavor", label = L["PER FAVOR"], width = 100, align = "RIGHT" },
	{ key = "crate", label = L["CRATE PRICE"], width = 110, align = "RIGHT" },
	{ key = "fill", label = L["CHEAPEST FILL"], width = 150 },
	{ key = "reward", label = L["REWARD"], width = 75, align = "RIGHT" },
	{ key = "held", label = L["YOU HOLD"], width = 70, align = "RIGHT" },
}

local function Money(copper)
	return copper and ns.FormatMoney(math.floor(copper + 0.5)) or Muted("-")
end

function tab.onOpen()
	local Cr = ns.Crates
	if Cr then
		pcall(Cr.ScanBags)
		pcall(Cr.ScanMarket)
	end
end

local function Row(e, favor, best)
	local tip = {}
	local cells = { perFavor = e.perFavor and Money(e.perFavor) or Muted("-"),
		crate = e.crate and Money(e.crate) or Muted(L["no price"]),
		reward = e.reward and tostring(e.reward) or Muted("?"),
		held = e.held > 0 and tostring(e.held) or Muted("0") }
	if e.fill then
		cells.fill = ("%d %s  %s"):format(e.fill.n, e.fill.name, Money(e.fill.total))
	elseif #e.options > 0 then
		cells.fill = Muted(L["no price for the bundles"])
	else
		cells.fill = Muted(L["fill list not read yet"])
	end
	if e.crate then
		tip[#tip + 1] = { L["Crate"], Money(e.crate) .. " " .. (e.crateLabel or "") }
	end
	for _, o in ipairs(e.options) do
		tip[#tip + 1] = { ("%d %s%s"):format(o.n, o.name, o.id and "" or (" " .. L["(item not identified)"])),
			o.total and (Money(o.total) .. " " .. (o.label or "")) or L["no price"] }
	end
	if e.reward then
		local how = e.rewardFrom == "tooltip" and L["from the tooltip"]
			or (L["seen at %d turn-ins"]):format(e.observed or 0)
		tip[#tip + 1] = { L["Reward"], ("%d %s (%s)"):format(e.reward, favor, how) }
	else
		tip[#tip + 1] = L["Reward not seen yet: turn one in once."]
	end
	if e.held > 0 and e.fillPerFavor then
		tip[#tip + 1] = { L["You hold"] .. " " .. e.held, (L["fill only: %s per %s"]):format(Money(e.fillPerFavor), favor) }
	end
	if #e.missing > 0 then
		tip[#tip + 1] = L["Missing:"] .. " " .. table.concat(e.missing, ", ")
	end
	local sub = e == best and (C.good .. L["best to buy and fill"] .. "|r") or (e.tier and Muted(tostring(e.tier)) or nil)
	return { itemID = e.id, icon = RW.ItemIcon(e.id), name = RW.ItemText(e.id, { name = e.name }), sub = sub, cells = cells, tip = tip }
end

function tab.Model()
	local Cr = ns.Crates
	if not Cr then
		return { rows = {}, summary = "", empty = "" }
	end
	local favor = Cr.FavorName() or L["Merchant's Favor"]
	local list, best, bestHeld = Cr.Ranked()
	local rows, ids = {}, {}
	for _, e in ipairs(list) do
		rows[#rows + 1] = Row(e, favor, best)
		ids[#ids + 1] = e.id
	end
	RW.LoadNames(ids)
	local balance = Cr.Balance()
	local line1 = ("|cffffffff%s|r  ·  %s"):format(L["Waylaid crates by cost per Favor"], favor)
	if balance and balance.balance then
		line1 = line1 .. ("  ·  %s: %d"):format(L["on this character"], balance.balance)
	end
	local parts = {}
	if best then
		parts[#parts + 1] = (L["Best to buy and fill: %s, %s per %s"]):format(best.name or ("item " .. best.id), Money(best.perFavor), favor)
	end
	if bestHeld then
		parts[#parts + 1] = (L["Best of the crates you hold: %s, fill for %s per %s"]):format(bestHeld.name or ("item " .. bestHeld.id),
			Money(bestHeld.fillPerFavor), favor)
	end
	local line2 = #parts > 0 and table.concat(parts, "  ·  ") or Muted(L["Crate bought + cheapest bundle, divided by the Favor it gives."])
	return { rows = rows, summary = line1 .. "\n" .. line2,
		empty = L["No Waylaid crate seen yet: carry one, or let an auction house scan see one."] }
end

RW.Register(tab)
RW.Crates = tab
