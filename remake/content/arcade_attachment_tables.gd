class_name ArcadeAttachmentTables
extends RefCounted
## What the arcade's attachments read: the Euler conversion and the arithmetic tables of the fight's
## data, the axis records (0x801FD170: six signed bytes each) and the clamps (0x801FD2F0).

const FILE := "characters/arcade_attachments.json"

static var _shared: ArcadeAttachmentTables

var solver: PoseSolver
var fighter: FighterTables
var limits: Array[PackedInt32Array] = []
var clamps := PackedInt32Array()


static func load_from(path: String, pose_solver: PoseSolver, fighter_tables: FighterTables) -> ArcadeAttachmentTables:
	var out := ArcadeAttachmentTables.new()
	out.solver = pose_solver
	out.fighter = fighter_tables
	var data: Dictionary = JsonFile.read(path)
	for record: Array in data.get("limits", []):
		out.limits.append(JsonFile.ints(record))
	out.clamps = JsonFile.ints(data.get("clamps", []))
	return out


## The converted tables, for a PlayStation fight that shows arcade models.
static func shared() -> ArcadeAttachmentTables:
	if _shared == null:
		_shared = load_from(Assets.path(FILE), PoseSolver.new(PoseTables.load_from(Assets.path("tables/pose.json"))),
			FighterTables.load_from(Assets.path("tables/fighter.json")))
	return _shared
