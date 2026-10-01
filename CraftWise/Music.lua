-- Profession music (issue #17): a song per profession that plays while you cast it.
-- The client can't seek inside a sound, so songs are split into short chunks played in sequence;
-- "resume" remembers the chunk where it stopped, "restart" starts from the first chunk each cast.
--
-- Songs live in a separate addon folder the player owns, CraftWise_Music (made by
-- tools/music_split.py), so CraftWise updates never delete them. It defines:
--   CraftWiseMusicSongs = { [name] = { path = "Interface\\AddOns\\CraftWise_Music\\name\\", chunks = n,
--     length = seconds per chunk, last = seconds of the last chunk,
--     full = path of the whole song (.ogg), duration = its seconds } }
-- Resume plays the chunks; start-over and party play the full file, so they never stutter.
local _, ns = ...

local Music = {}
ns.Music = Music

local FADE_MS = 250

-- Volume per profession: PlaySoundFile has no volume argument, so songs play on the Dialog channel
-- and its volume is set while one plays, then put back (also after a crash, at the next login).
local CHANNEL = "Dialog"
local VOLUME_CVAR, ENABLE_CVAR = "Sound_DialogVolume", "Sound_EnableDialog"

local function GetCV(name)
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
end

local function SetCV(name, value)
	if C_CVar and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, name, value)
	end
end
local playing -- { profession, song, index, handle, token }
local token = 0

-- English gathering spell names that differ from the profession name.
local SPELL_ALIASES = { ["Herb Gathering"] = "Herbalism" }

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- Where players drop song files. Files added while the game runs are seen after a restart.
Music.FOLDER = "Interface\\AddOns\\CraftWise_Music\\Songs\\"
Music.FOLDER_TEXT = "World of Warcraft/_classic_beta_/Interface/AddOns/CraftWise_Music/Songs"

local function Settings()
	return ns.db and ns.db.music
end

-- Chunked songs (tools/music_split.py, can resume) plus whole files added by name (play from the start).
function Music.Songs()
	local songs = {}
	for name, song in pairs(type(CraftWiseMusicSongs) == "table" and CraftWiseMusicSongs or {}) do
		songs[name] = song
	end
	for name, file in pairs(ns.db and ns.db.music and ns.db.music.files or {}) do
		if not songs[name] then
			songs[name] = { file = Music.FOLDER .. file, whole = true }
		end
	end
	return songs
end

-- Add a file from the Songs folder by its name. The client confirms it exists by queueing it;
-- it is stopped at once. Returns the song name, or nil and the reason.
function Music.AddFile(fileName)
	fileName = (fileName or ""):match("^%s*(.-)%s*$"):gsub("[/\\]", "")
	if fileName == "" then
		return nil, "Type the file name, e.g. mysong.mp3"
	end
	if not (fileName:lower():match("%.mp3$") or fileName:lower():match("%.ogg$")) then
		return nil, "Only .mp3 and .ogg files play in WoW."
	end
	local ok, willPlay, handle = pcall(PlaySoundFile, Music.FOLDER .. fileName, "Master")
	if ok and handle and StopSound then
		pcall(StopSound, handle)
	end
	if not (ok and willPlay) then
		return nil, "Not found. Check the name, and restart the game after adding files."
	end
	local name = fileName:gsub("%.%w+$", "")
	local s = Settings()
	s.files = s.files or {}
	s.files[name] = fileName
	ns.Notify("MUSIC_CHANGED")
	return name
end

function Music.RemoveFile(name)
	local s = Settings()
	if s and s.files and s.files[name] then
		s.files[name] = nil
		for _, choice in pairs(s.professions) do
			if choice.song == name then
				choice.song = nil
			end
		end
		if playing and playing.song == name then
			Music.Stop()
		end
		ns.Notify("MUSIC_CHANGED")
	end
end

function Music.IsWhole(name)
	local song = Music.Songs()[name]
	return song and song.whole or false
end

function Music.SongNames()
	local names = {}
	for name in pairs(Music.Songs()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end


-- Profession names the character has, from the client.
function Music.Professions()
	local list, seen = {}, {}
	if GetProfessions and GetProfessionInfo then
		local indices = { GetProfessions() }
		for i = 1, 6 do
			if indices[i] then
				local ok, name, icon, skill, maxSkill, _, _, skillLine = pcall(GetProfessionInfo, indices[i])
				if ok and name and not seen[name] then
					seen[name] = true
					list[#list + 1] = { name = name, icon = icon, skill = skill, maxSkill = maxSkill, skillLine = skillLine }
				end
			end
		end
	end
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.name and not seen[prof.name] then
			seen[prof.name] = true
			list[#list + 1] = { name = prof.name, icon = prof.icon, skill = prof.skill, maxSkill = prof.maxSkill }
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

-- Which profession a cast belongs to: a cached recipe, or a gathering spell named like the profession.
function Music.ProfessionOfSpell(spellID)
	for _, prof in pairs(ns.charDB and ns.charDB.professions or {}) do
		if prof.recipes[spellID] then
			return prof.name
		end
	end
	local name
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID)
		name = info and info.name
	end
	if not name or Secret(name) then
		return nil
	end
	name = SPELL_ALIASES[name] or name
	for _, prof in ipairs(Music.Professions()) do
		if prof.name == name then
			return name
		end
	end
end

local function PlayChunk(myToken)
	if not playing or playing.token ~= myToken then
		return
	end
	local song = Music.Songs()[playing.song]
	local full = song and (song.whole and song.file or song.full)
	if full and (song.whole or playing.mode == "restart" or playing.party) then
		-- Continuous playback from the full file: no chunk gaps. Chunks are only for resume.
		-- With a known duration it loops; otherwise it plays once.
		local ok, willPlay, handle = pcall(PlaySoundFile, full, CHANNEL)
		playing.handle = ok and willPlay and handle or nil
		playing.full = true
		if song.duration and C_Timer and C_Timer.NewTimer then
			playing.timer = C_Timer.NewTimer(song.duration, function()
				if playing and playing.token == myToken then
					PlayChunk(myToken)
				end
			end)
		end
		return
	end
	if not song or (song.chunks or 0) < 1 then
		playing = nil
		return
	end
	if playing.index > song.chunks then
		playing.index = 1 -- loop
	end
	local file = ("%s%03d.ogg"):format(song.path, playing.index)
	local ok, willPlay, handle = pcall(PlaySoundFile, file, CHANNEL)
	playing.handle = ok and willPlay and handle or nil
	local length = song.length or 2
	if playing.index == song.chunks and song.last then
		length = song.last -- the last chunk is usually shorter
	end
	playing.chunkStart, playing.chunkLength = GetTime and GetTime() or nil, length
	if C_Timer and C_Timer.NewTimer then
		playing.timer = C_Timer.NewTimer(length, function()
			if playing and playing.token == myToken then
				playing.index = playing.index + 1
				PlayChunk(myToken)
			end
		end)
	end
end

local function ApplyVolume(volume)
	local s = Settings()
	if not s then
		return
	end
	if not s.savedVolume then
		s.savedVolume = { volume = GetCV(VOLUME_CVAR), enable = GetCV(ENABLE_CVAR) }
	end
	SetCV(VOLUME_CVAR, tostring(volume or 1))
	SetCV(ENABLE_CVAR, "1")
end

function Music.RestoreVolume()
	local s = Settings()
	local saved = s and s.savedVolume
	if not saved then
		return
	end
	if saved.volume then
		SetCV(VOLUME_CVAR, saved.volume)
	end
	if saved.enable then
		SetCV(ENABLE_CVAR, saved.enable)
	end
	s.savedVolume = nil
end

function Music.Start(professionName, castGUID, party)
	local s = Settings()
	local choice = s and s.enabled and s.professions[professionName]
	if not choice or not choice.song or not Music.Songs()[choice.song] then
		return false
	end
	if playing and not playing.preview and playing.profession == professionName then
		playing.castGUID = castGUID or playing.castGUID
		return true -- already playing
	end
	Music.Stop()
	token = token + 1
	local index = 1
	if choice.mode ~= "restart" and not Music.IsWhole(choice.song) then
		index = s.position[choice.song] or 1
	end
	playing = { profession = professionName, song = choice.song, index = index, token = token, mode = choice.mode,
		castGUID = castGUID, party = party }
	ApplyVolume(choice.volume)
	PlayChunk(token)
	return true
end

function Music.Stop()
	if not playing then
		return
	end
	if playing.timer and playing.timer.Cancel then
		playing.timer:Cancel()
	end
	if playing.handle and StopSound then
		pcall(StopSound, playing.handle, FADE_MS)
	end
	local s = Settings()
	if s and not playing.preview and not playing.full and not Music.IsWhole(playing.song) then
		-- Resume continues at the chunk boundary nearest to where it stopped (at most half a chunk
		-- off, instead of always replaying the interrupted chunk); restart forgets the position.
		local index = playing.index
		if playing.chunkStart and playing.chunkLength and GetTime then
			if GetTime() - playing.chunkStart >= playing.chunkLength / 2 then
				index = index + 1
				local song = Music.Songs()[playing.song]
				if song and song.chunks and index > song.chunks then
					index = 1
				end
			end
		end
		s.position[playing.song] = playing.mode ~= "restart" and index or nil
	end
	playing = nil
	-- Put the channel volume back once the fade-out is over, unless something plays again.
	if C_Timer and C_Timer.After then
		C_Timer.After(FADE_MS / 1000 + 0.05, function()
			if not playing then
				Music.RestoreVolume()
			end
		end)
	else
		Music.RestoreVolume()
	end
end

-- Listen to a song from the start in the picker; doesn't touch the saved position.
function Music.Preview(songName, volume)
	Music.Stop()
	if not Music.Songs()[songName] then
		return false
	end
	token = token + 1
	playing = { song = songName, index = 1, token = token, mode = "restart", preview = true }
	ApplyVolume(volume)
	PlayChunk(token)
	return true
end

function Music.PreviewSong()
	return playing and playing.preview and playing.song or nil
end

local function Choice(professionName)
	local s = Settings()
	if not s then
		return nil
	end
	local choice = s.professions[professionName] or { mode = "resume" }
	s.professions[professionName] = choice
	return choice
end

function Music.SetSong(professionName, songName)
	local choice = Choice(professionName)
	if not choice then
		return
	end
	choice.song = songName
	if playing and playing.profession == professionName then
		Music.Stop()
	end
	ns.Notify("MUSIC_CHANGED")
end

-- Volume 0-1 per profession, in steps of 10%.
function Music.Volume(professionName)
	local s = Settings()
	local choice = s and s.professions[professionName]
	return choice and choice.volume or 1
end

function Music.SetVolume(professionName, volume)
	local choice = Choice(professionName)
	if not choice then
		return
	end
	volume = math.floor(math.max(0, math.min(1, volume)) * 10 + 0.5) / 10
	choice.volume = volume
	if playing and (playing.profession == professionName or playing.preview) then
		SetCV(VOLUME_CVAR, tostring(volume))
	end
	ns.Notify("MUSIC_CHANGED")
end

function Music.SetMode(professionName, mode)
	local choice = Choice(professionName)
	if choice then
		choice.mode = mode == "restart" and "restart" or "resume"
		ns.Notify("MUSIC_CHANGED")
	end
end

function Music.IsPlaying()
	return playing ~= nil, playing and playing.profession, playing and playing.index
end

-- Song choice per profession, cycled from the Music view: none -> song 1 -> song 2 -> ... -> none.
function Music.CycleSong(professionName)
	local s = Settings()
	if not s then
		return
	end
	local names = Music.SongNames()
	local choice = s.professions[professionName] or { mode = "resume" }
	s.professions[professionName] = choice
	local nextName
	if not choice.song then
		nextName = names[1]
	else
		for i, name in ipairs(names) do
			if name == choice.song then
				nextName = names[i + 1]
			end
		end
	end
	choice.song = nextName
	if playing and playing.profession == professionName then
		Music.Stop()
	end
	ns.Notify("MUSIC_CHANGED")
end

function Music.ToggleMode(professionName)
	local s = Settings()
	if not s then
		return
	end
	local choice = s.professions[professionName] or { mode = "resume" }
	s.professions[professionName] = choice
	choice.mode = choice.mode == "restart" and "resume" or "restart"
	ns.Notify("MUSIC_CHANGED")
end

local function OnStart(_, unit, castGUID, spellID)
	if unit ~= "player" or not spellID or Secret(spellID) then
		return
	end
	local prof = Music.ProfessionOfSpell(spellID)
	if prof then
		Music.Start(prof, castGUID)
	end
end

-- A failed second spell while casting must not stop the music: only the cast that started it counts.
local function OnStop(_, unit, castGUID)
	if unit ~= "player" or not playing or playing.party then
		return -- party mode ignores casts; it stops on the key or when you move
	end
	if playing.castGUID and castGUID and not Secret(castGUID) and castGUID ~= playing.castGUID then
		return
	end
	Music.Stop()
end

ns.On("UNIT_SPELLCAST_START", OnStart)
ns.On("UNIT_SPELLCAST_CHANNEL_START", OnStart)
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_STOP" }) do
	ns.On(event, OnStop)
end

ns.Listen("DB_READY", function()
	Music.RestoreVolume() -- left over if the game closed while a song played
end)
ns.On("PLAYER_LOGOUT", function()
	if playing then
		Music.Stop()
	end
	Music.RestoreVolume()
end)

-- Party (issue #20): one key starts the Party song and video and makes the character dance;
-- the same key or moving stops it. "Party" is set up in the Music tab like a profession.
Music.PARTY = "Party"
Music.PARTY_ICON = "Interface\\Icons\\INV_Misc_Drum_01"

function Music.PartyActive()
	return (playing and playing.party) or (ns.Video and ns.Video.Current() and ns.Video.Current().party) or false
end

function Music.StopParty()
	if playing and playing.party then
		Music.Stop()
	end
	local v = ns.Video and ns.Video.Current()
	if v and v.party then
		ns.Video.Stop()
	end
	ns.Notify("MUSIC_CHANGED")
end

function Music.ToggleParty()
	if Music.PartyActive() then
		Music.StopParty()
		return false
	end
	local s = Settings()
	local choice = s and s.professions[Music.PARTY]
	if not (choice and (choice.song or choice.video)) then
		ns.Print("Set up Party in the Music tab first (song and/or video).")
		return false
	end
	if not s.enabled then
		ns.Print("Music is off - tick \"Music on\" in the Music tab.")
		return false
	end
	Music.Stop()
	if choice.song then
		Music.Start(Music.PARTY, nil, true)
	end
	if ns.Video and choice.video then
		ns.Video.Start(Music.PARTY, nil, true)
	end
	-- C_ChatInfo.PerformEmote is restricted to hardware events: key binding, slash command, button.
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		pcall(C_ChatInfo.PerformEmote, "DANCE")
	end
	ns.Notify("MUSIC_CHANGED")
	return true
end

-- Key binding (Bindings.xml) and macro: /cw party
_G.BINDING_HEADER_CRAFTWISE = "CraftWise"
_G.BINDING_NAME_CRAFTWISE_PARTY = "Party: music, video and dance"
function CraftWise_PartyToggle()
	Music.ToggleParty()
end

ns.On("PLAYER_STARTED_MOVING", function()
	if Music.PartyActive() then
		Music.StopParty()
	end
end)
