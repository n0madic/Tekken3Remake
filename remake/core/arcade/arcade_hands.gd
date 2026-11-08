class_name ArcadeHands
extends FighterHands
## The hand and face channels of an arcade record: FUN_80194080 (the command), FUN_80194458 (the
## approach and True Ogre's wings) and FUN_80193EA4 (the face). True Ogre goes by the costume slot, a
## face is one of six shapes per costume instead of open or closed eyes, a wing's step is always one.

const OGRE_SLOTS: Array[int] = [0x20, 0x21]
const FACE_SHAPES := 6
const FACE_ROW := 8                 ## bytes per costume in the table of face pictures
const FACE_ROW_FIRST := 2           ## the row's first shape
const NO_PICTURE := -1
const NOT_A_SHAPE := 8              ## shapes 8 and 9 do nothing

var tables: FighterTables
var slot := 0


func _init(fighter_tables: FighterTables, costume_slot: int) -> void:
	tables = fighter_tables
	slot = costume_slot
	# FUN_80194328: the channels start at the costume's value of the table of hand shapes.
	var start := tables.hand_shape(slot)
	current = PackedInt32Array([start, start])
	target = PackedInt32Array([start, start])


func is_ogre() -> bool:
	return slot in OGRE_SLOTS


## FUN_8018C5A4: the speed is unsigned, event 20 takes the costume's own open shape (FUN_8019CC3C).
func event_command(command: int, value: int, table: FighterTables, costume: int) -> Vector2i:
	match command + EVENT_FIRST:
		EVENT_OPEN:
			return Vector2i(table.hand_open(costume), value)
		EVENT_COSTUME:
			return Vector2i(table.hand_shape(costume), value)
	return Vector2i(command & 7, value)


## FUN_80194080. The costume is the record's own, so the last argument is not used.
func command(hands: int, shape: int, speed: int, _char_id: int = 0) -> void:
	if shape >= FACE_OPEN:
		face_command(shape - FACE_OPEN, speed)
		return
	if shape >= NOT_A_SHAPE:
		return
	if not is_ogre():
		super(hands, shape, speed)
		return
	ogre_rate = 0
	var step := Fx.div_trunc(OGRE_LEVEL, absi(1 if speed == 0 else speed) + 1)
	if shape == 2 or shape == 3:
		ogre_target = OGRE_LEVEL
		if ogre_level < OGRE_LEVEL:
			ogre_rate = step
	else:
		ogre_target = 0
		if ogre_level > 0:
			ogre_rate = step
	target[0] = OGRE_LEVEL if shape == 2 else 0
	rate[0] = step


## FUN_80193EA4: a costume without the shape's picture keeps its face.
func face_command(shape: int, speed: int) -> void:
	if shape >= FACE_SHAPES:
		return
	face_speed = Fx.s16(speed)
	if face != shape and tables.face_rows[slot * FACE_ROW + FACE_ROW_FIRST + shape] != NO_PICTURE:
		face = shape


## FUN_80194458; `air_free` is the record's +0x1158.
func update(_char_id: int = 0, air_free: int = 0, _tables: FighterTables = null) -> void:
	if not is_ogre():
		for c in CHANNELS:
			_approach(c)
			variant[c] = variant_of(current[c])
		return
	_step_wings(air_free)
	_approach(0)
	if ogre_level < ogre_target:
		ogre_level = Fx.s16(ogre_level + ogre_rate)
		if not ogre_level < ogre_target:
			ogre_rate = 0
			ogre_level = ogre_target
	elif ogre_target < ogre_level:
		ogre_level = Fx.s16(ogre_level - ogre_rate)
		if not ogre_target < ogre_level:
			ogre_rate = 0
			ogre_level = ogre_target
	var v := Fx.s16(current[0]) >> 7
	variant[0] = v - 1 if v != 0 else 0


func _step_wings(air_free: int) -> void:
	if wing_phase == 0:
		if air_free == 0:
			if wing_frame != 0:
				wing_frame -= 1
		else:
			wing_frame += 1
			if tables.wing_open[wing_frame] == NO_PICTURE:
				wing_phase = 1
				wing_frame = 0
	elif wing_phase == 1:
		wing_frame += 1
		if tables.wing_beat[wing_frame] == NO_PICTURE:
			if air_free == 0:
				wing_frame = 0x10
				wing_phase = 0
			else:
				wing_frame = 0
	wing_variant = (tables.wing_open if wing_phase == 0 else tables.wing_beat)[wing_frame]
