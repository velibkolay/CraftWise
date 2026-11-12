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
	local layoutView = View() == "fishing" and PF.FishingLayout() or View()
	if state.layout ~= layoutView .. tostring(showLearn) then
		Layout(layoutView, showLearn)
	end

	state.data, state.hidden = FilteredRows()
	PF.UpdateFishingControls()
	local sortKey, sortDesc = SortSettings()
	local compare = ns.Profit.Comparator(sortKey, sortDesc)
	if ItemView() and View() ~= "music" and View() ~= "fishing" then
		local inner = compare
		compare = function(a, b)
			if a.dismissed ~= b.dismissed then
				return b.dismissed -- dismissed items last
			end
			return inner(a, b)
		end
	end
	table.sort(state.data, compare)
	state.offset = math.max(0, math.min(state.offset, #state.data - VISIBLE_ROWS))

	RenderSummary(ids)
	for key, header in pairs(PF.frame.headers) do
		local arrow = sortKey == key and (sortDesc and ARROW_DOWN or ARROW_UP) or ""
		local label = header.label
		if key == "name" and View() == "music" then
			label = L["PROFESSION"]
		elseif key == "name" and View() == "fishing" then
			label = state.fishZone and L["ITEM"] or L["ZONE"]
		elseif key == "name" and ItemView() then
			label = L["ITEM"]
		elseif key == "cost" and View() == "upgrades" then
			label = L["TOTAL COST"]
		end
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
	local unit = View() == "music" and "professions" or View() == "fishing" and not state.fishZone and "zones"
		or ItemView() and "items" or "recipes"
	PF.frame.count:SetText(Muted(("%d %s"):format(#state.data, unit)))
	local empty = "No recipes match. Clear the search or tick \"Show unlearned\"."
	if View() == "learn" then
		empty = "No recipes match. Clear the search or untick \"Fits my skill\"."
	elseif View() == "upgrades" and PF.UpgradeSection() == "ah" then
		empty = ns.UpgradeSearch.LastRun() and "No AH gear beats what you wear. Search again at the auction house later."
			or "No AH search yet. Open the auction house and click Search AH."
	elseif View() == "fishing" then
		empty = state.query ~= "" and "No zone matches the search."
			or "No catches yet and no local reference. Fish a while, or see docs/fishing-reference.md."
	elseif View() == "upgrades" then
		empty = "No upgrades from recipes you know or can learn now. Open your professions once so CraftWise knows them."
	end
	PF.frame.empty:SetText(empty)
	PF.frame.empty:SetShown((#ids > 0 or ItemView()) and #state.data == 0)
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
