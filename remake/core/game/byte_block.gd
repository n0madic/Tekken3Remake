class_name ByteBlock
extends RefCounted
## A block of the game's memory kept with its original layout: the save block and records, and
## the mode context with the fight's globals. Their structures are unions of per-mode and
## per-page layouts in the game, so the remake keeps the bytes and names the fields with
## accessors (subclasses); the flow traces compare the blocks byte for byte.

var bytes := PackedByteArray()


func _init(size: int = 0) -> void:
	bytes.resize(size)


func u8(at: int) -> int:
	return bytes.decode_u8(at)


func s8(at: int) -> int:
	return bytes.decode_s8(at)


func u16(at: int) -> int:
	return bytes.decode_u16(at)


func s16(at: int) -> int:
	return bytes.decode_s16(at)


func u32(at: int) -> int:
	return bytes.decode_u32(at)


func s32(at: int) -> int:
	return bytes.decode_s32(at)


func put8(at: int, v: int) -> void:
	bytes.encode_u8(at, v & 0xFF)


func put16(at: int, v: int) -> void:
	bytes.encode_u16(at, v & 0xFFFF)


func put32(at: int, v: int) -> void:
	bytes.encode_u32(at, v & 0xFFFFFFFF)


func copy_from(other: ByteBlock) -> void:
	bytes = other.bytes.duplicate()
