class_name FighterTables
extends RefCounted
## Per-costume tables of the fighter code, converted from the game executable
## (`imported/tables/fighter.json`).

const NO_KEY := 0

var costume_keys: PackedInt32Array        ## costume key (charId · 4 + costume) → costume slot
var costume_hand_shapes: PackedInt32Array ## costume slot → default hand shape (FUN_800364E8)
var costume_open_shapes: PackedInt32Array ## the arcade's costume slot → open hand shape (FUN_8019CC3C)
var attachment_limits: Array[PackedInt32Array] = []   ## FUN_80037F10's six-int records
var attachment_clamps: PackedInt32Array   ## (max, min) for costume slot 0x1A, then 0x24 / 0x29
var ratan: PackedInt32Array               ## libgte ratan2 table
var rsqrt: PackedInt32Array               ## VectorNormal's reciprocal square roots
var wing_open: PackedInt32Array           ## True Ogre's wing variants while they open (−1 ends)
var wing_beat: PackedInt32Array           ## the variants of one wing beat (−1 ends)
var face_rows: PackedInt32Array           ## the arcade's face pictures: 8 s8 per costume slot
var face_blink: PackedInt32Array          ## the arcade's face shape of a blink, per costume slot
var face_react: PackedInt32Array          ## ... during a move with the flag REACT_CHAIN
var face_down: PackedInt32Array           ## ... lying down


static func load_from(path: String) -> FighterTables:
	var data: Dictionary = JsonFile.read(path)
	var t := FighterTables.new()
	t.costume_keys = JsonFile.ints(data["costume_keys"])
	t.costume_hand_shapes = JsonFile.ints(data["costume_hand_shapes"])
	t.costume_open_shapes = JsonFile.ints(data.get("costume_open_shapes", []))
	for record: Array in data.get("attachment_limits", []):
		t.attachment_limits.append(JsonFile.ints(record))
	t.attachment_clamps = JsonFile.ints(data.get("attachment_clamps", []))
	t.ratan = JsonFile.ints(data.get("ratan", []))
	t.rsqrt = JsonFile.ints(data.get("rsqrt", []))
	t.wing_open = JsonFile.ints(data.get("wing_open", []))
	t.wing_beat = JsonFile.ints(data.get("wing_beat", []))
	t.face_rows = JsonFile.ints(data.get("face_rows", []))
	t.face_blink = JsonFile.ints(data.get("face_blink", []))
	t.face_react = JsonFile.ints(data.get("face_react", []))
	t.face_down = JsonFile.ints(data.get("face_down", []))
	return t


## FUN_80036440: the first costume key that selects `slot`, or key 0 when none does
## (the game then also sets the slot to that key's slot).
func key_of_slot(slot: int) -> int:
	for key in costume_keys.size():
		if costume_keys[key] == slot:
			return key
	return NO_KEY


## FUN_8019CC3C: the arcade costume's open hand shape (move event 20), 0 beyond the table.
func hand_open(slot: int) -> int:
	return costume_open_shapes[slot] if slot >= 0 and slot < costume_open_shapes.size() else 0


## FUN_800364E8: the costume's own hand shape (move event 21), 0 beyond the table.
func hand_shape(slot: int) -> int:
	return costume_hand_shapes[slot] if slot >= 0 and slot < costume_hand_shapes.size() else 0
