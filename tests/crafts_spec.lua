local function setup()
	local ns, stub = LoadAddon()
	stub.profession = { id = 165, name = "Leatherworking", skill = 50, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true, relativeDifficulty = 1 }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.Fire("SKILL_LINES_CHANGED") -- first sighting: skill 50
	return ns, stub
end

it("counts a craft followed by a skill update as a skill-up at the skill it was made", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	stub.profession.skill = 51
	stub.Fire("SKILL_LINES_CHANGED")
	local n, ups = ns.SkillUpStats(2149, 50)
	eq(n, 1); eq(ups, 1)
	eq(ns.db.skillups[2149][50].d, 1)
end)

it("counts a craft without a skill update as no skill-up once it settles", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	eq((ns.SkillUpStats(2149, 50)), 0) -- still waiting
	stub.now = stub.now + 3
	ns.SettleCrafts()
	local n, ups = ns.SkillUpStats(2149, 50)
	eq(n, 1); eq(ups, 0)
end)

it("pairs a skill update that arrives before the craft event", function()
	local ns, stub = setup()
	stub.profession.skill = 51
	stub.Fire("SKILL_LINES_CHANGED")
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	local n, ups = ns.SkillUpStats(2149, 50)
	eq(n, 1); eq(ups, 1)
end)

it("ignores other units, unknown spells and secret spell ids", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 2149)
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 12345)
	issecretvalue = function() return true end
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	issecretvalue = nil
	stub.now = stub.now + 3
	ns.SettleCrafts()
	eq(ns.CraftsRecorded(), 0)
end)

it("adds up recorded crafts over all skills and reads bundled thresholds", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	stub.profession.skill = 51
	stub.Fire("SKILL_LINES_CHANGED")
	stub.now = stub.now + 5
	stub.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2149)
	stub.now = stub.now + 3
	ns.SettleCrafts()
	local n, ups = ns.SkillUpStats(2149)
	eq(n, 2); eq(ups, 1)
	eq(ns.CraftsRecorded(), 2)
	ns.Thresholds = { [2149] = { 40, 70 } }
	local y, g = ns.RecipeThresholds(2149)
	eq(y, 40); eq(g, 70)
end)
