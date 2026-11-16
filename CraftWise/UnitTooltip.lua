-- Interface › Tooltips (#321 part 3): two lines on a unit tooltip, both off by default
-- (db.settings.interface.tipTarget, tipGuildRank). While both are off nothing is registered.
--   Target: a "Target: <name>" line with what the unit is targeting.
--   Guild rank: the rank after the guild name on the "<Guild>" line.
--
-- "Hold Shift to see a tooltip that is hidden in combat" is left out on purpose: CraftWise hides no
-- tooltip in combat, so there is nothing to reveal.
--
-- Built from Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`), nothing from another
-- addon:
--   Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua: TooltipDataProcessor.AddTooltipPostCall(type, fn)
--     with Enum.TooltipDataType.Unit (fn(tooltip, data); how TooltipDataRules.lua adds its own unit rules).
--   Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua: TooltipUtil.GetDisplayedUnit(tooltip) -> name, unit, guid.
--   Blizzard_UIPanels_Game/Mainline/TabardFrame.lua: GetGuildInfo(unit) -> guildName, rankName, rankIndex.
-- The post call runs each time the tooltip is built, on a cleared tooltip, so a line is added once. A
-- value the client marks secret (issecretvalue) is never read.
local _, ns = ...

local UT = {}
ns.UnitTooltip = UT

local registered = false

local function Settings()
	local s = ns.db and ns.db.settings
	if not s then
		return {}
	end
	s.interface = s.interface or {}
	return s.interface
end

local function On(key)
	return Settings()[key] == true
end

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Text(tooltip, i)
	local line = _G[(tooltip:GetName() or "GameTooltip") .. "TextLeft" .. i]
	return line, line and line:GetText()
end

-- The rank is added to the "<Guild>" line (the line holding the guild name, in the first lines), once.
function UT.AddGuildRank(tooltip, unit)
	local guild, rank = GetGuildInfo(unit)
	if Secret(guild) or Secret(rank) or type(guild) ~= "string" or type(rank) ~= "string" or rank == "" then
		return false
	end
	for i = 2, math.min(4, tooltip:NumLines() or 0) do
		local line, text = Text(tooltip, i)
		if type(text) == "string" and not Secret(text) and text:find(guild, 1, true) then
			if text:find(" - " .. rank, 1, true) then
				return false -- already there
			end
			line:SetText(text .. " - " .. rank)
			return true
		end
	end
	return false
end

-- "Target: <name>" under the last line; "you" when the unit targets the player.
function UT.AddTarget(tooltip, unit)
	local target = unit .. "target"
	if not UnitExists(target) then
		return false
	end
	local name = UnitName(target)
	if Secret(name) or type(name) ~= "string" then
		return false
	end
	local label = ns.L["Target:"]
	for i = 1, tooltip:NumLines() or 0 do
		local _, text = Text(tooltip, i)
		if type(text) == "string" and not Secret(text) and text:find(label, 1, true) == 1 then
			return false -- once
		end
	end
	local r, g, b = 1, 1, 1
	local colors = RAID_CLASS_COLORS
	if UnitIsPlayer(target) and colors then
		local _, classFile = UnitClass(target)
		local c = classFile and colors[classFile]
		if c then
			r, g, b = c.r, c.g, c.b
		end
	end
	if UnitIsUnit(target, "player") then
		name = ns.L["you"]
	end
	tooltip:AddDoubleLine(label, name, 0.7, 0.7, 0.7, r, g, b)
	return true
end

local function OnUnitTooltip(tooltip, data)
	if tooltip ~= GameTooltip or not data then
		return
	end
	local _, unit = TooltipUtil.GetDisplayedUnit(tooltip)
	if not unit or Secret(unit) then
		return
	end
	if On("tipGuildRank") and UnitIsPlayer(unit) then
		UT.AddGuildRank(tooltip, unit)
	end
	if On("tipTarget") then
		UT.AddTarget(tooltip, unit)
	end
end
UT.OnUnitTooltip = OnUnitTooltip

function UT.Apply()
	if not registered and (On("tipTarget") or On("tipGuildRank"))
		and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		registered = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
	end
end

function UT.Settings()
	return Settings()
end

function UT.Set(key, value)
	Settings()[key] = value and true or false
	UT.Apply()
end

ns.On("PLAYER_LOGIN", UT.Apply)
