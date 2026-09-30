it("window builds and renders rows without errors", function()
	local ns, stub = LoadAddon({ auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 100, max = 150, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
		[3760] = { info = { name = "Cloak", learned = false }, schematic = stub.Schematic({ { 2319, 5 } }, 3719) },
		[7000] = { info = { name = "Enchant", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, nil) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.ah[2318], stub.ah[2302] = 10, 100
	ns.ToggleProfitFrame()
	local rows = ns.BuildRows(165, true)
	eq(#rows, 3)
	ns.ToggleProfitFrame() -- hide
	ns.ToggleProfitFrame() -- show again
	ns.RefreshProfitFrame()
end)

it("tooltips render for known, trainer, vendor and bundled-only rows", function()
	local ns, stub = LoadAddon({ data = true, auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) },
	} }
	stub.Fire("TRADE_SKILL_SHOW")
	UnitFactionGroup = function() return "Horde" end
	ns.ToggleProfitFrame()
	local rendered = 0
	for _, f in ipairs(stub.frames) do
		if f.data and f.scripts.OnEnter then
			f.scripts.OnEnter(f)
			f.scripts.OnLeave(f)
			rendered = rendered + 1
		end
	end
	assert(rendered > 5, "expected visible rows, got " .. rendered)
	-- sort by every column without errors
	for _, f in ipairs(stub.frames) do
		if f.scripts.OnClick and not f.data and not f.scripts.OnDragStart then f.scripts.OnClick(f) end
	end
	-- scroll
	for _, f in ipairs(stub.frames) do
		if f.scripts.OnMouseWheel then f.scripts.OnMouseWheel(f, -1) end
	end
end)

it("minimap button toggles the window, hides on right-click, /cw minimap restores", function()
	local ns, stub = LoadAddon()
	local btn
	for _, f in ipairs(stub.frames) do if f.scripts.OnDragStart and f.scripts.OnClick and f.scripts.OnEnter then btn = f end end
	assert(btn, "minimap button not created at login")
	btn.scripts.OnClick(btn, "LeftButton") -- opens window
	btn.scripts.OnEnter(btn); btn.scripts.OnLeave(btn)
	btn.scripts.OnDragStart(btn)
	btn.scripts.OnUpdate(btn)
	eq(math.floor(ns.db.minimap.angle + 0.5), 0) -- cursor to the right of the minimap centre
	btn.scripts.OnDragStop(btn)
	btn.scripts.OnClick(btn, "RightButton")
	eq(ns.db.minimap.hide, true); eq(btn:IsShown(), false)
	SlashCmdList.CRAFTWISE("minimap")
	eq(ns.db.minimap.hide, false); eq(btn:IsShown(), true)
	CraftWise_OnAddonCompartmentClick()
end)

it("search filters rows by name", function()
	local ns, stub = LoadAddon({ data = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Handstitched Leather Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.ToggleProfitFrame()
	local box
	for _, f in ipairs(stub.frames) do if f.scripts.OnTextChanged then box = f end end
	box:SetText("boots")
	box.scripts.OnTextChanged(box)
	local visible = 0
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false then
			visible = visible + 1
			assert(f.data.name:lower():find("boots"), "unfiltered row " .. f.data.name)
		end
	end
	assert(visible > 0)
end)

it("gathering professions get no tab; icons come from the client or fallbacks", function()
	local ns, stub = LoadAddon()
	GetProfessions = function() return 1, 2 end
	GetProfessionInfo = function(i) if i == 1 then return "Leatherworking", 136247 end return "Skinning", 134366 end
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.profession = { id = 393, name = "Skinning", skill = 60, max = 75, recipes = {
		[9999] = { info = { name = "Skin", learned = true }, schematic = stub.Schematic({ { 1, 1 } }, 2) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	eq(ns.charDB.professions[165].icon, 136247)
	eq(ns.IsGathering(393), true); eq(ns.IsGathering(165), false)
	eq(ns.ProfessionIcon(12345), 134400)
	ns.ToggleProfitFrame()
	local tabs = 0
	for _, f in ipairs(stub.frames) do
		if f.label and f.icon and f.shown ~= false then tabs = tabs + 1 end
	end
	eq(tabs, 1)
end)

it("learn columns hide when unlearned recipes are hidden", function()
	local ns, stub = LoadAddon({ savedDB = { settings = { includeUnlearned = false } } })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.ToggleProfitFrame()
	local learnHeader
	for _, f in ipairs(stub.frames) do if f.label == "TO LEARN" then learnHeader = f end end
	eq(learnHeader.shown, false)
	ns.db.settings.includeUnlearned = true
	ns.RefreshProfitFrame()
	eq(learnHeader.shown, true)
end)

it("filters: hide unpriced and can-learn-now", function()
	local ns, stub = LoadAddon({ data = true, auctionator = true })
	stub.profession = { id = 165, name = "Leatherworking", skill = 60, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	stub.ah[2318], stub.ah[2302] = 10, 100
	ns.ToggleProfitFrame()
	local function visible()
		local n, rowsSeen = 0, {}
		for _, f in ipairs(stub.frames) do
			if f.data and f.shown ~= false then n = n + 1; rowsSeen[#rowsSeen + 1] = f.data end
		end
		return n, rowsSeen
	end
	ns.db.settings.hideUnpriced = true
	ns.RefreshProfitFrame()
	local n, seen = visible()
	assert(n >= 1)
	for _, r in ipairs(seen) do assert(r.profit, "unpriced row shown") end
	ns.db.settings.hideUnpriced = false
	ns.db.settings.onlyReachable = true
	ns.RefreshProfitFrame()
	n, seen = visible()
	for _, r in ipairs(seen) do assert(r.status == "known" or (r.required and not r.tooLow), "unreachable row shown: " .. r.name) end
end)
