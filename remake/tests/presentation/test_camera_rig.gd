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


## A sky laid out on the screen (the arcade's) tells the rig how far up it covers, for the view's
## pitch, in place of the coverage; the rest of a tall window extends downwards.
func test_a_screen_sky_limits_a_tall_window() -> void:
	var rig := CameraRig.new()
	rig._ready()
	rig.set_view(CameraView.new(200, 0, 0, -1000, -3000, 500), true)
	rig.coverage = PackedInt32Array([90])
	var pitches: Array[float] = []
	rig.sky_cover = func(pitch: float, frame_half_tan: float) -> float:
		pitches.append(pitch)
		return frame_half_tan * 1.25
	rig.place(1.0, Vector2(1080, 1920))
	expect(pitches.size() == 1 and is_equal_approx(pitches[0], WorldSpace.radians(200)), "it gets the view's pitch: %s" % [pitches])
	var up := rig.frame_tan.x * 1920.0 / 1080.0 + rig.camera.frustum_offset.y / CameraRig.NEAR
	expect(is_equal_approx(up, rig.frame_tan.y * 1.25), "up to where it covers, not the coverage's: %f" % up)
	expect(rig.frame_rect.position.y > 0.0 and rig.frame_rect.get_center().y < 0.5, "the 4:3 frame near the top: %s" % rig.frame_rect)
	rig.sky_cover = func(_pitch: float, _frame_half_tan: float) -> float: return INF
	rig.place(1.0, Vector2(1080, 1920))
	expect(is_equal_approx(rig.frame_rect.get_center().y, 0.5), "a sky that covers every view extends evenly: %s" % rig.frame_rect)
	rig.camera.free()
	rig.free()


## The arcade's frame is 512 by 240 rows of 0x980/4096: not 4:3 in the world, 4:3 on the monitor.
func test_the_arcade_frames_2d_at_the_monitors_shape() -> void:
	var rig := CameraRig.new()
	rig._ready()
	var view := CameraView.new(0, 0, 0, -1000, -3000, 500)
	view.half_width = ArcadeCamera.ARCADE_HALF_WIDTH
	view.half_height = ArcadeCamera.ARCADE_HALF_HEIGHT
	rig.set_view(view, true)
	rig.place(1.0, Vector2(960, 720))
	expect(rig.frame_rect.is_equal_approx(Rect2(0, 0, 1, 1)), "4:3 is the whole window: %s" % rig.frame_rect)
	expect(rig.visible_rect.is_equal_approx(Rect2(0, 0, 1, 1)), "and the scene fills it")
	expect(is_equal_approx(rig.camera.fov, rad_to_deg(2.0 * atan(ArcadeCamera.ARCADE_HALF_HEIGHT / 500.0))), "the height is the game's: %f" % rig.camera.fov)
	rig.place(1.0, Vector2(1280, 720))
	expect(rig.frame_rect.is_equal_approx(Rect2(0.125, 0, 0.75, 1)), "16:9 pillars it: %s" % rig.frame_rect)
	rig.place(1.0, Vector2(940, 720))
	expect(is_equal_approx(rig.frame_rect.size.x, 1.0), "between the two shapes the width fills: %s" % rig.frame_rect)
	expect(is_equal_approx(rig.frame_rect.size.x * 940.0 / (rig.frame_rect.size.y * 720.0), 4.0 / 3.0), "at 4:3: %s" % rig.frame_rect)
	expect(is_equal_approx(rig.frame_rect.get_center().y, 0.5), "centred: %s" % rig.frame_rect)
	rig.place(1.0, Vector2(720, 1280))
	expect(is_equal_approx(rig.frame_rect.size.y, 540.0 / 1280.0), "a tall window spans its width at 4:3: %s" % rig.frame_rect)
	expect(is_equal_approx(rig.frame_rect.get_center().y, 0.5), "and extends evenly: %s" % rig.frame_rect)
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


## The Godot camera has the rotation of the game's view matrix (ViewMatrix.build), with Tekken
## Force's level 4 roll. S = diag(1, −1, −1) turns the game's axes into Godot's, and the view
## matrix's row 1 is scaled by ASPECT.
func test_the_basis_has_the_view_matrix_rotation() -> void:
	if not require(AssetCatalog.ROOT.path_join("manifest.json")):
		return
	var tables := FightTables.load_from(AssetCatalog.ROOT + "tables")
	var directions: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
	var s := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	for a: PackedInt32Array in [PackedInt32Array([0, 0, 0x82]), PackedInt32Array([0x180, 0x7F0, 0x82]),
			PackedInt32Array([0x90, 0x400, -0x82]), PackedInt32Array([0x200, 0xC10, 0])]:
		var view := CameraView.new(a[0], a[1], 0, 0, 0, 500)
		view.roll = a[2]
		var r := ViewMatrix.build(view, tables).rot
		var basis := CameraRig.view_basis(WorldSpace.radians(a[0]), WorldSpace.radians(a[1]), WorldSpace.radians(a[2]))
		var scale_y := float(ViewMatrix.ASPECT) / 4096.0
		for d in directions:
			var want := Vector3(r[0] * d.x + r[1] * d.y + r[2] * d.z,
				(r[3] * d.x + r[4] * d.y + r[5] * d.z) / scale_y, r[6] * d.x + r[7] * d.y + r[8] * d.z) / 4096.0
			var got := s * (basis.transposed() * (s * d))
			expect(got.distance_to(want) < 0.002, "angles %s, %s: %s against %s" % [str(a), str(d), str(got), str(want)])
