-- Builds web/public/data/recipes.json, the recipe data of the price site (#143), from the addon's bundled
-- generated data: CraftWise/Data/Recipes.lua (spell -> profession, reagents, output; output sell prices; recipe
-- names), Sources.lua (recipe item -> spell and required skill) and Vendor.lua (vendor buy prices). Nothing is
-- added: what those files lack, the JSON lacks. Each file's header comment (source, build, licence) is carried
-- unchanged in the JSON's "sources" field.
--
--   lua5.1 tools/gen_site_recipes.lua     (repo root) rewrites web/public/data/recipes.json
--
-- Run it after the data generators (AGENTS.md, "Bundled data"). tests/site_recipes_spec.lua (in tests/run.lua)
-- fails while the committed JSON differs from what this script writes.
--
-- Format (keys sorted, so the file only changes when the data does):
--   v            1
--   about        what this file is
--   sources      { "<file>": [header comment lines] }
--   professions  { "<skillLine>": "Alchemy" }
--   teach        { "<recipe item ID>": [spell ID, required skill] }      (Sources.lua)
--   spells       { "<spell ID>": [skillLine, output item ID or 0 (no item: enchant etc.), output quantity (mean
--                  yield), reagent ID, quantity, reagent ID, quantity, ...] }    (Recipes.lua RecipeData)
--   names        { "<spell ID>": "name" } for spells that make no item (the item name says what the others make)
--   vendor       { "<item ID>": copper per unit a vendor sells it for }   (Vendor.lua)
--   sell         { "<item ID>": copper a vendor pays for one }            (Recipes.lua ItemSellPrices)
local G = {}

G.OUT = "web/public/data/recipes.json"
G.FILES = { "Recipes.lua", "Sources.lua", "Vendor.lua" }
local DIR = "CraftWise/Data/"

----------------------------------------------------------------------------------------------------
-- JSON writer: sorted keys, integers as integers, the shortest text that reads back for fractions.
----------------------------------------------------------------------------------------------------

local function Number(n)
	assert(n == n and n ~= math.huge and n ~= -math.huge, "not a finite number")
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return ("%d"):format(n)
	end
	for digits = 1, 17 do
		local text = ("%." .. digits .. "g"):format(n)
		if tonumber(text) == n then
			return text
		end
	end
	return ("%.17g"):format(n)
end

local function String(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		if c == '"' or c == "\\" then
			return "\\" .. c
		elseif c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		end
		return ("\\u%04x"):format(c:byte())
	end) .. '"'
end

local function IsList(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

-- Object keys sort as numbers when both are numeric, else as text, so "2" comes before "10".
local function KeyLess(a, b)
	local na, nb = tonumber(a), tonumber(b)
	if na and nb then
		return na < nb
	end
	return tostring(a) < tostring(b)
end

-- `depth` levels get a line each; deeper values are written on one line (a spell's array, a header).
local function Encode(v, depth, indent)
	local kind = type(v)
	if kind == "number" then
		return Number(v)
	elseif kind == "string" then
		return String(v)
	elseif kind == "boolean" then
		return tostring(v)
	end
	assert(kind == "table", "cannot write a " .. kind)
	local inner = indent .. "\t"
	local sep, open, close = ",", "", ""
	if depth > 0 then
		sep, open, close = ",\n" .. inner, "\n" .. inner, "\n" .. indent
	end
	local parts = {}
	if IsList(v) and (next(v) ~= nil or depth == 0) then
		for _, x in ipairs(v) do
			parts[#parts + 1] = Encode(x, depth - 1, inner)
		end
		if #parts == 0 then
			return "[]"
		end
		return "[" .. open .. table.concat(parts, sep) .. close .. "]"
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, KeyLess)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = String(tostring(k)) .. ":" .. (depth > 0 and " " or "") .. Encode(v[k], depth - 1, inner)
	end
	if #parts == 0 then
		return "{}"
	end
	return "{" .. open .. table.concat(parts, sep) .. close .. "}"
end
G.Encode = Encode

----------------------------------------------------------------------------------------------------
-- Reading the data files
----------------------------------------------------------------------------------------------------

-- The comment lines at the top of a file, up to its first code line, without "-- " and without the
-- tooling markers (luacheck, stylua, the type annotation).
local function Header(path)
	local lines = {}
	for line in io.lines(path) do
		local text = line:match("^%-%-%s?(.*)$")
		if not text then
			break
		end
		if not (text:match("^luacheck:") or text:match("^stylua:") or text:match("^%-%-?@")) then
			lines[#lines + 1] = (text:gsub("%s+$", ""))
		end
	end
	return lines
end

local function Load(root)
	local ns = {}
	for _, file in ipairs(G.FILES) do
		local chunk = assert(loadfile(root .. DIR .. file))
		setfenv(chunk, {})
		chunk("CraftWise", ns)
	end
	return ns
end

-- The JSON text for the data files under `root` ("" = the repo root as the current directory).
function G.Build(root)
	root = root or ""
	local ns = Load(root)
	local out = { v = 1, sources = {}, professions = {}, teach = {}, spells = {}, names = {}, vendor = {}, sell = {} }
	out.about = "Recipe data of wow.velikopter.com (#143), written by tools/gen_site_recipes.lua from the addon's bundled "
		.. "data files; do not edit. Licence: GPL-3.0 (CraftWise); each source file's header below names its own "
		.. "source and licence."
	for _, file in ipairs(G.FILES) do
		out.sources[file] = Header(root .. DIR .. file)
	end
	for name, line in pairs(ns.ProfessionSkillLines or {}) do
		out.professions[line] = name
	end
	for spell, r in pairs(assert(ns.RecipeData, "Recipes.lua: no RecipeData")) do
		local row = { r.skillLine, 0, 0 }
		if r.output then
			row[2], row[3] = r.output.itemID, r.output.quantity
		end
		for _, x in ipairs(r.reagents or {}) do
			row[#row + 1] = x.itemID
			row[#row + 1] = x.quantity
		end
		out.spells[spell] = row
	end
	for _, byName in pairs(ns.RecipeNames or {}) do
		for name, spell in pairs(byName) do
			-- false: the name is ambiguous within the profession. Only spells that make no item need a name.
			local r = spell and ns.RecipeData[spell]
			if r and not r.output then
				out.names[spell] = name
			end
		end
	end
	for spell, s in pairs(assert(ns.SourceData, "Sources.lua: no SourceData")) do
		local item = s.item
		-- Several spells per item never happens in the data; if it did, the lowest spell ID would win.
		if item and (not out.teach[item] or spell < out.teach[item][1]) then
			out.teach[item] = { spell, s.skill or 0 }
		end
	end
	for item, price in pairs(assert(ns.VendorPrices, "Vendor.lua: no VendorPrices")) do
		out.vendor[item] = price
	end
	for item, price in pairs(ns.ItemSellPrices or {}) do
		out.sell[item] = price
	end
	-- Top level and the "sources" lists one entry per line; every map entry on a line of its own.
	local text = {}
	local keys = {}
	for k in pairs(out) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = out[k]
		local depth = (k == "sources") and 2 or (type(v) == "table" and 1 or 0)
		text[#text + 1] = "\t" .. String(k) .. ": " .. Encode(v, depth, "\t")
	end
	return "{\n" .. table.concat(text, ",\n") .. "\n}\n"
end

local function Standalone()
	local text = G.Build("")
	local f = assert(io.open(G.OUT, "wb"))
	f:write(text)
	f:close()
	print(("wrote %s (%d bytes)"):format(G.OUT, #text))
end

if arg and arg[0] and arg[0]:match("gen_site_recipes%.lua$") then
	Standalone()
end

return G
