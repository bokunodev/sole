package uid

import "core:strings"
import "core:crypto"
import "core:sync"
import "core:time"
import "core:mem"

// base32 charset with ambigues characters removed
//
//	'O' -> '0'
//	'I' -> '1'
//	'S' -> '5'
//	'U' -> 'V'
charset := "0123456789ABCDEFGHJKLMNPQRTVWXYZ"

@(private)
_length_str :: 16

// - 1byte cluster id
// - 4byte unix second timstamp in bigendian order
// - 2byte counter in bigendian order
// - 3byte random
@(private)
_length_byt :: 10

@(private)
_byte_max :: 0xff

// Unix timestamp of Nov 04 2010 01:42:54 UTC in seconds
//
// match with twitter snowflake epoch
snowflake_epoch :: i64(1288834974)

// _decoder maps lookup table was stolen from [rid](https://github.com/solutionroute/rid)
@(private)
_decoder := [~u8(0)]byte {
	0 ..< ~u8(0) = _byte_max,
}

@(init)
_decoder_init :: proc() {
	for c, i in charset {
		_decoder[c] = byte(i)
	}
}

@(private)
_Generator :: struct {
	epoch:      i64,
	counter:    u16,
	cluster_id: u8,
	init:       bool,
}

Generator :: struct {
	_Generator: _Generator,
}

// init_generator, properly initialize a `Generator`
init_generator :: #force_inline proc(gen: ^Generator, epoch: i64, counter: u16, cluster_id: u8) {
	gen._Generator.epoch = epoch
	gen._Generator.counter = counter
	gen._Generator.cluster_id = cluster_id
	gen._Generator.init = true
}

// new_generator, creates and properly initialize a `Generator`
new_generator :: #force_inline proc(epoch: i64, counter: u16, cluster_id: u8) -> (gen: Generator) {
	gen._Generator.epoch = epoch
	gen._Generator.counter = counter
	gen._Generator.cluster_id = cluster_id
	gen._Generator.init = true

	return gen
}

UID :: [_length_byt]byte

// generate_uid, generates a new `UID`
generate_uid :: proc(gen: ^Generator) -> (uid: UID) {
	if !gen._Generator.init {
		panic("generator is not properly initialized")
	}

	// 1byte cluster id
	uid[0] = gen._Generator.cluster_id

	// 4byte timestamp
	timestamp := u32be(_time_now_u32(gen._Generator.epoch))
	mem.copy(mem.raw_data(uid[1:5]), &timestamp, size_of(timestamp))

	// 2byte counter
	//
	// Note: sync.atomic_add behaves the same as libc's [atomic_add](https://en.cppreference.com/w/c/atomic/atomic_fetch_add),
	// atomically replaces the value pointed by `ptr` with the result of addition of `delta` to the old value of `ptr`,
	// and returns the value `ptr` held previously
	//
	// we add 1 to make it behaves the same as atomic package in Go
	counter := u16be(sync.atomic_add(&gen._Generator.counter, 1) + 1)
	mem.copy(mem.raw_data(uid[5:7]), &counter, size_of(counter))

	// 3byte random
	crypto.rand_bytes(uid[7:10])

	return uid
}

@(private)
_time_now_u32 :: #force_inline proc(epoch: i64) -> u32 {
	return u32(time.to_unix_seconds(time.now()) - epoch)
}

@(private)
_extract_timestamp :: #force_inline proc(gen: ^Generator, uid: UID) -> time.Time {
	uid := uid
	temp := mem.reinterpret_copy(u32be, mem.raw_data(uid[1:5]))
	return time.unix(i64(temp) + gen._Generator.epoch, 0)
}

@(private)
_extract_counter :: #force_inline proc(uid: UID) -> u16 {
	uid := uid
	return u16(mem.reinterpret_copy(u16be, mem.raw_data(uid[5:7])))
}

// extract, extracts information from a `UID`
extract :: proc(
	gen: ^Generator,
	uid: UID,
) -> (
	cluster_id: u8,
	timestamp: time.Time,
	counter: u16,
	random: [3]byte,
) {
	uid := uid

	cluster_id = uid[0]
	timestamp = _extract_timestamp(gen, uid)
	counter = _extract_counter(uid)
	copy(random[:], uid[7:10])

	return
}

// encode, encodes `UID` into a string and return a copy of it.
//
// its up to the user to deallocate the string
encode :: proc(uid: UID) -> string {
	sb := strings.builder_make_len_cap(0, _length_str)
	defer strings.builder_destroy(&sb)

	encode_builder(&sb, uid)

	return strings.clone_from_bytes(sb.buf[:_length_str])
}

// encode_builder, encode `UID` into a string and write it to `sb`
//
// loop unrooling tips was stolen from [rid](https://github.com/solutionroute/rid)
encode_builder :: proc(sb: ^strings.Builder, uid: UID) {
	dst: [_length_str]byte
	
	//odinfmt: disable
	#no_bounds_check {
		dst[15] = charset[ uid[9] &  0x1F]
		dst[14] = charset[(uid[9] >> 5) | (uid[8] << 3) & 0x1F]
		dst[13] = charset[(uid[8] >> 2) & 0x1F]
		dst[12] = charset[(uid[8] >> 7) | (uid[7] << 1) & 0x1F]
		dst[11] = charset[(uid[7] >> 4) & 0x1F | (uid[6] << 4) & 0x1F]
		dst[10] = charset[(uid[6] >> 1) & 0x1F]
		dst[9 ] = charset[(uid[6] >> 6) & 0x1F | (uid[5] << 2) & 0x1F]
		dst[8 ] = charset[(uid[5] >> 3)]
		dst[7 ] = charset[ uid[4] &  0x1F]
		dst[6 ] = charset[(uid[4] >> 5) | (uid[3] << 3) & 0x1F]
		dst[5 ] = charset[(uid[3] >> 2) & 0x1F]
		dst[4 ] = charset[(uid[3] >> 7) | (uid[2] << 1) & 0x1F]
		dst[3 ] = charset[(uid[2] >> 4) & 0x1F | (uid[1] << 4) & 0x1F]
		dst[2 ] = charset[(uid[1] >> 1) & 0x1F]
		dst[1 ] = charset[(uid[1] >> 6) & 0x1F | (uid[0] << 2) & 0x1F]
		dst[0 ] = charset[(uid[0] >> 3)]
	}
	//odinfmt: enable

	if strings.write_bytes(sb, dst[:]) < _length_str {
		panic("strings.write_bytes failed")
	}
}

DecodeError :: enum {
	ErrInvalidStringLength,
	ErrInvalidStringChar,
}

@(private)
_validate :: proc(str: string) -> DecodeError {
	if len(str) != _length_str {
		return .ErrInvalidStringLength
	}

	if !strings.contains_any(charset, str) {
		return .ErrInvalidStringChar
	}

	return nil
}

// decode, validate and decode string `str`,
// return the decoded `UID` and a `DecodeError` if any
//
// loop unrooling tips was stolen from [rid](https://github.com/solutionroute/rid)
decode :: proc(str: string) -> (uid: UID, err: DecodeError) {
	if err = _validate(str); err != nil {
		return uid, err
	}
	
	//odinfmt: disable
	#no_bounds_check {
		uid[9] = _decoder[str[14]] << 5 | _decoder[str[15]]
		uid[8] = _decoder[str[12]] << 7 | _decoder[str[13]] << 2 | _decoder[str[14]] >> 3
		uid[7] = _decoder[str[11]] << 4 | _decoder[str[12]] >> 1
		uid[6] = _decoder[str[9 ]] << 6 | _decoder[str[10]] << 1 | _decoder[str[11]] >> 4
		uid[5] = _decoder[str[8 ]] << 3 | _decoder[str[9 ]] >> 2
		uid[4] = _decoder[str[6 ]] << 5 | _decoder[str[7 ]]
		uid[3] = _decoder[str[4 ]] << 7 | _decoder[str[5 ]] << 2 | _decoder[str[6]] >> 3
		uid[2] = _decoder[str[3 ]] << 4 | _decoder[str[4 ]] >> 1
		uid[1] = _decoder[str[1 ]] << 6 | _decoder[str[2 ]] << 1 | _decoder[str[3]] >> 4
		uid[0] = _decoder[str[0 ]] << 3 | _decoder[str[1 ]] >> 2
	}
	//odinfmt: enable

	return uid, nil
}
