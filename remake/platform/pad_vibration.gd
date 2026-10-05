class_name PadVibration
extends RefCounted
## The game's vibration scripts (VibrationUpdate 0x80029228, sound.md#vibration): PadVibrate
## queues a pattern into one of four slots per pad; every frame each slot's small-motor script
## gives on/off (a pulse mask by level, stepped by the frame counter) and its large-motor script
## a strength; the highest running slot drives each motor.

const PADS := 2
const SLOTS := 4
const CONTINUE := 0x1000

class MotorScript:
	var steps := PackedInt32Array()
	var index := -1                  ## −1: not running
	var count := 0

	func start(words: PackedInt32Array) -> void:
		if words.is_empty() or words[0] & 0xF000 == 0:
			return
		steps = words
		index = 0
		count = 0

	## Advances one frame; returns the running step's word, or −1.
	func step() -> int:
		if index < 0:
			return -1
		var word := steps[index]
		count += 1
		if (word & 0xFF) <= count:
			count = 0
			index = index + 1 if word & 0xF000 == CONTINUE and index + 1 < steps.size() else -1
		return word

var tables: FightTables.VibrationTables
var pending: Array[PackedInt32Array] = []          ## per pad: the pattern queued per slot
var small: Array[Array] = []                        ## per pad: MotorScript per slot
var large: Array[Array] = []
var small_on: Array[bool] = [false, false]          ## the motors of the last update
var large_level := PackedInt32Array([0, 0])
var _frame := 0                                     ## 0x800982E0 (vblanks)


func _init(vibration: FightTables.VibrationTables) -> void:
	tables = vibration
	for pad in PADS:
		pending.append(PackedInt32Array([0, 0, 0, 0]))
		var s: Array[MotorScript] = []
		var l: Array[MotorScript] = []
		for slot in SLOTS:
			s.append(MotorScript.new())
			l.append(MotorScript.new())
		small.append(s)
		large.append(l)


## PadVibrate(pad, pattern): pad 2 is both.
func vibrate(pad: int, pattern: int) -> void:
	if pattern < 0 or pattern >= tables.slots.size():
		return
	var slot := tables.slots[pattern]
	if slot >= SLOTS:
		return
	for p in PADS:
		if pad == p or pad >= PADS:
			pending[p][slot] = pattern


## Stops every script (a new fight, the pause menu leaving).
func clear() -> void:
	for p in PADS:
		pending[p] = PackedInt32Array([0, 0, 0, 0])
		for slot in SLOTS:
			(small[p][slot] as MotorScript).index = -1
			(large[p][slot] as MotorScript).index = -1
		small_on[p] = false
		large_level[p] = 0


## One frame of the scripts driving both players' motors (Pads); `enabled` false holds them still
## (the Vibration setting off).
func drive(enabled: bool) -> void:
	update()
	for p in PADS:
		Pads.set_motors(p, small_on[p] and enabled, large_level[p] if enabled else 0)


## Both players' motors stopped (a fight that ends, the application quitting).
static func stop_motors() -> void:
	for p in PADS:
		Pads.set_motors(p, false, 0)


## One frame (VibrationUpdate for both pads).
func update() -> void:
	var phase := _frame & 7
	_frame += 1
	for p in PADS:
		for slot in SLOTS:
			var pattern := pending[p][slot]
			if pattern != 0:
				(small[p][slot] as MotorScript).start(tables.small[pattern])
				(large[p][slot] as MotorScript).start(tables.large[pattern])
				pending[p][slot] = 0
		var on := false
		var level := 0
		for slot in SLOTS:
			var word := (small[p][slot] as MotorScript).step()
			if word >= 0:
				on = tables.pulses[(word & 0xF00) >> 8] & (1 << phase) != 0
			word = (large[p][slot] as MotorScript).step()
			if word >= 0:
				level = ((word & 0xF00) >> 4) + 15
		small_on[p] = on
		large_level[p] = level
