-- Usage (repo root): lua5.1 tests/run.lua
-- Each spec gets a fresh client stub and a freshly loaded addon.
package.path = "./tests/?.lua;" .. package.path

local TOC = "CraftWise/CraftWise.toc"

local function tocFiles()
	local files = {}
	for line in io.lines(TOC) do
		if not line:match("^%s*#") and line:match("%S") then
			table.insert(files, "CraftWise/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
		end
	end
	return files
end

-- Fresh globals per spec: clear everything the stub or addon defines.
local baseline
local function resetGlobals()
	for k in pairs(_G) do
		if not baseline[k] then _G[k] = nil end
	end
	package.loaded.wowstub = nil
end

function LoadAddon(opts)
	resetGlobals()
	local stub = require("wowstub")
	if opts and opts.auctionator then stub.EnableAuctionator() end
	local ns = {}
	for _, path in ipairs(tocFiles()) do
		-- Bundled data is large; specs opt in with { data = true } and otherwise set tiny tables.
		if opts and opts.data or not path:match("/Data/") then
		local chunk = assert(loadfile(path))
		chunk("CraftWise", ns)
		end
	end
	if opts and opts.savedDB then CraftWiseDB = opts.savedDB end
	stub.Fire("ADDON_LOADED", "CraftWise")
	return ns, stub
end

local passed, failed = 0, 0
function it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end
function eq(actual, expected, msg)
	if actual ~= expected then
		error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

baseline = {}
for k in pairs(_G) do baseline[k] = true end

local specs = { "profit_spec", "prices_spec", "recipes_spec", "trainer_spec", "money_spec", "ui_spec", "data_spec", "bags_spec", "crafts_spec" }
for _, spec in ipairs(specs) do
	print(spec)
	dofile("tests/" .. spec .. ".lua")
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
