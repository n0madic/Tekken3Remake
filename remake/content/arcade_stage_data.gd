class_name ArcadeStageData
extends RefCounted
## A stage's arcade version (stages/<letter>/arcade/, tools/remake_import/arcade.py): the
## polygonal scene, the tiled sky and the floor of the System 12 game, which the remake draws
## instead of the PlayStation's panorama when the Stage backdrops setting asks for them. See
## docs/research/arcade/stages.md.

const FILE := "arcade.json"
const FADE_FILE := "arcade_floor_fade.json"   ## in stages/, beside floor_fade.json
const SINE_FILE := "arcade_sine.json"          ## in stages/: the program's sine table (the props)

var directory: String
var scene: PackedFloat32Array          ## vertex_floats per corner (arcade.py's scene.bin)
var vertex_floats: int
var scene_texture: String
## The animated rectangle of the scene's atlas (stages 6 and 12, FUN_801E2114): x, y, w, h in
## atlas texels (empty: none), its frames' picture (one frame below the other), their count and
## the game frames each copy lasts.
var scene_animation_rect: PackedInt32Array
var scene_animation_texture: String
var scene_animation_frames: int
var scene_animation_period: int
var props_kind := ""                   ## ArcadeProps.CAROUSEL (stage 3), HELICOPTER (11) or none
var props_meshes: Array[PackedFloat32Array] = []   ## per prop, scene.bin's format about its origin
var scene_scale: float                 ## the scene is its TMD scaled by this about the fighters' midpoint …
var scene_y_scale: float               ## … and vertically by this too
var scene_height: int                  ## game units below the midpoint
var scene_extent: PackedInt32Array     ## min x, max x, min z, max z (scene units)
var sky: Dictionary = {}               ## arcade.json "sky" (stages.md#sky)
var floor_kind: int
var floor_shade: int
var floor_fade: int
var floor_tile_size: int
var floor_pattern: String
var floor_pattern_smooth: String


static func load_from(stage_dir: String) -> ArcadeStageData:
	var dir := stage_dir.path_join("arcade")
	if not FileAccess.file_exists(dir.path_join(FILE)):
		return null
	var data: Dictionary = JsonFile.read(dir.path_join(FILE))
	var a := ArcadeStageData.new()
	a.directory = dir
	a.vertex_floats = data.get("vertex_floats", 0)
	if a.vertex_floats <= 0:
		Log.warning("ArcadeStageData: %s: no vertex_floats; the PlayStation backdrop is drawn" % dir)
		return null
	a.scene_texture = data.get("scene_texture", "")
	a.scene_scale = JsonFile.number(data.get("scene_scale", 10))
	a.scene_y_scale = data.get("scene_y_scale", 1.0)
	a.scene_height = JsonFile.number(data.get("scene_height", 0))
	a.scene_extent = JsonFile.ints(data.get("scene_extent", [0, 0, 0, 0]))
	a.sky = data.get("sky", {})
	var animation: Variant = data.get("scene_animation")
	if animation is Dictionary:
		var d: Dictionary = animation
		a.scene_animation_frames = JsonFile.number(d.get("frames", 0))
		a.scene_animation_period = JsonFile.number(d.get("period", 1))
		# StageView.step divides by both: without them the scene stays as loaded.
		if a.scene_animation_frames > 0 and a.scene_animation_period > 0:
			a.scene_animation_rect = JsonFile.ints(d.get("rect", []))
			a.scene_animation_texture = d.get("texture", "")
		else:
			Log.warning("ArcadeStageData: %s: scene animation without frames or period" % dir)
	var floor: Dictionary = data.get("floor", {})
	a.floor_kind = JsonFile.number(floor.get("kind", 0))
	a.floor_shade = JsonFile.number(floor.get("shade", 0))
	a.floor_fade = JsonFile.number(floor.get("fade", 0))
	a.floor_tile_size = JsonFile.number(floor.get("tile_size", 2500))
	a.floor_pattern = floor.get("pattern", "")
	a.floor_pattern_smooth = floor.get("pattern_smooth", "")
	var props: Variant = data.get("props")
	if props is Dictionary:
		a.props_kind = (props as Dictionary).get("kind", "")
		for file: String in (props as Dictionary).get("meshes", []):
			a.props_meshes.append(FileAccess.get_file_as_bytes(dir.path_join(file)).to_float32_array())
	var mesh_path := dir.path_join("scene.bin")
	if FileAccess.file_exists(mesh_path):
		a.scene = FileAccess.get_file_as_bytes(mesh_path).to_float32_array()
	return a
