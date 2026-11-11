package savedvars

import "github.com/velibkolay/CraftWise/companion/svparse"

// Snapshot is CraftWiseDB.snapshots["<realm>-<name> <surname>"] (#63), field by field as
// docs/snapshot.md describes it. A section the snapshot doesn't have is nil (its reason is in
// Skipped or Errors). Raw is the whole table, for anything not typed here.
type Snapshot struct {
	V       *int64            `json:"v,omitempty"`
	T       *int64            `json:"t,omitempty"`
	Legacy  bool              `json:"legacy,omitempty"`
	Skipped map[string]string `json:"skipped,omitempty"`
	Errors  map[string]string `json:"errors,omitempty"`

	Char        *Character   `json:"char,omitempty"`
	Location    *Location    `json:"location,omitempty"`
	Equipment   *Equipment   `json:"equipment,omitempty"`
	Professions []Profession `json:"professions,omitempty"`
	// RecipesLearned is the recently learned recipes, newest first (#107).
	RecipesLearned []LearnedRecipe   `json:"recipesLearned,omitempty"`
	Quests         *Quests           `json:"quests,omitempty"`
	Reputations    *Reputations      `json:"reputations,omitempty"`
	Pet            *Pet              `json:"pet,omitempty"`
	Holdings       *Holdings         `json:"holdings,omitempty"`
	Ledger         map[string]Totals `json:"ledger,omitempty"` // "today", "reset"
	FlightPaths    *FlightPaths      `json:"flightPaths,omitempty"`
	Fishing        *FishingSummary   `json:"fishing,omitempty"`
	FishingZones   *FishingZones     `json:"fishingZones,omitempty"`
	Auctions       *AuctionSummary   `json:"auctions,omitempty"`
	Market         *MarketSummary    `json:"market,omitempty"`
	Crates         *Crates           `json:"crates,omitempty"`
	Favor          *Favor            `json:"favor,omitempty"`

	Raw *svparse.Table `json:"-" lua:"-"`
}

type Character struct {
	Name    string `json:"name,omitempty"`
	Surname string `json:"surname,omitempty"`
	Realm   string `json:"realm,omitempty"`
	Faction string `json:"faction,omitempty"`
	Race    string `json:"race,omitempty"`
	Class   string `json:"class,omitempty"`
	Level   *int64 `json:"level,omitempty"`
	XP      *int64 `json:"xp,omitempty"`
	XPMax   *int64 `json:"xpMax,omitempty"`
	Rested  *int64 `json:"rested,omitempty"`
	Money   *int64 `json:"money,omitempty"`
	// Guild: the guild name (string), false = not in a guild, nil = not sent by the client yet.
	Guild any `json:"guild,omitempty"`
}

type Location struct {
	Zone        string   `json:"zone,omitempty"`
	Subzone     *string  `json:"subzone,omitempty"` // "" = the client names no subzone
	MinimapZone string   `json:"minimapZone,omitempty"`
	MapID       *int64   `json:"mapID,omitempty"`
	Map         string   `json:"map,omitempty"`
	X           *float64 `json:"x,omitempty"`
	Y           *float64 `json:"y,omitempty"`
	Resting     *bool    `json:"resting,omitempty"`
}

type Equipment struct {
	Items []EquippedItem `json:"items"`
	Empty []string       `json:"empty"`
}

type EquippedItem struct {
	Slot   string   `json:"slot"`
	ID     int64    `json:"id"`
	Link   string   `json:"link,omitempty"`
	ILvl   *float64 `json:"ilvl,omitempty"`
	Armor  *int64   `json:"armor,omitempty"`
	Stats  string   `json:"stats,omitempty"`
	Dur    *int64   `json:"dur,omitempty"`
	DurMax *int64   `json:"durMax,omitempty"`
}

type Profession struct {
	Name         string `json:"name,omitempty"`
	Kind         string `json:"kind,omitempty"`
	Skill        *int64 `json:"skill,omitempty"`
	Max          *int64 `json:"max,omitempty"`
	Line         *int64 `json:"line,omitempty"`
	RecipesKnown *int64 `json:"recipesKnown,omitempty"`
	Scanned      *int64 `json:"scanned,omitempty"`
	Cached       *bool  `json:"cached,omitempty"`
	// Known is the learned recipe IDs, ascending, as "id,id,..." (#107).
	Known string `json:"known,omitempty"`
}

// LearnedRecipe is one recently learned recipe (#107). How "event": learned at T; how "scan": learned
// between After and T.
type LearnedRecipe struct {
	ID         int64  `json:"id"`
	Name       string `json:"name,omitempty"`
	Profession string `json:"profession,omitempty"`
	T          *int64 `json:"t,omitempty"`
	How        string `json:"how,omitempty"`
	After      *int64 `json:"after,omitempty"`
}

type Quests struct {
	List             []Quest  `json:"list"`
	InLog            *int64   `json:"inLog,omitempty"`
	Read             *int64   `json:"read,omitempty"`
	CollapsedHeaders []string `json:"collapsedHeaders,omitempty"`
	Hidden           *int64   `json:"hidden,omitempty"`
}

type Quest struct {
	ID         int64       `json:"id"`
	Title      string      `json:"title,omitempty"`
	Level      *int64      `json:"level,omitempty"`
	Zone       string      `json:"zone,omitempty"`
	Group      *int64      `json:"group,omitempty"`
	Complete   *bool       `json:"complete,omitempty"`
	Failed     *bool       `json:"failed,omitempty"`
	Objectives []Objective `json:"objectives,omitempty"`
}

type Objective struct {
	Text string `json:"text,omitempty"`
	Have *int64 `json:"have,omitempty"`
	Need *int64 `json:"need,omitempty"`
	Done bool   `json:"done"`
}

type Reputations struct {
	List             []Reputation `json:"list"`
	CollapsedHeaders []string     `json:"collapsedHeaders,omitempty"`
}

type Reputation struct {
	ID       *int64 `json:"id,omitempty"`
	Name     string `json:"name,omitempty"`
	Header   string `json:"header,omitempty"`
	Reaction *int64 `json:"reaction,omitempty"`
	Standing string `json:"standing,omitempty"`
	Value    *int64 `json:"value,omitempty"`
	Min      *int64 `json:"min,omitempty"`
	Max      *int64 `json:"max,omitempty"`
	AtWar    bool   `json:"atWar,omitempty"`
}

type Pet struct {
	Name          string `json:"name,omitempty"`
	Level         *int64 `json:"level,omitempty"`
	Family        string `json:"family,omitempty"`
	Happiness     *int64 `json:"happiness,omitempty"`
	HappinessText string `json:"happinessText,omitempty"`
	Loyalty       string `json:"loyalty,omitempty"`
}

type Holdings struct {
	Bags       map[int64]int64  `json:"bags,omitempty"`
	Bank       *SeenItems       `json:"bank,omitempty"`
	Mail       *SeenItems       `json:"mail,omitempty"`
	Names      map[int64]string `json:"names,omitempty"`
	NotCounted []string         `json:"notCounted,omitempty"`
}

// SeenItems is the bank or the mailbox as last seen (t = when).
type SeenItems struct {
	T     *int64          `json:"t,omitempty"`
	Mails *int64          `json:"mails,omitempty"`
	Items map[int64]int64 `json:"items,omitempty"`
}

// Totals is one ledger view of the snapshot (#46). StartMoney, Change and Other are nil when the
// start money wasn't seen.
type Totals struct {
	Since      *int64 `json:"since,omitempty"`
	StartMoney *int64 `json:"startMoney,omitempty"`
	Money      *int64 `json:"money,omitempty"`
	Change     *int64 `json:"change,omitempty"`
	Spent      *int64 `json:"spent,omitempty"`
	Received   *int64 `json:"received,omitempty"`
	Net        *int64 `json:"net,omitempty"`
	Other      *int64 `json:"other,omitempty"`
}

type FlightPaths struct {
	Maps []TaxiMap `json:"maps"`
}

type TaxiMap struct {
	MapID int64      `json:"mapID"`
	Map   string     `json:"map,omitempty"`
	T     *int64     `json:"t,omitempty"`
	Nodes []TaxiNode `json:"nodes"`
}

type TaxiNode struct {
	ID         *int64   `json:"id,omitempty"`
	Name       string   `json:"name,omitempty"`
	X          *float64 `json:"x,omitempty"`
	Y          *float64 `json:"y,omitempty"`
	State      string   `json:"state,omitempty"`
	Current    bool     `json:"current,omitempty"`
	Known      *bool    `json:"known,omitempty"`
	Transition bool     `json:"transition,omitempty"`
}

// FishingSummary is the snapshot's fishing ranking (#69, #86): this character, last 90 days.
type FishingSummary struct {
	Days              *int64        `json:"days,omitempty"`
	Catches           *int64        `json:"catches,omitempty"`
	ContainersOpened  *int64        `json:"containersOpened,omitempty"`
	SessionGapMinutes *float64      `json:"sessionGapMinutes,omitempty"`
	FindFish          *FindFish     `json:"findFish,omitempty"`
	Spots             []FishingSpot `json:"spots"`
	MoreSpots         *int64        `json:"moreSpots,omitempty"`
	Pools             []FishingPool `json:"pools"`
	MorePools         *int64        `json:"morePools,omitempty"`
}

type FindFish struct {
	SpellID  *int64 `json:"spellID,omitempty"`
	Known    *bool  `json:"known,omitempty"`
	Tracking *bool  `json:"tracking,omitempty"`
}

type FishingSpot struct {
	Zone     string   `json:"zone,omitempty"`
	Sub      string   `json:"sub"`
	Water    string   `json:"water,omitempty"` // "open", "pool", "?"
	Obj      *int64   `json:"obj,omitempty"`
	Pool     string   `json:"pool,omitempty"`
	N        *int64   `json:"n,omitempty"`
	PerCatch *float64 `json:"perCatch,omitempty"`
	PerHour  *float64 `json:"perHour,omitempty"`
	Timed    *int64   `json:"timed,omitempty"`
	Minutes  *float64 `json:"minutes,omitempty"`
	Unpriced *int64   `json:"unpriced,omitempty"`
	Top      string   `json:"top,omitempty"`
}

type FishingPool struct {
	Obj       *int64 `json:"obj,omitempty"`
	Name      string `json:"name,omitempty"`
	Visits    *int64 `json:"visits,omitempty"`
	PerVisit  string `json:"perVisit,omitempty"`
	Going     *int64 `json:"going,omitempty"`
	Seen      *int64 `json:"seen,omitempty"`
	NotFished *int64 `json:"notFished,omitempty"`
}

// FishingZones is the zone ranking by value per catch (#88).
type FishingZones struct {
	Reference bool          `json:"reference"`
	OwnMin    *int64        `json:"ownMin,omitempty"`
	Zones     []FishingZone `json:"zones"`
	More      *int64        `json:"more,omitempty"`
}

type FishingZone struct {
	Zone         string   `json:"zone,omitempty"`
	Source       string   `json:"source,omitempty"` // "own" or "ref"
	N            *int64   `json:"n,omitempty"`
	PerCatch     *float64 `json:"perCatch,omitempty"`
	PerCatchHigh *float64 `json:"perCatchHigh,omitempty"`
	PerHour      *float64 `json:"perHour,omitempty"`
	Unpriced     *int64   `json:"unpriced,omitempty"`
}

// AuctionSummary is the snapshot's auction tracker section (#81).
type AuctionSummary struct {
	Active           []AuctionRow `json:"active"`
	Sold             []AuctionRow `json:"sold"`
	Returning        []AuctionRow `json:"returning"`
	Uncertain        []AuctionRow `json:"uncertain"`
	ExpectedTotal    *int64       `json:"expectedTotal,omitempty"`
	ExpectedMissing  *int64       `json:"expectedMissing,omitempty"`
	ListedTotal      *int64       `json:"listedTotal,omitempty"`
	ListedCounted    *int64       `json:"listedCounted,omitempty"`
	ListedNote       string       `json:"listedNote,omitempty"`
	ListedNoBuyout   *int64       `json:"listedNoBuyout,omitempty"`
	ListedUnknownCut *int64       `json:"listedUnknownCut,omitempty"`
	ListedUnpriced   *int64       `json:"listedUnpriced,omitempty"`
	OwnedListAt      *int64       `json:"ownedListAt,omitempty"`
	OwnedListHouse   string       `json:"ownedListHouse,omitempty"`
}

type AuctionRow struct {
	ID           *int64 `json:"id,omitempty"`
	Item         *int64 `json:"item,omitempty"`
	Name         string `json:"name,omitempty"`
	Q            *int64 `json:"q,omitempty"`
	House        string `json:"house,omitempty"`
	HouseLabel   string `json:"houseLabel,omitempty"`
	Status       string `json:"status,omitempty"`
	StatusText   string `json:"statusText,omitempty"`
	Posted       *int64 `json:"posted,omitempty"`
	Expires      *int64 `json:"expires,omitempty"`
	DurText      string `json:"durText,omitempty"`
	Overdue      bool   `json:"overdue,omitempty"`
	UnitBuyout   *int64 `json:"unitBuyout,omitempty"`
	UnitBid      *int64 `json:"unitBid,omitempty"`
	Deposit      *int64 `json:"deposit,omitempty"`
	Untracked    bool   `json:"untracked,omitempty"`
	SoldAt       *int64 `json:"soldAt,omitempty"`
	SoldVia      string `json:"soldVia,omitempty"`
	UnitsSold    string `json:"unitsSold,omitempty"`
	Expected     *int64 `json:"expected,omitempty"`
	ExpectedNote string `json:"expectedNote,omitempty"`
	SalePrice    *int64 `json:"salePrice,omitempty"`
	At           *int64 `json:"at,omitempty"`
	Received     *int64 `json:"received,omitempty"`
	Sale         *int64 `json:"sale,omitempty"`
	Cut          *int64 `json:"cut,omitempty"`
	SettledAt    *int64 `json:"settledAt,omitempty"`
	Uncertain    string `json:"uncertain,omitempty"`
	Why          string `json:"why,omitempty"`
}

// MarketSummary says where the price data is (#90, #92); the prices are in CraftWiseMarketDB.
type MarketSummary struct {
	Where       string                  `json:"where,omitempty"`
	Houses      map[string]HouseSummary `json:"houses,omitempty"`
	Auctionator *struct {
		Label string `json:"label,omitempty"`
		House string `json:"house,omitempty"`
		Items *int64 `json:"items,omitempty"`
	} `json:"auctionator,omitempty"`
	Names    *int64 `json:"names,omitempty"`
	ItemInfo *int64 `json:"itemInfo,omitempty"`
}

type HouseSummary struct {
	Label                string `json:"label,omitempty"`
	Kind                 string `json:"kind,omitempty"`
	Items                *int64 `json:"items,omitempty"`
	WithHistory          *int64 `json:"withHistory,omitempty"`
	LastRecorded         *int64 `json:"lastRecorded,omitempty"`
	LastFullScan         *int64 `json:"lastFullScan,omitempty"`
	LastFullScanSource   string `json:"lastFullScanSource,omitempty"`
	LastFullScanItems    *int64 `json:"lastFullScanItems,omitempty"`
	LastFullScanLastOnly *int64 `json:"lastFullScanLastOnly,omitempty"`
}

// Crates is the Waylaid crates section (#91), cheapest Merchant's Favor first.
type Crates struct {
	List     []Crate `json:"list"`
	Best     *int64  `json:"best,omitempty"`
	BestHeld *int64  `json:"bestHeld,omitempty"`
}

type Crate struct {
	ID           *int64        `json:"id,omitempty"`
	Name         string        `json:"name,omitempty"`
	Tier         string        `json:"tier,omitempty"`
	Held         *int64        `json:"held,omitempty"`
	Crate        *int64        `json:"crate,omitempty"`
	CrateFrom    string        `json:"crateFrom,omitempty"`
	Options      []CrateOption `json:"options"`
	FillCost     *int64        `json:"fillCost,omitempty"`
	Reward       *float64      `json:"reward,omitempty"`
	RewardFrom   string        `json:"rewardFrom,omitempty"`
	Observed     *int64        `json:"observed,omitempty"`
	Total        *int64        `json:"total,omitempty"`
	PerFavor     *int64        `json:"perFavor,omitempty"`
	FillPerFavor *int64        `json:"fillPerFavor,omitempty"`
	Missing      string        `json:"missing,omitempty"`
}

type CrateOption struct {
	N    *int64 `json:"n,omitempty"`
	Name string `json:"name,omitempty"`
	ID   *int64 `json:"id,omitempty"`
	Cost *int64 `json:"cost,omitempty"`
	How  string `json:"how,omitempty"`
	Best bool   `json:"best,omitempty"`
}

// Favor is Merchant's Favor and the merchants that take it (#91).
type Favor struct {
	ID      *int64        `json:"id,omitempty"`
	Name    string        `json:"name,omitempty"`
	Balance *int64        `json:"balance,omitempty"`
	Max     *int64        `json:"max,omitempty"`
	Earned  *int64        `json:"earned,omitempty"`
	Vendors []FavorVendor `json:"vendors"`
}

type FavorVendor struct {
	NPC         *int64      `json:"npc,omitempty"`
	Name        string      `json:"name,omitempty"`
	Zone        string      `json:"zone,omitempty"`
	Sub         string      `json:"sub,omitempty"`
	Map         *int64      `json:"map,omitempty"`
	X           *float64    `json:"x,omitempty"`
	Y           *float64    `json:"y,omitempty"`
	T           *int64      `json:"t,omitempty"`
	Faction     string      `json:"faction,omitempty"`
	FactionID   *int64      `json:"factionID,omitempty"`
	Standing    any         `json:"standing,omitempty"` // label, or the number when no label is known
	StandingNow any         `json:"standingNow,omitempty"`
	Rep         *RepRange   `json:"rep,omitempty"`
	Full        bool        `json:"full,omitempty"`
	Items       []FavorItem `json:"items"`
}

type RepRange struct {
	Value *int64 `json:"value,omitempty"`
	Min   *int64 `json:"min,omitempty"`
	Max   *int64 `json:"max,omitempty"`
}

type FavorItem struct {
	ID       *int64 `json:"id,omitempty"`
	Name     string `json:"name,omitempty"`
	Favor    *int64 `json:"favor,omitempty"`
	P        *int64 `json:"p,omitempty"`
	Other    string `json:"other,omitempty"`
	S        *int64 `json:"s,omitempty"`
	Req      string `json:"req,omitempty"`
	Known    bool   `json:"known,omitempty"`
	Unusable bool   `json:"unusable,omitempty"`
	N        *int64 `json:"n,omitempty"`
}
