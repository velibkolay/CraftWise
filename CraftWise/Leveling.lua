-- Leveling view (issue #15): which known recipe levels a profession for the least money.
--
-- For every learned recipe at your current skill:
--   chance p      chance that one craft gives a skill point (see Chance below)
--   cost C        reagents at the cheapest buy price (vendor or AH), as in the Profit view
--   sale S        what the crafted item brings: AH price after the 5% cut when the AH rule says
--                 the AH is worth it (and the item isn't soulbound), otherwise the vendor price
--   net           C - S per craft (negative = the craft makes money)
--   crafts/point  1 / p
--   per point     net / p = expected money spent (or earned, when negative) per skill point
-- Rows are ranked by "per point", lowest first. Nothing is guessed: a recipe without a chance or
-- without reagent prices is listed last with the reason.
local _, ns = ...

local Leveling = {}
ns.Leveling = Leveling

Leveling.MIN_CRAFTS = 5 -- recorded crafts needed before a rate counts
Leveling.BINS = 4 -- stages between the yellow and the grey threshold

-- Position between the yellow (f = 1) and the grey threshold (f -> 0), in BINS stages.
-- Stage 1 = closest to yellow (best chance), stage BINS = closest to grey.
function Leveling.Stage(skill, yellow, grey)
	if not (skill and yellow and grey) or grey <= yellow or skill < yellow or skill >= grey then
		return nil
	end
	local f = (grey - skill) / (grey - yellow) -- (0, 1]
	local stage = Leveling.BINS - math.ceil(f * Leveling.BINS) + 1
	return math.max(1, math.min(Leveling.BINS, stage))
end

-- Recorded crafts pooled three ways: per recipe and stage, per stage (all recipes), per client
-- colour (yellow 1 / green 2) for recipes without thresholds.
local function Pools()
	local byRecipeStage, byStage, byColor = {}, {}, {}
	local function add(t, key, n, ups)
		local e = t[key] or { n = 0, ups = 0 }
		t[key] = e
		e.n, e.ups = e.n + n, e.ups + ups
	end
	for recipeID, bySkill in pairs(ns.db and ns.db.skillups or {}) do
		local yellow, grey = ns.RecipeThresholds(recipeID)
		for skill, e in pairs(bySkill) do
			local stage = Leveling.Stage(skill, yellow, grey)
			if stage then
				add(byRecipeStage, recipeID .. ":" .. stage, e.n, e.ups)
				add(byStage, stage, e.n, e.ups)
			end
			if e.d == 1 or e.d == 2 then
				add(byColor, e.d, e.n, e.ups)
			end
		end
	end
	return { recipeStage = byRecipeStage, stage = byStage, color = byColor }
end
Leveling.Pools = Pools

-- Chance of a skill point from one craft, and where it comes from.
-- Returns p (0..1 or nil), info = { kind, n, ups, stage }
--   orange: below the recipe's yellow threshold (or client says orange) -> always a point
--   grey:   at or above the grey threshold (or client says grey) -> never
--   recipe: your own crafts of this recipe at the same stage (at least MIN_CRAFTS)
--   stage:  all your crafts of any recipe at the same stage
--   color:  all your crafts at the same client colour (recipes without thresholds)
--   formula: none of the above has enough crafts: community formula (grey - skill) / (grey - yellow)
--            (SkillUp Forever, Skillet; not official). Shown as an estimate, chosen by Veli
--            2026-10-05 so every recipe gets a %; your own crafts replace it once recorded.
function Leveling.Formula(skill, yellow, grey)
	if not (skill and yellow and grey) or grey <= yellow or skill < yellow or skill >= grey then
		return nil
	end
	return (grey - skill) / (grey - yellow)
end

function Leveling.Chance(recipeID, difficulty, skill, pools)
	pools = pools or Pools()
	local yellow, grey = ns.RecipeThresholds(recipeID)
	if yellow and skill then
		if skill >= grey then
			return 0, { kind = "grey" }
		elseif skill < yellow then
			return 1, { kind = "orange" }
		end
		local stage = Leveling.Stage(skill, yellow, grey)
		local own = pools.recipeStage[recipeID .. ":" .. stage]
		if own and own.n >= Leveling.MIN_CRAFTS then
			return own.ups / own.n, { kind = "recipe", n = own.n, ups = own.ups, stage = stage }
		end
		local all = pools.stage[stage]
		if all and all.n >= Leveling.MIN_CRAFTS then
			return all.ups / all.n, { kind = "stage", n = all.n, ups = all.ups, stage = stage }
		end
		return Leveling.Formula(skill, yellow, grey), { kind = "formula", n = all and all.n or 0, stage = stage,
			skill = skill, yellow = yellow, grey = grey }
	end
	if difficulty == 0 then
		return 1, { kind = "orange" }
	elseif difficulty == 3 then
		return 0, { kind = "grey" }
	elseif difficulty == 1 or difficulty == 2 then
		local c = pools.color[difficulty]
		if c and c.n >= Leveling.MIN_CRAFTS then
			return c.ups / c.n, { kind = "color", n = c.n, ups = c.ups, color = difficulty }
		end
		return nil, { kind = "nodata", n = c and c.n or 0 }
	end
	return nil, { kind = "nodata", n = 0 }
end

local function Soulbound(itemID)
	local getInfo = C_Item and C_Item.GetItemInfo
	return getInfo and select(14, getInfo(itemID)) == 1 or false -- bindType 1 = bind on pickup
end

-- What one craft's output brings, by the same rule as the Bags view.
-- Returns copper (nil when unknown), source "auction" | "vendor" | "none", details
function Leveling.Sale(output)
	if not output then
		return 0, "none", {}
	end
	local q = output.quantity or 1
	local each = ns.GetVendorSellPrice(output.itemID)
	local vendor = each and each > 0 and math.floor(each * q) or nil
	local ah = not Soulbound(output.itemID) and ns.GetAuctionPrice(output.itemID) or nil
	local ahNet = ah and math.floor(ah * (1 - ns.AH_CUT) * q) or nil
	local details = { vendor = vendor, ahNet = ahNet, ahGross = ah and math.floor(ah * q) or nil }
	if ahNet and (not vendor or ns.AuctionWorthIt(ahNet, vendor)) then
		return ahNet, "auction", details
	elseif vendor then
		return vendor, "vendor", details
	end
	return nil, "unknown", details
end

-- Current skill: the client's live value, else what the profession window showed last.
function ns.ProfessionSkill(professionID)
	local live = ns.LiveSkill and ns.LiveSkill(professionID)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	return live or (prof and prof.skill)
end

function ns.LevelingRows(professionID)
	local prof = ns.charDB and ns.charDB.professions[professionID]
	if not prof then
		return {}, nil
	end
	local skill = ns.ProfessionSkill(professionID)
	local pools = Pools()
	local rows = {}
	for _, r in ipairs(ns.BuildRows(professionID, false)) do
		local recipe = prof.recipes[r.recipeID] or {}
		local p, info = Leveling.Chance(r.recipeID, recipe.difficulty, skill, pools)
		if info.kind ~= "grey" then
			local output = recipe.output
			if not output and r.outputItemID then
				output = select(2, ns.BundledRecipe(r.recipeID))
			end
			local sale, saleSource, saleDetails = Leveling.Sale(not r.noItemOutput and output or nil)
			r.chance, r.chanceInfo = p, info
			r.saleValue, r.saleSource, r.saleDetails = sale, saleSource, saleDetails
			r.thresholdYellow, r.thresholdGrey = ns.RecipeThresholds(r.recipeID)
			if r.costComplete then
				r.net = r.cost - (sale or 0)
				if p and p > 0 then
					r.craftsPerPoint = 1 / p
					r.perPoint = r.net / p
				end
			end
			rows[#rows + 1] = r
		end
	end
	return rows, skill
end
