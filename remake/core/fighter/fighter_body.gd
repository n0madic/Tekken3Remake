class_name FighterBody
extends RefCounted
## A fighter's skeleton as the fight code keeps it: the model's joint offsets and parents
## (FighterSetupParts, KmdRelocate), the 18 local joint matrices of the pose, their copy of the
## previous frame and the blend deltas, and the world joints (24 blocks: 22 draw parts and two
## spare slots for weapon points).

const JOINTS := 18
const PARTS := 22
const JOINT_BLOCKS := 24

var model: CharacterModel
var offsets: Array[PackedInt32Array] = []
var parents := PackedInt32Array()
var present: Array[bool] = []             ## draw parts with a matrix
var attachments: AttachmentDynamics
var root_mat := Fx.identity()             ## +0xF54
var root := JointFrame.new()              ## +0x8B0
var joints: Array[JointFrame] = []        ## +0x8F4
## The joints as FighterComposeJoints built them. The parts are drawn from these (the second
## matrix of each block, +0x20, made while composing), so the weapon points CollisionShapesUpdate
## writes into the spare blocks afterwards do not move Mokujin's stick.
var draw_joints: Array[JointFrame] = []
## Part 18's draw flag (+0x7C0). FUN_800363B0 sets it every frame for Mokujin: his stick
## (attachment 18) shows only while he fights with Yoshimitsu's moves (bank type 4).
var stick_shown := true
var local_mats: Array[PackedInt32Array] = []       ## +0xF74 rotations (translations: offsets)
var prev_local_mats: Array[PackedInt32Array] = [] ## +0x13B0 slots 1–17
var blend_delta: Array[PackedInt32Array] = []      ## +0x15F0 slots 1–17
var attach_local: Array[PackedInt32Array] = []     ## +0x11B4 attachments' local rotations
var pose_vector := PackedInt32Array()     ## the decoded pose of the running frame (0x800A8AB0)
var decoded_root_dy := 0                  ## 0x800A8A52: the unscaled root dy of the running frame
var look_at := LookAt.new()               ## 0x8009E920 per player
var ogre_sway := 0                        ## +0x1294 True Ogre's sway counter
var gon_gaze := 0                         ## GonEyesFollow's look direction of Gon's eyes (−17 to 17), shown by the view


## The head look-at state of a player (animation.md#procedural-head-and-eyes).
class LookAt:
	var current := PackedInt32Array([0, 0, 0, 0])   ## +0: angles (x, y, z) and a spare word
	var target := PackedInt32Array([0, 0, 0, 0])    ## +8
	var active := 0                                 ## +0x10
	var snap := 1                                   ## +0x11
	var hold := 0                                   ## +0x12


func _init(character: CharacterModel, fighter_tables: FighterTables, pose_tables: PoseTables, solver: PoseSolver) -> void:
	model = character
	offsets = character.joint_offsets()
	parents = character.joint_parents()
	for i in PARTS:
		present.append(false)
	# FighterSetupPart: an attachment part (18–21) without a parent row has no matrix.
	for i in character.parts.size():
		var part := character.parts[i]
		if i < JOINTS or part.parent != -1:
			present[part.joint] = true
	attachments = AttachmentDynamics.new(fighter_tables, pose_tables, solver, character)
	for i in JOINT_BLOCKS:
		joints.append(JointFrame.new())
	draw_joints = joints.duplicate()
	for i in JOINTS:
		local_mats.append(Fx.identity())
	for i in JOINTS - 1:
		prev_local_mats.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
		blend_delta.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	for i in 4:
		attach_local.append(Fx.identity())


## A reload into the same record (FighterSetupParts on a loaded fighter) sets only the model's
## offsets and parents: the matrices the record holds stay as they were.
func keep_matrices(old: FighterBody) -> void:
	root_mat = old.root_mat.duplicate()
	root = JointFrame.new(old.root.rot.duplicate(), old.root.t.duplicate())
	for i in JOINT_BLOCKS:
		joints[i] = JointFrame.new(old.joints[i].rot.duplicate(), old.joints[i].t.duplicate())
		draw_joints[i] = JointFrame.new(old.draw_joints[i].rot.duplicate(), old.draw_joints[i].t.duplicate())
	for i in JOINTS:
		local_mats[i] = old.local_mats[i].duplicate()
	for i in JOINTS - 1:
		prev_local_mats[i] = old.prev_local_mats[i].duplicate()
		blend_delta[i] = old.blend_delta[i].duplicate()
	for i in attach_local.size():
		attach_local[i] = old.attach_local[i].duplicate()
	ogre_sway = old.ogre_sway
	gon_gaze = old.gon_gaze


func scale_base() -> int:
	return model.scale_fixed()
