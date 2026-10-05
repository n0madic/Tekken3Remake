class_name PoseTables
extends RefCounted
## Constant tables of the pose pipeline, converted from the game executable
## (`imported/tables/pose.json`): sine/cosine, SquareRoot0 mantissas, the Euler joint
## slots, the limb basis and the normalised skeleton offsets.

const COS_OFFSET := 1024       ## g_cosTable starts a quarter turn into g_sinTable
const SQRT_BASE := 0x40

var sin_table: PackedInt32Array
var sqrt_table: PackedInt32Array
var euler_slots: PackedInt32Array
var limb_basis: PackedInt32Array
var skeleton_offsets: Array[PackedInt32Array] = []   ## chest, right/left shoulder, hips
var limb_offsets: Array[PackedInt32Array] = []       ## IK root offsets: arms, legs


static func load_from(path: String) -> PoseTables:
	var data: Dictionary = JsonFile.read(path)
	var t := PoseTables.new()
	t.sin_table = JsonFile.ints(data["sin"])
	t.sqrt_table = JsonFile.ints(data["sqrt"])
	t.euler_slots = JsonFile.ints(data["euler_slots"])
	t.limb_basis = JsonFile.ints(data["limb_basis"])
	t.skeleton_offsets = _triples(JsonFile.ints(data["skeleton_offsets"]))
	t.limb_offsets = _triples(JsonFile.ints(data["limb_offsets"]))
	return t


static func _triples(values: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for i in range(0, values.size(), 3):
		out.append(PackedInt32Array([values[i], values[i + 1], values[i + 2]]))
	return out


## Sine of a 16-bit angle (65536 = one turn), 4.12, as `tab.sin` in the pose code.
func sin16(angle: int) -> int:
	return sin_table[(angle >> 4) & 0xFFF]


func cos16(angle: int) -> int:
	return sin_table[COS_OFFSET + ((angle >> 4) & 0xFFF)]


## Entry of the 4096-unit tables (`fight_math.trig_raw`).
func sin12(index: int) -> int:
	return sin_table[index & 0xFFF]


func cos12(index: int) -> int:
	return sin_table[COS_OFFSET + (index & 0xFFF)]


## libgte SquareRoot0 with the game's mantissa table.
func square_root0(a: int) -> int:
	if a == 0:
		return 0
	var lz := 32 - Fx.bit_length(a)
	lz &= ~1
	var x := a >> (24 - lz) if lz < 24 else a << (lz - 24)
	var mant := sqrt_table[x - SQRT_BASE] & 0xFFFFFFFF
	return ((mant << ((31 - lz) >> 1)) & 0xFFFFFFFF) >> 12
