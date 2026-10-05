class_name EnbuAssets
extends RefCounted
## Everything the attract demonstrations need, loaded from the converted assets: the
## demonstrations' bank with the common bank, the tables and the camera reel once, and the
## models of each demonstration's costume slots when that demonstration is first played.

const COMMON_BANK := "divmot99"

var root: String
var data: EnbuData
var motions: MotionSet
var fighter_tables: FighterTables
var pose_tables: PoseTables
var camera_tables: CameraTables
var _models: Dictionary = {}         ## demonstration → (costume slot → CharacterModel)


## `folder` is the asset folder (res://imported/).
static func load_from(folder: String) -> EnbuAssets:
	var a := EnbuAssets.new()
	a.root = folder
	a.data = EnbuData.load_from(folder.path_join("enbu/enbu.json"))
	var own := MotionBank.load_named(folder.path_join("motion"), a.data.bank)
	var common := MotionBank.load_named(folder.path_join("motion"), COMMON_BANK)
	a.motions = MotionSet.new(own, common)
	a.fighter_tables = FighterTables.load_from(folder.path_join("tables/fighter.json"))
	a.pose_tables = PoseTables.load_from(folder.path_join("tables/pose.json"))
	a.camera_tables = CameraTables.load_from(folder.path_join("tables/camera.json"))
	return a


func demo(number: int) -> EnbuData.Demo:
	return data.demos[number]


## The models of demonstration `number` by costume slot (loaded once).
func models(number: int) -> Dictionary:
	if not _models.has(number):
		var loaded: Dictionary = {}
		var names := demo(number).models
		for slot: int in names:
			loaded[slot] = CharacterModel.load_from(root.path_join("characters/" + str(names[slot])))
		_models[number] = loaded
	return _models[number]


func reel() -> CameraReel:
	return CameraReel.new(motions.own, data.camera_reel, camera_tables)


func performance(number: int) -> EnbuPerformance:
	return EnbuPerformance.new(demo(number), motions, fighter_tables, pose_tables, models(number), reel())
