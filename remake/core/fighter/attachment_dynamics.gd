class_name AttachmentDynamics
extends RefCounted
## The swinging costume attachments (draw parts 18–21: hair, belts, scarves), FUN_80037F10.
##
## Each frame an attachment with a dynamics record turns its rest orientation towards a blend
## of three directions, seen in its rest frame: towards where its tip was on the previous frame
## (inertia), downwards (gravity, off while the tip touches the floor) and its rest direction.
## The blend becomes a yaw and a pitch through `ratan2` with per-record axis signs and scales,
## a few costumes clamp or cancel angles, and mode 1 aims at a point on another joint instead
## when that point lies further along the record's axis. The local rotation is then
## `rest · Euler(0, yaw, pitch)`.

const FIRST_PART := 18
const COUNT := 4
const REST_ONLY_SLOTS := [0x20, 0x21]      ## the first two attachments keep their local rotation
# Record fields (s16).
const LIMIT := 0
const INERTIA := 2
const GRAVITY := 3
const LENGTH := 4
const BALANCE := 5
const MODE := 6
const TARGET_JOINT := 7
const TARGET_OFFSET := 8
const TARGET_LIMIT := 11
const MODE_TARGET := 1
const WEIGHT_ONE := 0x100
# Costume slots with special handling in FUN_80037F10 / FUN_80038684.
const SLOT_NO_YAW_0 := 0x0E
const SLOT_NO_YAW_PARTS := 0x0F
const SLOT_NO_YAW_2 := 0x1B
const SLOT_FLIP := 0x26
const SLOT_CLAMP_A := 0x1A
const SLOT_CLAMP_B := [0x24, 0x29]
const FLIP_LIMIT := 2
const FLIP_TARGET_LIMIT := 8
const MIN_PITCH := 0x800
const LEAN_JOINTS := [16, 13]              ## FUN_800388C0: the direction from joint 13 to joint 16
const LEAN_MIN := 0x4000
const LEAN_LIFT := 0x40

var tables: FighterTables
var solver: PoseSolver
var pose_tables: PoseTables
var slot := 0
var rest: Array[PackedInt32Array] = []
var records: Array[PackedInt32Array] = []
var local: Array[PackedInt32Array] = []
var started: Array[bool] = [false, false, false, false]
var target_yaw := 0                         ## +0x1388
var target_pitch := 0                       ## +0x138C


func _init(fighter_tables: FighterTables, poses: PoseTables, pose_solver: PoseSolver, model: CharacterModel) -> void:
	tables = fighter_tables
	pose_tables = poses
	solver = pose_solver
	slot = model.costume_slot
	for i in COUNT:
		var part := model.parts[FIRST_PART + i]
		rest.append(part.rest if part.rest.size() == 3 else PackedInt32Array([0, 0, 0]))
		records.append(part.dynamics)
		local.append(Fx.identity())


## The local rotation of attachment `i` this frame. `parent` is its parent joint (this frame),
## `previous` its own joint on the previous frame, `offset` its local translation, `joints`
## the fighter's joints of this frame (0–17 are already built).
func update(i: int, parent: JointFrame, previous: JointFrame, offset: PackedInt32Array, joints: Array[JointFrame]) -> PackedInt32Array:
	var p := records[i]
	if p.is_empty() or (slot in REST_ONLY_SLOTS and i < 2):
		return local[i]
	var r := rest[i]
	if not started[i]:
		started[i] = true
		local[i] = solver.euler_to_matrix(r[0], r[1], r[2])
		return local[i]
	var r0 := solver.euler_to_matrix(r[0], r[1], r[2])
	var world_rest := Fx.mul_matrix(parent.rot, r0)
	var to_rest := Fx.transpose(world_rest)
	var tip := Gte.apply(previous.rot, p[LENGTH], 0, 0)
	for k in 3:
		tip[k] = Fx.w32(tip[k] + previous.t[k])
	var pivot := Gte.apply(parent.rot, offset[0], offset[1], offset[2])
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
		var side := Fx.s16(p[BALANCE] >> 4)
		down = Gte.apply(to_rest, side, Fx.s16((WEIGHT_ONE - p[BALANCE]) * 0x10), side)
	var out := PackedInt32Array([0, 0, 0])
	for k in 3:
		var v := Fx.w32(dir[k] * p[INERTIA] + down[k] * p[GRAVITY])
		out[k] = (v + 0xFF if v < 0 else v) >> 8
	out[0] = Fx.w32(out[0] + (WEIGHT_ONE - (p[INERTIA] + p[GRAVITY])) * 0x10)
	var flipped := false
	if p[MODE] == MODE_TARGET:
		flipped = _aim(p, to_rest, pivot, joints)
	elif slot in SLOT_CLAMP_B and i == 0:
		out = _lean(to_rest, previous, joints, out)
	var lim_index := p[LIMIT]
	if slot == SLOT_FLIP and flipped:
		lim_index = FLIP_LIMIT
	var lim := tables.attachment_limits[lim_index]
	var yaw_raw := Gte.ratan2(Fx.w32(lim[0] * out[2]), Fx.w32(lim[1] * out[0]), tables.ratan)
	var flat := pose_tables.square_root0(Fx.w32(out[0] * out[0] + out[2] * out[2]))
	var pitch_raw := Gte.ratan2(Fx.w32(lim[2] * out[1]), Fx.w32(lim[3] * flat), tables.ratan)
	var yaw := Fx.w32(yaw_raw * lim[4])
	var pitch := Fx.w32(pitch_raw * lim[5])
	if p[MODE] == MODE_TARGET:
		var t := tables.attachment_limits[p[TARGET_LIMIT]]
		var f := Fx.s16(t[5])
		var e := Fx.s16(t[4])
		if Fx.w32(f * target_yaw + e * target_pitch) < Fx.w32(f * yaw + e * pitch):
			yaw = target_yaw
			pitch = target_pitch
	var s_yaw := Fx.s16(yaw << 4)
	var s_pitch := Fx.w32(pitch << 4)
	if slot == SLOT_NO_YAW_0 and i == 0:
		s_yaw = 0
	if slot == SLOT_NO_YAW_PARTS and (i == 1 or i == 2):
		s_yaw = 0
	if slot == SLOT_NO_YAW_2 and i == 2:
		s_yaw = 0
	if slot == SLOT_FLIP:
		if i == 0:
			s_pitch = maxi(s_pitch, MIN_PITCH)
		elif i == 3:
			s_yaw = 0
	var pitch16 := Fx.s16(s_pitch)
	var clamp_at := -1
	if slot in SLOT_CLAMP_B and i < 4:
		clamp_at = 2
	elif slot == SLOT_CLAMP_A:
		clamp_at = 0
	if clamp_at >= 0:
		var hi := tables.attachment_clamps[clamp_at]
		var lo := tables.attachment_clamps[clamp_at + 1]
		if s_yaw > hi:
			s_yaw = hi
		elif s_yaw < lo:
			s_yaw = lo
		if pitch16 > hi:
			pitch16 = hi
		elif pitch16 < lo:
			pitch16 = lo
	local[i] = Fx.mul_matrix(r0, solver.euler_to_matrix(0, s_yaw, pitch16))
	return local[i]


## FUN_80038684: the target angles towards a point fixed to another joint (mode 1); true when
## costume slot 0x26 flips to its other limit record.
func _aim(p: PackedInt32Array, to_rest: PackedInt32Array, pivot: PackedInt32Array, joints: Array[JointFrame]) -> bool:
	var j := joints[p[TARGET_JOINT]]
	var v := Gte.apply_lv(j.rot, PackedInt32Array([p[TARGET_OFFSET], p[TARGET_OFFSET + 1], p[TARGET_OFFSET + 2]]))
	for k in 3:
		v[k] = Fx.w32(v[k] + j.t[k] - pivot[k])
	v = Gte.apply_lv(to_rest, v)
	var lim_index := p[LIMIT]
	var flipped := false
	if slot == SLOT_FLIP and v[0] < 0:
		lim_index = FLIP_TARGET_LIMIT
		flipped = true
	var lim := tables.attachment_limits[lim_index]
	target_yaw = Fx.w32(Gte.ratan2(Fx.w32(lim[0] * v[2]), Fx.w32(lim[1] * v[0]), tables.ratan) * lim[4])
	var flat := pose_tables.square_root0(Fx.w32(v[0] * v[0] + v[2] * v[2]))
	target_pitch = Fx.w32(Gte.ratan2(Fx.w32(lim[2] * v[1]), Fx.w32(lim[3] * flat), tables.ratan) * lim[5])
	return flipped


## FUN_800388C0: the first attachment of costume slots 0x24 and 0x29 points at a spot 128 units
## from joint 13 towards joint 16, lifted by 64, when those joints are far enough apart.
func _lean(to_rest: PackedInt32Array, previous: JointFrame, joints: Array[JointFrame], out: PackedInt32Array) -> PackedInt32Array:
	var a := joints[LEAN_JOINTS[1]].t
	var b := joints[LEAN_JOINTS[0]].t
	var d := PackedInt32Array([Fx.w32(b[0] - a[0]), Fx.w32(b[1] - a[1]), Fx.w32(b[2] - a[2])])
	var sq := Fx.w32(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	if sq < LEAN_MIN:
		return out
	var length := pose_tables.square_root0(sq)
	if length == 0:
		length = 1
	var v := PackedInt32Array([0, 0, 0])
	for k in 3:
		v[k] = Fx.w32(Fx.div_trunc(Fx.w32(d[k] << 7), length) + a[k])
	v[2] = Fx.w32(v[2] + LEAN_LIFT)
	for k in 3:
		v[k] = Fx.w32(v[k] - previous.t[k])
	return Gte.vector_normal(Gte.apply_lv(to_rest, v), tables.rsqrt)
