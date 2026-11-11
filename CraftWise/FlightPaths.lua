-- Known flight paths (issue #68), recorded per character when a flight master's map opens, for the
-- character snapshot (#63, `flightPaths`). Stored in CraftWiseCharDB.flightPaths[taxi map ID] =
-- { t, map, nodes = { { id, name, x, y, state, current, known } } }; each opening overwrites that
-- map's entry (the flight master lists the whole map), other maps stay as last seen.
--
-- Client data only: C_TaxiMap.GetAllTaxiNodes (the nodes the flight master shows, with their state)
-- on the taxi map the client opened (GetTaxiMapID, as Blizzard's flight map reads it), and
-- C_TaxiMap.GetTaxiNodesForMap for the explicit discovered flag (isUndiscovered, as the world map
-- shows it). A value the client doesn't give stays missing.
local _, ns = ...

local FP = {}
ns.FlightPaths = FP

-- Enum.FlightPathState (TaxiMapDocumentation): Current 0, Reachable 1, Unreachable 2.
local STATES = { [0] = "current", [1] = "reachable", [2] = "unreachable" }

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

local function Round(v)
	if type(v) ~= "number" or Secret(v) then
		return nil
	end
	return math.floor(v * 10000 + 0.5) / 10000
end

-- x, y of a vector2 (Vector2DMixin: fields x/y, or GetXY).
local function XY(pos)
	if type(pos) ~= "table" then
		return nil, nil
	end
	local x, y = pos.x, pos.y
	if (x == nil or y == nil) and pos.GetXY then
		x, y = pos:GetXY()
	end
	return Round(x), Round(y)
end

local function Store()
	if not ns.charDB then
		return nil
	end
	ns.charDB.flightPaths = ns.charDB.flightPaths or {}
	return ns.charDB.flightPaths
end

-- Reads the open flight master's map. Returns the stored entry, or nil and why nothing was stored.
function FP.Record()
	local store = Store()
	if not store then
		return nil, "character data not loaded"
	end
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then
		return nil, "C_TaxiMap.GetAllTaxiNodes/GetTaxiMapID not available"
	end
	local okMap, mapID = pcall(GetTaxiMapID)
	if not (okMap and type(mapID) == "number") or Secret(mapID) then
		return nil, "no taxi map ID"
	end
	local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
	if not (ok and type(list) == "table") or #list == 0 then
		return nil, "flight master listed no nodes"
	end
	-- Discovered flag per node, from the map's own taxi node list.
	local undiscovered = {}
	if C_TaxiMap.GetTaxiNodesForMap then
		local okMapNodes, mapNodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
		for _, n in ipairs(okMapNodes and type(mapNodes) == "table" and mapNodes or {}) do
			if n.nodeID and not Secret(n.nodeID) and type(n.isUndiscovered) == "boolean" then
				undiscovered[n.nodeID] = n.isUndiscovered
			end
		end
	end
	local nodes = {}
	for _, n in ipairs(list) do
		local id, name = n.nodeID, n.name
		if not (Secret(id) or Secret(name) or Secret(n.state)) then
			local node = { id = id, name = name, state = STATES[n.state] }
			node.x, node.y = XY(n.position)
			node.current = n.state == 0 or nil
			if id and undiscovered[id] ~= nil then
				node.known = not undiscovered[id]
			end
			if n.isMapLayerTransition then
				node.transition = true
			end
			nodes[#nodes + 1] = node
		end
	end
	table.sort(nodes, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	local entry = { t = time(), nodes = nodes }
	if C_Map and C_Map.GetMapInfo then
		local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
		entry.map = okInfo and info and info.name or nil
	end
	store[mapID] = entry
	return entry
end

-- Snapshot section: one entry per taxi map, by map ID.
function FP.Snapshot()
	local store = ns.charDB and ns.charDB.flightPaths
	if not (store and next(store)) then
		return nil, "no flight master map opened yet"
	end
	local maps = {}
	for mapID, entry in pairs(store) do
		local nodes = {}
		for i, n in ipairs(entry.nodes or {}) do
			local copy = {}
			for k, v in pairs(n) do
				copy[k] = v
			end
			nodes[i] = copy
		end
		maps[#maps + 1] = { mapID = mapID, map = entry.map, t = entry.t, nodes = nodes }
	end
	table.sort(maps, function(a, b)
		return a.mapID < b.mapID
	end)
	return { maps = maps }
end

ns.On("TAXIMAP_OPENED", function()
	local ok, entry, why = pcall(FP.Record)
	if ns.db then
		ns.db.debug = ns.db.debug or {}
		ns.db.debug.taxi = { nodes = ok and entry and #entry.nodes or 0, why = not ok and tostring(entry) or why }
	end
end)
