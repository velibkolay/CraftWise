-- Skill-up chance next to every recipe in the game's profession window (issue #15).
-- Same numbers as the Level view (Leveling.lua): orange 100%, measured rates from your recorded
-- crafts, "~" for the community formula estimate. Grey and unlearned recipes show nothing.
-- Hooks the recipe list's ScrollBox (Blizzard_Professions, loaded on demand) and only adds its own
-- font string to each row; Blizzard's row code is left alone.
local _, ns = ...

local hooked = false
local scrollBox
local RefreshRows

local GOOD = "|cff4fd18c"
local ESTIMATE = "|cffffb347"

local function Skill()
	local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	if base and base.skillLevel and not (issecretvalue and issecretvalue(base.skillLevel)) then
		return base.skillLevel, base.professionID
	end
	return nil, base and base.professionID
end

-- Chance text for a recipe, or nil when there's nothing to show.
function ns.RecipeChanceText(recipeID, difficulty, skill)
	if not (ns.Leveling and recipeID) then
		return nil
	end
	local p, info = ns.Leveling.Chance(recipeID, difficulty, skill, ns.Leveling.CachedPools())
	if not p or p <= 0 then
		return nil, info
	end
	local pct = math.floor(p * 100 + 0.5)
	if info.kind == "formula" then
		return ESTIMATE .. "~" .. pct .. "%|r", info, p
	end
	return GOOD .. pct .. "%|r", info, p
end

local labels = setmetatable({}, { __mode = "k" }) -- [row button] = our font string
ns.RecipeChanceLabels = labels

local function Label(button)
	local t = labels[button]
	if not t then
		t = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		t:SetPoint("RIGHT", button, "RIGHT", -4, 0)
		t:SetJustifyH("RIGHT")
		labels[button] = t
	end
	return t
end

local function UpdateRow(_, button, node)
	if not (button and node and node.GetData) then
		return
	end
	local data = node:GetData()
	local info = data and data.recipeInfo
	local text
	if info and info.learned and info.recipeID and not (issecretvalue and issecretvalue(info.recipeID)) then
		text = ns.RecipeChanceText(info.recipeID, info.relativeDifficulty, (Skill()))
	end
	if not text then
		if labels[button] then
			labels[button]:Hide()
		end
		return
	end
	local label = Label(button)
	label:SetText(text)
	label:Show()
	-- Keep the recipe name clear of the percentage.
	if button.Label and button.Label.GetWidth and button.GetWidth then
		local room = button:GetWidth() - label:GetStringWidth() - 12
			- (button.SkillUps and button.SkillUps:GetWidth() or 0)
			- (button.Count and button.Count:IsShown() and button.Count:GetStringWidth() or 0)
		if room > 40 and button.Label:GetWidth() > room then
			button.Label:SetWidth(room)
		end
	end
end

-- Hovering a recipe: where the chance comes from.
local KIND_TEXT = {
	orange = "orange: every craft gives a point",
	recipe = "your crafts of this recipe at this stage",
	stage = "your crafts of all recipes at this stage",
	color = "your crafts at this colour",
	formula = "estimate, community formula (not official)",
}

local function OnRecipeEnter(_, button, data)
	local info = data and data.recipeInfo
	if not (info and info.learned and button) then
		return
	end
	local text, how = ns.RecipeChanceText(info.recipeID, info.relativeDifficulty, (Skill()))
	if not text then
		return
	end
	if not GameTooltip:IsOwned(button.Label or button) then
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:AddLine(info.name or "", 1, 1, 1)
	end
	GameTooltip:AddDoubleLine("CraftWise: skill-up chance", text, 0.31, 0.7, 1, 1, 1, 1)
	local detail = KIND_TEXT[how.kind] or ""
	if how.n and how.kind ~= "formula" then
		detail = ("%s (%d of %d)"):format(detail, how.ups, how.n)
	end
	GameTooltip:AddLine(detail, 0.6, 0.6, 0.65, true)
	GameTooltip:Show()
end

local function Hook()
	if hooked then
		return true
	end
	local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
	scrollBox = list and list.ScrollBox
	if not (scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then
		return false
	end
	hooked = true
	ScrollUtil.AddInitializedFrameCallback(scrollBox, UpdateRow, ns)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("Professions.RecipeListOnEnter", OnRecipeEnter, ns)
	end
	RefreshRows()
	return true
end
ns.HookRecipeChance = Hook

RefreshRows = function()
	if scrollBox and scrollBox.ForEachFrame then
		scrollBox:ForEachFrame(function(button, node)
			UpdateRow(nil, button, node)
		end)
	end
end

ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_Professions" then
		Hook()
	end
end)
ns.On("PLAYER_LOGIN", Hook)
ns.On("TRADE_SKILL_SHOW", Hook)
ns.Listen("SKILLUPS_CHANGED", RefreshRows)
ns.On("SKILL_LINES_CHANGED", RefreshRows)
