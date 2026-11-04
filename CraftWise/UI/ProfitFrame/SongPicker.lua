-- Profit table window: the song picker of the Music view.
local _, ns = ...
local PF = ns.PF
local Style, L, C = ns.Style, ns.L, ns.Style.colors
local Muted = PF.Muted

local picker

local function BuildPicker()
	picker = CreateFrame("Frame", "CraftWiseSongPicker", PF.frame, "BackdropTemplate")
	picker:SetFrameStrata("DIALOG")
	picker:SetWidth(300)
	picker:EnableMouse(true)
	Style.Panel(picker)
	table.insert(UISpecialFrames, "CraftWiseSongPicker")
	picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	picker.title:SetPoint("TOPLEFT", 12, -10)
	local close = Style.CloseButton(picker, function()
		picker:Hide()
	end)
	close:SetPoint("TOPRIGHT", -6, -6)
	picker.songs = {}
	picker.videos = {}
	picker.videoLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.videoLabel:SetText(Muted("Video (small window while you cast)"))
	picker.modeLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.modeLabel:SetText(Muted("Next cast"))
	picker.resume = Style.Button(picker, 134, 22, L["Resume where it stopped"])
	picker.restart = Style.Button(picker, 134, 22, L["From the beginning"])
	picker.volLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.volDown = Style.Button(picker, 26, 22, "-")
	picker.volUp = Style.Button(picker, 26, 22, "+")
	picker.volText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.empty:SetPoint("TOPLEFT", 12, -36)
	picker.empty:SetPoint("RIGHT", -12, 0)
	picker.empty:SetJustifyH("LEFT")
	picker.empty:SetText(Muted("No songs yet. Add them with tools/music_split.py and restart the game."))
	-- Add a song file by name.
	picker.addLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.addLabel:SetJustifyH("LEFT")
	picker.addLabel:SetWidth(276)
	picker.addLabel:SetText(Muted("Add a song: put an .mp3 or .ogg in") .. "\n|cffffffff" .. ns.Music.FOLDER_TEXT
		.. "|r\n" .. Muted("restart the game, then type its file name here."))
	picker.addBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
	picker.addBox:SetSize(200, 22)
	picker.addBox:SetAutoFocus(false)
	picker.addBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	picker.addBtn = Style.Button(picker, 60, 22, L["Add"])
	picker.addMsg = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	picker.addMsg:SetJustifyH("LEFT")
	picker.addMsg:SetWidth(276)
	local function add()
		local name, err = ns.Music.AddFile(picker.addBox:GetText())
		if name then
			picker.addBox:SetText("")
			picker.addMsg:SetText(C.good .. "Added " .. name .. "|r")
			ns.Music.SetSong(picker.profession, name)
		else
			picker.addMsg:SetText(C.warn .. err .. "|r")
		end
		picker.addBox:ClearFocus()
		picker.render(picker.profession)
	end
	picker.addBtn:SetScript("OnClick", add)
	picker.addBox:SetScript("OnEnterPressed", add)
	picker:SetScript("OnHide", function()
		if ns.Music.PreviewSong() then
			ns.Music.Stop()
		end
		if ns.Video.PreviewName() then
			ns.Video.Stop()
		end
	end)
end

local function RenderPicker(prof)
	local choice = ns.db.music.professions[prof] or {}
	local names = ns.Music.SongNames()
	local options = { false }
	for _, n in ipairs(names) do
		options[#options + 1] = n
	end
	picker.title:SetText(prof .. "  " .. Muted("song"))
	local y = -34
	for i, name in ipairs(options) do
		local line = picker.songs[i]
		if not line then
			line = {}
			line.pick = Style.Button(picker, 190, 22)
			line.play = Style.Button(picker, 44, 22)
			line.remove = Style.Button(picker, 22, 22, "x")
			picker.songs[i] = line
		end
		line.pick:ClearAllPoints()
		line.pick:SetPoint("TOPLEFT", 12, y)
		line.play:ClearAllPoints()
		line.play:SetPoint("LEFT", line.pick, "RIGHT", 6, 0)
		local label = name and name:gsub("_", " ") or "No music"
		if name and ns.Music.IsWhole(name) then
			label = label .. Muted("  from start")
		end
		line.pick:SetLabel(label)
		line.pick:SetSelected((choice.song or false) == name)
		line.pick:SetScript("OnClick", function()
			ns.Music.SetSong(prof, name or nil)
			RenderPicker(prof)
		end)
		line.pick:Show()
		if name then
			line.play:SetLabel(ns.Music.PreviewSong() == name and "Stop" or "Play")
			line.play:SetScript("OnClick", function()
				if ns.Music.PreviewSong() == name then
					ns.Music.Stop()
				else
					ns.Music.Preview(name, ns.Music.Volume(prof))
				end
				RenderPicker(prof)
			end)
			line.play:Show()
			line.remove:ClearAllPoints()
			line.remove:SetPoint("LEFT", line.play, "RIGHT", 6, 0)
			line.remove:SetScript("OnClick", function()
				ns.Music.RemoveFile(name)
				RenderPicker(prof)
			end)
			line.remove:SetShown(ns.Music.IsWhole(name))
		else
			line.play:Hide()
			line.remove:Hide()
		end
		y = y - 26
	end
	for i = #options + 1, #picker.songs do
		picker.songs[i].pick:Hide()
		picker.songs[i].play:Hide()
		picker.songs[i].remove:Hide()
	end
	picker.empty:SetShown(#names == 0)
	if #names == 0 then
		y = y - 30
	end
	picker.modeLabel:ClearAllPoints()
	picker.modeLabel:SetPoint("TOPLEFT", 12, y - 8)
	picker.resume:ClearAllPoints()
	picker.resume:SetPoint("TOPLEFT", 12, y - 24)
	picker.restart:ClearAllPoints()
	picker.restart:SetPoint("LEFT", picker.resume, "RIGHT", 6, 0)
	local whole = choice.song and ns.Music.IsWhole(choice.song)
	local restart = choice.mode == "restart" or whole
	picker.resume:SetLabel(whole and Muted("Resume: split the song") or "Resume where it stopped")
	picker.resume:SetSelected(not restart)
	picker.restart:SetSelected(restart)
	picker.resume:SetScript("OnClick", function()
		ns.Music.SetMode(prof, "resume")
		RenderPicker(prof)
	end)
	picker.restart:SetScript("OnClick", function()
		ns.Music.SetMode(prof, "restart")
		RenderPicker(prof)
	end)
	-- Volume for this profession (e.g. low while fishing so the bobber splash stays audible).
	picker.volLabel:ClearAllPoints()
	picker.volLabel:SetPoint("TOPLEFT", 12, y - 58)
	picker.volLabel:SetText(Muted("Volume"))
	picker.volDown:ClearAllPoints()
	picker.volDown:SetPoint("TOPLEFT", 80, y - 52)
	picker.volText:ClearAllPoints()
	picker.volText:SetPoint("LEFT", picker.volDown, "RIGHT", 8, 0)
	picker.volText:SetWidth(44)
	picker.volText:SetText(("%d%%"):format(ns.Music.Volume(prof) * 100 + 0.5))
	picker.volUp:ClearAllPoints()
	picker.volUp:SetPoint("LEFT", picker.volText, "RIGHT", 8, 0)
	picker.volDown:SetScript("OnClick", function()
		ns.Music.SetVolume(prof, ns.Music.Volume(prof) - 0.1)
		RenderPicker(prof)
	end)
	picker.volUp:SetScript("OnClick", function()
		ns.Music.SetVolume(prof, ns.Music.Volume(prof) + 0.1)
		RenderPicker(prof)
	end)
	y = y - 30

	-- Video choice: "No video" and every converted video, with a preview.
	y = y - 58
	picker.videoLabel:ClearAllPoints()
	picker.videoLabel:SetPoint("TOPLEFT", 12, y)
	y = y - 16
	local videoOptions = { false }
	for _, n in ipairs(ns.Video.Names()) do
		videoOptions[#videoOptions + 1] = n
	end
	for i, name in ipairs(videoOptions) do
		local line = picker.videos[i]
		if not line then
			line = { pick = Style.Button(picker, 190, 22), play = Style.Button(picker, 44, 22) }
			picker.videos[i] = line
		end
		line.pick:ClearAllPoints()
		line.pick:SetPoint("TOPLEFT", 12, y)
		line.play:ClearAllPoints()
		line.play:SetPoint("LEFT", line.pick, "RIGHT", 6, 0)
		line.pick:SetLabel(name and name:gsub("_", " ") or "No video")
		line.pick:SetSelected((choice.video or false) == name)
		line.pick:SetScript("OnClick", function()
			ns.Video.SetVideo(prof, name or nil)
			RenderPicker(prof)
		end)
		line.pick:Show()
		if name then
			line.play:SetLabel(ns.Video.PreviewName() == name and "Stop" or "Play")
			line.play:SetScript("OnClick", function()
				if ns.Video.PreviewName() == name then
					ns.Video.Stop()
				else
					ns.Video.Preview(name)
				end
				RenderPicker(prof)
			end)
			line.play:Show()
		else
			line.play:Hide()
		end
		y = y - 26
	end
	for i = #videoOptions + 1, #picker.videos do
		picker.videos[i].pick:Hide()
		picker.videos[i].play:Hide()
	end
	y = y + 58 - 8
	picker.addLabel:ClearAllPoints()
	picker.addLabel:SetPoint("TOPLEFT", 12, y - 58)
	picker.addBox:ClearAllPoints()
	picker.addBox:SetPoint("TOPLEFT", 18, y - 106)
	picker.addBtn:ClearAllPoints()
	picker.addBtn:SetPoint("LEFT", picker.addBox, "RIGHT", 8, 0)
	picker.addMsg:ClearAllPoints()
	picker.addMsg:SetPoint("TOPLEFT", 12, y - 134)
	picker:SetHeight(-(y - 134) + 26)
	picker.profession = prof
	picker.render = RenderPicker
end

local function ShowPicker(row, prof)
	if not picker then
		BuildPicker()
	end
	if picker:IsShown() and picker.profession == prof then
		picker:Hide()
		return
	end
	RenderPicker(prof)
	picker:ClearAllPoints()
	picker:SetPoint("TOPLEFT", row.cells.songText, "TOPLEFT", -8, -4)
	picker:Show()
end
ns.ShowSongPicker = ShowPicker
PF.ShowPicker = ShowPicker
