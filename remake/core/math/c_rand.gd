class_name CRand
extends RefCounted
## The C library's rand() of the PsyQ runtime (0x8007A73C): x = x · 0x41C64E6D + 0x3039, the
## result bits 16–30. The state is part of the simulation state.

var state := 0


func set_seed(value: int) -> void:
	state = value & 0xFFFFFFFF


func next() -> int:
	state = (state * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
	return (state >> 16) & 0x7FFF
