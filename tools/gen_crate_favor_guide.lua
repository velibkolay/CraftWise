-- Writes CraftWise/Data/CrateFavorGuide.lua from web/site/lib/crateFavorGuide.ts (#176), the one source of
-- truth for the crate Favor guide values of the site and the addon. Nothing is added: the header comment, the
-- sources and the table rows are read from the TypeScript file.
--
--   lua5.1 tools/gen_crate_favor_guide.lua     (repo root) rewrites CraftWise/Data/CrateFavorGuide.lua
--
-- tests/crate_favor_guide_spec.lua (in tests/run.lua) fails while the committed file differs from what this
-- script writes. Lua 5.1, stdlib only.
local G = {}

G.SRC = "web/site/lib/crateFavorGuide.ts"
G.OUT = "CraftWise/Data/CrateFavorGuide.lua"

local function Read(path)
	local f = assert(io.open(path, "rb"), path .. " missing")
	local text = f:read("*a")
	f:close()
	return (text:gsub("\r\n", "\n"))
end

function G.Build(ts)
	ts = ts or Read(G.SRC)
	local header = {}
	for line in ts:gmatch("([^\n]*)\n") do
		local c = line:match("^//%s?(.*)$")
		if not c then
			break
		end
		header[#header + 1] = c
	end
	assert(#header > 0, "source header not found")
	local sources = {}
	for label, url, updated in ts:gmatch('{ label: "([^"]+)", url: "([^"]+)", updated: "([^"]+)" }') do
		sources[#sources + 1] = { label = label, url = url, updated = updated }
	end
	assert(#sources > 0, "GUIDE_SOURCES not found")
	local body = ts:match("const TABLE[^\n]*= {\n(.-)\n};")
	assert(body, "TABLE not found")
	local rows = {}
	for rank, cells in (body .. "\n"):gmatch("%s*(%a+): {(.-)},?\n") do
		local list = {}
		for kind, basis, favor in cells:gmatch("(%a+): ([LR])%((%d+)%)") do
			list[#list + 1] = ("%s = { %d, %q }"):format(kind, tonumber(favor), basis == "L" and "listed" or "rule")
		end
		table.sort(list)
		rows[#rows + 1] = ("\t%s = { %s },"):format(rank, table.concat(list, ", "))
	end
	assert(#rows > 0, "no table rows")
	table.sort(rows)
	local out = {}
	for _, h in ipairs(header) do
		out[#out + 1] = ("-- " .. h):gsub("%s+$", "")
	end
	out[#out + 1] = "-- Generated from web/site/lib/crateFavorGuide.ts by tools/gen_crate_favor_guide.lua; do not edit."
	out[#out + 1] = "local _, ns = ..."
	out[#out + 1] = "ns.CrateFavorGuide = {"
	out[#out + 1] = "\tsources = {"
	for _, s in ipairs(sources) do
		out[#out + 1] = ("\t\t{ label = %q, url = %q, updated = %q },"):format(s.label, s.url, s.updated)
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "\t-- [rank][kind] = { Favor per crate, basis }; basis \"listed\" = a guide lists the crate, \"rule\" = only the rank rule."
	out[#out + 1] = "\ttable = {"
	for _, r in ipairs(rows) do
		out[#out + 1] = "\t" .. r
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "}"
	return table.concat(out, "\n") .. "\n"
end

if arg and arg[0] and arg[0]:match("gen_crate_favor_guide%.lua$") then
	local text = G.Build()
	local f = assert(io.open(G.OUT, "wb"))
	f:write(text)
	f:close()
	print(("wrote %s (%d bytes)"):format(G.OUT, #text))
end

return G
