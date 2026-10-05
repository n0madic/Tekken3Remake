extends TestSuite
## The touch controls (TouchControls): each finger on its own, the face buttons, the stick's eight
## directions past its dead zone, sliding between buttons, the macros, and the pad word that
## InputRouter reads as the touch device.

const WINDOW := Vector2(1280, 720)

var _made: Array[TouchControls] = []
var _devices: PackedInt32Array


func _begin() -> void:
	_devices = Pads.devices.duplicate()


func _end() -> void:
	for t in _made:
		t.free()
	_made.clear()
	# A press joins the touch device as player 1: give the players their devices back.
	Pads.devices = _devices
	Pads.touch_bits = 0
	Pads.touch_latch = 0


func _controls(macros: String) -> TouchControls:
	var t := TouchControls.new()
	_made.append(t)
	t.size = WINDOW
	t.set_macros(macros)
	return t


func _centre_of(t: TouchControls, bits: int) -> Vector2:
	for c in t._controls:
		if c.bits == bits:
			return c.centre if c.rect.size == Vector2.ZERO else c.rect.get_center()
	return Vector2.INF


func test_buttons_and_stick() -> void:
	_begin()
	var t := _controls("none")
	var cross := _centre_of(t, PadState.CROSS)
	expect(t.press(0, cross), "a face button takes the finger")
	expect_equal(t.bits, PadState.CROSS, "Cross held")
	var start := Vector2(200, 500)
	expect(t.press(1, start), "the stick zone takes a second finger")
	t.move(1, start + Vector2(0, -3 * t._unit))
	expect_equal(t.bits, PadState.CROSS | PadState.UP, "up with Cross")
	t.move(1, start + Vector2(2 * t._unit, 2 * t._unit))
	expect_equal(t.bits, PadState.CROSS | PadState.DOWN | PadState.RIGHT, "down-right")
	t.move(1, start + Vector2(0.1 * t._unit, 0))
	expect_equal(t.bits, PadState.CROSS, "inside the dead zone: no direction")
	t.move(0, _centre_of(t, PadState.CIRCLE))
	expect_equal(t.bits, PadState.CIRCLE, "the finger slid from Cross to Circle")
	t.release(0)
	t.release(1)
	expect_equal(t.bits, 0, "all lifted")
	expect(Pads.read_device(InputRouter.TOUCH) & PadState.CIRCLE != 0, "a press lifted within the frame still counts")
	expect(not t.press(2, Vector2(WINDOW.x * 0.75, WINDOW.y * 0.5)), "an empty place on the right is not taken")
	expect(t.press(3, _centre_of(t, PadState.START)), "Start")
	expect_equal(t.bits, PadState.START, "Start held")
	t.reset()
	expect_equal(Pads.touch_bits, 0, "the reset clears the router's touch word")
	_end()


func test_stick_belongs_to_its_first_finger() -> void:
	_begin()
	var t := _controls("none")
	var start := Vector2(200, 500)
	expect(t.press(0, start), "the first finger takes the stick")
	expect(t.press(1, start + Vector2(20, 0)), "a second finger in the zone is taken too")
	expect_equal(t.bits, 0, "it does not move the stick")
	t.move(0, start + Vector2(0, -3 * t._unit))
	expect_equal(t.bits, PadState.UP, "the first finger steers")
	t.release(0)
	expect_equal(t.bits, 0, "its lift frees the stick")
	expect(not t._fingers.has(1), "the second finger is not tracked")
	expect(t.press(2, start), "a new finger takes the freed stick")
	t.move(2, start + Vector2(3 * t._unit, 0))
	expect_equal(t.bits, PadState.RIGHT, "and steers it")
	t.release(2)
	expect_equal(t.bits, 0, "all lifted")
	_end()


## The lift of a finger can be lost (an app switch, a system gesture): losing the focus lets every
## finger go, so that the stick is not held by a finger that is gone.
func test_losing_the_focus_lets_the_fingers_go() -> void:
	_begin()
	var t := _controls("none")
	var start := Vector2(200, 500)
	expect(t.press(1, start), "a stick finger")
	t.move(1, start + Vector2(3 * t._unit, 0))
	expect_equal(t.bits, PadState.RIGHT, "steering")
	t._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect_equal(t.bits, 0, "everything let go")
	expect(t.press(0, start), "a new finger, another index, takes the stick")
	t.move(0, start + Vector2(0, 3 * t._unit))
	expect_equal(t.bits, PadState.DOWN, "and steers it")
	t.reset()
	_end()


func test_macros() -> void:
	_begin()
	var t := _controls("throws")
	var throw := PadState.SQUARE | PadState.CROSS
	expect(t.press(0, _centre_of(t, throw)), "the 1+3 macro button")
	expect_equal(t.bits, throw, "1+3 held at once")
	expect_equal(Pads.read_device(InputRouter.TOUCH), throw, "InputRouter reads the touch word")
	t.reset()
	expect_equal(_controls("none")._controls.size(), 10, "four face buttons, Start, Select, L1, L2, R1 and R2")
	expect_equal(_controls("all")._controls.size(), 14, "and four macros")
	_end()


## The shoulder buttons in one row, L1 L2 over the stick and R2 R1 over the face buttons, Select and Start at
## the bottom in the middle, the macros in the top corners; every control inside the window and
## none overlapping another, at every size setting, on wide and 4:3 screens.
func test_layout() -> void:
	_begin()
	for window: Vector2 in [WINDOW, Vector2(2400, 1080), Vector2(1024, 768)]:
		for share: int in (GameSettings.SCHEMA["touch_size"] as Array)[1]:
			_check_layout(window, share)
	_end()


func _check_layout(window: Vector2, share: int) -> void:
	var t := _controls("all")
	t.size = window
	t.set_scale_share(share / 100.0)
	var at := "%d%% at %s" % [share, window]
	var l1 := _centre_of(t, PadState.L1)
	var l2 := _centre_of(t, PadState.L2)
	var r1 := _centre_of(t, PadState.R1)
	var r2 := _centre_of(t, PadState.R2)
	var triangle := _centre_of(t, PadState.TRIANGLE)
	expect(l1.x < l2.x and l2.x < window.x * 0.3 and l1.y < triangle.y, "L1 L2 over the stick (%s)" % at)
	expect(r2.x < triangle.x and r1.x > triangle.x and r1.y < triangle.y, "R2 R1 over the face buttons (%s)" % at)
	expect(is_equal_approx(l1.y, r1.y) and is_equal_approx(l2.y, r2.y) and is_equal_approx(l1.y, l2.y),
		"all four on one level (%s)" % at)
	var select := _centre_of(t, PadState.SELECT)
	var start := _centre_of(t, PadState.START)
	var middle := (select.x + start.x) / 2.0
	expect(select.x < start.x and select.y > window.y * 0.8 and middle <= window.x / 2.0 + 0.01
		and middle > window.x * 0.4, "Select and Start at the bottom, in the middle or left of it (%s)" % at)
	if window.x >= window.y * 16.0 / 9.0 - 1.0:
		expect(is_equal_approx(middle, window.x / 2.0), "in the middle on wide screens (%s)" % at)
	var throw_1 := _centre_of(t, PadState.SQUARE | PadState.CROSS)
	var throw_2 := _centre_of(t, PadState.TRIANGLE | PadState.CIRCLE)
	expect(throw_1.x < window.x * 0.25 and throw_2.x > window.x * 0.75 and throw_1.y < window.y * 0.2,
		"the throws in the top corners (%s)" % at)
	expect(t.top_left_free.position.x > _centre_of(t, PadState.SQUARE | PadState.TRIANGLE).x,
		"the free place right of the left macros (%s)" % at)
	var boxes: Array[Rect2] = []
	for c in t._controls:
		boxes.append(c.rect if c.rect.size != Vector2.ZERO else Rect2(c.centre - Vector2.ONE * c.radius, Vector2.ONE * 2.0 * c.radius))
	for i in boxes.size():
		expect(Rect2(Vector2.ZERO, window).encloses(boxes[i]), "control %d inside the window (%s)" % [i, at])
		for j in range(i + 1, boxes.size()):
			var a := t._controls[i]
			var b := t._controls[j]
			var apart := a.centre.distance_to(b.centre) > a.radius + b.radius \
				if a.rect.size == Vector2.ZERO and b.rect.size == Vector2.ZERO else not boxes[i].intersects(boxes[j])
			expect(apart, "controls %d and %d apart (%s)" % [i, j, at])
			# A rectangle's touch area (taken before any round button's) must not reach a round
			# button's touch area.
			if (a.rect.size == Vector2.ZERO) != (b.rect.size == Vector2.ZERO):
				var round := a if a.rect.size == Vector2.ZERO else b
				var rect := (b if round == a else a).rect.grow(TouchControls.RECT_SLACK * t._unit)
				var nearest := round.centre.clamp(rect.position, rect.end)
				expect(nearest.distance_to(round.centre) > round.radius * TouchControls.HIT_SLACK,
					"touch areas of controls %d and %d apart (%s)" % [i, j, at])
	expect(t.press(0, l1) and t.bits == PadState.L1, "L1 pressed (%s)" % at)
	t.reset()


## The key configuration page shows all four shoulder buttons, assigned or not.
func test_key_configuration_shows_every_shoulder() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	var all := PadState.L1 | PadState.L2 | PadState.R1 | PadState.R2
	expect_equal(TouchControls.shoulders_shown(flow), 0, "none assigned by default")
	flow.state = GameFlow.State.OPTIONS
	flow.options.page = OptionsScreen.PAGE_RECORDS
	expect_equal(TouchControls.shoulders_shown(flow), 0, "other options pages")
	flow.options.page = OptionsScreen.PAGE_KEYS
	expect_equal(TouchControls.shoulders_shown(flow), all, "the key configuration page")
	flow.state = GameFlow.State.MENU
	expect_equal(TouchControls.shoulders_shown(flow), 0, "left the options")


## Only the shoulder buttons the key configuration uses are shown; the others leave their places
## empty (a touch there is not taken).
func test_unassigned_shoulders_hidden() -> void:
	_begin()
	var t := _controls("none")
	var r1 := _centre_of(t, PadState.R1)
	var l1 := _centre_of(t, PadState.L1)
	t.set_shoulders(0)
	expect_equal(t._controls.size(), 6, "none by default: four face buttons, Select and Start")
	expect(not t.press(0, r1), "R1's place is empty")
	t.set_shoulders(PadState.L1)
	expect_equal(t._controls.size(), 7, "L1 once it has an action")
	expect_equal(_centre_of(t, PadState.L1), l1, "in its own place")
	expect(t.press(1, l1) and t.bits == PadState.L1, "and pressed")
	t.reset()
	_end()


## A shoulder button that goes away under a finger lets go; one that stays keeps its finger.
func test_hidden_shoulder_lets_go() -> void:
	_begin()
	var t := _controls("none")
	t.set_shoulders(PadState.L1 | PadState.R1)
	expect(t.press(0, _centre_of(t, PadState.L1)), "L1 held")
	expect(t.press(1, _centre_of(t, PadState.R1)), "R1 held")
	t.set_shoulders(PadState.R1)
	expect_equal(t.bits, PadState.R1, "L1 is gone and let go; R1 stays held")
	t.release(1)
	expect_equal(t.bits, 0, "R1 lifted")
	t.reset()
	_end()


## While something plays only Select and Start stay, in their places; the stick is gone.
func test_playback_keeps_select_and_start() -> void:
	_begin()
	var t := _controls("throws")
	var start := _centre_of(t, PadState.START)
	var cross := _centre_of(t, PadState.CROSS)
	expect(t.press(0, cross), "Cross held")
	t.set_playback(true)
	expect_equal(t.bits, 0, "the fingers down let go")
	expect_equal(t._controls.size(), 2, "Select and Start only")
	expect_equal(_centre_of(t, PadState.START), start, "Start in its place")
	expect(not t.press(1, cross), "Cross's place is empty")
	expect(not t.press(2, Vector2(200, 500)), "no stick")
	expect(t.press(3, start) and t.bits == PadState.START, "Start skips")
	t.set_playback(false)
	expect_equal(t._controls.size(), 12, "everything back: face buttons, throws, Select, Start, shoulders")
	_end()


func test_stick_directions() -> void:
	_begin()
	var t := _controls("none")
	var expected := [PadState.RIGHT, PadState.RIGHT | PadState.DOWN, PadState.DOWN, PadState.DOWN | PadState.LEFT,
		PadState.LEFT, PadState.LEFT | PadState.UP, PadState.UP, PadState.UP | PadState.RIGHT]
	for k in 8:
		var offset := Vector2.from_angle(TAU * k / 8.0) * t._unit
		expect_equal(t.stick_bits(offset), expected[k], "direction %d" % k)
	_end()


## The touch controls take player 1: a keyboard there moves to player 2, a pad on player 1 with
## player 2 taken leaves.
func test_touch_takes_player_one() -> void:
	_begin()
	var t := _controls("none")
	Pads.devices = PackedInt32Array([InputRouter.KEYBOARD, InputRouter.NO_DEVICE])
	t.press(0, _centre_of(t, PadState.CROSS))
	expect_equal(Pads.devices, PackedInt32Array([InputRouter.TOUCH, InputRouter.KEYBOARD]), "the keyboard moves to 2P")
	t.reset()
	Pads.devices = PackedInt32Array([0, 1])
	t.press(0, _centre_of(t, PadState.CROSS))
	expect_equal(Pads.devices, PackedInt32Array([InputRouter.TOUCH, 1]), "pad 0 leaves, pad 1 stays 2P")
	t.reset()
	_end()
