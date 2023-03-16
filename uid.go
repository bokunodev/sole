package uid

import (
	"crypto/rand"
	"database/sql/driver"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync/atomic"
	"time"
	"unsafe"
)

const (
	// Ambigues characters
	// 	'O' -> '0'
	// 	'I' -> '1'
	// 	'S' -> '5'
	// 	'U' -> 'V'
	charset = "0123456789ABCDEFGHJKLMNPQRTVWXYZ"
	lenstr  = 16

	// Structure
	// 	- 1 byte cluster id
	// 	- 4 byte unix second timstamp
	// 	- 2 byte counter
	// 	- 3 byte random
	lenbyt  = 10
	bytemax = 0xff

	// Unix timestamp of Nov 04 2010 01:42:54 UTC in seconds,
	// you may customize this to set a different epoch for your application.
	SnowflakeEpoch int64 = 1288834974
)

// decoder maps lookup table is stolen from [solutionroute/rid]
//
// [solutionroute/rid]: https://github.com/solutionroute/rid
var decoder [256]byte

func init() {
	// initialize the decoding map, used also for sanity checking input
	for i := 0; i < len(decoder); i++ {
		decoder[i] = bytemax
	}

	for i, c := range charset {
		decoder[c] = byte(i)
	}

	// case insensitive decode
	for i, c := range strings.ToLower(charset) {
		decoder[c] = byte(i)
	}
}

type Generator struct {
	epoch     int64
	counter   uint32
	clusterID uint8
	init      bool
}

func New(lastEpoch int64, lastCounter uint16, clusterID uint8) Generator {
	return Generator{
		epoch:     lastEpoch,
		counter:   uint32(lastCounter),
		clusterID: clusterID,
		init:      true,
	}
}

func (gen *Generator) NewID() (id ID) {
	if !gen.init {
		panic("generator is not properly initialized")
	}

	now := time.Now().Unix() - gen.epoch
	id[0] = gen.clusterID                                                          // 1byte cluster id
	binary.BigEndian.PutUint32(id[1:5], uint32(now))                               // 4byte timestamp
	binary.BigEndian.PutUint16(id[5:7], uint16(atomic.AddUint32(&gen.counter, 1))) // 2byte counter
	rand.Read(id[7:10])                                                            // 3byte random

	return id
}

var (
	ErrInvalidStringLength = errors.New("ErrInvalidStringLength")
	ErrInvalidStringChar   = errors.New("ErrInvalidStringChar")
)

func (gen *Generator) Extract(id ID) (uint8, time.Time, uint16, [3]byte) {
	ts := int64(binary.BigEndian.Uint32(id[1:5])) + gen.epoch

	return id[0], time.Unix(ts, 0),
		binary.BigEndian.Uint16(id[5:7]),
		[3]byte(id[7:10])
}

// loop unrooling in encode and decode functions are stolen from [solutionroute/rid]
//
// [solutionroute/rid]: https://github.com/solutionroute/rid
func encode(id ID) string {
	var dst [lenstr]byte

	dst[15] = charset[id[9]&0x1F]
	dst[14] = charset[(id[9]>>5)|(id[8]<<3)&0x1F]
	dst[13] = charset[(id[8]>>2)&0x1F]
	dst[12] = charset[id[8]>>7|(id[7]<<1)&0x1F]
	dst[11] = charset[(id[7]>>4)&0x1F|(id[6]<<4)&0x1F]
	dst[10] = charset[(id[6]>>1)&0x1F]
	dst[9] = charset[(id[6]>>6)&0x1F|(id[5]<<2)&0x1F]
	dst[8] = charset[id[5]>>3]
	dst[7] = charset[id[4]&0x1F]
	dst[6] = charset[id[4]>>5|(id[3]<<3)&0x1F]
	dst[5] = charset[(id[3]>>2)&0x1F]
	dst[4] = charset[id[3]>>7|(id[2]<<1)&0x1F]
	dst[3] = charset[(id[2]>>4)&0x1F|(id[1]<<4)&0x1F]
	dst[2] = charset[(id[1]>>1)&0x1F]
	dst[1] = charset[(id[1]>>6)&0x1F|(id[0]<<2)&0x1F]
	dst[0] = charset[id[0]>>3]

	return string(dst[:])
}

// loop unrooling in encode and decode functions are stolen from [solutionroute/rid]
//
// [solutionroute/rid]: https://github.com/solutionroute/rid
func decode(id []byte, str string) error {
	if err := validate(str); err != nil {
		return err
	}

	_ = str[15] // eliminate bound check
	_ = id[9]   // eliminate bound check

	id[9] = decoder[str[14]]<<5 | decoder[str[15]]
	id[8] = decoder[str[12]]<<7 | decoder[str[13]]<<2 | decoder[str[14]]>>3
	id[7] = decoder[str[11]]<<4 | decoder[str[12]]>>1
	id[6] = decoder[str[9]]<<6 | decoder[str[10]]<<1 | decoder[str[11]]>>4
	id[5] = decoder[str[8]]<<3 | decoder[str[9]]>>2
	id[4] = decoder[str[6]]<<5 | decoder[str[7]]
	id[3] = decoder[str[4]]<<7 | decoder[str[5]]<<2 | decoder[str[6]]>>3
	id[2] = decoder[str[3]]<<4 | decoder[str[4]]>>1
	id[1] = decoder[str[1]]<<6 | decoder[str[2]]<<1 | decoder[str[3]]>>4
	id[0] = decoder[str[0]]<<3 | decoder[str[1]]>>2

	return nil
}

var Empty ID

type ID [lenbyt]byte

func Parse(str string) (id ID, err error) {
	return id, decode(id[:], str)
}

// String implements [fmt.Stringer]
func (id ID) String() string {
	return encode(id)
}

// MarshalJSON implements [encoding/json.Marshaler]
func (id ID) MarshalJSON() ([]byte, error) {
	return json.Marshal(id.String())
}

// UnmarshalJSON implements [encoding/json.Unmarshaler]
func (id *ID) UnmarshalJSON(p []byte) error {
	var str string
	if err := json.Unmarshal(p, &str); err != nil {
		return nil
	}

	if err := decode((*id)[:], str); err != nil {
		return err
	}

	return nil
}

// Value implements [database/sql/driver.Valuer]
func (id ID) Value() (driver.Value, error) {
	return id.String(), nil
}

// Scan implements [database/sql.Scanner]
func (id *ID) Scan(src any) error {
	switch val := src.(type) {
	case string:
		return decode((*id)[:], val)
	case []byte:
		return decode((*id)[:], unsafeBytesToString(val))
	}

	return fmt.Errorf("cannot scan (%T) into ID", src)
}

// MarshalText implements [encoding.TextMarshaler]
func (id ID) MarshalText() (text []byte, err error) {
	return []byte(id.String()), nil
}

// UnmarshalText implements [encoding.TextUnmarshaler]
func (id *ID) UnmarshalText(text []byte) error {
	return decode((*id)[:], unsafeBytesToString(text))
}

// MarshalBinary implements [encoding.BinaryMarshaler]
func (id ID) MarshalBinary() (data []byte, err error) {
	return id[:], nil
}

// UnmarshalBinary implements [encoding.BinaryUnmarshaler]
func (id *ID) UnmarshalBinary(data []byte) error {
	if len(data) != lenbyt {
		return ErrInvalidStringLength
	}

	return decode((*id)[:], unsafeBytesToString(data))
}

func unsafeBytesToString(p []byte) string {
	return unsafe.String(unsafe.SliceData(p), len(p))
}

func validate(str string) error {
	if len(str) != lenstr {
		return ErrInvalidStringLength
	}

	if res := decoder[str[0]] | decoder[str[1]] |
		decoder[str[2]] | decoder[str[3]] |
		decoder[str[4]] | decoder[str[5]] |
		decoder[str[6]] | decoder[str[7]] |
		decoder[str[8]] | decoder[str[9]] |
		decoder[str[10]] | decoder[str[11]] |
		decoder[str[12]] | decoder[str[13]] |
		decoder[str[14]] | decoder[str[15]]; res == bytemax {
		return ErrInvalidStringChar
	}

	return nil
}
