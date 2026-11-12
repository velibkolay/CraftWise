-- Records window, Snapshot tab (`/craftwise snapshot`, #63): save the character snapshot now and see when it
-- was last saved and which sections it holds. The client writes SavedVariables to disk only on /reload,
-- logout or quit, so a Reload UI button sits next to Save.
local _, ns = ...
local RW = ns.RW
local L = ns.L
local C = ns.Style.colors
local Muted = RW.Muted

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local tab = { key = "snapshot", label = L["Snapshot"] }

tab.columns = {
	{ key = "name", label = L["SECTION"], width = 220 },
	{ key = "status", label = L["IN THE LAST SNAPSHOT"], width = 540 },
}

-- Saves now; keeps the outcome for the summary. Returns "saved" or "failed".
function tab.Save(st)
	local ok, snap = pcall(ns.Snapshot.Save)
	if ok and snap then
		st.snapshotNote = C.good .. L["Snapshot saved."] .. "|r " .. Muted(L["Reload the UI or log out to write it to disk."])
		return "saved"
	end
	st.snapshotNote = C.bad .. L["Snapshot failed:"] .. "|r " .. tostring(ok and L["character not loaded yet"] or snap)
	return "failed"
end

function tab.buttons(st)
	return {
		{ key = "save", label = L["Save snapshot"], width = 120, onClick = function()
			tab.Save(st)
		end, tip = L["Writes the character snapshot (character, gear, professions, quests, ledger, fishing, auctions, market, crates, farm) into CraftWiseDB. Also done on every logout and reload."] },
		{ key = "reload", label = L["Reload UI"], width = 100, onClick = function()
			if C_UI and C_UI.Reload then
				C_UI.Reload()
			end
		end, tip = L["Reloads the interface: the client writes the saved variables (and the snapshot) to disk."] },
	}
end

function tab.Model(st)
	local S = ns.Snapshot
	local key = S.Key()
	local snap = key and ns.db and ns.db.snapshots and ns.db.snapshots[key]
	local rows = {}
	for _, section in ipairs(S.SECTIONS) do
		local name = section[1]
		local status
		if not snap then
			status = Muted("-")
		elseif snap.errors and snap.errors[name] then
			status = C.bad .. L["error:"] .. "|r " .. tostring(snap.errors[name])
		elseif snap.skipped and snap.skipped[name] then
			status = C.warn .. L["skipped:"] .. "|r " .. tostring(snap.skipped[name])
		elseif snap[name] ~= nil then
			status = C.good .. L["saved"] .. "|r"
		else
			status = Muted(L["not in it"])
		end
		rows[#rows + 1] = { icon = ICON, name = name, cells = { status = status } }
	end
	local line1
	if snap and snap.t then
		line1 = ("|cffffffff%s|r  ·  %s %s (%s %s)  ·  %s"):format(L["Snapshot"], L["last saved"], date("%Y-%m-%d %H:%M", snap.t),
			RW.Ago(snap.t), L["ago"], key)
	else
		line1 = ("|cffffffff%s|r  ·  %s"):format(L["Snapshot"], key and L["not saved yet for this character"] or L["character not loaded yet"])
	end
	local line2 = st.snapshotNote or Muted(L["For Claude: WTF/Account/<account>/SavedVariables/CraftWise.lua, current after a reload, logout or quit."])
	return { rows = rows, summary = line1 .. "\n" .. line2, empty = "" }
end

RW.Register(tab)
RW.Snapshot = tab
