class_name StageData
extends RefCounted
## A converted stage: the panorama mesh (objects on the 6 × 6 grid), its atlas and the
## floor pattern. See docs/research/code/stages.md.

const BASE_NEUTRAL := 128           ## the vertex colour that leaves a texel unchanged (0x80)

var number: int
var letter: String
var directory: String
var cell: int
var panorama_height: int
var floor_kind: int
var floor_shade: int               ## kind 0's distance shading factor (FloorDrawGrid; 0: none)
var floor_fade: int                ## the distance the shading table spans (game units)
var floor_tile_size: int
var floor_tiles: Array[Dictionary] = []
var floor_pattern: String          ## the 10 × 10 pattern as drawn by the game
var floor_pattern_smooth: String   ## the same with the tile seams smoothed
var vertex_floats: int
var panorama_extent: PackedInt32Array   ## min x, max x, min z, max z of the panorama objects
var panorama: PackedFloat32Array
## Tekken Ball's and Tekken Force's stages have a screen-space tile map instead of a panorama:
## picture, tile (pixels), width and height (cells).
var tile_map: Dictionary = {}
## Tekken Force's item pictures (the levels with items): "picture" and "shadow" file names.
var item: Dictionary = {}
## The light rig (stages.md#lighting): back colour level, the fighters' base colour (their vertex
## colours start from it; 0x80 = 1 per channel), main light colour and direction (4096-unit pitch
## and yaw). `ambient` is the back colour's level in bytes (SetBackColor's argument) and
## `ambient_level` the record's word it comes from, in GTE units of 4096 (`ambient << 4` plus the
## low bits the flash ramp still sees).
var ambient: int
var ambient_level: int
var base_colour := Vector3.ONE
var light_colour: Color
var light_pitch: int
var light_yaw: int
## View coverage: per direction around +x (counter-clockwise from above) the highest elevation
## in degrees the backdrop covers without gaps, seen from `coverage_eye`.
var coverage: PackedInt32Array
var coverage_eye: PackedInt32Array
## The arcade version of the stage (converted with --arcade), or null.
var arcade: ArcadeStageData


static func load_from(dir: String) -> StageData:
	var data: Dictionary = JsonFile.read(dir + "/stage.json")
	var s := StageData.new()
	s.directory = dir
	s.number = data.get("stage", -1)
	s.letter = data.get("letter", "")
	s.cell = data.get("cell", 0)
	s.panorama_height = data.get("panorama_height", 0)
	s.floor_kind = data.get("floor_kind", 0)
	s.floor_shade = JsonFile.number(data.get("floor_shade", 0))
	s.floor_fade = JsonFile.number(data.get("floor_fade", 0))
	s.floor_tile_size = data.get("floor_tile_size", 1800)
	for tile: Dictionary in data.get("floor_tiles", []):
		s.floor_tiles.append(tile)
	s.floor_pattern = data.get("floor_pattern", "")
	s.floor_pattern_smooth = data.get("floor_pattern_smooth", "")
	s.vertex_floats = data.get("vertex_floats", 0)
	s.panorama_extent = JsonFile.ints(data.get("panorama_extent", [0, 0, 0, 0]))
	if FileAccess.file_exists(dir + "/panorama.bin"):
		s.panorama = FileAccess.get_file_as_bytes(dir + "/panorama.bin").to_float32_array()
	s.tile_map = data.get("tile_map", {})
	s.item = data.get("item", {})
	var light: Dictionary = data.get("lighting", {})
	s.ambient = light.get("ambient", 128)
	s.ambient_level = light.get("ambient_level", s.ambient << 4)
	var base := JsonFile.ints(light.get("base_rgb", [BASE_NEUTRAL, BASE_NEUTRAL, BASE_NEUTRAL]))
	s.base_colour = Vector3(base[0], base[1], base[2]) / BASE_NEUTRAL
	s.light_colour = _colour(light.get("light_rgb", [200, 200, 200]))
	s.light_pitch = light.get("light_pitch", 512)
	s.light_yaw = light.get("light_yaw", 2560)
	var cover: Dictionary = data.get("coverage", {})
	s.coverage = JsonFile.ints(cover.get("elevation", []))
	s.coverage_eye = JsonFile.ints(cover.get("eye", [0, 0, 0]))
	s.arcade = ArcadeStageData.load_from(dir)
	return s


static func _colour(value: Variant) -> Color:
	var c := JsonFile.ints(value)
	return Color8(c[0], c[1], c[2])
