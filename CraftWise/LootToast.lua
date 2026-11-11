-- Loot toast (issue #114): what the player just received, one line per item or coin amount, each shown
-- for a few seconds and then faded out on its own timer.
--
--   * Items: CHAT_MSG_LOOT lines of the player's own receipts, read with the client's own format strings
--     LOOT_ITEM_SELF_MULTIPLE and LOOT_ITEM_SELF ("You receive loot: %sx%d." / "You receive loot: %s." in
--     English; every locale's client has its own), so only items that actually reached the bags show, with
--     or without the loot window and whoever loots (Loot.lua, Blizzard, another addon). Items pushed
--     without looting (quest rewards, LOOT_ITEM_PUSHED_SELF) and other players' loot are left out.
--     The text may be a secret value on 12.x clients (Market.lua's OnLoot has the same note): such a line
--     is skipped, the item still reaches the bags.
--   * Coin: the money the player gained (PLAYER_MONEY, GetMoney before and after), shown only when a
--     CHAT_MSG_MONEY (the client's "You loot ..." / "Your share of the loot is ...") arrives within
--     MONEY_PAIR_SECONDS of it, in either order. The amount is the exact copper difference; the message
--     text is never parsed, so no locale's coin wording matters. Vendor sales, mail and quest rewards
--     change the money without that message and don't show.
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
T.MONEY_PAIR_SECONDS = 2
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

----------------------------------------------------------------------------------------------------
-- Parsing
----------------------------------------------------------------------------------------------------

-- Lua pattern for a client format string, and the argument index of each capture. %s matches any text,
-- %d digits; positional forms (%1$s, %2$d) some locales use are honoured.
function T.Pattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		return nil
	end
	local order = {}
	local s = fmt:gsub("%%(%d)%$([sd])", function(index, kind)
		order[#order + 1] = tonumber(index)
		return "\1" .. kind
	end)
	s = s:gsub("%%([sd])", function(kind)
		order[#order + 1] = #order + 1
		return "\1" .. kind
	end)
	s = s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	s = s:gsub("\1s", "(.+)"):gsub("\1d", "(%%d+)")
	return "^" .. s .. "$", order
end

local function Match(text, fmt)
	local pattern, order = T.Pattern(fmt)
	if not pattern then
		return nil
	end
	local caps = { text:match(pattern) }
	if #caps == 0 then
		return nil
	end
	local args = {}
	for i, index in ipairs(order) do
		args[index] = caps[i]
	end
	return args
end

-- Item link and count of one of the player's own loot lines, or nil (someone else's loot, another
-- message, a secret value). The multiple form first: the single one's %s would swallow "x2".
function T.ParseLoot(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return nil
	end
	local args = Match(text, LOOT_ITEM_SELF_MULTIPLE)
	if args and args[1] and args[2] then
		return args[1], tonumber(args[2])
	end
	args = Match(text, LOOT_ITEM_SELF)
	if args and args[1] then
		return args[1], 1
	end
	return nil
end

function T.ItemID(link)
	return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

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
-- Events
----------------------------------------------------------------------------------------------------

function T.OnLoot(_, text)
	if not T.Enabled() then
		return
	end
	local link, count = T.ParseLoot(text)
	if link then
		T.ShowItem(link, count)
	end
end

-- Coin: a money gain and a CHAT_MSG_MONEY within MONEY_PAIR_SECONDS, in either order.
local lastMoney, gain, moneyMsg -- gain = { copper, t }; moneyMsg = t of an unpaired CHAT_MSG_MONEY

local function Fresh(t, now)
	return t and now - t <= T.MONEY_PAIR_SECONDS
end

function T.OnMoney()
	local now, money = GetTime(), GetMoney()
	local before = lastMoney
	lastMoney = money
	if not before or money <= before then
		return
	end
	local copper = money - before
	if Fresh(moneyMsg, now) then
		moneyMsg, gain = nil, nil
		if T.Enabled() then
			T.ShowMoney(copper)
		end
		return
	end
	if gain and Fresh(gain.t, now) then
		gain.copper = gain.copper + copper -- several changes before the message: one loot
	else
		gain = { copper = copper, t = now }
	end
end

function T.OnMoneyMessage()
	local now = GetTime()
	if gain and Fresh(gain.t, now) then
		local copper = gain.copper
		gain, moneyMsg = nil, nil
		if T.Enabled() then
			T.ShowMoney(copper)
		end
		return
	end
	gain, moneyMsg = nil, now
end

local function NoteMoney()
	lastMoney = GetMoney()
end

ns.On("CHAT_MSG_LOOT", T.OnLoot)
ns.On("CHAT_MSG_MONEY", T.OnMoneyMessage)
ns.On("PLAYER_MONEY", T.OnMoney)
ns.On("PLAYER_LOGIN", NoteMoney)
ns.On("PLAYER_ENTERING_WORLD", NoteMoney)

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
