class_name InputRouter
extends Node
## Turns keyboards and gamepads into one pad word per player (autoload `Pads`).
##
## Devices are assigned to players on their first button press and released when
## unplugged. Each physics frame produces the physical buttons (`held`, like the game's
## 0x800AE230) and the newly pressed ones; the game applies its key configuration itself
## (GameFlow.key_tables).
## PlayStation controllers over Bluetooth arrive as standard SDL gamepads, so the
## joypad bindings below cover DualShock 4 and DualSense as well as other gamepads.

const PLAYERS := 2
const KEYBOARD := -1          ## device id of the keyboard's left layout (WASD, player 1)
const KEYBOARD_2 := -3        ## device id of the keyboard's right layout (arrows, player 2)
const TOUCH := -4             ## device id of the on-screen touch controls (player 1)
const NO_DEVICE := -2
const STICK_DEADZONE := 0.5
const TRIGGER_THRESHOLD := 0.5
const AXIS_FULL := 0.95       ## an axis pushed this far joins its pad without having been seen at rest
const AXES: Array[JoyAxis] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]

const JOY_BUTTONS := {
	JOY_BUTTON_A: PadState.CROSS,
	JOY_BUTTON_B: PadState.CIRCLE,
	JOY_BUTTON_X: PadState.SQUARE,
	JOY_BUTTON_Y: PadState.TRIANGLE,
	JOY_BUTTON_LEFT_SHOULDER: PadState.L1,
	JOY_BUTTON_RIGHT_SHOULDER: PadState.R1,
	JOY_BUTTON_BACK: PadState.SELECT,
	JOY_BUTTON_START: PadState.START,
	JOY_BUTTON_DPAD_UP: PadState.UP,
	JOY_BUTTON_DPAD_RIGHT: PadState.RIGHT,
	JOY_BUTTON_DPAD_DOWN: PadState.DOWN,
	JOY_BUTTON_DPAD_LEFT: PadState.LEFT,
}

## Keyboard layouts for two players at one keyboard, the face buttons laid out as on the pad
## (Square Triangle over Cross Circle): by default the left player W A S D + R T / F G, the right
## player the arrows + U I / J K. Each joins as its own device on its first key and takes its own
## side (player 1, player 2) when that one is free. The settings rebind them (`layouts`,
## GameSettings.key_layout); Escape, Tab and F3 stay reserved (RESERVED_KEYS).
const DEFAULT_LAYOUTS := [
	{
		KEY_W: PadState.UP, KEY_D: PadState.RIGHT, KEY_S: PadState.DOWN, KEY_A: PadState.LEFT,
		KEY_R: PadState.SQUARE, KEY_T: PadState.TRIANGLE, KEY_F: PadState.CROSS, KEY_G: PadState.CIRCLE,
		KEY_Z: PadState.L1, KEY_X: PadState.R1, KEY_C: PadState.L2, KEY_V: PadState.R2,
		KEY_SPACE: PadState.START, KEY_Q: PadState.SELECT,
	},
	{
		KEY_UP: PadState.UP, KEY_RIGHT: PadState.RIGHT, KEY_DOWN: PadState.DOWN, KEY_LEFT: PadState.LEFT,
		KEY_U: PadState.SQUARE, KEY_I: PadState.TRIANGLE, KEY_J: PadState.CROSS, KEY_K: PadState.CIRCLE,
		KEY_O: PadState.L1, KEY_P: PadState.R1, KEY_L: PadState.L2, KEY_SEMICOLON: PadState.R2,
		KEY_ENTER: PadState.START, KEY_BACKSPACE: PadState.SELECT,
	},
]
## The buttons a keyboard layout binds, by the names the settings file keeps them under.
const BINDABLE := {
	"up": PadState.UP, "right": PadState.RIGHT, "down": PadState.DOWN, "left": PadState.LEFT,
	"square": PadState.SQUARE, "triangle": PadState.TRIANGLE, "cross": PadState.CROSS, "circle": PadState.CIRCLE,
	"l1": PadState.L1, "r1": PadState.R1, "l2": PadState.L2, "r2": PadState.R2,
	"start": PadState.START, "select": PadState.SELECT,
}
const STATS_KEY := KEY_F3     ## toggles the `--stats` line (DevOptions)
const FULLSCREEN_KEY := KEY_F11   ## toggles fullscreen on Windows, as Alt + ALT_ENTER_KEYS do
const ALT_ENTER_KEYS := [KEY_ENTER, KEY_KP_ENTER]
## Keys no layout takes: Escape (ESCAPE_KEY), Tab (the settings screen's tabs), STATS_KEY and FULLSCREEN_KEY.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_TAB, STATS_KEY, FULLSCREEN_KEY]
## The device of each keyboard layout.
const KEYBOARDS := [KEYBOARD, KEYBOARD_2]
## The player each keyboard layout takes when it is free (the touch controls: assign_touch).
const KEYBOARD_PLAYER := {KEYBOARD: 0, KEYBOARD_2: 1}
## Escape stands for the buttons the game sets per screen in `escape_buttons` (Start in a fight or
## a movie, Select or Start + Select, back, in the menus). It takes no player of its own: they go
## to the player the game names (`escape_player`: in a fight its human), else to the player on a
## keyboard layout (the left one first), else to player 1. Both are latched on the press, so a
## screen change while Escape is held moves nothing; the game sets them through `escape_rules`,
## asked each frame before the pads are read. The system's Back
## (Android's button or gesture) is an Escape press held BACK_FRAMES frames where the game allows it
## (`back_allowed`: not on the main menu, where Escape opens the settings).
const ESCAPE_KEY := KEY_ESCAPE
const BACK_FRAMES := 6

var devices := PackedInt32Array([NO_DEVICE, NO_DEVICE])
## The keyboard layouts in use (key → pad bit), the left one first.
var layouts: Array[Dictionary] = [(DEFAULT_LAYOUTS[0] as Dictionary).duplicate(), (DEFAULT_LAYOUTS[1] as Dictionary).duplicate()]
var keyboard_seen := false         ## a key was pressed this session (a keyboard is attached)
var held := PackedInt32Array([0, 0])
var pressed := PackedInt32Array([0, 0])
var rumble := Rumble.new()
var escape_buttons := PadState.START
var escape_player := -1            ## the player Escape's buttons go to on this screen, −1: escape_owner()
## Returns Vector2i(escape_buttons, escape_player) for the screen showing now (the game sets it).
var escape_rules := Callable()
var _escape_to := 0                ## the player Escape's latched buttons go to while it is held
var _axes_at_rest: Dictionary = {}  ## Vector2i(device, axis) → true: seen pressing nothing
var _escape_held := 0              ## the buttons Escape stood for when pressed, kept while held
var escape_pressed := false        ## Escape went down this frame
var _escape_down := false
var _back_frames := 0              ## frames the system's Back still holds Escape down
var back_allowed := true           ## the system's Back presses Escape on this screen
var touch_bits := 0                ## the touch controls' pad word (TouchControls sets it each frame)
var touch_latch := 0               ## touch presses since the last physics frame: a tap shorter
                                   ## than a frame still reaches the game once


func _ready() -> void:
	process_physics_priority = -100   # before every consumer of the pad words
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventJoypadMotion
	if motion != null:
		_axis_moved(motion.device, motion.axis, motion.axis_value)
		return
	if not event.is_pressed() or event.is_echo():
		return
	var device := NO_DEVICE
	if event is InputEventKey:
		keyboard_seen = true
		var key := (event as InputEventKey).physical_keycode
		for layout in layouts.size():
			if layouts[layout].has(key):
				device = KEYBOARDS[layout] as int
				break
	elif event is InputEventJoypadButton:
		device = (event as InputEventJoypadButton).device
	if device != NO_DEVICE and not device in devices:
		assign(device)


func _physics_process(_delta: float) -> void:
	if escape_rules.is_valid():
		var rules: Vector2i = escape_rules.call()
		escape_buttons = rules.x
		escape_player = rules.y
	var escape := escape_latch(Input.is_physical_key_pressed(ESCAPE_KEY) or _back_frames > 0)
	_back_frames = maxi(0, _back_frames - 1)
	for player in PLAYERS:
		var now := read_device(devices[player])
		if player == _escape_to:
			now |= escape
		pressed[player] = now & ~held[player]
		held[player] = now
	touch_latch = 0
	rumble.update()


## The system's Back (the application does not quit on it: project setting quit_on_go_back).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


## Presses Escape as the system's Back does.
func back() -> void:
	if back_allowed:
		_back_frames = BACK_FRAMES


## Assigns a device to its keyboard side if free, else to the first free player; returns the
## player or −1.
func assign(device: int) -> int:
	var preferred: int = KEYBOARD_PLAYER.get(device, -1)
	if preferred >= 0 and devices[preferred] == NO_DEVICE:
		devices[preferred] = device
		return preferred
	for player in PLAYERS:
		if devices[player] == NO_DEVICE:
			devices[player] = device
			return player
	return -1


## The touch controls take player 1 (remake-plan.md, "Touch"): a device already there moves to
## player 2 when that is free, else it leaves. Returns the player (0).
func assign_touch() -> int:
	var other := devices[0]
	if other == TOUCH:
		return 0
	if other != NO_DEVICE:
		devices[0] = NO_DEVICE
		if devices[1] == NO_DEVICE:
			devices[1] = other
	devices[0] = TOUCH
	return 0


## Physical buttons of one device as a pad word.
func read_device(device: int) -> int:
	if device == NO_DEVICE:
		return 0
	if device == TOUCH:
		return touch_bits | touch_latch
	var bits := 0
	if device == KEYBOARD or device == KEYBOARD_2:
		var layout: Dictionary = layouts[KEYBOARDS.find(device)]
		for key: Key in layout:
			if Input.is_physical_key_pressed(key) and not is_alt_enter(key, Input.is_physical_key_pressed(KEY_ALT)):
				var key_bit: int = layout[key]
				bits |= key_bit
		return bits
	for button: JoyButton in JOY_BUTTONS:
		if Input.is_joy_button_pressed(device, button):
			var button_bit: int = JOY_BUTTONS[button]
			bits |= button_bit
	for axis: JoyAxis in AXES:
		bits |= axis_bits(axis, Input.get_joy_axis(device, axis))
	return bits


## Whether the fullscreen hotkeys (F11, Alt + Enter) act on this system: on Windows only (F11 is
## reserved from the layouts everywhere).
static func fullscreen_hotkeys(os_name: String = OS.get_name()) -> bool:
	return os_name == "Windows"


## Whether `key` held with Alt is the fullscreen hotkey, not the button a layout binds to it (the
## right player's Start by default).
static func is_alt_enter(key: Key, alt_held: bool, os_name: String = OS.get_name()) -> bool:
	return alt_held and key in ALT_ENTER_KEYS and fullscreen_hotkeys(os_name)


## The pad bits an axis at this value presses: L2 and R2 past TRIGGER_THRESHOLD, the left stick's
## directions past STICK_DEADZONE.
static func axis_bits(axis: JoyAxis, value: float) -> int:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return PadState.L2 if value > TRIGGER_THRESHOLD else 0
		JOY_AXIS_TRIGGER_RIGHT:
			return PadState.R2 if value > TRIGGER_THRESHOLD else 0
		JOY_AXIS_LEFT_X:
			return PadState.RIGHT if value > STICK_DEADZONE else PadState.LEFT if value < -STICK_DEADZONE else 0
		JOY_AXIS_LEFT_Y:
			return PadState.DOWN if value > STICK_DEADZONE else PadState.UP if value < -STICK_DEADZONE else 0
	return 0


## A stick or trigger that presses a button joins its pad once that axis has been seen at rest, or
## at once when it is pushed all the way (AXIS_FULL: Godot reports an axis only as it changes, so a
## digital trigger's first press, 0 to 1, is its first event): a drifting stick never joins by itself.
func _axis_moved(device: int, axis: JoyAxis, value: float) -> void:
	var key := Vector2i(device, axis)
	if axis_bits(axis, value) == 0:
		_axes_at_rest[key] = true
	elif (_axes_at_rest.has(key) or absf(value) >= AXIS_FULL) and not device in devices:
		assign(device)


## Whether a keyboard can be at hand: always on computers and the web; on phones and tablets one
## the system reports or that pressed a key this session.
func has_keyboard() -> bool:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return true
	return keyboard_seen or DisplayServer.has_hardware_keyboard()


## The player Escape's buttons go to: the one on the left keyboard layout, else on the right one,
## else player 1.
func escape_owner() -> int:
	for device: int in [KEYBOARD, KEYBOARD_2]:
		var player := devices.find(device)
		if player >= 0:
			return player
	return 0


## The buttons Escape stands for, latched on its press so a screen change while it is held
## does not press others.
func escape_latch(down: bool) -> int:
	escape_pressed = down and not _escape_down
	_escape_down = down
	if not down:
		_escape_held = 0
	elif escape_pressed:
		_escape_held = escape_buttons
		_escape_to = escape_player if escape_player >= 0 else escape_owner()
	return _escape_held


func device_name(player: int) -> String:
	var device := devices[player]
	if device == NO_DEVICE:
		return "—"
	if device == KEYBOARD:
		return "Keyboard 1"
	if device == KEYBOARD_2:
		return "Keyboard 2"
	if device == TOUCH:
		return "Touch"
	return Input.get_joy_name(device)


## Motor levels of a player's pad for this frame: small motor on/off, large 0–255.
func set_motors(player: int, small_on: bool, large: int) -> void:
	rumble.set_motors(devices[player], small_on, large)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	# A pad that comes with this id later is another pad: its axes are not known to rest.
	for axis: JoyAxis in AXES:
		_axes_at_rest.erase(Vector2i(device, axis))
	if connected:
		return
	for player in PLAYERS:
		if devices[player] == device:
			devices[player] = NO_DEVICE
			held[player] = 0
			pressed[player] = 0
