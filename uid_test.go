package uid

import (
	"encoding/hex"
	"encoding/json"
	"testing"
	"time"
)

var (
	epoch    = SnowflakeEpoch
	sequence = uint32(666)
)

func BenchmarkUIDGen(b *testing.B) {
	g := New(epoch, sequence)

	var id ID
	for i := 0; i < b.N; i++ {
		id = g.NewID()
	}
	_ = id
}

func BenchmarkUIDParse(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_, err := Parse("2X35DGR00019Q470")
		if err != nil {
			b.Fatal(err)
		}
	}
}

func TestGenerateParse(t *testing.T) {
	g := New(epoch, sequence)

	id1 := g.NewID()
	t.Log("id1:", id1)

	strid := id1.String()

	id2, err := Parse(strid)
	if err != nil {
		t.Fatal(err)
	}

	t.Log("id2:", id2)

	if id1 != id2 {
		t.Error("ids does not equal")
	}
}

func TestJsonMarshalUnmarshal(t *testing.T) {
	g := New(epoch, sequence)

	id1 := g.NewID()
	t.Log("id1:", id1)
	p, err := json.Marshal(id1)
	if err != nil {
		t.Fatal(err)
	}

	var id2 ID
	err = json.Unmarshal(p, &id2)
	if err != nil {
		t.Fatal(err)
	}

	t.Log("id2:", id2)

	if id1 != id2 {
		t.Error("marshaled and unmarshaled ids does not equal")
	}
}

func TestExtract(t *testing.T) {
	g := New(epoch, 0)

	now := time.Now().UTC().Truncate(time.Second)

	id1 := g.NewID()
	t.Log("id1:", id1)
	ts, seq, ent := g.Extract(id1)
	t.Log("ts:", ts, "seq:", seq, "random:", hex.EncodeToString(ent[:]))

	if !ts.Equal(now) {
		t.Errorf("extracted timestamp does not match; expected: (%v) got: (%v)", now, ts)
	}

	if !ts.Equal(now) {
		t.Errorf("extracted sequence does not match; expected: (1) got: (%v)", seq)
	}
}

func TestDatabaseSQLValuerScanner(t *testing.T) {
	g := New(epoch, sequence)

	id1 := g.NewID()
	t.Log("id1:", id1)
	v, err := id1.Value()
	if err != nil {
		t.Fatal(err)
	}

	var id2 ID
	id2.Scan(v)
	if err != nil {
		t.Fatal(err)
	}

	t.Log("id2:", id2)

	if id1 != id2 {
		t.Error("value and scanned ids does not equal")
	}
}
