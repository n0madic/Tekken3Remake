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
## Everything that is not the stage (fighters, effects, the ball, the items) lies within this
## distance of the camera, in metres.
const DYNAMIC_RANGE := 100.0


## The include's constant `name`.
func _constant(name: String) -> float:
	var regex := RegEx.create_from_string("const float " + name + " = ([0-9.e+-]+);")
	var found := regex.search(FileAccess.get_file_as_string(INCLUDE))
	expect(found != null, name + " is declared in the include")
	return found.get_string(1).to_float() if found != null else NAN


## The reversed depth (1 at the near plane, 0 at the far plane) of a point `z` metres ahead.
func _depth_at(z: float) -> float:
	return CameraRig.NEAR * (CameraRig.FAR - z) / (z * (CameraRig.FAR - CameraRig.NEAR))


func test_band_is_inside_the_depth_range() -> void:
	var base := _constant("STAGE_DEPTH_BASE")
	var span := _constant("STAGE_DEPTH_SPAN")
	expect(base > 0.0 and span > 0.0 and base + span < 1.0, "a thin band strictly inside 0..1")
	expect(_depth_at(CameraRig.NEAR) > 0.99, "the depth helper is reversed, near = 1")


func test_band_lies_behind_everything_dynamic() -> void:
	var top := _constant("STAGE_DEPTH_BASE") + _constant("STAGE_DEPTH_SPAN")
	expect(_depth_at(DYNAMIC_RANGE) > top, "a point %d m ahead is nearer than the whole stage" % int(DYNAMIC_RANGE))
	expect(_depth_at(1.0) > top, "so is one at the fighters' distance")


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
	expect(include.contains("DEPTH = STAGE_DEPTH_BASE"), "its fragment write is the band's")
	expect(include.contains("POSITION.z = POSITION.z * STAGE_DEPTH_SPAN"), "theirs shifts the clip-space depth")
