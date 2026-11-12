-- Farm tracker (#126), in the Origami look (#150 "Farm tracker and mini mode", #158). One folded sheet
-- 260 wide whose dog-ear carries the state (orange running, rule-strong paused, flap without a session):
-- top line (Farm, state word, timer), gold per hour, the split bar (coin, items at AH, vendor only), the
-- fishing card while the session has catches, the top 5 loot, links Log · History and the buttons of the
-- state. The numbers come from ns.Farm (Farm.lua, unchanged); FF.Model turns them into plain data that the
-- specs read and this file draws. Refreshed once a second while shown and on FARM_CHANGED.
--
-- The links open Gather › Farm in the main window (#156, UI/Main/Pages/Farm.lua): Log the open session's
-- row with its loot log, "+ N more" the same row with every item (× removes one from the session), History
-- and the no-session History button the page itself (FF.OpenLog, FF.OpenList, FF.OpenHistory).
--
-- Mini mode (#164): the – button at the top right (or Settings) swaps frame.full for frame.mini, a strip
-- 30 tall with a cut 12 corner in the state colour: timer, gold per hour, "/ h"; paused "Paused" and the
-- session total. Click opens the full tracker, right-click pauses or resumes, drag moves it. The mode is
-- CraftWiseDB.farm.mini; both modes share the tracker's position (CraftWiseDB.farm.pos), and switching
-- keeps the top left corner where it is.
--
-- Fade (#163): with CraftWiseDB.farm.fade on, the whole tracker (full or mini) sits at 40 % alpha while the mouse is away and returns to 100 % on hover, in 140 ms. The frame's
-- OnEnter/OnLeave drive it; the per-frame OnUpdate also checks, because moving onto a child (a row, a
-- button) doesn't fire the tracker's own OnEnter/OnLeave.
--
-- Background alpha (#162) is frame.cwSheet:SetAlpha.
local _, ns = ...
local Style, L = ns.Style, ns.L
local C = Style.C
local Farm = ns.Farm

local FF = {}
ns.FarmFrame = FF

FF.WIDTH = 260
FF.CUT = 22
FF.PAD = 16
FF.INNER = FF.WIDTH - 2 * FF.PAD
FF.TOP_LOOT = 5
FF.LOOT_ROW = 24
FF.SPLIT_HEIGHT = 6
FF.SPLIT_GAP = 2
FF.BUTTON_HEIGHT = 28
FF.DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = -300, y = 150 }
-- Mini mode (#164): strip height, corner, padding left / right, gap between its parts.
FF.MINI_HEIGHT = 30
FF.MINI_CUT = 12
FF.MINI_PAD_LEFT = 12
FF.MINI_PAD_RIGHT = 26
FF.MINI_GAP = 12
-- Fade (#163): alpha away from the mouse, and how long a change takes.
FF.FADE_ALPHA = 0.4
FF.FADE_TIME = 0.14

FF.FISH_MARK = "|TInterface\\Icons\\Trade_Fishing:12:12|t"
FF.COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame
local last -- model of the last refresh

local function Settings()
	return ns.db and ns.db.farm
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

local function Paint(text, color)
	return Style.Hex(color) .. text .. "|r"
end

-- Money in coin colours, at most two units (ns.FormatCoins, Money.lua); nil is "—" in text3 (no figure,
-- never a guess).
function FF.Coins(copper)
	if copper == nil then
		return Paint("—", "text3")
	end
	return ns.FormatCoins(copper)
end

-- The same without colours, for the inverse tooltip (dark text on a light sheet).
function FF.PlainCoins(copper)
	if copper == nil then
		return "—"
	end
	return (ns.FormatCoins(copper):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "0:41:05" (board "Farm tracker states").
function FF.Timer(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

-- Item name without colour or brackets; "item <id>" only when nothing is known.
function FF.ItemName(row)
	local name = ns.ItemInfoNow and ns.ItemInfoNow(row.itemID)
	if not name and type(row.link) == "string" then
		name = row.link:match("%[(.-)%]")
	end
	return name or ("item " .. tostring(row.itemID))
end

-- Colour of an item's quality (Style.QualityColor, spec: q-* constants); text when it has none or is unknown.
function FF.ItemColor(itemID)
	local quality = C_Item and C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(itemID))
	return Style.QualityColor(quality) or C.text
end

-- Item text: name in its link's colour, brackets dropped.
local function ItemText(row)
	local link = row.link
	if type(link) == "string" and link:find("|h[", 1, true) then
		return (link:gsub("|h%[(.-)%]|h", "|h%1|h"))
	end
	return (ns.ItemInfoNow(row.itemID)) or ("item " .. tostring(row.itemID))
end
FF.ItemText = ItemText

-- Value cell: stack value and its source word; an AH value over a day old carries its age in red; no
-- price says so (spec: States, Unknown price and Stale).
function FF.ValueText(row)
	if not row.value then
		return Paint(L["no price"], "text3")
	end
	local tag = Paint(row.source == "auction" and "AH" or L["vendor"], "text3")
	if row.stale then
		tag = tag .. " " .. Paint(("%d d"):format(row.age or 0), "danger")
	end
	return FF.Coins(row.value) .. " " .. tag
end

-- One log line: like the list's value cell; coin lines are coin.
function FF.LogValueText(e)
	if e.copper then
		return FF.Coins(e.copper)
	end
	return FF.ValueText(e)
end

-- The long-run catch rate (#136, ns.Fishing.CatchRate) for the fishing card's last line: "your usual rate
-- 144/h", or how many timed catches there are of the ones it needs.
function FF.RateText(r)
	if not r then
		return nil
	end
	if not r.enough then
		return (L["your usual rate: %d of %d timed catches"]):format(r.timed or 0, r.min or 0)
	end
	return (L["your usual rate %d/h"]):format(math.floor(r.perHour + 0.5))
end

-- The same rate per water type, for the card's tooltip.
local RATE_WATERS = { { "open", "Open water" }, { "pool", "Pools" }, { "?", "Water not known yet" } }
function FF.RateLines(r)
	local lines = {}
	if not r then
		return lines
	end
	local function line(label, x)
		local rate = x.perHour and x.enough and ("%d/h"):format(math.floor(x.perHour + 0.5)) or L["too few"]
		lines[#lines + 1] = ("%s: %s (%d %s, %d min)"):format(label, rate, x.timed, L["timed"], math.floor(x.seconds / 60 + 0.5))
	end
	line(L["All water"], r)
	for _, w in ipairs(RATE_WATERS) do
		if r.waters[w[1]] then
			line(L[w[2]], r.waters[w[1]])
		end
	end
	return lines
end

----------------------------------------------------------------------------------------------------
-- Model: what the tracker shows, as plain data
----------------------------------------------------------------------------------------------------

-- The tracker for session s (nil = none) at `now`:
-- { state = "none"|"running"|"paused"|"idle", flap, word, wordColor, timer, timerColor, hero (copper|nil),
--   caption, title, hint (no session), split = { coin, ah, vendor }, fish, loot (top rows), more, unpriced,
--   buttons = { names }, totals }
function FF.Model(s, now)
	if not s then
		return { state = "none", flap = "flap", word = L["no session"], wordColor = "text3", title = L["Press Start, then loot."],
			hint = Farm.AutoStart() and L["Or just loot: \"Start on first loot\" is on in Settings."] or nil,
			buttons = { "start", "history" }, loot = {}, more = 0, unpriced = 0 }
	end
	local t = Farm.Totals(s, now)
	local m = { totals = t, timer = FF.Timer(t.seconds), hero = t.gph, fish = t.fish }
	if Farm.Running(s) then
		m.state, m.flap, m.word, m.wordColor, m.timerColor = "running", "live", L["running"], "live", "text"
		m.buttons = { "pause", "endAction" }
	else
		m.state = s.autoPaused and "idle" or "paused"
		m.flap, m.wordColor, m.timerColor = "ruleStrong", "text2", "text2"
		m.word = s.autoPaused and (L["paused · idle %d min"]):format(Farm.IdleMinutes()) or L["paused"]
		m.buttons = { "resume", "endLine" }
	end
	local zone = s.zone or (t.zones[1] and t.zones[1].zone)
	if m.state == "idle" then
		m.caption = L["per hour · resumes with your next loot"]
	else
		m.caption = L["per hour"] .. " · " .. L["total"] .. " " .. FF.Coins(t.total) .. (zone and (" · " .. zone) or "")
	end
	m.split = { coin = t.coin, ah = t.ah, vendor = t.items - t.ah, stale = t.stale }
	m.loot = {}
	for i = 1, math.min(FF.TOP_LOOT, #t.rows) do
		m.loot[i] = t.rows[i]
	end
	m.more = math.max(0, #t.rows - FF.TOP_LOOT)
	m.unpriced = t.unknownItems
	return m
end

-- "+ 9 more · 2 unpriced"; "" when there is neither.
function FF.FooterText(m)
	local parts = {}
	if m.more > 0 then
		parts[#parts + 1] = ("+ %d %s"):format(m.more, L["more"])
	end
	if m.unpriced > 0 then
		parts[#parts + 1] = ("%d %s"):format(m.unpriced, L["unpriced"])
	end
	return table.concat(parts, " · ")
end

-- The split bar: three parts with 2 unit gaps over `width`, each as wide as its share; parts without
-- value take no room and no gap. Returns { { x, w } } in the order given (w = 0: not drawn).
function FF.SplitGeometry(values, width, gap)
	gap = gap or FF.SPLIT_GAP
	local total, n = 0, 0
	for _, v in ipairs(values) do
		if v > 0 then
			total, n = total + v, n + 1
		end
	end
	local out = {}
	local free = width - gap * math.max(n - 1, 0)
	local x, placed = 0, 0
	for i, v in ipairs(values) do
		if v > 0 and total > 0 then
			placed = placed + 1
			local w = placed == n and (width - x) or math.floor(free * v / total + 0.5)
			w = math.max(1, w)
			out[i] = { x = x, w = w }
			x = x + w + gap
		else
			out[i] = { x = x, w = 0 }
		end
	end
	return out
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

local function StartDrag()
	if frame and not frame.locked then
		frame:StartMoving()
	end
end

local function StopDrag()
	if frame then
		frame:StopMovingOrSizing()
		SavePosition()
	end
end

-- Child frames that take the mouse (hover cells, rows) pass a drag on to the tracker.
local function ForwardDrag(f)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", StartDrag)
	f:SetScript("OnDragStop", StopDrag)
end

function FF.ApplyLock()
	if not frame then
		return
	end
	local s = Settings()
	frame.locked = s and s.locked or false
end

function FF.ApplyScale()
	if not frame then
		return
	end
	local s = Settings()
	local scale = s and tonumber(s.scale) or 1
	frame:SetScale(math.max(Farm.MIN_SCALE, math.min(Farm.MAX_SCALE, scale)))
	Style.SnapRules()
end

-- Re-anchors the tracker by its top left corner (kept in CraftWiseDB.farm.pos), so a change of size
-- (mini <-> full) grows or shrinks to the right and down. Nothing happens while the client can't say
-- where the frame is.
local function AnchorTopLeft()
	local left, top = frame:GetLeft(), frame:GetTop()
	if type(left) ~= "number" or type(top) ~= "number" then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	SavePosition()
end

----------------------------------------------------------------------------------------------------
-- Build: the tracker
----------------------------------------------------------------------------------------------------

-- An invisible cell over a region that shows the inverse tooltip; tip() returns title and lines.
local function Hover(parent, tip)
	local h = CreateFrame("Button", nil, parent)
	ForwardDrag(h)
	h:SetScript("OnEnter", function(self)
		local title, lines = tip()
		if title then
			Style.ShowTip(self, title, unpack(lines or {}))
		end
	end)
	h:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	return h
end

local function Height(fs, fallback)
	local h = fs.GetStringHeight and fs:GetStringHeight()
	return type(h) == "number" and h > 0 and math.ceil(h) or fallback
end

local function BuildTop(full)
	local title = Style.Text(full, "Section", "text")
	title:SetFont(Style.FontFiles.nextExtraBold, 13, "")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", FF.PAD, -14)
	title:SetText(L["Farm"])
	frame.title = title
	frame.word = Style.Text(full, "Small", "text3")
	Style.SmallBold(frame.word)
	frame.word:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 0)
	frame.timer = Style.Text(full, "Figure", "text")
	frame.timer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -46, -14)
	frame.timer:SetJustifyH("RIGHT")
	-- The – button (#164): a 8 x 2 bar in text2 (text while hovered) between the timer and the dog-ear.
	local minus = CreateFrame("Button", nil, full)
	minus:SetSize(16, 20)
	minus:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -11)
	minus.bar = minus:CreateTexture(nil, "ARTWORK")
	Style.Fill(minus.bar, C.text2)
	minus.bar:SetSize(8, 2)
	minus.bar:SetPoint("CENTER", minus, "CENTER", 0, 0)
	minus:SetScript("OnClick", function()
		FF.SetMini(true)
	end)
	minus:SetScript("OnEnter", function(self)
		Style.Fill(self.bar, C.text)
		Style.ShowTip(self, L["Mini mode"], L["Click the strip to open the full tracker again."])
	end)
	minus:SetScript("OnLeave", function(self)
		Style.Fill(self.bar, C.text2)
		Style.HideTip(self)
	end)
	ForwardDrag(minus)
	frame.minus = minus
end

local HERO_TIP = {
	"Coin + items per hour of session time (from one minute on). Items at their CraftWise sell value: AH at your profit house after the cut, or vendor, whichever pays more; bind on pickup and quest items at vendor. Unpriced items are not in it.",
}

local function HeroTip()
	local m = last
	if not (m and m.totals) then
		return nil
	end
	local t = m.totals
	local lines = { L[HERO_TIP[1]], L["Time"] .. ": " .. FF.Timer(t.seconds), L["Coin per hour"] .. ": " .. FF.PlainCoins(t.coinGph) }
	local p = t.priciest
	if p then
		lines[#lines + 1] = ("%s: %s, %s %s"):format(L["Priciest"], FF.ItemName(p), FF.PlainCoins(p.unit), L["each"])
	end
	for i = 1, math.min(3, #t.zones) do
		local z = t.zones[i]
		lines[#lines + 1] = ("%s: %s · %s/h"):format(z.zone, FF.Timer(z.seconds), FF.PlainCoins(z.gph))
	end
	return L["Gold per hour"], lines
end

local function BuildHero(full)
	local hero = CreateFrame("Frame", nil, full)
	hero:SetHeight(56)
	frame.hero = hero
	hero.value = Style.Text(hero, "FigureXL", "text")
	hero.value:SetPoint("TOPLEFT", hero, "TOPLEFT", FF.PAD, 0)
	hero.caption = Style.Text(hero, "Caption", "text3")
	hero.caption:SetPoint("TOPLEFT", hero, "TOPLEFT", FF.PAD, -42)
	hero.caption:SetWidth(FF.INNER)
	hero.caption:SetJustifyH("LEFT")
	hero.caption:SetWordWrap(false)
	hero.hover = Hover(hero, HeroTip)
	hero.hover:SetAllPoints(hero)

	-- No session: what to do (board "No session yet").
	local empty = CreateFrame("Frame", nil, full)
	frame.empty = empty
	empty.title = Style.Text(empty, "Section", "text")
	empty.title:SetFont(Style.FontFiles.nextExtraBold, 13, "")
	empty.title:SetPoint("TOPLEFT", empty, "TOPLEFT", FF.PAD, 0)
	empty.hint = Style.Text(empty, "Caption", "text2")
	empty.hint:SetPoint("TOPLEFT", empty.title, "BOTTOMLEFT", 0, -4)
	empty.hint:SetWidth(FF.INNER)
	empty.hint:SetJustifyH("LEFT")
	empty.hint:SetWordWrap(true)
end

local SPLIT = {
	{ key = "coin", color = C.coinGold, label = "Coin",
		help = "Coin looted (paired with the loot message; vendor sales, mail and quests don't count)." },
	{ key = "ah", color = C.text, label = "Items at AH",
		help = "Items whose CraftWise value is their AH price at your profit house, after the cut." },
	{ key = "vendor", color = C.ruleStrong, label = "Vendor only",
		help = "Items valued at their vendor price: no AH price, bound on pickup or a quest item, or the vendor pays more." },
}

local function SplitTip(i)
	return function()
		local m = last
		if not (m and m.totals) then
			return nil
		end
		local part, t = SPLIT[i], m.totals
		local lines = { L[part.help], FF.PlainCoins(m.split[part.key]) }
		if part.key == "ah" and t.stale > 0 then
			lines[#lines + 1] = (L["%s of it from AH prices over a day old."]):format(FF.PlainCoins(t.stale))
		end
		if part.key == "vendor" then
			lines[#lines + 1] = L["Everything sold to a vendor"] .. ": " .. FF.PlainCoins(t.vendor)
				.. (t.vendorUnknown > 0 and (" " .. (L["(%d without a vendor price)"]):format(t.vendorUnknown)) or "")
		end
		if t.unknownUnits > 0 then
			lines[#lines + 1] = (L["%d items without any price are counted, not valued."]):format(t.unknownUnits)
		end
		return L[part.label], lines
	end
end

local function BuildSplit(full)
	local split = CreateFrame("Frame", nil, full)
	split:SetHeight(FF.SPLIT_HEIGHT + 6 + 12 + 14)
	frame.split = split
	split.bars, split.labels, split.figures = {}, {}, {}
	local colWidth = FF.INNER / #SPLIT
	for i, part in ipairs(SPLIT) do
		local bar = split:CreateTexture(nil, "ARTWORK")
		Style.Fill(bar, part.color)
		bar:SetHeight(FF.SPLIT_HEIGHT)
		split.bars[i] = bar
		local label = Style.Text(split, "Label", "text3")
		label:SetPoint("TOPLEFT", split, "TOPLEFT", FF.PAD + (i - 1) * colWidth, -(FF.SPLIT_HEIGHT + 6))
		label:SetText(L[part.label])
		split.labels[i] = label
		local fig = Style.Text(split, "Figure", "text")
		fig:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
		split.figures[i] = fig
		local hover = Hover(split, SplitTip(i))
		hover:SetPoint("TOPLEFT", split, "TOPLEFT", FF.PAD + (i - 1) * colWidth, 0)
		hover:SetSize(colWidth, FF.SPLIT_HEIGHT + 6 + 12 + 14)
	end
end

local FISH_TIP = {
	"Fishing loot windows this session, and catches per hour of fishing time: the time between two catches at most two minutes apart.",
	"Per catch: coin + items per catch, items at the same values as the loot. Caught containers you opened count as their contents.",
	"Your usual rate: timed catches per hour from the fishing log over the last 90 days (Settings › Fishing sets the session gap and how many catches it needs).",
}

local function FishTip()
	local f = last and last.fish
	if not f then
		return nil
	end
	local lines = { L[FISH_TIP[1]], L[FISH_TIP[2]], L["Gold per hour of fishing"] .. ": " .. FF.PlainCoins(f.gph) }
	if f.coin > 0 then
		lines[#lines + 1] = L["Coin from fishing"] .. ": " .. FF.PlainCoins(f.coin)
	end
	if f.unknownUnits > 0 then
		lines[#lines + 1] = (L["%d caught items without a price."]):format(f.unknownUnits)
	end
	if f.opened > 0 then
		lines[#lines + 1] = (L["%d caught containers opened."]):format(f.opened)
	end
	for i = 1, math.min(3, #f.zones) do
		local z = f.zones[i]
		lines[#lines + 1] = ("%s: %d %s, %s %s"):format(z.zone, z.catches, L["catches"], FF.PlainCoins(z.perCatch), L["per catch"])
	end
	lines[#lines + 1] = L[FISH_TIP[3]]
	for _, line in ipairs(FF.RateLines(ns.Fishing.CatchRate and ns.Fishing.CatchRate())) do
		lines[#lines + 1] = line
	end
	return L["Fishing"], lines
end

local FISH_COLUMNS = { { "catches", "Catches" }, { "perCatch", "Per catch" }, { "perHour", "Per hour" } }

local function BuildFish(full)
	local fish = CreateFrame("Frame", nil, full)
	frame.fish = fish
	fish.card = CreateFrame("Frame", nil, fish)
	fish.card:SetPoint("TOPLEFT", fish, "TOPLEFT", FF.PAD, 0)
	fish.card:SetPoint("BOTTOMRIGHT", fish, "BOTTOMRIGHT", -FF.PAD, 0)
	Style.Sheet(fish.card, C.card, C.cardFlap, 14, false)
	local title = Style.Text(fish.card, "Label", "text2")
	title:SetPoint("TOPLEFT", fish.card, "TOPLEFT", 10, -8)
	title:SetText(L["Fishing"])
	fish.values = {}
	local colWidth = (FF.INNER - 20) / #FISH_COLUMNS
	for i, col in ipairs(FISH_COLUMNS) do
		local label = Style.Text(fish.card, "Caption", "text3")
		label:SetPoint("TOPLEFT", fish.card, "TOPLEFT", 10 + (i - 1) * colWidth, -23)
		label:SetText(L[col[2]])
		local value = Style.Text(fish.card, "Figure", "text")
		value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
		fish.values[col[1]] = value
	end
	fish.line = Style.Text(fish.card, "Caption", "text3")
	fish.line:SetPoint("TOPLEFT", fish.card, "TOPLEFT", 10, -53)
	fish.line:SetWidth(FF.INNER - 20)
	fish.line:SetJustifyH("LEFT")
	fish.line:SetWordWrap(true)
	fish.hover = Hover(fish, FishTip)
	fish.hover:SetAllPoints(fish.card)
end

local function LootTooltip(self)
	local r = self.data
	if not r then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(r.itemID)
	else
		GameTooltip:AddLine(FF.ItemName(r))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Looted this session"], tostring(r.n), 0.75, 0.75, 0.75, 1, 1, 1)
	if r.value then
		GameTooltip:AddDoubleLine(L["Value"], ns.FormatMoney(r.value), 0.75, 0.75, 0.75, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["Each"], ns.FormatMoney(r.unit) .. "  " .. (r.label or r.source or ""), 0.75, 0.75, 0.75, 1, 1, 1)
		if r.stale then
			GameTooltip:AddLine((L["AH price is %d days old."]):format(r.age), C.danger[1], C.danger[2], C.danger[3])
		end
		if r.cutUnverified then
			GameTooltip:AddLine(L["AH cut unverified at this house: value before the cut."], C.danger[1], C.danger[2], C.danger[3], true)
		end
	else
		GameTooltip:AddLine(L["No AH or vendor price known: not valued."], C.text2[1], C.text2[2], C.text2[3], true)
	end
	if r.noAuction then
		GameTooltip:AddLine(L["Bind on pickup or quest item: vendor only."], C.text2[1], C.text2[2], C.text2[3], true)
	end
	GameTooltip:Show()
end

-- A footer link: Caption text2, text on hover.
local function Link(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(FF.LOOT_ROW)
	b.text = Style.Text(b, "Caption", "text2")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text:SetText(text)
	b:SetWidth(math.floor((b.text:GetStringWidth() or 0) + 0.5))
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		self.text:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	end)
	b:SetScript("OnLeave", function(self)
		self.text:SetTextColor(C.text2[1], C.text2[2], C.text2[3], 1)
	end)
	ForwardDrag(b)
	return b
end

local function BuildLoot(full)
	local loot = CreateFrame("Frame", nil, full)
	frame.loot = loot
	local rule = Style.Rule(loot, "H", C.rule)
	rule:SetPoint("TOPLEFT", loot, "TOPLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", loot, "TOPRIGHT", 0, 0)
	loot.rows = {}
	for i = 1, FF.TOP_LOOT do
		local row = CreateFrame("Button", nil, loot)
		row:SetHeight(FF.LOOT_ROW)
		row:SetPoint("TOPLEFT", loot, "TOPLEFT", 0, -(i - 1) * FF.LOOT_ROW)
		row:SetPoint("TOPRIGHT", loot, "TOPRIGHT", 0, -(i - 1) * FF.LOOT_ROW)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icon:SetPoint("LEFT", row, "LEFT", FF.PAD, 0)
		row.value = Style.Text(row, "Figure", "text")
		row.value:SetPoint("RIGHT", row, "RIGHT", -FF.PAD, 0)
		row.value:SetWidth(62)
		row.value:SetJustifyH("RIGHT")
		row.count = Style.Text(row, "Figure", "text3")
		row.count:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
		row.count:SetWidth(30)
		row.count:SetJustifyH("RIGHT")
		row.name = Style.Text(row, "Small", "text")
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		local hair = Style.Rule(row, "H", C.rule)
		hair:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		hair:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
		row:SetScript("OnEnter", LootTooltip)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		ForwardDrag(row)
		loot.rows[i] = row
	end
	loot.nothing = Style.Text(loot, "Small", "text3")
	loot.nothing:SetPoint("LEFT", loot, "TOPLEFT", FF.PAD, -FF.LOOT_ROW / 2)
	loot.nothing:SetText(L["Nothing looted yet."])

	local footer = CreateFrame("Frame", nil, loot)
	footer:SetHeight(FF.LOOT_ROW)
	loot.footer = footer
	-- "+ 9 more": the open session's row on Gather › Farm, every item with × to remove it.
	loot.more = Link(footer, "", function()
		FF.OpenList()
	end)
	loot.more:SetPoint("LEFT", footer, "LEFT", FF.PAD, 0)
	loot.more.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3], 1)
	loot.more:SetScript("OnLeave", function(self)
		self.text:SetTextColor(C.text3[1], C.text3[2], C.text3[3], 1)
	end)
	loot.history = Link(footer, L["History"], function()
		FF.OpenHistory()
	end)
	loot.history:SetPoint("RIGHT", footer, "RIGHT", -FF.PAD, 0)
	loot.dot = Style.Text(footer, "Caption", "text3")
	loot.dot:SetPoint("RIGHT", loot.history, "LEFT", -4, 0)
	loot.dot:SetText("·")
	loot.log = Link(footer, L["Log"], function()
		FF.OpenLog()
	end)
	loot.log:SetPoint("RIGHT", loot.dot, "LEFT", -4, 0)
end

-- Buttons per state (spec): running Pause (line) + End session (action); paused Resume (primary) + End
-- session (line); no session Start (primary) + History (line).
local function BuildButtons(full)
	local bar = CreateFrame("Frame", nil, full)
	bar:SetHeight(FF.BUTTON_HEIGHT)
	frame.buttons = bar
	local h = FF.BUTTON_HEIGHT
	local b = {
		pause = Style.LineButton(bar, L["Pause"], nil, h),
		endAction = Style.ActionButton(bar, L["End session"], nil, h),
		resume = Style.PrimaryButton(bar, L["Resume"], nil, h),
		endLine = Style.LineButton(bar, L["End session"], nil, h),
		start = Style.PrimaryButton(bar, L["Start"], nil, h),
		history = Style.LineButton(bar, L["History"], nil, h),
	}
	bar.b = b
	b.pause:SetScript("OnClick", function()
		Farm.TogglePause()
	end)
	b.resume:SetScript("OnClick", function()
		Farm.TogglePause()
	end)
	b.start:SetScript("OnClick", function()
		Farm.Start()
	end)
	b.history:SetScript("OnClick", function()
		FF.OpenHistory()
	end)
	for _, key in ipairs({ "endAction", "endLine" }) do
		b[key]:SetScript("OnClick", function()
			Farm.Slash("reset")
		end)
		b[key]:HookScript("OnEnter", function(self)
			Style.ShowTip(self, L["End session"], L["Ends the session and keeps it in the history."])
		end)
		b[key]:HookScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
	end
	for _, button in pairs(b) do
		ForwardDrag(button)
		button:Hide()
	end
end

-- Shows the two buttons of the state: side by side, equal widths (running, paused), or at their own
-- width (no session).
local function ApplyButtons(names, equal)
	local b = frame.buttons.b
	for _, button in pairs(b) do
		button:Hide()
	end
	local x = FF.PAD
	local half = (FF.INNER - 8) / 2
	for _, name in ipairs(names) do
		local button = b[name]
		if equal then
			button:SetWidth(half)
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame.buttons, "TOPLEFT", x, 0)
		button:Show()
		x = x + (equal and half or (button:GetWidth() or button.cwWidth or 0)) + 8
	end
end

----------------------------------------------------------------------------------------------------
-- Build: the mini strip (#164)
----------------------------------------------------------------------------------------------------

local function BuildMini()
	local mini = CreateFrame("Button", nil, frame)
	mini:SetAllPoints(frame)
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.mini = mini
	-- Running: timer, gold per hour, "/ h". Paused: word ("Paused"), session total. No session: word.
	mini.timer = Style.Text(mini, "Figure", "text2")
	mini.timer:SetPoint("LEFT", mini, "LEFT", FF.MINI_PAD_LEFT, 0)
	mini.word = Style.Text(mini, "Small", "text2")
	Style.SmallBold(mini.word)
	mini.word:SetPoint("LEFT", mini, "LEFT", FF.MINI_PAD_LEFT, 0)
	mini.second = Style.Text(mini, "FigureBold", "text")
	mini.unit = Style.Text(mini, "Caption", "text3")
	mini.unit:SetPoint("LEFT", mini.second, "RIGHT", FF.MINI_GAP, 0)
	mini.unit:SetText(L["/ h"])
	ForwardDrag(mini)
	-- A drag ends with a mouse up over the strip; that is not a click.
	mini:SetScript("OnMouseDown", function(self)
		self.cwDragged = false
	end)
	mini:SetScript("OnDragStart", function(self)
		self.cwDragged = true
		StartDrag()
	end)
	mini:SetScript("OnClick", function(self, button)
		if self.cwDragged then
			self.cwDragged = false
			return
		end
		if button == "RightButton" then
			-- Pause or resume; without a session there is nothing to pause.
			if Farm.Current() then
				Farm.TogglePause()
			end
		else
			FF.SetMini(false)
		end
	end)
	mini:SetScript("OnEnter", function(self)
		Style.ShowTip(self, L["Farm"], L["Click: open the full tracker"], L["Right-click: pause / resume"],
			L["Drag: move (unless locked)"])
	end)
	mini:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	mini:Hide()
end

----------------------------------------------------------------------------------------------------
-- Fade (#163)
----------------------------------------------------------------------------------------------------

local fadeAlpha, fadeTarget = 1, 1

function FF.FadeEnabled()
	local s = Settings()
	return s ~= nil and s.fade == true
end

-- The mouse is over the tracker (or one of its children).
function FF.Hovered()
	if not frame then
		return false
	end
	return frame:IsMouseOver() and true or false
end

local function SetFadeAlpha(a)
	fadeAlpha = a
	frame:SetAlpha(a)
end

-- Moves the tracker's alpha to where the setting and the mouse say: 1 with the fade off or while hovered,
-- FF.FADE_ALPHA otherwise; over FF.FADE_TIME unless instant.
function FF.ApplyFade(instant)
	if not frame then
		return
	end
	local target = (FF.FadeEnabled() and not FF.Hovered()) and FF.FADE_ALPHA or 1
	if target == fadeTarget and not instant then
		return
	end
	fadeTarget = target
	if instant or fadeAlpha == target then
		-- Replaces a running fade (Style.Tween keeps one per owner and key) and sets the alpha now.
		Style.Tween(frame, "fade", 0.001, "linear", function()
			SetFadeAlpha(target)
		end)
		return
	end
	local from = fadeAlpha
	Style.Tween(frame, "fade", FF.FADE_TIME, "linear", function(p)
		SetFadeAlpha(from + (target - from) * p)
	end)
end

-- Settings: "Fade farm tracker to 40 % away from the mouse".
function FF.SetFade(on)
	local s = Settings()
	if s then
		s.fade = on and true or false
	end
	FF.ApplyFade()
end

function FF.Alpha()
	return fadeAlpha
end

----------------------------------------------------------------------------------------------------
-- Mini mode (#164)
----------------------------------------------------------------------------------------------------

function FF.IsMini()
	local s = Settings()
	return s ~= nil and s.mini == true
end

-- Shows the mode's content and corner; the next refresh sizes the frame.
local function ApplyMode()
	local mini = FF.IsMini()
	frame.full:SetShown(not mini)
	frame.mini:SetShown(mini)
	frame.cwSheet:SetCut(mini and FF.MINI_CUT or FF.CUT)
	if mini then
		frame:SetHeight(FF.MINI_HEIGHT)
	else
		frame:SetWidth(FF.WIDTH)
	end
end

-- The – button and Settings: mini (true) or the full tracker (false); remembered in CraftWiseDB.farm.mini.
function FF.SetMini(on)
	local s = Settings()
	if not s then
		return
	end
	s.mini = on and true or false
	if not frame then
		return
	end
	AnchorTopLeft()
	Style.HideTip()
	ApplyMode()
	FF.Refresh()
end

local function Build()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "CraftWiseFarmFrame", UIParent)
	frame:SetWidth(FF.WIDTH)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", StartDrag)
	frame:SetScript("OnDragStop", StopDrag)
	Style.Sheet(frame, C.sheet, C.flap, FF.CUT, true)
	-- The full tracker's content; mini mode (#164) swaps it for its strip.
	local full = CreateFrame("Frame", nil, frame)
	full:SetAllPoints(frame)
	frame.full = full
	BuildTop(full)
	BuildHero(full)
	BuildSplit(full)
	BuildFish(full)
	BuildLoot(full)
	BuildButtons(full)
	BuildMini()

	-- Fade (#163): the frame's own enter and leave, and a check every frame for its children.
	frame:SetScript("OnEnter", function()
		FF.ApplyFade()
	end)
	frame:SetScript("OnLeave", function()
		FF.ApplyFade()
	end)

	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		if FF.FadeEnabled() then
			FF.ApplyFade()
		end
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
	ApplyMode()
	return frame
end

----------------------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------------------

-- The state colour on the dog-ear (shared with mini mode, #164).
function FF.ApplyFlap(color)
	if frame and frame.cwSheet then
		frame.cwSheet:SetFlap(Style.Color(color))
	end
end

local function SetColor(fs, color)
	local c = Style.Color(color)
	fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function RefreshSplit(m)
	local split = frame.split
	local values = { m.split.coin, m.split.ah, m.split.vendor }
	local geo = FF.SplitGeometry({ math.max(values[1], 0), math.max(values[2], 0), math.max(values[3], 0) }, FF.INNER)
	for i, g in ipairs(geo) do
		local bar = split.bars[i]
		if g.w > 0 then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", split, "TOPLEFT", FF.PAD + g.x, 0)
			bar:SetWidth(g.w)
			bar:Show()
		else
			bar:Hide()
		end
		split.figures[i]:SetText(FF.Coins(values[i]))
	end
	SetColor(split.labels[2], m.split.stale > 0 and "danger" or "text3")
end

local function RefreshFish(f)
	local fish = frame.fish
	if not f then
		fish:Hide()
		return
	end
	fish:Show()
	fish.values.catches:SetText(tostring(f.catches))
	fish.values.perCatch:SetText(FF.Coins(f.perCatch))
	fish.values.perHour:SetText(f.cph and tostring(math.floor(f.cph + 0.5)) or Paint("—", "text3"))
	local parts = {}
	if f.best then
		parts[1] = L["Best catch"] .. ": " .. Paint(FF.ItemName(f.best), FF.ItemColor(f.best.itemID))
	end
	parts[#parts + 1] = FF.RateText(ns.Fishing.CatchRate and ns.Fishing.CatchRate())
	fish.line:SetText(table.concat(parts, " · "))
	fish.cwHeight = 53 + Height(fish.line, 12) + 8
	fish:SetHeight(fish.cwHeight)
end

local function RefreshLoot(m)
	local loot = frame.loot
	for i, row in ipairs(loot.rows) do
		local r = m.loot[i]
		row.data = r
		if r then
			local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.itemID)
			row.icon:SetTexture(icon or QUESTION_ICON)
			row.name:SetText(FF.ItemName(r))
			SetColor(row.name, FF.ItemColor(r.itemID))
			row.count:SetText("×" .. r.n)
			row.value:SetText(r.value and FF.Coins(r.value) or Paint(L["no price"], "text3"))
			row:Show()
		else
			row:Hide()
		end
	end
	loot.nothing:SetShown(#m.loot == 0)
	loot.more.text:SetText(FF.FooterText(m))
	loot.more:SetWidth(math.floor((loot.more.text:GetStringWidth() or 0) + 0.5))
	loot.more:SetShown(m.more > 0 or m.unpriced > 0)
	loot.footer:ClearAllPoints()
	local rows = math.max(#m.loot, 1)
	loot.footer:SetPoint("TOPLEFT", loot, "TOPLEFT", 0, -rows * FF.LOOT_ROW)
	loot.footer:SetPoint("TOPRIGHT", loot, "TOPRIGHT", 0, -rows * FF.LOOT_ROW)
	loot.cwHeight = (rows + 1) * FF.LOOT_ROW
	loot:SetHeight(loot.cwHeight)
end

-- Stacks the shown sections from the top line down and sizes the tracker to them.
function FF.Layout()
	local y = -30
	local function stack(section, gap, height)
		if not section:IsShown() then
			return
		end
		y = y - gap
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", frame.full, "TOPLEFT", 0, y)
		section:SetPoint("TOPRIGHT", frame.full, "TOPRIGHT", 0, y)
		if height then
			section:SetHeight(height)
		end
		y = y - (height or section.cwHeight or 0)
	end
	local none = last and last.state == "none"
	stack(frame.empty, 18, 16 + (frame.empty.hint:IsShown() and (4 + Height(frame.empty.hint, 24)) or 0))
	stack(frame.hero, 8, 56)
	stack(frame.split, 12, FF.SPLIT_HEIGHT + 6 + 12 + 14)
	stack(frame.fish, 12, nil)
	stack(frame.loot, 12, nil)
	stack(frame.buttons, none and 18 or 10, FF.BUTTON_HEIGHT)
	frame:SetHeight(math.floor(-y + 14 + 0.5))
end

-- The mini strip: running timer, gold per hour, "/ h"; paused "Paused" and the session total; no session
-- the state word alone. Its width follows the text.
local function RefreshMini(m)
	local mini = frame.mini
	local running, none = m.state == "running", m.state == "none"
	mini.timer:SetShown(running)
	mini.word:SetShown(not running)
	mini.second:SetShown(not none)
	mini.unit:SetShown(running)
	local first = running and mini.timer or mini.word
	if running then
		mini.timer:SetText(m.timer)
		mini.second:SetText(FF.Coins(m.hero))
	elseif none then
		mini.word:SetText(m.word)
		SetColor(mini.word, "text3")
	else
		mini.word:SetText(L["Paused"])
		SetColor(mini.word, "text2")
		mini.second:SetText(FF.Coins(m.totals.total))
	end
	mini.second:ClearAllPoints()
	mini.second:SetPoint("LEFT", first, "RIGHT", FF.MINI_GAP, 0)
	local function width(fs)
		return math.ceil(fs:GetStringWidth() or 0)
	end
	local w = FF.MINI_PAD_LEFT + width(first) + FF.MINI_PAD_RIGHT
	if not none then
		w = w + FF.MINI_GAP + width(mini.second)
	end
	if mini.unit:IsShown() then
		w = w + FF.MINI_GAP + width(mini.unit)
	end
	frame:SetWidth(w)
	frame:SetHeight(FF.MINI_HEIGHT)
end

function FF.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local s = Farm.Current()
	local m = FF.Model(s, Farm.Now())
	last = m
	FF.ApplyFlap(m.flap)
	if FF.IsMini() then
		RefreshMini(m)
		return
	end
	frame.word:SetText(m.word)
	SetColor(frame.word, m.wordColor)
	frame.timer:SetText(m.timer or "")
	if m.timerColor then
		SetColor(frame.timer, m.timerColor)
	end
	local none = m.state == "none"
	frame.empty:SetShown(none)
	frame.hero:SetShown(not none)
	frame.split:SetShown(not none)
	frame.loot:SetShown(not none)
	if none then
		frame.empty.title:SetText(m.title)
		frame.empty.hint:SetText(m.hint or "")
		frame.empty.hint:SetShown(m.hint ~= nil)
		RefreshFish(nil)
	else
		frame.hero.value:SetText(FF.Coins(m.hero))
		frame.hero.caption:SetText(m.caption)
		RefreshSplit(m)
		RefreshFish(m.fish)
		RefreshLoot(m)
	end
	ApplyButtons(m.buttons, not none)
	FF.Layout()
end

----------------------------------------------------------------------------------------------------
-- Opening and the links (to Gather › Farm, #156)
----------------------------------------------------------------------------------------------------

-- Log link: the open session's row on Gather › Farm with its loot log, newest first.
function FF.OpenLog()
	if ns.OpenFarmPage then
		return ns.OpenFarmPage(ns.FarmHistory.CURRENT, true)
	end
end

-- "+ N more": the open session's row with every looted item; × removes one from the session.
function FF.OpenList()
	if ns.OpenFarmPage then
		return ns.OpenFarmPage(ns.FarmHistory.CURRENT)
	end
end

-- History link and the no-session History button: Gather › Farm, the finished sessions.
function FF.OpenHistory()
	if ns.OpenFarmPage then
		return ns.OpenFarmPage()
	end
end

function FF.LootRows()
	return frame and frame.loot.rows
end

function FF.FishCard()
	return frame and frame.fish
end

function FF.Last()
	return last
end

-- The tracker frame.
function FF.Window()
	return frame
end

function FF.Show()
	Build()
	frame:Show()
	FF.Refresh()
	FF.ApplyFade(true)
end

-- The mini strip, for the specs.
function FF.Mini()
	return frame and frame.mini
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
