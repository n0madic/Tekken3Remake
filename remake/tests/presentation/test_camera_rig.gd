extends TestSuite
## CameraRig shows the simulation's camera: built from the reel's pitch and yaw, the Godot
## camera looks from the eye at the reel's target; wide windows extend sideways up to 21:9 and
## tall ones upwards as far as the stage's coverage allows and downwards over the floor.



func test_the_view_looks_at_the_reel_target() -> void:
	if not require(AssetCatalog.ROOT.path_join("enbu/enbu.json")):
		return
	var reel := EnbuAssets.load_from(AssetCatalog.ROOT).reel()
	reel.start()
	var worst := 0.0
	for n in 400:
		var sample := reel.sample
		var view := reel.step(500)
		var target := WorldSpace.point(CameraReel._half(sample[3]), CameraReel._half(sample[4]), CameraReel._half(sample[5]))
		var eye := WorldSpace.point(view.x, view.y, view.z)
		var basis := CameraRig.view_basis(view.pitch * TAU / 4096.0, view.yaw * TAU / 4096.0)
		var forward := -basis.z
		var angle := forward.angle_to((target - eye).normalized())
		worst = maxf(worst, angle)
	expect(worst < deg_to_rad(0.5), "the camera looks at the target (worst %.3f°)" % rad_to_deg(worst))


func test_wide_and_tall_windows() -> void:
	var rig := CameraRig.new()
	rig._ready()
	rig.set_view(CameraView.new(0, 0, 0, -1000, -3000, 500), true)
	rig.place(1.0, Vector2(1600, 1200))
	expect_equal(rig.visible_rect, Rect2(0, 0, 1, 1), "4:3 fills the window")
	rig.place(1.0, Vector2(3440, 1440))
	expect(rig.visible_rect.size.x < 1.0 and is_equal_approx(rig.visible_rect.size.x * 3440.0 / 1440.0, 21.0 / 9.0),
		"beyond 21:9 the sides are framed: %s" % rig.visible_rect)
	rig.place(1.0, Vector2(1080, 1920))
	expect_equal(rig.visible_rect, Rect2(0, 0, 1, 1), "a tall window is always filled")
	expect(is_equal_approx(rig.frame_rect.get_center().y, 0.5), "without coverage data it extends evenly: %s" % rig.frame_rect)
	rig.coverage = PackedInt32Array([20])
	rig.place(1.0, Vector2(1080, 1920))
	expect(rig.frame_rect.get_center().y < 0.5, "a backdrop that ends 20° up moves the 4:3 frame up: %s" % rig.frame_rect)
	expect(is_equal_approx(rig.frame_rect.size.x, 1.0), "the 4:3 frame spans the width: %s" % rig.frame_rect)
	rig.camera.free()
	rig.free()


## Every stream of the reel starts with a cut, and only there: the rig must not interpolate
## across two shots.
func test_the_reel_marks_its_cuts() -> void:
	if not require(AssetCatalog.ROOT.path_join("enbu/enbu.json")):
		return
	var reel := EnbuAssets.load_from(AssetCatalog.ROOT).reel()
	reel.start()
	var cuts := 0
	var steps := 0
	while not reel.finished():
		var starts := reel.next_frame == 1
		var view := reel.step(500)
		expect_equal(view.cut, starts, "step %d" % steps)
		if view.cut:
			cuts += 1
		steps += 1
	expect_equal(cuts, reel.streams.size(), "one cut per stream")
	var rig := CameraRig.new()
	rig._ready()
	rig.set_view(CameraView.new(0, 0, 0, 0, 0, 500))
	rig.set_view(CameraView.new(1024, 0, 5000, 0, 0, 500), true)
	rig.place(0.5, Vector2(1600, 1200))
	expect(rig.camera.position.is_equal_approx(WorldSpace.point(5000, 0, 0)), "a cut is not interpolated: %s" % rig.camera.position)
	rig.camera.free()
	rig.free()


## The coverage direction the rig reads is the one the camera faces, in the converter's
## convention (direction k along the game's (cos θ, −sin θ) in x and z, θ = k·360°/count).
func test_coverage_follows_the_view_direction() -> void:
	if not require(AssetCatalog.ROOT.path_join("enbu/enbu.json")):
		return
	const COUNT := 72
	var reel := EnbuAssets.load_from(AssetCatalog.ROOT).reel()
	reel.start()
	var wrong := 0
	for n in 1000:
		var sample := reel.sample
		var view := reel.step(500)
		var dx := CameraReel._half(sample[3]) - view.x
		var dz := CameraReel._half(sample[5]) - view.z
		if dx * dx + dz * dz < 100 * 100:
			continue
		var theta := fposmod(atan2(-float(dz), float(dx)), TAU)
		var expected := roundi(theta / TAU * COUNT) % COUNT
		var got := CameraRig.coverage_index(view.yaw * TAU / 4096.0, COUNT)
		if mini(posmod(got - expected, COUNT), posmod(expected - got, COUNT)) > 1:
			wrong += 1
	expect_equal(wrong, 0, "views whose coverage direction is not the one they face")
	# Only the faced direction's low backdrop limits a tall window.
	var rig := CameraRig.new()
	rig._ready()
	var coverage := PackedInt32Array()
	coverage.resize(COUNT)
	coverage.fill(90)
	coverage[CameraRig.coverage_index(0.0, COUNT)] = 20
	rig.coverage = coverage
	rig.set_view(CameraView.new(0, 0, 0, -1000, -3000, 500), true)
	rig.place(1.0, Vector2(1080, 1920))
	expect(rig.frame_rect.get_center().y < 0.5, "facing the low backdrop limits the upward extension: %s" % rig.frame_rect)
	rig.set_view(CameraView.new(0, 2048, 0, -1000, -3000, 500), true)
	rig.place(1.0, Vector2(1080, 1920))
	expect(is_equal_approx(rig.frame_rect.get_center().y, 0.5), "facing away it does not: %s" % rig.frame_rect)
	# A low direction 15° to the side is still inside the view: it limits the extension too.
	coverage.fill(90)
	coverage[(CameraRig.coverage_index(0.0, COUNT) + 3) % COUNT] = 20
	rig.set_view(CameraView.new(0, 0, 0, -1000, -3000, 500), true)
	rig.place(1.0, Vector2(1080, 1920))
	expect(rig.frame_rect.get_center().y < 0.5, "a low backdrop at the side limits it: %s" % rig.frame_rect)
	# Turning the camera by small steps moves the frame by small steps (no jumps between
	# the stage's 5° directions).
	for k in COUNT:
		coverage[k] = roundi(25.0 + 10.0 * sin(3.0 * k * TAU / COUNT))
	var worst := 0.0
	var last := -1.0
	for step in 400:
		rig.set_view(CameraView.new(0, step, 0, -1000, -3000, 500), true)
		rig.place(1.0, Vector2(1080, 1920))
		var y := rig.frame_rect.position.y
		if last >= 0.0:
			worst = maxf(worst, absf(y - last))
		last = y
	expect(worst < 0.01, "the frame moves smoothly while the camera turns (largest step %.4f)" % worst)
	rig.camera.free()
	rig.free()
