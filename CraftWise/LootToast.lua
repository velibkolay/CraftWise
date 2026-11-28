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
--   * Look (#426): floating like OneForAll's loot feed, no strips or backgrounds. Each line is an 18 icon
--     (cropped), 6 apart a 14 OUTLINE name (quality colour: "+name", "+N name"; coin "+coins" in gold, no icon)
--     and, 8 after it, the value in C.text2 ("12s 40c AH"). Lines float up the 260 x 200 area at (height - 18) / life
--     (life = duration + fade), fade in over 0.2 s, fade out over the fade, and push each other up to keep
--     22 apart. A long name is cut before the value is.
--     `/craftwise loottoast on|off|lock|unlock|test|duration <s>|value on|off|reset`.
--
-- The floating look is adapted from OneForAll 6.2.17, "Loot feed" (Smoergi, GPL-3.0-or-later).
local _, ns = ...

local T = {}
ns.LootToast = T

T.MAX_LINES = 8 -- older lines are dropped when a new one would be the ninth
T.MIN_DURATION, T.MAX_DURATION = 1, 30
T.WIDTH, T.HEIGHT = 260, 200 -- the area the lines float up in (and the Move box)
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
	local duration, fade = line.duration or T.Duration(), T.Fade()
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

-- Fade-in at the start of a line's life (a merged line keeps its own start, so it does not blink).
T.FADE_IN = 0.2
function T.LineAlpha(line, now)
	local born = line.born or line.t
	local a = T.Alpha(line, now)
	if now - born < T.FADE_IN then
		a = a * math.max(0, now - born) / T.FADE_IN
	end
	return a
end

-- Adds a line (or adds to the same item's line while it is still fully shown) and returns it. A new line
-- starts at the bottom (y = 0); a merged one goes back there with its timer restarted.
function T.Add(entry, now)
	for i, line in ipairs(lines) do
		if line.key == entry.key and not line.test == not entry.test and now - line.t <= T.Duration() then
			line.count = (line.count or 0) + (entry.count or 0)
			line.copper = (line.copper or 0) + (entry.copper or 0)
			line.link = entry.link or line.link
			line.t, line.y, line.floatT = now, 0, now
			table.remove(lines, i)
			table.insert(lines, 1, line)
			return line
		end
	end
	local line = {}
	for k, v in pairs(entry) do
		line[k] = v
	end
	line.t, line.born, line.y, line.floatT = now, now, 0, now
	table.insert(lines, 1, line)
	while #lines > T.MAX_LINES do
		table.remove(lines)
	end
	return line
end

-- Floating: speed = (height - top margin) / life, so an undisturbed line reaches the top just as its life
-- ends. Lines keep GAP apart, the newer ones push the older ones up (a pushed line may reach the top early).
T.GAP = 22
T.TOP_MARGIN = 18 -- a line that reaches height - this is gone
function T.Life(line)
	return (line and line.duration or T.Duration()) + T.Fade()
end

function T.Float(now)
	for i, line in ipairs(lines) do
		local dt = math.max(0, now - (line.floatT or now))
		line.floatT = now
		local y = (line.y or 0) + (T.HEIGHT - T.TOP_MARGIN) / T.Life(line) * dt
		if i > 1 then
			y = math.max(y, lines[i - 1].y + T.GAP)
		end
		line.y = y
	end
end

-- Drops the lines that have faded out or floated to the top; true while any line is left.
function T.Expire(now)
	for i = #lines, 1, -1 do
		if T.Alpha(lines[i], now) <= 0 or (lines[i].y or 0) > T.HEIGHT - T.TOP_MARGIN then
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
	if line.text then -- a line of another feature (the vendor loop alert, #186): text, best name, profit
		parts.name = line.text
		parts.color = line.itemID and Style.QualityColor(T.Quality(line.itemID)) or Style.C.text
		parts.count = line.detail
		parts.money = line.copper and ("+" .. ns.FormatCoins(line.copper)) or nil
		parts.source = line.copper and (line.sourceText or "per craft") or nil
		return parts
	end
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

----------------------------------------------------------------------------------------------------
-- Frame: the anchor is the 260 x 200 area; each line floats up from its bottom edge.
----------------------------------------------------------------------------------------------------

T.ICON = 18
T.ICON_GAP = 6
T.SPACE = 8 -- between the name and the value
T.PAD = 4
T.FONT_SIZE = 14
T.MOVE_BG_ALPHA = 0.25

local anchor -- movable frame the rows float in; while unlocked it is the Move box
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

local function Outlined(fs, color)
	local font = fs:GetFont() or ns.Style.FontFiles.next
	if font then
		fs:SetFont(font, T.FONT_SIZE, "OUTLINE")
	end
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetTextColor(color[1], color[2], color[3], 1)
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	local C = ns.Style.C
	row = CreateFrame("Frame", nil, anchor)
	row:SetSize(T.WIDTH - 2 * T.PAD, 20)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(T.ICON, T.ICON)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.name = ns.Style.Text(row, "Body", "text")
	row.value = ns.Style.Text(row, "Body", "text2")
	Outlined(row.name, C.text)
	Outlined(row.value, C.text2)
	row:SetScript("OnMouseUp", function(self)
		local click = self.line and self.line.onClick
		if click then
			click(self.line)
		end
	end)
	rows[i] = row
	return row
end

local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The head of a line: "+name", "+N name"; the coin line "+coins" in gold. Its colour comes with it.
function T.Head(line, parts)
	if line.key == "money" then
		return "+" .. Plain(parts.money), ns.Style.C.coinGold
	end
	local n = tonumber(line.count) or 1
	return "+" .. (n > 1 and (n .. " ") or "") .. parts.name, parts.color
end

-- The muted tail: detail (lines of other features), value and source word, "test". Coin digits lose their
-- colours here, so the whole value is one muted text.
function T.Tail(line, parts)
	local out = {}
	if line.text and parts.count then
		out[#out + 1] = parts.count
	end
	if parts.money and line.key ~= "money" then
		out[#out + 1] = Plain(parts.money)
		if parts.source then
			out[#out + 1] = parts.source
		end
	end
	if parts.test then
		out[#out + 1] = "test"
	end
	return table.concat(out, " ")
end

-- Fills a row; the name is cut (the client's "...") before the value is: its width is what is left of the
-- area after the icon and the value.
local function Fill(row, line)
	local parts = T.LineParts(line)
	local head, color = T.Head(line, parts)
	local tail = T.Tail(line, parts)
	local hasIcon = line.key ~= "money"
	row.icon:SetShown(hasIcon)
	if hasIcon then
		row.icon:SetTexture(line.icon or T.UNKNOWN_ICON)
	end
	row.name:ClearAllPoints()
	if hasIcon then
		row.name:SetPoint("LEFT", row.icon, "RIGHT", T.ICON_GAP, 0)
	else
		row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
	end
	row.name:SetWidth(0)
	row.name:SetText(head)
	row.name:SetTextColor(color[1], color[2], color[3], 1)
	row.value:SetText(tail)
	local valueWidth = tail ~= "" and math.ceil(row.value:GetStringWidth() or 0) + T.SPACE or 0
	local room = (T.WIDTH - 2 * T.PAD) - (hasIcon and (T.ICON + T.ICON_GAP) or 0) - valueWidth
	local want = math.ceil(row.name:GetStringWidth() or 0)
	row.name:SetWidth(math.max(1, math.min(want, room)))
	row.value:ClearAllPoints()
	row.value:SetPoint("LEFT", row.name, "RIGHT", T.SPACE, 0)
	row.value:SetShown(tail ~= "")
end

-- Draws the lines at `now`: moves them, drops the finished ones.
function T.Render(now)
	if not anchor then
		return
	end
	T.Float(now)
	local active = T.Expire(now)
	for i, line in ipairs(lines) do
		local row = Row(i)
		row.line = line
		row:EnableMouse(line.onClick ~= nil) -- clickable lines (#186) open their page
		Fill(row, line)
		row:ClearAllPoints()
		row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", T.PAD, line.y or 0)
		row:SetAlpha(T.LineAlpha(line, now))
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

-- Move (unlocked): the whole area shows as a dim white box with a 1 unit C.text outline and its label; drag it.
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
	anchor:SetSize(T.WIDTH, T.HEIGHT)
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
	Style.Fill(anchor.handle, C.text, T.MOVE_BG_ALPHA)
	anchor.label = Style.Text(anchor, "Label", "text")
	anchor.label:SetPoint("CENTER", anchor, "CENTER", 0, 0)
	anchor.label:SetText("Loot toast · drag to move")
	anchor.outline = CreateFrame("Frame", nil, anchor)
	anchor.outline:SetAllPoints(anchor)
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

-- A line of another feature, shown whatever the loot toast's own switch says (it has its own setting):
-- { key, text, detail, copper, icon, duration, onClick }. A line with the same key is replaced.
function T.ShowCustom(entry)
	for i = #lines, 1, -1 do
		if lines[i].key == entry.key then
			table.remove(lines, i)
		end
	end
	Build()
	local now = GetTime()
	local line = T.Add(entry, now)
	anchor:SetScript("OnUpdate", OnUpdate)
	T.Render(now)
	return line
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
		ns.Print(arg == "unlock" and "Loot toast unlocked: drag the white box, then Lock in the Settings (or /craftwise loottoast lock)."
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
