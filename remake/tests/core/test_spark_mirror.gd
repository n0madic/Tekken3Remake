extends TestSuite
## Which way a hit spark's flipbook is drawn (EffectObjects.spawn_mirrored): EffectSpawn
## (FUN_80076B6C) keeps the sign of the hit direction's cross product with the camera's ray to the
## point, and FUN_80077158 swaps the quad's left and right texels when it is set. The cases follow
## the decompiled expression, in the game's own 32-bit arithmetic.


## What the game's own EffectSpawn stored (tools/research/verify_spark_mirror.py --export, which
## checks 3,000 random cases): the point's x and z, the direction's x and z, the camera's x and z,
## and the flag. The later rows are far out, where the products pass 2³¹.
const GAME_CASES: Array = [
	[-54778, 59213, 32169, 29130, -73457, -23136, false],
	[4675, 219, -3632, 2994, -2561, -4463, true],
	[3952, -5966, -348, 1104, 5400, 1297, false],
	[-5499, -5635, -3946, -548, -5584, 4642, false],
	[915, 5892, 3078, -278, -5525, 2644, false],
	[-337, -2218, 3434, -3744, 5089, -2416, true],
	[64030, 40904, -28243, -952, 42457, 13115, true],
	[722, -89585, 10634, -29102, 51158, 51586, false],
	[-47998, 26829, -3854, -3514, 42725, 87779, true],
	[-1109, 22522, -20132, 12301, -34156, -20130, true],
	[-59827, -79509, 22415, -17622, -40738, -27182, true],
	[-9579, -79239, 6921, 11053, -4216, -41029, true],
]


static func _view(x: int, z: int) -> CameraView:
	return CameraView.new(0, 0, x, 0, z, 500)


func test_it_matches_what_the_game_stored() -> void:
	for row: Array in GAME_CASES:
		var point := PackedInt32Array([row[0] as int, 0, row[1] as int])
		var hit := PackedInt32Array([row[2] as int, 0, row[3] as int])
		expect_equal(EffectObjects.spawn_mirrored(point, hit, _view(row[4] as int, row[5] as int)), row[6] as bool,
			"point (%d, %d), direction (%d, %d), camera (%d, %d)" % [row[0], row[1], row[2], row[3], row[4], row[5]])


func test_the_hit_direction_decides_the_side() -> void:
	var point := PackedInt32Array([0, 0, 1000])
	var view := _view(0, 0)
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([100, 0, 0]), view), false, "a hit along +x")
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([-100, 0, 0]), view), true, "a hit along −x is the other way round")


func test_seen_from_the_other_side_the_same_hit_is_mirrored() -> void:
	var point := PackedInt32Array([0, 0, 1000])
	var hit := PackedInt32Array([100, 0, 0])
	expect_equal(EffectObjects.spawn_mirrored(point, hit, _view(0, 0)), false, "camera before the point")
	expect_equal(EffectObjects.spawn_mirrored(point, hit, _view(0, 2000)), true, "camera beyond it")


func test_a_hit_along_the_view_ray_is_not_mirrored() -> void:
	var point := PackedInt32Array([300, 0, 1000])
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([30, 0, 100]), _view(0, 0)), false, "along the ray: no side")
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([-30, 0, -100]), _view(0, 0)), false, "against it too")


func test_height_does_not_count() -> void:
	var point := PackedInt32Array([0, -500, 1000])
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([-100, 4000, 0]), _view(0, 0)), true, "only x and z of the direction")


func test_no_direction_no_mirror() -> void:
	var point := PackedInt32Array([0, 0, 1000])
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array(), _view(0, 0)), false, "a move event's flipbook has none")
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([0, 0, 0]), _view(0, 0)), false, "a zero direction")
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([-100, 0, 0]), null), false, "nor without a camera")


func test_the_sum_wraps_as_the_games_32_bits_do() -> void:
	# 30000 · 80000 = 2.4e9 is past 2³¹: the game's int turns negative, a 64-bit one would not. Far
	# beyond what a fight reaches, but the port keeps the game's arithmetic.
	var point := PackedInt32Array([0, 0, 80000])
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([30000, 0, 0]), _view(0, 0)), true, "32-bit wrap")
	expect_equal(EffectObjects.spawn_mirrored(point, PackedInt32Array([20000, 0, 0]), _view(0, 0)), false, "1.6e9 does not wrap")
