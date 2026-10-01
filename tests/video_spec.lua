local function setup()
	local ns, stub = LoadAddon()
	stub.profession = { id = 356, name = "Fishing", skill = 10, max = 75, recipes = {} }
	stub.spells[7620] = "Fishing"
	CraftWiseMusicVideos = { Clip = { path = "V\\Clip\\", sheets = 2, frames = 30, fps = 10, cols = 5, rows = 5,
		width = 192, height = 190, size = 1024 } }
	ns.Video.SetVideo("Fishing", "Clip")
	return ns, stub
end

it("maps frames to sheets and texture coordinates", function()
	local ns = setup()
	local v = CraftWiseMusicVideos.Clip
	local sheet, l, r, t, b = ns.Video.FrameCoords(v, 0)
	eq(sheet, 1); eq(l, 0); eq(r, 192 / 1024); eq(t, 0); eq(b, 190 / 1024)
	sheet, l, r, t, b = ns.Video.FrameCoords(v, 26) -- second sheet, frame 1 (col 1, row 0)
	eq(sheet, 2); eq(l, 192 / 1024); eq(t, 0)
	sheet, l, r, t, b = ns.Video.FrameCoords(v, 7) -- col 2, row 1
	eq(sheet, 1); eq(l, 384 / 1024); eq(t, 190 / 1024)
end)

it("shows the window while casting, advances frames, and resumes at the saved frame", function()
	local ns, stub = setup()
	stub.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "f1", 7620)
	assert(CraftWiseVideoFrame.shown, "window shown")
	ns.Video.Tick(0.35) -- 3 frames at 10 fps
	eq(ns.Video.Current().frame, 3)
	stub.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "f1", 7620)
	eq(CraftWiseVideoFrame.shown, false)
	eq(ns.db.music.videoPos.Clip, 3)
	stub.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "f2", 7620)
	eq(ns.Video.Current().frame, 3)
	ns.Video.Tick(2.75) -- wraps after 30 frames
	eq(ns.Video.Current().frame, 0)
end)

it("preview doesn't save a position and the picker lists videos", function()
	local ns, stub = setup()
	ns.Video.Preview("Clip")
	ns.Video.Tick(0.5)
	ns.Video.Stop()
	eq(ns.db.music.videoPos, nil)
	ns.db.settings.view = "music"
	ns.ToggleProfitFrame()
	local row
	for _, f in ipairs(stub.frames) do
		if f.data and f.shown ~= false and f.data.name == "Fishing" then row = f end
	end
	row.scripts.OnClick(row, "LeftButton")
	local picker = CraftWiseSongPicker
	eq(picker.videos[2].pick.selected, true) -- Clip chosen
	picker.videos[1].pick.scripts.OnClick(picker.videos[1].pick)
	eq(ns.db.music.professions.Fishing.video, nil)
end)
