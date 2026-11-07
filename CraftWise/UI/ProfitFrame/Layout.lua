-- Profit table window: column layout per view and the show/hide state of the controls.
local _, ns = ...
local PF = ns.PF
local L = ns.L
local PAD, HEADER_Y, VIEWS, CELL_KEYS = PF.PAD, PF.HEADER_Y, PF.VIEWS, PF.CELL_KEYS
local rows, tabs, viewButtons, state = PF.rows, PF.tabs, PF.viewButtons, PF.state
local Settings, Money, View, ItemView = PF.Settings, PF.Money, PF.View, PF.ItemView

-- Positions headers and cells for a view. In the profit view the learn columns only show with
-- unlearned recipes; without them the recipe column takes their space.
local function Layout(view, showLearn)
	local cols = VIEWS[view]
	local extra = 0
	for _, col in ipairs(cols) do
		if col.learn and not showLearn then
			extra = extra + col.width + 8
		end
	end
	local visibleKeys = {}
	local hx, cx = PAD + 42, 42
	for i, col in ipairs(cols) do
		local visible = showLearn or not col.learn
		local width = i == 1 and (col.width + extra) or col.width
		local header = PF.frame.headers[col.key]
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", hx, HEADER_Y)
		header:SetWidth(width)
		header:SetShown(visible)
		visibleKeys[col.key] = visible
		for _, row in ipairs(rows) do
			if i == 1 then
				row.name:SetWidth(width)
				row.status:SetWidth(width)
			else
				local cell = row.cells[col.key]
				cell:ClearAllPoints()
				cell:SetPoint("LEFT", cx, 0)
				cell:SetWidth(width)
			end
		end
		if visible then
			hx, cx = hx + width + 8, cx + width + 8
		end
	end
	-- Hide everything the view doesn't use.
	for key, header in pairs(PF.frame.headers) do
		if not visibleKeys[key] then
			header:Hide()
		end
	end
	for _, row in ipairs(rows) do
		for _, key in ipairs(CELL_KEYS) do
			row.cells[key]:SetShown(visibleKeys[key] or false)
		end
	end
	state.layout = view .. tostring(showLearn)
end

local function UpdateControls()
	local learnView = View() == "learn"
	for key, button in pairs(viewButtons) do
		button:SetSelected(key == View())
	end
	local bagsView = View() == "bags"
	PF.frame.fits:SetShown(learnView)
	local upgradesView = View() == "upgrades"
	PF.frame.showKept:SetShown(bagsView)
	PF.frame.sortBtn:SetShown(bagsView)
	PF.frame.matsOnly:SetShown(bagsView)
	PF.frame.ahLimit:SetShown(bagsView)
	PF.frame.ahLimit:SetLabel(("%s: +%d%%, min %s"):format(L["AH rule"], Settings().ahMinPercent or 20,
		Money(Settings().ahMinCopper or 0)))
	PF.frame.summary:SetPoint("RIGHT", bagsView and PF.frame.ahLimit or PF.frame, bagsView and "LEFT" or "RIGHT", bagsView and -12 or -PAD, 0)
	PF.frame.showDismissed:SetShown(upgradesView)
	PF.frame.musicOn:SetShown(View() == "music")
	PF.frame.partyBtn:SetShown(View() == "music")
	PF.frame.partyBtn:SetLabel(ns.Music.PartyActive() and "Stop party" or "Party!")
	PF.frame.partyBtn:SetSelected(ns.Music.PartyActive())
	local levelView = View() == "level"
	PF.frame.priced:SetShown(not learnView and not levelView and not ItemView())
	PF.frame.unlearned:SetShown(not learnView and not levelView and not ItemView())
	for _, tab in ipairs(tabs) do
		if ItemView() then
			tab:Hide()
		end
	end
end

PF.Layout, PF.UpdateControls = Layout, UpdateControls
