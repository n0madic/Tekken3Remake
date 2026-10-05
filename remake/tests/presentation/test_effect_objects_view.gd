extends TestSuite
## EffectObjectsView takes the converted effect objects (effects.json "objects") once in setup:
## every model's corners (model 0 has none), the models' own sprites and the UV tables' frames,
## as the pool is drawn from them each step.


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
