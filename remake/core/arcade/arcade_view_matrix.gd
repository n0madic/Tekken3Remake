class_name ArcadeViewMatrix
extends ViewMatrix
## The arcade's view (FUN_801A26A4): the same matrix as the PlayStation's for a 512 × 240 display, whose
## rows are scaled by 0x980 / 4096, and the GTE's screen offset of that display (FUN_801BB838).

const ARCADE_ASPECT := 0x980
const ARCADE_OFFSET_X := 256
const ARCADE_OFFSET_Y := 120


static func build_arcade(view: CameraView, tables: FightTables) -> ArcadeViewMatrix:
	var m := ArcadeViewMatrix.new()
	m._fill(view, tables, ARCADE_ASPECT)
	return m


func _rtps(tr: PackedInt32Array) -> PackedInt32Array:
	return Gte.rtps_origin(tr, h, ARCADE_OFFSET_X, ARCADE_OFFSET_Y)
