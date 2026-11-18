class_name Rumble
extends RefCounted
## Drives controller motors the way the game drives a DualShock: every frame the
## vibration scripts produce a small-motor on/off state and a large-motor strength
## (docs/research/code/sound.md#vibration). The levels are sent each frame
## with a short duration, so a motor stops when its script stops asking for it. PadVibration
## runs the scripts and InputRouter passes their levels to the player's device.
##
## The touch controls' player feels the phone's (or tablet's) own vibration motor: one motor, so
## it runs at the stronger of the two levels (the small motor's buzz at SMALL_SHARE). A phone
## motor is driven by one-shot pulses (Input.vibrate_handheld), each replacing the one running:
## a pulse of HANDHELD_PULSE frames is sent when the level changes and renewed every
## HANDHELD_RENEW frames while it holds; a 1 ms pulse cuts it short when the level falls to zero.

const FRAME_SECONDS := 1.0 / 60.0
const HOLD_FRAMES := 2          ## covers one late frame without a gap
const LARGE_MAX := 255.0

const SMALL_SHARE := 0.5        ## the small motor's buzz on a phone's single motor
const HANDHELD_STEPS := 8.0     ## a phone's level is rounded to eighths (a new pulse on a change)
const HANDHELD_PULSE := 6       ## frames
const HANDHELD_RENEW := 4       ## frames
const HANDHELD_CUT_MS := 1

var _levels: Dictionary = {}    ## device → Vector2(weak, strong)
var handheld_level := 0.0       ## the phone motor's level running now (0: still)
var _handheld_age := 0          ## frames since its last pulse


func set_motors(device: int, small_on: bool, large: int) -> void:
	if device < 0 and device != InputRouter.TOUCH:
		return
	_levels[device] = Vector2(1.0 if small_on else 0.0, clampf(large / LARGE_MAX, 0.0, 1.0))


func update() -> void:
	var handheld := 0.0
	for device: int in _levels:
		var level: Vector2 = _levels[device]
		if device == InputRouter.TOUCH:
			handheld = maxf(level.x * SMALL_SHARE, level.y)
		elif level == Vector2.ZERO:
			Input.stop_joy_vibration(device)
		else:
			Input.start_joy_vibration(device, level.x, level.y, FRAME_SECONDS * HOLD_FRAMES)
	_levels.clear()
	_update_handheld(handheld)


func _update_handheld(level: float) -> void:
	level = ceilf(level * HANDHELD_STEPS) / HANDHELD_STEPS
	_handheld_age += 1
	if level <= 0.0:
		if handheld_level > 0.0:
			Input.vibrate_handheld(HANDHELD_CUT_MS, 1.0 / LARGE_MAX)
		handheld_level = 0.0
		return
	if level != handheld_level or _handheld_age >= HANDHELD_RENEW:
		Input.vibrate_handheld(roundi(HANDHELD_PULSE * FRAME_SECONDS * 1000.0), level)
		handheld_level = level
		_handheld_age = 0
