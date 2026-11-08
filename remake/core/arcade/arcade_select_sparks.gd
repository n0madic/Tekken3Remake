class_name ArcadeSelectSparks
extends RefCounted
## The character select's sparks (FUN_801BF8B4, FUN_801BF6B4): every fourth frame a line rises from the
## name plates over one of the portraits, the sides in turn, and fades. They draw from the frame generator
## (FUN_801B2468) that the ladder's picks draw from too, so they belong to the simulation.

const COUNT := 0x40
const LENGTH := 0xA0
const WIDTH := 1
const LEVEL_MASK := 0xFF
const PORTRAIT_WIDTH := 0xA8
const START_BRIGHTNESS := 0xA0
const FADE_MIN := 6
const RISE := 0x10                  ## pixels per displayed frame
const EVERY_MASK := 3
const SIDE_BIT := 4
const STRATA_SHIFT := 3             ## the frame's next two bits pick the quarter of the portrait
const POSITION_BITS := 10
const POSITION_MASK := 0x3FF
const FIXED_SHIFT := 12


## 0x14 bytes each, at +0x168 of the select's context.
class Spark:
	var active := 0
	var started := 0                ## +2
	var x := 0
	var y := 0
	var first_y := 0
	var start := 0                  ## +0xA: the clock when it started
	var brightness := 0             ## +0xC
	var fade := 0                   ## +0x10


var sparks: Array[Spark] = []


func _init() -> void:
	for i in COUNT:
		sparks.append(Spark.new())


## FUN_801BF88C.
func clear() -> void:
	for s: Spark in sparks:
		s.active = 0
		s.started = 0


## FUN_801BF8B4 and the loop of FUN_801BF990.
func step(frame: int, clock: int, side_x: PackedInt32Array, start_y: int, fight: FightState) -> void:
	if frame & EVERY_MASK == 0:
		_spawn(frame, side_x, start_y, fight)
	for s: Spark in sparks:
		if s.active == 1:
			_rise(s, clock, fight)


func _spawn(frame: int, side_x: PackedInt32Array, start_y: int, fight: FightState) -> void:
	var s := _free()
	if s == null:
		return
	s.active = 1
	var strata := (frame >> STRATA_SHIFT) & 3
	var quarter := ((strata & 1) << 1) | (strata >> 1)
	var at := (quarter << POSITION_BITS) | ((Opponents.frame_random(fight) >> 2) & POSITION_MASK)
	var side := 1 if frame & SIDE_BIT != 0 else 0
	s.x = Fx.s16(side_x[side] + ((at * PORTRAIT_WIDTH) >> FIXED_SHIFT))
	s.first_y = start_y
	s.y = start_y


## FUN_801BF850.
func _free() -> Spark:
	for s: Spark in sparks:
		if s.active == 0:
			s.started = 0
			return s
	return null


## FUN_801BF6B4 without its drawing.
func _rise(s: Spark, clock: int, fight: FightState) -> void:
	var now := clock & 0xFFFF
	if s.started == 0:
		s.brightness = START_BRIGHTNESS
		s.start = now
		s.started = 1
		s.fade = (Opponents.frame_random(fight) & 3) + FADE_MIN
	s.brightness -= s.fade
	s.y = Fx.s16(s.first_y + (now - s.start) * -RISE)
	if s.y + LENGTH < 0 or s.brightness < 1:
		s.active = 0
