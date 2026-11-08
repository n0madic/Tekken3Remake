class_name ArcadeBank
extends MotionBank
## The arcade's one motion bank (tools/remake_import/arcade_motion_bake.py): every bank type shares
## its move rows and branch rows, each type has its own full table of slots, the poses are 57
## channels (3 of the root and 3 per joint, no inverse kinematics).

const BANK_NAME := "arcade"
const CHANNELS := 57
const CHANNEL_BYTES := CHANNELS * 2
const STREAM_BLOCK_FRAMES := 16

var slots: Array[PackedInt32Array] = []      ## per bank type: the row of each slot


static func load_arcade(folder: String) -> ArcadeBank:
	var bank := ArcadeBank.new()
	var data := bank._read(folder.path_join(BANK_NAME))
	var tables: Array = data["slots"]
	for table: Array in tables:
		bank.slots.append(JsonFile.ints(table))
	return bank


## The channels of a stream's frame (0-based). FUN_80194744 reads a frame before the first (the
## blend's source of a move that starts at frame 0) as frame 15 of the stream's first block.
func pose(offset: int, frame: int) -> PackedInt32Array:
	var entry: Vector2i = anims[offset]
	if frame < 0:
		frame = ((frame - 1) & (STREAM_BLOCK_FRAMES - 1)) + 1
	var index := entry.x + clampi(frame, 0, entry.y - 1)
	var out := PackedInt32Array()
	out.resize(CHANNELS)
	var base := index * CHANNEL_BYTES
	for c in CHANNELS:
		out[c] = poses.decode_s16(base + 2 * c)
	return out
