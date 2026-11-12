-- Loot toast (issue #114): what the player just received, one line per item or coin amount, each shown
-- for a few seconds and then faded out on its own timer.
--
--   * What was looted comes from the loot feed (LootFeed.lua, #126): the player's own CHAT_MSG_LOOT lines
--     read with the client's format strings, what containers opened from the bags give (#135, read from
--     their loot window, with or without a chat line), and looted coin (a money gain paired with CHAT_MSG_MONEY).
--     The farm tracker (Farm.lua) reads the same feed, so both always agree on what was looted.
--   * Value: the CraftWise sell value of the stack (ns.GetSellValue: AH at the profit house after the
--     cut, or vendor, whichever the addon uses), omitted when it has none.
--   * The same item (or coin) again while its line is still fully shown adds to that line and restarts
--     its timer, so an area loot of five corpses is one line per item, not five.
--   * Settings in CraftWiseDB.lootToast (Core.lua defaults): enabled, duration (seconds fully shown),
--     fade (seconds of fade-out), value (show the value text), locked, pos (anchor position).
--   * Look (#159, Origami): each line a folded strip, the newest with the turkuaz flap; lines step down in
--     alpha (1, 0.75, 0.5); background alpha from db.settings.alpha.toast (default 0.70).
--     `/craftwise loottoast on|off|lock|unlock|test|duration <s>|value on|off|reset`.
local _, ns = ...

local T = {}
ns.LootToast = T

T.MAX_LINES = 8 -- older lines are dropped when a new one would be the ninth
T.MIN_DURATION, T.MAX_DURATION = 1, 30
T.ROW_HEIGHT = 28
T.WIDTH = 260 -- width of the Move handle and outline; the strips are as wide as their text
T.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
T.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
T.DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 300, y = 120 }

local function Settings()
	return ns.db and ns.db.lootToast
end

function T.Enabled()
	local s = Settings()
	return s ~= nil and s.enabled ~= false
end

function T.Duration()
	local s = Settings()
	return s and tonumber(s.duration) or 4
end

function T.Fade()
	local s = Settings()
	return s and tonumber(s.fade) or 1
end

-- Parsing lives in the loot feed (#126); kept here under the names the toast always had.
local Feed = ns.LootFeed
T.Pattern, T.ParseLoot, T.ItemID = Feed.Pattern, Feed.ParseLoot, Feed.ItemID
T.MONEY_PAIR_SECONDS = Feed.MONEY_PAIR_SECONDS

----------------------------------------------------------------------------------------------------
-- Lines (pure; the frame below only draws them)
----------------------------------------------------------------------------------------------------

local lines = {} -- newest first: { key, itemID, link, count, copper, icon, t, test }

function T.Lines()
	return lines
end

function T.Clear()
	for i = #lines, 1, -1 do
		lines[i] = nil
	end
end

-- 1 while shown, falling to 0 over the fade, 0 once over.
function T.Alpha(line, now)
	local age = now - line.t
	local duration, fade = T.Duration(), T.Fade()
	if age <= duration then
		return 1
	end
	if fade <= 0 or age >= duration + fade then
		return 0
	end
	return 1 - (age - duration) / fade
end

-- Sell value of the line's stack in copper (ns.GetSellValue), and its source; nil when unknown.
function T.Value(itemID, count)
	if not (itemID and ns.GetSellValue) then
		return nil
	end
	local v = ns.GetSellValue(itemID)
	if not (v and v.copper and v.copper > 0) then
		return nil
	end
	return math.floor(v.copper * (count or 1) + 0.5), v.source
end

-- Adds a line (or adds to the same item's line while it is still fully shown) and returns it.
function T.Add(entry, now)
	for i, line in ipairs(lines) do
		if line.key == entry.key and not line.test == not entry.test and now - line.t <= T.Duration() then
			line.count = (line.count or 0) + (entry.count or 0)
			line.copper = (line.copper or 0) + (entry.copper or 0)
			line.link = entry.link or line.link
			line.t = now
			table.remove(lines, i)
			table.insert(lines, 1, line)
			return line
		end
	end
	local line = {}
	for k, v in pairs(entry) do
		line[k] = v
	end
	line.t = now
	table.insert(lines, 1, line)
	while #lines > T.MAX_LINES do
		table.remove(lines)
	end
	return line
end

-- Drops the lines that have faded out; true while any line is left.
function T.Expire(now)
	for i = #lines, 1, -1 do
		if T.Alpha(lines[i], now) <= 0 then
			table.remove(lines, i)
		end
	end
	return #lines > 0
end

local function ItemIcon(itemID)
	local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
	if not icon and C_Item.GetItemInfoInstant then
		icon = select(5, C_Item.GetItemInfoInstant(itemID))
	end
	return icon or T.UNKNOWN_ICON
end

-- Name of a line's item: the link's text without brackets, else the client's name, else "item <id>".
function T.ItemName(line)
	local name = line.link and line.link:match("|h%[(.-)%]|h")
	if not name or name == "" then
		name = ns.ItemInfoNow(line.itemID)
	end
	return name or ("item " .. tostring(line.itemID))
end

-- Quality of the line's item (C_Item.GetItemQualityByID, else the item info), nil while unknown.
function T.Quality(itemID)
	if not itemID then
		return nil
	end
	local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	if q == nil and C_Item.GetItemInfo then
		q = select(3, C_Item.GetItemInfo(itemID))
	end
	return q
end

-- What a line shows (#159, spec "Loot toast"): name in its quality colour, "×count" (C.text2), the stack's
-- value in coin digits with its source word (AH / vendor) when "With value" is on, and "test" on the Test
-- lines. The coin line is "Coin" and the coins themselves.
--   { name, color = Style colour, count = "×4" | nil, money = coins text | nil, source = "AH" | "vendor" | nil,
--     test = true | nil }
function T.LineParts(line)
	local Style = ns.Style
	local parts = { test = line.test and true or nil }
	if line.key == "money" then
		parts.name, parts.color = "Coin", Style.C.text
		parts.money = ns.FormatCoins(line.copper or 0)
		return parts
	end
	parts.name = T.ItemName(line)
	parts.color = Style.QualityColor(T.Quality(line.itemID)) or Style.C.text
	parts.count = "×" .. tostring(line.count or 1)
	local s = Settings()
	if not (s and s.value == false) then
		local copper, source = T.Value(line.itemID, line.count)
		if copper then
			parts.money = ns.FormatCoins(copper)
			parts.source = source == "auction" and "AH" or "vendor"
		end
	end
	return parts
end

-- Alpha by position: the newest line 1, the next 0.75, every older one 0.5 (spec "Loot toast").
T.STEPS = { 1, 0.75, 0.5 }
function T.StepAlpha(index)
	return T.STEPS[math.min(math.max(index or 1, 1), #T.STEPS)]
end

-- A line's alpha: its step times its own timer (shown for "Lines stay", then the fade-out).
function T.LineAlpha(index, line, now)
	return T.StepAlpha(index) * T.Alpha(line, now)
end

-- Background transparency of the strips (Settings > Look and > Loot toast, db.settings.alpha.toast, #162).
-- Only the strips' fill and shadow use it; icon, text and the turkuaz flap of the newest line follow the
-- line's own alpha.
T.DEFAULT_ALPHA = 0.70
function T.BackgroundAlpha()
	return ns.Style.WindowAlpha("toast")
end

----------------------------------------------------------------------------------------------------
-- Frame: each line a folded strip (cut 8, hard shadow), 28 tall, 6 apart, newest on top. Padding 6 left
-- and 20 right (room for the dog-ear), parts 8 apart; the strip is as wide as what it shows.
----------------------------------------------------------------------------------------------------

T.CUT = 8
T.GAP = 6
T.PAD_LEFT, T.PAD_RIGHT = 6, 20
T.ICON = 18
T.SPACE = 8
T.HANDLE = 16 -- the Move handle above the lines
T.MOVE_LINES = 3 -- the Move outline covers this many lines

local anchor -- movable frame the rows hang from; while unlocked it is the drag handle
local rows = {}

local function SavePosition()
	local s = Settings()
	if not (s and anchor) then
		return
	end
	local point, _, relPoint, x, y = anchor:GetPoint()
	if point then
		s.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

local function PlaceAnchor()
	local s = Settings()
	local pos = s and s.pos or T.DEFAULT_POS
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

-- Top of line i below the anchor.
function T.RowOffset(i)
	return -(i - 1) * (T.ROW_HEIGHT + T.GAP)
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	local Style = ns.Style
	local C = Style.C
	row = CreateFrame("Frame", nil, anchor)
	row:SetHeight(T.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, T.RowOffset(i))
	row.sheet = Style.Sheet(row, C.sheet, C.flap, T.CUT, true)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(T.ICON, T.ICON)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:SetPoint("LEFT", row, "LEFT", T.PAD_LEFT, 0)
	row.name = Style.Text(row, "Body", "text")
	row.count = Style.Text(row, "Figure", "text2")
	row.money = Style.Text(row, "Figure", "text")
	row.source = Style.Text(row, "Caption", "text3")
	row.test = Style.Text(row, "Caption", "text3")
	row.test:SetText("test")
	row.parts = { row.name, row.count, row.money, row.source, row.test }
	for _, fs in ipairs(row.parts) do
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
	end
	rows[i] = row
	return row
end

-- Fills a row with a line's parts; places them left to right and sizes the strip to them.
local function Fill(row, parts)
	row.name:SetText(parts.name)
	row.name:SetTextColor(parts.color[1], parts.color[2], parts.color[3], 1)
	row.count:SetText(parts.count or "")
	row.money:SetText(parts.money or "")
	row.source:SetText(parts.source or "")
	local shown = { row.name, parts.count and row.count, parts.money and row.money, parts.source and row.source,
		parts.test and row.test }
	local x = T.PAD_LEFT + T.ICON + T.SPACE
	local first = true
	for i, fs in ipairs(row.parts) do
		if shown[i] then
			if not first then
				x = x + T.SPACE
			end
			first = false
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", row, "LEFT", x, 0)
			fs:Show()
			x = x + math.ceil(fs:GetStringWidth() or 0)
		else
			fs:Hide()
		end
	end
	row:SetWidth(x + T.PAD_RIGHT)
end

-- Draws the lines at `now`; drops the faded ones first.
function T.Render(now)
	if not anchor then
		return
	end
	local C = ns.Style.C
	local active = T.Expire(now)
	local bg = T.BackgroundAlpha()
	for i, line in ipairs(lines) do
		local row = Row(i)
		row.icon:SetTexture(line.icon)
		Fill(row, T.LineParts(line))
		row.sheet:SetFlap(i == 1 and C.nokta or C.flap)
		row.sheet:SetAlpha(bg)
		-- The flap of the newest line is "here": it keeps full strength whatever the background alpha.
		if i == 1 then
			row.sheet.pieces.c:SetVertexColor(C.nokta[1], C.nokta[2], C.nokta[3], 1)
		end
		row:SetAlpha(T.LineAlpha(i, line, now))
		row:Show()
	end
	for i = #lines + 1, #rows do
		rows[i]:Hide()
	end
	if not active then
		anchor:SetScript("OnUpdate", nil)
	end
end

local function OnUpdate()
	T.Render(GetTime())
end

-- Move (unlocked): a 1 unit C.text outline over the first three lines' place and a handle above it to drag.
local function ApplyLock()
	local s = Settings()
	local locked = not s or s.locked ~= false
	anchor:EnableMouse(not locked)
	anchor.handle:SetShown(not locked)
	anchor.label:SetShown(not locked)
	anchor.outline:SetShown(not locked)
end

local function Build()
	if anchor then
		return anchor
	end
	local Style = ns.Style
	local C = Style.C
	anchor = CreateFrame("Frame", "CraftWiseLootToastAnchor", UIParent)
	anchor:SetSize(T.WIDTH, T.HANDLE)
	anchor:SetFrameStrata("HIGH")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	anchor.handle = anchor:CreateTexture(nil, "BACKGROUND")
	anchor.handle:SetAllPoints(anchor)
	Style.Fill(anchor.handle, C.text)
	anchor.label = Style.Text(anchor, "Label", Style.INK)
	anchor.label:SetPoint("LEFT", anchor, "LEFT", T.PAD_LEFT, 0)
	anchor.label:SetText("Loot toast · drag to move")
	anchor.outline = CreateFrame("Frame", nil, anchor)
	anchor.outline:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
	anchor.outline:SetSize(T.WIDTH, T.MOVE_LINES * T.ROW_HEIGHT + (T.MOVE_LINES - 1) * T.GAP)
	anchor.outline.border = Style.Border(anchor.outline, C.text)
	PlaceAnchor()
	ApplyLock()
	anchor:Show()
	return anchor
end

local function Show(entry)
	if not T.Enabled() then
		return nil
	end
	Build()
	local now = GetTime()
	local line = T.Add(entry, now)
	anchor:SetScript("OnUpdate", OnUpdate)
	T.Render(now)
	return line
end

function T.ShowItem(link, count, itemID)
	itemID = itemID or T.ItemID(link)
	if not itemID then
		return nil
	end
	return Show({ key = "item:" .. itemID, itemID = itemID, link = link, count = count or 1, icon = ItemIcon(itemID) })
end

function T.ShowMoney(copper)
	if not (copper and copper > 0) then
		return nil
	end
	return Show({ key = "money", copper = copper, count = 0, icon = T.COIN_ICON })
end

----------------------------------------------------------------------------------------------------
-- Events: one line per looted item or coin amount from the loot feed (LootFeed.lua, #126).
----------------------------------------------------------------------------------------------------

function T.OnFeed(kind, data)
	if not T.Enabled() then
		return
	end
	if kind == "item" then
		T.ShowItem(data.link, data.count, data.itemID)
	elseif kind == "money" then
		T.ShowMoney(data.copper)
	end
end

Feed.Subscribe(T.OnFeed)

----------------------------------------------------------------------------------------------------
-- Test lines and slash command
----------------------------------------------------------------------------------------------------

-- Three sample lines (spec: "Test pushes three sample lines labelled as a test"): two different items
-- from the bags with their real values and a coin line, each labelled "test" and marked so a real loot
-- never adds to them. With fewer items in the bags, fewer lines.
T.TEST_ITEMS = 2
function T.Test()
	Build()
	if not T.Enabled() then
		ns.Print("Loot toast is off; showing the test anyway. /craftwise loottoast on turns it on.")
	end
	local seen, n = {}, 0
	for bag = 0, ns.LAST_BAG or 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not seen[info.itemID] and n < T.TEST_ITEMS then
				seen[info.itemID] = true
				n = n + 1
				T.Add({ key = "item:" .. info.itemID, itemID = info.itemID, link = info.hyperlink,
					count = info.stackCount or 1, icon = info.iconFileID or ItemIcon(info.itemID), test = true }, GetTime())
			end
		end
	end
	T.Add({ key = "money", copper = 12345, count = 0, icon = T.COIN_ICON, test = true }, GetTime())
	anchor:SetScript("OnUpdate", OnUpdate)
	T.Render(GetTime())
end

local function Status()
	local s = Settings() or {}
	ns.Print(("Loot toast %s, %s, %gs shown + %gs fade, value %s."):format(
		T.Enabled() and "on" or "off", s.locked == false and "unlocked" or "locked",
		T.Duration(), T.Fade(), s.value == false and "off" or "on"))
	ns.Print("/craftwise loottoast on | off | unlock | lock | test | duration <seconds> | value on | value off | reset")
end

-- Back to the default place (also Settings › Look › Reset window positions, #157).
function T.ResetPosition()
	local s = Settings()
	if not s then
		return
	end
	s.pos = nil
	Build()
	PlaceAnchor()
end

function T.Slash(arg)
	local s = Settings()
	if not s then
		return
	end
	arg = (arg or ""):lower():match("^%s*(.-)%s*$")
	if arg == "on" or arg == "off" then
		s.enabled = arg == "on"
		if not s.enabled then
			T.Clear()
			T.Render(GetTime())
		end
		ns.Print("Loot toast " .. arg .. ".")
	elseif arg == "unlock" or arg == "lock" then
		s.locked = arg == "lock"
		Build()
		ApplyLock()
		ns.Print(arg == "unlock" and "Loot toast unlocked: drag the white handle, then Lock in the Settings (or /craftwise loottoast lock)."
			or "Loot toast locked.")
	elseif arg == "test" then
		T.Test()
	elseif arg == "reset" then
		T.ResetPosition()
		ns.Print("Loot toast position reset.")
	elseif arg:match("^value") then
		local v = arg:match("^value%s+(%a+)$")
		if v ~= "on" and v ~= "off" then
			ns.Print("Usage: /craftwise loottoast value on | off")
			return
		end
		s.value = v == "on"
		ns.Print("Loot toast value " .. v .. ".")
	elseif arg:match("^duration") then
		local seconds = tonumber(arg:match("^duration%s+([%d%.]+)$"))
		if not seconds or seconds < T.MIN_DURATION or seconds > T.MAX_DURATION then
			ns.Print(("Usage: /craftwise loottoast duration <seconds, %d to %d>"):format(T.MIN_DURATION, T.MAX_DURATION))
			return
		end
		s.duration = seconds
		ns.Print(("Loot toast lines stay %gs, then fade in %gs."):format(seconds, T.Fade()))
	else
		Status()
	end
end
