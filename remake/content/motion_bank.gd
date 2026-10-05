class_name MotionBank
extends RefCounted
## A motion bank (`divmot*.bin`) as converted: move rows, the move-index slots, the
## baked 49-channel pose vectors of every animation stream, the branch rows, the sound and frame
## event lists, the attack records and the baked camera streams.
## See docs/research/formats/divmot-banks.md.

const COMMON_FLAG := 0x40000000      ## slot entries / animation words in the common bank
const EMPTY_SLOT := 0x3FFFFFFF
const POSE_CHANNELS := 49
const POSE_BYTES := POSE_CHANNELS * 2
const ROW_ANIM := 0                  ## word index of the animation offset in a move row
const ROW_EVENTS := 8                ## word index of the event list index (+0x20), −1 for none
const ROW_FLAGS := 9                 ## word index of the flags (+0x24)
const NO_LIST := 0xFFFFFFFF
const CAMERA_CHANNELS := 7           ## eye x, y, z, target x, y, z, fight-camera weight
const CAMERA_BYTES := CAMERA_CHANNELS * 2

var name: String
var type_code: int
var moves: Array[PackedInt64Array] = []
var move_index: PackedInt64Array
var anims: Dictionary = {}           ## stream offset → Vector2i(first pose, frame count)
var poses: PackedByteArray
var events: PackedInt32Array         ## section 4 as u16 words: (frame, command) pairs, 0-ended
var camera_choices: Array[PackedInt32Array] = []   ## section 7: (kind, weight, script)
var camera_streams: Dictionary = {}  ## section-8 offset → Vector3i(first sample, frames, yaw mode)
var camera_samples: PackedByteArray
var branches: Array[PackedInt32Array] = []   ## command, restriction, condition, parameter, target,
											 ## flags, first, last, entry
var sounds: PackedInt32Array         ## section 3 as u16 words
var empty_slots: PackedInt32Array    ## section 5: bit s of word s / 16 set when slot s is empty
var attacks: PackedByteArray         ## section 9: attack records
var anim_bytes: Dictionary = {}      ## stream offset → Vector2i(first byte of the stream, tag)


## A converted bank by name from a folder (`<name>.json.gz`, `.poses.bin.gz`, `.camera.bin`,
## `.attacks.bin`).
static func load_named(folder: String, bank_name: String) -> MotionBank:
	var base := folder.path_join(bank_name)
	var data: Dictionary = JsonFile.read(base + ".json.gz")
	var bank := MotionBank.new()
	bank.name = data.get("name", "")
	bank.type_code = data.get("type", -1)
	for row: Array in data.get("moves", []):
		bank.moves.append(PackedInt64Array(row))
	var index: Array = data.get("move_index", [])
	bank.move_index = PackedInt64Array(index)
	var anim_table: Dictionary = data.get("anims", {})
	for key: String in anim_table:
		var entry: Array = anim_table[key]
		var first: int = entry[0]
		var frames: int = entry[1]
		bank.anims[int(key)] = Vector2i(first, frames)
		if entry.size() >= 4:
			var first_byte: int = entry[2]
			var tag: int = entry[3]
			bank.anim_bytes[int(key)] = Vector2i(first_byte, tag)
	bank.poses = DataFile.read(base + ".poses.bin.gz")
	bank.events = JsonFile.ints(data.get("events", []))
	for choice: Array in data.get("camera_choices", []):
		bank.camera_choices.append(JsonFile.ints(choice))
	var streams: Dictionary = data.get("camera_streams", {})
	for key: String in streams:
		var s := JsonFile.ints(streams[key])
		bank.camera_streams[int(key)] = Vector3i(s[0], s[1], s[2])
	var camera_path := base + ".camera.bin"
	if FileAccess.file_exists(camera_path):
		bank.camera_samples = FileAccess.get_file_as_bytes(camera_path)
	for row: Array in data.get("branches", []):
		bank.branches.append(JsonFile.ints(row))
	bank.sounds = JsonFile.ints(data.get("sounds", []))
	bank.empty_slots = JsonFile.ints(data.get("empty_slots", []))
	var attacks_path := base + ".attacks.bin"
	if FileAccess.file_exists(attacks_path):
		bank.attacks = FileAccess.get_file_as_bytes(attacks_path)
	return bank


## DivmotLinkBank: every move row decoded and linked (`common` is the common bank, this bank
## itself for the common bank; `builtins` the built-in attack descriptor ids). The rows refer to
## this bank; the bank does not keep them, so that no reference cycle forms (FightContent keeps
## them).
func link(common: MotionBank, builtins: PackedInt32Array) -> Array[MoveRow]:
	var rows: Array[MoveRow] = []
	for r in moves.size():
		rows.append(MoveRow.link(self, r, common, builtins))
	return rows


## The first byte of a stream's header (the frame count's low byte), which DivmotLinkBank stores
## as the move's length.
func anim_first_byte(offset: int) -> int:
	var entry: Vector2i = anim_bytes.get(offset, Vector2i(-1, 0))
	return entry.x if entry.x >= 0 else frame_count(offset) & 0xFF


## The s16 tag before a stream (reversal condition 0x4B).
func anim_tag(offset: int) -> int:
	return (anim_bytes.get(offset, Vector2i(0, 0)) as Vector2i).y


func slot_empty(slot: int) -> bool:
	return (empty_slots[slot >> 4] >> (slot & 15)) & 1 != 0


func has_anim(offset: int) -> bool:
	return anims.has(offset)


func frame_count(offset: int) -> int:
	return (anims[offset] as Vector2i).y


## Pose vector of an animation at a 0-based frame, clamped to the stream like AnimDecodePose.
func pose(offset: int, frame: int) -> PackedInt32Array:
	var entry: Vector2i = anims[offset]
	var index := entry.x + clampi(frame, 0, entry.y - 1)
	var out := PackedInt32Array()
	out.resize(POSE_CHANNELS)
	var base := index * POSE_BYTES
	for c in POSE_CHANNELS:
		out[c] = poses.decode_s16(base + 2 * c)
	return out


func move_flags(row: int) -> int:
	return moves[row][ROW_FLAGS]


## One frame of a camera stream as FUN_80038F38 returns it (7 channels).
func camera_sample(offset: int, frame: int) -> PackedInt32Array:
	var entry: Vector3i = camera_streams[offset]
	var base := (entry.x + clampi(frame, 0, entry.y - 1)) * CAMERA_BYTES
	var out := PackedInt32Array()
	out.resize(CAMERA_CHANNELS)
	for c in CAMERA_CHANNELS:
		out[c] = camera_samples.decode_s16(base + 2 * c)
	return out


func camera_frames(offset: int) -> int:
	return (camera_streams[offset] as Vector3i).y
