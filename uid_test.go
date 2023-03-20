package uid

import (
	"encoding/json"
	"testing"
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
	g := New(epoch, sequence)

	id1 := g.NewID()
	t.Log("id1:", id1)
	t.Log(g.Extract(id1))
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
