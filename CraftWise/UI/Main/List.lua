-- Main window: the list of a page (spec "Main window shell", List row and "Mouse and keys"). One list per
-- page, made when the page first shows: a header row 24 tall with a 2 unit C.text rule, sortable headers
-- (▾ on the active one; click to sort, again to reverse), and a ScrollBox (mouse wheel, 4 unit thumb in
-- C.ruleStrong, no arrows) of rows with 1 unit C.rule hairlines. A click opens a row in place (one at a
-- time, the nokta moves to it; again closes it); right- or middle-click on an item row opens the item
-- menu; Shift-click puts the item link into chat; hovering an item shows its GameTooltip with the
-- CraftWise lines, any other row (or a column's own tip) the inverse tooltip.
-- Docked (#161): the same list draws two-line rows 44 tall (spec, board "Docked layout"): icon, the name
-- over its rail (or a note line), the result right with the sub-figure under it. What a row shows comes
-- from M.DockedView: the page's DockedRow(row, ctx), else the Make pages' row.view, else its columns.
local _, ns = ...
local M = ns.Main
local Style = ns.Style
local C = Style.C

local ICON = 22
local OPEN_MARGIN = { left = 56, right = 22, bottom = 8 } -- board "Window layout": the opened row's card
-- (the layout's metrics give left and right: openLeft, openRight; docked 18 and 18)
local OPEN_PAD_X, OPEN_PAD_Y = 14, 10

local List = {}

local function ShowRowTip(list, owner, data)
	if list.page.RowTooltip then
		local ok, err = M.Call(list.page.RowTooltip, owner, data, list.ctx)
		if not ok and list.onError then
			list.onError(err)
		end
	elseif data.itemID and GameTooltip and GameTooltip.SetItemByID then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.itemID)
		GameTooltip:Show()
	elseif data.tip then
		Style.ShowTip(owner, unpack(data.tip))
	end
end

local function HideTips(owner)
	if GameTooltip then
		GameTooltip:Hide()
	end
	Style.HideTip(owner)
end

-- Shift-click: the item's link into the chat box. ChatFrameUtil.InsertLink is what Blizzard's Forever UI
-- calls for a chat link (Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua, HandleModifiedItemClick);
-- ChatEdit_InsertLink is only its deprecation fallback.
function M.LinkToChat(itemID)
	local _, link = ns.ItemInfoNow(itemID)
	if link and ChatFrameUtil and ChatFrameUtil.InsertLink then
		return ChatFrameUtil.InsertLink(link) and true or false
	end
	return false
end

-- A click on a row (or on a cell with its own tip). Returns what it did, for the specs.
function List:Click(rowFrame, mouse)
	local element = rowFrame.element
	local data = element and element.row
	if not data then
		return nil
	end
	if mouse == "LeftButton" and IsShiftKeyDown() and data.itemID then
		M.LinkToChat(data.itemID)
		return "link"
	end
	if (mouse == "RightButton" or mouse == "MiddleButton") and data.itemID then
		HideTips(rowFrame)
		if ns.ShowItemMenu then
			ns.ShowItemMenu(data.itemID, rowFrame)
		end
		return "menu"
	end
	if mouse == "LeftButton" then
		if self.page.Open then
			self:Toggle(data)
			return "toggle"
		elseif self.page.OnClick then
			self.page.OnClick(data, self.ctx)
			return "click"
		end
	end
	return nil
end

-- Opens a row in place, or closes it when it is the open one.
function List:Toggle(data)
	local key = M.RowKey(data)
	if self.openKey == key then
		self.openKey = nil
	else
		self.openKey, self.justOpened = key, key
	end
	self:Render()
end

local function BuildRow(list, b)
	b.cw = true
	b.cwOwnTooltip = list.page.RowTooltip ~= nil -- Tooltip.lua: no second CraftWise section
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	Style.Fill(b.bg, C.selected)
	b.hair = Style.Rule(b, "H", C.rule, "BORDER")
	b.hair:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.hair:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.nokta = Style.Nokta(b)
	b.nokta:Hide()
	b.cells, b.icons, b.hits, b.rails = {}, {}, {}, {}
	b.cwList = list
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	b:SetScript("OnClick", function(self, mouse)
		list:Click(self, mouse)
	end)
	b:SetScript("OnEnter", function(self)
		if self.element then
			ShowRowTip(list, self, self.element.row)
		end
	end)
	b:SetScript("OnLeave", function(self)
		HideTips(self)
	end)
end

-- A column's own tip (e.g. why a price is unknown): a hit area over the cell; clicks go to the row.
local function Hit(list, b, i)
	local hit = b.hits[i]
	if not hit then
		hit = CreateFrame("Button", nil, b)
		hit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
		hit:SetScript("OnClick", function(_, mouse)
			list:Click(b, mouse)
		end)
		hit:SetScript("OnEnter", function(self)
			local data = b.element and b.element.row
			local col = self.col
			local tip = data and col and col.tip and col.tip(data)
			if tip then
				Style.ShowTip(self, unpack(tip))
			elseif data then
				ShowRowTip(list, self, data)
			end
		end)
		hit:SetScript("OnLeave", function(self)
			HideTips(self)
		end)
		b.hits[i] = hit
	end
	return hit
end

local function CellText(col, data)
	if col.text then
		return col.text(data)
	end
	local v = data.cells and data.cells[col.key]
	if v == nil then
		v = data[col.key]
	end
	return v ~= nil and tostring(v) or ""
end

function List:InitRow(b, element)
	if not b.cw then
		BuildRow(self, b)
	end
	b.element = element
	if self.docked then
		return self:InitDockedRow(b, element)
	end
	local data = element.row
	local open = self.openKey ~= nil and self.openKey == M.RowKey(data)
	b.bg:SetShown(open)
	if open then
		b.nokta:MoveTo(b, "LEFT", 11, 0, self.justOpened ~= M.RowKey(data))
		if self.justOpened == M.RowKey(data) then
			self.justOpened = nil
		end
	else
		b.nokta:Hide()
	end
	for i, col in ipairs(self.columns) do
		local pos = self.positions[i]
		if b.rails[i] and not col.rail then
			b.rails[i]:Hide()
		end
		if col.rail then
			local spec = col.rail(data, self.ctx) or {}
			if spec.selected == nil then
				spec.selected = open
			end
			M.DrawRail(b, i, pos, spec)
			if b.cells[i] then
				b.cells[i]:Hide()
			end
			if b.icons[i] then
				b.icons[i]:Hide()
			end
		elseif col.icon then
			local icon = b.icons[i]
			if not icon then
				icon = b:CreateTexture(nil, "ARTWORK")
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				b.icons[i] = icon
			end
			icon:ClearAllPoints()
			icon:SetPoint("LEFT", b, "LEFT", pos.x, 0)
			icon:SetSize(ICON, ICON)
			icon:SetTexture(data.icon or (data.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID)))
			icon:Show()
			if b.cells[i] then
				b.cells[i]:Hide()
			end
		else
			local cell = b.cells[i]
			if not cell then
				cell = Style.Text(b, col.font or "Body", "text")
				cell:SetWordWrap(false)
				b.cells[i] = cell
			end
			cell:SetFontObject(Style.Fonts[col.font or "Body"])
			local color = Style.Color(col.color and col.color(data) or "text")
			cell:SetTextColor(color[1], color[2], color[3], 1)
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", b, "LEFT", pos.x, 0)
			cell:SetWidth(pos.width)
			cell:SetJustifyH(col.align or "LEFT")
			cell:SetText(CellText(col, data))
			cell:Show()
			if b.icons[i] then
				b.icons[i]:Hide()
			end
		end
		if col.tip then
			local hit = Hit(self, b, i)
			hit.col = col
			hit:ClearAllPoints()
			hit:SetPoint("TOPLEFT", b, "TOPLEFT", pos.x, 0)
			hit:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", pos.x, 0)
			hit:SetWidth(pos.width)
			hit:Show()
		elseif b.hits[i] then
			b.hits[i]:Hide()
		end
	end
	for i = #self.columns + 1, math.max(#b.cells, #b.icons, #b.hits, #b.rails) do
		for _, set in ipairs({ b.cells, b.icons, b.hits, b.rails }) do
			if set[i] then
				set[i]:Hide()
			end
		end
	end
	if self.page.InitRow then
		local ok, err = M.Call(self.page.InitRow, b, data, self.ctx)
		if not ok and self.onError then
			self.onError(err)
		end
	end
end

function List:InitDetail(f, element)
	if not f.cw then
		f.cw = true
		f.card = CreateFrame("Frame", nil, f)
		Style.Sheet(f.card, C.card, C.cardFlap, 10, false)
		f.content = CreateFrame("Frame", nil, f.card)
		f.content:SetPoint("TOPLEFT", f.card, "TOPLEFT", OPEN_PAD_X, -OPEN_PAD_Y)
		f.content:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -OPEN_PAD_X, OPEN_PAD_Y)
	end
	local m = self.metrics or {}
	f.card:ClearAllPoints()
	f.card:SetPoint("TOPLEFT", f, "TOPLEFT", m.openLeft or OPEN_MARGIN.left, 0)
	f.card:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(m.openRight or OPEN_MARGIN.right), OPEN_MARGIN.bottom)
	f.element = element
	local ok, err = M.Call(self.page.Open, f.content, element.row, self.ctx)
	if not ok and self.onError then
		self.onError(err)
	end
end

-- The elements the ScrollBox shows: each row, and after the open one its opened part.
function List:Elements()
	local out = {}
	for _, row in ipairs(self.rows) do
		out[#out + 1] = { row = row }
		if self.openKey ~= nil and self.openKey == M.RowKey(row) and self.page.Open then
			local h = self.page.OpenHeight and select(2, M.Call(self.page.OpenHeight, row, self.ctx)) or nil
			out[#out + 1] = { open = true, row = row, height = (tonumber(h) or 64) + 2 * OPEN_PAD_Y }
		end
	end
	return out
end

function List:Extent(element)
	if element.open then
		return element.height + OPEN_MARGIN.bottom
	end
	return self.rowHeight
end

function List:LayoutHeaders()
	local sortKey = M.Sort(self.page)
	for i, col in ipairs(self.columns) do
		local h = self.headers[i]
		if not h then
			h = CreateFrame("Button", nil, self.head)
			h.label = Style.Text(h, "Label", "text3")
			h.label:SetPoint("LEFT", h, "LEFT", 0, 0)
			h.label:SetPoint("RIGHT", h, "RIGHT", 0, 0)
			h.label:SetWordWrap(false)
			h:SetScript("OnClick", function(btn)
				if btn.col and btn.col.sort then
					M.ClickSort(self.page, btn.col.key)
				end
			end)
			self.headers[i] = h
		end
		h.col = col
		local pos = self.positions[i]
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", self.head, "TOPLEFT", pos.x, 0)
		h:SetSize(pos.width, self.metrics.listHeader or 24)
		h.label:SetJustifyH(col.align or "LEFT")
		local active = col.sort and col.key == sortKey
		local c = active and C.text or C.text3
		h.label:SetTextColor(c[1], c[2], c[3], 1)
		h.label:SetText((col.label or "") .. (active and (" " .. Style.Glyph("down", 10, "text")) or ""))
		h:Show()
	end
	for i = #self.columns + 1, #self.headers do
		self.headers[i]:Hide()
	end
end

-- Builds the elements again and hands them to the ScrollBox (the scroll position stays).
function List:Render()
	local provider = CreateDataProvider(self:Elements())
	self.box:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	self.empty:SetShown(#self.rows == 0 and (self.emptyText or "") ~= "")
	self.empty:SetText(self.emptyText or "")
end

-- New rows from the page's model. columns: the page's list; metrics: the layout's.
function List:SetRows(rows, ctx, columns, metrics, emptyText)
	self.rows, self.ctx, self.columns, self.metrics = rows or {}, ctx, columns or {}, metrics
	self.emptyText = emptyText
	self.rowHeight = (not self.docked and self.page.rowHeight) or metrics.rowHeight or 36
	self.positions = M.ColumnLayout(self.columns, metrics.width, metrics.pad)
	-- noHeader: lists whose group rows carry the 2 unit rule (board "Bags") have no header row.
	local headHeight = self.page.noHeader and 0 or (metrics.listHeader or 24)
	self.head:SetHeight(headHeight)
	self.head:SetShown(not self.page.noHeader and headHeight > 0)
	self.box:ClearAllPoints()
	self.box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -headHeight)
	self.box:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	local still = false
	for _, row in ipairs(self.rows) do
		still = still or (self.openKey ~= nil and M.RowKey(row) == self.openKey)
	end
	if not still then
		self.openKey = nil
	end
	self:LayoutHeaders()
	self:Render()
end

function M.List(parent, page, docked)
	local list = CreateFrame("Frame", nil, parent)
	for k, f in pairs(List) do
		list[k] = f
	end
	list.page, list.rows, list.columns, list.headers = page, {}, {}, {}
	list.docked = docked and true or false
	list.head = CreateFrame("Frame", nil, list)
	list.head:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	list.head:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	list.head:SetHeight(24)
	list.headRule = list.head:CreateTexture(nil, "ARTWORK")
	Style.Fill(list.headRule, C.text)
	list.headRule:SetHeight(2)
	list.headRule:SetPoint("BOTTOMLEFT", list.head, "BOTTOMLEFT", 0, 0)
	list.headRule:SetPoint("BOTTOMRIGHT", list.head, "BOTTOMRIGHT", 0, 0)

	list.box = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	list.box:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -24)
	list.box:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	list.bar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	list.bar:SetPoint("TOPRIGHT", list.box, "TOPRIGHT", -7, 0)
	list.bar:SetPoint("BOTTOMRIGHT", list.box, "BOTTOMRIGHT", -7, 0)
	Style.ScrollBar(list.bar)
	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(function(factory, element)
		if element.open then
			factory("Frame", function(f, e)
				list:InitDetail(f, e)
			end)
		else
			factory("Button", function(b, e)
				list:InitRow(b, e)
			end)
		end
	end)
	view:SetElementExtentCalculator(function(_, element)
		return list:Extent(element)
	end)
	list.view = view
	ScrollUtil.InitScrollBoxListWithScrollBar(list.box, list.bar, view)
	if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
		ScrollUtil.AddManagedScrollBarVisibilityBehavior(list.box, list.bar)
	end
	-- An empty list in a working page: one line in C.text3 that says what to do.
	list.empty = Style.Text(list, "Body", "text3")
	list.empty:SetPoint("TOPLEFT", list.box, "TOPLEFT", 22, -14)
	list.empty:SetJustifyH("LEFT")
	list.empty:Hide()
	return list
end

----------------------------------------------------------------------------------------------------
-- Docked rows (#161)
----------------------------------------------------------------------------------------------------

-- Inner width of an opened row's card in a layout (its content frame): pages lay their opened rows out
-- in it.
function M.OpenInnerWidth(ctx)
	local m = ctx and ctx.metrics or {}
	return (m.width or 880) - (m.openLeft or OPEN_MARGIN.left) - (m.openRight or OPEN_MARGIN.right) - 2 * OPEN_PAD_X
end

-- What a docked row shows (pure):
--   group = { title, note, right }        a group header row (Bags, Upgrades): title, note, total right
--   line, lineColor                       a row of one line of text
--   icon (texture) | itemID, desaturate   the icon when the page's list has one (icon = false: none)
--   name, nameColor, nameFont             line 1, left
--   rail = { value, max, zeroAt, point, low, high, selected }   line 2, under the name
--   note, noteColor, live                 line 2 when there is no rail (live: the orange nokta before it)
--   result, resultColor, sub, subColor    right: the result, the sub-figure under it
--   tag                                   a line tag under the result (the Bags mark)
--   tip                                   the result's own tip (why a figure is missing)
--   missing                               the result is still missing: a skeleton bar while scanning
--   here                                  the row is "here" (Ledger: today): C.selected and the nokta
-- From the page's DockedRow(row, ctx) when it returns one; else the Make pages' row.view; else derived
-- from its columns: the name column, the rail column, the last column as the result, a right aligned
-- column before it as the sub-figure and the other columns as the note.
local function ColText(col, data)
	local t = CellText(col, data)
	return t ~= "" and t or nil
end

local function ColColor(col, data)
	return col.color and col.color(data) or nil
end

function M.DockedView(page, data, ctx, columns)
	if page.DockedRow then
		local ok, v = M.Call(page.DockedRow, data, ctx)
		if not ok then
			error(v, 0)
		end
		if v then
			return v
		end
	end
	columns = columns or {}
	local v = {}
	local hasIcon, railCol, nameCol = false, nil, nil
	local texts = {}
	for _, col in ipairs(columns) do
		if col.icon then
			hasIcon = true
		elseif col.rail then
			railCol = railCol or col
		elseif not nameCol and (col.key == "name") then
			nameCol = col
		else
			texts[#texts + 1] = col
		end
	end
	if not nameCol and texts[1] then
		nameCol = table.remove(texts, 1)
	end
	v.icon = hasIcon and (data.icon or (data.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID))) or nil
	if not hasIcon then
		v.icon = false
	end
	local view = data.view
	if view then
		v.name, v.nameColor = view.name, view.nameColor
		v.result, v.resultColor, v.sub = view.result, view.resultColor, view.sub
		v.missing = view.missing
		if view.rail then
			v.rail = { value = view.rail.value, max = ctx and ctx.railMax, zeroAt = view.rail.zeroAt }
		end
		v.tip = view.tips and (view.tips.profit or view.tips.perSkill)
		return v
	end
	if nameCol then
		v.name, v.nameColor = ColText(nameCol, data), ColColor(nameCol, data)
	end
	local resultCol = table.remove(texts)
	if resultCol then
		v.result, v.resultColor = ColText(resultCol, data), ColColor(resultCol, data)
		v.tip = resultCol.tip and resultCol.tip(data) or nil
	end
	local last = texts[#texts]
	if last and last.align == "RIGHT" then
		table.remove(texts)
		v.sub = ColText(last, data)
	end
	if railCol then
		v.rail = railCol.rail(data, ctx) or {}
	end
	local notes = {}
	for _, col in ipairs(texts) do
		notes[#notes + 1] = ColText(col, data)
	end
	v.note = #notes > 0 and table.concat(notes, " · ") or nil
	return v
end

local DOCK_ICON_GAP, DOCK_LINE1, DOCK_LINE2, DOCK_RAIL = 10, -7, -25, -27

local function DockedParts(b)
	local d = b.dk
	if d then
		return d
	end
	d = {}
	d.icon = b:CreateTexture(nil, "ARTWORK")
	d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	d.icon:SetSize(ICON, ICON)
	d.name = Style.Text(b, "Body", "text")
	d.name:SetJustifyH("LEFT")
	d.name:SetWordWrap(false)
	d.note = Style.Text(b, "Caption", "text3")
	d.note:SetJustifyH("LEFT")
	d.note:SetWordWrap(false)
	d.result = Style.Text(b, "FigureBold", "text")
	d.result:SetJustifyH("RIGHT")
	d.result:SetWordWrap(false)
	d.sub = Style.Text(b, "Caption", "text3")
	d.sub:SetJustifyH("RIGHT")
	d.sub:SetWordWrap(false)
	d.live = Style.Nokta(b, C.live)
	d.live:Hide()
	d.title = Style.Text(b, "Section", "text")
	d.gnote = Style.Text(b, "Caption", "text3")
	d.gnote:SetWordWrap(false)
	d.right = Style.Text(b, "Figure", "text")
	d.right:SetJustifyH("RIGHT")
	d.rule = b:CreateTexture(nil, "ARTWORK")
	Style.Fill(d.rule, C.text)
	d.rule:SetHeight(2)
	d.rule:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	d.rule:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	d.line = Style.Text(b, "Small", "text3")
	d.line:SetJustifyH("LEFT")
	d.line:SetWordWrap(false)
	d.tag = CreateFrame("Frame", nil, b)
	d.tag:SetHeight(14)
	d.tag.border = Style.Border(d.tag, C.ruleStrong)
	d.tag.label = Style.Text(d.tag, "Label", "text2")
	d.tag.label:SetPoint("CENTER", d.tag, "CENTER", 0, 0)
	b.dk = d
	return d
end

local function Paint(fs, color)
	local c = Style.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], 1)
end

function List:InitDockedRow(b, element)
	local data = element.row
	local m = self.metrics or {}
	local d = DockedParts(b)
	local ok, v = pcall(M.DockedView, self.page, data, self.ctx, self.columns)
	if not ok then
		if self.onError then
			self.onError(v)
		end
		v = {}
	end
	b.dockedView = v
	local width, pad = m.width or 380, m.pad or 18
	local open = self.openKey ~= nil and self.openKey == M.RowKey(data)
	local here = open or v.here
	b.bg:SetShown(here and true or false)
	if here then
		b.nokta:MoveTo(b, "LEFT", pad / 2, 0, self.justOpened ~= M.RowKey(data))
		if self.justOpened == M.RowKey(data) then
			self.justOpened = nil
		end
	else
		b.nokta:Hide()
	end
	local all = { d.icon, d.name, d.note, d.result, d.sub, d.live, d.title, d.gnote, d.right, d.rule, d.line, d.tag }
	for _, r in ipairs(all) do
		r:Hide()
	end
	if b.rails.dock then
		b.rails.dock:Hide()
	end
	if b.hits.dock then
		b.hits.dock:Hide()
	end
	if b.cwSkeleton then
		b.cwSkeleton:Hide()
	end
	b.hair:SetShown(not v.group)
	if v.group then
		-- A group header (board "Bags"): title, its note, the total right, the 2 unit C.text rule.
		local g = v.group
		d.title:ClearAllPoints()
		d.title:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", pad, 8)
		d.title:SetText(g.title or "")
		d.gnote:ClearAllPoints()
		d.gnote:SetPoint("BOTTOMLEFT", d.title, "BOTTOMRIGHT", 8, 1)
		d.gnote:SetWidth(math.max(width - 2 * pad - 80 - 8 - 90, 40))
		d.gnote:SetText(g.note or "")
		d.right:ClearAllPoints()
		d.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -pad, 8)
		d.right:SetText(g.right or "")
		for _, r in ipairs({ d.title, d.gnote, d.right, d.rule }) do
			r:Show()
		end
	elseif v.line then
		d.line:ClearAllPoints()
		d.line:SetPoint("LEFT", b, "LEFT", pad, 0)
		d.line:SetWidth(width - 2 * pad)
		d.line:SetText(v.line)
		Paint(d.line, v.lineColor or "text3")
		d.line:Show()
	else
		local x = pad
		local iconCol = false
		for _, col in ipairs(self.columns or {}) do
			iconCol = iconCol or col.icon and true or false
		end
		if v.icon ~= false and (v.icon or v.itemID or iconCol) then
			local tex = v.icon or (v.itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(v.itemID)) or nil
			d.icon:SetTexture(tex)
			d.icon:SetDesaturated(v.desaturate and true or false)
			d.icon:ClearAllPoints()
			d.icon:SetPoint("LEFT", b, "LEFT", pad, 0)
			d.icon:Show()
			x = pad + ICON + DOCK_ICON_GAP
		end
		local right = m.rightColumn or 132
		local nameW = width - x - pad - right - DOCK_ICON_GAP
		d.name:ClearAllPoints()
		d.name:SetPoint("TOPLEFT", b, "TOPLEFT", x, DOCK_LINE1)
		d.name:SetWidth(nameW)
		d.name:SetFontObject(Style.Fonts[v.nameFont or "Body"])
		d.name:SetText(v.name or "")
		Paint(d.name, v.nameColor)
		d.name:Show()
		if v.rail then
			local spec = v.rail
			if spec.selected == nil then
				spec.selected = here and true or false
			end
			local r = M.DrawRail(b, "dock", { x = x, width = nameW }, spec)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", b, "TOPLEFT", x, DOCK_RAIL)
			r:SetSize(nameW, 8)
			r.zero:SetHeight(8)
			if r.Relayout and not spec.point then
				r:Relayout()
			end
		elseif v.note then
			local nx = x
			if v.live then
				d.live:SetSize(8, 8)
				d.live:ClearAllPoints()
				d.live:SetPoint("CENTER", b, "TOPLEFT", x + 4, DOCK_LINE2 - 6)
				d.live:Show()
				nx = x + 12
			end
			d.note:ClearAllPoints()
			d.note:SetPoint("TOPLEFT", b, "TOPLEFT", nx, DOCK_LINE2)
			d.note:SetWidth(nameW - (nx - x))
			d.note:SetText(v.note)
			Paint(d.note, v.noteColor or "text3")
			d.note:Show()
		end
		local scanning = v.missing and self.ctx and self.ctx.prices and self.ctx.prices.scanning
		d.result:ClearAllPoints()
		d.result:SetPoint("TOPRIGHT", b, "TOPRIGHT", -pad, DOCK_LINE1 + 1)
		d.result:SetWidth(right)
		d.result:SetText(scanning and "" or (v.result or ""))
		Paint(d.result, v.resultColor)
		d.result:Show()
		if scanning then
			b.cwSkeleton = b.cwSkeleton or M.Skeleton(b, 50, 8)
			b.cwSkeleton:ClearAllPoints()
			b.cwSkeleton:SetPoint("TOPRIGHT", b, "TOPRIGHT", -pad, DOCK_LINE1 - 3)
			b.cwSkeleton:Show()
		end
		if v.tag then
			d.tag.label:SetText(v.tag)
			d.tag:SetWidth(math.floor((d.tag.label:GetStringWidth() or 0) + 12 + 0.5))
			d.tag:ClearAllPoints()
			d.tag:SetPoint("TOPRIGHT", b, "TOPRIGHT", -pad, DOCK_LINE2 + 2)
			d.tag:Show()
		end
		if v.sub then
			d.sub:ClearAllPoints()
			d.sub:SetPoint("TOPRIGHT", b, "TOPRIGHT", v.tag and -(pad + (d.tag:GetWidth() or 0) + 6) or -pad, DOCK_LINE2)
			d.sub:SetWidth(right)
			d.sub:SetText(v.sub)
			Paint(d.sub, v.subColor or "text3")
			d.sub:Show()
		end
		if v.tip then
			local hit = Hit(self, b, "dock")
			hit.col = { tip = function() return v.tip end }
			hit:ClearAllPoints()
			hit:SetPoint("TOPRIGHT", b, "TOPRIGHT", -pad, 0)
			hit:SetSize(right, (m.rowHeight or 44))
			hit:Show()
		end
	end
	if self.page.DockedInitRow then
		local okInit, err = M.Call(self.page.DockedInitRow, b, data, self.ctx, v)
		if not okInit and self.onError then
			self.onError(err)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Rail columns (spec "Shapes and textures", Rails): a 4 unit bar on the list's shared axis; or, with
-- spec.point, a tick at the value and its likely range as a thin line (board "Fishing").
----------------------------------------------------------------------------------------------------

local RAIL_HEIGHT = 16

-- x of a value on a rail of `width` (0 .. width), zero at the left.
local function RailX(value, maxAbs, width)
	if not value or value <= 0 then
		return 0
	end
	local zero, w = Style.RailGeometry(value, maxAbs, width, 0)
	return zero + w
end

function M.DrawRail(b, i, pos, spec)
	local r = b.rails[i]
	if not r then
		r = Style.Rail(b, spec.zeroAt or 0)
		r.range = r:CreateTexture(nil, "ARTWORK", nil, 1)
		r.range:SetTexture(Style.WHITE)
		r.tick = r:CreateTexture(nil, "ARTWORK", nil, 3)
		r.tick:SetTexture(Style.WHITE)
		b.rails[i] = r
	end
	r.zeroAt = spec.zeroAt or 0
	r:ClearAllPoints()
	r:SetPoint("LEFT", b, "LEFT", pos.x, 0)
	r:SetSize(pos.width, RAIL_HEIGHT)
	r:Show()
	r.spec = spec
	if not spec.point then
		r.range:Hide()
		r.tick:Hide()
		r:SetValue(spec.value, spec.max, spec.selected)
		return r
	end
	r:SetValue(nil, spec.max, spec.selected)
	local w, max = pos.width, spec.max or 0
	if not spec.value or max <= 0 then
		r.range:Hide()
		r.tick:Hide()
		return r
	end
	local lo, hi = RailX(spec.low or spec.value, max, w), RailX(spec.high or spec.value, max, w)
	if hi - lo >= 1 then
		Style.Fill(r.range, C.ruleStrong)
		r.range:ClearAllPoints()
		r.range:SetPoint("LEFT", r, "LEFT", lo, 0)
		r.range:SetSize(hi - lo, 2)
		r.range:Show()
	else
		r.range:Hide()
	end
	local x = RailX(spec.value, max, w)
	Style.Fill(r.tick, spec.selected and C.text or C.text2)
	r.tick:ClearAllPoints()
	r.tick:SetPoint("LEFT", r, "LEFT", math.max(0, x - 1), 0)
	r.tick:SetSize(3, 6)
	r.tick:Show()
	return r
end

-- Opens a row of a page's list from outside (the farm tracker's links); false while the list isn't built.
function M.OpenRow(pageKey, rowKey)
	local list = M.ListOf and M.ListOf(pageKey)
	if not list then
		return false
	end
	if list.openKey ~= rowKey then
		list.openKey, list.justOpened = rowKey, rowKey
	end
	list:Render()
	return true
end

----------------------------------------------------------------------------------------------------
-- Pool: widgets an opened row draws into its card. The ScrollBox reuses the opened part between rows,
-- so a page's Open starts with pool:Reset() and takes what it needs again.
----------------------------------------------------------------------------------------------------

local Pool = {}
Pool.__index = Pool

function M.Pool(owner)
	local p = owner.cwPool
	if not p then
		p = setmetatable({ owner = owner, kinds = {}, used = {} }, Pool)
		owner.cwPool = p
	end
	return p
end

function Pool:Reset()
	for kind, list in pairs(self.kinds) do
		for _, w in ipairs(list) do
			w:Hide()
			if w.ClearAllPoints then
				w:ClearAllPoints()
			end
		end
		self.used[kind] = 0
	end
end

function Pool:Take(kind, make)
	local list = self.kinds[kind]
	if not list then
		list = {}
		self.kinds[kind] = list
	end
	local n = (self.used[kind] or 0) + 1
	self.used[kind] = n
	local w = list[n]
	if not w then
		w = make(self.owner)
		list[n] = w
	end
	w:Show()
	return w
end

-- A FontString in `font` and `color` (a Style colour name or table).
function Pool:Text(font, color, text)
	local fs = self:Take("text", function(owner)
		local t = Style.Text(owner, font or "Small", "text")
		t:SetJustifyH("LEFT")
		t:SetWordWrap(false)
		return t
	end)
	fs:SetFontObject(Style.Fonts[font or "Small"])
	local c = Style.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], 1)
	fs:SetJustifyH("LEFT")
	fs:SetWidth(0)
	fs:SetText(text or "")
	return fs
end

-- A WHITE8x8 texture in a colour (bars, rules).
function Pool:Bar(color)
	local t = self:Take("bar", function(owner)
		local tex = owner:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(Style.WHITE)
		return tex
	end)
	Style.Fill(t, Style.Color(color or "text"))
	return t
end

-- An item icon (tex coords 0.08-0.92).
function Pool:Icon(size, texture)
	local t = self:Take("icon", function(owner)
		local tex = owner:CreateTexture(nil, "ARTWORK")
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		return tex
	end)
	t:SetSize(size or 16, size or 16)
	t:SetTexture(texture)
	return t
end

-- A line button; onClick() on a click, tip = { title, lines... } for the inverse tooltip.
function Pool:Button(label, onClick, tip, height)
	local b = self:Take("button", function(owner)
		local btn = Style.LineButton(owner, "", nil, height or 22)
		local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
		btn:SetScript("OnEnter", function(this)
			enter(this)
			if this.cwTip then
				Style.ShowTip(this, unpack(this.cwTip))
			end
		end)
		btn:SetScript("OnLeave", function(this)
			leave(this)
			Style.HideTip(this)
		end)
		btn:SetScript("OnClick", function(this)
			if this.cwClick then
				this.cwClick(this)
			end
		end)
		return btn
	end)
	b:SetHeight(height or 22)
	b:SetLabel(label)
	b.cwClick, b.cwTip = onClick, tip
	return b
end

-- A mouse area over a line: hover shows an item's tooltip (itemID) or the inverse tip; right-click opens
-- the item menu, Shift-click links the item, like a list row.
function Pool:Hit(data)
	local h = self:Take("hit", function(owner)
		local hit = CreateFrame("Button", nil, owner)
		hit:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
		hit:SetScript("OnEnter", function(this)
			local d = this.cwData or {}
			if d.itemID and GameTooltip and GameTooltip.SetItemByID then
				GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(d.itemID)
				for _, line in ipairs(d.lines or {}) do
					GameTooltip:AddDoubleLine(line[1], line[2], 0.75, 0.75, 0.75, 1, 1, 1)
				end
				GameTooltip:Show()
			elseif d.tip then
				Style.ShowTip(this, unpack(d.tip))
			end
		end)
		hit:SetScript("OnLeave", function(this)
			HideTips(this)
		end)
		hit:SetScript("OnClick", function(this, mouse)
			local d = this.cwData or {}
			if not d.itemID then
				return
			end
			if mouse == "LeftButton" and IsShiftKeyDown() then
				M.LinkToChat(d.itemID)
			elseif (mouse == "RightButton" or mouse == "MiddleButton") and ns.ShowItemMenu then
				HideTips(this)
				ns.ShowItemMenu(d.itemID, this)
			end
		end)
		return hit
	end)
	h.cwData = data
	return h
end
