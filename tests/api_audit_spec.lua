-- Every client API and event CraftWise uses must exist in WoW: Forever.
-- Source of truth: tests/forever_api.lua (generated from Blizzard's own API documentation for the
-- Forever client, see tools/gen_api_index.lua). Undocumented legacy functions are listed in
-- tests/api_allowlist.lua, each with how it was verified. Anything else fails this spec, so an API
-- that only exists on other clients (like the global GetItemInfo) is caught before the game is.
local api = dofile("tests/forever_api.lua")
local allow = dofile("tests/api_allowlist.lua")

local function read(path)
	local f = assert(io.open(path))
	local s = f:read("*a")
	f:close()
	return s
end

local function sourceFiles()
	local files = {}
	for line in io.lines("CraftWise/CraftWise.toc") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") and not line:match("^Data\\") then
			files[#files + 1] = "CraftWise/" .. line:gsub("\\", "/"):gsub("%s+$", "")
		end
	end
	return files
end

-- Strip comments and string contents so they don't look like calls.
local function code(src)
	src = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	return src
end

-- Names a file defines itself (locals, its functions, parameters) are not client calls there.
-- Globals the addon defines (function Foo / Foo = / _G.Foo) count for every file.
local function definitions(src, globalsOnly)
	local defined = {}
	if not globalsOnly then
		for name in src:gmatch("local%s+function%s+([%a_][%w_]*)") do defined[name] = true end
		for names in src:gmatch("local%s+([%a_][%w_,%s]*)") do
			for name in names:gmatch("[%a_][%w_]*") do defined[name] = true end
		end
		for params in src:gmatch("function[%w_%.:%s]*%(([^)]*)%)") do
			for name in params:gmatch("[%a_][%w_]*") do defined[name] = true end
		end
	end
	for name in src:gmatch("\nfunction%s+([%a_][%w_]*)%s*%(") do defined[name] = true end
	for name in src:gmatch("_G%.([%a_][%w_]*)%s*=") do defined[name] = true end
	for name in src:gmatch("\n([%u][%w_]*)%s*=") do defined[name] = true end
	return defined
end

local function collect()
	local calls, events = {}, {}
	local all = {}
	for _, path in ipairs(sourceFiles()) do
		all[path] = code(read(path))
	end
	local globals = {}
	for _, src in pairs(all) do
		for name in pairs(definitions(src, true)) do globals[name] = true end
	end
	for path, src in pairs(all) do
		local defined = definitions(src)
		-- C_Namespace.Function and plain Global( calls (not methods, not fields of our tables).
		for ns_, fn in src:gmatch("(C_[%w_]+)%.([%w_]+)") do
			calls[ns_ .. "." .. fn] = calls[ns_ .. "." .. fn] or path
		end
		for _, name in src:gmatch("([%s%(%[{=,!~<>%+%-%*/]+)([%u][%w_]*)%s*%(") do
			if not defined[name] and not globals[name] then
				calls[name] = calls[name] or path
			end
		end
		for name in src:gmatch("pcall%(%s*([%u][%w_]*)%s*[,)]") do
			if not defined[name] and not globals[name] then
				calls[name] = calls[name] or path
			end
		end
		for name in src:gmatch("ns%.On%(%s*\"([%u_]+)\"") do events[name] = path end
		for list in src:gmatch("ipairs%(%s*{([^}]*)}%s*%)%s*do%s*ns%.On") do
			for name in list:gmatch("\"([%u_]+)\"") do events[name] = path end
		end
		for name in src:gmatch("RegisterEvent%(%s*\"([%u_]+)\"") do events[name] = path end
	end
	return calls, events
end

it("every function CraftWise calls exists in the Forever client", function()
	local calls = collect()
	local missing = {}
	for name, path in pairs(calls) do
		if not api.functions[name] and not allow.functions[name] and not allow.lua[name] then
			missing[#missing + 1] = name .. " (" .. path .. ")"
		end
	end
	table.sort(missing)
	assert(#missing == 0, "not in Forever API docs or allowlist: " .. table.concat(missing, ", "))
end)

it("every event CraftWise registers exists in the Forever client", function()
	local _, events = collect()
	local missing = {}
	local n = 0
	for name, path in pairs(events) do
		n = n + 1
		if not api.events[name] and not allow.events[name] then
			missing[#missing + 1] = name .. " (" .. path .. ")"
		end
	end
	table.sort(missing)
	assert(n > 10, "event scan found too few events")
	assert(#missing == 0, "events not in Forever API docs: " .. table.concat(missing, ", "))
end)

it("the allowlist only holds functions the docs don't cover", function()
	for name in pairs(allow.functions) do
		assert(not api.functions[name], name .. " is documented now - remove it from the allowlist")
	end
end)
