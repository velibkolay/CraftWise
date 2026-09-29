local _, ns = ...

local GOLD, SILVER = 10000, 100
local ICON = "|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"

-- Formats copper as "12g 34s 56c" (icons in game). Negative values keep a leading "-".
-- Leading zero units are dropped; trailing ones too, but at least one unit is shown.
function ns.FormatMoney(copper, plain)
	if copper == nil then
		return "?"
	end
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local g = math.floor(copper / GOLD)
	local s = math.floor((copper % GOLD) / SILVER)
	local c = copper % SILVER
	local parts = {}
	local function unit(n, letter, icon)
		parts[#parts + 1] = n .. (plain and letter or ICON:format(icon))
	end
	if g > 0 then
		unit(g, "g", "Gold")
	end
	if s > 0 then
		unit(s, "s", "Silver")
	end
	if c > 0 or #parts == 0 then
		unit(c, "c", "Copper")
	end
	return sign .. table.concat(parts, " ")
end
