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


## A pad's motors are stopped once as they fall still, not on every frame the game asks for nothing.
func test_pad_stopped_once() -> void:
	var rumble := Rumble.new()
	var pad := 0
	rumble.set_motors(pad, false, 0)
	rumble.update()
	expect(not rumble.running.has(pad), "never started: nothing to stop")
	rumble.set_motors(pad, true, 128)
	rumble.update()
	expect(rumble.running.has(pad), "running")
	rumble.set_motors(pad, false, 0)
	rumble.update()
	expect(not rumble.running.has(pad), "stopped as the levels fall to zero")
	rumble.set_motors(pad, false, 0)
	rumble.update()
	expect(not rumble.running.has(pad), "and left alone after that")
