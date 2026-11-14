extends TestSuite
## The stage's depth band (stage_depth.gdshaderinc): the floor, the panorama and the arcade scene
## are drawn behind everything else, as the game's farthest ordering-table entries, so a body
## lying partly under the floor is not cut by it.

const INCLUDE := "res://presentation/stage/stage_depth.gdshaderinc"
const STAGE_SHADERS := [
	"res://presentation/stage/floor.gdshader",
	"res://presentation/stage/panorama.gdshader",
	"res://presentation/stage/arcade_scene.gdshader",
]
## The depth step of a 24-bit buffer.
const STEP_24_BIT := 1.0 / 16777216.0


## The include's constant `name`.
func _constant(name: String) -> float:
	var regex := RegEx.create_from_string("const float " + name + " = ([0-9.e+-]+);")
	var found := regex.search(FileAccess.get_file_as_string(INCLUDE))
	expect(found != null, name + " is declared in the include")
	return found.get_string(1).to_float() if found != null else NAN


## The reversed depth (1 at the near plane, 0 at the far plane) of a point `z` metres ahead.
func _depth_at(z: float) -> float:
	return CameraRig.NEAR * (CameraRig.FAR - z) / (z * (CameraRig.FAR - CameraRig.NEAR))


## The depth the band gives a stage point `z` metres ahead: the one STAGE_DEPTH_NEAR ahead at its top.
func _band_depth(z: float) -> float:
	return _constant("STAGE_DEPTH_BASE") + _constant("STAGE_DEPTH_SPAN") * _depth_at(z) / _depth_at(_constant("STAGE_DEPTH_NEAR"))


func test_band_is_inside_the_depth_range() -> void:
	var base := _constant("STAGE_DEPTH_BASE")
	var span := _constant("STAGE_DEPTH_SPAN")
	expect(base > 0.0 and span > 0.0 and base + span < 1.0, "a thin band strictly inside 0..1")
	expect(_depth_at(CameraRig.NEAR) > 0.99, "the depth helper is reversed, near = 1")


func test_band_lies_behind_everything_dynamic() -> void:
	# Everything that is not the stage (fighters, effects, the ball, the items) lies within the
	# include's STAGE_DEPTH_RANGE of the camera, in metres.
	var top := _constant("STAGE_DEPTH_BASE") + _constant("STAGE_DEPTH_SPAN")
	var range_m := _constant("STAGE_DEPTH_RANGE")
	expect(_depth_at(range_m) > top, "a point %d m ahead is nearer than the whole stage" % int(range_m))
	expect(_depth_at(1.0) > top, "so is one at the fighters' distance")
	expect(range_m >= 32.768 + 5.0, "the ordering table's last entry (32.8 m) and the biases beyond it are within")


## What the squeeze costs a 24-bit depth buffer (the Mobile renderer on Android GPUs, the web):
## the distance one step of it covers inside the band. The arcade scene's eaves, pillars and
## balustrades, 10 to 60 m away, z-fought when the band held the depths from the near plane.
func test_band_keeps_the_stage_resolved_on_a_24_bit_buffer() -> void:
	var span := _constant("STAGE_DEPTH_SPAN")
	var scale := span / _depth_at(_constant("STAGE_DEPTH_NEAR"))
	for case: Array in [[3.0, 0.001], [10.0, 0.005], [30.0, 0.02], [60.0, 0.08]]:
		var z: float = case[0]
		var limit: float = case[1]
		# d(z) = near (far − z) / (z (far − near)), so a step of the band is a depth step of
		# STEP / scale, which covers z² (far − near) / (near · far) times that many metres.
		var step := STEP_24_BIT / scale * z * z * (CameraRig.FAR - CameraRig.NEAR) / (CameraRig.NEAR * CameraRig.FAR)
		expect(step <= limit, "at %d m one step covers %.4f m, at most %.3f" % [int(z), step, limit])


func test_a_nearer_stage_surface_stays_behind_what_lies_beyond_it() -> void:
	var near := _constant("STAGE_DEPTH_NEAR")
	var top := _constant("STAGE_DEPTH_BASE") + _constant("STAGE_DEPTH_SPAN")
	expect(is_equal_approx(_band_depth(near), top), "the band's top is the depth STAGE_DEPTH_NEAR ahead")
	expect(_band_depth(CameraRig.FAR) < _band_depth(near), "farther stage surfaces lie lower in the band")
	# A surface nearer than that rises above the band, but anything 12 times as far is in front of it.
	for z: float in [CameraRig.NEAR * 1.2, 0.2, 0.5, 1.4, 3.0, near]:
		expect(_band_depth(z) < _depth_at(12.0 * z), "a stage surface %.2f m ahead lies behind a body %.1f m ahead" % [z, 12.0 * z])
	# The arcade scene's nearest seen (stage 5's opening) leaves the fighters in front of it.
	expect(_band_depth(1.4) < _depth_at(10.0), "the arcade scene at 1.4 m lies behind a fighter 10 m ahead")


func test_backdrop_quad_lies_behind_the_band() -> void:
	var backdrop := _depth_at(CameraRig.FAR * FightView.BACKDROP_DEPTH)
	expect(backdrop < _constant("STAGE_DEPTH_BASE"), "the tile-map stages' backdrop is behind the floor")


func test_stage_shaders_use_the_band() -> void:
	for path: String in STAGE_SHADERS:
		var code := (load(path) as Shader).code
		expect(code.contains("#include \"" + INCLUDE + "\""), path + " includes the band")
		expect(code.contains("STAGE_DEPTH_VERTEX"), path + " shifts its vertices")
		expect(code.contains("STAGE_DEPTH_FRAGMENT"), path + " has the Compatibility renderer's fragment write")


func test_compatibility_writes_the_depth_from_the_fragment() -> void:
	var include := FileAccess.get_file_as_string(INCLUDE)
	expect(include.contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"),
		"Compatibility has no depth pre-pass: it writes DEPTH, the others shift the vertices")
	expect(include.contains("? STAGE_DEPTH_BASE + FRAGCOORD.z * stage_depth_scale(PROJECTION_MATRIX) : FRAGCOORD.z;"), "its fragment write is the band's")
	expect(include.contains("POSITION.z = POSITION.z * stage_depth_scale(PROJECTION_MATRIX)"), "theirs shifts the clip-space depth")
	expect(include.contains("return STAGE_DEPTH_SPAN / (0.5 * c.z / c.w + 0.5);"),
		"OpenGL's clip depth (−1..1) is taken to the window's (0..1) for the band's top")


func test_only_the_cameras_perspective_pass_is_shifted() -> void:
	var include := FileAccess.get_file_as_string(INCLUDE)
	expect(include.count("PROJECTION_MATRIX[3][3] == 0.0") == 2, "both paths leave the orthographic shadow passes alone")
	expect(include.contains("POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); if ("),
		"POSITION is written first on every path")
