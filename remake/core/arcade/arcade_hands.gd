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


func _is_ogre(_char_id: int) -> bool:
	return is_ogre()


## FUN_8018C5A4: the speed is unsigned, event 20 takes the costume's own open shape (FUN_8019CC3C).
func event_command(command: int, value: int, table: FighterTables, costume: int) -> Vector2i:
	match command + EVENT_FIRST:
		EVENT_OPEN:
			return Vector2i(table.hand_open(costume), value)
		EVENT_COSTUME:
			return Vector2i(table.hand_shape(costume), value)
	return Vector2i(command & 7, value)


## FUN_80194080. The costume is the record's own, so the character is not used: a face is one of its own
## shapes, the rest is the PlayStation's command.
func command(hands: int, shape: int, speed: int, char_id: int = 0) -> void:
	if shape >= FACE_OPEN:
		face_command(shape - FACE_OPEN, speed)
		return
	super(hands, shape, speed, char_id)


## FUN_80193EA4: a costume without the shape's picture keeps its face.
func face_command(shape: int, speed: int) -> void:
	if shape >= FACE_SHAPES:
		return
	face_speed = Fx.s16(speed)
	if face != shape and tables.face_rows[slot * FACE_ROW + FACE_ROW_FIRST + shape] != NO_PICTURE:
		face = shape


## FUN_80194458's wings: a wing's step is always one.
func _update_wings(air_free: int, _tables: FighterTables) -> void:
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
