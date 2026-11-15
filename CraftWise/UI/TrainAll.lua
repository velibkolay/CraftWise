-- "Train all" at a class trainer (issue #259, the pattern of the merchant bulk buy, #201): a button on the
-- trainer window opens a confirmation that lists the spells and the total cost; the confirmation's button is
-- the only thing that buys, one BuyTrainerService per spell (ClassSpells.lua decides and buys). Nothing is
-- bought on opening a trainer or by any timer. Settings: db.settings.trainAll (default on).
local _, ns = ...
local Style, L = ns.Style, ns.L

local TA = {}
ns.TrainAll = TA

TA.WIDTH = 280
local button, panel, current

function TA.Enabled()
	return not (ns.db and ns.db.settings and ns.db.settings.trainAll == false)
end

function TA.Hide()
	current = nil
	if panel then
		panel:Hide()
	end
end

-- The confirmation: the spells and the total, with Train and Cancel.
function TA.Confirm(plan)
	if not panel then
		return
	end
	current = plan
	panel.lines:SetText(table.concat(ns.ClassSpells.ConfirmLines(plan), "\n"))
	local count = #plan.lines
	panel.total:SetText((count == 1 and L["1 spell"] or (L["%d spells"]):format(count)) .. " · " .. ns.FormatCoins(plan.total))
	panel.note:SetText(plan.skipped > 0 and (L["%d more you can't afford yet are left out"]):format(plan.skipped) or "")
	panel.go:SetText(L["Train"])
	panel:SetHeight(110 + math.min(count, ns.ClassSpells.MAX_CONFIRM_LINES + 1) * 14)
	panel:Show()
end

-- Opening the confirmation. Reads the trainer; says why when there is nothing to buy.
function TA.Open()
	local plan, why = ns.ClassSpells.TrainPlan()
	if not plan then
		TA.Hide()
		ns.Print((why or L["Train all isn't available"]) .. ".")
		return nil
	end
	TA.Confirm(plan)
	return plan
end

-- The confirmation's click: buys the listed spells.
function TA.Go()
	local plan = current
	TA.Hide()
	if not plan then
		return 0
	end
	local bought, spent, why = ns.ClassSpells.TrainAll(plan)
	if bought > 0 then
		ns.Print((L["Training %d spells for %s."]):format(bought, ns.FormatCoins(spent)))
	end
	if why then
		ns.Print(why .. ".")
	end
	return bought
end

local function Create()
	if button or not ClassTrainerFrame then
		return
	end
	button = Style.ActionButton(ClassTrainerFrame, L["Train all"], 90, 22)
	button:SetPoint("TOPRIGHT", ClassTrainerFrame, "TOPRIGHT", -40, -30)
	button:SetFrameLevel((ClassTrainerFrame:GetFrameLevel() or 1) + 5)
	button:SetScript("OnClick", TA.Open)
	panel = CreateFrame("Frame", "CraftWiseTrainAll", ClassTrainerFrame)
	panel:SetSize(TA.WIDTH, 160)
	panel:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", 4, -30)
	panel:SetFrameLevel((ClassTrainerFrame:GetFrameLevel() or 1) + 10)
	panel.sheet = Style.Sheet(panel, nil, nil, 10, true)
	panel.title = Style.Text(panel, "Small", "text3")
	panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
	panel.title:SetText("CraftWise · " .. L["Train all"])
	panel.lines = Style.Text(panel, "Body", "text")
	panel.lines:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -30)
	panel.lines:SetWidth(TA.WIDTH - 24)
	panel.lines:SetJustifyH("LEFT")
	panel.total = Style.Text(panel, "BodyBold", "text")
	panel.total:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 44)
	panel.note = Style.Text(panel, "Small", "text3")
	panel.note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 30)
	panel.note:SetWidth(TA.WIDTH - 24)
	panel.note:SetJustifyH("LEFT")
	panel.go = Style.ActionButton(panel, L["Train"], 100, 24)
	panel.go:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 8)
	panel.go:SetScript("OnClick", TA.Go)
	panel.cancel = Style.ActionButton(panel, L["Cancel"], 80, 24)
	panel.cancel:SetPoint("LEFT", panel.go, "RIGHT", 8, 0)
	panel.cancel:SetScript("OnClick", TA.Hide)
	panel:Hide()
	TA.button, TA.panel = button, panel
end

-- Shows the button at a class trainer only (not at profession or pet trainers).
function TA.Update()
	Create()
	if not button then
		return
	end
	local show = TA.Enabled() and ns.ClassSpells.TrainerOpen() and ns.ClassSpells.IsClassTrainer()
	button:SetShown(show and true or false)
	if not show then
		TA.Hide()
	end
end

ns.On("TRAINER_SHOW", function()
	TA.Hide()
	TA.Update()
end)
ns.On("TRAINER_UPDATE", function()
	TA.Update()
end)
ns.On("TRAINER_CLOSED", function()
	TA.Hide()
end)
