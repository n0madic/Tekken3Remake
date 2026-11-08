class_name ArcadeBody
extends FighterBody
## An arcade fighter's joints: the 18 of the pose, then the rows 18–23 of its model (hair, sashes, tails:
## `ArcadeAttachments`), which the hit segments and the weapon points read too. `view` is the same joints
## in the order of CharacterModel: the rows from CharacterModel.ARCADE_JOINT.

const FIRST_ROW := FighterBody.JOINTS
const ROWS := 6

var rows: ArcadeAttachments
var view: Array[JointFrame] = []
var _locals: Array[PackedInt32Array] = []


func _init(character: CharacterModel, fighter_tables: FighterTables, pose_tables: PoseTables, solver: PoseSolver,
		tables: ArcadeAttachmentTables) -> void:
	super(character, fighter_tables, pose_tables, solver)
	rows = ArcadeAttachments.new(character, tables)
	for j in CharacterModel.JOINT_COUNT:
		view.append(JointFrame.new())
	for i in ROWS:
		_locals.append(Fx.identity())


## The frame's skeleton is composed: the rows still hold the last frame's, with the weapon points.
func begin_rows() -> void:
	view = view.duplicate()
	for j in FighterBody.JOINTS:
		view[j] = joints[j]
	for i in ROWS:
		view[CharacterModel.ARCADE_JOINT + i] = joints[FIRST_ROW + i]


## FUN_8019B6D8: the attachment's local rotation; a frame that does not `move` keeps the last one's.
func row_local(a: CharacterModel.ArcadeAttachment, moves: bool) -> PackedInt32Array:
	var i := a.joint - CharacterModel.ARCADE_JOINT
	if moves:
		_locals[i] = rows.local_of(a, view[a.joint], row_offset(a), view)
	return _locals[i]


static func row_offset(a: CharacterModel.ArcadeAttachment) -> PackedInt32Array:
	return PackedInt32Array([a.offset.x, a.offset.y, -a.offset.z])


func compose_row(a: CharacterModel.ArcadeAttachment, local: PackedInt32Array, offset: PackedInt32Array) -> void:
	view[a.joint] = JointFrame.compose_offset(view[a.parent], local, offset)
	joints[FIRST_ROW + a.joint - CharacterModel.ARCADE_JOINT] = view[a.joint]


func view_joints() -> Array[JointFrame]:
	return view
