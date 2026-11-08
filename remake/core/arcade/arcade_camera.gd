class_name ArcadeCamera
extends CameraDirector
## The arcade program's fight camera (World ver. E1): the director FUN_801D009C with its five sources.
## The framing, the swing and the blends are the PlayStation's with the wider screen's shape; the
## director's state machine, the projection plane per stage, the choice lists, the byte streams and the
## round-end cameras are the arcade's own (flow_camera.md §5, D1, D2, D17–D22, D24–D27, D30, D31).
## Proven by tests/fight/test_arcade_fight_traces.gd.
##
## The arcade's bugs are reproduced: FUN_801D35B0 always picks side 0 (its clip test gets the stack
## addresses of the points), FUN_801CFC28 chooses with the thrower's index as the side.
##
## TODO: FUN_801A4C78's framing view of the round-start frame (FUN_801A43A4), overwritten by the director
## before the frame is drawn: only its step of the camera generator is here.

const STAGE_COUNT := 14
const REEL_H_MIN := 600                     ## FUN_801D4100
const REEL_H_MAX := 2000
const FIGHT_DISTANCE_SCALE := 0x4B840       ## the fight camera's distance per H, over FIGHT_DISTANCE_BASE
const FIGHT_DISTANCE_BASE := 0x9280
const WEIGHT_PER_STEP := 0x20               ## a stream's weight 0…0x80 in 4.12
const STREAM_FULL := 0x80
const STREAM_CHANNELS := 8
const SAMPLE_OF_CHANNEL: Array[int] = [1, 4, 0, 2, 3, 5]    ## channel → eye xyz, target xyz of the sample
const SAMPLE_WEIGHT := 6
const SAMPLE_H := 7
const CHANNEL_H := 6
const CHANNEL_WEIGHT := 7
const SCRIPT_STREAMS := 0x1E                ## scripts from here on are streams …
const SCRIPT_END := 0x232                   ## … up to here
const CHOICE_IDS := 0xD7
const CHOICE_FLAG_MIRROR := 1               ## an entry whose second script is the first one mirrored
const BYTE_CANCEL := 3                      ## move camera bytes
const BYTE_KEEP := 0x11
const BYTE_SKIP := 0x5D                     ## this fighter's target follows on odd pose frames only
const BYTE_NEXT_LIST_END := 0x17            ## below it a throw's next move chooses again (FUN_801D364C)
const BYTE_CHAIN := 0x4D
const BYTE_CHAIN_END := 0x4E
const BYTES_SWITCH: Array[int] = [0x20, 0x50, 0x51, 0x52]   ## FUN_801D2CD0
const PRESET_DRAW := 0xE3                   ## FUN_801C2F6C's bound for a draw whose value is dropped
const THROW_ENDING := 0x23                  ## a stream's fade when the throw is broken
const CANCEL_FADE := 8
const PRESET_WAIT := 0x10
const VICTIM_HOLD := 0x400000               ## FUN_801D4698: the victim's move state
const THROWN_TRANSITION := 0x21
const THROWER_LAST_EVENT := 0xB00
const VICTIM_LAST_EVENT := 0xC00
const HIT_RATING_KO := 3
const KO_DAMAGE := 0x1B
const HIT_H_BASE := 0x3BB
const ARCADE_HALF_WIDTH := 256.0            ## half the 512-pixel display
const ARCADE_HALF_HEIGHT := 120.0 * 4096.0 / ArcadeViewMatrix.ARCADE_ASPECT
const ARCADE_INTRO_ROUND1 := 0x78
const ARCADE_INTRO_LATER := 0x35
const INTRO_OFFSET_FLAG := 6
const INTROS := 10
const START_EYE_Y := -1200                  ## FUN_801D2B54: where sources 0 and 1 start
const START_EYE_Z := -8000
const REPLAY_STYLES := 2
const SWING_RANGE := 0x1E
const SWING_LEAST := 0x19
const WINNER_REACH := 0x1450
const WINNER_REACH_MORE := 0x5A0
const WINNER_ARC := 0x2AB
const WINNER_LOW_EYE := -0x352
const WINNER_HEAD := 0xFA4
const WINNER_GROUND := -0x1B05
const LOSER_REACH := 7000
const LOSER_REACH_MORE := 600
const LOSER_ARC := 0x401
const LOSER_ARC_START := 0x200
const LOSER_EYE_Y := -0x4B0
const LOSER_TARGET_Y := -0x591
const LOSER_DOWN_HEIGHT := 8000
const LOSER_NEAR_HEAD := -400
const LOSER_SPEED_DIV := 0xBF
# The attract's styles, as the table of styles names them; each has a step for its first frame.
const ATTRACT_FIGHT := 10
const ATTRACT_ORBIT := 20
const ATTRACT_CIRCLE := 30
const ATTRACT_SWEEP := 40
const ATTRACT_FRAMES := 0x2D0
const ORBIT_HEIGHT := -0x530
const ORBIT_HEIGHT_FREE := -0x898

var reel_list := 0                          ## 0x8021F8EC
var reel_index := 0                         ## 0x8021F8E8
var stage_mode := 0                 ## 0x802F4C38: 0 free, 1 and 2 the low-ceilinged stages
var stream_cursor := 0              ## 0x802A108C
var stream_last := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])      ## 0x8029E064: last delta per channel
var stream_totals := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])    ## 0x8029E044: the channels' values
var replay_count := 0               ## 0x802A1130: frames of a skipping fighter's target
var attract_counter := 0            ## 0x8021F39C: the attract's fights so far, which pick the first style


func _init(fight_state: FightState) -> void:
	super(fight_state)
	shape.spread = 0x188
	shape.band = 0x44
	shape.top = 0x8C
	shape.top_script = 0xB4
	shape.bottom = 0x9C
	shape.lift = 0x200
	swing_limits = [[0x13, 0x200], [0x14, 0x180], [0x15, 0x80], [0x16, 0x40]]
	view.half_width = ARCADE_HALF_WIDTH
	view.half_height = ARCADE_HALF_HEIGHT
	replay_track = 0
	# BSS: the first round's start tracks before FUN_801CEA84 ever wrote these, and the attract never does.
	skip_side = 0
	cam_script = 0
	stream_frame = 0


# ==== director ====================================================================================

## FUN_801D009C.
func step(f0: FighterState, f1: FighterState) -> void:
	if fight.attract != 0:
		_attract_step(f0, f1)
		return
	match fight.camera_phase:
		CameraPhase.RESET, CameraPhase.INTRO:
			if fight.camera_phase == CameraPhase.RESET:
				reset()
				_init_sources(f0, f1)
				_intro_start(f0, f1)
				replay_on = 0
				cam_script = -1
				stream_frame = -1
				fight.camera_phase = CameraPhase.INTRO
			if _intro_frame(f0, f1):
				fight.camera_phase = CameraPhase.FIGHT
		CameraPhase.FIGHT:
			_fight_frame(f0, f1)
		CameraPhase.WINNER_0, CameraPhase.WINNER_1:
			shake_stop()
			_winner_start(f0 if fight.camera_phase == CameraPhase.WINNER_0 else f1)
			fight.camera_phase = CameraPhase.WINNER
			_winner_step()
		CameraPhase.WINNER:
			_winner_step()
		CameraPhase.LOSER_0, CameraPhase.LOSER_1:
			shake_stop()
			var f := f0 if fight.camera_phase == CameraPhase.LOSER_0 else f1
			_loser_step(f, f.health == 0)


## FUN_801D009C's branch while the attract runs: set up once per fight, then FUN_801D683C.
func _attract_step(f0: FighterState, f1: FighterState) -> void:
	if attract_state == 0:
		replay_on = 0
		reset()
		_attract_style(attract_counter & 3, f0, f1)
		_init_sources(f0, f1)
		attract_state = 1
		attract_counter += 1
	elif attract_state != 1:
		return
	_attract_frame(f0, f1)


## FUN_801D67F4.
func _attract_style(choice: int, f0: FighterState, f1: FighterState) -> void:
	attract_choice = choice
	attract_style = ct.attract_styles[choice]
	_init_sources(f0, f1)


## FUN_801D683C: four styles of 720 frames each. Each style's first frame starts it; the program also has
## a style of FUN_801D66E0 that its table of styles never names.
func _attract_frame(f0: FighterState, f1: FighterState) -> void:
	track(f0, f1, 0)
	var first := false
	match attract_style:
		ATTRACT_FIGHT:
			_camera_fight(f0, f1, 1, _fight_distance())
			first = true
		ATTRACT_FIGHT + 1:
			_camera_fight(f0, f1, 0, _fight_distance())
		ATTRACT_ORBIT:
			_attract_orbit(f0, f1, -1)
			first = true
		ATTRACT_ORBIT + 1, ATTRACT_SWEEP + 1:
			_attract_orbit(f0, f1, 0)
		ATTRACT_CIRCLE:
			_circle(f0, f1, -1)
			first = true
		ATTRACT_CIRCLE + 1:
			_circle(f0, f1, 0)
		ATTRACT_SWEEP:
			_attract_orbit(f0, f1, -2)
			first = true
		_:
			_attract_style(0, f0, f1)
			_use_source(SOURCE_FIGHT)
			return
	if first:
		attract_timer = ATTRACT_FRAMES
		attract_style += 1
	else:
		attract_timer -= 1
		if attract_timer < 0:
			attract_choice = (attract_choice + 1) & 0xFFFF
			attract_style = ct.attract_styles[attract_choice & 3]
	_use_source(SOURCE_FIGHT)


## FUN_801D61F0: source 0 behind the first fighter, looking at the fighters' midpoint (start with `kind` < 0:
## ~kind is 0 level, 1 rising and sweeping sideways).
func _attract_orbit(f0: FighterState, f1: FighterState, kind: int) -> void:
	if kind < 0:
		orbit_kind = ~kind
		orbit_yaw = Fx.s16(f0.facing)
		orbit_frame = 0
	var height := 0
	var sweep := 0
	if orbit_kind == 0:
		height = ORBIT_HEIGHT_FREE if stage_mode == 0 else ORBIT_HEIGHT
	else:
		var sway := FightMath.sin12(Fx.div_trunc(orbit_frame * 0x800, ATTRACT_FRAMES) & 0xFFF, t)
		height = Fx.trunc12(sway * 500) - 0x5DC if stage_mode == 0 else Fx.trunc12(sway * 100) - 0x4B0
		sweep = Fx.div_trunc(orbit_frame * 8000, ATTRACT_FRAMES) - 4000
	orbit_frame += 1
	if f0.hit_done[3] == 0:
		orbit_yaw = 0x400 - Fx.div_trunc(Fx.s16(f0.facing), 16)
	var k := _index64(orbit_yaw)
	var c := FightMath.cos12(k, t)
	var sn := FightMath.sin12(k, t)
	var reach := Fx.div_trunc(_circle_distance() * 0x60, 0x80)
	var x := f0.root_x - Fx.trunc12(reach * c) + Fx.trunc12(sweep * sn)
	var z := f0.root_z - Fx.trunc12(reach * sn) - Fx.trunc12(sweep * c)
	var yaw := CameraMath.atan2_units4096(Fx.div_trunc(f1.root_x + f0.root_x, 2) - x,
		Fx.div_trunc(f1.root_z + f0.root_z, 2) - z, ct)
	var k2 := _index64((yaw - 0x400) * -0x40)
	var along := Fx.trunc12(FightMath.sin12(k2, t) * (f0.root_x - x) + FightMath.cos12(k2, t) * (f0.root_z - z))
	var pitch := CameraMath.atan2_units4096(along, -height, ct)
	sources[SOURCE_FIGHT] = PackedInt32Array([x, height, z, pitch * 0x40 - 0x2400, (yaw - 0x400) * 0x40,
		_stage_row()[0]])


## FUN_801D6004: source 0 circling the fighters at a random pitch and direction (start with `restart` < 0).
func _circle(_f0: FighterState, _f1: FighterState, restart: int) -> void:
	if restart < 0:
		var r := fight.rng.next()
		match stage_mode:
			0:
				circle_pitch = ct.attract_pitches[r & 7] << 6
			1:
				circle_pitch = ct.attract_pitches[r & 3] << 5
			2:
				circle_pitch = ct.attract_pitches[r & 1] << 4
		circle_yaw = (fight.rng.next() & 0xFFF) << 6
		circle_speed = ct.attract_speeds[fight.rng.next() & 1] << 6
	cam_script = -1
	circle_yaw = (circle_yaw + circle_speed) & 0x3FFFF
	_frame_fighters(circle_pitch, circle_yaw, 1, _circle_distance(), SOURCE_FIGHT)


func _circle_distance() -> int:
	return Fx.div_trunc(_fight_distance() * 10, 9)


## FUN_801AE998.
func shake_stop() -> void:
	fight.shake_script = -1
	fight.shake_pos = 0


## FUN_801CEA84: the view stays as it is.
func reset() -> void:
	weights.fill(0)
	prev_weights.fill(0)
	weights[SOURCE_FIGHT] = Fx.ONE
	state = Cinematic.IDLE
	wait = -1
	throw_player = -1
	count_total = -1
	count = -1
	hit_total = -1
	hit_count = -1
	skip_side = -1
	stream_restart = 0
	enabled = 1


## The round's start in FUN_8018A6D0: FUN_801A4C78's step of the generator, FUN_801D2B54, FUN_801D556C(0).
func round_start(f0: FighterState, f1: FighterState) -> void:
	attract_state = 0
	_camera_random()
	_init_sources(f0, f1)
	intro_index = intro_counter % INTROS
	_intro_place(f0, f1)


## The scenes' start (FUN_801E1758, FUN_801E0E30): FUN_801CEA84, FUN_801D67F4, FUN_801D2B54, then the
## reel.
func scene_start(list: int, f0: FighterState, f1: FighterState) -> void:
	reset()
	_attract_style(0, f0, f1)
	_init_sources(f0, f1)
	reel_start(list)


## FUN_801D4100 with a list: its first stream, from nothing, with its first step.
func reel_start(list: int) -> bool:
	reel_list = list
	reel_index = 0
	script_kind = -1
	weights[SOURCE_STREAM] = Fx.ONE
	h_min = REEL_H_MIN
	h_max = REEL_H_MAX
	stream_frame = 0
	enabled = 0
	stream_origin.fill(0)
	preset_yaw = 0
	mirror = 0
	weights[0] = 0
	weights[1] = 0
	stream_rescale = 0
	_reel_stream(_reel_id())
	replay_on = 0                  # FUN_801D70D4 (0x801D41E0)
	return reel_step()


## FUN_801D4100(0): a step of the reel (FUN_801D3D14, then source 2 in use). True once its last stream
## has ended, the frame that stream's end mark was read; the director takes over from the next.
func reel_step() -> bool:
	if script_kind >= 0:
		return true
	preset_yaw = 0
	var s := stream_sample
	var target := PackedInt32Array([s[3], s[4], s[5]])
	var eye := PackedInt32Array([Fx.s16(s[3] + s[0]), Fx.s16(s[4] + s[1]), Fx.s16(s[5] + s[2])])
	sources[SOURCE_STREAM] = _look_source(eye, target, s[SAMPLE_H], s[SAMPLE_H])
	stream_frame += 1
	_stream_sample()
	var over := false
	if s[1] + s[4] >= 0:
		reel_index += 1
		var id := _reel_id()
		over = id < 0
		if not over:
			stream_frame = 0
			_reel_stream(id)
	_use_source(SOURCE_STREAM)
	return over


## FUN_801D3110 with its third argument: the stream has no yaw mode byte at its start.
func _reel_stream(id: int) -> void:
	stream_last.fill(0)
	stream_totals.fill(0)
	stream_cursor = ct.stream_offsets[id - 1]
	_stream_sample()


## FUN_801D3554: the stream of the list's entry, −1 past its end.
func _reel_id() -> int:
	var list := ct.reels[reel_list]
	return -_kind_of(list[reel_index]) if reel_index < list.size() else -1


## FUN_801D0320: the stage's projection plane and the camera's limits.
func _load_stage() -> void:
	var row := _stage_row()
	h = row[0]
	h_min = row[1]
	h_max = row[2]
	stream_rescale = row[3]
	stage_mode = row[4]
	view.h = clampi(h, h_min, h_max)


func _stage_row() -> PackedInt32Array:
	return ct.stage_rows[fight.stage if fight.stage < STAGE_COUNT else 0]


## FUN_801D2B54.
func _init_sources(f0: FighterState, f1: FighterState) -> void:
	_load_stage()
	track(f0, f1, 0)
	track(f0, f1, 0)
	for i in SOURCES:
		var st := source_state[i]
		if i != SOURCE_FIGHT:
			st.cleared_a = 0
			st.cleared_b = 0
			st.depth_step = 0
			st.lateral = 0
			st.depth = 0
			st.moved = 0
		st.speed = 0
		st.angle = 0
		st.phase = 0
		st.error = 0
		st.pitch_target = 0
		st.pitch = 0
		st.pitch_step = 0
		st.frames = 0
	for i in 2:
		sources[i] = PackedInt32Array([0, START_EYE_Y, START_EYE_Z, 0, 0, h])


func _fight_distance() -> int:
	return Fx.div_trunc(h * FIGHT_DISTANCE_SCALE, FIGHT_DISTANCE_BASE)


func _restart_of(source: int) -> int:
	return 1 if prev_weights[source] < 1 else 0


## FUN_801CF9AC: returns true when the intro has faded into the fight camera.
func _intro_frame(f0: FighterState, f1: FighterState) -> bool:
	if enabled == 0:
		return false
	track(f0, f1, 0)
	cam_script = -1
	stream_frame = -1
	weights[SOURCE_STREAM] = _intro_step()
	weights[SOURCE_FIGHT] = Fx.ONE - weights[SOURCE_STREAM]
	if weights[SOURCE_FIGHT] > 0:
		_camera_fight(f0, f1, _restart_of(SOURCE_FIGHT), _fight_distance())
	_blend()
	if weights[SOURCE_STREAM] > 0:
		return false
	state = Cinematic.IDLE
	weights[SOURCE_FIGHT] = Fx.ONE
	weights[SOURCE_STREAM] = 0
	return true


## FUN_801CEB78.
func _fight_frame(f0: FighterState, f1: FighterState) -> void:
	if enabled == 0:
		return
	track(f0, f1, 0)
	if (throw_player == 0 and f0.throw_state == 0) or (throw_player == 1 and f1.throw_state == 0):
		throw_player = -1
	skip_side = _skipping(f0, f1)
	match state:
		Cinematic.IDLE:
			_cinematic_start(f0, f1)
		Cinematic.PRESET:
			_only_script()
			if _thrower_done(f0, f1):
				count = _blend_out(f0, f1)
				count_total = count
				state = Cinematic.PRESET_OUT
		Cinematic.PRESET_IN:
			_preset_in(f0, f1)
		Cinematic.PRESET_OUT:
			weights[SOURCE_SCRIPT] = _fade()
			weights[SOURCE_FIGHT] = Fx.ONE - weights[SOURCE_SCRIPT]
			if count < 0:
				count_total = -1
				count = -1
				state = Cinematic.IDLE
		Cinematic.TRANSITION:
			weights[SOURCE_TRANSITION] = _fade()
			weights[SOURCE_FIGHT] = Fx.ONE - weights[SOURCE_TRANSITION]
			if count < 0:
				state = Cinematic.IDLE
		Cinematic.STREAM:
			if not _stream_frame_state(f0, f1):
				return
		Cinematic.HIT:
			_only_script()
			hit_count -= 1
			if hit_count < 1:
				count = hit_script.blend_out
				count_total = count
				hit_total = -1
				state = Cinematic.HIT_OUT
		Cinematic.HIT_OUT:
			weights[SOURCE_SCRIPT] = _fade()
			weights[SOURCE_FIGHT] = Fx.ONE - weights[SOURCE_SCRIPT]
			if count < 0:
				count_total = -1
				count = -1
				state = Cinematic.IDLE
		_:
			reset()
	if weights[SOURCE_SCRIPT] > 0:
		if hit_total < 0:
			_script_camera(f0, f1, _restart_of(SOURCE_SCRIPT), _fight_distance(), thrower)
		else:
			_hit_camera(f0, f1, _restart_of(SOURCE_SCRIPT), _fight_distance())
	if weights[SOURCE_FIGHT] > 0:
		_camera_fight(f0, f1, _restart_of(SOURCE_FIGHT), _fight_distance())
	_blend()


func _only_script() -> void:
	weights[SOURCE_SCRIPT] = Fx.ONE
	weights[SOURCE_STREAM] = 0
	weights[SOURCE_FIGHT] = 0


## One step of a fade: the weight of what fades out.
func _fade() -> int:
	var w := Fx.div_trunc(count << 12, count_total)
	count -= 1
	return w


## FUN_801CEB2C.
static func _skipping(f0: FighterState, f1: FighterState) -> int:
	if _camera_byte(f0) == BYTE_SKIP:
		return 0
	return 1 if _camera_byte(f1) == BYTE_SKIP else -1


## The side of a camera around fighter `p`: 0 when he is left of the other on screen, 1 when right, by
## the last frame's places when they are level, −1 when these are too.
func _side_for(p: int) -> int:
	var a := targets[p][3]
	var b := targets[1 - p][3]
	if a != b:
		return 0 if a < b else 1
	a = prev_targets[p][3]
	b = prev_targets[1 - p][3]
	if a != b:
		return 0 if a < b else 1
	return -1


## State 1: a throw's camera, else perhaps a hit's.
func _cinematic_start(f0: FighterState, f1: FighterState) -> void:
	cam_script = -1
	count = -1
	hit_total = -1
	if throw_player < 0 and (f0.throw_state > 0 or f1.throw_state > 0):
		thrower = 1 if f0.throw_state < 1 else 0
		side = _side_for(thrower)
		hit_total = -1
		throw_player = thrower
		var r := _throw_start(f0, f1, thrower, side)
		if r < 0:
			cam_script = -1
		elif script_kind < 0:
			wait = -1
			state = Cinematic.STREAM
			count = r
			count_total = r
		else:
			_preset_start(f0, f1)
			wait = PRESET_WAIT
			state = Cinematic.PRESET_IN
			count = r
			count_total = r
		return
	var hit := _hit_choose(f0, f1)
	if hit < 0:
		return
	side = _side_for(hit)
	thrower = hit
	script_kind = 1
	count = hit_script.blend_in
	count_total = count
	if count >= 0:
		state = Cinematic.HIT
		hit_count = hit_script.frames - hit_script.blend_out
		hit_total = hit_count


## State 3: the preset's start waits, then the fight camera fades into it.
func _preset_in(f0: FighterState, f1: FighterState) -> void:
	if wait >= 0:
		if _camera_byte(f0) != BYTE_CANCEL:
			wait -= 1
			if _camera_byte(f1) != BYTE_CANCEL:
				return
		cam_script = -1
		wait = -1
		state = Cinematic.IDLE
		return
	weights[SOURCE_FIGHT] = Fx.div_trunc(count << 12, count_total)
	weights[SOURCE_SCRIPT] = Fx.ONE - weights[SOURCE_FIGHT]
	if not _thrower_done(f0, f1):
		count -= 1
		if count < 0:
			state = Cinematic.PRESET
		return
	count = _blend_out(f0, f1)
	count_total = count
	if weights[SOURCE_SCRIPT] == 0:
		state = Cinematic.IDLE
	elif weights[SOURCE_FIGHT] == 0:
		state = Cinematic.PRESET_OUT
	else:
		_transition_start()


## State 6: returns false when the frame ends with no blend (the camera switched).
func _stream_frame_state(f0: FighterState, f1: FighterState) -> bool:
	var restart := 0
	if stream_restart == 0:
		if wait == -1:
			restart = 1
			wait = -2
	else:
		wait = -3
		stream_restart = 0
	var r := _script_camera(f0, f1, restart, _fight_distance(), thrower)
	if r < 0:
		return false
	weights[SOURCE_STREAM] = Fx.ONE - r * WEIGHT_PER_STEP
	weights[SOURCE_SCRIPT] = 0
	weights[SOURCE_FIGHT] = r * WEIGHT_PER_STEP
	if _camera_byte(f0) == BYTE_CANCEL or _camera_byte(f1) == BYTE_CANCEL:
		count = CANCEL_FADE
		count_total = CANCEL_FADE
		if r == STREAM_FULL:
			state = Cinematic.IDLE
		else:
			_stream_fades()
		wait = -1
		cam_script = -1
	elif (thrower == 0 and f0.throw_state < 0) or (thrower == 1 and f1.throw_state < 0):
		count = THROW_ENDING
		count_total = THROW_ENDING
		_stream_fades()
		wait = -1
		cam_script = -1
	elif wait == -2 and r == 0:
		wait = -3
	elif wait == -3 and r == STREAM_FULL:
		count = _blend_out(f0, f1)
		count_total = count
		state = Cinematic.IDLE
		wait = -1
	return true


func _stream_fades() -> void:
	_transition_start()
	weights[SOURCE_STREAM] = 0


# ==== choosing a camera ===========================================================================

## FUN_801D4454: the script for a camera id; sets the mirror and the choice's index. Modes 1 and 2 have
## their own thresholds and draw through the CPU's generator.
func _choose(id: int, side_flag: int, _player: int) -> int:
	var row: PackedInt32Array = ct.choice_rows[id if id < CHOICE_IDS else 0]
	var r := 0
	match stage_mode:
		0:
			r = fight.rng.next() & 0xFFF
		1:
			r = _ai_random(row[1])
		2:
			r = _ai_random(row[2])
	var k := row[0]
	var index := 0
	while ct.choice_entries[k][1] < r:
		k += 1
		index += 1
	choice_index = index
	return _entry_script(ct.choice_entries[k], side_flag)


func _entry_script(entry: PackedInt32Array, side_flag: int) -> int:
	mirror = 1 if entry[0] & 3 == CHOICE_FLAG_MIRROR and side_flag != 0 else 0
	return entry[3] if side_flag != 0 else entry[2]


## FUN_801D4650: a script's preset, or −stream id, 0 for none.
func _kind_of(value: int) -> int:
	if value >= 0 and value < SCRIPT_STREAMS:
		return ct.script_kinds[value]
	if value >= 0 and value < SCRIPT_END:
		return -(value - (SCRIPT_STREAMS - 1))
	return 0


## FUN_801D4800.
func _throw_start(f0: FighterState, f1: FighterState, thrower_index: int, side_flag: int) -> int:
	if cam_script >= 0:
		reset()
		return -1
	return _chosen_blend_in(f0 if thrower_index == 0 else f1, side_flag, true)


## FUN_801D49A0: the thrower's next camera while one runs.
func _next_camera(thr: FighterState, side_flag: int) -> int:
	if cam_script < 0:
		reset()
		return -1
	return _chosen_blend_in(thr, side_flag, false)


## What FUN_801D4800 and FUN_801D49A0 share: the blend-in of the chosen script, 0 for a stream, −1 for
## none. Only the first keeps the move a preset was chosen for.
func _chosen_blend_in(thr: FighterState, side_flag: int, keep_move: bool) -> int:
	cam_script = _choose(_camera_byte(thr), side_flag, thr.index)
	if cam_script < 0:
		return -1
	script_kind = _kind_of(cam_script)
	if script_kind < 0:
		switch_mode = 0
		script_move = thr.pose_move
		return 0
	if script_kind > 0:
		var blend_in: int = ct.presets[script_kind - 1][0]
		switch_mode = 1 if blend_in < 2 else 0
		if keep_move:
			script_move = thr.pose_move
		return blend_in
	return -1


## FUN_801D2E98.
func _preset_start(f0: FighterState, f1: FighterState) -> void:
	_ai_random(PRESET_DRAW)
	super(f0, f1)


## FUN_801D4BA0.
func _preset_random(index: int) -> Vector2i:
	var p := super(index)
	if p.x < 0 and stage_mode == 2:
		p.x = 0
	if stage_mode != 0:
		p.x = Fx.div_trunc(p.x, 2)
	return p


## FUN_801D4B2C, also for scripts that are not presets (it reads before the table then).
func _blend_out(_f0: FighterState, _f1: FighterState) -> int:
	if script_kind > 0:
		return ct.presets[script_kind - 1][1]
	return ct.blend_outs[-script_kind]


## FUN_801D4698.
func _throw_ends(thr: FighterState, vic: FighterState) -> bool:
	if thr.throw_state < 1 or vic.throw_state >= 0 or _camera_byte(thr) == BYTE_CANCEL:
		return true
	if switch_mode == 1:
		return false
	if vic.pose_move.state & VICTIM_HOLD:
		return true
	var thrower_left := _event_distance(thr, THROWER_LAST_EVENT)
	var victim_left := _event_distance(vic, VICTIM_LAST_EVENT)
	if thrower_left < 0 and victim_left < 0:
		return false
	if maxi(thrower_left, victim_left) != 0:
		return false
	return thr.transition != THROWN_TRANSITION


# ==== script cameras ==============================================================================

## FUN_801D2F4C: source 1 for a preset, or the stream step (returning its weight).
func _script_camera(f0: FighterState, f1: FighterState, restart: int, distance: int, thrower_index: int) -> int:
	var thr := f0 if thrower_index == 0 else f1
	var vic := f1 if thrower_index == 0 else f0
	if script_kind < 0:
		return _stream_step(-script_kind if restart != 0 else 0, thr, vic)
	if script_kind < 1:
		reset()
		return 0
	_frame_fighters(preset_pitch, preset_yaw, restart, _sar(distance * 0x72, 7), SOURCE_SCRIPT)
	if restart != 0 or thr.pose_move == script_move or thr.throw_state <= 0:
		return 0
	if _camera_byte(thr) == BYTE_KEEP:
		return 0
	script_move = thr.pose_move
	if _camera_byte(thr) in BYTES_SWITCH and stage_mode != 2:
		_switch_to_stream(side, thr, vic)
	return 0


## The common part of FUN_801CFEF0, FUN_801CFD44 and FUN_801CFC28 up to the choice.
func _switch_begin(side_flag: int) -> void:
	hit_total = -1
	throw_player = thrower
	side = side_flag


## What the three do when the chosen script is a preset or nothing; returns true on a stream.
func _switch_chosen(r: int) -> bool:
	if r < 0:
		cam_script = -1
	elif script_kind >= 0:
		state = Cinematic.PRESET
		count = 1
		count_total = 1
	else:
		state = Cinematic.STREAM
		count = r
		count_total = r
		return true
	return false


func _switch_end(stream_shown: bool) -> void:
	wait = -1
	weights[SOURCE_FIGHT] = 0
	weights[SOURCE_SCRIPT] = 0 if stream_shown else Fx.ONE
	weights[SOURCE_STREAM] = Fx.ONE if stream_shown else 0
	switch_mode = 1


## A stream starting around the victim at once (FUN_801D3938).
func _stream_around(vic: FighterState, yaw: int) -> void:
	preset_yaw = yaw & 0xFFF
	stream_origin = PackedInt32Array([vic.root_x, vic.pos_y, vic.root_z])
	stream_frame = 0
	_stream_start(-script_kind)
	_stream_sample()
	stream_restart = 1


## FUN_801CFEF0: a preset's next move goes to a stream.
func _switch_to_stream(side_flag: int, thr: FighterState, vic: FighterState) -> void:
	_switch_begin(side_flag)
	var r := _next_camera(thr, side_flag)
	if _switch_chosen(r):
		_stream_around(vic, 0x400 - _facing16(vic))
	_switch_end(false)


## FUN_801CFD44: a stream chains into another, seen from the victim's other side.
func _switch_chain(thr: FighterState, vic: FighterState) -> void:
	_switch_begin(0)
	var r := _next_camera(thr, 0)
	if _switch_chosen(r):
		_stream_around(vic, -(_facing16(vic) + 0xA00))
		mirror = 0
	_switch_end(true)


## FUN_801CFC28: a stream's next move chooses again. The choice's side is the thrower's index.
func _switch_next(side_flag: int, thr: FighterState) -> void:
	_switch_begin(side_flag)
	var r := _next_camera(thr, thrower)
	_switch_chosen(r)
	_switch_end(false)


static func _facing16(f: FighterState) -> int:
	return Fx.div_trunc(f.facing, 16)


# ==== camera streams ==============================================================================

## FUN_801D367C: `id` ≠ 0 starts stream `id`; otherwise the thrower's next move may change it. Returns
## the frame's weight, −1 when the switch went to another camera.
func _stream_step(id: int, thr: FighterState, vic: FighterState) -> int:
	if id == 0:
		var move := thr.pose_move
		if move != script_move and thr.throw_state > 0 and _camera_byte(thr) != BYTE_KEEP:
			var before := script_move.flags & 0xFF
			script_move = move
			var byte := _camera_byte(thr)
			if byte < BYTE_NEXT_LIST_END:
				# FUN_801D35B0: always side 0 (it clips the stack addresses of its points).
				_switch_next(0, thr)
				return -1
			if before == BYTE_CHAIN and byte != BYTE_CHAIN_END:
				_switch_chain(thr, vic)
			_stream_continue(thr)
	else:
		stream_frame = 0
		var yaw_mode := _stream_start(id)
		_stream_sample()
		var k := _facing16(vic)
		match yaw_mode:
			0, 4:
				preset_yaw = (0x400 - k) & 0xFFF
			1:
				preset_yaw = (0x800 - k) & 0xFFF
			2:
				preset_yaw = -k & 0xFFF
			3, 5:
				preset_yaw = -(k + 0x400) & 0xFFF
		stream_origin = PackedInt32Array([vic.pos_x, vic.pos_y, vic.pos_z])
	if script_kind < 0:
		return _stream_view()
	reset()
	# TODO: the game returns its caller's $s4 here (FUN_801D367C); no choice list reaches it with the
	# converted tables' streams.
	return -1


## The same choice's script in the list of the thrower's new camera id (FUN_801D45C0, FUN_801D4650),
## its stream from the start.
func _stream_continue(thr: FighterState) -> void:
	var row: PackedInt32Array = ct.choice_rows[_camera_byte(thr) if _camera_byte(thr) < CHOICE_IDS else 0]
	cam_script = _entry_script(ct.choice_entries[row[0] + choice_index], side)
	script_kind = _kind_of(cam_script)
	if script_kind < 0:
		_stream_start(-script_kind)
		_stream_sample()
	stream_frame = 0


## FUN_801D3110 with an id: the stream from its start; returns its yaw mode (its first byte).
func _stream_start(id: int) -> int:
	stream_last.fill(0)
	stream_totals.fill(0)
	stream_cursor = ct.stream_offsets[id - 1]
	var yaw_mode := ct.streams[stream_cursor]
	stream_cursor += 1
	return yaw_mode


## FUN_801D3110: the next sample into `stream_sample` (eye, target, weight, H): a word of two-bit codes,
## then per channel nothing (0), the last delta again (1), a signed byte (2) or a word (3).
func _stream_sample() -> void:
	var bytes := ct.streams
	var codes := bytes.decode_u16(stream_cursor)
	stream_cursor += 2
	for channel in STREAM_CHANNELS:
		var delta := 0
		match codes & 3:
			1:
				delta = stream_last[channel]
			2:
				delta = bytes.decode_s8(stream_cursor)
				stream_cursor += 1
			3:
				delta = bytes.decode_u16(stream_cursor)
				stream_cursor += 2
		codes >>= 2
		stream_last[channel] = delta & 0xFFFF
		match channel:
			CHANNEL_H:
				stream_totals[channel] += Fx.s16(delta)
				stream_sample[SAMPLE_H] = stream_totals[channel]
			CHANNEL_WEIGHT:
				stream_totals[channel] += Fx.s16(delta)
				stream_sample[SAMPLE_WEIGHT] = stream_totals[channel]
			_:
				stream_totals[channel] = Fx.s16(delta + stream_totals[channel])
				stream_sample[SAMPLE_OF_CHANNEL[channel]] = stream_totals[channel]


## FUN_801D3970: source 2 from the current sample, then the next one. Returns the used sample's weight.
## The eye is stored relative to the target; only that offset is rescaled to the stage's plane.
func _stream_view() -> int:
	var s := stream_sample
	var weight := s[SAMPLE_WEIGHT]
	var plane := s[SAMPLE_H]
	var ex := s[0]
	var ey := s[1]
	var ez := s[2]
	var tx := s[3]
	var ty := s[4]
	var tz := s[5]
	if mirror != 0:
		ez = Fx.s16(-ez)
		tz = Fx.s16(-tz)
	if stream_rescale != 0:
		ex = Fx.div_trunc(ex * h, plane)
		ey = Fx.div_trunc(ey * h, plane)
		ez = Fx.div_trunc(ez * h, plane)
		plane = h
	ex = Fx.s16(tx + ex)
	ey = Fx.s16(ty + ey)
	ez = Fx.s16(tz + ez)
	var sn := FightMath.sin12(preset_yaw & 0xFFF, t)
	var cs := FightMath.cos12(preset_yaw & 0xFFF, t)
	var eye := PackedInt32Array([
		Fx.trunc12(cs * ex - sn * ez) + stream_origin[0],
		ey + stream_origin[1],
		Fx.trunc12(sn * ex + cs * ez) + stream_origin[2]])
	var target := PackedInt32Array([
		Fx.trunc12(cs * tx - sn * tz) + stream_origin[0],
		ty + stream_origin[1],
		Fx.trunc12(sn * tx + cs * tz) + stream_origin[2]])
	sources[SOURCE_STREAM] = _look_source(eye, target, plane, plane)
	stream_frame += 1
	_stream_sample()
	return weight


## FUN_801D05E0: a source at `eye` looking at `target`; the plane is taken as it is.
func _look_source(eye: PackedInt32Array, target: PackedInt32Array, plane: int, _keep: int) -> PackedInt32Array:
	var dx := target[0] - eye[0]
	var dz := target[2] - eye[2]
	var flat := CameraMath.isqrt(Fx.w32(dx * dx + dz * dz))
	var pitch := CameraMath.atan2_units4096(flat, target[1] - eye[1], ct) << 6
	var yaw := (CameraMath.atan2_units4096(dx, dz, ct) - 0x400) * 0x40
	return PackedInt32Array([eye[0], eye[1], eye[2], pitch, yaw, plane])


# ==== framing ======================================================================================

## FUN_801D1344's axis: the direction from the left fighter to the right one.
func _fight_axis(f0: FighterState, f1: FighterState) -> int:
	if f0.screen_x < f1.screen_x:
		return CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)
	return CameraMath.atan2_units4096(targets[0][0] - targets[1][0], targets[0][2] - targets[1][2], ct)


## FUN_801D0F9C has no fixed height.
func _target_height(f: FighterState) -> int:
	return Fx.w32(f.body.joints[2].t[1] - 0x122)


# ==== hit cameras =================================================================================

## FUN_801D4E88.
func _hit_choose(f0: FighterState, f1: FighterState) -> int:
	if f0.hit_clean != 0 and f1.hit_clean != 0:
		return -1
	for i in 2:
		var d := f0 if i == 0 else f1
		var a := f1 if i == 0 else f0
		if d.hit_clean == 0:
			continue
		var rating := _hit_rating(d)
		for row: PackedInt32Array in ct.hit_rows:
			if rating != HIT_RATING_KO and (a.bank_type != row[0] or a.cur_slot != row[1]):
				continue
			if not _hit_pick(row[2], rating):
				return -1
			hit_point = d.hit_slots[0].point.duplicate()
			return i
	hit_script = null
	return -1


static func _hit_rating(d: FighterState) -> int:
	if d.ko != 0 and d.last_damage > KO_DAMAGE:
		return HIT_RATING_KO
	if d.counter_hit != 0:
		return 2
	return 1 if d.close_hit != 0 else 0


## FUN_801D4DA4.
func _hit_pick(list_id: int, rating: int) -> bool:
	var r := fight.rng.next() & 0xFFF
	var records: Array = ct.hit_lists[list_id - HIT_LIST_BASE]
	for record: PackedInt32Array in records:
		if r <= record[0]:
			var chosen: CameraTables.HitScript = ct.hit_scripts[record[1 + rating]]
			if chosen.kind == -1:
				return false
			hit_script = chosen
			return true
	return false


## FUN_801D5078.
func _hit_camera(f0: FighterState, f1: FighterState, restart: int, distance: int) -> void:
	var s := hit_script
	if s.kind != 0 and s.kind != 1:
		reset()
		return
	if restart != 0:
		_ai_random(PRESET_DRAW)
		var axis := _axis_yaw(f0, f1)
		var pitch: int = s.pitches[fight.rng.next() & 3] << 6
		var yaw_offset: int = s.yaws[fight.rng.next() & 3] * (-0x40 if side != 0 else 0x40)
		if stage_mode == 1 or stage_mode == 2:
			pitch = 0
		preset_yaw = axis + yaw_offset
		preset_pitch = pitch
	if s.kind == 0:
		_frame_fighters(preset_pitch, preset_yaw, restart, _sar(distance * 0x72, 7), SOURCE_SCRIPT)
		return
	var k := maxi(Fx.div_trunc(hit_count << 12, hit_total) - 0x400, 0)
	var d := Fx.trunc12((s.start_distance - s.end_distance) * k)
	d = Fx.div_trunc((d + s.end_distance) * h, HIT_H_BASE)
	var sp := FightMath.sin12(_index18(preset_pitch), t)
	var cp := FightMath.cos12(_index18(preset_pitch), t)
	var yi := (CameraMath.sar6(preset_yaw) + 0x400) & 0xFFF
	var eye := PackedInt32Array([
		hit_point[0] - Fx.trunc12(Fx.trunc12(d * FightMath.cos12(yi, t)) * cp),
		hit_point[1] - Fx.trunc12(d * sp),
		hit_point[2] - Fx.trunc12(Fx.trunc12(d * FightMath.sin12(yi, t)) * cp)])
	sources[SOURCE_SCRIPT] = _look_source(eye, hit_point, h, h)


# ==== round intro =================================================================================

## FUN_801D556C(1): the next offset (on stages with a mode, one that fits under their ceilings).
func _intro_start(f0: FighterState, f1: FighterState) -> void:
	while true:
		intro_counter += 1
		intro_index = intro_counter % INTROS
		if stage_mode == 0 or ct.intro_offsets[intro_index][INTRO_OFFSET_FLAG] == 0:
			break
	_intro_place(f0, f1)


func _intro_place(f0: FighterState, f1: FighterState) -> void:
	intro_length = ARCADE_INTRO_ROUND1 if fight.rounds_played == 1 else ARCADE_INTRO_LATER
	intro_timer = intro_length
	_camera_fight(f0, f1, 1, _fight_distance())
	intro_base = sources[SOURCE_FIGHT].duplicate()


## FUN_801D56D4: source 2 of the intro frame; returns its weight.
func _intro_step() -> int:
	var offset: PackedInt32Array = ct.intro_offsets[intro_index]
	var k := FightMath.sin12((Fx.div_trunc(intro_timer << 10, intro_length) + 0xC00) & 0xFFF, t) + Fx.ONE
	var eye := PackedInt32Array([intro_base[0] + Fx.trunc12(offset[0] * k),
		intro_base[1] + Fx.trunc12(offset[1] * k), intro_base[2] + Fx.trunc12(offset[2] * k)])
	var target := PackedInt32Array([intro_base[0] + Fx.trunc12(offset[3] * k),
		intro_base[1] + Fx.trunc12(offset[4] * k), Fx.trunc12(offset[5] * k)])
	var plane := sources[SOURCE_FIGHT][5]
	sources[SOURCE_STREAM] = _look_source(eye, target, plane, plane)
	intro_timer -= 1
	return Fx.ONE if intro_timer > 1 else intro_timer << 12


# ==== round end ===================================================================================

## FUN_801D5970, FUN_801A511C: the winner's camera (style 0, the only one the code ever sets).
func _winner_start(f: FighterState) -> void:
	enabled = 0
	round_end_fighter = f
	var r := _camera_random()
	var a := (((r * WINNER_ARC) >> 16) + WINNER_ARC - _facing16(f)) & 0xFFF
	var reach := Fx.div_trunc(view.h * WINNER_REACH, HIT_H_BASE) + WINNER_REACH_MORE
	winner_a[5] = f.root_x + Fx.trunc12(reach * FightMath.cos12(a, t))
	winner_a[6] = WINNER_LOW_EYE if stage_mode == 0 else _target_height(f)
	winner_a[7] = f.root_z + Fx.trunc12(reach * FightMath.sin12(a, t))
	var v := _winner_aim(f)
	winner_a[0] = v[0]
	winner_a[1] = v[1]
	winner_a[2] = 0


## FUN_801A4FE8: the view at the winner's root, its pitch limited by the head and the floor.
func _winner_aim(f: FighterState) -> PackedInt32Array:
	var eye := PackedInt32Array([winner_a[5], winner_a[6], winner_a[7]])
	var v := _aim(eye, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
	var head := _aim(eye, PackedInt32Array([f.root_x, _target_height(f), f.root_z]))
	var pitch := mini(v[0], head[0] + WINNER_HEAD)
	var ground := _aim(eye, PackedInt32Array([f.root_x, 0, f.root_z]))
	pitch = mini(pitch, ground[0] + WINNER_GROUND)
	if stage_mode != 0 and pitch < 0:
		pitch = 0
	return PackedInt32Array([pitch, v[1]])


## FUN_801D59A4, FUN_801A52A8.
func _winner_step() -> void:
	enabled = 0
	var f := round_end_fighter
	var dx := f.root_x - winner_a[5]
	var dy := f.root_y - winner_a[6]
	var dz := f.root_z - winner_a[7]
	var d := FightMath.sqrt_table(Fx.w32(dx * dx + dy * dy + dz * dz), t)
	if d - Fx.div_trunc(view.h * WINNER_REACH, HIT_H_BASE) > 0:
		winner_a[5] += Fx.div_trunc(dx * 8, d)
		winner_a[6] += Fx.div_trunc(dy * 8, d)
		winner_a[7] += Fx.div_trunc(dz * 8, d)
	var v := _winner_aim(f)
	winner_a[0] += Fx.div_trunc(_s18(v[0] - winner_a[0]), 32)
	winner_a[1] += Fx.div_trunc(_s18(v[1] - winner_a[1]), 32)
	view.pitch = CameraMath.sar6(winner_a[0])
	view.yaw = CameraMath.sar6(winner_a[1])
	view.x = winner_a[5]
	view.y = winner_a[6]
	view.z = winner_a[7]


## FUN_801D59FC: `alive`: the loser keeps health (time up).
func loser_start(f: FighterState, alive: bool) -> void:
	weights[SOURCE_FIGHT] = Fx.ONE
	weights[SOURCE_SCRIPT] = 0
	weights[SOURCE_STREAM] = 0
	if not alive:
		loser_height = 0
		loser_yaw = fight.rng.next() & 0x3F
		return
	var a := (((_camera_random() * LOSER_ARC) >> 16) + LOSER_ARC_START - _facing16(f)) & 0xFFF
	var reach := Fx.div_trunc(h * LOSER_REACH, HIT_H_BASE) + Fx.div_trunc(h * LOSER_REACH_MORE, HIT_H_BASE)
	loser[0] = f.root_x + Fx.trunc12(reach * FightMath.cos12(a, t))
	loser[1] = LOSER_EYE_Y
	loser[2] = f.root_z + Fx.trunc12(reach * FightMath.sin12(a, t))
	loser[3] = f.root_x
	loser[4] = LOSER_TARGET_Y
	loser[5] = f.root_z
	loser[6] = 0


## FUN_801D5F4C. `down`: the loser's health is 0: straight above him (FUN_801D5E94; no closer drawing as
## on the PlayStation); otherwise FUN_801D5BE0.
func _loser_step(f: FighterState, down: bool) -> void:
	enabled = 0
	if down:
		view.pitch = 0x400
		view.yaw = loser_yaw + 0x800 - _facing16(f)
		view.x = f.root_x
		view.y = -loser_height - Fx.div_trunc(h * LOSER_DOWN_HEIGHT, HIT_H_BASE)
		view.z = f.root_z
		return
	var dx := loser[3] - loser[0]
	var dz := loser[5] - loser[2]
	var d := FightMath.sqrt_table(Fx.w32(dx * dx + dz * dz), t)
	if d - Fx.div_trunc(h * LOSER_REACH, HIT_H_BASE) > 0:
		var speed := Fx.div_trunc(h, LOSER_SPEED_DIV)
		loser[0] += Fx.div_trunc(speed * dx, d)
		loser[2] += Fx.div_trunc(speed * dz, d)
	loser[3] += _smooth6(f.root_x - loser[3])
	loser[4] += _smooth6(mini(f.body.joints[2].t[1], LOSER_NEAR_HEAD) - loser[4])
	loser[5] += _smooth6(f.root_z - loser[5])
	if stage_mode == 2 and loser[1] - loser[4] < LOSER_NEAR_HEAD:
		loser[4] = loser[1] - LOSER_NEAR_HEAD
	var a := _aim4096(PackedInt32Array([loser[0], loser[1], loser[2]]), PackedInt32Array([loser[3], loser[4], loser[5]]))
	view.pitch = mini(a[0], 0)
	view.yaw = a[1]
	view.x = loser[0]
	view.y = loser[1]
	view.z = loser[2]


# ==== replay camera ===============================================================================

## FUN_801D6DA8.
func replay_start(f0: FighterState, f1: FighterState) -> void:
	reset()
	_init_sources(f0, f1)
	replay_track = -1
	replay_count = -1
	weights[SOURCE_FIGHT] = 0
	replay_on = 1
	weights[SOURCE_SCRIPT] = Fx.ONE
	weights[SOURCE_STREAM] = 0
	replay_reset = 1
	replay_style = (replay_style + 1) % REPLAY_STYLES
	replay_pitch = 0
	replay_yaw = Fx.s16(CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)) << 6
	replay_distance = _fight_distance() * 2
	if fight.rng.next() & 1:
		replay_yaw += 0x20000
	if replay_style == 0:
		replay_yaw += _ai_random(0xE38E) - 0x71C7
		var sign := -1 if fight.rng.next() & 1 == 0 else 1
		replay_swing = sign * _replay_swing()
		replay_swing_to = -sign * _replay_swing()
	else:
		replay_yaw += _ai_random(0x15555) - 0xAAAA
		replay_swing = 0
		replay_swing_to = 0
	replay_step(f0, f1)


func _replay_swing() -> int:
	return Fx.div_trunc((_ai_random(SWING_RANGE) + SWING_LEAST) * 0x40000, 0x168)


## FUN_801D6C08.
func replay_step(f0: FighterState, f1: FighterState) -> void:
	if replay_on == 0:
		return
	_replay_targets(f0, f1)
	_frame_fighters(replay_pitch, replay_swing + replay_yaw, replay_reset, replay_distance, SOURCE_SCRIPT)
	replay_reset = 0
	replay_swing += Fx.div_trunc(_s18(replay_swing_to - replay_swing), 128)
	replay_distance += Fx.div_trunc((_fight_distance() - replay_distance) * 6, 256)
	_use_source(SOURCE_SCRIPT)
	enabled = 0


## FUN_801D6A44: a skipping fighter's move takes the targets every fourth frame only.
func _replay_targets(f0: FighterState, f1: FighterState) -> void:
	replay_track = _skipping(f0, f1)
	if replay_track < 0:
		replay_count = 0
	else:
		replay_count += 1
	if replay_track >= 0 and replay_count & 3 != 0:
		return
	for k in 2:
		var f := f0 if k == 0 else f1
		targets[k][0] = f.root_x
		targets[k][1] = mini(f.root_y, f.body.joints[2].t[1])
		targets[k][2] = f.root_z
		replay_targets[k] = targets[k][0]
		replay_targets[2 + k] = targets[k][1]
		replay_targets[4 + k] = targets[k][2]
