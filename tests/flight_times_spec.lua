-- Interface › Flight map (#321 part 2): flight times recorded from flights flown, tooltip line, bar,
-- bigger flight map. Invented nodes only.
local function setup()
	local ns, stub = LoadAddon()
	local hooks = { secure = 0 }
	local orig = hooksecurefunc
	function hooksecurefunc(...) hooks.secure = hooks.secure + 1; return orig(...) end
	-- The flight master's list: slot 1 is where we stand, 2 and 3 are destinations (3 needs two legs).
	local nodes = {
		{ type = "CURRENT", name = "Testburg" },
		{ type = "REACHABLE", name = "Fakehold", legs = 1 },
		{ type = "REACHABLE", name = "Far Fake", legs = 2, stop = 2 },
		{ type = "UNREACHABLE", name = "Nowhere" },
	}
	function NumTaxiNodes() return #nodes end
	function TaxiNodeGetType(i) return nodes[i].type end
	function TaxiNodeName(i) return nodes[i].name end
	function GetNumRoutes(i) return nodes[i].legs or 0 end
	function TaxiGetNodeSlot(i, leg, source) return source and 1 or nodes[i].stop or i end
	function TakeTaxiNode(slot) end
	function TaxiRequestEarlyLanding() end
	local onTaxi = false
	function UnitOnTaxi() return onTaxi end
	local lines = {}
	function GameTooltip.NumLines() return #lines end
	function GameTooltip.AddLine(_, text) lines[#lines + 1] = text; _G["GameTooltipTextLeft" .. #lines] = { GetText = function() return text end } end
	return ns, stub, hooks, lines, function(v) onTaxi = v end
end

local function fly(stub, setTaxi, slot, secs)
	TakeTaxiNode(slot)
	setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	stub.now = stub.now + secs
	setTaxi(false); stub.Fire("PLAYER_CONTROL_GAINED")
end

it("flights: every switch off hooks nothing and shows nothing", function()
	local ns, stub, hooks, lines, setTaxi = setup()
	local s = ns.Flights.Settings()
	eq(s.flightTimes, false); eq(s.flightBar, false); eq(s.flightBig, false)
	ns.Flights.Apply()
	eq(hooks.secure, 0)
	fly(stub, setTaxi, 2, 60)
	eq(next(ns.db.flights), nil, "nothing recorded")
	ns.Flights.OnNodeEnter(2)
	eq(#lines, 0)
	eq(CraftWiseFlightBar, nil)
end)

it("flights: a whole flight is recorded per start and end, and shown on the tooltip once", function()
	local ns, stub, hooks, lines, setTaxi = setup()
	local Fl = ns.Flights
	Fl.Set("flightTimes", true)
	assert(hooks.secure >= 1)
	Fl.OnNodeEnter(2)
	eq(lines[1], "Flight time: not recorded")
	fly(stub, setTaxi, 2, 191)
	eq(Fl.Lookup("Testburg", "Fakehold").secs, 191); eq(Fl.Lookup("Testburg", "Fakehold").n, 1)
	eq(Fl.Lookup("Testburg", "Far Fake"), nil, "other routes stay unknown")
	for i = #lines, 1, -1 do lines[i] = nil end
	Fl.OnNodeEnter(2); Fl.OnNodeEnter(2)
	eq(#lines, 1, "the line is added once")
	eq(lines[1], "Flight time: 3:11")
	fly(stub, setTaxi, 2, 190)
	for i = #lines, 1, -1 do lines[i] = nil end
	Fl.OnNodeEnter(2)
	eq(lines[1], "Flight time: 3:10 (2×)")
	for i = #lines, 1, -1 do lines[i] = nil end
	Fl.OnNodeEnter(1); Fl.OnNodeEnter(4)
	eq(#lines, 0, "no line on the current or an unreachable node")
end)

it("flights: a cancelled, rerouted or cut-short flight is not recorded", function()
	local ns, stub, _, _, setTaxi = setup()
	local Fl = ns.Flights
	Fl.Set("flightTimes", true)
	-- cancelled: destination chosen, never took off
	TakeTaxiNode(2); stub.now = stub.now + 60; setTaxi(false); stub.Fire("PLAYER_CONTROL_GAINED")
	eq(next(ns.db.flights), nil)
	-- reroute in the air
	TakeTaxiNode(2); setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	stub.now = stub.now + 30; TakeTaxiNode(3)
	stub.now = stub.now + 30; setTaxi(false); stub.Fire("PLAYER_CONTROL_GAINED")
	eq(next(ns.db.flights), nil, "reroute")
	-- early landing
	TakeTaxiNode(2); setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	stub.now = stub.now + 20; TaxiRequestEarlyLanding()
	setTaxi(false); stub.Fire("PLAYER_CONTROL_GAINED")
	eq(next(ns.db.flights), nil, "early landing")
	-- a loading screen before the landing
	TakeTaxiNode(2); setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	setTaxi(false); stub.Fire("PLAYER_ENTERING_WORLD")
	eq(next(ns.db.flights), nil, "loading screen")
	eq(Fl.Flying(), nil)
end)

it("flights: the bar names the destination and next stop, counts down, and says when the route is not recorded", function()
	local ns, stub, _, _, setTaxi = setup()
	local Fl = ns.Flights
	Fl.Set("flightBar", true)
	TakeTaxiNode(3); setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	eq(CraftWiseFlightBar.shown, true)
	local title, detail = Fl.BarText()
	eq(title, "To Far Fake"); eq(detail, "Next stop: Fakehold  ·  Time not recorded")
	setTaxi(false); stub.Fire("PLAYER_CONTROL_GAINED")
	eq(CraftWiseFlightBar.shown, false)
	eq(next(ns.db.flights), nil, "the bar alone records nothing")
	Fl.Set("flightTimes", true)
	fly(stub, setTaxi, 2, 120)
	TakeTaxiNode(2); setTaxi(true); stub.Fire("PLAYER_CONTROL_LOST")
	stub.now = stub.now + 45
	title, detail = Fl.BarText()
	eq(title, "To Fakehold"); eq(detail, "1:15 left")
	stub.now = stub.now + 100
	eq(select(2, Fl.BarText()), "arriving")
end)

it("flights: the bigger flight map scales the frame and gives it back", function()
	local ns = setup()
	local Fl = ns.Flights
	TaxiFrame = CreateFrame("Frame", "TaxiFrame")
	TaxiFrame.scale = 1
	function TaxiFrame:GetScale() return self.scale end
	function TaxiFrame:SetScale(v) self.scale = v end
	Fl.Set("flightBig", true)
	eq(TaxiFrame.scale, 1.25)
	Fl.Set("flightScale", 1.4)
	eq(TaxiFrame.scale, 1.4)
	Fl.Set("flightScale", 9)
	eq(Fl.Scale(), 1.5, "kept to the range")
	Fl.Set("flightBig", false)
	eq(TaxiFrame.scale, 1)
end)

it("flights: FormatTime", function()
	local ns = setup()
	eq(ns.Flights.FormatTime(65), "1:05"); eq(ns.Flights.FormatTime(3729), "1:02:09"); eq(ns.Flights.FormatTime(0), "0:00")
end)
