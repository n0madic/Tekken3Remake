class_name FighterSkeleton
extends RefCounted
## A fighter's joints for one frame: pose vector → local rotations (PoseSolver) → root
## (RootUpdate) → world joint frames (FighterComposeJoints).
##
## Rules: docs/research/formats/animation.md#pose-to-matrices and
## docs/research/code/moves.md#root-motion.
## The costume attachments 18–21 swing with AttachmentDynamics (FUN_80037F10) when fighter
## tables are given; without them, or without a dynamics record, they follow their parent joint
## rigidly at the KMD offset.
## The fight builds its joints with FighterAnimation (motion blending, head look-at, True
## Ogre's sway); this skeleton serves the attract demonstration and the model viewer.

const JOINTS := 18                  ## joints built from the pose vector
const ALL_JOINTS := CharacterModel.PART_COUNT

var solver: PoseSolver
var tables: PoseTables
var offsets: Array[PackedInt32Array]
var parents: PackedInt32Array
var scale: int                                   ## model scale, 4.12
var local_slots: Array[PackedInt32Array] = []    ## persist between frames, as in the game
var root := JointFrame.new()
var joints: Array[JointFrame] = []
var attachments: AttachmentDynamics


func _init(pose_tables: PoseTables, model: CharacterModel, fighter_tables: FighterTables = null) -> void:
	tables = pose_tables
	solver = PoseSolver.new(pose_tables)
	if fighter_tables != null:
		attachments = AttachmentDynamics.new(fighter_tables, pose_tables, solver, model)
	offsets = model.joint_offsets()
	parents = model.joint_parents()
	scale = model.scale_fixed()
	for i in JOINTS:
		local_slots.append(Fx.identity())
	for i in ALL_JOINTS:
		joints.append(JointFrame.new())


## Root displacement of a pose vector (AnimDecodeRoot × model scale, AnimScaleRoot).
func root_displacement(pose: PackedInt32Array) -> PackedInt32Array:
	return PackedInt32Array([
		Fx.s16((pose[0] * scale) >> 12),
		Fx.s16((pose[1] * scale) >> 12),
		Fx.s16((pose[2] * scale) >> 12),
	])


## Poses the skeleton on the ground at `anchor` (the move's anchor, fighter posX/Y/Z)
## with the given facing and heading (16-bit angles), no tilt.
func update(pose: PackedInt32Array, anchor: PackedInt32Array, facing: int, heading: int) -> void:
	solver.build(pose, local_slots)
	var d := root_displacement(pose)
	var a := ((0x8000 - facing) >> 4) & 0xFFF
	var c := tables.cos12(a)
	var s := tables.sin12(a)
	root = JointFrame.new(
		root_rotation(0, (heading - 0x8000) & 0xFFFF, 0),
		PackedInt32Array([
			anchor[0] + Fx.trunc12(d[0] * c - d[2] * s),
			anchor[1] + d[1],
			anchor[2] + Fx.trunc12(d[0] * s + d[2] * c),
		]))
	for m in JOINTS:
		var parent := root if parents[m] < 0 else joints[parents[m]]
		joints[m] = JointFrame.compose_offset(parent, local_slots[m], offsets[m])
	for m in range(JOINTS, ALL_JOINTS):
		var parent := root if parents[m] < 0 else joints[parents[m]]
		var local := Fx.identity()
		if attachments != null:
			local = attachments.update(m - JOINTS, parent, joints[m], offsets[m], joints)
		joints[m] = JointFrame.compose_offset(parent, local, offsets[m])


## FUN_8003A6B4: Rx·Ry·Rz from three 16-bit angles with the game's GTE rounding.
func root_rotation(x: int, y: int, z: int) -> PackedInt32Array:
	return rotation_xyz(x, y, z, tables)


static func rotation_xyz(x: int, y: int, z: int, tables: PoseTables) -> PackedInt32Array:
	var cx := tables.cos12(x >> 4)
	var sx := tables.sin12(x >> 4)
	var cy := tables.cos12(y >> 4)
	var sy := tables.sin12(y >> 4)
	var cz := tables.cos12(z >> 4)
	var sz := tables.sin12(z >> 4)
	var a1 := Fx.sat16((sx * cz) >> 12)
	var a2 := Fx.sat16((sx * sz) >> 12)
	var a3 := Fx.sat16((sx * cy) >> 12)
	var cxcz := (cx * cz) >> 12
	var b1 := Fx.sat16((sy * a1) >> 12)
	var b2 := Fx.sat16((sy * a2) >> 12)
	var b3 := Fx.sat16((sy * cxcz) >> 12)
	var cxsz := (cx * sz) >> 12
	return PackedInt32Array([
		Fx.s16(Fx.sat16((cy * cz) >> 12)), Fx.s16(Fx.sat16((cy * -sz) >> 12)), Fx.s16(sy),
		Fx.s16(b1 + cxsz), Fx.s16(cxcz - b2), Fx.s16(-a3),
		Fx.s16(a2 - b3), Fx.s16(((cxsz * sy) >> 12) + a1), Fx.s16(Fx.sat16((cy * cx) >> 12)),
	])
