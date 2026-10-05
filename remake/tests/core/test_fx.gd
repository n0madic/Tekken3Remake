extends TestSuite
## The integer helpers reproduce the R3000 and GTE behaviour the ports rely on.


func test_s16_wraps() -> void:
	expect_equal(Fx.s16(0x7FFF), 0x7FFF)
	expect_equal(Fx.s16(0x8000), -0x8000)
	expect_equal(Fx.s16(0x1_2345), 0x2345)
	expect_equal(Fx.s16(-1), -1)


func test_sat16_saturates() -> void:
	expect_equal(Fx.sat16(40000), 0x7FFF)
	expect_equal(Fx.sat16(-40000), -0x8000)
	expect_equal(Fx.sat16(123), 123)


func test_w32_wraps_like_c_int() -> void:
	expect_equal(Fx.w32(0x7FFFFFFF + 1), -0x80000000)
	expect_equal(Fx.w32(0x1_0000_0005), 5)
	expect_equal(Fx.w32(-0x80000001), 0x7FFFFFFF)


func test_division_and_shifts_round_like_c() -> void:
	expect_equal(Fx.div_trunc(-7, 2), -3)
	expect_equal(Fx.div_trunc(7, -2), -3)
	expect_equal(Fx.trunc12(-1), 0)
	expect_equal(Fx.trunc12(-4097), -1)
	var n := -4097
	expect_equal(n >> 12, -2, "arithmetic shift floors, as MIPS sra")


func test_mul_matrix_identity() -> void:
	var m := PackedInt32Array([100, -200, 300, 4096, 0, -4096, 7, 8, 9])
	expect_equal(Fx.mul_matrix(Fx.identity(), m), m)
	expect_equal(Fx.mul_matrix(m, Fx.identity()), m)


func test_compose_offset_uses_parent_rotation() -> void:
	# 90° about z: x → y.
	var parent := JointFrame.new(PackedInt32Array([0, -Fx.ONE, 0, Fx.ONE, 0, 0, 0, 0, Fx.ONE]), PackedInt32Array([10, 20, 30]))
	var child := JointFrame.compose_offset(parent, Fx.identity(), PackedInt32Array([100, 0, 0]))
	expect_equal(child.t, PackedInt32Array([10, 120, 30]))
	expect_equal(child.rot, parent.rot)
