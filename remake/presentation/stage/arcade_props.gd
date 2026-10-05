class_name ArcadeProps
extends RefCounted
## The arcade stages' animated props (docs/research/arcade/stages.md#props), ported
## from tools/research/arcade_props_sim.py, which matches the arcade's own routines frame for frame
## (verify_arcade_props.py; tests/presentation/test_arcade_props.gd replays its trace here).
##
## Stage 3 turns its carousel (FUN_801E59FC, FUN_801E5AD0). Stage 11 flies a helicopter around
## the arena (FUN_801E3DE0 at a round's start, FUN_801E3D0C every frame it is shown) in one of
## four modes: 0 hovers and, once the camera has turned far, circles to stay in view; 1–3 fly
## scripted figures. Arcade bug #63 (game-bugs.md) kept mode 0 from ever circling; the circling
## runs here, as meant.
##
## The state is the game's: SVECTOR angles and positions (scene units, y down) per prop, and the
## helicopter's 16-bit variables.

const CAROUSEL := "carousel"
const HELICOPTER := "helicopter"
const PROPS := 4
const CAROUSEL_TURN := -5
const CAROUSEL_FRAMES := 0x88
const CAROUSEL_START := 0x955
const WARMUP := 0x78
const ROTOR := 0x29F
const RADIUS := 0x1068
const NEAR_TURN := 0x17C
const FAR_TURN := 0x352
const NEAR_PROFILE: Array[int] = [7, 507, 460, 11]   ## top step, orbit, brake distance, turn rate
const FAR_PROFILE: Array[int] = [15, 1016, 793, 16]
const ANGLE_MASK := 0xFFF
## The arcade's input bits of the four attack buttons (FUN_8018F070 picks a pose with them in the
## order FighterStartWinPose picks it with □ △ ✕ ○): LP, RP, LK, RK.
const ARCADE_BUTTONS := {PadState.SQUARE: 0x200, PadState.TRIANGLE: 0x100, PadState.CROSS: 0x40, PadState.CIRCLE: 0x20}
const QUARTER := 0x400

var kind := ""
var sine: PackedInt32Array             ## the arcade's 4096-entry table (stages/arcade_sine.json)
var angles: Array[PackedInt32Array] = []
var positions: Array[PackedInt32Array] = []
var profile: Array[int] = [0, 0, 0, 0]
var accelerate := 0
var reverse := 0
var bob_dir := 0
var yaw_timer := 0
var yaw_dir := 0
var tilt_timer := 0
var tilt_dir := 0
var fa14 := 0
var phase_timer := 0
var flags := 0
var start_yaw := 0
var orbit := 0
var orbit_target := 0
var turn_left := 0
var bank := 0
var speed := 0
var step_size := 0
var turn_step := 0
var turn_rate := 0
var mode := 0
var warmup := 0
var state := 0
var timer := 0
var camera_ref := 0
var camera_last := 0
var slide_x := 0
var slide_z := 0
var axis := 0
var slide := 0
var bob_timer := 0
var radius := 0
var carousel_timer := 0


func _init(prop_kind: String = "", sine_table: PackedInt32Array = PackedInt32Array()) -> void:
	kind = prop_kind
	sine = sine_table
	for p in PROPS:
		angles.append(PackedInt32Array([0, 0, 0]))
		positions.append(PackedInt32Array([0, 0, 0]))


## The arcade's input word for a PlayStation pad's held buttons (the attack buttons only).
static func arcade_buttons(held: int) -> int:
	var out := 0
	for button: int in ARCADE_BUTTONS:
		if held & button:
			out |= ARCADE_BUTTONS[button] as int
	return out


static func s16(v: int) -> int:
	return ((v + 0x8000) & 0xFFFF) - 0x8000


## The round's start: FUN_801E59FC or FUN_801E3DE0 (`buttons`: the first player's held buttons
## in the arcade's input word, `counter` its frame counter; their low bits pick the mode).
func start(buttons: int = 0, counter: int = 0) -> void:
	if kind == CAROUSEL:
		_carousel_start()
	elif kind == HELICOPTER:
		_helicopter_start(buttons, counter)


## One frame: the carousel turns always; the helicopter only on the frames it is shown, with the
## camera's yaw (4096 units, the arcade's 0x802C6BD8).
func step(camera_yaw: int = 0) -> void:
	if kind == CAROUSEL:
		_carousel_step()
	elif kind == HELICOPTER:
		_helicopter_step(camera_yaw)


## The state as verify_arcade_props.py's frame_words: angles, positions, the variables (16-bit,
## the port's field order), the manoeuvre profile.
func words() -> PackedInt32Array:
	var out := PackedInt32Array()
	for a in angles:
		out.append_array(a)
	for v in positions:
		out.append_array(v)
	for v: int in [accelerate, reverse, bob_dir, yaw_timer, yaw_dir, tilt_timer, tilt_dir, fa14,
			phase_timer, flags, start_yaw, orbit, orbit_target, turn_left, bank, speed, step_size,
			turn_step, turn_rate, mode, warmup, state, timer, camera_ref, camera_last, slide_x,
			slide_z, axis, slide, bob_timer, radius, carousel_timer]:
		out.append(s16(v))
	out.append_array(PackedInt32Array(profile))
	return out


# ---- stage 3 ----

func _carousel_start() -> void:
	for p in 3:
		positions[p] = PackedInt32Array([0, -300, 0xC1C])
	angles[0] = PackedInt32Array([0, CAROUSEL_START, 0])
	angles[1] = PackedInt32Array([0, 0, 0])
	angles[2] = PackedInt32Array([0, 0x800, 0])
	angles[3] = PackedInt32Array([0, 0x800, 0])
	positions[3] = PackedInt32Array([0, 0, 0])
	carousel_timer = 0


func _carousel_step() -> void:
	angles[0][1] = s16(angles[0][1] + CAROUSEL_TURN)
	carousel_timer = s16(carousel_timer + 1)
	if carousel_timer == CAROUSEL_FRAMES:
		angles[0][1] = CAROUSEL_START
		carousel_timer = 0


# ---- stage 11 ----

func _helicopter_start(buttons: int, counter: int) -> void:
	angles[0] = PackedInt32Array([s16(0xFF61), 0x71C, 0])
	angles[1] = PackedInt32Array([0, 0, 0])
	angles[2] = PackedInt32Array([0, 0, 0])
	positions[0] = PackedInt32Array([0, s16(0xFE70), RADIUS])
	positions[1] = PackedInt32Array([0, s16(0xFED4), 0])
	positions[2] = PackedInt32Array([0, 0x118, s16(0xFB32)])
	yaw_timer = 0x80
	fa14 = s16(0xFFFE)
	flags = 0
	state = 0
	bob_dir = -1
	bob_timer = 0x20
	yaw_dir = -1
	tilt_timer = 0x20
	tilt_dir = -1
	phase_timer = 0
	start_yaw = 0
	orbit = 0
	orbit_target = 0
	camera_ref = 0
	speed = 0
	warmup = 0
	slide_x = -70
	slide_z = 70
	timer = 0
	axis = 1
	bank = 1
	radius = RADIUS
	reverse = 1
	if buttons & 0x200:
		mode = 0
	elif buttons & 0x100:
		mode = 1
	elif buttons & 0x40:
		mode = 2
	elif buttons & 0x20:
		mode = 3
	else:
		mode = counter & 3


func _helicopter_step(camera_yaw: int) -> void:
	if warmup > WARMUP:
		_watch_camera(s16(camera_yaw))
	else:
		warmup = s16(warmup + 1)
	_fly()


## FUN_801E3F68.
func _watch_camera(yaw: int) -> void:
	angles[0][1] = s16(angles[0][1] & ANGLE_MASK)
	start_yaw = s16(start_yaw & ANGLE_MASK)
	if mode == 0:
		if flags & 2:
			camera_last = yaw
			return
		var turned := yaw - camera_ref if camera_ref < yaw else camera_ref - yaw
		var bits := 7 if camera_ref < yaw else 0x23
		if turned > NEAR_TURN:
			profile.assign(FAR_PROFILE if turned > FAR_TURN else NEAR_PROFILE)
			phase_timer = 0
			flags = (flags | bits) & 0xFFFF
			start_yaw = angles[0][1]
			camera_ref = yaw
			camera_last = yaw
			return
		timer = s16(timer + 1)
		camera_last = yaw
	elif mode >= 1 and mode <= 3:
		timer = s16(timer + 1)
		flags = (flags | 0x1000) & 0xFFFF


## x, z of the helicopter on the orbit at `angle` (sin and cos of −angle), rounded toward zero.
func _orbit_position(angle: int, r: int = RADIUS) -> void:
	positions[0][0] = s16(_scaled(sine[-angle & ANGLE_MASK], r))
	positions[0][2] = s16(_scaled(sine[(-angle + QUARTER) & ANGLE_MASK], r))


static func _scaled(v: int, r: int) -> int:
	var p := v * r
	return (p + 0xFFF if p < 0 else p) >> 12


## FUN_801E40C0.
func _fly() -> void:
	angles[1][1] = s16(angles[1][1] - ROTOR)
	angles[2][0] = s16(angles[2][0] + ROTOR)
	if flags & 1 and mode == 0:
		_manoeuvre(1)
		_manoeuvre(-1)
	else:
		var t := yaw_timer
		if t & 2:
			angles[0][1] = s16(angles[0][1] + yaw_dir)
		yaw_timer = s16(t + 1)
		if yaw_timer == 0x100:
			yaw_timer = 0
			yaw_dir = s16(-yaw_dir)
	if not (flags & 1) or not (flags & 0x1000):
		positions[0][1] = s16(positions[0][1] + (1 if bob_dir > 0 else -1))
		bob_timer = s16(bob_timer + 1)
		if bob_timer == 0x40:
			bob_timer = 0
			bob_dir = s16(-bob_dir)
		angles[0][2] = s16(angles[0][2] + tilt_dir)
		tilt_timer = s16(tilt_timer + 1)
		if tilt_timer == 0x40:
			tilt_timer = 0
			tilt_dir = s16(-tilt_dir)
		if not (flags & 0x1000):
			return
	match mode:
		1:
			_figure_1()
		2:
			_figure_2()
		3:
			_figure_3()


## FUN_801E42DC (side 1) and its mirror FUN_801E4674 (side −1).
func _manoeuvre(side: int) -> void:
	var rise := 4 if side > 0 else 0x20
	var orbit_bit := 8 if side > 0 else 0x40
	var brake_bit := 0x10 if side > 0 else 0x80
	if flags & rise:
		var early := phase_timer < 0x20
		phase_timer = s16(phase_timer + 1)
		if early:
			angles[0][1] = s16(angles[0][1] + 0x10 * side)
			positions[0][1] = s16(positions[0][1] + 8)
		else:
			flags = (flags & ~rise | orbit_bit) & 0xFFFF
			phase_timer = 0
			bank = 0
			speed = 0
	if flags & orbit_bit:
		var top := profile[0]
		var delta := profile[1]
		var brake := profile[2]
		var step := s16((speed >> 1) + 2)
		step_size = step
		var gap := orbit - orbit_target
		if (gap < 0 and -gap < brake) or (gap >= 0 and gap < brake):
			step_size = top
			if step < top:
				speed = s16(speed + 1)
				step_size = step
		else:
			if not (flags & brake_bit):
				turn_rate = profile[3]
				turn_left = (absi(angles[0][1] - start_yaw) + delta) & ANGLE_MASK
				flags = (flags | brake_bit) & 0xFFFF
			speed = s16(speed - 1)
			if speed < 0:
				speed = 0
				flags = flags & ~orbit_bit & 0xFFFF
				orbit_target = s16(orbit_target + delta * side)
		orbit = s16(orbit + step_size * side)
		_orbit_position(orbit)
		if bank < 0x1E:
			angles[0][2] = s16(angles[0][2] - 10 * side)
			bank = s16(bank + 1)
	if flags & brake_bit:
		if phase_timer < 0x20:
			positions[0][1] = s16(positions[0][1] - 8)
		phase_timer = s16(phase_timer + 1)
		if phase_timer > 0x24:
			turn_rate = s16(turn_rate - 1)
		if turn_rate < 0:
			turn_rate = 0
		turn_step = s16(turn_rate * 2 + 2)
		angles[0][1] = s16(angles[0][1] - turn_step * side)
		var left := s16(turn_left - turn_step)
		turn_left = left & 0xFFFF
		if left < 0:
			if side > 0:
				phase_timer = 0
			flags = flags & (0xFFEC if side > 0 else 0xFF7C)
		if bank > 0:
			bank = s16(bank - 1)
			angles[0][2] = s16(angles[0][2] + 10 * side)


## FUN_801E4A0C (mode 1).
func _figure_1() -> void:
	var a := angles[0]
	var t := timer
	match state:
		0, 1:
			if t < (200 if state == 0 else 0x118):
				a[1] = s16(a[1] + 4)
				angles[0] = a
				return
		2:
			step_size = s16(speed >> 3 | 1)
			if t == 500:
				accelerate = 0
			if accelerate == 0:
				if t < 0x212:
					a[2] = s16(a[2] + bank * 6)
				if t < 0x230:
					a[0] = s16(a[0] + 4)
				speed = s16(speed + (1 if reverse == 0 else -1))
				if speed == 0:
					state = 5
					timer = 0
			else:
				if t < 0x1F:
					a[2] = s16(a[2] - bank * 6)
				if t < 0x3D:
					a[0] = s16(a[0] - 1)
				if absi(step_size) < 8:
					speed = s16(speed + (-1 if reverse == 0 else 1))
				else:
					step_size = -8 if reverse == 0 else 8
			var next := orbit + step_size
			orbit = s16(next)
			a[1] = s16(a[1] - step_size)
			angles[0] = a
			_orbit_position(next)
			return
		4:
			if t < 0x118:
				a[1] = s16(a[1] - 4)
				angles[0] = a
				return
		5:
			if t < 0x1E:
				return
			if t < 0xD2:
				a[0] = s16(a[0] - 1)
			if t > 0x137:
				if speed == 0:
					reverse = 1 - reverse
				accelerate = 1
				bank = s16(-bank)
				state = 2
				timer = 0
				angles[0] = a
				return
			a[1] = s16(a[1] + (-4 if reverse else 4))
			angles[0] = a
			return
		_:
			return
	state = 2
	timer = 0
	accelerate = 1


## FUN_801E4E04 (mode 2).
func _figure_2() -> void:
	var a := angles[0]
	var t := timer
	match state:
		0:
			if t < 0x1E:
				a[2] = s16(a[2] - 8)
			if t >= 0x82 and t < 0xA0:
				a[2] = s16(a[2] + 8)
			if t < 0xA0:
				a[1] = s16(a[1] - 0xB)
			if t == 0x8C:
				accelerate = 1
			angles[0] = a
			if t < 0x8D:
				return
			step_size = 0x19 if speed > 1 else 5
			if t == 0x15E:
				accelerate = 0
			if accelerate == 0:
				speed = s16(speed - 1)
				if speed == 0:
					state = 2
					timer = 0
			else:
				speed = s16(speed + 1)
			radius = s16(radius + step_size)
			_orbit_position(orbit, radius)
		2:
			if t < 0x50:
				a[1] = s16(a[1] - 0xB)
				a[2] = s16(a[2] - 3)
			else:
				accelerate = 1
				state = 3
				timer = 0
				orbit = 0
				speed = 0
				a[1] = s16(a[1] - 0xB)
				a[2] = s16(a[2] - 5)
			angles[0] = a
		3:
			if t < 0x14:
				a[1] = s16(a[1] - 0x16)
				a[2] = s16(a[2] - 5)
			else:
				a[1] = s16(a[1] - step_size)
			angles[0] = a
			var step := (s16(speed) >> 3) | 1
			step_size = s16(step)
			if t == 0x578:
				accelerate = 0
			var next_speed := speed
			if accelerate == 0:
				next_speed = speed - 1
				if speed == 1:
					state = 4
					timer = 0
			else:
				next_speed = speed + 1
				if step > 8:
					step_size = 8
					next_speed = speed
			speed = s16(next_speed)
			var next := orbit + step_size
			radius = s16(radius - 10)
			orbit = s16(next)
			if radius < RADIUS:
				radius = RADIUS
			_orbit_position(next, radius)
		4:
			if t < 100:
				a[2] = s16(a[2] + 3)
			if t > 0xA0:
				timer = 0
				state = 5
			angles[0] = a
		5:
			if t < 0x15E:
				a[1] = s16(a[1] - 5)
			elif t < 0x1D6:
				a[2] = s16(a[2] + 2)
			if t < 0x3C:
				a[0] = s16(a[0] + 1)
			if t < 0x78:
				a[2] = s16(a[2] - 2)
			if t > 0x208:
				state = 6
				timer = 0
				accelerate = 1
			angles[0] = a
		6:
			if t < 0x1E:
				a[0] = s16(a[0] - 1)
			if t < 0x50:
				a[2] = s16(a[2] + 4)
			var step := (s16(speed) >> 3) | 1
			step_size = s16(step)
			var next_speed := speed
			if accelerate == 0:
				next_speed = speed - 1
				if speed == 1:
					state = 7
					timer = 0
			else:
				next_speed = speed + 1
				if step > 8:
					step_size = 8
					next_speed = speed
			speed = s16(next_speed)
			orbit = s16(orbit - step_size)
			a[1] = s16(a[1] + step_size)
			angles[0] = a
			_orbit_position(orbit)


## FUN_801E54B4 (mode 3).
func _figure_3() -> void:
	var a := angles[0]
	var pos := positions[0]
	var t := timer
	match state:
		0:
			if t < 0x1E:
				a[0] = s16(a[0] - 1)
			if t < 0x10E:
				pos[1] = s16(pos[1] + 10)
			else:
				state = 1
				timer = 0
				slide = slide_z if axis == 0 else slide_x
		1:
			if t < 0x79:
				var k := 0 if axis == 0 else 2
				pos[k] = s16(pos[k] + slide)
			else:
				timer = 0
				if axis == 0:
					slide_z = s16(-slide_z)
				else:
					slide_x = s16(-slide_x)
				state = 2
				axis = 1 - axis
		2:
			if t < 0x41:
				a[1] = s16(a[1] + 0x20)
			else:
				state = 3
				timer = 0
				orbit = s16(orbit + 0x800)
		3:
			if t >= 0xF1 and t < 0x10E:
				a[0] = s16(a[0] + 1)
			if t < 0x10E:
				pos[1] = s16(pos[1] - 10)
			else:
				state = 4
				timer = 0
				flags &= 0xFFFD
		4:
			if t >= 0x79:
				state = 5
				flags |= 2
				timer = 0
		5:
			if t < 0x32:
				a[0] = s16(a[0] + 3)
				a[1] = s16(a[1] - 1)
				pos[1] = s16(pos[1] - 1)
			elif t < 0x118:
				a[1] = s16(a[1] - 5)
				pos[1] = s16(pos[1] - 6)
			else:
				state = 6
				accelerate = 1
				flags &= 0xFFFD
				timer = 0
		6:
			var step := (s16(speed) >> 4) * 2 + 1
			step_size = s16(step)
			if t == 0x66:
				accelerate = 0
			var next_speed := speed
			if accelerate == 0:
				next_speed = speed - 1
				if speed == 1:
					state = 7
					timer = 0
					flags &= 0xFFFD
					step_size = 5
			else:
				next_speed = speed + 1
				if step > 10:
					step_size = 10
					next_speed = speed
			speed = s16(next_speed)
			orbit = s16(orbit - step_size)
			a[1] = s16(a[1] + step_size)
			angles[0] = a
			positions[0] = pos
			_orbit_position(orbit)
			return
		7:
			if t < 300:
				a[1] = s16(a[1] + 4)
				if t < 0x11E:
					pos[1] = s16(pos[1] + 5)
			if t >= 0xC9 and t < 0x15E:
				a[0] = s16(a[0] - 1)
			if t >= 0x15F:
				state = 8
				flags &= 0xFFFD
				timer = 0
		8:
			if t >= 0x79:
				state = 0
				flags |= 2
				timer = 0
	angles[0] = a
	positions[0] = pos
