-- Loot toast (issue #114): what the player just received, one line per item or coin amount, each shown
-- for a few seconds and then faded out on its own timer.
--
--   * What was looted comes from the loot feed (LootFeed.lua, #126): the player's own CHAT_MSG_LOOT lines
--     read with the client's format strings, and looted coin (a money gain paired with CHAT_MSG_MONEY).
--     The farm tracker (Farm.lua) reads the same feed, so both always agree on what was looted.
--   * Value: the CraftWise sell value of the stack (ns.GetSellValue: AH at the profit house after the
--     cut, or vendor, whichever the addon uses), omitted when it has none.
--   * The same item (or coin) again while its line is still fully shown adds to that line and restarts
--     its timer, so an area loot of five corpses is one line per item, not five.
--   * Settings in CraftWiseDB.lootToast (Core.lua defaults): enabled, duration (seconds fully shown),
--     fade (seconds of fade-out), value (show the value text), locked, pos (anchor position).
--     `/craftwise loottoast on|off|lock|unlock|test|duration <s>|value on|off|reset`.
local _, ns = ...

local T = {}
ns.LootToast = T

T.MAX_LINES = 8 -- older lines are dropped when a new one would be the ninth
T.MIN_DURATION, T.MAX_DURATION = 1, 30
T.ROW_HEIGHT = 20
T.WIDTH = 260
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

-- Text of a line: item name in its link's quality colour (brackets dropped) and count, or the coins.
function T.LineText(line)
	if line.key == "money" then
		return ns.FormatMoney(line.copper or 0)
	end
	local name = (line.link or ""):gsub("|h%[(.-)%]|h", "|h%1|h")
	if name == "" then
		name = ns.ItemInfoNow(line.itemID) or ("item " .. tostring(line.itemID))
	end
	if (line.count or 1) > 1 then
		name = name .. " |cffffffffx" .. line.count .. "|r"
	end
	return name
end

-- Small value text of a line ("12s 30c AH" / "45c vendor"), nil when off or unknown.
function T.ValueText(line)
	local s = Settings()
	if line.key == "money" or (s and s.value == false) then
		return nil
	end
	local copper, source = T.Value(line.itemID, line.count)
	if not copper then
		return nil
	end
	return ns.FormatMoney(copper) .. " " .. (source == "auction" and "AH" or "vendor")
end

----------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------

local anchor -- movable frame the rows hang from
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

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, anchor)
	row:SetSize(T.WIDTH, T.ROW_HEIGHT)
	row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(i - 1) * T.ROW_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(T.ROW_HEIGHT - 2, T.ROW_HEIGHT - 2)
	row.icon:SetPoint("LEFT")
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetJustifyH("LEFT")
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("LEFT", row.text, "RIGHT", 8, 0)
	row.value:SetJustifyH("LEFT")
	rows[i] = row
	return row
end

-- Draws the lines at `now`; drops the faded ones first.
function T.Render(now)
	if not anchor then
		return
	end
	local active = T.Expire(now)
	for i, line in ipairs(lines) do
		local row = Row(i)
		row.icon:SetTexture(line.icon)
		row.text:SetText(T.LineText(line))
		local value = T.ValueText(line)
		row.value:SetText(value and ((ns.Style and ns.Style.colors.muted or "") .. value .. "|r") or "")
		row:SetAlpha(T.Alpha(line, now))
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

local function ApplyLock()
	local s = Settings()
	local locked = not s or s.locked ~= false
	anchor:EnableMouse(not locked)
	anchor.bg:SetShown(not locked)
	anchor.label:SetShown(not locked)
end

local function Build()
	if anchor then
		return anchor
	end
	anchor = CreateFrame("Frame", "CraftWiseLootToastAnchor", UIParent)
	anchor:SetSize(T.WIDTH, T.ROW_HEIGHT)
	anchor:SetFrameStrata("HIGH")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", anchor.StartMoving)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
	anchor.bg:SetAllPoints()
	if ns.Style then
		ns.Style.Fill(anchor.bg, ns.Style.colors.accent)
	end
	anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	anchor.label:SetPoint("CENTER")
	anchor.label:SetText("CraftWise loot - drag, then /craftwise loottoast lock")
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

-- Up to three different items from the bags (with their real values) and a coin line, marked as test
-- lines so a real loot never adds to them.
function T.Test()
	Build()
	if not T.Enabled() then
		ns.Print("Loot toast is off; showing the test anyway. /craftwise loottoast on turns it on.")
	end
	local seen, n = {}, 0
	for bag = 0, ns.LAST_BAG or 5 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not seen[info.itemID] and n < 3 then
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
		ns.Print(arg == "unlock" and "Loot toast unlocked: drag the blue bar, then /craftwise loottoast lock."
			or "Loot toast locked.")
	elseif arg == "test" then
		T.Test()
	elseif arg == "reset" then
		s.pos = nil
		Build()
		PlaceAnchor()
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
