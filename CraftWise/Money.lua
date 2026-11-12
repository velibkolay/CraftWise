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

-- Money in the Origami look (#150 Rules): digits in the coin colours, at most two units, starting at the
-- largest one present ("12g 40s", "66s 20c", "7c"); a zero second unit is left out ("3g"). Smaller units
-- are cut, not rounded. Negative values get a "−". For mono FontStrings (CraftWiseFontFigure*).
function ns.FormatCoins(copper)
	if copper == nil then
		return nil
	end
	local Style = ns.Style
	local sign = copper < 0 and "−" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local units = {
		{ math.floor(copper / GOLD), "g", "coinGold" },
		{ math.floor((copper % GOLD) / SILVER), "s", "coinSilver" },
		{ copper % SILVER, "c", "coinCopper" },
	}
	local first = 3
	for i = 1, 3 do
		if units[i][1] > 0 then
			first = i
			break
		end
	end
	local parts = {}
	for i = first, math.min(first + 1, 3) do
		local u = units[i]
		if i == first or u[1] > 0 then
			parts[#parts + 1] = Style.Hex(u[3]) .. u[1] .. u[2] .. "|r"
		end
	end
	return sign .. table.concat(parts, " ")
end
