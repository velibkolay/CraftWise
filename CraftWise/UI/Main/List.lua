-- Main window: the list of a page (spec "Main window shell", List row and "Mouse and keys"). One list per
-- page, made when the page first shows: a header row 24 tall with a 2 unit C.text rule, sortable headers
-- (▾ on the active one; click to sort, again to reverse), and a ScrollBox (mouse wheel, 4 unit thumb in
-- C.ruleStrong, no arrows) of rows with 1 unit C.rule hairlines. A click opens a row in place (one at a
-- time, the nokta moves to it; again closes it); right- or middle-click on an item row opens the item
-- menu; Shift-click puts the item link into chat; hovering an item shows its GameTooltip with the
-- CraftWise lines, any other row (or a column's own tip) the inverse tooltip.
local _, ns = ...
local M = ns.Main
local Style = ns.Style
local C = Style.C

local ICON = 22
local OPEN_MARGIN = { left = 56, right = 22, bottom = 8 } -- board "Window layout": the opened row's card
local OPEN_PAD_X, OPEN_PAD_Y = 14, 10

local List = {}

local function ShowRowTip(owner, data)
	if data.itemID and GameTooltip and GameTooltip.SetItemByID then
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
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints(b)
	Style.Fill(b.bg, C.selected)
	b.hair = Style.Rule(b, "H", C.rule, "BORDER")
	b.hair:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	b.hair:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
	b.nokta = Style.Nokta(b)
	b.nokta:Hide()
	b.cells, b.icons, b.hits = {}, {}, {}
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	b:SetScript("OnClick", function(self, mouse)
		list:Click(self, mouse)
	end)
	b:SetScript("OnEnter", function(self)
		if self.element then
			ShowRowTip(self, self.element.row)
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
				ShowRowTip(self, data)
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
		if col.icon then
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
	for i = #self.columns + 1, math.max(#b.cells, #b.icons, #b.hits) do
		for _, set in ipairs({ b.cells, b.icons, b.hits }) do
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
		f.card:SetPoint("TOPLEFT", f, "TOPLEFT", OPEN_MARGIN.left, 0)
		f.card:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -OPEN_MARGIN.right, OPEN_MARGIN.bottom)
		Style.Sheet(f.card, C.card, C.cardFlap, 10, false)
		f.content = CreateFrame("Frame", nil, f.card)
		f.content:SetPoint("TOPLEFT", f.card, "TOPLEFT", OPEN_PAD_X, -OPEN_PAD_Y)
		f.content:SetPoint("BOTTOMRIGHT", f.card, "BOTTOMRIGHT", -OPEN_PAD_X, OPEN_PAD_Y)
	end
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
	self.rowHeight = self.page.rowHeight or metrics.rowHeight or 36
	self.positions = M.ColumnLayout(self.columns, metrics.width, metrics.pad)
	self.head:SetHeight(metrics.listHeader or 24)
	self.box:ClearAllPoints()
	self.box:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(metrics.listHeader or 24))
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

function M.List(parent, page)
	local list = CreateFrame("Frame", nil, parent)
	for k, f in pairs(List) do
		list[k] = f
	end
	list.page, list.rows, list.columns, list.headers = page, {}, {}, {}
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
