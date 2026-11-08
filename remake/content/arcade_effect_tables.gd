class_name ArcadeEffectTables
extends RefCounted
## The arcade effect objects' tables (`imported/tables/effects.json`, tools/remake_import/arcade_effect_tables.py).

var sin_table := PackedInt32Array()         ## per 4096-unit angle, 0x7FFF scale (0x8017CB78)
var cos_table := PackedInt32Array()
var atan_table := PackedInt32Array()        ## 0x80184B78
var angle_base := PackedInt32Array()        ## per octant (0x8017C498)
var angle_sign := PackedInt32Array()        ## per octant: non-zero mirrors the arctangent (0x8017C4A8)
var breath_offsets: Array[Array] = []       ## per fighter: two (x, y, z) from the head joint
var cloud_offsets: Array[PackedInt32Array] = []
var burn_joints := PackedInt32Array()
var glow_joints := PackedInt32Array()       ## per attack joint: the joint that glows (0: none)
var segment_fireball := PackedInt32Array()  ## per burst frame: 0 ends the hit segment
var segment_cloud := PackedInt32Array()     ## per cloud frame


static func load_from(path: String) -> ArcadeEffectTables:
	var d: Dictionary = JsonFile.read(path)
	var t := ArcadeEffectTables.new()
	t.sin_table = JsonFile.ints(d["sin"])
	t.cos_table = JsonFile.ints(d["cos"])
	t.atan_table = JsonFile.ints(d["atan"])
	t.angle_base = JsonFile.ints(d["angle_base"])
	t.angle_sign = JsonFile.ints(d["angle_sign"])
	for points: Array in d["breath_offsets"]:
		t.breath_offsets.append(FightTables._rows(points))
	t.cloud_offsets = FightTables._rows(d["cloud_offsets"])
	t.burn_joints = JsonFile.ints(d["burn_joints"])
	t.glow_joints = JsonFile.ints(d["glow_joints"])
	t.segment_fireball = JsonFile.ints(d["segment_fireball"])
	t.segment_cloud = JsonFile.ints(d["segment_cloud"])
	return t
