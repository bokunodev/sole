package sole

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
//	'B' -> '8'
charset := "0123456789ACDEFGHJKLMNPQRTUVWXYZ"
charset_lower := "0123456789acdefghjklmnpqrtuvwxyz"

@(private)
_length_str :: 16

// - 4 byte unix second timstamp in bigendian order
// - 4 byte sequence in bigendian order
// - 2 byte random
@(private)
_length_byt :: 10

@(private)
_byte_max :: 0xff

// Unix timestamp of `Nov 04 2010 01:42:54 UTC` in seconds, twitter snowflake's epoch.
snowflake_epoch :: i64(1288834974)

// _decoder maps lookup table was stolen from [solutionroute/rid](https://github.com/solutionroute/rid)
@(private)
_decoder := [256]byte {
	0 ..< 256 = _byte_max,
}

@(init)
_decoder_init :: proc() {
	for c, i in charset {
		_decoder[c] = byte(i)
	}

	for c, i in charset_lower {
		_decoder[c] = byte(i)
	}
}

@(private)
// for testing purposes, to allow me to mock the timestamp.
now_proc :: #type proc(_: i64) -> i64

@(private)
_time_now :: proc(epoch: i64) -> i64 {
	return time.to_unix_seconds(time.now()) - epoch
}

@(private)
_Generator :: struct {
	epoch:    i64,
	sequence: u32,
	init:     bool,
	now:      now_proc,
}

Generator :: struct {
	_Generator: _Generator,
}

// init, properly initialize a `Generator`
init :: #force_inline proc(gen: ^Generator, epoch: i64, sequence: u32) {
	gen._Generator.epoch = epoch
	gen._Generator.sequence = sequence
	gen._Generator.init = true
	gen._Generator.now = _time_now
}

UID :: [_length_byt]byte

// generate, generates a new `UID`
generate :: proc(gen: ^Generator) -> (uid: UID) {
	if !gen._Generator.init {
		panic("generator is not properly initialized")
	}

	// 4byte timestamp
	timestamp := u32be(gen._Generator.now(gen._Generator.epoch))
	mem.copy(mem.raw_data(uid[0:4]), &timestamp, size_of(timestamp))

	// 4byte sequence
	//
	// Note: sync.atomic_add behaves the same as libc's [atomic_add](https://en.cppreference.com/w/c/atomic/atomic_fetch_add),
	// atomically replaces the value pointed by `ptr` with the result of addition of `delta` to the old value of `ptr`,
	// and returns the value `ptr` held previously
	//
	// we add 1 to make it behaves the same as atomic package in Go
	sequence := u32be(sync.atomic_add(&gen._Generator.sequence, 1) + 1)
	mem.copy(mem.raw_data(uid[4:8]), &sequence, size_of(sequence))

	// 2byte random
	crypto.rand_bytes(uid[8:10])

	return uid
}

@(private)
_extract_timestamp :: #force_inline proc(gen: ^Generator, uid: UID) -> time.Time {
	uid := uid
	temp := mem.reinterpret_copy(u32be, mem.raw_data(uid[0:4]))
	return time.unix(i64(temp) + gen._Generator.epoch, 0)
}

@(private)
_extract_sequence :: #force_inline proc(uid: UID) -> u32 {
	uid := uid
	return u32(mem.reinterpret_copy(u32be, mem.raw_data(uid[4:8])))
}

// extract, extracts information from a `UID`
extract :: proc(
	gen: ^Generator,
	uid: UID,
) -> (
	timestamp: time.Time,
	sequence: u32,
	random: [2]byte,
) {
	uid := uid

	timestamp = _extract_timestamp(gen, uid)
	sequence = _extract_sequence(uid)
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
// loop unrooling tips was stolen from [solutionroute/rid](https://github.com/solutionroute/rid)
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
		panic("strings.write_bytes too short")
	}
}

DecodeError :: enum {
	ErrInvalidStringLength,
	ErrInvalidStringChar,
}

@(private)
_validate :: proc(str: string) -> DecodeError #no_bounds_check {
	if len(str) != _length_str {
		return .ErrInvalidStringLength
	}
	
	//odinfmt: disable
	res := _decoder[str[0 ]] |
		   _decoder[str[1 ]] |
		   _decoder[str[2 ]] |
		   _decoder[str[3 ]] |
		   _decoder[str[4 ]] |
		   _decoder[str[5 ]] |
		   _decoder[str[6 ]] |
		   _decoder[str[7 ]] |
		   _decoder[str[8 ]] |
		   _decoder[str[9 ]] |
		   _decoder[str[10]] |
		   _decoder[str[11]] |
		   _decoder[str[12]] |
		   _decoder[str[13]] |
		   _decoder[str[14]] |
		   _decoder[str[15]]
	if res == _byte_max {
		return .ErrInvalidStringChar
	}
	//odinfmt: enable

	return nil
}

// decode, validate and decode string `str`,
// return the decoded `UID` and a `DecodeError` if any
//
// loop unrooling tips was stolen from [solutionroute/rid](https://github.com/solutionroute/rid)
decode :: proc(str: string) -> (uid: UID, err: DecodeError) {
	_validate(str) or_return
	
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
