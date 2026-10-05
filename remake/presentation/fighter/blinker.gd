class_name Blinker
extends RefCounted
## Eye blinking (FUN_80034354, animation.md#blinking) as a presentation effect: the eyes stay
## open for a random 1–255 frames (odd), then close for 4. Moves with flag bit 18 and lying
## moves (state bit 2 without flag bit 30) keep them closed. The attract demonstration does
## not blink (the game skips the routine in game state 6).

const CLOSED_FRAMES := 4
const FLAG_EYES_CLOSED := 0x40000
const FLAG_LOOK_AT := 0x40000000
const STATE_DOWN := 0x4

var rng := RandomNumberGenerator.new()
var closed := false
var _left := 0


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_left = _open_frames()


## Whether a move (its +0x24 flags) keeps the eyes closed.
static func held(flags: int) -> bool:
	return flags & FLAG_EYES_CLOSED != 0


## Whether a move (its +0x24 flags and +0x04 state) is a lying one that keeps them closed.
static func lying(flags: int, state: int) -> bool:
	return state & STATE_DOWN != 0 and flags & FLAG_LOOK_AT == 0


## One frame of the running move (its +0x24 flags and +0x04 state); true while closed.
func step(flags: int, state: int) -> bool:
	if held(flags) or lying(flags, state):
		closed = true
		_left = 2
		return closed
	_left -= 1
	if _left <= 0:
		closed = not closed
		_left = CLOSED_FRAMES if closed else _open_frames()
	return closed


func _open_frames() -> int:
	return (rng.randi() & 0xFE) + 1
