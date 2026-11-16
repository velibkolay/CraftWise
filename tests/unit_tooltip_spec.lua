-- Interface › Tooltips (#321 part 3): the unit's target and the guild rank on a unit tooltip.
local function setup()
	local ns, stub = LoadAddon()
	local post
	local registered = 0
	TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) registered = registered + 1; post = fn end }
	Enum.TooltipDataType = { Unit = 2, Item = 0 }
	local lines = {}
	GameTooltip = { }
	function GameTooltip:GetName() return "GameTooltip" end
	function GameTooltip:NumLines() return #lines end
	local function add(left, right)
		lines[#lines + 1] = left
		_G["GameTooltipTextLeft" .. #lines] = { text = left, GetText = function(self) return self.text end, SetText = function(self, t) self.text = t end }
	end
	function GameTooltip:AddLine(t) add(t) end
	function GameTooltip:AddDoubleLine(l, r) add(l .. " " .. r) end
	TooltipUtil = { GetDisplayedUnit = function() return "Someone", "mouseover", "g" end }
	stub.names.mouseover = "Someone"; stub.names.mouseovertarget = "Target Dummy"
	UnitExists = function(u) return stub.names[u] ~= nil end
	UnitIsPlayer = function() return false end
	UnitIsUnit = function() return false end
	GetGuildInfo = function() return "Test Guild", "Officer", 2 end
	add("Someone"); add("<Test Guild>"); add("Level 60")
	local function lineText(i) return _G["GameTooltipTextLeft" .. i].text end
	return ns, stub, function() return post end, function() return registered end, lines, lineText, add
end

it("unit tooltip: both off registers nothing and adds nothing", function()
	local ns, _, post, registered = setup()
	ns.UnitTooltip.Apply()
	eq(registered(), 0)
	eq(post(), nil)
end)

it("unit tooltip: target line once, 'you' for the player, nothing without a target", function()
	local ns, stub, post, registered, lines = setup()
	ns.UnitTooltip.Set("tipTarget", true)
	eq(registered(), 1)
	local n = #lines
	post()(GameTooltip, {})
	eq(#lines, n + 1); eq(lines[#lines], "Target: Target Dummy")
	post()(GameTooltip, {}) -- the same tooltip drawn again: still one line
	eq(#lines, n + 1)
	stub.names.mouseovertarget = nil
	local nn = #lines
	for i = #lines, n + 1, -1 do lines[i] = nil end
	post()(GameTooltip, {})
	eq(#lines, n, "no target, no line")
	stub.names.mouseovertarget = "Me"
	UnitIsUnit = function(a, b) return b == "player" end
	post()(GameTooltip, {})
	eq(lines[#lines], "Target: you")
end)

it("unit tooltip: the guild rank goes after the guild name once, only for players", function()
	local ns, _, post, _, lines, lineText = setup()
	ns.UnitTooltip.Set("tipGuildRank", true)
	post()(GameTooltip, {})
	eq(lineText(2), "<Test Guild>", "not a player: untouched")
end)

it("unit tooltip: guild rank for a player", function()
	local ns, _, post, _, lines, lineText = setup()
	UnitIsPlayer = function() return true end
	ns.UnitTooltip.Set("tipGuildRank", true)
	post()(GameTooltip, {})
	eq(lineText(2), "<Test Guild> - Officer")
	post()(GameTooltip, {})
	eq(lineText(2), "<Test Guild> - Officer", "added once")
	eq(lineText(1), "Someone"); eq(lineText(3), "Level 60")
end)
