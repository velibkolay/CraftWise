-- Profession video (issue #19): a short silent clip in a small window while you cast a profession.
-- Addons can't play video files, so tools/video_frames.py turns a video into frames packed on
-- sprite sheets (TGA) in CraftWise_Music/Videos; this module flips through them like a flipbook.
-- CraftWise_Music/Videos.lua defines:
--   CraftWiseMusicVideos = { [name] = { path = "...\\Videos\\name\\", sheets = n, frames = n, fps = n,
--     cols = 4, rows = 7, width = 256, height = 144, size = 1024 } }
local _, ns = ...

local Video = {}
ns.Video = Video

local window, texture
local current -- { name, frame, profession, castGUID, preview, elapsed }

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Settings()
	return ns.db and ns.db.music
end

function Video.Videos()
	return type(CraftWiseMusicVideos) == "table" and CraftWiseMusicVideos or {}
end

function Video.Names()
	local names = {}
	for name in pairs(Video.Videos()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

-- Sheet number and texture coordinates of frame i (0-based).
function Video.FrameCoords(v, i)
	local perSheet = v.cols * v.rows
	local sheet = math.floor(i / perSheet) + 1
	local k = i % perSheet
	local col, row = k % v.cols, math.floor(k / v.cols)
	local s = v.size
	return sheet, col * v.width / s, (col + 1) * v.width / s, row * v.height / s, (row + 1) * v.height / s
end

local function SavePosition()
	local s = Settings()
	if not (s and window and window.GetPoint) then
		return
	end
	local point, _, relPoint, x, y = window:GetPoint()
	if point then
		s.videoWindow = { point = point, relPoint = relPoint, x = x, y = y }
	end
end

local function BuildWindow()
	window = CreateFrame("Frame", "CraftWiseVideoFrame", UIParent, "BackdropTemplate")
	window:SetFrameStrata("MEDIUM")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	if ns.Style then
		ns.Style.Panel(window)
	end
	texture = window:CreateTexture(nil, "ARTWORK")
	texture:SetPoint("TOPLEFT", 2, -2)
	texture:SetPoint("BOTTOMRIGHT", -2, 2)
	local pos = Settings() and Settings().videoWindow
	if pos then
		window:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 160)
	end
	window:Hide()
	window:SetScript("OnUpdate", function(_, elapsed)
		Video.Tick(elapsed)
	end)
end

local function ShowFrame()
	local v = current and Video.Videos()[current.name]
	if not (v and texture) then
		return
	end
	local sheet, l, r, t, b = Video.FrameCoords(v, current.frame)
	texture:SetTexture(("%s%03d"):format(v.path, sheet))
	texture:SetTexCoord(l, r, t, b)
end

function Video.Tick(elapsed)
	if not current then
		return
	end
	local v = Video.Videos()[current.name]
	if not v then
		return
	end
	current.elapsed = current.elapsed + elapsed
	local step = 1 / (v.fps or 10)
	local advanced = false
	while current.elapsed >= step do
		current.elapsed = current.elapsed - step
		current.frame = (current.frame + 1) % v.frames
		advanced = true
	end
	if advanced then
		ShowFrame()
	end
end

local function Play(name, startFrame, extra)
	local v = Video.Videos()[name]
	if not v then
		return false
	end
	if not window then
		BuildWindow()
	end
	window:SetSize(v.width + 4, v.height + 4)
	current = { name = name, frame = (startFrame or 0) % v.frames, elapsed = 0 }
	for k, val in pairs(extra or {}) do
		current[k] = val
	end
	ShowFrame()
	window:Show()
	return true
end

function Video.Start(professionName, castGUID)
	local s = Settings()
	local choice = s and s.enabled and s.professions[professionName]
	if not (choice and choice.video and Video.Videos()[choice.video]) then
		return false
	end
	if current and not current.preview and current.profession == professionName then
		current.castGUID = castGUID or current.castGUID
		return true
	end
	Video.Stop()
	s.videoPos = s.videoPos or {}
	return Play(choice.video, s.videoPos[choice.video], { profession = professionName, castGUID = castGUID })
end

function Video.Stop()
	if not current then
		return
	end
	local s = Settings()
	if s and not current.preview then
		s.videoPos = s.videoPos or {}
		s.videoPos[current.name] = current.frame
	end
	current = nil
	if window then
		window:Hide()
	end
end

function Video.Preview(name)
	Video.Stop()
	return Play(name, 0, { preview = true })
end

function Video.PreviewName()
	return current and current.preview and current.name or nil
end

function Video.Current()
	return current
end

function Video.SetVideo(professionName, name)
	local s = Settings()
	if not s then
		return
	end
	local choice = s.professions[professionName] or { mode = "resume" }
	s.professions[professionName] = choice
	choice.video = name
	if current and current.profession == professionName then
		Video.Stop()
	end
	ns.Notify("MUSIC_CHANGED")
end

ns.On("UNIT_SPELLCAST_START", function(_, unit, castGUID, spellID)
	if unit ~= "player" or not spellID or Secret(spellID) or not ns.Music then
		return
	end
	local prof = ns.Music.ProfessionOfSpell(spellID)
	if prof then
		Video.Start(prof, castGUID)
	end
end)
ns.On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, castGUID, spellID)
	if unit ~= "player" or not spellID or Secret(spellID) or not ns.Music then
		return
	end
	local prof = ns.Music.ProfessionOfSpell(spellID)
	if prof then
		Video.Start(prof, castGUID)
	end
end)
for _, event in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_STOP" }) do
	ns.On(event, function(_, unit, castGUID)
		if unit ~= "player" or not current or current.preview then
			return
		end
		if current.castGUID and castGUID and not Secret(castGUID) and castGUID ~= current.castGUID then
			return
		end
		Video.Stop()
	end)
end
