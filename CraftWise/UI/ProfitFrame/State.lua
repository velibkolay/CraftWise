-- Profit table window: shared constants, state and small helpers.
-- The window is split by responsibility (State, Fishing, Data, Rows, Tooltips, SongPicker, Layout, Refresh,
-- Frame, Events). The files share their internals through ns.PF and load in the order CraftWise.toc lists them:
-- a file only uses what the files before it export.
local _, ns = ...
local Style = ns.Style
local L = ns.L
local C = Style.colors

local WIDTH, HEIGHT = 900, 580
local PAD = 16
local ROW_HEIGHT = 36
local HEADER_Y = -150 -- top of the column header row
local LIST_TOP = HEADER_Y - 22
local VISIBLE_ROWS = math.floor((HEIGHT + LIST_TOP - 40) / ROW_HEIGHT)

-- Column definitions; each view lists the columns it shows, in order, with widths.
local COLUMN_DEFS = {
	name = { label = L["RECIPE"], align = "LEFT" },
	cost = { label = L["COST"], align = "RIGHT" },
	sellsFor = { label = L["SELLS FOR"], align = "RIGHT" },
	profit = { label = L["PROFIT"], align = "RIGHT" },
	learnCost = { label = L["TO LEARN"], align = "RIGHT" },
	breakEven = { label = L["PAYS OFF"], align = "RIGHT" },
	required = { label = L["SKILL"], align = "RIGHT" },
	whereText = { label = L["WHERE TO GET IT"], align = "LEFT" },
	equippedText = { label = L["REPLACES"], align = "LEFT" },
	gain = { label = L["UPGRADE"], align = "LEFT" },
	songText = { label = L["SONG"], align = "LEFT" },
	modeText = { label = L["NEXT CAST"], align = "LEFT" },
	chance = { label = L["CHANCE"], align = "LEFT" },
	saleValue = { label = L["SALE"], align = "RIGHT" },
	net = { label = L["NET / CRAFT"], align = "RIGHT" },
	perPoint = { label = L["PER SKILL-UP"], align = "RIGHT" },
	sample = { label = L["SAMPLE"], align = "RIGHT" },
	topCatches = { label = L["TOP CATCHES"], align = "LEFT" },
	perCatch = { label = L["PER CATCH"], align = "RIGHT" },
	perHour = { label = L["PER HOUR"], align = "RIGHT" },
	fishChance = { label = L["CHANCE"], align = "RIGHT" },
	unitValue = { label = L["UNIT VALUE"], align = "RIGHT" },
}
local VIEWS = {
	-- Profit: what to craft. The learn columns only show with unlearned recipes.
	profit = {
		{ key = "name", width = 260 },
		{ key = "cost", width = 100 },
		{ key = "sellsFor", width = 130 },
		{ key = "profit", width = 100 },
		{ key = "learnCost", width = 95, learn = true },
		{ key = "breakEven", width = 75, learn = true },
	},
	-- Learn: every recipe you don't know yet, where to get it and what it earns.
	learn = {
		{ key = "name", width = 245 },
		{ key = "required", width = 50 },
		{ key = "whereText", width = 280 },
		{ key = "learnCost", width = 95 },
		{ key = "profit", width = 100 },
	},
	-- Level: which known recipe levels the profession for the least money (Leveling.lua).
	level = {
		{ key = "name", width = 215 },
		{ key = "chance", width = 150 },
		{ key = "cost", width = 90 },
		{ key = "saleValue", width = 105 },
		{ key = "net", width = 95 },
		{ key = "perPoint", width = 115 },
	},
	-- Upgrades: items from your recipes that beat what you wear.
	upgrades = {
		{ key = "name", width = 280 },
		{ key = "equippedText", width = 220 },
		{ key = "gain", width = 150 },
		{ key = "cost", width = 110 },
	},
	-- Music: a song per profession while you level it.
	music = {
		{ key = "name", width = 260 },
		{ key = "songText", width = 300 },
		{ key = "modeText", width = 240 },
	},
	-- Fishing (#88): zones by value per catch; a zone's loot table (fishzone).
	fishing = {
		{ key = "name", width = 220 },
		{ key = "sample", width = 95 },
		{ key = "topCatches", width = 245 },
		{ key = "perCatch", width = 120 },
		{ key = "perHour", width = 85 },
	},
	fishzone = {
		{ key = "name", width = 220 },
		{ key = "fishChance", width = 110 },
		{ key = "sample", width = 120 },
		{ key = "unitValue", width = 195 },
		{ key = "perCatch", width = 120 },
	},
}
local CELL_KEYS = { "cost", "sellsFor", "profit", "learnCost", "breakEven", "required", "whereText",
	"equippedText", "gain", "songText", "modeText",
	"chance", "saleValue", "net", "perPoint", "sample", "topCatches", "perCatch", "perHour", "fishChance", "unitValue" }

local QUALITY_COLORS = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }

local STATUS_TEXT = {
	known = L["Known"],
	trainable = L["Trainer"],
	vendor = L["Vendor recipe"],
	drop = L["Drop recipe"],
	quest = L["Quest recipe"],
	unlearned = L["Source not known yet"],
}

-- Texture arrows: the game font has no triangle glyphs.
local ARROW_DOWN = " |TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-3|t"
local ARROW_UP = " |TInterface\\Buttons\\Arrow-Up-Up:12:12:0:3|t"

-- Recipe name colours as in the game's profession window.
local SKILL_COLORS = {
	red = "|cffff4040", orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40bf40", grey = "|cff808080",
}

local rows, tabs, viewButtons = {}, {}, {} -- the window itself is PF.frame, set by Frame.lua
local state = { professionID = nil, offset = 0, data = {}, query = "", hidden = 0 }

local function Settings()
	return ns.db.settings
end

local function Money(copper)
	return ns.FormatMoney(copper)
end

local function Muted(text)
	return C.muted .. text .. "|r"
end

local function ItemName(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
	if not name and C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(itemID)
	end
	return name or ("item " .. itemID)
end

local function StatusLine(r)
	local text = STATUS_TEXT[r.status] or r.status
	if r.status == "known" then
		return Muted(text)
	end
	local parts = { text }
	if r.required then
		parts[#parts + 1] = ("skill %d"):format(r.required)
	end
	local color = C.good
	if r.tooLow then
		color = C.warn
	elseif r.status == "unlearned" then
		color = C.muted
	end
	return color .. table.concat(parts, " · ") .. "|r"
end

-- "typical · Horde AH": what auction prices in the window are based on (#26 phase 2).
local function PriceBasisText()
	local basis = ns.PriceSettings()
	local _, label = ns.ProfitHouse()
	return ns.BASIS_TEXT[basis] .. " · " .. (label or "own faction AH")
end

-- Short tag for where "Sells for" comes from (#48): "vendor", "AH", or "AH gross" when the house's
-- cut is unverified (no net value); nil without a sale value.
local function SaleTag(source, cutUnverified)
	if source == "vendor" then
		return "vendor"
	elseif source == "auction" then
		return cutUnverified and "AH gross" or "AH"
	end
	return nil
end

-- "reagents: AH" / "reagents: paid cost, else AH": the reagent cost basis of a view (#47).
local function CostBasisText(view)
	if ns.CostBasis(view) == "paid" then
		return "reagents: paid cost, else AH"
	end
	return "reagents: AH"
end

local function View()
	local v = Settings().view
	return (v == "learn" or v == "level" or v == "upgrades" or v == "music" or v == "fishing") and v or "profit"
end

-- Upgrades view section: "craft" (Craftable, #16) or "ah" (General / AH, #50).
local function UpgradeSection()
	return Settings().upgradeSection == "ah" and "ah" or "craft"
end

-- Views that list items across all professions (no profession tabs).
local function ItemView()
	return View() == "upgrades" or View() == "music" or View() == "fishing"
end

-- Shared with the other ProfitFrame files.
ns.PF = {
	WIDTH = WIDTH, HEIGHT = HEIGHT, PAD = PAD, ROW_HEIGHT = ROW_HEIGHT, HEADER_Y = HEADER_Y, LIST_TOP = LIST_TOP,
	VISIBLE_ROWS = VISIBLE_ROWS,
	COLUMN_DEFS = COLUMN_DEFS, VIEWS = VIEWS, CELL_KEYS = CELL_KEYS,
	QUALITY_COLORS = QUALITY_COLORS, SKILL_COLORS = SKILL_COLORS,
	ARROW_DOWN = ARROW_DOWN, ARROW_UP = ARROW_UP,
	rows = rows, tabs = tabs, viewButtons = viewButtons, state = state,
	Settings = Settings, Money = Money, Muted = Muted, ItemName = ItemName, StatusLine = StatusLine,
	View = View, ItemView = ItemView, PriceBasisText = PriceBasisText, SaleTag = SaleTag, CostBasisText = CostBasisText, UpgradeSection = UpgradeSection,
}
