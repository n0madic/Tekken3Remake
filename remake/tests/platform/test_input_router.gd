extends TestSuite
## Pad words and device assignment of the input router.


func test_devices_join_in_order_and_only_once() -> void:
	var router := InputRouter.new()
	expect_equal(router.assign(InputRouter.KEYBOARD), 0)
	expect_equal(router.assign(3), 1)
	expect_equal(router.assign(4), -1, "no free player")
	expect_equal(router.devices[0], InputRouter.KEYBOARD)
	router.free()


func test_unassigned_player_reads_nothing() -> void:
	var router := InputRouter.new()
	expect_equal(router.read_device(InputRouter.NO_DEVICE), 0)
	router.free()


func test_pad_bits_follow_libetc() -> void:
	# The game's face buttons: □ 0x80, △ 0x10, ✕ 0x40, ○ 0x20; directions 0x1000–0x8000.
	expect_equal(PadState.SQUARE, 0x80)
	expect_equal(PadState.TRIANGLE, 0x10)
	expect_equal(PadState.CROSS, 0x40)
	expect_equal(PadState.CIRCLE, 0x20)
	expect_equal(PadState.UP | PadState.RIGHT | PadState.DOWN | PadState.LEFT, 0xF000)
	expect_equal(PadState.describe(PadState.START | PadState.L1), "L1 Start")


func test_two_keyboard_layouts_are_two_players() -> void:
	var router := InputRouter.new()
	var arrows := InputEventKey.new()
	arrows.physical_keycode = KEY_LEFT
	arrows.pressed = true
	var wasd := InputEventKey.new()
	wasd.physical_keycode = KEY_A
	wasd.pressed = true
	router._unhandled_input(arrows)
	router._unhandled_input(wasd)
	router._unhandled_input(arrows)
	expect_equal(router.devices[0], InputRouter.KEYBOARD, "WASD takes player 1 though pressed second")
	expect_equal(router.devices[1], InputRouter.KEYBOARD_2, "the arrows take player 2")
	for key: Key in InputRouter.DEFAULT_LAYOUTS[0]:
		expect(not (InputRouter.DEFAULT_LAYOUTS[1] as Dictionary).has(key), "a key belongs to one layout only")
	router.free()


func test_rebound_layouts_pick_the_device() -> void:
	var router := InputRouter.new()
	router.layouts[1] = {KEY_A: PadState.LEFT}
	router.layouts[0] = {KEY_H: PadState.LEFT}
	var a := InputEventKey.new()
	a.physical_keycode = KEY_A
	a.pressed = true
	router._unhandled_input(a)
	expect_equal(router.devices[1], InputRouter.KEYBOARD_2, "A now belongs to the right layout")
	expect(router.keyboard_seen, "a key was seen")
	expect(router.has_keyboard(), "a keyboard at hand")
	router.free()


func test_escape_keeps_the_buttons_of_its_press() -> void:
	var router := InputRouter.new()
	router.escape_buttons = PadState.START
	expect_equal(router.escape_latch(true), PadState.START, "the pause in a fight")
	router.escape_buttons = PadState.START | PadState.SELECT
	expect_equal(router.escape_latch(true), PadState.START, "held across a screen change")
	expect_equal(router.escape_latch(false), 0, "released")
	expect(not router.escape_pressed, "held, not pressed")
	expect_equal(router.escape_latch(true), PadState.START | PadState.SELECT, "the next press")
	expect(router.escape_pressed, "pressed")
	router.free()


func test_escape_goes_to_the_keyboard_player_without_joining() -> void:
	var router := InputRouter.new()
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	router._unhandled_input(esc)
	expect_equal(router.devices, PackedInt32Array([InputRouter.NO_DEVICE, InputRouter.NO_DEVICE]), "Escape takes no player")
	expect_equal(router.escape_owner(), 0, "no keyboard: player 1")
	router.assign(3)
	expect_equal(router.escape_owner(), 0, "a pad on player 1: still player 1")
	router.assign(InputRouter.KEYBOARD)
	expect_equal(router.devices[1], InputRouter.KEYBOARD, "the keyboard joins as player 2")
	expect_equal(router.escape_owner(), 1, "then Escape is player 2's")
	router.free()


## The system's Back (Android) presses Escape for a few frames: the buttons Escape stands for.
func test_back_presses_escape() -> void:
	var router := InputRouter.new()
	router.escape_buttons = PadState.SELECT
	router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	router._physics_process(0.0)
	expect(router.escape_pressed, "pressed on the first frame")
	expect_equal(router.held[0], PadState.SELECT, "Select for player 1")
	for i in InputRouter.BACK_FRAMES - 1:
		router._physics_process(0.0)
	expect_equal(router.held[0], PadState.SELECT, "held for BACK_FRAMES frames")
	router._physics_process(0.0)
	expect_equal(router.held[0], 0, "then released")
	router.back_allowed = false
	router.back()
	router._physics_process(0.0)
	expect(not router.escape_pressed and router.held[0] == 0, "nothing where the game does not allow it")
	router.free()


## A gamepad joins on its stick and triggers too, past the levels at which they press buttons,
## once the axis has been seen at rest (a drifting stick never joins by itself).
func test_stick_and_triggers_join() -> void:
	var router := InputRouter.new()
	var motion := InputEventJoypadMotion.new()
	motion.device = 5
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = -0.9
	router._unhandled_input(motion)
	expect(not 5 in router.devices, "never seen at rest (a drifting stick): no join")
	motion.axis_value = InputRouter.STICK_DEADZONE * 0.5
	router._unhandled_input(motion)
	expect(not 5 in router.devices, "a stick inside its dead zone does not join")
	motion.axis_value = -0.9
	router._unhandled_input(motion)
	expect_equal(router.devices[0], 5, "pushed from rest, the stick joins its pad")
	motion.device = 6
	motion.axis = JOY_AXIS_TRIGGER_RIGHT
	motion.axis_value = 0.0
	router._unhandled_input(motion)
	motion.axis_value = 0.9
	router._unhandled_input(motion)
	expect_equal(router.devices[1], 6, "a squeezed trigger joins its pad")
	var other := InputRouter.new()
	motion.device = 7
	motion.axis_value = 1.0
	other._unhandled_input(motion)
	expect_equal(other.devices[0], 7, "a digital trigger (0 to 1 in one event) joins on its first press")
	other.free()
	router._on_joy_connection_changed(5, false)
	router._on_joy_connection_changed(5, true)
	motion.device = 5
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = -0.9
	router._unhandled_input(motion)
	expect(not 5 in router.devices, "another pad under the same id is not known to rest")
	router.free()


func test_axis_bits() -> void:
	expect_equal(InputRouter.axis_bits(JOY_AXIS_LEFT_X, -0.9), PadState.LEFT)
	expect_equal(InputRouter.axis_bits(JOY_AXIS_LEFT_Y, 0.9), PadState.DOWN)
	expect_equal(InputRouter.axis_bits(JOY_AXIS_LEFT_Y, 0.2), 0, "inside the dead zone")
	expect_equal(InputRouter.axis_bits(JOY_AXIS_TRIGGER_LEFT, 0.9), PadState.L2)
	expect_equal(InputRouter.axis_bits(JOY_AXIS_RIGHT_X, 1.0), 0, "the right stick presses nothing")


func test_escape_owner_and_reserved_stats_key() -> void:
	var router := InputRouter.new()
	router.assign(InputRouter.KEYBOARD_2)
	expect_equal(router.escape_owner(), 1, "the keyboard's player")
	expect(InputRouter.STATS_KEY in InputRouter.RESERVED_KEYS, "F3 is no layout's key")
	router.free()


## Escape's buttons go to the player the game names, latched with them on the press: a screen
## change while it is held moves nothing to another pad.
func test_escape_player_is_latched() -> void:
	var router := InputRouter.new()
	router.assign(InputRouter.KEYBOARD)
	var rules := [Vector2i(PadState.START, 1)]
	router.escape_rules = func() -> Vector2i: return rules[0]
	router.back()
	router._physics_process(0.0)
	expect_equal(router.held[1], PadState.START, "the fight's human gets Start")
	expect_equal(router.held[0], 0, "not the keyboard's player")
	rules[0] = Vector2i(PadState.SELECT, -1)
	router._physics_process(0.0)
	expect_equal(router.held[1], PadState.START, "held across the screen change: the same buttons, the same player")
	expect_equal(router.held[0], 0, "nothing moves to the keyboard's player")
	for i in InputRouter.BACK_FRAMES:
		router._physics_process(0.0)
	router.back()
	router._physics_process(0.0)
	expect_equal(router.held[0], PadState.SELECT, "the next press follows the new rules")
	router.free()
