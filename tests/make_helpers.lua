-- Helpers for specs that look at the Make pages of the main window (#154): open a page, read the rows it
-- shows, hover or click one. Loaded per spec with dofile (globals are reset between addon loads).
local H = {}

-- Opens the main window on a Make page ("craft" | "learn" | "level") for a profession. Without AH data
-- the page shows No prices; vendorOnly = true (the default here) clicks Show vendor-only profits.
function H.Open(ns, page, professionID, vendorOnly)
	local M = ns.Main
	if professionID then
		M.UI().profession = professionID
	end
	if vendorOnly ~= false then
		M.state.vendorOnly[page] = true
	end
	M.Open(page)
	return M.ListOf(page)
end

-- The row frames the page's list shows, in order (opened parts left out).
function H.Frames(ns, page)
	local list = ns.Main.ListOf(page)
	local out = {}
	for _, fr in ipairs(list and list.box.frames or {}) do
		if fr.elementData and not fr.elementData.open then
			out[#out + 1] = fr
		end
	end
	return out
end

-- The rows (model rows with their view) the page shows, in order.
function H.Rows(ns, page)
	local out = {}
	for _, fr in ipairs(H.Frames(ns, page)) do
		out[#out + 1] = fr.elementData.row
	end
	return out
end

function H.Names(ns, page)
	local out = {}
	for _, r in ipairs(H.Rows(ns, page)) do
		out[#out + 1] = r.name
	end
	return table.concat(out, ",")
end

function H.Frame(ns, page, recipeID)
	for _, fr in ipairs(H.Frames(ns, page)) do
		if fr.elementData.row.recipeID == recipeID then
			return fr
		end
	end
end

-- Hovers the row of a recipe; returns true when it was shown.
function H.Hover(ns, page, recipeID)
	local fr = H.Frame(ns, page, recipeID)
	if not fr then
		return false
	end
	fr.scripts.OnEnter(fr)
	fr.scripts.OnLeave(fr)
	return true
end

-- Records what GameTooltip gets while fn runs: lines "left | right" and single lines, colour codes and
-- textures stripped.
function H.CaptureTooltip(fn)
	local function plain(s)
		s = tostring(s or "")
		s = s:gsub("|T[^|]*|t", function(t)
			local coin = t:match("UI%-(%a+)Icon")
			return coin == "Gold" and "g" or coin == "Silver" and "s" or coin == "Copper" and "c" or ""
		end)
		return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local seen = {}
	local add, add2 = GameTooltip.AddLine, GameTooltip.AddDoubleLine
	GameTooltip.AddLine = function(self, l, ...) seen[#seen + 1] = plain(l); return add(self, l, ...) end
	GameTooltip.AddDoubleLine = function(self, l, r, ...) seen[#seen + 1] = plain(l) .. " | " .. plain(r); return add2(self, l, r, ...) end
	local ok, err = pcall(fn)
	GameTooltip.AddLine, GameTooltip.AddDoubleLine = add, add2
	if not ok then
		error(err, 2)
	end
	return table.concat(seen, "\n")
end

-- The Make tools of a page: { profession = chip, filter = edit box }.
function H.Tools(ns, page)
	local s = ns.Main.SlotsOf(page)
	return s and s.tools
end

-- Types into the filter box.
function H.Filter(ns, page, text)
	local box = H.Tools(ns, page).filter
	box:SetText(text)
	box.scripts.OnTextChanged(box)
end

return H
