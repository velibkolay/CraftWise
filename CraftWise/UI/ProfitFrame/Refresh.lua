-- Profit table window: Refresh (filter, sort, render everything) and the entry points other files call.
local _, ns = ...
local PF = ns.PF
local L = ns.L
local VISIBLE_ROWS, ARROW_DOWN, ARROW_UP = PF.VISIBLE_ROWS, PF.ARROW_DOWN, PF.ARROW_UP
local rows, state = PF.rows, PF.state
local Settings, Muted, ItemName, View, ItemView = PF.Settings, PF.Muted, PF.ItemName, PF.View, PF.ItemView
local ProfessionIDs, FilteredRows, SortSettings = PF.ProfessionIDs, PF.FilteredRows, PF.SortSettings
local RenderTabs, RenderSummary, RenderRow, UpdateScrollBar =
	PF.RenderTabs, PF.RenderSummary, PF.RenderRow, PF.UpdateScrollBar
local Layout, UpdateControls = PF.Layout, PF.UpdateControls

local function Refresh()
	if not (PF.frame and PF.frame:IsShown() and ns.charDB) then
		return
	end
	local ids = ProfessionIDs()
	if not state.professionID or not ns.charDB.professions[state.professionID] then
		state.professionID = ids[1]
	end
	if not ItemView() then
		RenderTabs(ids)
	end
	UpdateControls()
	local showLearn = View() == "learn" or Settings().includeUnlearned
	local layoutView = View()
	if state.layout ~= layoutView .. tostring(showLearn) then
		Layout(layoutView, showLearn)
	end

	state.data, state.hidden = FilteredRows()
	local sortKey, sortDesc = SortSettings()
	local compare = ns.Profit.Comparator(sortKey, sortDesc)
	table.sort(state.data, compare)
	state.offset = math.max(0, math.min(state.offset, #state.data - VISIBLE_ROWS))

	RenderSummary(ids)
	for key, header in pairs(PF.frame.headers) do
		local arrow = sortKey == key and (sortDesc and ARROW_DOWN or ARROW_UP) or ""
		local label = header.label
		header.text:SetText(label .. arrow)
	end

	for i = 1, VISIBLE_ROWS do
		local r = state.data[i + state.offset]
		if r then
			RenderRow(rows[i], r, i + state.offset)
		else
			rows[i].data = nil
			rows[i]:Hide()
		end
	end
	PF.frame.count:SetText(Muted(("%d %s"):format(#state.data, "recipes")))
	local empty = "No recipes match. Clear the search or tick \"Show unlearned\"."
	if View() == "learn" then
		empty = "No recipes match. Clear the search or untick \"Fits my skill\"."
	end
	PF.frame.empty:SetText(empty)
	PF.frame.empty:SetShown(#ids > 0 and #state.data == 0)
	UpdateScrollBar()
end
ns.RefreshProfitFrame = Refresh

-- Is a frame part of the CraftWise window? (Its own tooltips already show CraftWise details.)
function ns.InOwnWindow(owner)
	local f = owner
	for _ = 1, 6 do
		if not f then
			return false
		end
		if f == PF.frame then
			return true
		end
		f = f.GetParent and f:GetParent()
	end
	return false
end

-- "Recipes using this": the profession of yours that uses the item most, searched by the item's name,
-- with unlearned recipes shown (Profit view; the Learn view shows only what you don't know).
function ns.ShowRecipesUsing(itemID)
	local counts = {}
	for _, e in ipairs(ns.UsedIn(itemID)) do
		if e.professionID then
			counts[e.professionID] = (counts[e.professionID] or 0) + 1
		end
	end
	local best, most = nil, 0
	for id, n in pairs(counts) do
		if n > most then
			best, most = id, n
		end
	end
	if not best then
		ns.WithItemNames({ itemID }, function()
			ns.Print(ns.ItemChatText(itemID) .. " is not used by your professions.")
		end)
		return false
	end
	if not (PF.frame and PF.frame:IsShown()) then
		ns.ToggleProfitFrame()
	end
	Settings().view, Settings().includeUnlearned = "profit", true
	PF.frame.unlearned:SetChecked(true)
	state.professionID, state.offset = best, 0
	state.query = ItemName(itemID)
	PF.frame.search:SetText(state.query)
	PF.frame.searchHint:Hide()
	Refresh()
	return true
end

PF.Refresh = Refresh
