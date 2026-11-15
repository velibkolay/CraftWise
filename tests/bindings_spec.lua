-- Issue #306: the client declares a binding header every time it sees `header="..."`, so a header
-- name may appear on one binding only (a second declaration raises "Binding header X was attempted
-- to be loaded more than once"). Later bindings of the group stay under it without the attribute.
local f = assert(io.open("CraftWise/Bindings.xml", "rb"))
local xml = f:read("*a")
f:close()

it("#306: every binding header in Bindings.xml is declared once", function()
	local seen, count = {}, 0
	for tag in xml:gmatch("<Binding%s[^>]*>") do
		local header = tag:match('header%s*=%s*"([^"]*)"')
		if header then
			count = count + 1
			assert(not seen[header], "binding header " .. header .. " is declared more than once")
			seen[header] = true
		end
	end
	assert(count >= 1, "no binding header found")
end)

it("#306: the three bindings are still there, the first one carries CRAFTWISE", function()
	local names = {}
	for name in xml:gmatch('<Binding%s+name%s*=%s*"([^"]*)"') do
		names[#names + 1] = name
	end
	eq(table.concat(names, ","), "CRAFTWISE_PARTY,CRAFTWISE_MAIN,CRAFTWISE_FARM")
	assert(xml:match('<Binding%s+name="CRAFTWISE_PARTY"%s+header="CRAFTWISE"'), "first binding lost the header")
end)
