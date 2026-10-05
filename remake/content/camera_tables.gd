class_name CameraTables
extends RefCounted
## Constant tables of the camera code, converted from the game executable
## (`imported/tables/camera.json`, camera.md): the octant table of `Atan2Units4096` and the
## director's presets, choice lists, hit cameras, round intro offsets and winner camera choices.

## A hit camera script (camera.md#hit-cameras).
class HitScript:
	var kind := -1                ## 0 preset-style framing, 1 contact-point view, −1 none
	var frames := 0
	var blend_in := 0
	var blend_out := 0
	var start_distance := 0
	var end_distance := 0
	var pitches := PackedInt32Array()          ## pitch offsets (<< 6: 18-bit angles)
	var yaws := PackedInt32Array()

var atan_table: PackedInt32Array
var presets: Array[PackedInt32Array] = []      ## blend in, blend out, pitch offsets[4], yaw offsets[4]
var outside_blend_out := 0                     ## the word FUN_80067C8C reads for non-preset scripts
var preset_index := PackedInt32Array()         ## preset index + 1 per preset script value
var choices: Array[PackedInt32Array] = []      ## EXE choice list: (kind, weight, script)
var hit_rows: Array[PackedInt32Array] = []     ## (bank type, move slot, list id)
var hit_lists: Array = []                      ## per list id − 300: records (cumulative weight out of 0x1000, script per rating ×4)
var hit_scripts: Array[HitScript] = []
var intro_offsets: Array[PackedInt32Array] = []
var intro_offset_ball := PackedInt32Array()
var attract_styles := PackedInt32Array()        ## the demonstration camera's styles (FUN_800693E8)
var attract_pitches := PackedInt32Array()       ## the circling camera's pitches (FUN_80068E90)
var attract_speeds := PackedInt32Array()        ## its yaw steps
var winner_lateral := PackedInt32Array()
var winner_forward := PackedInt32Array()
var winner_height := PackedInt32Array()


static func load_from(path: String) -> CameraTables:
	var data: Dictionary = JsonFile.read(path)
	var t := CameraTables.new()
	t.atan_table = JsonFile.ints(data["atan"])
	for row: Array in data.get("presets", []):
		t.presets.append(JsonFile.ints(row))
	t.preset_index = JsonFile.ints(data.get("preset_index", []))
	t.outside_blend_out = JsonFile.number(data.get("outside_blend_out", 0))
	for row: Array in data.get("choices", []):
		t.choices.append(JsonFile.ints(row))
	for row: Array in data.get("hit_rows", []):
		t.hit_rows.append(JsonFile.ints(row))
	for records: Array in data.get("hit_lists", []):
		var list: Array[PackedInt32Array] = []
		for record: Array in records:
			list.append(JsonFile.ints(record))
		t.hit_lists.append(list)
	for words: Array in data.get("hit_scripts", []):
		var w := JsonFile.ints(words)
		var s := HitScript.new()
		s.kind = w[0]
		s.frames = w[1]
		s.blend_in = w[2]
		s.blend_out = w[3]
		s.start_distance = w[4]
		s.end_distance = w[5]
		s.pitches = w.slice(6, 10)
		s.yaws = w.slice(10, 14)
		t.hit_scripts.append(s)
	for row: Array in data.get("intro_offsets", []):
		t.intro_offsets.append(JsonFile.ints(row))
	t.intro_offset_ball = JsonFile.ints(data.get("intro_offset_ball", [0, 0, 0]))
	t.attract_styles = JsonFile.ints(data.get("attract_styles", []))
	t.attract_pitches = JsonFile.ints(data.get("attract_pitches", []))
	t.attract_speeds = JsonFile.ints(data.get("attract_speeds", []))
	t.winner_lateral = JsonFile.ints(data.get("winner_lateral", []))
	t.winner_forward = JsonFile.ints(data.get("winner_forward", []))
	t.winner_height = JsonFile.ints(data.get("winner_height", []))
	return t
