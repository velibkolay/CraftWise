local function setup()
	local ns, stub = LoadAddon()
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[3760] = { info = { name = "Hillman's Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[3761] = { info = { name = "Fine Leather Tunic", learned = false }, schematic = stub.Schematic({ { 2318, 6 } }, 3761) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	return ns, stub
end

it("maps services to recipes by tooltip id, then by name", function()
	local ns, stub = setup()
	stub.trainer = {
		{ name = "Hillman's Cloak", kind = "available", fee = 450, required = 90, tooltipID = 3760 },
		{ name = "Fine Leather Tunic", kind = "unavailable", fee = 900, required = 120 },
		{ name = "Unknown Thing", kind = "available", fee = 1, required = 1 },
		{ name = "Header", kind = "header" },
	}
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[3760].fee, 450); eq(ns.db.trainer[3760].required, 90)
	eq(ns.db.trainer[3761].fee, 900)
	local n = 0
	for _ in pairs(ns.db.trainer) do n = n + 1 end
	eq(n, 2)
end)

it("ignores tooltip ids that are not cached recipes and falls back to name", function()
	local ns, stub = setup()
	stub.trainer = { { name = "Hillman's Cloak", kind = "available", fee = 450, required = 90, tooltipID = 99999 } }
	stub.Fire("TRAINER_SHOW")
	eq(ns.db.trainer[3760].fee, 450); eq(ns.db.trainer[99999], nil)
end)
