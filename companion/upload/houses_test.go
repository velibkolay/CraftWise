package upload

import "testing"

// #382: what the state remembers under "<realm>|H" belongs to "H", so the first upload after the change does
// not send the whole market again.
func TestMigrateHouseKeys(t *testing.T) {
	st := NewState("s", "f")
	st.init()
	r6, r8 := "CAMWOW EU4 Realm 6 PvP|H", "CAMWOW EU4 Realm 8 PvP|H"
	st.Scans[r6], st.Scans[r8] = 100, 300
	st.Prices[priceKey(r6, "2589")] = &PriceMark{LastT: 50}
	st.Prices[priceKey(r8, "2589")] = &PriceMark{LastT: 70}
	st.Prices[priceKey(r6, "15210:1017")] = &PriceMark{LastT: 90}
	st.Prices[priceKey("N:BootyBay", "1")] = &PriceMark{LastT: 5}
	st.Got[r8+"2589"] = []int64{1, 2}
	st.Got[r6+"2589"] = []int64{2, 3}
	st.Got["Some Realm|N:Gadgetzan15210:1017"] = []int64{9}
	if !st.MigrateHouseKeys() {
		t.Fatal("something was moved")
	}
	if len(st.Scans) != 1 || st.Scans["H"] != 300 {
		t.Errorf("scans %+v", st.Scans)
	}
	if got := st.Prices[priceKey("H", "2589")]; got == nil || got.LastT != 70 {
		t.Errorf("the newer mark stays: %+v", got)
	}
	if got := st.Prices[priceKey("H", "15210:1017")]; got == nil || got.LastT != 90 {
		t.Errorf("%+v", got)
	}
	if len(st.Prices) != 3 || st.Prices[priceKey("N:BootyBay", "1")] == nil {
		t.Errorf("prices %+v", st.Prices)
	}
	if got := st.Got["H2589"]; len(got) != 3 {
		t.Errorf("got %+v", st.Got)
	}
	if st.Got["N:Gadgetzan15210:1017"][0] != 9 || len(st.Got) != 2 {
		t.Errorf("got %+v", st.Got)
	}
	if st.MigrateHouseKeys() {
		t.Error("second run moves nothing")
	}
}
