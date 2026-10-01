-- Profession music (issue #17): a song per profession that plays while you cast it.
-- The client can't seek inside a sound, so songs are split into short chunks played in sequence;
-- "resume" remembers the chunk where it stopped, "restart" starts from the first chunk each cast.
--
-- Songs live in a separate addon folder the player owns, CraftWise_Music (made by
-- tools/music_split.py), so CraftWise updates never delete them. It defines:
--   CraftWiseMusicSongs = { [name] = { path = "Interface\\AddOns\\CraftWise_Music\\name\\", chunks = n,
--     length = seconds per chunk, last = seconds of the last chunk } }
local _, ns = ...

local Music = {}
ns.Music = Music

local FADE_MS = 250
local playing -- { profession, song, index, handle, token }
local token = 0

-- English gathering spell names that differ from the profession name.
local SPELL_ALIASES = { ["Herb Gathering"] = "Herbalism" }

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

function Music.Songs()
	return type(CraftWiseMusicSongs) == "table" and CraftWiseMusicSongs or {}
end

function Music.SongNames()
	local names = {}
	for name in pairs(Music.Songs()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

local function Settings()
	return ns.db and ns.db.music
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
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
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
	if not song or (song.chunks or 0) < 1 then
		playing = nil
		return
	end
	if playing.index > song.chunks then
		playing.index = 1 -- loop
	end
	local file = ("%s%03d.ogg"):format(song.path, playing.index)
	local s = Settings()
	local ok, willPlay, handle = pcall(PlaySoundFile, file, s and s.channel or "Master")
	playing.handle = ok and willPlay and handle or nil
	local length = song.length or 2
	if playing.index == song.chunks and song.last then
		length = song.last -- the last chunk is usually shorter
	end
	if C_Timer and C_Timer.NewTimer then
		playing.timer = C_Timer.NewTimer(length, function()
			if playing and playing.token == myToken then
				playing.index = playing.index + 1
				PlayChunk(myToken)
			end
		end)
	end
end

function Music.Start(professionName, castGUID)
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
	if choice.mode ~= "restart" then
		index = s.position[choice.song] or 1
	end
	playing = { profession = professionName, song = choice.song, index = index, token = token, mode = choice.mode,
		castGUID = castGUID }
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
	if s and not playing.preview then
		-- Resume replays the interrupted chunk from its start; restart forgets the position.
		s.position[playing.song] = playing.mode ~= "restart" and playing.index or nil
	end
	playing = nil
end

-- Listen to a song from the start in the picker; doesn't touch the saved position.
function Music.Preview(songName)
	Music.Stop()
	if not Music.Songs()[songName] then
		return false
	end
	token = token + 1
	playing = { song = songName, index = 1, token = token, mode = "restart", preview = true }
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
	if unit ~= "player" or not playing then
		return
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
