-- Music (#157; spec in #150 "Look up, Music, Settings", board "Music"): a song and a clip per profession
-- while you cast it, and Party. An orange Playing card while a song plays (song, chunk, time bar, Music
-- on, Party!), then one row per profession: Song and Video dropdowns, Next cast segmented Resume / From
-- start, volume slider. Sources: Music.SongNames, Music.SetSong, Music.SetMode, Music.SetVolume,
-- Music.ToggleParty, Video.lua clips. The dropdowns also preview a song or clip and remove a song file
-- added by name; a song file is added by name under the rows (today's song picker, moved here).
-- Row data (Mu.Rows, Mu.Playing) is built apart from the drawing, so the docked layout (#161) can draw it.
-- Provisional (#161 Q3), docked: the page scrolls; each profession row stacks into lines (Song, Video,
-- Next cast, then volume, each with its label), the Playing card stacks too (DockedRows, DockedCard).
local _, ns = ...
local M = ns.Main
local Style, L = ns.Style, ns.L
local C = Style.C

local Mu = {}
M.Music = Mu

Mu.ROW_HEIGHT = 44
Mu.POLL = 0.25 -- seconds between checks of what plays while the page shows
local PAD, GAP = 22, 14
local COLS = { name = 180, mode = 180, volume = 110 } -- Song and Video share what is left (board)

----------------------------------------------------------------------------------------------------
-- Model
----------------------------------------------------------------------------------------------------

function Mu.SongLabel(name)
	return name and (name:gsub("_", " ")) or L["No song"]
end

function Mu.VideoLabel(name)
	return name and (name:gsub("_", " ")) or L["No video"]
end

-- One row per profession the character has, Party first (as the Music view had it).
function Mu.Rows()
	local music = ns.db.music
	local rows = {}
	local function Row(name, prof, party)
		local choice = music.professions[name] or {}
		local whole = choice.song and ns.Music.IsWhole(choice.song) or false
		return {
			key = name, name = name, party = party, icon = party and ns.Music.PARTY_ICON or prof and prof.icon,
			skill = prof and prof.skill, maxSkill = prof and prof.maxSkill,
			song = choice.song, songLabel = Mu.SongLabel(choice.song),
			video = choice.video, videoLabel = Mu.VideoLabel(choice.video),
			mode = (choice.mode == "restart" or whole) and "restart" or "resume", whole = whole,
			volume = ns.Music.Volume(name),
		}
	end
	rows[1] = Row(ns.Music.PARTY, nil, true)
	for _, prof in ipairs(ns.Music.Professions()) do
		rows[#rows + 1] = Row(prof.name, prof, false)
	end
	return rows
end

-- "1:04".
function Mu.Clock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- The Playing card, nil when nothing plays: { label, name, sub, progress (0-1) | nil, elapsed, duration }.
function Mu.Playing(now)
	local p = ns.Music.NowPlaying(now)
	if not p then
		return nil
	end
	local card = { name = Mu.SongLabel(p.song), song = p.song, profession = p.profession }
	if p.preview then
		card.label = L["Playing · preview"]
	elseif p.party then
		card.label = L["Playing · Party"]
	else
		card.label = (L["Playing · while you cast %s"]):format(p.profession or "?")
	end
	local sub = {}
	if p.chunk and p.chunks then
		sub[#sub + 1] = (L["chunk %d of %d"]):format(p.chunk, p.chunks)
		if not p.preview and not p.party then
			sub[#sub + 1] = L["resumes here next cast"]
		end
	elseif p.full then
		sub[#sub + 1] = L["from the start"]
	end
	card.sub = table.concat(sub, " · ")
	card.elapsed, card.duration = p.elapsed, p.duration
	if p.elapsed and p.duration and p.duration > 0 then
		card.progress = math.max(0, math.min(1, p.elapsed / p.duration))
	end
	return card
end

-- Choices of a dropdown: { { value (false = none), label, whole } }.
function Mu.Options(kind)
	if kind == "video" then
		local out = { { value = false, label = L["No video"] } }
		for _, name in ipairs(ns.Video.Names()) do
			out[#out + 1] = { value = name, label = Mu.VideoLabel(name) }
		end
		return out
	end
	local out = { { value = false, label = L["No song"] } }
	for _, name in ipairs(ns.Music.SongNames()) do
		out[#out + 1] = { value = name, label = Mu.SongLabel(name), whole = ns.Music.IsWhole(name) }
	end
	return out
end

function Mu.Choose(kind, profession, value)
	if kind == "video" then
		ns.Video.SetVideo(profession, value or nil)
	else
		ns.Music.SetSong(profession, value or nil)
	end
end

function Mu.SetMusicOn(on)
	ns.db.music.enabled = on and true or false
	if not on then
		ns.Music.Stop()
	end
	M.Refresh()
end

function Mu.Party()
	ns.Music.ToggleParty()
	M.Refresh()
end

-- Adds a song file by name (Music.AddFile); returns the message shown under the box and its colour.
function Mu.AddFile(text)
	local name, err = ns.Music.AddFile(text)
	if name then
		Mu.message = { (L["Added %s. Choose it in a Song list."]):format(Mu.SongLabel(name)), "text2" }
	else
		Mu.message = { err, "danger" }
	end
	M.Refresh()
	return name, err
end

----------------------------------------------------------------------------------------------------
-- Dropdown menu (song or video): folded sheet like the item menu; Play previews, × removes a song
-- added by name. Closes on a choice, a click elsewhere or Escape; a preview stops when it closes.
----------------------------------------------------------------------------------------------------

local MENU_W, MENU_ROW, MENU_PAD = 240, 24, 8
local menu

local function BuildMenu()
	menu = CreateFrame("Frame", "CraftWiseMusicMenu", UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetWidth(MENU_W)
	menu:EnableMouse(true)
	menu:SetClampedToScreen(true)
	menu.sheet = Style.Sheet(menu, C.sheet, C.flap, 10, true)
	table.insert(UISpecialFrames, "CraftWiseMusicMenu")
	menu.rows = {}
	menu.nokta = Style.Nokta(menu)
	menu:SetScript("OnHide", function()
		if ns.Music.PreviewSong() then
			ns.Music.Stop()
		end
		if ns.Video.PreviewName() then
			ns.Video.Stop()
		end
	end)
	menu:Hide()
	Mu.menu = menu
end

local function MenuRow(i)
	local r = menu.rows[i]
	if r then
		return r
	end
	r = CreateFrame("Button", nil, menu)
	r:SetHeight(MENU_ROW)
	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints(r)
	Style.Fill(r.bg, C.selected)
	r.bg:Hide()
	r.label = Style.Text(r, "Body", "text")
	r.label:SetPoint("LEFT", r, "LEFT", 20, 0)
	r.label:SetJustifyH("LEFT")
	r.label:SetWordWrap(false)
	r.label:SetWidth(MENU_W - 20 - 80)
	r.play = Style.Chip(r, L["Play"], 20)
	r.play:SetPoint("RIGHT", r, "RIGHT", -30, 0)
	r.remove = Style.Chip(r, "×", 20)
	r.remove:SetPoint("RIGHT", r, "RIGHT", -6, 0)
	r:SetScript("OnClick", function(self)
		Mu.Choose(menu.kind, menu.profession, self.opt.value)
		menu:Hide()
	end)
	r:SetScript("OnEnter", function(self)
		self.bg:Show()
	end)
	r:SetScript("OnLeave", function(self)
		self.bg:SetShown(self.current and true or false)
	end)
	r.play:SetScript("OnClick", function()
		local opt = r.opt
		if menu.kind == "video" then
			if ns.Video.PreviewName() == opt.value then
				ns.Video.Stop()
			else
				ns.Video.Preview(opt.value)
			end
		elseif ns.Music.PreviewSong() == opt.value then
			ns.Music.Stop()
		else
			ns.Music.Preview(opt.value, ns.Music.Volume(menu.profession))
		end
		Mu.RenderMenu()
	end)
	r.remove:SetScript("OnClick", function()
		ns.Music.RemoveFile(r.opt.value)
		Mu.RenderMenu()
	end)
	r.remove:HookScript("OnEnter", function(self)
		Style.ShowTip(self, L["Remove"], L["Takes this song file off the list; the file stays in your Songs folder."])
	end)
	r.remove:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	menu.rows[i] = r
	return r
end

function Mu.RenderMenu()
	local opts = Mu.Options(menu.kind)
	local choice = ns.db.music.professions[menu.profession] or {}
	local current = (menu.kind == "video" and choice.video or choice.song) or false
	local previewing = menu.kind == "video" and ns.Video.PreviewName() or ns.Music.PreviewSong()
	for i, opt in ipairs(opts) do
		local r = MenuRow(i)
		r.opt = opt
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -MENU_PAD - (i - 1) * MENU_ROW)
		r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -MENU_PAD - (i - 1) * MENU_ROW)
		r.label:SetText(opt.label .. (opt.whole and (Style.Hex("text3") .. "  " .. L["from start"] .. "|r") or ""))
		local c = opt.value and C.text or C.text2
		r.label:SetTextColor(c[1], c[2], c[3], 1)
		r.current = opt.value == current
		r.bg:SetShown(r.current)
		r.label:SetFontObject(r.current and Style.Fonts.BodyBold or Style.Fonts.Body)
		if r.current then
			menu.nokta:MoveTo(r, "LEFT", 10, 0, true)
		end
		r.play:SetShown(opt.value and true or false)
		r.play:SetLabel(opt.value and previewing == opt.value and L["Stop"] or L["Play"])
		r.remove:SetShown(opt.whole and menu.kind ~= "video" or false)
		r:Show()
	end
	for i = #opts + 1, #menu.rows do
		menu.rows[i]:Hide()
	end
	menu:SetHeight(2 * MENU_PAD + #opts * MENU_ROW)
	return opts
end

-- Opens the song or video list of a profession under its dropdown.
function Mu.OpenMenu(owner, kind, profession)
	if not menu then
		BuildMenu()
	end
	if menu:IsShown() and menu.kind == kind and menu.profession == profession then
		menu:Hide()
		return
	end
	menu.kind, menu.profession = kind, profession
	Mu.RenderMenu()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	menu:Show()
end

ns.On("GLOBAL_MOUSE_DOWN", function()
	if menu and menu:IsShown() and not menu:IsMouseOver() then
		menu:Hide()
	end
end)

----------------------------------------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------------------------------------

-- Dropdown button (board "sel"): 26 tall, 1 unit C.ruleStrong border, the choice and a ▾.
local function Dropdown(parent, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	b.kind = kind
	b.border = Style.Border(b, C.ruleStrong)
	b.text = Style.Text(b, "Small", "text")
	b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.text:SetPoint("RIGHT", b, "RIGHT", -22, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	b.caret = Style.Text(b, "Small", "text2")
	b.caret:SetPoint("RIGHT", b, "RIGHT", -8, 0)
	b.caret:SetText(Style.Glyph("down", 9, "text2"))
	b:SetScript("OnClick", function(self)
		Mu.OpenMenu(self, self.kind, self.profession)
	end)
	b:SetScript("OnEnter", function(self)
		self.border:SetColor(C.text)
	end)
	b:SetScript("OnLeave", function(self)
		self.border:SetColor(C.ruleStrong)
	end)
	return b
end

local function BuildRow(list, i)
	local r = CreateFrame("Frame", nil, list)
	r:SetHeight(Mu.ROW_HEIGHT)
	r.hair = Style.Rule(r, "H", C.rule)
	r.hair:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.hair:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
	r.name = Style.Text(r, "Section", "text")
	r.name:SetPoint("LEFT", r, "LEFT", PAD, 0)
	r.name:SetJustifyH("LEFT")
	r.skill = Style.Text(r, "Caption", "text3")
	r.skill:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
	r.nameHit = CreateFrame("Frame", nil, r)
	r.nameHit:EnableMouse(true)
	r.nameHit:SetPoint("TOPLEFT", r, "TOPLEFT", PAD, 0)
	r.nameHit:SetSize(COLS.name, Mu.ROW_HEIGHT)
	r.nameHit:SetScript("OnEnter", function(self)
		local d = r.data
		if not d then
			return
		end
		if d.party then
			Style.ShowTip(self, L["Party"], L["One key: your character dances, the Party song and video start. Press again or move to stop."],
				L["Key: Key Bindings > AddOns > CraftWise, or /craftwise party."])
		else
			Style.ShowTip(self, d.name, (L["Plays while you cast %s and stops when the cast ends."]):format(d.name))
		end
	end)
	r.nameHit:SetScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	r.song = Dropdown(r, "song")
	r.video = Dropdown(r, "video")
	r.mode = Style.Segmented(r, { L["Resume"], L["From start"] }, function(index)
		local d = r.data
		if d then
			ns.Music.SetMode(d.name, index == 1 and "resume" or "restart")
		end
	end)
	r.mode.buttons[1]:HookScript("OnEnter", function(self)
		local d = r.data
		if d and d.whole then
			Style.ShowTip(self, L["Resume"], L["A song added by name plays from the start. Split it with tools/music_split.py to resume."])
		end
	end)
	r.mode.buttons[1]:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	r.volume = Style.Slider(r, COLS.volume, 0, 1, 0.1, function(value)
		local d = r.data
		if d then
			ns.Music.SetVolume(d.name, value)
		end
	end)
	r.volume:HookScript("OnEnter", function(self)
		local d = r.data
		Style.ShowTip(self, L["Volume"], d and ("%d %%"):format(math.floor(d.volume * 100 + 0.5)) or "")
	end)
	r.volume:HookScript("OnLeave", function(self)
		Style.HideTip(self)
	end)
	list.rows[i] = r
	return r
end

local function DrawRows(list, rows, width)
	local flex = math.floor((width - 2 * PAD - COLS.name - COLS.mode - COLS.volume - 4 * GAP) / 2)
	for i, d in ipairs(rows) do
		local r = list.rows[i] or BuildRow(list, i)
		r.data = d
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * Mu.ROW_HEIGHT)
		r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * Mu.ROW_HEIGHT)
		r.name:SetText(d.party and L["Party"] or d.name)
		r.skill:SetText(d.skill and tostring(d.skill) or "")
		r:SetHeight(Mu.ROW_HEIGHT)
		r.name:ClearAllPoints()
		r.name:SetPoint("LEFT", r, "LEFT", PAD, 0)
		r.nameHit:SetSize(COLS.name, Mu.ROW_HEIGHT)
		for _, t in pairs(r.dl or {}) do
			t:Hide()
		end
		local x = PAD + COLS.name + GAP
		for _, key in ipairs({ "song", "video" }) do
			local dd = r[key]
			dd.profession = d.name
			dd:ClearAllPoints()
			dd:SetPoint("LEFT", r, "LEFT", x, 0)
			dd:SetWidth(flex)
			dd.text:SetText(key == "song" and d.songLabel or d.videoLabel)
			local c = (key == "song" and d.song or key == "video" and d.video) and C.text or C.text3
			dd.text:SetTextColor(c[1], c[2], c[3], 1)
			x = x + flex + GAP
		end
		r.mode:ClearAllPoints()
		r.mode:SetPoint("LEFT", r, "LEFT", x, 0)
		r.mode:SetShown(not d.party) -- Party always plays from the start
		r.mode:SetSelected(d.mode == "restart" and 2 or 1)
		x = x + COLS.mode + GAP
		r.volume:ClearAllPoints()
		r.volume:SetPoint("LEFT", r, "LEFT", x, 0)
		r.volume:SetValueQuietly(d.volume)
		r:Show()
	end
	for i = #rows + 1, #list.rows do
		list.rows[i]:Hide()
	end
end

----------------------------------------------------------------------------------------------------
-- Provisional (#161 Q3): docked rows and card
----------------------------------------------------------------------------------------------------

Mu.DOCKED_LINE, Mu.DOCKED_LABEL = 30, 76

-- Lines of a docked row, in order: { key, label } (Party has no Next cast: it always plays from the start).
function Mu.DockedLines(d)
	local lines = { { "song", L["Song"] }, { "video", L["Video"] } }
	if not d.party then
		lines[#lines + 1] = { "mode", L["Next cast"] }
	end
	lines[#lines + 1] = { "volume", L["Volume"] }
	return lines
end

function Mu.DockedRowHeight(d)
	return 10 + 18 + 6 + #Mu.DockedLines(d) * Mu.DOCKED_LINE + 4
end

local function DockedRows(list, rows, width, pad)
	local ctlW = width - 2 * pad - Mu.DOCKED_LABEL
	local y = 0
	for i, d in ipairs(rows) do
		local r = list.rows[i] or BuildRow(list, i)
		r.data = d
		local h = Mu.DockedRowHeight(d)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
		r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
		r:SetHeight(h)
		r.name:SetText(d.party and L["Party"] or d.name)
		r.name:ClearAllPoints()
		r.name:SetPoint("TOPLEFT", r, "TOPLEFT", pad, -10)
		r.skill:SetText(d.skill and tostring(d.skill) or "")
		r.nameHit:SetSize(width - 2 * pad, 22)
		r.dl = r.dl or {}
		for _, t in pairs(r.dl) do
			t:Hide()
		end
		local ly = 10 + 18 + 6
		for _, line in ipairs(Mu.DockedLines(d)) do
			local key = line[1]
			local label = r.dl[key]
			if not label then
				label = Style.Text(r, "Label", "text3")
				r.dl[key] = label
			end
			label:SetText(line[2])
			label:ClearAllPoints()
			label:SetPoint("LEFT", r, "TOPLEFT", pad, -(ly + Mu.DOCKED_LINE / 2 - 2))
			label:Show()
			local ctl = r[key]
			ctl:ClearAllPoints()
			ctl:SetPoint("LEFT", r, "TOPLEFT", pad + Mu.DOCKED_LABEL, -(ly + Mu.DOCKED_LINE / 2 - 2))
			if key == "song" or key == "video" then
				ctl.profession = d.name
				ctl:SetWidth(ctlW)
				ctl.text:SetText(key == "song" and d.songLabel or d.videoLabel)
				local c = (key == "song" and d.song or key == "video" and d.video) and C.text or C.text3
				ctl.text:SetTextColor(c[1], c[2], c[3], 1)
			elseif key == "mode" then
				ctl:SetSelected(d.mode == "restart" and 2 or 1)
			elseif key == "volume" then
				ctl:SetValueQuietly(d.volume)
			end
			ly = ly + Mu.DOCKED_LINE
		end
		r.mode:SetShown(not d.party)
		r:Show()
		y = y + h
	end
	for i = #rows + 1, #list.rows do
		list.rows[i]:Hide()
	end
	return y
end

-- The Playing card: window, one line with the time bar and the toggles right; docked, stacked: label,
-- song, chunk, the time bar across, then Music on and Party!.
Mu.CARD_HEIGHT, Mu.DOCKED_CARD_HEIGHT = 76, 14 + 12 + 26 + 14 + 10 + 4 + 16 + 8 + 28 + 14
local function LayoutCard(card, docked)
	local bar = card.bar
	card.party:ClearAllPoints()
	card.on:ClearAllPoints()
	bar:ClearAllPoints()
	if docked then
		card:SetHeight(Mu.DOCKED_CARD_HEIGHT)
		bar:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", -26, -10)
		bar:SetPoint("RIGHT", card, "RIGHT", -16, 0)
		card.on:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 16, 14)
		card.party:SetPoint("LEFT", card.on, "RIGHT", 8, 0)
	else
		card:SetHeight(Mu.CARD_HEIGHT)
		card.party:SetPoint("RIGHT", card, "RIGHT", -16, 0)
		card.on:SetPoint("RIGHT", card.party, "LEFT", -8, 0)
		bar:SetSize(220, 4)
		bar:SetPoint("RIGHT", card.on, "LEFT", -18, 6)
	end
	card.barWidth = docked and nil or 220
	card.nokta:MoveTo(card, docked and "TOPLEFT" or "LEFT", 16 + 5.5, docked and -20 or 0, true)
end

local function BuildCard(body)
	local card = CreateFrame("Frame", nil, body)
	body.card = card
	card:SetHeight(76)
	card.sheet = Style.Sheet(card, C.card, C.live, 14, false)
	card.nokta = Style.Nokta(card, C.live)
	card.nokta:MoveTo(card, "LEFT", 16 + 5.5, 0, true)
	card.label = Style.Text(card, "Label", "live")
	card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 16 + 26, -14)
	card.name = Style.Text(card, "Hero", "text")
	card.name:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -1)
	card.name:SetWordWrap(false)
	card.sub = Style.Text(card, "Caption", "text3")
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -1)
	card.party = Style.Chip(card, L["Party!"], 28)
	card.party:SetPoint("RIGHT", card, "RIGHT", -16, 0)
	card.party:SetScript("OnClick", Mu.Party)
	card.on = Style.Chip(card, L["Music on"], 28)
	card.on:SetPoint("RIGHT", card.party, "LEFT", -8, 0)
	card.on:SetScript("OnClick", function()
		Mu.SetMusicOn(not ns.db.music.enabled)
	end)
	local bar = CreateFrame("Frame", nil, card)
	card.bar = bar
	bar:SetSize(220, 4)
	bar:SetPoint("RIGHT", card.on, "LEFT", -18, 6)
	bar.track = bar:CreateTexture(nil, "ARTWORK")
	bar.track:SetAllPoints(bar)
	Style.Fill(bar.track, C.cardFlap)
	bar.fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	Style.Fill(bar.fill, C.text)
	bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
	bar.from = Style.Text(card, "Caption", "text3")
	bar.from:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
	bar.to = Style.Text(card, "Caption", "text3")
	bar.to:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -4)
	card:Hide()
end

-- The time bar only; called by the poll so it moves without rebuilding the page.
local function UpdateTime(card, playing)
	local bar = card.bar
	local has = playing and playing.progress ~= nil
	bar:SetShown(has and true or false)
	bar.from:SetShown(has and true or false)
	bar.to:SetShown(has and true or false)
	if has then
		bar.fill:SetWidth(math.max((card.barWidth or card.dockedBarWidth or 220) * playing.progress, 0.01))
		bar.from:SetText(Mu.Clock(playing.elapsed))
		bar.to:SetText(Mu.Clock(playing.duration))
	end
end

-- Music on and Party!: in the Playing card while a song plays, else in the list bar (see the PR).
local function PaintToggles(on, party)
	on:SetOn(ns.db.music.enabled)
	party:SetOn(ns.Music.PartyActive())
	party:SetLabel(ns.Music.PartyActive() and L["Stop party"] or L["Party!"])
end

local function PlayingKey(p)
	return p and (tostring(p.song) .. "|" .. tostring(p.profession) .. "|" .. tostring(p.sub)) or "none"
end

local function Build(body)
	BuildCard(body)
	local bar = CreateFrame("Frame", nil, body)
	body.listBar = bar
	bar:SetHeight(44)
	bar.title = Style.Text(bar, "BodyBold", "text")
	bar.title:SetPoint("LEFT", bar, "LEFT", PAD, 0)
	bar.title:SetText(L["A song per profession"])
	bar.note = Style.Text(bar, "Caption", "text3")
	bar.note:SetPoint("LEFT", bar.title, "RIGHT", 8, 0)
	bar.note:SetText(L["plays while you cast it · songs live in your own CraftWise_Music folder"])
	bar.party = Style.Chip(bar, L["Party!"])
	bar.party:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
	bar.party:SetScript("OnClick", Mu.Party)
	bar.on = Style.Chip(bar, L["Music on"])
	bar.on:SetPoint("RIGHT", bar.party, "LEFT", -8, 0)
	bar.on:SetScript("OnClick", function()
		Mu.SetMusicOn(not ns.db.music.enabled)
	end)

	local head = CreateFrame("Frame", nil, body)
	body.head = head
	head:SetHeight(24)
	head.rule = head:CreateTexture(nil, "ARTWORK")
	Style.Fill(head.rule, C.text)
	head.rule:SetHeight(2)
	head.rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
	head.rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
	head.labels = {}
	for i, label in ipairs({ L["Profession"], L["Song"], L["Video"], L["Next cast"], L["Volume"] }) do
		head.labels[i] = Style.Text(head, "Label", "text3")
		head.labels[i]:SetText(label)
	end

	local list = CreateFrame("Frame", nil, body)
	body.list = list
	list.rows = {}

	-- Add a song file by name (from the old song picker).
	local add = CreateFrame("Frame", nil, body)
	body.add = add
	add:SetHeight(60)
	add.help = Style.Text(add, "Caption", "text3")
	add.help:SetPoint("TOPLEFT", add, "TOPLEFT", PAD, 0)
	add.help:SetJustifyH("LEFT")
	add.help:SetText((L["Add a song: put an .mp3 or .ogg in %s, restart the game, then type its file name."]):format(ns.Music.FOLDER_TEXT))
	add.box = CreateFrame("EditBox", nil, add)
	add.box:SetSize(220, 24)
	add.box:SetPoint("TOPLEFT", add.help, "BOTTOMLEFT", 0, -6)
	add.box:SetAutoFocus(false)
	add.box:SetFontObject(Style.Fonts.Small)
	add.box:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
	add.box:SetTextInsets(8, 8, 0, 0)
	add.box.border = Style.Border(add.box, C.ruleStrong)
	add.btn = Style.LineButton(add, L["Add"])
	add.btn:SetPoint("LEFT", add.box, "RIGHT", 8, 0)
	local function DoAdd()
		local name = Mu.AddFile(add.box:GetText())
		if name then
			add.box:SetText("")
		end
		add.box:ClearFocus()
	end
	add.btn:SetScript("OnClick", DoAdd)
	add.box:SetScript("OnEnterPressed", DoAdd)
	add.box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	add.msg = Style.Text(add, "Small", "text2")
	add.msg:SetPoint("LEFT", add.btn, "RIGHT", 12, 0)

	local elapsed = 0
	body:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < Mu.POLL then
			return
		end
		elapsed = 0
		local p = Mu.Playing()
		if PlayingKey(p) ~= body.playingKey then
			M.Refresh()
		elseif p then
			UpdateTime(body.card, p)
		end
	end)
end

-- Docked or window: the page's parts sit in the scroll's child (docked) or on the body.
local function Container(body, docked)
	if not docked then
		if body.dscroll then
			body.dscroll:Hide()
		end
		for _, part in ipairs({ body.card, body.listBar, body.list, body.add }) do
			part:SetParent(body)
		end
		body.head:Show()
		return body
	end
	if not body.dscroll then
		body.dscroll = M.Docked.Scroll(body)
		body.dscroll:SetAllPoints(body)
	end
	local child = body.dscroll.child
	for _, part in ipairs({ body.card, body.listBar, body.list, body.add }) do
		part:SetParent(child)
	end
	body.head:Hide() -- no columns to head: each row names its lines
	body.dscroll:Show()
	return child
end

local function Refresh(body, ctx)
	local width = ctx and ctx.metrics and ctx.metrics.width or 880
	local docked = M.IsDocked(ctx)
	local pad = docked and ctx.metrics.pad or PAD
	local playing = Mu.Playing()
	body.playingKey = PlayingKey(playing)
	Mu.lastPlaying = playing
	local parent = Container(body, docked)
	if docked then
		parent:SetWidth(width)
	end
	local y = docked and 0 or 16
	local card = body.card
	card:SetShown(playing ~= nil)
	LayoutCard(card, docked)
	card.dockedBarWidth = width - 2 * pad - 32
	if playing then
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -y)
		card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, -y)
		card.label:SetText(playing.label)
		card.name:SetText(playing.name)
		card.sub:SetText(playing.sub or "")
		UpdateTime(card, playing)
		PaintToggles(card.on, card.party)
		y = y + (docked and (Mu.DOCKED_CARD_HEIGHT + 8) or 76)
	end
	local bar = body.listBar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
	bar.on:SetShown(not playing)
	bar.party:SetShown(not playing)
	PaintToggles(bar.on, bar.party)
	bar.title:ClearAllPoints()
	bar.note:ClearAllPoints()
	bar.party:ClearAllPoints()
	if docked then
		-- the title with the toggles right, its note under it
		bar:SetHeight(48)
		bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -8)
		bar.note:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -4)
		bar.note:SetWidth(width - 2 * pad)
		bar.note:SetWordWrap(false)
		bar.party:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -pad, -4)
		y = y + 48
	else
		bar:SetHeight(44)
		bar.title:SetPoint("LEFT", bar, "LEFT", PAD, 0)
		bar.note:SetPoint("LEFT", bar.title, "RIGHT", 8, 0)
		bar.note:SetWidth(0)
		bar.party:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
		y = y + 44
	end
	local head = body.head
	head:ClearAllPoints()
	head:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
	head:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
	local flex = math.floor((width - 2 * PAD - COLS.name - COLS.mode - COLS.volume - 4 * GAP) / 2)
	local x = PAD
	for i, w in ipairs({ COLS.name, flex, flex, COLS.mode, COLS.volume }) do
		head.labels[i]:ClearAllPoints()
		head.labels[i]:SetPoint("LEFT", head, "LEFT", x, 0)
		x = x + w + GAP
	end
	if not docked then
		y = y + 24
	end
	local rows = Mu.Rows()
	Mu.lastRows = rows
	local list = body.list
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	list:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
	if docked then
		local h = DockedRows(list, rows, width, pad)
		list:SetHeight(h)
		y = y + h + 14
	else
		list:SetHeight(#rows * Mu.ROW_HEIGHT)
		DrawRows(list, rows, width)
		y = y + #rows * Mu.ROW_HEIGHT + 14
	end
	local add = body.add
	add:ClearAllPoints()
	add:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	add:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
	add.help:ClearAllPoints()
	add.help:SetPoint("TOPLEFT", add, "TOPLEFT", pad, 0)
	add.help:SetWidth(width - 2 * pad)
	add.help:SetWordWrap(true)
	add.msg:ClearAllPoints()
	if docked then
		-- the message under the box (no room beside it)
		add.box:SetWidth(width - 2 * pad - 60)
		add.msg:SetPoint("TOPLEFT", add.box, "BOTTOMLEFT", 0, -6)
		add:SetHeight(84)
		body.dscroll:SetContentHeight(y + 84 + 16)
	else
		add.box:SetWidth(220)
		add.msg:SetPoint("LEFT", add.btn, "RIGHT", 12, 0)
		add:SetHeight(60)
	end
	local msg = Mu.message
	add.msg:SetText(msg and msg[1] or (#ns.Music.SongNames() == 0 and L["No songs yet."] or ""))
	local c = Style.Color(msg and msg[2] or "text3")
	add.msg:SetTextColor(c[1], c[2], c[3], 1)
	if menu and menu:IsShown() then
		Mu.RenderMenu()
	end
end

M.RegisterPage({
	key = "music", section = "music", label = L["Music"], order = 1, kind = "custom",
	events = { "MUSIC_CHANGED", "PROFESSIONS_CHANGED" },
	Build = Build,
	Refresh = Refresh,
})
