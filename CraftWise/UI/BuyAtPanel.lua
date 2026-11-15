-- "Where to buy it" panel (issue #276): opened by a click on a reagent in an opened Make row (Craft, Level up).
-- Lists every recorded vendor of the item that sells to the player's faction (Merchant.BuyAtAll), the nearest
-- one marked, each with a waypoint button, and "Waypoint to nearest" at the foot. "Nearest" is only claimed
-- where it can be measured: the same map by distance, else the same zone, else the same continent; a vendor
-- on another continent is listed without a distance (Merchant.lua says how). A waypoint is only ever set by
-- a click on one of the buttons (C_Map.SetUserWaypoint).
local _, ns = ...
local Style, L = ns.Style, ns.L

local P = {}
ns.BuyAtPanel = P

P.WIDTH, P.ROW, P.MAX_ROWS, P.MAX_REMINDERS = 520, 24, 10, 5

local panel

local SCOPE_WORDS = { map = L["nearest on this map"], zone = L["in this zone"], continent = L["on this continent"] }

local function Say(text)
	if ns.Print then
		ns.Print(text)
	end
end

-- Sets the waypoint of an entry and says so (or why not).
function P.Waypoint(entry)
	local ok, why = ns.Merchant.Waypoint(entry)
	if ok then
		Say((L["Waypoint set at %s."]):format(entry.merchant.name or "?"))
	else
		Say((why or L["No waypoint"]) .. ".")
	end
	return ok
end

local function Row(i)
	local row = panel.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, panel)
	row:SetSize(P.WIDTH - 24, P.ROW)
	row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -34 - (i - 1) * P.ROW)
	row.text = Style.Text(row, "Small", "text")
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -156, 0)
	row.text:SetJustifyH("LEFT")
	row.go = Style.ActionButton(row, L["Waypoint"], 74, 20)
	row.go:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.remind = Style.ActionButton(row, L["Remind"], 74, 20)
	row.remind:SetPoint("RIGHT", row.go, "LEFT", -6, 0)
	row.remind:SetScript("OnClick", function(self)
		if self.entry then
			P.PickTime(self.entry)
		end
	end)
	row.go:SetScript("OnClick", function(self)
		if self.entry then
			P.Waypoint(self.entry)
		end
	end)
	panel.rows[i] = row
	return row
end

-- Setting a reminder (#289): "Remind" on a vendor row shows the time choices (the learned one first when the
-- stock log has it); one click sets it. Active reminders are listed under the vendors, each with a delete.
function P.PickTime(entry)
	panel.pick = (panel.pick and panel.pick.npcID == entry.npcID) and nil or entry
	P.Fill(panel.itemID)
end

function P.SetReminder(entry, seconds)
	local rec, why = ns.Restock.Add(entry.npcID, panel.itemID, seconds)
	if rec then
		Say((L["Reminder set: %s"]):format(ns.Restock.Line(rec)))
	else
		Say((why or L["No reminder"]) .. ".")
	end
	panel.pick = nil
	P.Fill(panel.itemID)
	return rec
end

local function Chip(i)
	local b = panel.choices[i]
	if b then
		return b
	end
	b = Style.ActionButton(panel, "", 96, 20)
	b:SetScript("OnClick", function(self)
		if self.entry and self.seconds then
			P.SetReminder(self.entry, self.seconds)
		end
	end)
	panel.choices[i] = b
	return b
end

local function ReminderRow(i)
	local row = panel.reminders[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, panel)
	row:SetSize(P.WIDTH - 24, P.ROW)
	row.text = Style.Text(row, "Small", "text2")
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
	row.text:SetJustifyH("LEFT")
	row.del = Style.ActionButton(row, "×", 26, 20)
	row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.del:SetScript("OnClick", function(self)
		if self.id then
			ns.Restock.Remove(self.id)
			P.Fill(panel.itemID)
		end
	end)
	panel.reminders[i] = row
	return row
end

local function Create()
	if panel then
		return panel
	end
	panel = CreateFrame("Frame", "CraftWiseBuyAt", UIParent)
	panel:SetSize(P.WIDTH, 120)
	panel:SetFrameStrata("DIALOG")
	panel:EnableMouse(true)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.rows, panel.choices, panel.reminders = {}, {}, {}
	panel.title = Style.Text(panel, "BodyBold", "text")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetWidth(P.WIDTH - 60)
	panel.title:SetJustifyH("LEFT")
	panel.close = Style.ActionButton(panel, "×", 24, 20)
	panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
	panel.close:SetScript("OnClick", function()
		panel:Hide()
	end)
	panel.note = Style.Text(panel, "Small", "text3")
	panel.note:SetWidth(P.WIDTH - 24)
	panel.note:SetJustifyH("LEFT")
	panel.nearest = Style.ActionButton(panel, L["Waypoint to nearest"], 160, 24)
	panel.nearest:SetScript("OnClick", function(self)
		if self.entry then
			P.Waypoint(self.entry)
		end
	end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, "CraftWiseBuyAt") -- Escape closes it
	end
	panel:Hide()
	P.panel = panel
	return panel
end

-- Fills the panel for an item. Returns the panel, or nil when nothing is known about where to buy it.
function P.Fill(itemID)
	local all = ns.Merchant.BuyAtAll(itemID)
	if not all then
		return nil
	end
	Create()
	local name = ns.ItemInfoNow and select(1, ns.ItemInfoNow(itemID)) or nil
	panel.title:SetText((L["Where to buy %s"]):format(name or ("item " .. itemID)))
	for _, row in ipairs(panel.rows) do
		row:Hide()
	end
	local shown = math.min(#all.entries, P.MAX_ROWS)
	for i = 1, shown do
		local e = all.entries[i]
		local row = Row(i)
		local nearest = all.nearest == e
		local scope = SCOPE_WORDS[e.scope]
		row.text:SetText((nearest and (Style.Hex("live") .. "› |r") or "") .. e.text .. (scope and (" " .. Style.Hex("text3") .. scope .. "|r") or ""))
		row.go.entry = e
		row.remind.entry = e
		local located = e.merchant.map and e.merchant.x and e.merchant.y
		if row.go.SetEnabled then
			row.go:SetEnabled(located and true or false)
		end
		row:Show()
	end
	local y = 34 + shown * P.ROW + 4
	for _, b in ipairs(panel.choices) do
		b:Hide()
	end
	if panel.pick then
		local choices = ns.Restock.Choices(panel.pick.npcID, itemID)
		panel.pickLabel = panel.pickLabel or Style.Text(panel, "Small", "text2")
		panel.pickLabel:ClearAllPoints()
		panel.pickLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y - 4)
		panel.pickLabel:SetText((L["Remind me at %s in:"]):format(panel.pick.merchant.name or "?"))
		panel.pickLabel:Show()
		local x = 12
		for i, choice in ipairs(choices) do
			local b = Chip(i)
			b.entry, b.seconds = panel.pick, choice.seconds
			b:SetLabel(choice.label)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y - 24)
			b:Show()
			x = x + 102
		end
		y = y + 50
	elseif panel.pickLabel then
		panel.pickLabel:Hide()
	end
	panel.nearest.entry = all.nearest
	panel.nearest:ClearAllPoints()
	panel.nearest:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
	if panel.nearest.SetEnabled then
		panel.nearest:SetEnabled(all.nearest ~= nil and all.nearest.merchant.map ~= nil)
	end
	local note
	if all.bundled then
		note = L["Sold by vendors, location not recorded yet"]
	elseif not all.nearest then
		note = L["None of these is on your continent: no nearest one is claimed."]
	elseif #all.entries > shown then
		note = (L["+%d more: /craftwise where"]):format(#all.entries - shown)
	end
	panel.note:ClearAllPoints()
	panel.note:SetPoint("LEFT", panel.nearest, "RIGHT", 10, 0)
	panel.note:SetWidth(P.WIDTH - 24 - 170)
	panel.note:SetText(note or "")
	panel.nearest:SetShown(not all.bundled)
	y = y + 32
	local active = ns.Restock.List()
	for _, row in ipairs(panel.reminders) do
		row:Hide()
	end
	for i = 1, math.min(#active, P.MAX_REMINDERS) do
		local r = active[i]
		local row = ReminderRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -y)
		row.text:SetText(ns.Restock.Line(r))
		row.del.id = r.id
		row:Show()
		y = y + P.ROW
	end
	panel:SetHeight(y + 8)
	return panel
end

-- Opens the panel next to `owner` (the clicked reagent), or closes it when it already shows this item.
function P.Toggle(itemID, owner)
	if panel and panel:IsShown() and panel.itemID == itemID then
		panel:Hide()
		return nil
	end
	if panel and panel.itemID ~= itemID then
		panel.pick = nil
	end
	if not P.Fill(itemID) then
		return nil
	end
	panel.itemID = itemID
	panel:ClearAllPoints()
	if owner then
		panel:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 6)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	panel:Show()
	return panel
end
