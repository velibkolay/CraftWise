-- Farm tracker window (#126): session stats on the left, the loot list on the right, in the CraftWise
-- style; below them a Fishing panel (#130) while the session has catches. The loot panel shows the list
-- (per item) or the log (one line per drop, newest first, #130); the view is kept in CraftWiseDB.farm.view. Movable by its title (unless locked), scalable, position kept in CraftWiseDB.farm.pos. The
-- numbers come from ns.Farm.Totals; this file only draws them. Refreshed once a second while shown and
-- whenever the session changes (FARM_CHANGED).
local _, ns = ...
local Style, L = ns.Style, ns.L
local C = Style.colors
local Farm = ns.Farm

local FF = {}
ns.FarmFrame = FF

FF.STATS_WIDTH = 236
FF.LIST_WIDTH = 330
FF.HEIGHT = 300
FF.ROW_HEIGHT = 18
FF.VISIBLE_ROWS = 13
FF.ZONE_LINES = 3
FF.FISH_HEIGHT = 136
FF.DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = -300, y = 150 }

local frame
local offset = 0
local last -- totals of the last refresh
local logOffset = 0
local logEntries -- log of the last refresh, newest first

FF.FISH_MARK = "|TInterface\\Icons\\Trade_Fishing:12:12|t"
FF.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- "list" or "log".
function FF.View()
	local st = ns.db and ns.db.farm
	return st and st.view == "log" and "log" or "list"
end

function FF.SetView(view)
	local st = ns.db and ns.db.farm
	if st then
		st.view = view == "log" and "log" or "list"
	end
	FF.Refresh()
end

local function Settings()
	return ns.db and ns.db.farm
end

local function Muted(text)
	return C.muted .. text .. "|r"
end

local function Money(copper)
	return copper and ns.FormatMoney(copper) or Muted("-")
end

-- Item text: name in its link's quality colour, brackets dropped.
local function ItemText(row)
	local link = row.link
	if type(link) == "string" and link:find("|h[", 1, true) then
		return (link:gsub("|h%[(.-)%]|h", "|h%1|h"))
	end
	return (ns.ItemInfoNow(row.itemID)) or ("item " .. tostring(row.itemID))
end
FF.ItemText = ItemText

-- Value cell of a list row: stack value and where it comes from; "?" when no price is known.
function FF.ValueText(row)
	if not row.value then
		return C.warn .. "?|r"
	end
	local tag = row.source == "auction" and "AH" or "vendor"
	if row.stale then
		tag = C.warn .. tag .. "!|r"
	else
		tag = Muted(tag)
	end
	return Money(row.value) .. " " .. tag
end

----------------------------------------------------------------------------------------------------
-- Position, lock, scale
----------------------------------------------------------------------------------------------------

local function SavePosition()
	local s = Settings()
	if not (s and frame) then
		return
	end
	local point, _, relPoint, x, y = frame:GetPoint()
	if point then
		s.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

local function Place()
	local s = Settings()
	local pos = s and s.pos or FF.DEFAULT_POS
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

function FF.ApplyLock()
	if not frame then
		return
	end
	local s = Settings()
	frame.locked = s and s.locked or false
	frame.lockText:SetText(frame.locked and Muted("locked") or "")
end

function FF.ApplyScale()
	if not frame then
		return
	end
	local s = Settings()
	local scale = s and tonumber(s.scale) or 1
	frame:SetScale(math.max(Farm.MIN_SCALE, math.min(Farm.MAX_SCALE, scale)))
end

----------------------------------------------------------------------------------------------------
-- Build
----------------------------------------------------------------------------------------------------

local STAT_KEYS = { "time", "coin", "items", "vendor", "ah", "gph", "coinGph", "priciest", "unknown" }
local STAT_LABELS = { time = "Time", coin = "Coin", items = "Items", vendor = "Vendor only", ah = "AH part",
	gph = "Gold / hour", coinGph = "Coin / hour", priciest = "Priciest", unknown = "Unpriced" }
local STAT_HELP = {
	time = "Time the session ran. Pauses, idle stretches and time logged out don't count.",
	coin = "Coin looted (paired with the loot message; vendor sales, mail and quests don't count).",
	items = "Items looted, each at its CraftWise sell value: AH at your profit house after the cut, or vendor, whichever pays more. Bind on pickup and quest items: vendor. Unpriced items are not in it.",
	vendor = "The same items, all sold to a vendor.",
	ah = "The part of Items that rests on AH prices; the part from AH prices over a day old is shown as stale.",
	gph = "Coin + Items per hour of session time (from one minute on).",
	coinGph = "Coin only, per hour.",
	priciest = "The looted item with the highest value per unit.",
	unknown = "Items with no AH or vendor price: counted, never valued.",
}

local function StatLine(parent, i, key)
	local y = -40 - (i - 1) * 17
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 12, y)
	label:SetText(L[STAT_LABELS[key]])
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("TOPRIGHT", -12, y)
	value:SetJustifyH("RIGHT")
	value:SetWidth(FF.STATS_WIDTH - 104)
	value:SetWordWrap(false)
	local hover = CreateFrame("Frame", nil, parent)
	hover:SetPoint("TOPLEFT", 8, y + 2)
	hover:SetSize(FF.STATS_WIDTH - 16, 16)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L[STAT_LABELS[key]])
		GameTooltip:AddLine(L[STAT_HELP[key]], 0.8, 0.8, 0.8, true)
		local p = key == "priciest" and last and last.priciest
		if p then
			GameTooltip:AddDoubleLine(ItemText(p), Money(p.unit) .. " " .. L["each"], 1, 1, 1, 1, 1, 1)
		end
		if key == "ah" and last and last.stale > 0 then
			GameTooltip:AddDoubleLine(L["From stale AH prices"], Money(last.stale), 1, 0.6, 0.3, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	hover:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return value
end

local FISH_KEYS = { "catches", "rate", "perCatch", "gph", "best", "opened" }
local FISH_LABELS = { catches = "Catches", rate = "Your rate", perCatch = "Per catch", gph = "Gold / hour",
	best = "Best catch", opened = "Containers" }
local FISH_HELP = {
	catches = "Fishing loot windows this session (the fishing log's catches), and catches per hour of fishing time: the time between two catches at most two minutes apart.",
	perCatch = "Coin + items per catch, items at the same values as the loot list. Caught containers you opened count as their contents. Unpriced items are counted apart, not in it.",
	rate = "Your long-run catch rate from the fishing log (#136): timed catches per hour over the last 90 days, overall and in open water and pools. Catches less than the fishing session gap apart are one session (/craftwise fishing gap); a session's first catch is untimed. Shown from as many timed catches as /craftwise fishing ownmin asks.",
	gph = "Fishing coin + items per hour of fishing time.",
	best = "The caught item with the highest value per unit.",
	opened = "Containers caught this session and opened: their contents count as fishing loot.",
}

-- The long-run catch rate (#136, ns.Fishing.CatchRate): "167/h · open 170 · pools 120", only from enough
-- timed catches (a water type below that is left out of the line, the tooltip says why).
local RATE_WATERS = { { "open", "open", "Open water" }, { "pool", "pools", "Pools" }, { "?", "not known", "Water not known yet" } }
local function PerHour(x)
	return ("%d/h"):format(math.floor(x + 0.5))
end

function FF.RateText(r)
	if not r or r.timed == 0 then
		return Muted(L["no timed catches yet"])
	end
	if not r.enough then
		return Muted((L["%d timed catches, too few (%d)"]):format(r.timed, r.min))
	end
	local parts = {}
	for _, w in ipairs(RATE_WATERS) do
		local x = r.waters[w[1]]
		if x and x.enough then
			parts[#parts + 1] = L[w[2]] .. " " .. math.floor(x.perHour + 0.5)
		end
	end
	return PerHour(r.perHour) .. (#parts > 0 and Muted("  ·  " .. table.concat(parts, "  ·  ")) or "")
end

function FF.RateTooltip()
	local r = ns.Fishing.CatchRate and ns.Fishing.CatchRate()
	if not r then
		return
	end
	local function line(label, x)
		local text = x.perHour and x.enough and PerHour(x.perHour) or L["too few"]
		GameTooltip:AddDoubleLine(label, ("%s  (%d timed, %d min)"):format(text, x.timed, math.floor(x.seconds / 60 + 0.5)),
			0.8, 0.8, 0.8, 1, 1, 1)
	end
	line(L["All water"], r)
	for _, w in ipairs(RATE_WATERS) do
		if r.waters[w[1]] then
			line(L[w[3]], r.waters[w[1]])
		end
	end
end

local function FishLine(parent, i, key)
	local y = -32 - (i - 1) * 16
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", 12, y)
	label:SetText(L[FISH_LABELS[key]])
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("TOPLEFT", 92, y)
	value:SetWidth(FF.STATS_WIDTH - 2)
	value:SetJustifyH("LEFT")
	value:SetWordWrap(false)
	local hover = CreateFrame("Frame", nil, parent)
	hover:SetPoint("TOPLEFT", 8, y + 2)
	hover:SetSize(FF.STATS_WIDTH + 70, 16)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L[FISH_LABELS[key]])
		GameTooltip:AddLine(L[FISH_HELP[key]], 0.8, 0.8, 0.8, true)
		local f = last and last.fish
		if key == "perCatch" and f and f.unknownUnits > 0 then
			GameTooltip:AddLine((L["%d caught items without a price."]):format(f.unknownUnits), 1, 0.6, 0.3, true)
		end
		if key == "rate" then
			FF.RateTooltip()
		end
		if key == "perCatch" and f and f.coin > 0 then
			GameTooltip:AddDoubleLine(L["Coin from fishing"], Money(f.coin), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	hover:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return value
end

local function BuildFish()
	local fish = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	fish:SetPoint("TOPLEFT", frame.stats, "BOTTOMLEFT", 0, -6)
	fish:SetSize(FF.STATS_WIDTH + FF.LIST_WIDTH + 6, FF.FISH_HEIGHT)
	Style.Panel(fish)
	frame.fish = fish
	local title = fish:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Fishing"])
	fish.values = {}
	for i, key in ipairs(FISH_KEYS) do
		fish.values[key] = FishLine(fish, i, key)
	end
	local x = FF.STATS_WIDTH + 100
	local head = fish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	head:SetPoint("TOPLEFT", x, -14)
	head:SetText(Muted(L["Zones"] .. "  ·  " .. L["catches, per catch, per hour"]))
	fish.zones = {}
	for i = 1, FF.ZONE_LINES do
		local name = fish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", x, -16 - i * 16)
		name:SetWidth(96)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		local value = fish:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOPRIGHT", -12, -16 - i * 16)
		value:SetJustifyH("RIGHT")
		fish.zones[i] = { name = name, value = value }
	end
	fish:Hide()
end

-- The Fishing panel: shown with its numbers while the session has catches, hidden otherwise.
local function RefreshFish(f)
	local fish = frame.fish
	frame:SetHeight(FF.HEIGHT + (f and (FF.FISH_HEIGHT + 6) or 0))
	if not f then
		fish:Hide()
		return
	end
	fish:Show()
	local V = fish.values
	V.catches:SetText(f.catches .. (f.cph and Muted(("  ·  %s/h"):format(f.cph)) or ""))
	V.rate:SetText(FF.RateText(ns.Fishing.CatchRate and ns.Fishing.CatchRate()))
	V.perCatch:SetText(Money(f.perCatch) .. (f.unknownUnits > 0 and ("  " .. C.warn .. "+" .. f.unknownUnits .. " ?|r") or ""))
	V.gph:SetText(Money(f.gph))
	local b = f.best
	V.best:SetText(b and (ItemText(b) .. " " .. ns.FormatMoney(b.unit)) or Muted("-"))
	V.opened:SetText(f.opened > 0 and tostring(f.opened) or Muted("0"))
	for i, z in ipairs(fish.zones) do
		local zone = f.zones[i]
		z.name:SetText(zone and zone.zone or "")
		z.value:SetText(zone and (zone.catches .. "  " .. Money(zone.perCatch) .. "  " .. Money(zone.gph) .. Muted("/h")) or "")
	end
end

local function RowTooltip(self)
	local r = self.data
	if not r then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
	else
		GameTooltip:AddLine(ItemText(r))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Looted this session"], tostring(r.n), 0.8, 0.8, 0.8, 1, 1, 1)
	if r.value then
		GameTooltip:AddDoubleLine(L["Value"], Money(r.value), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Each"], Money(r.unit) .. "  " .. (r.label or r.source or ""), 0.8, 0.8, 0.8, 1, 1, 1)
		if r.stale then
			GameTooltip:AddLine((L["AH price is %d days old."]):format(r.age), 1, 0.6, 0.3)
		end
		if r.cutUnverified then
			GameTooltip:AddLine(L["AH cut unverified at this house: value before the cut."], 1, 0.6, 0.3, true)
		end
	else
		GameTooltip:AddLine(L["No AH or vendor price known: not valued."], 1, 0.76, 0.3, true)
	end
	if r.noAuction then
		GameTooltip:AddLine(L["Bind on pickup or quest item: vendor only."], 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(L["x: remove from this session and ignore it until Reset."], 0.55, 0.55, 0.6, true)
	GameTooltip:Show()
end

local function BuildRows(list)
	frame.rows = {}
	for i = 1, FF.VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(FF.LIST_WIDTH - 16, FF.ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * FF.ROW_HEIGHT)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		Style.Fill(row.bg, i % 2 == 0 and C.stripe or { 0, 0, 0, 0 })
		row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.count:SetPoint("LEFT", 2, 0)
		row.count:SetWidth(34)
		row.count:SetJustifyH("RIGHT")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(FF.ROW_HEIGHT - 4, FF.ROW_HEIGHT - 4)
		row.icon:SetPoint("LEFT", row.count, "RIGHT", 4, 0)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row.name:SetWidth(150)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.remove = Style.CloseButton(row, function()
			local data = row.data
			if data then
				Farm.RemoveItem(data.itemID)
			end
		end)
		row.remove:SetSize(16, 16)
		row.remove:SetPoint("RIGHT", 0, 0)
		row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
		row.value:SetJustifyH("RIGHT")
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		frame.rows[i] = row
	end
end

local function LogTooltip(self)
	local e = self.data
	if not e then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if e.itemID and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(e.itemID)
	else
		GameTooltip:AddLine(e.itemID and ItemText(e) or L["Coin"])
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Looted at"], date("%H:%M:%S", e.t), 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Zone"], e.zone, 0.8, 0.8, 0.8, 1, 1, 1)
	if e.itemID then
		GameTooltip:AddDoubleLine(L["Count"], tostring(e.n), 0.8, 0.8, 0.8, 1, 1, 1)
		if e.value then
			GameTooltip:AddDoubleLine(L["Value"], Money(e.value) .. "  " .. (e.label or e.source or ""), 0.8, 0.8, 0.8, 1, 1, 1)
		else
			GameTooltip:AddLine(L["No AH or vendor price known: not valued."], 1, 0.76, 0.3, true)
		end
	else
		GameTooltip:AddDoubleLine(L["Coin"], Money(e.copper), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if e.fish then
		GameTooltip:AddLine(L["From a fishing catch."], 0.5, 0.8, 1, true)
	end
	GameTooltip:Show()
end

local function BuildLogRows(list)
	frame.logRows = {}
	for i = 1, FF.VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(FF.LIST_WIDTH - 16, FF.ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * FF.ROW_HEIGHT)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		Style.Fill(row.bg, i % 2 == 0 and C.stripe or { 0, 0, 0, 0 })
		row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.time:SetPoint("LEFT", 2, 0)
		row.time:SetWidth(48)
		row.time:SetJustifyH("LEFT")
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(FF.ROW_HEIGHT - 4, FF.ROW_HEIGHT - 4)
		row.icon:SetPoint("LEFT", row.time, "RIGHT", 2, 0)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row.name:SetWidth(118)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.zone:SetPoint("RIGHT", 0, 0)
		row.zone:SetWidth(52)
		row.zone:SetJustifyH("RIGHT")
		row.zone:SetWordWrap(false)
		row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", row.zone, "LEFT", -4, 0)
		row.value:SetJustifyH("RIGHT")
		row:SetScript("OnEnter", LogTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:Hide()
		frame.logRows[i] = row
	end
end

-- One log line: value cell like the list's ("?" = unknown), coin lines in coin.
function FF.LogValueText(e)
	if e.copper then
		return Money(e.copper)
	end
	return FF.ValueText(e)
end

local function Build()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "CraftWiseFarmFrame", UIParent, "BackdropTemplate")
	frame:SetSize(FF.STATS_WIDTH + FF.LIST_WIDTH + 6, FF.HEIGHT)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not self.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	local stats = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	stats:SetPoint("TOPLEFT")
	stats:SetSize(FF.STATS_WIDTH, FF.HEIGHT)
	Style.Panel(stats)
	frame.stats = stats
	local title = stats:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -12)
	title:SetText("|cffffffffCraftWise|r " .. Muted(L["Farm"]))
	frame.state = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.state:SetPoint("LEFT", title, "RIGHT", 8, 0)
	frame.lockText = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.lockText:SetPoint("TOPRIGHT", -12, -14)

	frame.values = {}
	for i, key in ipairs(STAT_KEYS) do
		frame.values[key] = StatLine(stats, i, key)
	end
	local zoneY = -40 - #STAT_KEYS * 17 - 6
	local zoneHead = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zoneHead:SetPoint("TOPLEFT", 12, zoneY)
	zoneHead:SetText(Muted(L["Zones"]))
	frame.zones = {}
	for i = 1, FF.ZONE_LINES do
		local name = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("TOPLEFT", 12, zoneY - i * 15)
		name:SetWidth(100)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		local value = stats:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOPRIGHT", -12, zoneY - i * 15)
		value:SetJustifyH("RIGHT")
		frame.zones[i] = { name = name, value = value }
	end

	frame.pause = Style.Button(stats, 80, 22, L["Pause"])
	frame.pause:SetPoint("BOTTOMLEFT", 12, 10)
	frame.pause:SetScript("OnClick", function()
		Farm.TogglePause()
	end)
	frame.reset = Style.Button(stats, 80, 22, L["Reset"])
	frame.reset:SetPoint("LEFT", frame.pause, "RIGHT", 8, 0)
	frame.reset:SetScript("OnClick", function()
		Farm.Slash("reset")
	end)
	frame.reset:SetScript("OnEnter", function(self)
		self:SetSelected(false)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Reset"])
		GameTooltip:AddLine(L["Ends the session and keeps it in the history (/craftwise farm history)."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	frame.reset:SetScript("OnLeave", function(self)
		self:SetSelected(false)
		GameTooltip:Hide()
	end)
	local gear = CreateFrame("Button", nil, stats)
	gear:SetSize(18, 18)
	gear:SetPoint("LEFT", frame.reset, "RIGHT", 10, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetAllPoints()
	gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetScript("OnClick", function(self)
		ns.ToggleSettings(self)
	end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Settings"])
		GameTooltip:AddLine("/craftwise farm lock | unlock | scale <n> | idle <min> | history", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	list:SetPoint("TOPLEFT", stats, "TOPRIGHT", 6, 0)
	list:SetSize(FF.LIST_WIDTH, FF.HEIGHT)
	Style.Panel(list)
	frame.list = list
	local close = Style.CloseButton(list, function()
		Farm.Slash("hide")
	end)
	close:SetPoint("TOPRIGHT", -6, -6)
	frame.listHead = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.listHead:SetPoint("TOPLEFT", 12, -12)
	frame.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER")
	frame.empty:SetWidth(FF.LIST_WIDTH - 40)
	BuildRows(list)
	BuildLogRows(list)
	frame.viewButton = Style.Button(list, 56, 20, "")
	frame.viewButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
	frame.viewButton:SetScript("OnClick", function()
		FF.SetView(FF.View() == "log" and "list" or "log")
	end)
	frame.viewButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(FF.View() == "log" and L["Loot list"] or L["Loot log"])
		GameTooltip:AddLine(FF.View() == "log" and L["Per item: count and value, x removes an item."]
			or L["One line per drop, newest first: time, item, value, zone; fishing catches marked."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	frame.viewButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		if FF.View() == "log" then
			local n = logEntries and #logEntries or 0
			logOffset = math.max(0, math.min(math.max(0, n - FF.VISIBLE_ROWS), logOffset - delta * 3))
		else
			local n = last and #last.rows or 0
			offset = math.max(0, math.min(math.max(0, n - FF.VISIBLE_ROWS), offset - delta * 3))
		end
		FF.Refresh()
	end)

	BuildFish()

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed >= 1 then
			elapsed = 0
			Farm.Tick()
			FF.Refresh()
		end
	end)

	Place()
	FF.ApplyLock()
	FF.ApplyScale()
	return frame
end

----------------------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------------------

function FF.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local s = Farm.Current()
	local now = Farm.Now()
	local V = frame.values
	if not s then
		last = nil
		offset = 0
		for _, key in ipairs(STAT_KEYS) do
			V[key]:SetText(Muted("-"))
		end
		V.time:SetText(Farm.FormatTime(0))
		frame.state:SetText(Muted(L["no session"]))
		frame.pause:SetLabel(L["Start"])
		for _, z in ipairs(frame.zones) do
			z.name:SetText("")
			z.value:SetText("")
		end
		for _, row in ipairs(frame.rows) do
			row.data = nil
			row:Hide()
		end
		logEntries, logOffset = nil, 0
		for _, row in ipairs(frame.logRows) do
			row.data = nil
			row:Hide()
		end
		frame.viewButton:SetLabel(FF.View() == "log" and L["List"] or L["Log"])
		frame.listHead:SetText(Muted(FF.View() == "log" and L["Loot log"] or L["Loot"]))
		frame.empty:SetText(Farm.AutoStart() and L["A session starts with your next loot."]
			or L["Press Start, then loot."])
		frame.empty:Show()
		RefreshFish(nil)
		return
	end
	local t = Farm.Totals(s, now)
	last = t
	RefreshFish(t.fish)
	local state
	if Farm.Running(s) then
		state = C.good .. L["running"] .. "|r"
	elseif s.autoPaused then
		state = C.warn .. L["paused (idle)"] .. "|r"
	else
		state = C.warn .. L["paused"] .. "|r"
	end
	frame.state:SetText(state)
	frame.pause:SetLabel(Farm.Running(s) and L["Pause"] or L["Resume"])
	V.time:SetText(Farm.FormatTime(t.seconds))
	V.coin:SetText(Money(t.coin))
	V.items:SetText(Money(t.items))
	V.vendor:SetText(Money(t.vendor) .. (t.vendorUnknown > 0 and Muted(" +?") or ""))
	V.ah:SetText(Money(t.ah) .. (t.stale > 0 and (" " .. C.warn .. L["stale"] .. " " .. ns.FormatMoney(t.stale) .. "|r") or ""))
	V.gph:SetText(Money(t.gph))
	V.coinGph:SetText(Money(t.coinGph))
	local p = t.priciest
	V.priciest:SetText(p and (ItemText(p) .. " " .. ns.FormatMoney(p.unit)) or Muted("-"))
	V.unknown:SetText(t.unknownUnits > 0 and (C.warn .. t.unknownUnits .. "|r" .. Muted(" (" .. t.unknownItems .. " " .. L["items"] .. ")"))
		or Muted("0"))
	for i, z in ipairs(frame.zones) do
		local zone = t.zones[i]
		z.name:SetText(zone and zone.zone or "")
		z.value:SetText(zone and (Farm.FormatTime(zone.seconds) .. "  " .. Money(zone.gph) .. Muted("/h")) or "")
	end

	frame.viewButton:SetLabel(FF.View() == "log" and L["List"] or L["Log"])
	if FF.View() == "log" then
		for _, row in ipairs(frame.rows) do
			row.data = nil
			row:Hide()
		end
		FF.RefreshLog(s)
		return
	end
	for _, row in ipairs(frame.logRows) do
		row.data = nil
		row:Hide()
	end
	local n = #t.rows
	offset = math.max(0, math.min(offset, math.max(0, n - FF.VISIBLE_ROWS)))
	frame.listHead:SetText(Muted(("%s  ·  %d"):format(L["Loot"], n)))
	frame.empty:SetText(L["Nothing looted yet."])
	frame.empty:SetShown(n == 0)
	for i, row in ipairs(frame.rows) do
		local r = t.rows[offset + i]
		row.data = r
		if r then
			row.count:SetText(C.warn .. r.n .. "x|r")
			local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID)
			row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:SetText(ItemText(r))
			row.value:SetText(FF.ValueText(r))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- The log view: newest drop on top.
function FF.RefreshLog(s)
	logEntries = Farm.LogEntries(s)
	local n = #logEntries
	logOffset = math.max(0, math.min(logOffset, math.max(0, n - FF.VISIBLE_ROWS)))
	local head = ("%s  ·  %d"):format(L["Loot log"], n)
	if (s.logDropped or 0) > 0 then
		head = head .. (" (%d %s)"):format(s.logDropped, L["older dropped"])
	end
	frame.listHead:SetText(Muted(head))
	frame.empty:SetText(L["Nothing looted yet."])
	frame.empty:SetShown(n == 0)
	for i, row in ipairs(frame.logRows) do
		local e = logEntries[logOffset + i]
		row.data = e
		if e then
			row.time:SetText(Muted(date("%H:%M:%S", e.t)))
			if e.itemID then
				local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.itemID)
				row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				row.name:SetText((e.fish and (FF.FISH_MARK .. " ") or "") .. (e.n > 1 and (C.warn .. e.n .. "x|r ") or "") .. ItemText(e))
			else
				row.icon:SetTexture(FF.COIN_ICON)
				row.name:SetText((e.fish and (FF.FISH_MARK .. " ") or "") .. L["Coin"])
			end
			row.value:SetText(FF.LogValueText(e))
			row.zone:SetText(Muted(e.zone))
			row:Show()
		else
			row:Hide()
		end
	end
end

function FF.Rows()
	return frame and frame.rows
end

function FF.LogRows()
	return frame and frame.logRows
end

function FF.FishPanel()
	return frame and frame.fish
end

function FF.Show()
	Build()
	frame:Show()
	FF.Refresh()
end

function FF.Hide()
	if frame then
		frame:Hide()
	end
end

function FF.IsShown()
	return frame ~= nil and frame:IsShown()
end

ns.Listen("FARM_CHANGED", FF.Refresh)
ns.Listen("PRICES_CHANGED", FF.Refresh)
