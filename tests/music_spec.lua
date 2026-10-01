local function setup(mode)
	local ns, stub = LoadAddon()
	stub.profession = { id = 393, name = "Skinning", skill = 30, max = 75, recipes = {} }
	stub.spells[8613] = "Skinning"
	CraftWiseMusicSongs = { Song = { path = "Interface\\AddOns\\CraftWise_Music\\Song\\", chunks = 3, length = 2 },
		Other = { path = "P\\", chunks = 1, length = 5 } }
	ns.Music.CycleSong("Skinning") -- none -> Other (sorted)
	ns.Music.CycleSong("Skinning") -- Other -> Song
	if mode == "restart" then ns.Music.ToggleMode("Skinning") end
	return ns, stub
end

local function last(stub) return stub.sounds[#stub.sounds] end

it("plays chunks while skinning, stops when the cast ends, resumes at the stopped chunk", function()
	local ns, stub = setup()
	eq(ns.db.music.professions.Skinning.song, "Song")
	stub.Fire("UNIT_SPELLCAST_START", "player", "cast1", 8613)
	eq(last(stub).file, "Interface\\AddOns\\CraftWise_Music\\Song\\001.ogg")
	eq(last(stub).channel, "Master")
	stub.RunTimers()
	eq(last(stub).file:sub(-7), "002.ogg")
	stub.Fire("UNIT_SPELLCAST_STOP", "player", "cast1", 8613)
	eq(last(stub).stopped, true)
	eq(ns.db.music.position.Song, 2)
	stub.RunTimers() -- cancelled timer must not play anything
	eq(#stub.sounds, 2)
	stub.Fire("UNIT_SPELLCAST_START", "player", "cast2", 8613)
	eq(last(stub).file:sub(-7), "002.ogg")
	stub.RunTimers(); stub.RunTimers()
	eq(last(stub).file:sub(-7), "001.ogg") -- loops after the last chunk
end)

it("restart mode starts from the first chunk every cast", function()
	local ns, stub = setup("restart")
	stub.Fire("UNIT_SPELLCAST_START", "player", "c", 8613)
	stub.RunTimers()
	stub.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "c", 8613)
	stub.Fire("UNIT_SPELLCAST_START", "player", "d", 8613)
	eq(last(stub).file:sub(-7), "001.ogg")
	eq(ns.db.music.position.Song, nil)
end)

it("ignores other units, other casts failing, other spells and turned-off music", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_START", "target", "x", 8613)
	stub.Fire("UNIT_SPELLCAST_START", "player", "x", 133) -- not a profession
	eq(#stub.sounds, 0)
	stub.Fire("UNIT_SPELLCAST_START", "player", "c", 8613)
	stub.Fire("UNIT_SPELLCAST_FAILED", "player", "other", 133) -- pressing another spell mid-cast
	eq(last(stub).stopped, nil)
	stub.Fire("UNIT_SPELLCAST_STOP", "player", "c", 8613)
	ns.db.music.enabled = false
	stub.Fire("UNIT_SPELLCAST_START", "player", "e", 8613)
	eq(#stub.sounds, 1)
end)

it("plays for crafting recipes of a profession and cycles back to no song", function()
	local ns, stub = setup()
	stub.profession = { id = 165, name = "Leatherworking", skill = 50, max = 75, recipes = {
		[2149] = { info = { name = "Boots", learned = true }, schematic = stub.Schematic({ { 2318, 2 } }, 2302) } } }
	stub.Fire("TRADE_SKILL_SHOW")
	ns.Music.CycleSong("Leatherworking")
	stub.Fire("UNIT_SPELLCAST_START", "player", "c", 2149)
	eq(last(stub).file, "P\\001.ogg")
	ns.Music.CycleSong("Leatherworking") -- Other -> Song stops current
	eq(last(stub).stopped, true)
	ns.Music.CycleSong("Leatherworking") -- Song -> none
	eq(ns.db.music.professions.Leatherworking.song, nil)
end)

it("music view renders professions; clicks cycle song and toggle mode", function()
	local ns, stub = setup()
	ns.db.settings.view = "music"
	ns.ToggleProfitFrame()
	local row
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.name == "Skinning" then row = f end
	end
	eq(row.data.song, "Song")
	row.scripts.OnEnter(row)
	row.scripts.OnClick(row, "RightButton")
	eq(ns.db.music.professions.Skinning.mode, "restart")
	row.scripts.OnClick(row, "LeftButton")
	eq(ns.db.music.professions.Skinning.song, nil)
end)
