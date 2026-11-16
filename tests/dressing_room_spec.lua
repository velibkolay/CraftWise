-- Interface › Dressing room (#321 part 4): undress, try-ons only, pause / play. Invented links only.
local function setup()
	local ns, stub = LoadAddon()
	local hooks = { secure = 0 }
	local orig = hooksecurefunc
	function hooksecurefunc(...) hooks.secure = hooks.secure + 1; return orig(...) end
	local log = {}
	local actor = {}
	function actor:Undress(weapons) log[#log + 1] = "undress:" .. tostring(weapons) end
	function actor:TryOn(link) log[#log + 1] = "tryon:" .. link end
	function actor:SetPaused(p, g) log[#log + 1] = "paused:" .. tostring(p) .. ":" .. tostring(g) end
	DressUpFrame = CreateFrame("Frame", "DressUpFrame")
	DressUpFrame.ModelScene = CreateFrame("Frame")
	function DressUpFrame.ModelScene:GetPlayerActor() return actor end
	function DressUpVisualLink(forced, link) end
	function DressUpFrame_Show(frame, ids, force, link) end
	return ns, stub, hooks, log
end

it("dressing room: off hooks nothing and builds no button", function()
	local ns, _, hooks = setup()
	ns.DressingRoom.Apply()
	eq(hooks.secure, 0)
	eq(DressUpFrame.hooks, nil, "no HookScript")
end)

it("dressing room: undress, try-ons only (links tried since the open or reset), pause and play", function()
	local ns, stub, _, log = setup()
	local DR = ns.DressingRoom
	DR.Set("dressStrip", true); DR.Set("dressAnim", true)
	DressUpVisualLink(nil, "item:1"); DressUpVisualLink(nil, "item:2"); DressUpVisualLink(nil, "item:1")
	eq(#DR.Tried(), 2, "no duplicates")
	DR.Undress()
	eq(log[#log], "undress:true")
	for i = #log, 1, -1 do log[i] = nil end
	DR.TriedOnly()
	eq(table.concat(log, ","), "undress:true,tryon:item:1,tryon:item:2")
	eq(DR.TogglePause(), true); eq(log[#log], "paused:true:false")
	eq(DR.TogglePause(), false); eq(log[#log], "paused:false:false")
	-- the Reset button asks DressUpFrame_Show for a player refresh: the list starts again
	DressUpFrame_Show(DressUpFrame, nil, true, nil)
	eq(#DR.Tried(), 0)
	eq(DR.TriedOnly(), false, "nothing tried on, nothing to show")
	DressUpVisualLink(nil, "item:3")
	DressUpFrame.hooks.OnHide[1](DressUpFrame)
	eq(#DR.Tried(), 0, "closing the room forgets them")
end)

it("dressing room: only the switched-on buttons show", function()
	local ns = setup()
	local DR = ns.DressingRoom
	DR.Set("dressAnim", true)
	DR.Set("dressStrip", false)
	-- links are not tracked without the strip switch
	DressUpVisualLink(nil, "item:9")
	eq(#DR.Tried(), 0)
end)
