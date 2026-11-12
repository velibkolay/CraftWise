-- The client's own names of item classes and subclasses and the vendor sell price of every item
-- (#120). Recorded by the addon (C_Item.GetItemClassInfo / GetItemSubClassInfo, C_Item.GetItemInfo's
-- sellPrice) and uploaded by the companion; nothing here is guessed or taken from a third party.
--
-- Write budget (#118): names change almost never and the upload writes a row only when its name
-- changed, so after the first upload they cost nothing. The sell price is one more column of `items`:
-- written with the item's info, so it costs nothing extra for a new item and one row per known item
-- the first time its price arrives.

-- Vendor sell price per unit in copper; 0 = vendors don't buy it; NULL = not known yet.
ALTER TABLE items ADD COLUMN sell_price INTEGER;

-- Item class names as the client gives them (localized), e.g. 7 = "Trade Goods".
CREATE TABLE item_classes (
	class INTEGER PRIMARY KEY,
	name TEXT NOT NULL
);

-- Item subclass names as the client gives them, e.g. (7, 9) = "Herb".
CREATE TABLE item_subclasses (
	class INTEGER NOT NULL,
	subclass INTEGER NOT NULL,
	name TEXT NOT NULL,
	PRIMARY KEY (class, subclass)
) WITHOUT ROWID;
