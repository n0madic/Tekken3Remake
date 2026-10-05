class_name FighterHands
extends RefCounted
## The hand and face channels of a fighter: `HandFaceCommand` (0x800346F8) sets a target shape
## and `FighterHandPoses` (0x80034BC4) moves towards it every animated frame and picks the
## vertex variant of each hand part (3dmk-models.md#vertex-variants).
##
## Fields: `+0x127C` current, `+0x1280` target, `+0x1284` rate per channel; `+0x128E` the face
## speed and `+0x1290` the face (shapes 10 and 11: open or closed eyes). True Ogre (character
## 0x14) animates one level `+0x1296` (target `+0x1298`, rate `+0x129A`) and his wings
## (`+0x128B` frame, `+0x128C` phase, `+0x128D` first step) instead of two hands.

const CHANNELS := 2
const FIST := 0x200              ## channel value of the closed fist; shapes 2–7 lie above it
const FACE_OPEN := 10
const FACE_CLOSED := 11
const OGRE_LEVEL := 0x100

var current := PackedInt32Array([0, 0])
var target := PackedInt32Array([0, 0])
var rate := PackedInt32Array([0, 0])
var variant := PackedInt32Array([0, 0])   ## the vertex variant each hand part shows
var face := 0                             ## 0 open eyes, 1 closed (shapes 10 / 11)
var face_speed := 0
var ogre_level := 0
var ogre_target := 0
var ogre_rate := 0
var wing_frame := 0
var wing_phase := 0
var wing_first := 0
var wing_variant := 0


## HandFaceCommand for `hands` (bit 0 channel 0, bit 1 channel 1), a shape and a speed: shapes
## 0 and 1 blend between open hand and fist over `speed + 1` frames, other shapes are set at once.
func command(hands: int, shape: int, speed: int, char_id: int = 0) -> void:
	if shape >= FACE_OPEN:
		if shape - FACE_OPEN < 2:
			face_speed = Fx.s16(speed)
			face = shape - FACE_OPEN
		return
	if shape >= 8:
		return
	if char_id == Character.TRUE_OGRE:
		if speed == 0:
			speed = 1
		var ogre := Fx.div_trunc(OGRE_LEVEL, 1 - speed) if speed < 0 else Fx.div_trunc(OGRE_LEVEL, speed + 1)
		ogre_rate = 0
		if shape == 2 or shape == 3:
			ogre_target = OGRE_LEVEL
			if ogre_level < OGRE_LEVEL:
				ogre_rate = ogre
		else:
			ogre_target = 0
			if ogre_level > 0:
				ogre_rate = ogre
		target[0] = OGRE_LEVEL if shape == 2 else 0
		rate[0] = ogre
		return
	for c in CHANNELS:
		if hands & (c + 1) == 0:
			continue
		var value := 0 if shape == 0 else FIST if shape == 1 else shape + FIST - 1
		if current[c] <= FIST and value <= FIST:
			if speed != 0:
				rate[c] = Fx.div_trunc(FIST, 1 - speed) if speed < 0 else Fx.div_trunc(FIST, speed + 1)
		else:
			current[c] = value
			rate[c] = 0
		target[c] = value


## FighterHandPoses for an animated frame (`air_free`: the fighter's +0x128A).
func update(char_id: int = 0, air_free: int = 0, tables: FighterTables = null) -> void:
	if char_id == Character.TRUE_OGRE:
		_update_wings(air_free, tables)
		_approach(0)
		var level := ogre_level
		if level < ogre_target:
			ogre_level = Fx.s16(level + ogre_rate)
			if not ogre_level < ogre_target:
				ogre_rate = 0
				ogre_level = ogre_target
		elif ogre_target < level:
			ogre_level = Fx.s16(level - ogre_rate)
			if not ogre_target < ogre_level:
				ogre_rate = 0
				ogre_level = ogre_target
		var v := Fx.s16(current[0]) >> 7
		variant[0] = v - 1 if v != 0 else 0
		return
	for c in CHANNELS:
		_approach(c)
		variant[c] = variant_of(current[c])


func _approach(c: int) -> void:
	if current[c] < target[c]:
		current[c] = Fx.s16(current[c] + rate[c])
		if not current[c] < target[c]:
			rate[c] = 0
			current[c] = target[c]
	elif target[c] < current[c]:
		current[c] = Fx.s16(current[c] - rate[c])
		if not target[c] < current[c]:
			rate[c] = 0
			current[c] = target[c]


## True Ogre's wings: folded (phase 0) they open while he is airborne outside reactions; open
## (phase 1) they beat, one step per frame (two on the first).
func _update_wings(air_free: int, tables: FighterTables) -> void:
	if tables == null:
		return
	if wing_phase == 0:
		if air_free == 0:
			if wing_frame != 0:
				wing_frame -= 1
		else:
			wing_frame = (wing_frame + 2) & 0xFF
			if tables.wing_open[wing_frame] == -1:
				wing_phase = 1
				wing_frame = 0
				wing_first = 1
	elif wing_phase == 1:
		var steps := 1
		if wing_first != 0:
			steps = 2
			wing_first = 0
		wing_frame = (wing_frame + steps) & 0xFF
		if tables.wing_beat[wing_frame] == -1:
			if air_free == 0:
				wing_frame = 0x10
				wing_phase = 0
			else:
				wing_frame = 0
	wing_variant = (tables.wing_open if wing_phase == 0 else tables.wing_beat)[wing_frame]


static func variant_of(value: int) -> int:
	if value > FIST:
		return value - (FIST - 3)
	var v := value >> 7
	return v - 1 if v != 0 else 0
