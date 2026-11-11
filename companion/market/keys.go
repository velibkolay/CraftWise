package market

import (
	"fmt"
	"strconv"
	"strings"
)

// ItemKey is Market.lua's item key: the item ID, or "itemID:suffixID" for random-suffix gear.
type ItemKey struct {
	ItemID int64
	Suffix int64 // 0 = none
}

// String is the key as the Lua code writes it.
func (k ItemKey) String() string {
	if k.Suffix != 0 {
		return fmt.Sprintf("%d:%d", k.ItemID, k.Suffix)
	}
	return strconv.FormatInt(k.ItemID, 10)
}

// MarshalText lets an ItemKey be a JSON object key.
func (k ItemKey) MarshalText() ([]byte, error) { return []byte(k.String()), nil }

// ParseItemKey reads a key as a SavedVariables file holds it: a number, or "itemID:suffixID".
func ParseItemKey(key any) (ItemKey, error) {
	switch k := key.(type) {
	case float64:
		id := int64(k)
		if float64(id) != k || id <= 0 {
			return ItemKey{}, fmt.Errorf("item key %v is not an item ID", k)
		}
		return ItemKey{ItemID: id}, nil
	case string:
		idText, suffixText, ok := strings.Cut(k, ":")
		id, err := strconv.ParseInt(idText, 10, 64)
		if err != nil || id <= 0 {
			return ItemKey{}, fmt.Errorf("item key %q is not an item ID", k)
		}
		if !ok {
			return ItemKey{ItemID: id}, nil
		}
		suffix, err := strconv.ParseInt(suffixText, 10, 64)
		if err != nil {
			return ItemKey{}, fmt.Errorf("item key %q: bad suffix", k)
		}
		return ItemKey{ItemID: id, Suffix: suffix}, nil
	}
	return ItemKey{}, fmt.Errorf("item key of type %T", key)
}

// AuctionatorPrice is one CraftWiseMarketDB.auctionator.items value (#90): when CraftWise read it,
// Auctionator's price in copper, and Auctionator's age of that price in days. House unknown.
type AuctionatorPrice struct {
	T      *int64 `json:"t,omitempty"`
	Copper *int64 `json:"copper,omitempty"`
	Age    *int64 `json:"age,omitempty"`
}

// EncodeAuctionator packs a price as Market.lua's ExportAuctionator writes it: "t,copper,age".
func EncodeAuctionator(p AuctionatorPrice) string {
	return opt(p.T) + "," + opt(p.Copper) + "," + opt(p.Age)
}

// DecodeAuctionator reads "t,copper,age" (Market.lua AuctionatorExport).
func DecodeAuctionator(s string) (AuctionatorPrice, error) {
	f := strings.Split(s, ",")
	if len(f) != 3 {
		return AuctionatorPrice{}, malformed("auctionator price %q: want 3 fields", s)
	}
	var out AuctionatorPrice
	var err error
	for i, dst := range []**int64{&out.T, &out.Copper, &out.Age} {
		if *dst, err = num(f[i]); err != nil {
			return AuctionatorPrice{}, err
		}
	}
	return out, nil
}

// ItemInfo is one CraftWiseMarketDB.itemInfo value (#92): quality (Enum.ItemQuality), icon file ID,
// class and subclass ID as the client returned them, and when CraftWise read them. A field the
// client didn't give is nil. The name is not here: it is CraftWiseMarketDB.names[itemID].
type ItemInfo struct {
	Quality  *int64 `json:"q,omitempty"`
	Icon     *int64 `json:"i,omitempty"`
	Class    *int64 `json:"c,omitempty"`
	Subclass *int64 `json:"s,omitempty"`
	T        *int64 `json:"t,omitempty"`
}

// EncodeItemInfo packs item info as Market.lua's EncodeItemInfo does: "q,i,c,s,t" in base 36, an
// unknown field empty. Unlike the price records, a negative number is written as unknown, not as 0.
func EncodeItemInfo(info ItemInfo) string {
	field := func(p *int64) string {
		if p == nil || *p < 0 {
			return ""
		}
		return base36(*p)
	}
	return field(info.Quality) + "," + field(info.Icon) + "," + field(info.Class) + "," + field(info.Subclass) + "," + field(info.T)
}

// DecodeItemInfo reads "q,i,c,s,t" (Market.lua ItemInfo).
func DecodeItemInfo(s string) (ItemInfo, error) {
	f := strings.Split(s, ",")
	if len(f) != 5 {
		return ItemInfo{}, malformed("item info %q: want 5 fields", s)
	}
	var out ItemInfo
	var err error
	for i, dst := range []**int64{&out.Quality, &out.Icon, &out.Class, &out.Subclass, &out.T} {
		if *dst, err = num(f[i]); err != nil {
			return ItemInfo{}, err
		}
	}
	return out, nil
}
