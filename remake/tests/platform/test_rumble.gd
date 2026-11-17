extends TestSuite
## The motors (Rumble): the touch controls' player feels the phone's own motor at the stronger of
## the two levels, rounded to eighths; it stops when the game stops asking.


func test_touch_drives_the_phone_motor() -> void:
	var rumble := Rumble.new()
	rumble.set_motors(InputRouter.TOUCH, false, 255)
	rumble.update()
	expect_equal(rumble.handheld_level, 1.0, "the large motor at full strength")
	rumble.set_motors(InputRouter.TOUCH, true, 0)
	rumble.update()
	expect_equal(rumble.handheld_level, Rumble.SMALL_SHARE, "the small motor's buzz")
	rumble.set_motors(InputRouter.TOUCH, true, 200)
	rumble.update()
	expect_equal(rumble.handheld_level, 7.0 / 8.0, "the stronger one, rounded up to eighths")
	rumble.update()
	expect_equal(rumble.handheld_level, 0.0, "no request this frame: still")
	rumble.set_motors(InputRouter.KEYBOARD, true, 255)
	rumble.update()
	expect_equal(rumble.handheld_level, 0.0, "a keyboard has no motor")
