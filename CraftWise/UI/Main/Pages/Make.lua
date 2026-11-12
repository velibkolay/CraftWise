-- Main window, section Make (#154; spec in #150 "Make: Craft, Learn, Level up", board "Window layout"):
-- what the three pages share. The pages themselves are Craft.lua, Learn.lua and LevelUp.lua; the recipe
-- and skill-up tooltips are MakeTooltips.lua. Shared through ns.Main.Make (MK).
--   - the profession dropdown and the filter box in the sub bar (one choice, one query for all three)
--   - the rows: the existing models (ns.BuildRows, ns.LevelingRows) behind the filter box and the chips;
--     only their drawing is new
--   - row data kept apart from row drawing (below), so the docked layout (#161) can draw the same rows
--   - the opened row's reagents and Price history
--
-- Row data. A page's Model returns the model's rows as they are, each with `view` added: everything a
-- layout draws and nothing about frames.
--   view.name, view.nameColor (a Style colour name), view.icon, view.itemID
--   view.rail = { value, zeroAt } or nil       on the list's shared scale ctx.railMax
--   view.result, view.resultColor              the right-hand figure
--   view.sub                                   the sub-figure (under the result in the docked layout)
--   view.cells[key], view.colors[key], view.tips[key]   the window layout's columns (MK.Column)
-- The window layout draws view.cells by column; the docked layout draws name over rail, result right
-- with view.sub under it.
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local MK = {}
M.Make = MK

MK.state = { query = "" } -- the filter box: one query for the three pages, this session

----------------------------------------------------------------------------------------------------
-- Small helpers (pure)
----------------------------------------------------------------------------------------------------

function MK.ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

-- Coin digits without colours ("1g 50s"): captions in C.text3.
function MK.PlainMoney(copper)
	local s = ns.FormatCoins(copper)
	if not s then
		return nil
	end
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- "+1g 20s" in coin colours, "−45s" in C.danger: text and colour name.
function MK.Signed(copper)
	if copper == nil then
		return M.DASH, "text3"
	elseif copper < 0 then
		return "−" .. MK.PlainMoney(-copper), "danger"
	end
	return "+" .. ns.FormatCoins(copper), "text"
end

-- Short tag for where a sale price comes from (#48): "vendor", "AH", or "AH gross" when the house's
-- cut is unverified (no net value); nil without a sale value.
function MK.SaleTag(source, cutUnverified)
	if source == "vendor" then
		return "vendor"
	elseif source == "auction" then
		return cutUnverified and "AH gross" or "AH"
	end
	return nil
end

-- "typical · Horde AH": what auction prices are based on (#26 phase 2).
function MK.PriceBasisText()
	local basis = ns.PriceSettings()
	local _, label = ns.ProfitHouse()
	return ns.BASIS_TEXT[basis] .. " · " .. (label or "own faction AH")
		.. (ns.HasAuctionator() and (", else " .. ns.AUCTIONATOR_LABEL) or "")
end

-- "reagents: AH" / "reagents: paid cost, else AH": a page's reagent cost basis (#47).
function MK.CostBasisText(view)
	if ns.CostBasis(view) == "paid" then
		return "reagents: paid cost, else AH"
	end
	return "reagents: AH"
end

-- With the paid basis: how many rows fell back to AH prices for a reagent.
function MK.BasisNote(view, rows)
	local text = MK.CostBasisText(view)
	if ns.CostBasis(view) == "paid" then
		local fallback = 0
		for _, r in ipairs(rows or {}) do
			if r.paidFallbacks then
				fallback = fallback + 1
			end
		end
		if fallback > 0 then
			text = text .. (" (%d %s with reagents at AH)"):format(fallback, fallback == 1 and "row" or "rows")
		end
	end
	return text
end

local SKILL_WORDS = { orange = "Orange", yellow = "Yellow", green = "Green", grey = "Grey" }

-- "Yellow" in its skill colour (the profession window's), nil for unlearned recipes.
function MK.ColorWord(color)
	if not SKILL_WORDS[color] then
		return nil
	end
	return Style.Hex("skill." .. color) .. L[SKILL_WORDS[color]] .. "|r"
end

-- A recipe name's colour: its skill-up colour; white when not learned yet.
function MK.NameColor(r)
	if SKILL_WORDS[r.skillColor] then
		return "skill." .. r.skillColor
	end
	return "text"
end

-- "58%" (measured, white) or "~41%" (the community formula, grey): text, colour name.
function MK.ChanceText(p, kind)
	if not p or p <= 0 then
		return nil
	end
	local pct = math.floor(p * 100 + 0.5) .. "%"
	if kind == "formula" then
		return "~" .. pct, "text2"
	end
	return pct, "text"
end

-- "No known recipe has a price yet." from a hero model's reason.
function MK.Sentence(reason)
	reason = tostring(reason or "")
	return (reason:gsub("^%l", string.upper)) .. (reason:match("[%.!?]$") and "" or ".")
end

-- A hero card without an answer: the page's label, a dash and the reason.
function MK.NoHero(label, reason)
	return { label = label, name = M.DASH, nameColor = "text3", sub = MK.Sentence(reason) }
end

-- "by profit": how the list is sorted, for the list bar.
function MK.SortNote(page, notes)
	local key = M.Sort(page)
	return notes[key] or ""
end

-- A window-layout column that draws view.cells[key] in view.colors[key], with view.tips[key] on hover.
function MK.Column(key, label, width, align, font, sort)
	return {
		key = key, label = label, width = width, align = align, font = font, sort = sort,
		text = function(r)
			return r.view and r.view.cells[key] or ""
		end,
		color = function(r)
			return r.view and r.view.colors[key] or "text"
		end,
		tip = function(r)
			return r.view and r.view.tips[key]
		end,
	}
end

-- A fresh view for a row: name, colour, icon and empty cells.
function MK.NewView(r, itemID)
	local icon = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or r.icon
	return {
		name = r.name or ("Recipe #" .. tostring(r.recipeID)),
		nameColor = MK.NameColor(r),
		icon = icon,
		itemID = itemID,
		cells = {}, colors = {}, tips = {},
	}
end

-- Adds the view to the row and the fields the shell's list reads (key, name, icon, itemID).
function MK.Attach(r, view)
	r.view = view
	r.key = r.recipeID
	r.icon = view.icon
	r.itemID = view.itemID
	view.cells.name, view.colors.name = view.name, view.nameColor
	return r
end

----------------------------------------------------------------------------------------------------
-- Rows: the existing models behind the filter box and the chips
----------------------------------------------------------------------------------------------------

-- The filter matches recipe names and reagent names ("which recipes use Light Leather").
function MK.Matches(r, query)
	if query == "" then
		return true
	end
	if (r.name or ""):lower():find(query, 1, true) then
		return true
	end
	for _, line in ipairs(r.reagents or {}) do
		if MK.ItemName(line.itemID):lower():find(query, 1, true) then
			return true
		end
	end
	return false
end

local function Query(query)
	return (query or MK.state.query or ""):lower()
end

-- Craft: known recipes (and unlearned ones with the Unlearned chip). Returns rows, hidden (by Hide unpriced).
function MK.CraftRows(professionID, settings, query)
	if not professionID then
		return {}, 0
	end
	local s = settings or ns.db.settings
	query = Query(query)
	local out, hidden = {}, 0
	for _, r in ipairs(ns.BuildRows(professionID, s.includeUnlearned, "profit")) do
		if MK.Matches(r, query) then
			if s.hideUnpriced and not r.profit then
				hidden = hidden + 1
			else
				out[#out + 1] = r
			end
		end
	end
	return out, hidden
end

-- Learn: every recipe not known yet, with where to get it. Returns rows, hidden (by the chips), all
-- (unfiltered, for the hero card).
function MK.LearnRows(professionID, settings, query)
	if not professionID then
		return {}, 0, {}
	end
	local s = settings or ns.db.settings
	query = Query(query)
	local all = ns.BuildRows(professionID, true, "learn")
	local out, hidden = {}, 0
	for _, r in ipairs(all) do
		if r.status ~= "known" and MK.Matches(r, query) then
			if s.learnFitsSkill and (not r.required or r.tooLow) then
				hidden = hidden + 1 -- fits your skill only when the requirement is known and met
			elseif s.hideUnpriced and not r.profit then
				hidden = hidden + 1
			else
				r.where = ns.RecipeWhere(r.recipeID)
				r.whereText = r.where[1] and r.where[1].text or nil
				r.whereLabel = r.where[1] and r.where[1].origin == "seen" and r.where[1].label or nil
				out[#out + 1] = r
			end
		end
	end
	return out, hidden, all
end

-- Level up: known recipes that still give skill (grey ones are left out). Returns rows, skill, all.
function MK.LevelRows(professionID, query)
	if not professionID then
		return {}, nil, {}
	end
	query = Query(query)
	local all, skill = ns.LevelingRows(professionID)
	local out = {}
	for _, r in ipairs(all) do
		if MK.Matches(r, query) then
			out[#out + 1] = r
		end
	end
	return out, skill, all
end

----------------------------------------------------------------------------------------------------
-- Why a row has no profit (the Unknown price state's hover: the reason, never a guess)
----------------------------------------------------------------------------------------------------

function MK.WhyNoPrice(r, ctx)
	local house = ctx and ctx.prices and ctx.prices.label or L["the profit house"]
	if r.noItemOutput then
		return { L["Makes no item"], L["Recipes without an item have no sale price."] }
	end
	if not r.costComplete then
		local names = {}
		for _, id in ipairs(r.missing or {}) do
			names[#names + 1] = MK.ItemName(id)
		end
		return { L["A reagent has no price"], (L["No AH price at %s and no vendor price: %s."]):format(house,
			#names > 0 and table.concat(names, ", ") or "?") }
	end
	if r.cutUnverified then
		return { (L["AH cut not verified at %s"]):format(house),
			L["No profit until the cut is measured; it is never assumed."] }
	end
	if not (r.sellsFor or r.saleValue) then
		return { L["No sale price"], (L["No AH price at %s and vendors don't buy it."]):format(house) }
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Profession dropdown (chip "Leatherworking 191 ▾") and filter box, in each Make page's sub bar tools
----------------------------------------------------------------------------------------------------

local MENU_WIDTH, MENU_ROW, MENU_PAD = 200, 24, 8
local menu

local function ProfessionLabel(id, prof)
	if not prof then
		return L["No profession yet"]
	end
	local skill = ns.ProfessionSkill and ns.ProfessionSkill(id) or prof.skill
	return (prof.name or "?") .. (skill and (" " .. Style.Hex("text2") .. skill .. "|r") or "")
end
MK.ProfessionLabel = ProfessionLabel

local function BuildMenu()
	menu = CreateFrame("Frame", "CraftWiseProfessionMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetWidth(MENU_WIDTH)
	menu:EnableMouse(true)
	menu:SetClampedToScreen(true)
	menu.sheet = Style.Sheet(menu, C.sheet, C.flap, 10, true)
	table.insert(UISpecialFrames, "CraftWiseProfessionMenu")
	menu.nokta = Style.Nokta(menu)
	menu.nokta:Hide()
	menu.buttons = {}
	menu:Hide()
end

local function MenuButton(i)
	local b = menu.buttons[i]
	if not b then
		b = CreateFrame("Button", nil, menu)
		b:SetHeight(MENU_ROW)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints(b)
		Style.Fill(b.bg, C.selected)
		b.label = Style.Text(b, "Body", "text")
		b.label:SetPoint("LEFT", b, "LEFT", 28, 0)
		b:SetScript("OnClick", function(self)
			menu:Hide()
			M.SetProfession(self.id)
		end)
		b:SetScript("OnEnter", function(self)
			self.bg:Show()
		end)
		b:SetScript("OnLeave", function(self)
			self.bg:SetShown(self.current and true or false)
		end)
		menu.buttons[i] = b
	end
	return b
end

-- The professions to choose from, under the chip; the current one has the nokta.
function MK.ShowProfessionMenu(anchor)
	if not menu then
		BuildMenu()
	end
	local ids = M.ProfessionIDs()
	local current = M.Profession()
	local profs = ns.charDB and ns.charDB.professions or {}
	for i, id in ipairs(ids) do
		local b = MenuButton(i)
		b.id = id
		b.current = id == current
		b.label:SetText(ProfessionLabel(id, profs[id]))
		b.label:SetFontObject(b.current and Style.Fonts.BodyBold or Style.Fonts.Body)
		b.bg:SetShown(b.current)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -(MENU_PAD + (i - 1) * MENU_ROW))
		b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -(MENU_PAD + (i - 1) * MENU_ROW))
		b:Show()
		if b.current then
			menu.nokta:MoveTo(b, "LEFT", 14, 0, true)
		end
	end
	for i = #ids + 1, #menu.buttons do
		menu.buttons[i]:Hide()
	end
	menu:SetHeight(2 * MENU_PAD + math.max(#ids, 1) * MENU_ROW)
	menu.anchor = anchor
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	menu:Show()
	return menu
end

function MK.Menu()
	return menu
end

ns.On("GLOBAL_MOUSE_DOWN", function()
	if menu and menu:IsShown() and not menu:IsMouseOver() and not (menu.anchor and menu.anchor:IsMouseOver()) then
		menu:Hide()
	end
end)

MK.FILTER_WIDTH, MK.TOOL_GAP = 160, 18

-- The query changes: every Make page shows it.
function MK.SetQuery(text)
	text = text or ""
	if text == MK.state.query then
		return
	end
	MK.state.query = text
	M.Refresh()
end

-- Tools(slot, ctx) of a Make page: the profession chip and the filter box, right aligned (board).
function MK.BuildTools(slot)
	local box = CreateFrame("EditBox", nil, slot)
	slot.filter = box
	box:SetSize(MK.FILTER_WIDTH, 24)
	box:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
	box:SetAutoFocus(false)
	box:SetFontObject(Style.Fonts.Small)
	box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	box:SetTextInsets(8, 8, 0, 0)
	box.border = Style.Border(box, C.ruleStrong)
	box.hint = Style.Text(box, "Small", "text3")
	box.hint:SetPoint("LEFT", box, "LEFT", 8, 0)
	box.hint:SetText(L["Filter recipes"])
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "")
		if not self.cwSetting then
			MK.SetQuery(text)
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.border:SetColor(C.text)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.border:SetColor(C.ruleStrong)
	end)

	local chip = Style.Chip(slot, "")
	slot.profession = chip
	chip.label:SetFontObject(Style.Fonts.Body)
	chip:SetPoint("RIGHT", box, "LEFT", -MK.TOOL_GAP, 0)
	chip:SetScript("OnClick", function(self)
		if menu and menu:IsShown() then
			menu:Hide()
		else
			MK.ShowProfessionMenu(self)
		end
	end)
	chip:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Profession"], L["Choose which profession Craft, Learn and Level up show."])
	end)
	chip:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
end

function MK.UpdateTools(slot, ctx)
	local chip, box = slot.profession, slot.filter
	chip:SetLabel(ProfessionLabel(ctx.professionID, ctx.prof) .. " " .. Style.Glyph("down", 9, "text2"))
	chip.label:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	if (box:GetText() or "") ~= MK.state.query then
		box.cwSetting = true
		box:SetText(MK.state.query)
		box.cwSetting = false
	end
	box.hint:SetShown(MK.state.query == "")
end

-- A chip bound to a boolean setting (Unlearned, Hide unpriced, Fits my skill).
function MK.SettingChip(slot, label, key, tip)
	local chip = Style.Chip(slot, label)
	chip.settingKey = key
	chip:SetScript("OnClick", function(self)
		local s = ns.db.settings
		s[key] = not s[key]
		self:SetOn(s[key])
		M.Refresh()
	end)
	if tip then
		chip:HookScript("OnEnter", function(self)
			Style.ShowTip(self, label, tip)
		end)
		chip:HookScript("OnLeave", function(self)
			Style.HideTip(self)
		end)
	end
	return chip
end

-- Lays chips out from the right of the list bar, 8 apart; marks each on or off from the settings.
function MK.LayoutChips(slot, chips)
	local right = nil
	for i = #chips, 1, -1 do
		local chip = chips[i]
		chip:ClearAllPoints()
		if right then
			chip:SetPoint("RIGHT", right, "LEFT", -8, 0)
		else
			chip:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
		end
		right = chip
	end
end

function MK.UpdateChips(chips)
	local s = ns.db.settings
	for _, chip in ipairs(chips) do
		chip:SetOn(s[chip.settingKey] and true or false)
	end
end

----------------------------------------------------------------------------------------------------
-- Rails and the Scanning state in rows
----------------------------------------------------------------------------------------------------

-- Where column `index` sits in a row of the current layout.
function MK.ColumnAt(columns, index, ctx)
	local m = ctx.metrics or M.WINDOW_METRICS
	return M.ColumnLayout(columns, m.width or 880, m.pad or 22)[index]
end

-- While a scan runs, a figure that is still missing is a skeleton bar in its column (spec "Scanning").
function MK.DrawSkeleton(b, cellIndex, pos, missing, ctx)
	local scanning = ctx.prices and ctx.prices.scanning and missing
	if scanning and not b.cwSkeleton then
		b.cwSkeleton = M.Skeleton(b, 50, 8)
	end
	if b.cwSkeleton then
		b.cwSkeleton:ClearAllPoints()
		b.cwSkeleton:SetPoint("RIGHT", b, "LEFT", pos.x + pos.width, 0)
		b.cwSkeleton:SetShown(scanning and true or false)
	end
	local cell = b.cells and b.cells[cellIndex]
	if cell and scanning then
		cell:SetText("")
	end
	return scanning and true or false
end

-- " 3 d" in C.danger after an AH figure while prices are stale (spec "Stale").
function MK.StaleAge(ctx)
	local p = ctx and ctx.prices
	if p and p.stale and not p.scanning then
		return " " .. Style.Hex("danger") .. M.ShortAge(p.age) .. "|r"
	end
	return ""
end

----------------------------------------------------------------------------------------------------
-- Opened row: each reagent (quantity, name, total, source and "have N"), Price history (board "Window
-- layout"). Learn adds where to get the recipe above it.
----------------------------------------------------------------------------------------------------

MK.REAGENT_WIDTH, MK.REAGENT_GAP, MK.REAGENT_HEIGHT, MK.REAGENTS_PER_LINE = 130, 20, 44, 4
MK.WHERE_LINE = 15

local SOURCE_TEXT = { vendor = "vendor", auction = "AH", paid = "paid", crafted = "crafted" }

-- One reagent line of the opened row (pure): quantity, name, total (coins), note ("AH · have 6").
function MK.ReagentLine(line, counter)
	local have = counter and counter(line.itemID) or 0
	local note = line.total and (SOURCE_TEXT[line.source] or line.source or "") or ""
	if have > 0 then
		note = note .. (note ~= "" and " · " or "") .. (L["have %d"]):format(have)
	end
	return {
		itemID = line.itemID,
		head = Style.Hex("text") .. line.quantity .. "|r " .. MK.ItemName(line.itemID),
		total = line.total and ns.FormatCoins(line.total) or nil,
		note = note,
		have = have,
	}
end

function MK.ReagentLines(r, counter)
	counter = counter or (ns.Holdings and ns.Holdings.Counter())
	local out = {}
	for i, line in ipairs(r.reagents or {}) do
		out[i] = MK.ReagentLine(line, counter)
	end
	return out
end

local function Lines(n)
	return math.max(1, math.ceil(n / MK.REAGENTS_PER_LINE))
end

-- Height of the opened part: where lines (Learn) and the reagent lines.
function MK.OpenHeight(r, whereLines)
	return (whereLines or 0) * MK.WHERE_LINE + ((whereLines or 0) > 0 and 6 or 0)
		+ Lines(#(r.reagents or {})) * MK.REAGENT_HEIGHT - 8
end

-- Draws the opened part of a recipe row into the list's content frame (reused between rows; the shell's
-- M.Pool hands the widgets out again). opts.where = { { text, label } } lines above the reagents (Learn).
-- Each reagent has a hit area: hover shows the item, right-click its menu, Shift-click links it.
function MK.DrawOpen(content, r, opts)
	opts = opts or {}
	local pool = M.Pool(content)
	pool:Reset()
	local y = 0
	for _, w in ipairs(opts.where or {}) do
		local fs = pool:Text("Small", "text2", w.text .. (w.label and (" " .. Style.Hex("text3") .. "[" .. w.label .. "]|r") or ""))
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		y = y + MK.WHERE_LINE
	end
	if #(opts.where or {}) > 0 then
		y = y + 6
	end
	content.reagentLines = MK.ReagentLines(r, opts.counter)
	content.reagentCells = {}
	if #content.reagentLines == 0 then
		local fs = pool:Text("Small", "text3", L["Reagents unknown - open this profession again."])
		fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	end
	for i, line in ipairs(content.reagentLines) do
		local col, row = (i - 1) % MK.REAGENTS_PER_LINE, math.floor((i - 1) / MK.REAGENTS_PER_LINE)
		local x, top = col * (MK.REAGENT_WIDTH + MK.REAGENT_GAP), -(y + row * MK.REAGENT_HEIGHT)
		local head = pool:Text("Small", "text", line.head)
		head:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
		head:SetWidth(MK.REAGENT_WIDTH)
		local total = pool:Text("Figure", "text", line.total or M.NoPriceText())
		total:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
		local note = pool:Text("Caption", "text2", line.note)
		note:SetPoint("TOPLEFT", total, "BOTTOMLEFT", 0, -1)
		local hit = pool:Hit({ itemID = line.itemID })
		hit:SetPoint("TOPLEFT", content, "TOPLEFT", x, top)
		hit:SetSize(MK.REAGENT_WIDTH, MK.REAGENT_HEIGHT - 8)
		content.reagentCells[i] = { head = head, total = total, note = note, hit = hit, x = x, y = top }
	end
	-- Price history of the crafted item: Look up › Items once #157 lands, else Records › Market.
	local itemID = r.outputItemID
	local h = pool:Button(L["Price history"], function()
		ns.OpenItemLookup(itemID, "history")
	end, { L["Price history"], L["Auction house prices recorded for the crafted item."] }, 26)
	h:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + (MK.REAGENT_HEIGHT - 8 - 26) / 2))
	h:SetShown(itemID ~= nil)
	content.history = h
end

----------------------------------------------------------------------------------------------------
-- Refreshes the Make pages need beyond the shell's own (RECIPES, PROFESSIONS, PRICES)
----------------------------------------------------------------------------------------------------

local function RefreshMake()
	local page = M.CurrentPage()
	if page and page.section == "make" then
		M.Refresh()
	end
end
MK.RefreshMake = RefreshMake

ns.On("AUCTION_HOUSE_CLOSED", RefreshMake) -- Auctionator prices may have changed during a scan
ns.On("SKILL_LINES_CHANGED", RefreshMake) -- the skill in the profession chip and the chances
