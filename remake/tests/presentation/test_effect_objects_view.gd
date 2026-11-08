extends TestSuite
## EffectObjectsView takes the converted effect objects (effects.json "objects") once in setup:
## every model's corners (model 0 has none), the models' own sprites and the UV tables' frames,
## as the pool is drawn from them each step.

const DISC_DATA := [
	"test_setup_reads_the_converted_objects",
]


func test_setup_reads_the_converted_objects() -> void:
	var dir := AssetCatalog.ROOT.path_join("effects")
	if not require(dir.path_join("effects.json")):
		return
	var data := EffectData.load_from(dir)
	var view := EffectObjectsView.new()
	view.setup(data)
	var quads: Array = data.objects.get("quads", [])
	expect_equal(view.quad_corners.size(), quads.size(), "a corner pair per model")
	expect_equal(view.corners(0), Color(), "model 0 has no quad")
	var m := 1.0 / WorldSpace.UNITS_PER_METRE
	for model in range(1, quads.size()):
		var q: Array = quads[model]
		var a := JsonFile.ints(q[0])
		var b := JsonFile.ints(q[3])
		expect_equal(view.corners(model), Color(a[0] * m, a[1] * m, b[0] * m, b[1] * m), "model %d corners" % model)
	var tables: Array = data.objects.get("uv_tables", [])
	expect_equal(view.uv_frames.size(), tables.size(), "a frame list per UV table")
	for t in tables.size():
		var table: Dictionary = tables[t]
		var frames: Array = table["frames"]
		var first := JsonFile.ints(frames[0])
		var o := EffectObjects.Obj.new()
		o.uv_table = t + 1
		o.uv = frames.size() + 5
		var last := JsonFile.ints(frames[frames.size() - 1])
		expect_equal(view.sprite_of(o), PackedInt32Array([last[0], last[1], JsonFile.number(table["size"])]),
				"table %d: a frame past the end draws the last" % (t + 1))
		o.uv = 0
		expect_equal(view.sprite_of(o)[0], first[0], "table %d: frame 0" % (t + 1))
	view.show_pool(EffectPool.new())
	view.free()


## The texel of a frame at `uv` as effect_object.gdshaderinc's texel_colour() takes it (one axis).
static func _texel(origin: int, size: int, uv: float) -> int:
	return floori(origin + clampf(uv * size, 0.0, size - 0.001))


## A pixel on the quad's edge is shaded at its centre, which MSAA can leave outside the quad: `uv`
## a little below 0 or above 1. The texel must stay in the frame on both sides (issue
## n0madic/Tekken3Remake#24: the top and left edges read the page's row and column before the
## frame, white in the fire's palette, as thin lines on the flames).
func test_an_edge_pixel_stays_inside_its_frame() -> void:
	for uv: float in [-0.5, -0.02, -0.0001, 0.0, 0.5, 0.9999, 1.0, 1.02, 1.5]:
		var texel := _texel(160, 32, uv)
		expect(texel >= 160 and texel <= 191, "uv %s reads texel %d of the frame 160..191" % [uv, texel])
	expect_equal(_texel(160, 32, -0.02), 160, "below the frame: its first texel")
	expect_equal(_texel(160, 32, 1.02), 191, "above the frame: its last texel")


func test_shader_holds_the_texel_inside_the_frame() -> void:
	var code := FileAccess.get_file_as_string("res://presentation/effects/effect_object.gdshaderinc")
	expect(code.contains("floor(sprite.xy + clamp(uv * sprite.z, vec2(0.0), vec2(sprite.z - 0.001)))"), "clamped on both sides")
