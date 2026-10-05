class_name ArcadeAttachments
extends RefCounted
## The joints of an arcade model's own attachments (hair, sashes, tails, skirts:
## CharacterModel.arcade_attachments), built after each simulation step from the fight's
## skeleton. The fight keeps the PlayStation's skeleton and attachments for its own state; these
## joints only carry the arcade mesh's faces.
##
## Each attachment hangs from its parent joint at its offset, turned by its rest angles plus its
## record's offsets (FUN_8019b634). A swinging one (FUN_8019b6d8) then turns towards a blend of
## the direction to its smoothed tip of the previous step, gravity (with the helicopter stage's
## wind) and its rest direction, seen in its rest frame, as a yaw and a pitch; mode 1 aims at a
## point on another joint when that point lies further along the record's axis, mode 2 keeps the
## tip off a line fixed to another joint, and costume slot 0x24's second attachment leans
## towards a spot between joints 13 and 16. Verified case by case against the arcade's routine
## (tools/research/arcade_attachment_cases.py, tests/presentation/test_arcade_attachments.gd).

const TABLES_FILE := "characters/arcade_attachments.json"
const FIRST_ATTACHMENT_ROW := 18
const REST_ONLY_SLOTS := [0x20, 0x21]      ## their first two attachments keep identity
const REST_ONLY_COUNT := 2
# Record fields (s16 words; the first three are the rest angle offsets).
const AXIS := 3                 ## the yaw and pitch's axis record (`limits`)
const SMOOTHING := 4            ## the tip moves 1/n of the way each step
const TOWARDS := 5              ## weight of the tip's direction (of WEIGHT_ONE)
const REST := 6                 ## weight of the rest direction … and of gravity (the rest)
const LENGTH := 7               ## the tip's distance along the attachment
const GRAVITY := 8              ## the part of the down direction that is down (the rest is wind)
const MODE := 9
const TARGET_JOINT := 10
const TARGET_POINT := 11        ## three words: a point in the target joint
const TARGET_AXIS := 14         ## mode 1: the target angles' axis record; mode 2: the line's reach
const MODE_TARGET := 1
const MODE_LINE := 2
const WEIGHT_ONE := 0x100
const SLOT_FLIP := 0x26         ## mode 1 flips to FLIP_AXIS behind the target
const FLIP_AXIS := 0x28
const SLOT_CLAMP_A := 0x1A      ## clamps 0–1 on every attachment
const SLOT_CLAMP_B := 0x24      ## clamps 2–3 on the first four; the lean on attachment 1
const CLAMP_B_COUNT := 4
const LEAN_ATTACHMENT := 1
const LEAN_FROM := 13
const LEAN_TO := 16
const LEAN_MIN := 0x2400        ## squared distance below which there is no lean
const LEAN_REACH := 0x60
const LEAN_LIFT := 0x40

static var _solver: PoseSolver
static var _limits: Array[PackedInt32Array] = []
static var _clamps := PackedInt32Array()
static var _fighter_tables: FighterTables

var model: CharacterModel
var wind := PackedInt32Array([0, 0, 0])     ## FUN_8019c738's wind (x, y, z), the helicopter stage's
var _started: Array[bool] = []
var _tips: Array[PackedInt32Array] = []
var _target_yaw := 0                        ## mode 1's angles (fighter +0x1268 / +0x126C)
var _target_pitch := 0
var _previous: Array[JointFrame] = []       ## every joint of the last step
var _joints := PackedInt32Array()           ## the joints the model's attachments hang from


func _init(character: CharacterModel) -> void:
	model = character
	for a in model.arcade_attachments:
		_joints.append(a.joint)
	reset()


## Starts again from the rest rotations (FUN_8019b634, when a model is set up).
func reset() -> void:
	_started.clear()
	_tips.clear()
	for i in CharacterModel.JOINT_COUNT - CharacterModel.ARCADE_JOINT:
		_started.append(false)
		_tips.append(PackedInt32Array([0, 0, 0]))
	_target_yaw = 0
	_target_pitch = 0
	_previous.clear()


## Whether the model has an attachment on `joint`.
func has_joint(joint: int) -> bool:
	return _joints.has(joint)


## The Euler conversion of the game's tables (PoseSolver.euler_to_matrix), loaded once.
static func solver() -> PoseSolver:
	if _solver == null:
		_solver = PoseSolver.new(PoseTables.load_from(Assets.path("tables/pose.json")))
	return _solver


static func fighter_tables() -> FighterTables:
	if _fighter_tables == null:
		_fighter_tables = FighterTables.load_from(Assets.path("tables/fighter.json"))
	return _fighter_tables


## The arcade's axis records (0x801FD170: six signed bytes each) and clamps (0x801FD2F0).
static func load_tables() -> void:
	if not _limits.is_empty():
		return
	var data: Dictionary = JsonFile.read(Assets.path(TABLES_FILE))
	for record: Array in data.get("limits", []):
		_limits.append(JsonFile.ints(record))
	_clamps = JsonFile.ints(data.get("clamps", []))


## The skeleton's `joints` followed by the attachments' joints, CharacterModel.JOINT_COUNT in all
## (identity where the model has no attachment).
func update(joints: Array[JointFrame]) -> Array[JointFrame]:
	var all: Array[JointFrame] = joints.duplicate()
	while all.size() < CharacterModel.JOINT_COUNT:
		all.append(JointFrame.new())
	if _previous.size() == all.size():
		for a in model.arcade_attachments:
			all[a.joint] = _previous[a.joint]
	for a in model.arcade_attachments:
		var offset := PackedInt32Array([a.offset.x, a.offset.y, -a.offset.z])
		var previous := all[a.joint]
		all[a.joint] = JointFrame.compose_offset(all[a.parent], _local(a, previous, offset, all), offset)
	_previous = all
	return all


func _local(a: CharacterModel.ArcadeAttachment, previous: JointFrame, offset: PackedInt32Array,
		joints: Array[JointFrame]) -> PackedInt32Array:
	var i := a.joint - CharacterModel.ARCADE_JOINT
	var angles := PackedInt32Array([Fx.s16(a.rest[0] + a.record[0]), Fx.s16(a.rest[1] + a.record[1]),
		Fx.s16(a.rest[2] + a.record[2])])
	if a.static_record:
		return solver().euler_to_matrix(angles[0], angles[1], angles[2])
	if model.costume_slot in REST_ONLY_SLOTS and i < REST_ONLY_COUNT:
		return Fx.identity()
	if not _started[i]:
		_started[i] = true
		return solver().euler_to_matrix(angles[0], angles[1], angles[2])
	return swing(model.costume_slot, i, angles, a.record, previous, joints[a.parent], offset, joints)


## FUN_8019b6d8 for a started swinging attachment `i`: its local rotation this step, from its
## rest `angles`, `record`, its own joint of the last step, its parent's and the other joints
## of this step, by joint. Updates the smoothed tip and mode 1's target angles.
func swing(slot: int, i: int, angles: PackedInt32Array, record: PackedInt32Array, previous: JointFrame,
		parent: JointFrame, offset: PackedInt32Array, joints: Array[JointFrame]) -> PackedInt32Array:
	load_tables()
	var tables := fighter_tables()
	var r0 := solver().euler_to_matrix(angles[0], angles[1], angles[2])
	var to_rest := Fx.transpose(Fx.mul_matrix(parent.rot, r0))
	# The tip of the last step, smoothed over SMOOTHING steps.
	var tip := Gte.apply_lv(previous.rot, PackedInt32Array([record[LENGTH], 0, 0]))
	var smoothed := _tips[i]
	var n := record[SMOOTHING]
	for k in 3:
		tip[k] = Fx.w32(tip[k] + previous.t[k])
		smoothed[k] = Fx.div_trunc(Fx.w32((n - 1) * smoothed[k] + tip[k]), n)
		tip[k] = smoothed[k]
	var pivot := Gte.apply_lv(parent.rot, offset)
	for k in 3:
		pivot[k] = Fx.w32(pivot[k] + parent.t[k])
	var gravity_on := true
	if tip[1] >= 0:
		gravity_on = false
		tip[1] = 0
	var d := PackedInt32Array([Fx.w32(tip[0] - pivot[0]), Fx.w32(tip[1] - pivot[1]), Fx.w32(tip[2] - pivot[2])])
	var dir := Gte.vector_normal(Gte.apply_lv(to_rest, d), tables.rsqrt)
	var down := PackedInt32Array([0, 0, 0])
	if gravity_on:
		var g := record[GRAVITY]
		down = Gte.apply(to_rest, _shift8(wind[0] * g), (WEIGHT_ONE - g) * 0x10, _shift8(wind[2] * g))
	var v := PackedInt32Array([0, 0, 0])
	for k in 3:
		v[k] = _shift8(Fx.w32(record[TOWARDS] * dir[k] + record[REST] * down[k]))
	v[0] = Fx.w32(v[0] + (WEIGHT_ONE - (record[TOWARDS] + record[REST])) * 0x10)
	var flipped := false
	if record[MODE] == MODE_LINE:
		v = _line(record, to_rest, v, pivot, joints[joint_of_row(record[TARGET_JOINT])])
	elif record[MODE] == MODE_TARGET:
		flipped = _aim(slot, record, to_rest, pivot, joints[joint_of_row(record[TARGET_JOINT])])
	if slot == SLOT_CLAMP_B and i == LEAN_ATTACHMENT:
		v = _lean(to_rest, previous, joints, v)
	var axis := record[AXIS] & 0xFFFF
	if slot == SLOT_FLIP and flipped:
		axis = FLIP_AXIS
	var lim := _limits[axis]
	var yaw := Fx.w32(Gte.ratan2(Fx.w32(lim[0] * v[2]), Fx.w32(lim[1] * v[0]), tables.ratan) * lim[4])
	var flat := solver().tables.square_root0(Fx.w32(v[0] * v[0] + v[2] * v[2]))
	var pitch := Fx.w32(Gte.ratan2(Fx.w32(lim[2] * v[1]), Fx.w32(lim[3] * flat), tables.ratan) * lim[5])
	if record[MODE] == MODE_TARGET:
		var t := _limits[record[TARGET_AXIS]]
		if Fx.w32(t[5] * _target_yaw + t[4] * _target_pitch) < Fx.w32(t[5] * yaw + t[4] * pitch):
			yaw = _target_yaw
			pitch = _target_pitch
	var s_yaw := Fx.s16(yaw << 4)
	var s_pitch := Fx.s16(pitch << 4)
	var clamp_at := -1
	if slot == SLOT_CLAMP_A:
		clamp_at = 0
	elif slot == SLOT_CLAMP_B and i < CLAMP_B_COUNT:
		clamp_at = 2
	if clamp_at >= 0:
		var hi := _clamps[clamp_at]
		var lo := _clamps[clamp_at + 1]
		if s_yaw > hi:
			s_yaw = hi
		elif s_yaw < lo:
			s_yaw = lo
		if s_pitch > hi:
			s_pitch = hi
		elif s_pitch < lo:
			s_pitch = lo
	return Fx.mul_matrix(r0, solver().euler_to_matrix(0, s_yaw, s_pitch))


## Mode 1's target angles (FUN_8019bed0): towards the record's point on the target joint, seen
## in the rest frame; true when costume slot 0x26 flips its axis (the point is behind).
func _aim(slot: int, record: PackedInt32Array, to_rest: PackedInt32Array, pivot: PackedInt32Array,
		target: JointFrame) -> bool:
	var v := Gte.apply_lv(target.rot, PackedInt32Array([record[TARGET_POINT], record[TARGET_POINT + 1],
		record[TARGET_POINT + 2]]))
	for k in 3:
		v[k] = Fx.w32(v[k] + target.t[k] - pivot[k])
	v = Gte.apply_lv(to_rest, v)
	var axis := record[AXIS] & 0xFFFF
	var flipped := false
	if slot == SLOT_FLIP and v[0] < 0:
		flipped = true
		axis = FLIP_AXIS
	var lim := _limits[axis]
	var tables := fighter_tables()
	_target_yaw = Fx.w32(Gte.ratan2(Fx.w32(lim[0] * v[2]), Fx.w32(lim[1] * v[0]), tables.ratan) * lim[4])
	var flat := solver().tables.square_root0(Fx.w32(v[0] * v[0] + v[2] * v[2]))
	_target_pitch = Fx.w32(Gte.ratan2(Fx.w32(lim[2] * v[1]), Fx.w32(lim[3] * flat), tables.ratan) * lim[5])
	return flipped


## Mode 2 (FUN_8019c15c): the direction `v` (scaled by the tip's length) is kept off the line
## through the record's point on the target joint along the joint's x axis: within the reach it
## is pushed out to the reach.
func _line(record: PackedInt32Array, to_rest: PackedInt32Array, v: PackedInt32Array, pivot: PackedInt32Array,
		target: JointFrame) -> PackedInt32Array:
	var length := record[LENGTH]
	var along := Gte.apply_lv(target.rot, PackedInt32Array([0x1000, record[TARGET_POINT + 1] << 12,
		record[TARGET_POINT + 2] << 12]))
	var at := Gte.apply_lv(target.rot, PackedInt32Array([0, record[TARGET_POINT + 1] << 12,
		record[TARGET_POINT + 2] << 12]))
	for k in 3:
		along[k] = Fx.w32(along[k] + target.t[k] * 0x1000 - pivot[k] * 0x1000)
		at[k] = Fx.w32(at[k] + target.t[k] * 0x1000 - pivot[k] * 0x1000)
	at = Gte.apply_lv(to_rest, at)
	along = Gte.apply_lv(to_rest, along)
	var c := PackedInt32Array([0, 0, 0])
	var e := PackedInt32Array([0, 0, 0])
	for k in 3:
		c[k] = Fx.w32(at[k] - length * v[k])
		e[k] = Fx.w32(along[k] - at[k])
	var dot := _shift12(Fx.w32(c[0] * e[0] + c[1] * e[1] + c[2] * e[2]))
	# p: the line's point nearest the tip; the tip is pushed out from it to the reach.
	var p := PackedInt32Array([0, 0, 0])
	var sq := 0
	for k in 3:
		p[k] = _shift12(Fx.w32(at[k] - _shift12(Fx.w32(dot * e[k]))))
		var q := _shift12(Fx.w32(length * v[k])) - p[k]
		sq = Fx.w32(sq + q * q)
	var reach := record[TARGET_AXIS]
	if sq >= reach * reach:
		return v
	var root := solver().tables.square_root0(sq)
	if root == 0:
		root = 1
	var out := PackedInt32Array([0, 0, 0])
	for k in 3:
		out[k] = Fx.w32(Fx.div_trunc(Fx.w32((_shift12(Fx.w32(length * v[k])) - p[k]) * reach), root) + p[k])
	return out


## FUN_8019c598: costume slot 0x24's lean towards a spot LEAN_REACH from joint 13 towards
## joint 16, lifted by LEAN_LIFT, when the joints are far enough apart.
func _lean(to_rest: PackedInt32Array, previous: JointFrame, joints: Array[JointFrame], v: PackedInt32Array) -> PackedInt32Array:
	var a := joints[LEAN_FROM].t
	var b := joints[LEAN_TO].t
	var d := PackedInt32Array([Fx.w32(b[0] - a[0]), Fx.w32(b[1] - a[1]), Fx.w32(b[2] - a[2])])
	var sq := Fx.w32(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	if sq < LEAN_MIN:
		return v
	var length := solver().tables.square_root0(sq)
	if length == 0:
		length = 1
	var w := PackedInt32Array([0, 0, 0])
	for k in 3:
		w[k] = Fx.w32(Fx.div_trunc(Fx.w32(d[k] * LEAN_REACH), length) + a[k])
	w[2] = Fx.w32(w[2] + LEAN_LIFT)
	for k in 3:
		w[k] = Fx.w32(w[k] - previous.t[k])
	return Gte.vector_normal(Gte.apply_lv(to_rest, w), fighter_tables().rsqrt)


## The joint of an arcade model row (rows 18–23 are the attachments, from ARCADE_JOINT).
static func joint_of_row(row: int) -> int:
	return row if row < FIRST_ATTACHMENT_ROW else CharacterModel.ARCADE_JOINT + row - FIRST_ATTACHMENT_ROW


## C's signed division by 256 (towards zero), as the compiled `(x + 0xFF) >> 8` for negatives.
static func _shift8(x: int) -> int:
	return (x + 0xFF if x < 0 else x) >> 8


static func _shift12(x: int) -> int:
	return (x + 0xFFF if x < 0 else x) >> 12
