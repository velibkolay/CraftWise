-- Interface › Flight map (#321 part 2): flight times recorded from flights this account has flown, shown
-- on the flight map tooltip and on a bar while flying, and a bigger flight map. Every switch is off by
-- default (db.settings.interface); while a switch is off nothing is hooked.
--
-- Times: only flights this account has flown. A flight is recorded from a takeoff to the landing of one
-- whole route (start node -> destination node, by the names the client gives them). An unknown route
-- reads "not recorded"; nothing is estimated and no table is bundled. A flight that is cut short is not
-- recorded: an early landing (TaxiRequestEarlyLanding), a new destination taken in the air (a second
-- TakeTaxiNode), a loading screen before landing, or a flight whose takeoff was not seen.
--
-- Built from Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`), nothing from another
-- addon:
--   Blizzard_UIPanels_Game/Shared/TaxiFrame.lua: TaxiNodeOnButtonEnter(button) (the tooltip), NumTaxiNodes,
--     TaxiNodeGetType ("CURRENT" | "REACHABLE" | ...), TaxiNodeName, GetNumRoutes, TaxiGetNodeSlot(slot,
--     route, isSource); the frame is TaxiFrame.
--   Blizzard_FlightMap/FM_FlightPathDataProvider.lua: FlightMap_FlightPointPinMixin:OnMouseEnter (pin
--     .taxiNodeData.slotIndex), TakeTaxiNode(slot); the frame is FlightMapFrame (Blizzard_FlightMap.lua).
--   Blizzard_ActionBar/Shared/VehicleLeaveButton.lua: TaxiRequestEarlyLanding().
--   Blizzard_APIDocumentationGenerated/UnitDocumentation: UnitOnTaxi; events PLAYER_CONTROL_LOST and
--     PLAYER_CONTROL_GAINED.
--
-- Bigger flight map: Blizzard's frame only allows what any frame allows: SetScale. That is all this does
-- (a size between 1 and 1.5 times); it does not move the frame or change its icons.
local _, ns = ...

local Fl = {}
ns.Flights = Fl

local PENDING_SECONDS = 30 -- a takeoff must follow the destination click within this time
local MIN_SECONDS = 1

local installed = {}
local pending -- { from, to, legs, nextStop, at }: a destination was taken, the flight has not started
local flight -- { from, to, legs, nextStop, takeoff, aborted }
local bar

local function Settings()
	local s = ns.db and ns.db.settings
	if not s then
		return {}
	end
	s.interface = s.interface or {}
	return s.interface
end

function Fl.Settings()
	return Settings()
end

local function On(key)
	return Settings()[key] == true
end

local function Store()
	if not ns.db then
		return nil
	end
	ns.db.flights = ns.db.flights or {}
	return ns.db.flights
end

----------------------------------------------------------------------------------------------------
-- Recorded times
----------------------------------------------------------------------------------------------------

-- The record of a route: { secs, n, t } or nil (never flown).
function Fl.Lookup(from, to)
	local store = Store()
	local row = store and from and to and store[from]
	return row and row[to] or nil
end

function Fl.Record(from, to, secs)
	local store = Store()
	if not (store and from and to and type(secs) == "number") or secs < MIN_SECONDS then
		return nil
	end
	store[from] = store[from] or {}
	local rec = store[from][to] or { n = 0 }
	rec.secs, rec.n, rec.t = math.floor(secs + 0.5), (rec.n or 0) + 1, time()
	store[from][to] = rec
	return rec
end

-- 3:05, 12:00; one hour or more: 1:02:09.
function Fl.FormatTime(secs)
	secs = math.max(0, math.floor((secs or 0) + 0.5))
	local h, m, s = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

----------------------------------------------------------------------------------------------------
-- Reading the flight master's map (the client's own functions, as TaxiFrame.lua calls them)
----------------------------------------------------------------------------------------------------

local function CurrentName()
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then
			return TaxiNodeName(i)
		end
	end
end

-- What a click on destination slot would start: nil unless the slot is reachable.
local function Describe(slot)
	local ok, info = pcall(function()
		if TaxiNodeGetType(slot) ~= "REACHABLE" then
			return nil
		end
		local out = { from = CurrentName(), to = TaxiNodeName(slot), legs = GetNumRoutes(slot) }
		if out.legs and out.legs > 1 then
			out.nextStop = TaxiNodeName(TaxiGetNodeSlot(slot, 1, false))
		end
		return out
	end)
	return ok and info or nil
end

-- The tooltip line for a destination, or nil when the node is not a destination.
function Fl.TooltipText(slot)
	local info = Describe(slot)
	if not info then
		return nil
	end
	local rec = Fl.Lookup(info.from, info.to)
	if not rec then
		return ns.L["Flight time: not recorded"]
	end
	local n = rec.n or 1
	return ns.L["Flight time:"] .. " " .. Fl.FormatTime(rec.secs) .. (n > 1 and (" (" .. n .. "×)") or "")
end

local function HasLine(text)
	for i = 1, GameTooltip:NumLines() or 0 do
		local line = _G["GameTooltipTextLeft" .. i]
		if line and line:GetText() == text then
			return true
		end
	end
	return false
end

-- Both Blizzard frames call this after they filled the tooltip: the line is added once, whatever the
-- number of times the tooltip is rebuilt for the same node.
local function OnNodeEnter(slot)
	if not On("flightTimes") then
		return
	end
	local text = Fl.TooltipText(slot)
	if text and not HasLine(text) then
		GameTooltip:AddLine(text, 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end
end
Fl.OnNodeEnter = OnNodeEnter

----------------------------------------------------------------------------------------------------
-- The flight itself
----------------------------------------------------------------------------------------------------

local function OnTakeTaxiNode(slot)
	if not (On("flightTimes") or On("flightBar")) then
		return
	end
	if flight then
		flight.aborted = true -- a new destination in the air: neither flight is a whole route
		pending = nil
		return
	end
	local info = Describe(slot)
	if info then
		info.at = GetTime()
		pending = info
	end
end

local function Takeoff()
	if pending and UnitOnTaxi("player") and GetTime() - pending.at <= PENDING_SECONDS then
		flight = pending
		flight.takeoff = GetTime()
		pending = nil
		if On("flightBar") then
			Fl.ShowBar()
		end
	end
end

-- The time is from takeoff to the first PLAYER_CONTROL_GAINED (f.gained), not to a later recheck.
local function Landed()
	local f = flight
	flight = nil
	Fl.HideBar()
	if f and not f.aborted and f.from and f.to and f.gained and On("flightTimes") then
		Fl.Record(f.from, f.to, f.gained - f.takeoff)
	end
end

-- The client may still report UnitOnTaxi while control comes back (#333): the landing is looked for again
-- a few times, and while the bar is up on every tick. A landing seen without PLAYER_CONTROL_GAINED has no
-- trustworthy time: the bar goes, nothing is recorded.
local function CheckLanded()
	if flight and not UnitOnTaxi("player") then
		Landed()
		return true
	end
	return false
end
Fl.CheckLanded = CheckLanded

local RECHECK = { 0.5, 1, 2 }

ns.On("PLAYER_CONTROL_LOST", function()
	if pending then
		Takeoff()
		C_Timer.After(1, Takeoff)
	end
end)

ns.On("PLAYER_CONTROL_GAINED", function()
	if flight then
		flight.gained = flight.gained or GetTime()
		if not CheckLanded() then
			local f = flight
			for _, secs in ipairs(RECHECK) do
				C_Timer.After(secs, function()
					if flight == f then
						CheckLanded()
					end
				end)
			end
		end
	end
	pending = nil
end)

-- A loading screen before the landing: the time is not a whole flight.
ns.On("PLAYER_ENTERING_WORLD", function()
	if flight and not UnitOnTaxi("player") then
		flight.aborted = true
		Landed()
	end
end)

----------------------------------------------------------------------------------------------------
-- The bar while flying
----------------------------------------------------------------------------------------------------

local function BarText()
	local f = flight
	if not f then
		return "", ""
	end
	local title = ns.L["To"] .. " " .. (f.to or "?")
	local rec = Fl.Lookup(f.from, f.to)
	local parts = {}
	if f.nextStop then
		parts[#parts + 1] = ns.L["Next stop:"] .. " " .. f.nextStop
	end
	if rec then
		local left = rec.secs - (GetTime() - f.takeoff)
		parts[#parts + 1] = left > 0 and (Fl.FormatTime(left) .. " " .. ns.L["left"]) or ns.L["arriving"]
	else
		parts[#parts + 1] = ns.L["Time not recorded"]
	end
	return title, table.concat(parts, "  ·  ")
end
Fl.BarText = BarText

local function UpdateBar()
	if bar then
		local title, detail = BarText()
		bar.title:SetText(title)
		bar.detail:SetText(detail)
	end
end

local elapsed = 0
local function OnBarUpdate(_, dt)
	elapsed = elapsed + dt
	if elapsed >= 0.5 then
		elapsed = 0
		if CheckLanded() then
			return
		end
		UpdateBar()
	end
end

local function BuildBar()
	local Style = ns.Style
	local C = Style.C
	bar = CreateFrame("Frame", "CraftWiseFlightBar", UIParent)
	bar:SetSize(300, 44)
	bar:SetPoint("TOP", UIParent, "TOP", 0, -140)
	bar:SetFrameStrata("MEDIUM")
	bar.sheet = Style.Sheet(bar, C.sheet, C.flap, 10, true)
	bar.title = Style.Text(bar, "BodyBold", "text")
	bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -8)
	bar.title:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -12, -8)
	bar.title:SetJustifyH("LEFT")
	bar.detail = Style.Text(bar, "Caption", "text2")
	bar.detail:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 8)
	bar.detail:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -12, 8)
	bar.detail:SetJustifyH("LEFT")
	bar:Hide()
end

function Fl.ShowBar()
	if not bar then
		BuildBar()
	end
	elapsed = 0
	UpdateBar()
	bar:SetScript("OnUpdate", OnBarUpdate)
	bar:Show()
end

function Fl.HideBar()
	if bar then
		bar:SetScript("OnUpdate", nil)
		bar:Hide()
	end
end

function Fl.Flying()
	return flight
end

----------------------------------------------------------------------------------------------------
-- Bigger flight map
----------------------------------------------------------------------------------------------------

local original = {} -- frame -> scale it had before we changed it

function Fl.Scale()
	local v = tonumber(Settings().flightScale) or 1.25
	return math.max(1, math.min(1.5, v))
end

local function ScaleFrame(frame, on)
	if not frame then
		return
	end
	if on then
		original[frame] = original[frame] or frame:GetScale() or 1
		frame:SetScale(Fl.Scale())
	elseif original[frame] then
		frame:SetScale(original[frame])
		original[frame] = nil
	end
end

function Fl.ApplyScale()
	local on = On("flightBig")
	for _, name in ipairs({ "TaxiFrame", "FlightMapFrame" }) do
		local frame = _G[name]
		if frame then
			if on and not installed["scale" .. name] then
				installed["scale" .. name] = true
				frame:HookScript("OnShow", function(self)
					if On("flightBig") then
						ScaleFrame(self, true)
					end
				end)
			end
			ScaleFrame(frame, on)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Switches
----------------------------------------------------------------------------------------------------

local function HookPins()
	if not installed.pins and FlightMap_FlightPointPinMixin and FlightMap_FlightPointPinMixin.OnMouseEnter then
		installed.pins = true
		hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", function(pin)
			local data = pin.taxiNodeData
			if data then
				OnNodeEnter(data.slotIndex)
			end
		end)
	end
end

function Fl.Apply()
	local times, barOn = On("flightTimes"), On("flightBar")
	if (times or barOn) and not installed.take and TakeTaxiNode then
		installed.take = true
		hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
		if TaxiRequestEarlyLanding then
			hooksecurefunc("TaxiRequestEarlyLanding", function()
				if flight then
					flight.aborted = true
				end
			end)
		end
	end
	if times and not installed.buttons and TaxiNodeOnButtonEnter then
		installed.buttons = true
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
			OnNodeEnter(button:GetID())
		end)
	end
	if times then
		HookPins()
	end
	if not barOn then
		Fl.HideBar()
	elseif flight then
		Fl.ShowBar()
	end
	Fl.ApplyScale()
end

function Fl.Set(key, value)
	if key == "flightScale" then
		Settings().flightScale = tonumber(value) or 1.25
	else
		Settings()[key] = value and true or false
	end
	Fl.Apply()
end

ns.Listen("DB_READY", function()
	if On("flightTimes") or On("flightBar") or On("flightBig") then
		Fl.Apply()
	end
end)

-- The flight map pins live in a load-on-demand Blizzard addon.
ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_FlightMap" then
		if On("flightTimes") then
			HookPins()
		end
		Fl.ApplyScale()
	end
end)
