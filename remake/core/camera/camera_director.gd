class_name CameraDirector
extends RefCounted
## The fight camera (camera.md): `CameraDirector` (0x800633C0) with its five camera sources,
## the two-fighter framing, the round intro, throw presets and camera streams, hit cameras and
## the round-end cameras. Integer port of the game's code (the framing and blending follow the
## verified `tools/research/camera_sim.py`); the state is the director's globals, named after the
## documentation with the address in the comment.
##
## Game bugs 1, 2, 6, 53, 54 and 55 are not reproduced (remake-plan.md#original-bugs).
##
## The demonstration fight (mode 6, or any mode while the attract flag is set) has its own
## camera (FUN_800693E8). Tekken Ball frames the ball too (a third target, at pitch and yaw 0);
## Tekken Force has its own side-scrolling camera (force.ovl, TekkenForce).
##
## The intro counter and the winner style persist across matches, as in the game: GameFlow keeps
## one director for the whole session (the flow traces compare both).

const SOURCE_FIGHT := 0
const SOURCE_SCRIPT := 1           ## throw presets and hit cameras
const SOURCE_STREAM := 2           ## round intro and camera streams
const SOURCE_OUTPUT := 3           ## the blend result
const SOURCE_TRANSITION := 4       ## a frozen view fading into the fight camera
const SOURCES := 5
const DISTANCE := 0x158D           ## the fight camera's distance
const MIN_DISTANCE := 800
const MARGIN := 0x96
const SPREAD_LIMIT := 0x119
const SWING_CAP := 0xDDD0
const SWING_KICK := 0x600
const SWING_LIMITS := [[0x27, 0x200], [0x28, 0x180], [0x29, 0x80], [0x2A, 0x40]]
const STREAM_H := 0x226            ## projection plane of camera stream samples
const STREAM_WEIGHT_FULL := 0x140
const STREAM_BASE := 1 << 40       ## stream scripts: STREAM_BASE | player << 16 | section-8 offset
const PRESET_SCRIPTS := 0x1E
const CAMERA_BYTE_CUT := 9         ## move camera byte that cancels a cinematic camera
const CAMERA_BYTE_KEEP := 0x25
const CAMERA_BYTE_STREAM := 0x63
const CAMERA_BYTE_SKIP := 0x53     ## 'S': bank type 4 tracks its target on odd frames only
const FIRST_BANK_ID := 0x2B        ## camera ids from here on are in the fighter's bank
const REJECTED_IDS := 0x19         ## ids 0x19–0x2A have no camera
const REJECTED_COUNT := 0x12
const HIT_LIST_BASE := 300
const HIT_DISTANCE_H := 0x2EE
const INTRO_ROUND1 := 0x78
const INTRO_LATER := 0x35
const OGRE_CAMERA_ID := 0x4B       ## the Ogre scene's camera id in Ogre's bank
const OGRE_BANK_TYPE := BankType.OGRE


## The director's sub-state within CameraPhase.FIGHT (camera.md#cinematic-cameras).
enum Cinematic {
	IDLE = 1,                  ## fight camera; starts a throw or hit camera
	PRESET = 2,                ## a throw preset at full weight until the throw ends
	PRESET_IN = 3,             ## blending from the fight camera into the preset
	PRESET_OUT = 4,            ## blending back to the fight camera
	TRANSITION = 5,            ## a frozen view fading into the fight camera
	STREAM = 6,                ## a camera stream, weighted by its own channel
	HIT = 8,                   ## a hit camera for its hold time
}


## Per-source framing state (0x800A06D0 + 0x30 · source).
class SourceState:
	var phase := 0                 ## +0x00 yaw swing: 0 idle, 1 swinging
	var moved := 0                 ## +0x02 the camera moved more than about 31 units
	var cleared_a := 0             ## +0x04
	var cleared_b := 0             ## +0x06
	var frames := 0                ## +0x08
	var angle := 0                 ## +0x0C swing offset
	var speed := 0                 ## +0x10
	var pitch := 0                 ## +0x14
	var pitch_target := 0          ## +0x18
	var pitch_step := 0            ## +0x1C
	var error := 0                 ## +0x20 last axis error
	var depth_step := 0            ## +0x24
	var depth := 0                 ## +0x28 vertical back-off
	var lateral := 0               ## +0x2C horizontal back-off

var fight: FightState
var t: FightTables
var ct: CameraTables

# ---- view and projection
var view := CameraView.new(0, 0, 0, 0, 0, 500)   ## g_camera 0x800A8A88 (angles in 4096 units)
var h := 500                       ## 0x800A919C projection plane used by the framing
var h_min := 500                   ## 0x800A919E
var h_max := 500                   ## 0x800A91A0
var stream_rescale := 1            ## 0x800A91A2
var overhead := 0                  ## 0x800B08D4 overhead KO camera: fighters drawn closer

# ---- sources and weights
var sources: Array[PackedInt32Array] = []            ## 0x800A0650: x, y, z, pitch, yaw (18-bit), H
var source_state: Array[SourceState] = []
var weights := PackedInt32Array([0, 0, 0, 0, 0])      ## 0x800A9140 (4.12)
var prev_weights := PackedInt32Array([0, 0, 0, 0, 0]) ## 0x800A914A
var height_term := 0               ## 0x80098754 lift of source 1
var targets: Array[PackedInt32Array] = []            ## 0x800AE170: x, y, z, screen x per fighter
var prev_targets: Array[PackedInt32Array] = []       ## 0x800AE1A0

# ---- director
var state := Cinematic.IDLE        ## 0x800A9138
var enabled := 1                   ## 0x800A913C: the fight camera runs (round-end cameras clear it)
var intro_timer := 0               ## 0x800A913E
var cinematic := 1                 ## 0x800A9154
var thrower := 0                   ## 0x800A9156
var side := 0                      ## 0x800A9158
var wait := -1                     ## 0x800A915A
var count := -1                    ## 0x800A915C
var count_total := -1              ## 0x800A915E
var throw_player := -1             ## 0x800A9160
var switch_mode := 0               ## 0x800A9162: 1 after a switch, or a preset that cuts
var hit_count := -1                ## 0x800A9164
var hit_total := -1                ## 0x800A9166
var cam_script := -1                   ## 0x800A9168: preset (< 0x1E), stream (STREAM_BASE | …) or −1
var script_kind := 0               ## 0x800A916C: preset index + 1, −1 stream, 0 none
var choice_index := 0              ## 0x800A916E
var script_move: MoveRow           ## 0x800A9170: the thrower's move the camera was chosen for
var preset_pitch := 0              ## 0x800A9174
var preset_yaw := 0                ## 0x800A9178
var stream := -1                   ## 0x800A917C: the playing stream script, −1 none
var stream_frames := 0             ## 0x800A9180
var stream_frame := -1             ## 0x800A9182
var mirror := 0                    ## 0x800A9184
var stream_origin := PackedInt32Array([0, 0, 0])      ## 0x800A918C
var stream_restart := 0            ## 0x800A91A6
var skip_side := -1                ## 0x800A91A8
var stream_sample := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])   ## 0x800A07D0: eye, target, weight, H
var hit_script: CameraTables.HitScript    ## 0x800A07E0
var hit_point := PackedInt32Array([0, 0, 0])          ## 0x800A07F0

# ---- round intro
var intro_base := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## 0x800A0850
var intro_length := 0              ## 0x800A0868
var intro_index := 0               ## 0x800A086A
var intro_counter := 0             ## 0x8009892C

# ---- round end
var winner_style := 0              ## 0x800A0844
var round_end_fighter: FighterState   ## 0x800A0840
var winner_a := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])   ## 0x8009EA48: pitch, yaw, roll, -, -, eye
var winner_b := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])   ## 0x8009EA70
var winner_drift := PackedInt32Array([0, 0])                    ## 0x8009EA98
var loser := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])            ## 0x800A0890: eye, target, roll
var loser_height := 0              ## 0x800A08B0
var loser_yaw := 0                 ## 0x800A08B4

# ---- replay camera
var replay_on := 0                 ## 0x800A0875
var replay_reset := 0              ## 0x800A0876
var replay_distance := 0           ## 0x800A0870
var replay_pitch := 0              ## 0x800A087A
var replay_style := 0              ## 0x800A0874
var replay_yaw := 0                ## 0x800A0878
var replay_swing := 0              ## 0x800A087E
var replay_swing_to := 0           ## 0x800A0880
var replay_track := -1             ## 0x800A0838
var replay_targets := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## 0x800A0820: x, y, z per fighter

# ---- the Ogre scene's reel (FUN_800673E4(2))
var reel_stream := -1              ## the stream script of Ogre's camera id 0x4B
var reel_frame := 0                ## its next frame (FUN_800666E0)
var reel_left := 0                 ## 0x800A07C2: samples left before the reel ends
var reel_sample := PackedInt32Array()   ## 0x800A07D0: the raw sample the next step shows

# The demonstration fight's camera (FUN_800693E8).
var attract_state := 0             ## 0x800A913A: 0 set up, 1 running
var attract_choice := 0            ## 0x800A086C: the style counter (0–3)
var attract_style := 0             ## 0x800A086E: the style and its step (10, 11, 20, 21, …)
var attract_timer := 0             ## 0x80098950: frames left in a style
var orbit_kind := 0                ## 0x800A0810
var orbit_frame := 0               ## 0x800A0814
var orbit_yaw := 0                 ## 0x800A0818
var circle_pitch := 0              ## 0x80098944
var circle_yaw := 0                ## 0x80098948 (18-bit)
var circle_speed := 1              ## 0x8009894C


func _init(fight_state: FightState) -> void:
	fight = fight_state
	t = fight.tables
	ct = t.camera
	for i in SOURCES:
		sources.append(PackedInt32Array([0, 0, 0, 0, 0, 0]))
		source_state.append(SourceState.new())
	for i in 2:
		targets.append(PackedInt32Array([0, 0, 0, 0]))
		prev_targets.append(PackedInt32Array([0, 0, 0, 0]))


# ==== director ====================================================================================

## CameraDirector for the fight frame; `fight.camera_phase` is g_cameraPhase.
func step(f0: FighterState, f1: FighterState) -> void:
	skip_side = -1
	if f0.bank_type == BankType.YOSHIMITSU and _camera_byte(f0) == CAMERA_BYTE_SKIP:
		skip_side = 0
	elif f1.bank_type == BankType.YOSHIMITSU and _camera_byte(f1) == CAMERA_BYTE_SKIP:
		skip_side = 1
	if fight.attract != 0 or fight.mode == GameMode.DEMO:
		_attract_step(f0, f1)
		return
	if fight.mode == GameMode.FORCE:
		_force_step(f0, f1)
		return
	match fight.camera_phase:
		CameraPhase.RESET, CameraPhase.INTRO:
			if fight.camera_phase == CameraPhase.RESET:
				reset()
				_init_sources(f0, f1)
				_init_sources(f0, f1)
				stream = -1
				_intro_start(f0, f1)
				cam_script = -1
				stream_frame = -1
				stream = -1
				fight.camera_phase = CameraPhase.INTRO
			if enabled != 0 and _intro_frame(f0, f1):
				fight.camera_phase = CameraPhase.FIGHT
		CameraPhase.FIGHT:
			if enabled != 0:
				_fight_frame(f0, f1)
		CameraPhase.WINNER_0, CameraPhase.WINNER_1:
			fight.shake_script = -1
			_winner_start(f0 if fight.camera_phase == CameraPhase.WINNER_0 else f1)
			fight.camera_phase = CameraPhase.WINNER
			_winner_step()
		CameraPhase.WINNER:
			_winner_step()
		CameraPhase.LOSER_0, CameraPhase.LOSER_1:
			fight.shake_script = -1
			var f := f0 if fight.camera_phase == CameraPhase.LOSER_0 else f1
			_loser_step(f, f.health == 0)


## The demonstration fight's branch of CameraDirector: set up once (CameraReset, FUN_80069388,
## FUN_800661C0, FUN_800669CC, FUN_800699F0), then FUN_800693E8 every frame.
func _attract_step(f0: FighterState, f1: FighterState) -> void:
	if attract_state == 0:
		reset()
		_attract_next_style(f0, f1)
		_init_sources(f0, f1)
		stream = 0
		replay_on = 0
		attract_state = 1
	elif attract_state != 1:
		attract_state = 0
		return
	_attract_frame(f0, f1)


## Tekken Force's branch of CameraDirector: set up once (CameraReset, FUN_80069388, FUN_800661C0,
## FUN_800669CC, FUN_800699F0, then force.ovl's FUN_800B545C; phase 2), then the side-scrolling
## camera (FUN_800B5504) as source 0 every frame.
func _force_step(f0: FighterState, f1: FighterState) -> void:
	if fight.camera_phase == CameraPhase.RESET:
		reset()
		_attract_next_style(f0, f1)
		_init_sources(f0, f1)
		stream = 0
		replay_on = 0
		fight.force.camera_setup(view)
		fight.camera_phase = CameraPhase.FIGHT
	elif fight.camera_phase != CameraPhase.FIGHT:
		return
	sources[SOURCE_FIGHT] = fight.force.camera_frame(view)
	_use_source(SOURCE_FIGHT)


## FUN_80063364: the camera starts again (practice after its replay): CameraReset, the style
## counter and the sources, and the replay's own state.
func restart(f0: FighterState, f1: FighterState) -> void:
	reset()
	_attract_next_style(f0, f1)
	_init_sources(f0, f1)
	stream = 0
	replay_on = 0


## FUN_80069388: the style of the counter (modulo 4) and the sources set up again.
func _attract_next_style(f0: FighterState, f1: FighterState) -> void:
	attract_choice = Fx.s16(_c_rem4(attract_choice))
	attract_style = ct.attract_styles[attract_choice]
	_init_sources(f0, f1)


static func _c_rem4(v: int) -> int:
	return v - Fx.div_trunc(v, 4) * 4


## FUN_800693E8: four styles of 720 frames each: the fight camera (10), an orbit (20, 40) and a
## circling camera (30); each style's first frame starts it.
func _attract_frame(f0: FighterState, f1: FighterState) -> void:
	track(f0, f1, 0)
	var started := false
	match Fx.s16(attract_style - 10):
		0:
			_camera_fight(f0, f1, 1, DISTANCE)
			started = true
		1:
			_camera_fight(f0, f1, 0, DISTANCE)
		10:
			_orbit(f0, -1)
			started = true
		0xB, 0x1F:
			_orbit(f0, 0)
		0x14:
			_circle(f0, f1, -1)
			started = true
		0x15:
			_circle(f0, f1, 0)
		0x1E:
			_orbit(f0, -2)
			started = true
		_:
			_attract_next_style(f0, f1)
	if started:
		attract_timer = 0x2D0
		attract_style = (attract_style + 1) & 0xFFFF
	attract_timer -= 1
	if attract_timer < 0:
		attract_choice = Fx.s16(attract_choice + 1)
		attract_style = ct.attract_styles[_c_rem4(attract_choice)]
	_use_source(SOURCE_FIGHT)


## FUN_80069038: source 0 orbiting behind fighter 0 (start with `kind` < 0: ~kind is the orbit
## kind, 0 level, 1 rising and sweeping sideways), looking at the fighters' midpoint.
func _orbit(f: FighterState, kind: int) -> void:
	var x0 := targets[0][0]
	var z0 := targets[0][2]
	if kind < 0:
		orbit_kind = ~kind
		orbit_yaw = Fx.s16(f.facing)
		orbit_frame = 0
	var height := 0
	var sweep := 0
	if orbit_kind == 0:
		height = -0x62A
	elif orbit_kind == 1 or orbit_kind == 2:
		var sway := FightMath.sin12(Fx.div_trunc(orbit_frame * 0x800, 0x2D0) & 0xFFF, t) * 100
		height = Fx.trunc12(sway) - 0x5AA
		sweep = Fx.div_trunc(orbit_frame * 8000, 0x2D0) - 4000
	orbit_frame += 1
	if f.hit_done[3] == 0:
		orbit_yaw = 0x400 - Fx.div_trunc(Fx.s16(f.facing), 16) if Fx.s16(f.facing) >= 0 \
			else 0x400 - ((Fx.s16(f.facing) + 0xF) >> 4)
	var k := _index64(orbit_yaw)
	var c := FightMath.cos12(k, t)
	var sn := FightMath.sin12(k, t)
	var x := x0 - Fx.trunc12(c * 0x11F5) + Fx.trunc12(sweep * sn)
	var z := z0 - Fx.trunc12(sn * 0x11F5) - Fx.trunc12(sweep * c)
	var yaw := CameraMath.atan2_units4096(Fx.div_trunc(targets[1][0] + x0, 2) - x,
		Fx.div_trunc(targets[1][2] + z0, 2) - z, ct)
	var k2 := _index64((yaw - 0x400) * -0x40)
	var along := Fx.trunc12(FightMath.sin12(k2, t) * (x0 - x) + FightMath.cos12(k2, t) * (z0 - z))
	var pitch := CameraMath.atan2_units4096(along, -height, ct)
	sources[SOURCE_FIGHT] = PackedInt32Array([x, height, z, Fx.s16(pitch) * 64 - 0x1B00, (yaw - 0x400) * 0x40, 500])


## The table index of an angle as the code forms it: (v rounded toward zero to 64ths) & 0xFFF.
static func _index64(v: int) -> int:
	if v < 0:
		v += 0x3F
	return (v >> 6) & 0xFFF


## FUN_80068E90: source 0 circling the fighters at a random pitch and direction (start with
## `restart` < 0), framed at 1.1 times the fight camera's distance.
func _circle(f0: FighterState, f1: FighterState, restart: int) -> void:
	if restart < 0:
		circle_pitch = ct.attract_pitches[fight.rng.next() & 7]
		circle_yaw = (fight.rng.next() & 0xFFF) << 6
		circle_speed = ct.attract_speeds[fight.rng.next() & 1]
	cam_script = -1
	circle_yaw = (circle_yaw + circle_speed) & 0x3FFFF
	_frame_fighters(circle_pitch, circle_yaw, 1, 0x17F2, SOURCE_FIGHT)


## CameraReset (0x80062CF8).
func reset() -> void:
	view.pitch = 0
	view.yaw = 0
	view.x = 0
	view.y = -0x4B0
	view.z = 0
	for i in SOURCES:
		weights[i] = 0
		prev_weights[i] = 0
	weights[0] = Fx.ONE
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
	intro_timer = 0
	cinematic = 1 if fight.mode < GameMode.DEMO or fight.mode > GameMode.FORCE else 0


## The round start (FUN_8002AB68): FUN_800661C0, then FUN_8006867C(0) (the intro offset of the
## counter as it is, the fight camera placed from scratch and kept as the intro's base).
func round_start(f0: FighterState, f1: FighterState) -> void:
	_init_sources(f0, f1)
	intro_index = intro_counter % 10
	intro_length = INTRO_ROUND1 if fight.rounds_played == 1 else INTRO_LATER
	intro_timer = intro_length
	_camera_fight(f0, f1, 1, DISTANCE)
	intro_base = sources[SOURCE_FIGHT].duplicate()


## FUN_800661C0: the projection plane, both target sets, cleared source states and the
## start positions of sources 0 and 1.
func _init_sources(f0: FighterState, f1: FighterState) -> void:
	h = 500
	h_min = 500
	h_max = 500
	stream_rescale = 1
	view.h = 500
	track(f0, f1, 0)
	track(f0, f1, 0)
	for i in SOURCES:
		source_state[i] = SourceState.new()
	for i in 2:
		sources[i] = PackedInt32Array([0, -0x5AA, -0x1F40, 0, 0, h])


## The round intro (phase 1): returns true when it has faded into the fight camera.
func _intro_frame(f0: FighterState, f1: FighterState) -> bool:
	track(f0, f1, 0)
	cam_script = -1
	stream_frame = -1
	stream = -1
	var w := _intro_step()
	weights[0] = Fx.s16(Fx.ONE - w)
	weights[2] = Fx.s16(w)
	if weights[0] > 0:
		_camera_fight(f0, f1, 1 if prev_weights[0] < 1 else 0, DISTANCE)
	_blend()
	if weights[2] > 0:
		return false
	state = Cinematic.IDLE
	return true


## Phase 2: the fight camera with throw, stream and hit cameras (camera.md#cinematic-cameras).
func _fight_frame(f0: FighterState, f1: FighterState) -> void:
	track(f0, f1, 0)
	if (throw_player == 0 and f0.throw_state == 0) or (throw_player == 1 and f1.throw_state == 0):
		throw_player = -1
	match state:
		Cinematic.IDLE:
			_cinematic_start(f0, f1)
		Cinematic.PRESET:
			weights[1] = Fx.ONE
			weights[2] = 0
			weights[0] = 0
			if _thrower_done(f0, f1):
				count = Fx.s16(_blend_out(f0, f1))
				state = Cinematic.PRESET_OUT
				count_total = count
		Cinematic.PRESET_IN:
			if wait < 0:
				weights[0] = Fx.s16(_div(count << 12, count_total))
				weights[1] = Fx.s16(Fx.ONE - weights[0])
				if _thrower_done(f0, f1):
					count = Fx.s16(_blend_out(f0, f1))
					count_total = count
					if weights[1] == 0:
						state = Cinematic.IDLE
					elif weights[0] == 0:
						state = Cinematic.PRESET_OUT
					else:
						_transition_start()
				else:
					count = Fx.s16(count - 1)
					if count < 0:
						state = Cinematic.PRESET
			elif _camera_byte(f0) == CAMERA_BYTE_CUT:
				_cancel()
			else:
				wait = Fx.s16(wait - 1)
				if _camera_byte(f1) == CAMERA_BYTE_CUT:
					_cancel()
		Cinematic.PRESET_OUT:
			var c := count
			count = Fx.s16(count - 1)
			weights[1] = Fx.s16(_div(c << 12, count_total))
			weights[0] = Fx.s16(Fx.ONE - weights[1])
			if count < 0:
				count_total = -1
				count = -1
				state = Cinematic.IDLE
		Cinematic.TRANSITION:
			var c := count
			count = Fx.s16(count - 1)
			weights[4] = Fx.s16(_div(c << 12, count_total))
			weights[0] = Fx.s16(Fx.ONE - weights[4])
			if count < 0:
				state = Cinematic.IDLE
		Cinematic.STREAM:
			if not _stream_frame_state(f0, f1):
				return
		Cinematic.HIT:
			weights[1] = Fx.ONE
			weights[2] = 0
			weights[0] = 0
			hit_count = Fx.s16(hit_count - 1)
			if hit_count < 1:
				hit_total = -1
				state = Cinematic.IDLE
				weights[0] = Fx.ONE
				weights[2] = 0
				weights[1] = 0
				count_total = -1
				count = -1
		_:
			reset()
	if weights[1] > 0:
		if hit_total < 0:
			_script_camera(f0, f1, 1 if prev_weights[1] < 1 else 0, DISTANCE, thrower)
		else:
			_hit_camera(f0, f1, 1 if prev_weights[1] < 1 else 0, DISTANCE)
	if weights[0] > 0:
		_camera_fight(f0, f1, 1 if prev_weights[0] < 1 else 0, DISTANCE)
	_blend()


## State IDLE: a running throw starts its preset or stream camera (CameraThrowStart); otherwise
## CameraHitChoose may start a hit camera.
func _cinematic_start(f0: FighterState, f1: FighterState) -> void:
	cam_script = -1
	count = -1
	hit_total = -1
	if cinematic == 0:
		return
	if throw_player < 0 and (f0.throw_state > 0 or f1.throw_state > 0):
		thrower = 1 if f0.throw_state < 1 else 0
		side = 0 if _screen_order() else 1
		if f0.throw_state < 1:
			side = 1 - side
		hit_total = -1
		throw_player = thrower
		var r := _throw_start(f0, f1, thrower, side)
		if r < 0:
			cam_script = -1
			return
		if script_kind < 0:
			state = Cinematic.STREAM
			wait = -1
		else:
			_preset_start(f0, f1)
			wait = 0x10
			state = Cinematic.PRESET_IN
		count = r
		count_total = r
		return
	var r := _hit_choose(f0, f1)
	if r < 0:
		return
	thrower = r
	side = 0 if _screen_order() else 1
	if r != 0:
		side = 1 - side
	script_kind = 1
	r = hit_script.blend_in
	if r >= 0 and script_kind >= 0:
		state = Cinematic.HIT
		hit_count = hit_script.frames - hit_script.blend_out
		hit_total = hit_count
	count = r
	count_total = r


## State STREAM: the camera stream. Returns false when the director stops for this frame.
func _stream_frame_state(f0: FighterState, f1: FighterState) -> bool:
	var restart := 0
	if stream_restart == 0:
		if wait == -1:
			restart = 1
			wait = -2
	else:
		wait = -3
		stream_restart = 0
	var r := _script_camera(f0, f1, restart, DISTANCE, thrower)
	if r < 0:
		return false
	weights[1] = 0
	weights[0] = Fx.s16(Fx.div_trunc(r << 12, STREAM_WEIGHT_FULL))
	weights[2] = Fx.s16(Fx.ONE - weights[0])
	if _camera_byte(f0) == CAMERA_BYTE_CUT or _camera_byte(f1) == CAMERA_BYTE_CUT:
		_blend_out(f0, f1)
		count_total = 8
		count = 8
		if r == STREAM_WEIGHT_FULL:
			state = Cinematic.IDLE
		else:
			_transition_start()
			weights[2] = 0
		wait = -1
		cam_script = -1
	elif (thrower == 0 and f0.throw_state < 0) or (thrower == 1 and f1.throw_state < 0):
		count_total = 0x23
		count = 0x23
		_transition_start()
		weights[2] = 0
		wait = -1
		cam_script = -1
	elif wait == -2 and r == 0:
		wait = -3
	elif wait == -3 and r == STREAM_WEIGHT_FULL:
		count = Fx.s16(_blend_out(f0, f1))
		state = Cinematic.IDLE
		wait = -1
		count_total = count
		stream = -1
	return true


## A preset is cancelled by a move camera byte 9 while it waits to blend in.
func _cancel() -> void:
	cam_script = -1
	wait = -1
	state = Cinematic.IDLE


## State 5: source 4 freezes the blended view and fades into the fight camera.
func _transition_start() -> void:
	weights[4] = Fx.ONE
	weights[1] = 0
	weights[0] = 0
	state = Cinematic.TRANSITION
	sources[SOURCE_TRANSITION] = sources[SOURCE_OUTPUT].duplicate()


## The side flag's screen order: fighter 0 left of fighter 1. On equal screen positions the
## game compares a third target's screen x with the previous frame's first one (bug #53); the
## remake compares the previous frame's positions.
func _screen_order() -> bool:
	if targets[0][3] == targets[1][3]:
		return prev_targets[0][3] < prev_targets[1][3]
	return targets[0][3] < targets[1][3]


static func _camera_byte(f: FighterState) -> int:
	return f.pose_move.flags & 0xFF


# ==== throw cameras ===============================================================================

## CameraThrowStart (0x80067988): the thrower's camera; its blend-in length, 0 for a stream,
## −1 for none.
func _throw_start(f0: FighterState, f1: FighterState, thrower_index: int, side_flag: int) -> int:
	var thr := f0 if thrower_index == 0 else f1
	if cam_script != -1:
		reset()
		return -1
	return _choose_for(thr, side_flag, thrower_index)


## The common part of CameraThrowStart and FUN_80067B14.
func _choose_for(thr: FighterState, side_flag: int, player: int) -> int:
	cam_script = _choose(_camera_byte(thr), side_flag, player)
	if cam_script == -1:
		return -1
	script_kind = _kind_of(cam_script)
	if script_kind < 0:
		switch_mode = 0
		script_move = thr.pose_move
		return 0
	if script_kind > 0:
		script_move = thr.pose_move
		var blend_in: int = ct.presets[script_kind - 1][0]
		switch_mode = 1 if blend_in < 2 else 0
		return blend_in
	return -1


## CameraChoose (0x80067548): the script for a camera id (−1 none); sets the choice index.
## A random number is drawn even when the id has no camera.
func _choose(id: int, side_flag: int, player: int) -> int:
	var r := fight.rng.next()
	if id < 1:
		id = 1
	if fight.mode == GameMode.PRACTICE or (id - REJECTED_IDS >= 0 and id - REJECTED_IDS < REJECTED_COUNT):
		return -1
	var entries: Array[PackedInt32Array] = ct.choices
	var k := id + 1
	if id >= FIRST_BANK_ID:
		entries = fight.fighters[player].bank.camera_choices
		k = id - FIRST_BANK_ID + 1
	var index := 0
	while (entries[k][1] & 0xFFFF) < (r & 0xFFF):
		k += 1
		index += 1
	mirror = 0
	var value: int = entries[k][2]
	if entries[k][0] != 1 and side_flag != 0:
		var nxt: PackedInt32Array = entries[k + 1]
		if nxt[0] == 0 or (entries[k][1] & 0xFFFF) < (nxt[1] & 0xFFFF):
			mirror = 1
		else:
			value = nxt[2]
	if value < 0 and value != -1:
		value = STREAM_BASE | player << 16 | (value & 0xFFFF)
	choice_index = index
	return value


## The preset index + 1 of a script, −1 for a stream, 0 for anything else (FUN_800677C8).
func _kind_of(value: int) -> int:
	if value >= 0 and value < PRESET_SCRIPTS:
		return ct.preset_index[value]
	return -1 if value >= STREAM_BASE else 0


## FUN_800664A0: a preset's random pitch and yaw offset around the fighters' axis.
func _preset_start(f0: FighterState, f1: FighterState) -> void:
	var yaw := _axis_yaw(f0, f1)
	var p := _preset_random(script_kind - 1)
	if side != 0:
		p.y = -p.y
	preset_yaw = yaw + p.y
	preset_pitch = p.x


## FUN_80067DE4: (pitch << 5, yaw offset << 6) of preset `index`, one random pick each.
func _preset_random(index: int) -> Vector2i:
	var preset: PackedInt32Array = ct.presets[index]
	var pitch: int = preset[2 + (fight.rng.next() & 3)] << 5
	var yaw: int = preset[6 + (fight.rng.next() & 3)] << 6
	return Vector2i(pitch, yaw)


## FUN_80066430: the direction between the targets in 18-bit units, turned by 180° when
## fighter 1 is left of fighter 0 on screen.
func _axis_yaw(f0: FighterState, f1: FighterState) -> int:
	var axis := CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)
	if f1.screen_x <= f0.screen_x:
		axis = (axis + 0x800) & 0xFFF
	return axis << 6


## CameraThrowEnds (0x80067818) for the running thrower (as the director calls it).
func _thrower_done(f0: FighterState, f1: FighterState) -> bool:
	if thrower == 0:
		return _throw_ends(f0, f1)
	if thrower == 1:
		return _throw_ends(f1, f0)
	return false


func _throw_ends(thr: FighterState, vic: FighterState) -> bool:
	if thr.throw_state < 1 or vic.throw_state >= 0:
		return true
	if _camera_byte(thr) == CAMERA_BYTE_CUT:
		return true
	if switch_mode == 1:
		return false
	if vic.pose_move.state & 0x400000:
		return true
	var thrower_left := _event_distance(thr, 0xB00)
	var victim_left := _event_distance(vic, 0xC00)
	if thrower_left < 0 and victim_left < 0:
		return false
	var left := victim_left if thrower_left <= victim_left else thrower_left
	return left == 0 and thr.transition != Transition.THROW


## Frames from the fighter's pose frame to the last event `kind` (high byte) of its move.
static func _event_distance(f: FighterState, kind: int) -> int:
	var move := f.pose_move
	var left := -1
	if move.events < 0:
		return left
	var events := move.bank.events
	var i := move.events
	while events[i] != 0:
		if events[i + 1] & 0xFF00 == kind:
			left = events[i] - f.pose_frame
		i += 2
	return left


## FUN_80067C8C: the blend-out length of the running script, 5 for a cut when the preset
## camera is already close to the fight camera's direction.
func _blend_out(f0: FighterState, f1: FighterState) -> int:
	var v := ct.outside_blend_out
	if cam_script >= 0 and cam_script < PRESET_SCRIPTS:
		v = ct.presets[ct.preset_index[cam_script] - 1][1]
	if v < 2:
		var s := sources[SOURCE_SCRIPT]
		if _within(s[3], 0xE37):
			var axis := CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)
			if f1.screen_x <= f0.screen_x:
				axis = (axis + 0x800) & 0xFFF
			if _within(_s18(s[4] - axis * 0x40), 0xE37):
				v = 5
	return v


## `v + limit < 2 · limit + 1` as the game's unsigned test: −limit ≤ v ≤ limit.
static func _within(v: int, limit: int) -> bool:
	return (v + limit) & 0xFFFFFFFF < 2 * limit + 1


## FUN_80066568: source 1 for a preset (or the stream step for a stream). Returns the
## stream's weight, 0 otherwise.
func _script_camera(f0: FighterState, f1: FighterState, restart: int, distance: int, thrower_index: int) -> int:
	var thr := f0 if thrower_index == 0 else f1
	var vic := f1 if thrower_index == 0 else f0
	if script_kind < 0:
		return _stream_step(cam_script if restart != 0 else 0, thr, vic)
	if script_kind < 1:
		reset()
		return 0
	_frame_fighters(preset_pitch, preset_yaw, restart, Fx.div_trunc(distance * 0x72, 128), SOURCE_SCRIPT)
	if restart != 0 or thr.pose_move == script_move:
		return 0
	if thr.throw_state > 0 and _camera_byte(thr) != CAMERA_BYTE_KEEP:
		var to_stream := thr.bank_type == BankType.PAUL and _camera_byte(thr) == CAMERA_BYTE_STREAM
		script_move = thr.pose_move
		if to_stream:
			_switch_camera(side, thr, vic, true)
	return 0


## FUN_800670E4: a stream (re)start or the switch at the thrower's next move, then the
## stream step (FUN_800669D8). `restart_script` 0: no restart. −1 when the switch went to preset
## framing.
func _stream_step(restart_script: int, thr: FighterState, vic: FighterState) -> int:
	if restart_script == 0:
		var move := thr.pose_move
		if move != script_move and thr.throw_state > 0 and _camera_byte(thr) != CAMERA_BYTE_KEEP:
			script_move = move
			if _camera_byte(thr) < FIRST_BANK_ID:
				# NormalClip of (thrower root, midpoint of the roots, stream eye) in x/z. The game
				# passes the points' stack addresses instead of their values (bug #54), so it
				# always picks the same side; the remake uses the values.
				var ax := Fx.s16(thr.root_x)
				var az := Fx.s16(thr.root_z)
				var bx := Fx.s16(Fx.div_trunc(thr.root_x + vic.root_x, 2))
				var bz := Fx.s16(Fx.div_trunc(thr.root_z + vic.root_z, 2))
				var cx := stream_sample[0]
				var cz := stream_sample[2]
				var clip := Fx.w32(ax * bz + bx * cz + cx * az - ax * cz - bx * az - cx * bz)
				_switch_camera(1 if clip < 0 else 0, thr, vic, false)
				return -1
			cam_script = _bank_script(thr)
			script_kind = _kind_of(cam_script)
			_stream_start(cam_script)
			_stream_sample()
			stream_frame = 0
	else:
		stream_frame = 0
		var yaw_mode := _stream_start(restart_script)
		_stream_sample()
		var k := Fx.div_trunc(vic.heading, 16)
		var yaw := 0
		match yaw_mode:
			0, 4:
				yaw = 0x400 - k
			1:
				yaw = 0x800 - k
			2:
				yaw = -k
			3, 5:
				yaw = -(k + 0x400)
		preset_yaw = yaw & 0xFFF
		stream_origin = PackedInt32Array([vic.pos_x, vic.pos_y, vic.pos_z])
	if script_kind < 0:
		return _stream_view()
	reset()
	# The game returns its caller's $s3 here, 1 (bug #55); the remake returns as the switch does.
	return -1


## FUN_800676CC: the same choice index in the list of the thrower's new camera id (≥ 0x2B).
func _bank_script(thr: FighterState) -> int:
	var entries: Array[PackedInt32Array] = thr.bank.camera_choices
	var k := _camera_byte(thr) - FIRST_BANK_ID + 1 + choice_index
	mirror = 0
	var value: int = entries[k][2]
	if entries[k][0] != 1 and side != 0:
		var nxt: PackedInt32Array = entries[k + 1]
		if nxt[0] == 0 or (entries[k][1] & 0xFFFF) < (nxt[1] & 0xFFFF):
			mirror = 1
		else:
			value = nxt[2]
	if value < 0 and value != -1:
		value = STREAM_BASE | thr.player_index << 16 | (value & 0xFFFF)
	return value


## FUN_8006312C / FUN_8006320C: the camera of the thrower's next move of a multi-part throw.
## `start_stream` (FUN_8006320C) also starts a stream around the victim.
func _switch_camera(side_flag: int, thr: FighterState, vic: FighterState, start_stream: bool) -> void:
	side = side_flag
	hit_total = -1
	throw_player = thrower
	var r := -1
	if cam_script == -1:
		reset()
	else:
		r = _choose_for(thr, side_flag, thr.player_index)
	if r < 0:
		cam_script = -1
	elif script_kind < 0:
		if start_stream:
			preset_yaw = (0x400 - Fx.div_trunc(vic.heading, 16)) & 0xFFF
			stream_origin = PackedInt32Array([vic.root_x, vic.pos_y, vic.root_z])
			stream_frame = 0
			_stream_start(cam_script)
			_stream_sample()
			stream_restart = 1
		state = Cinematic.STREAM
		count = r
		count_total = r
	else:
		state = Cinematic.PRESET
		count_total = 1
		count = 1
		stream = -1
	wait = -1
	weights[1] = Fx.ONE
	weights[0] = 0
	weights[2] = 0
	switch_mode = 1


# ==== camera streams ==============================================================================

## FUN_800666E0 with a script: selects the stream; returns its yaw mode.
func _stream_start(value: int) -> int:
	stream = value
	stream_frame = 0
	var bank := _stream_bank(value)
	var offset := value & 0xFFFF
	stream_frames = bank.camera_frames(offset)
	return (bank.camera_streams[offset] as Vector3i).z


func _stream_bank(value: int) -> MotionBank:
	return fight.fighters[(value >> 16) & 0xFF].bank


## The Ogre scene's camera set-up (FUN_800B4528's first frame, modes.md#match-flow): CameraReset,
## FUN_80069388, FUN_800661C0, then the reel of Ogre's camera id 0x4B (FUN_800673E4(2)): the
## stream state cleared, source 2 at full weight, and the reel's first step at once.
func ogre_start(f0: FighterState, f1: FighterState) -> void:
	reset()
	_attract_next_style(f0, f1)
	_init_sources(f0, f1)
	reel_stream = _choose(OGRE_CAMERA_ID, 0, 0 if f0.bank_type == OGRE_BANK_TYPE else 1)
	script_kind = -1
	weights[SOURCE_STREAM] = Fx.ONE
	stream_frame = 0
	enabled = 0
	stream_origin = PackedInt32Array([0, 0, 0])
	preset_yaw = 0
	mirror = 0
	weights[SOURCE_FIGHT] = 0
	weights[SOURCE_SCRIPT] = 0
	stream_rescale = 1
	# FUN_800666E0 selecting the stream returns its frame count + 1, less one: every sample shows.
	reel_left = Fx.s16(_stream_bank(reel_stream).camera_frames(reel_stream & 0xFFFF))
	reel_frame = 0
	_reel_take()
	replay_on = 0                  # FUN_800699F0
	reel_step()


## FUN_800673E4(0) on the Ogre reel: FUN_80066D00 makes source 2 of the current sample (halved,
## rescaled to the projection plane) and takes the next, then CameraUseSource(2). True on the step
## that shows the stream's last sample: the director takes over from the next frame.
func reel_step() -> bool:
	if script_kind >= 0:
		return true
	preset_yaw = 0
	sources[SOURCE_STREAM] = CameraReel.source_of(reel_sample, h, ct)
	_reel_take()
	reel_left = Fx.s16(reel_left - 1)
	_use_source(SOURCE_STREAM)
	return reel_left <= 0


func _reel_take() -> void:
	reel_sample = _stream_bank(reel_stream).camera_sample(reel_stream & 0xFFFF, reel_frame)
	reel_frame += 1


## FUN_800666E0 sampling: the next frame into `stream_sample` (positions · 20/32, weight / 8
## clamped to 0…320 and 320 from the last frame on, H 550).
## Past the last frame the game decodes beyond the stream; those samples only ever feed an
## unused source (the weight is then 320), so the remake repeats the last frame.
func _stream_sample() -> void:
	var index := stream_frame
	stream_frame = Fx.s16(stream_frame + 1)
	var raw := _stream_bank(stream).camera_sample(stream & 0xFFFF, index)
	var w := Fx.div_trunc(raw[6], 8)
	if w < 0:
		w = 0
	elif w > STREAM_WEIGHT_FULL or stream_frames <= stream_frame:
		w = STREAM_WEIGHT_FULL
	for i in 6:
		stream_sample[i] = Fx.s16(Fx.div_trunc(raw[i] * 0x14, 32))
	stream_sample[6] = w
	stream_sample[7] = STREAM_H


## FUN_800669D8: source 2 from the current sample (placed around the stream origin, turned by
## the stream yaw, mirrored for the other side, rescaled to the projection plane), then the
## next sample. Returns the used sample's weight.
func _stream_view() -> int:
	var s := stream_sample
	var sample_h := s[7]
	var weight := s[6]
	var ex := s[0]
	var ey := s[1]
	var ez := s[2]
	var tx := s[3]
	var ty := s[4]
	var tz := s[5]
	if mirror != 0:
		ez = Fx.s16(-s[2])
		tz = Fx.s16(-s[5])
	var sn := FightMath.sin12(preset_yaw & 0xFFF, t)
	var cs := FightMath.cos12(preset_yaw & 0xFFF, t)
	var plane := sample_h
	if stream_rescale != 0:
		plane = h
		ey = Fx.s16(ty + Fx.s16(Fx.div_trunc((s[1] - ty) * plane, sample_h)))
		ex = Fx.s16(tx + Fx.s16(Fx.div_trunc((s[0] - tx) * plane, sample_h)))
		ez = Fx.s16(tz + Fx.s16(Fx.div_trunc((ez - tz) * plane, sample_h)))
	var eye := PackedInt32Array([
		stream_origin[0] + Fx.trunc12(cs * ex - sn * ez),
		stream_origin[1] + ey,
		stream_origin[2] + Fx.trunc12(sn * ex + cs * ez)])
	var target := PackedInt32Array([
		stream_origin[0] + Fx.trunc12(cs * tx - sn * tz),
		stream_origin[1] + ty,
		stream_origin[2] + Fx.trunc12(sn * tx + cs * tz)])
	sources[SOURCE_STREAM] = _look_source(eye, target, plane, sources[SOURCE_STREAM][5])
	_stream_sample()
	return weight


# ==== hit cameras =================================================================================

## CameraHitChoose (0x80067FD4): the index of the fighter whose clean hit gets a hit camera,
## −1 for none.
func _hit_choose(f0: FighterState, f1: FighterState) -> int:
	if f0.hit_clean != 0 and f1.hit_clean != 0:
		return -1
	for i in 2:
		var d := f0 if i == 0 else f1
		var a := f1 if i == 0 else f0
		if d.hit_clean == 0:
			continue
		var rating := 0
		if d.ko != 0 and d.last_damage > 0x1B:
			rating = 3
		elif d.counter_hit != 0:
			rating = 2
		elif d.close_hit != 0:
			rating = 1
		for row: PackedInt32Array in ct.hit_rows:
			if rating != 3 and (a.bank_type != row[0] or a.cur_slot != row[1]):
				continue
			var r := fight.rng.next() & 0xFFF
			# Weights are cumulative thresholds ending at 0x1000 (FUN_80067ECC), so a record
			# is always chosen.
			for record: PackedInt32Array in ct.hit_lists[row[2] - HIT_LIST_BASE]:
				if r <= record[0]:
					var chosen: CameraTables.HitScript = ct.hit_scripts[record[1 + rating]]
					if chosen.kind == -1:
						return -1
					hit_script = chosen
					hit_point = d.hit_slots[d.best_hit_slot].point.duplicate()
					return i
			return -1
	hit_script = null
	return -1


## FUN_80068244: source 1 for a hit camera.
func _hit_camera(f0: FighterState, f1: FighterState, restart: int, distance: int) -> void:
	var s := hit_script
	if s.kind != 0 and s.kind != 1:
		reset()
		return
	if restart != 0:
		var axis := _axis_yaw(f0, f1)
		var pitch: int = s.pitches[fight.rng.next() & 3] << 6
		var pick := fight.rng.next() & 3
		var yaw_offset: int = s.yaws[pick] * (-0x40 if side != 0 else 0x40)
		preset_yaw = axis + yaw_offset
		preset_pitch = pitch
	if s.kind == 0:
		_frame_fighters(preset_pitch, preset_yaw, restart, Fx.div_trunc(distance * 0x72, 128), SOURCE_SCRIPT)
		return
	var k := _div(hit_count << 12, hit_total) - 0x400
	if k < 1:
		k = 0
	var dist := Fx.trunc12((s.start_distance - s.end_distance) * k)
	dist = Fx.div_trunc((dist + s.end_distance) * h, HIT_DISTANCE_H)
	var sp := FightMath.sin12(_index18(preset_pitch), t)
	var cp := FightMath.cos12(_index18(preset_pitch), t)
	var yi := (CameraMath.sar6(preset_yaw) + 0x400) & 0xFFF
	var eye := PackedInt32Array([
		hit_point[0] - Fx.trunc12(Fx.trunc12(dist * FightMath.cos12(yi, t)) * cp),
		hit_point[1] - Fx.trunc12(dist * sp),
		hit_point[2] - Fx.trunc12(Fx.trunc12(dist * FightMath.sin12(yi, t)) * cp)])
	sources[SOURCE_SCRIPT] = _look_source(eye, hit_point, h, sources[SOURCE_SCRIPT][5])


# ==== round intro =================================================================================

## FUN_8006867C(1): the next intro offset and length; the fight camera placed from scratch.
func _intro_start(f0: FighterState, f1: FighterState) -> void:
	intro_counter += 1
	intro_index = intro_counter % 10
	intro_length = INTRO_ROUND1 if fight.rounds_played == 1 else INTRO_LATER
	intro_timer = intro_length
	_camera_fight(f0, f1, 1, DISTANCE)
	intro_base = sources[SOURCE_FIGHT].duplicate()


## FUN_8006879C: source 2 of the intro frame; returns its weight. The eye is the fight
## camera's plus the offset eased from 2× to 0, looking at the fight camera's x and y at z 0.
func _intro_step() -> int:
	var offset: PackedInt32Array = ct.intro_offset_ball if fight.mode == GameMode.BALL else ct.intro_offsets[intro_index]
	var k := FightMath.sin12((Fx.div_trunc(intro_timer << 10, intro_length) + 0xC00) & 0xFFF, t) + Fx.ONE
	var eye := PackedInt32Array([intro_base[0] + Fx.trunc12(offset[0] * k),
		intro_base[1] + Fx.trunc12(offset[1] * k), intro_base[2] + Fx.trunc12(offset[2] * k)])
	var target := PackedInt32Array([intro_base[0], intro_base[1], 0])
	var src := sources[SOURCE_FIGHT]
	sources[SOURCE_STREAM] = _look_source(eye, target, src[5], src[5])
	intro_timer = Fx.s16(intro_timer - 1)
	return Fx.ONE if intro_timer > 0x10 else intro_timer << 8


# ==== round end ===================================================================================

## FUN_80068998: the winner camera of a round that does not end the match; the two styles
## alternate.
func _winner_start(f: FighterState) -> void:
	enabled = 0
	winner_style = (winner_style + 1) & 1
	round_end_fighter = f
	if winner_style == 0:
		_winner_a_start(f)
	else:
		_winner_b_start(f)


func _winner_step() -> void:
	enabled = 0
	if winner_style == 0:
		_winner_a_step(round_end_fighter)
	else:
		_winner_b_step(round_end_fighter)


## FUN_800466F8: style A starts 3953 units away at a random angle 60°–120° off the facing.
func _winner_a_start(f: FighterState) -> void:
	var r := _camera_random()
	var a := (((r * 0x2AB) >> 16) + 0x2AB - Fx.div_trunc(f.facing, 16)) & 0xFFF
	var eye := PackedInt32Array([f.root_x + Fx.trunc12(FightMath.cos12(a, t) * 0xF71), -0x352,
		f.root_z + Fx.trunc12(FightMath.sin12(a, t) * 0xF71)])
	winner_a = _winner_view(f, eye, winner_a)


## FUN_80046854: the eye approaches by 8 units per frame while farther than 2513; the view
## turns with 1/32 smoothing.
func _winner_a_step(f: FighterState) -> void:
	var dx := f.root_x - winner_a[5]
	var dy := f.root_y - winner_a[6]
	var dz := f.root_z - winner_a[7]
	var d := FightMath.sqrt_table(Fx.w32(dx * dx + dy * dy + dz * dz), t)
	if d - 0x9D1 > 0:
		winner_a[5] += Fx.div_trunc(dx * 8, d)
		winner_a[6] += Fx.div_trunc(dy * 8, d)
		winner_a[7] += Fx.div_trunc(dz * 8, d)
	var aim := _winner_view(f, winner_a.slice(5, 8), PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	winner_a[0] += Fx.div_trunc(_s18(aim[0] - winner_a[0]), 32)
	winner_a[1] += Fx.div_trunc(_s18(aim[1] - winner_a[1]), 32)
	_use_round_end_view(winner_a, true)


## FUN_80046A38: style B picks a lateral offset, a forward distance and a height, and a side.
func _winner_b_start(f: FighterState) -> void:
	var lateral: int = ct.winner_lateral[(_camera_random() * 3) >> 16]
	var forward: int = ct.winner_forward[(_camera_random() * 3) >> 16]
	var height: int = ct.winner_height[(_camera_random() * 3) >> 16]
	winner_b[6] = height
	if height < -0x79D:
		forward = ct.winner_forward[2]
	var a := (0x400 - Fx.div_trunc(f.facing, 16)) & 0xFFF
	var sn := FightMath.sin12(a, t)
	var cs := FightMath.cos12(a, t)
	winner_drift[0] = Fx.s16(Fx.div_trunc(-cs, 512))
	winner_drift[1] = Fx.s16(Fx.div_trunc(-sn, 512))
	var fx := forward * sn
	var fz := forward * -cs
	if _camera_random() < 0x8000:
		fx = -fx
		fz = -fz
	winner_b[5] = f.root_x + Fx.trunc12(lateral * cs + fx)
	winner_b[7] = f.root_z + Fx.trunc12(lateral * sn + fz)
	winner_b = _winner_view(f, winner_b.slice(5, 8), winner_b)


## FUN_80046CB8: the eye drifts backwards along the facing, is pushed out to 2308 units, yaw
## follows with 1/32 and pitch with 1/16 smoothing, and the eye sinks when looking up.
func _winner_b_step(f: FighterState) -> void:
	winner_b[5] += winner_drift[0]
	winner_b[7] += winner_drift[1]
	var dx := f.root_x - winner_b[5]
	var dy := f.root_y - winner_b[6]
	var dz := f.root_z - winner_b[7]
	var push := 0x904 - FightMath.sqrt_table(Fx.w32(dx * dx + dy * dy + dz * dz), t)
	if push > 0:
		var flat := FightMath.sqrt_table(Fx.w32(dx * dx + dz * dz), t)
		winner_b[5] -= Fx.div_trunc(_div(push * dx, flat), 16)
		winner_b[7] -= Fx.div_trunc(_div(push * dz, flat), 16)
	var aim := _winner_view(f, winner_b.slice(5, 8), PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	winner_b[0] += Fx.div_trunc(_s18(aim[0] - winner_b[0]), 32)
	winner_b[1] += Fx.div_trunc(_s18(aim[1] - winner_b[1]), 16)
	if winner_b[0] > 0:
		var floor_y := Fx.trunc12(FightMath.sin12(_index18(winner_b[0]), t) * -0x1D4C)
		if floor_y < winner_b[6]:
			winner_b[6] += Fx.div_trunc(floor_y - winner_b[6], 16)
	_use_round_end_view(winner_b, true)


## FUN_80046508: the view from `eye` at the winner's root, its pitch limited by the head and
## the floor, the eye pushed out to 5800 units when closer (into `out`).
func _winner_view(f: FighterState, eye: PackedInt32Array, out: PackedInt32Array) -> PackedInt32Array:
	var root := PackedInt32Array([f.root_x, f.root_y, f.root_z])
	var v := _aim(eye, root)
	out[0] = v[0]
	out[1] = v[1]
	out[2] = 0
	out[5] = eye[0]
	out[6] = eye[1]
	out[7] = eye[2]
	var head := _aim(eye, PackedInt32Array([f.root_x, f.body.joints[2].t[1] - 0x122, f.root_z]))
	out[0] = mini(out[0], head[0] + 0xFA4)
	var ground := _aim(eye, PackedInt32Array([f.root_x, 0, f.root_z]))
	out[0] = mini(out[0], ground[0] - 0x1B05)
	var ex := out[5] - f.root_x
	var ez := out[7] - f.root_z
	if Fx.w32(ex * ex + ez * ez) < 0x2014E40:
		var i := _index18(out[1])
		out[5] = f.root_x + Fx.trunc12(FightMath.sin12(i, t) * 0x16A8)
		out[7] = f.root_z - Fx.trunc12(FightMath.cos12(i, t) * 0x16A8)
	return out


## FUN_80046284: pitch (signed) and yaw − 90° of the eye-to-target vector, in 18-bit units.
func _aim(eye: PackedInt32Array, target: PackedInt32Array) -> PackedInt32Array:
	var a := _aim4096(eye, target)
	return PackedInt32Array([a[0] << 6, a[1] << 6])


## FUN_80046180: the same in 4096 units.
func _aim4096(eye: PackedInt32Array, target: PackedInt32Array) -> PackedInt32Array:
	var dx := target[0] - eye[0]
	var dz := target[2] - eye[2]
	var flat := CameraMath.isqrt(Fx.w32(dx * dx + dz * dz))
	var pitch := CameraMath.atan2_units4096(flat, target[1] - eye[1], ct) & 0xFFF
	if pitch & 0x800:
		pitch -= 0x1000
	return PackedInt32Array([pitch, CameraMath.atan2_units4096(dx, dz, ct) - 0x400])


## FUN_800463A4 (18-bit angles) / FUN_80046458 (4096 units): a round-end view becomes the
## camera. The projection plane is left as it is.
func _use_round_end_view(v: PackedInt32Array, angles18: bool) -> void:
	view.pitch = CameraMath.sar6(v[0]) if angles18 else v[0]
	view.yaw = CameraMath.sar6(v[1]) if angles18 else v[1]
	view.x = v[5]
	view.y = v[6]
	view.z = v[7]


## FUN_80068A44: the loser camera of the match-deciding round, set up at the result (by the
## round flow). `alive`: time out (the loser keeps health); otherwise the overhead KO view.
func loser_start(f: FighterState, alive: bool) -> void:
	weights[0] = Fx.ONE
	weights[1] = 0
	weights[2] = 0
	if not alive:
		loser_height = 0
		loser_yaw = (fight.rng.next() & 0x7F) - 0x40
		return
	var a := (((_camera_random() * 0x401) >> 16) + 0x200 - Fx.div_trunc(f.heading, 16)) & 0xFFF
	var reach := 0x19C4 if f.bank_type == BankType.KUMA else 0xF8A
	loser[0] = f.root_x + Fx.trunc12(FightMath.cos12(a, t) * reach)
	loser[2] = f.root_z + Fx.trunc12(FightMath.sin12(a, t) * reach)
	loser[1] = -0x5DC
	loser[3] = f.root_x
	loser[4] = -0x591
	loser[5] = f.root_z
	loser[6] = 0


## FUN_80068C44: the loser camera each frame. `down`: the loser's health is 0.
func _loser_step(f: FighterState, down: bool) -> void:
	enabled = 0
	if not down:
		var dx := loser[3] - loser[0]
		var dz := loser[5] - loser[2]
		var d := FightMath.sqrt_table(Fx.w32(dx * dx + dz * dz), t)
		var left := d - (0x188A if f.bank_type == BankType.KUMA else 0xE50)
		if left > 0:
			loser[0] += _div(dx * 2, d)
			loser[2] += _div(dz * 2, d)
		loser[3] += _smooth6(f.root_x - loser[3])
		loser[4] += _smooth6(f.body.joints[2].t[1] - loser[4])
		loser[5] += _smooth6(f.root_z - loser[5])
		var a := _aim4096(PackedInt32Array([loser[0], loser[1], loser[2]]), PackedInt32Array([loser[3], loser[4], loser[5]]))
		view.pitch = a[0]
		view.yaw = a[1]
		view.x = loser[0]
		view.y = loser[1]
		view.z = loser[2]
		return
	if fight.mode != GameMode.BALL:
		overhead = 1
	view.pitch = 0x400
	view.yaw = loser_yaw + 0x800 - Fx.div_trunc(f.heading, 16)
	view.x = f.root_x
	view.y = -0x1EAD - loser_height
	view.z = f.root_z


## `(v · 6) / 128` rounded toward zero.
static func _smooth6(v: int) -> int:
	return Fx.div_trunc(v * 6, 128)


## One step of the camera generator 0x800A95F4; its upper half.
func _camera_random() -> int:
	fight.camera_rng = ((fight.camera_rng + 1) * 0x10DCD) & 0xFFFFFFFF
	return fight.camera_rng >> 16


# ==== replay camera ===============================================================================

## FUN_80069824 at the replay's start: an orbit from a random side (two styles alternate).
func replay_start(f0: FighterState, f1: FighterState) -> void:
	reset()
	_init_sources(f0, f1)
	replay_track = -1
	replay_on = 1
	weights[0] = 0
	weights[1] = Fx.ONE
	weights[2] = 0
	replay_reset = 1
	replay_distance = 0x2B1A
	replay_pitch = 0
	replay_style = (replay_style + 1) & 1
	var axis := CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)
	replay_yaw = Fx.s16(axis << 6)
	fight.rng.next()
	if replay_style == 0:
		replay_yaw = Fx.s16(replay_yaw - 0x71C7 + _ai_random(0xE38E))
		var a := (_ai_random(0x1E) + 0x19) * 0x40000
		replay_swing = Fx.s16(Fx.div_trunc(a, 360))
		var b := (_ai_random(0x1E) + 0x19) * 0x40000
		replay_swing_to = Fx.s16(-Fx.div_trunc(b, 360))
		if fight.rng.next() & 1:
			replay_swing = Fx.s16(-replay_swing)
			replay_swing_to = Fx.s16(-replay_swing_to)
	else:
		var s := _ai_random(0x15555)
		replay_swing_to = 0
		replay_swing = 0
		replay_yaw = Fx.s16(replay_yaw + 0x5556 + s)
	replay_step(f0, f1)


## FUN_800569D0: a random value below `n` from rand() and the AI generator 0x800AE168.
func _ai_random(n: int) -> int:
	var r := fight.rng.next()
	var v := Fx.w32(n * ((r + fight.ai_rng) & 0x7FFF))
	fight.ai_rng = (fight.ai_rng * 5 + 3) & 0xFFFFFFFF
	if v < 0:
		v += 0x7FFF
	return v >> 15


## FUN_800696FC: the replay camera each frame: source 1 framing both fighters from the orbit
## yaw, swinging and closing in slowly.
func replay_step(f0: FighterState, f1: FighterState) -> void:
	if replay_on == 0:
		return
	_replay_targets(f0, f1)
	_frame_fighters(replay_pitch, replay_swing + replay_yaw, replay_reset, replay_distance, SOURCE_SCRIPT)
	var d := _s18(replay_swing_to - replay_swing)
	replay_reset = 0
	replay_swing = Fx.s16(replay_swing + Fx.div_trunc(d, 128))
	replay_distance = Fx.s16(replay_distance + Fx.div_trunc((0x113D - replay_distance) * 6, 256))
	_use_source(SOURCE_SCRIPT)
	enabled = 0


## FUN_800695EC: the replay's targets, the roots (at head height at most), taken every fourth
## frame while bank type 4 tracks on odd frames only ('S' camera byte).
func _replay_targets(f0: FighterState, f1: FighterState) -> void:
	var skip := -1
	if f0.bank_type == BankType.YOSHIMITSU and _camera_byte(f0) == CAMERA_BYTE_SKIP:
		skip = 0
	elif f1.bank_type == BankType.YOSHIMITSU and _camera_byte(f1) != CAMERA_BYTE_SKIP:
		skip = -1
	elif f1.bank_type == BankType.YOSHIMITSU:
		skip = 1
	if skip < 0:
		replay_track = -1
	else:
		var was := replay_track
		replay_track = Fx.s16(replay_track + 1)
		if was < 0:
			replay_track = 0
	for k in 2:
		var f := f0 if k == 0 else f1
		if replay_track < 0 or replay_track & 3 == 0:
			replay_targets[k] = f.root_x
			replay_targets[4 + k] = f.root_z
			replay_targets[2 + k] = mini(f.root_y, f.body.joints[2].t[1])
			targets[k][0] = replay_targets[k]
			targets[k][1] = replay_targets[2 + k]
			targets[k][2] = replay_targets[4 + k]


# ==== fight camera ================================================================================

## CameraTrackFighters (0x80064944): one target per fighter (the move anchor, or the root while
## launched, in throws or for move flag bit 29; head height − 0x122).
func track(f0: FighterState, f1: FighterState, force_root: int) -> void:
	if f0.throw_state != 0 or f1.throw_state != 0:
		force_root = 1
	for k in 2:
		var f := f0 if k == 0 else f1
		prev_targets[k] = targets[k].duplicate()
		if skip_side != k or f.pose_frame & 1:
			var tg := targets[k]
			if not f.pose_move.flags & MoveFlag.TRACK_ROOT and f.throw_state == 0 and force_root == 0:
				tg[0] = f.pos_x
				tg[2] = f.pos_z
			else:
				tg[0] = f.root_x
				tg[2] = f.root_z
			tg[3] = f.screen_x
			tg[1] = Fx.w32(f.body.joints[2].t[1] - 0x122)
			if f.cur_slot == 2 and f.bank_type == BankType.YOSHIMITSU:
				tg[1] = -0x6B8
	var a := targets[0]
	var b := targets[1]
	if a[0] == b[0] and a[2] == b[2]:
		b[0] = a[0] + 1
		b[2] = a[2] + 1
		a[0] -= 1
		a[2] -= 1


## CameraFight (0x8006636C): source 0 from the yaw spring and the framing.
func _camera_fight(f0: FighterState, f1: FighterState, restart: int, distance: int) -> void:
	var spring := _yaw_spring(f0, f1, restart, SOURCE_FIGHT)
	var pitch := source_state[SOURCE_FIGHT].pitch
	var yaw := spring.y
	if fight.mode == GameMode.BALL:
		pitch = 0
		yaw = 0
	_frame_fighters(pitch, yaw, spring.x, distance, SOURCE_FIGHT)


## CameraYawSpring (0x80064AF8): (reset for the framing, yaw).
func _yaw_spring(f0: FighterState, f1: FighterState, restart: int, src: int) -> Vector2i:
	var st := source_state[src]
	var cam_yaw := sources[src][4]
	var axis := CameraMath.atan2_units4096(targets[1][0] - targets[0][0], targets[1][2] - targets[0][2], ct)
	if f1.screen_x <= f0.screen_x:
		axis = (axis + 0x800) & 0xFFF
	var err := _s18(Fx.w32(axis * 0x40 - cam_yaw))
	var sign := signi(err)
	err = absi(err)
	if restart != 0:
		st.angle = 0
		st.speed = 0
		st.pitch_target = 0
		st.pitch = 0
		st.pitch_step = 0
		st.cleared_a = 0
		st.cleared_b = 0
		return Vector2i(restart, Fx.w32(axis * 0x40))
	if src != 0 or err > 0x1AAAA or fight.fighter_distance < 200:
		st.cleared_a = 0
		st.cleared_b = 0
		return Vector2i(0, cam_yaw)
	var offset := _swing(st, f0, f1, err, sign)
	_pitch_follow(st, err)
	return Vector2i(0, Fx.w32(cam_yaw + offset))


## The yaw swing of the fight source: a kick when the camera falls behind the fighters' axis, then
## a damped spring within ±SWING_CAP (narrower while a move's camera byte asks for it); returns
## the yaw offset.
func _swing(st: SourceState, f0: FighterState, f1: FighterState, err: int, sign: int) -> int:
	var phase := st.phase
	var frames := st.frames
	var angle := st.angle
	var speed := st.speed
	var offset := 0
	if phase == 0:
		frames = 0 if err < 0xE38 else Fx.s16(frames + 1)
		if frames > 0:
			phase = 1
			frames = 0
			speed = Fx.w32(speed + sign * SWING_KICK)
	elif phase == 1:
		if err < 0x38E4:
			angle = Fx.w32(angle - _sar(Fx.w32(angle * 0xE), 7))
			speed = Fx.w32(speed - _half(speed) + sign * 0x300)
			if err < 0xE39:
				speed = Fx.w32(speed - _half(speed))
				frames = Fx.s16(frames + 1)
				if frames >= 0x20:
					angle = 0
					phase = 0
					frames = 0
			else:
				frames = 0
		else:
			speed = Fx.w32(speed + sign * SWING_KICK)
		angle = Fx.w32(angle + speed)
		var limit := _swing_limit(_camera_byte(f0), _camera_byte(f1))
		var hi := SWING_CAP
		var lo := -SWING_CAP
		if limit >= 1:
			hi = _sar(limit * SWING_CAP, 8)
			lo = _sar(-limit * SWING_CAP, 8)
		if hi < angle:
			angle = hi
			speed = Fx.w32(speed - SWING_KICK)
		elif angle < lo:
			angle = lo
			speed = Fx.w32(speed + SWING_KICK)
		offset = _sar(angle, 6)
	st.phase = phase
	st.frames = frames
	st.angle = angle
	st.speed = speed
	return offset


## The swing limit (in 1/256 of SWING_CAP) asked for by either fighter's move camera byte, or −1.
static func _swing_limit(b0: int, b1: int) -> int:
	for entry: Array in SWING_LIMITS:
		if b0 == entry[0] or b1 == entry[0]:
			return entry[1] as int
	return -1


## The pitch target grows with the yaw error; the fight source's pitch follows it while it moves.
func _pitch_follow(st: SourceState, err: int) -> void:
	if err < 0x38E3:
		st.pitch_target = 0
	else:
		var q := _sar(Fx.div_trunc(Fx.w32((err - 0x38E3) * 0x1000), 0xC71D), 8)
		st.pitch_target = Fx.trunc12(Fx.w32(FightMath.sin12(q, t) * 0x44440))
	var s0 := source_state[SOURCE_FIGHT]
	if s0.moved == 0:
		s0.pitch_step = 0
	else:
		var step := clampi(_sar(Fx.w32(s0.pitch_target - s0.pitch), 4), -0x100, 0x100)
		s0.pitch_step = step
		s0.pitch = Fx.w32(s0.pitch + step)
	s0.error = err


## The working state of one CameraFrameFighters call: the targets in view space around the orbit
## centre (`u` across, `v` up, `z` along the view, `depth` along the ground) and the camera's
## offsets from it (`lateral` across, `back` along the view, `vertical` up).
class Framing:
	var pitch := 0
	var yaw := 0
	var distance := 0
	var restart := 0
	var src := 0
	var sp := 0                    # sine and cosine of −pitch and −yaw
	var cp := 0
	var sy := 0
	var cy := 0
	var mx := 0                    # the orbit centre
	var mz := 0
	var cam_y := 0
	var u := PackedInt32Array([0, 0])
	var v := PackedInt32Array([0, 0])
	var z := PackedInt32Array([0, 0])
	var depth := PackedInt32Array([0, 0, 0])   # both targets, then the camera
	var ball := PackedInt32Array()             # Tekken Ball: u, depth, v, world y
	var e2 := 0                    # the vertical view coordinate of the ground point
	var back := 0
	var lateral := 0
	var lift := 0
	var scale := 0


## CameraFrameFighters (0x800650F8): source `src` framing both targets (camera.md#fight-camera).
func _frame_fighters(pitch: int, yaw: int, restart: int, distance: int, src: int) -> void:
	var fr := Framing.new()
	fr.pitch = Fx.w32(pitch)
	fr.yaw = Fx.w32(yaw)
	fr.distance = Fx.w32(distance)
	if fr.distance < 0x321:
		fr.distance = MIN_DISTANCE
	fr.restart = restart
	fr.src = src
	fr.cam_y = sources[src][1]
	fr.sp = FightMath.sin12(_index18(-fr.pitch), t)
	fr.cp = FightMath.cos12(_index18(-fr.pitch), t)
	fr.sy = FightMath.sin12(_index18(-fr.yaw), t)
	fr.cy = FightMath.cos12(_index18(-fr.yaw), t)
	_orbit_centre(fr)
	_project_targets(fr)
	_fit_horizontal(fr)
	var vertical := _fit_vertical(fr)
	_place_source(fr, vertical)


## The point the camera orbits: the targets' midpoint, offset by the camera's current position
## turned into the new yaw (or placed at `distance` on a restart).
func _orbit_centre(fr: Framing) -> void:
	var rec := sources[fr.src]
	fr.mx = _div(targets[0][0] + targets[1][0], 2)
	fr.mz = _div(targets[0][2] + targets[1][2], 2)
	var ox := 0
	var oz := 0
	if fr.restart == 0:
		var i := _index18(_s18(fr.yaw - rec[4]))
		var s_ := FightMath.sin12(i, t)
		var c_ := FightMath.cos12(i, t)
		var dx := Fx.w32(rec[0] - fr.mx)
		var dz := Fx.w32(rec[2] - fr.mz)
		ox = Fx.trunc12(c_ * dx - s_ * dz)
		oz = Fx.trunc12(s_ * dx + c_ * dz)
	else:
		var i := _index18(fr.yaw + 0x30000)
		ox = Fx.trunc12(fr.distance * FightMath.cos12(i, t))
		oz = Fx.trunc12(fr.distance * FightMath.sin12(i, t))
	fr.mx = Fx.w32(fr.mx + ox)
	fr.mz = Fx.w32(fr.mz + oz)


## Both targets (and the ball) in view space, the ground point below their middle, and the depth
## correction that puts the camera `distance` behind it.
func _project_targets(fr: Framing) -> void:
	for k in 2:
		var tx := Fx.w32(targets[k][0] - fr.mx)
		var tz := Fx.w32(targets[k][2] - fr.mz)
		var ty := Fx.w32(targets[k][1] - fr.cam_y)
		var a1 := Fx.trunc12(fr.sy * tx + fr.cy * tz)
		fr.u[k] = Fx.trunc12(fr.cy * tx - fr.sy * tz)
		fr.z[k] = Fx.trunc12(fr.cp * a1 - fr.sp * ty)
		fr.v[k] = Fx.trunc12(fr.sp * a1 + fr.cp * ty)
		fr.depth[k] = a1
	# Tekken Ball: the ball (FUN_800B4948) is a third target; it keeps its raw depth, without the
	# distance correction below.
	if fight.mode == GameMode.BALL:
		var p := fight.ball.position()
		var tx := Fx.w32(p[0] - fr.mx)
		var tz := Fx.w32(p[2] - fr.mz)
		var ty := Fx.w32(p[1] - fr.cam_y)
		var a1 := Fx.trunc12(fr.sy * tx + fr.cy * tz)
		fr.ball = PackedInt32Array([Fx.trunc12(fr.cy * tx - fr.sy * tz), Fx.trunc12(fr.cp * a1 - fr.sp * ty),
			Fx.trunc12(fr.sp * a1 + fr.cp * ty), p[1]])
	var m := _div(fr.depth[0] + fr.depth[1], 2)
	var up := Fx.w32(-0x1C2 - fr.cam_y)
	var e10 := Fx.trunc12(fr.cp * m - fr.sp * up)
	fr.e2 = Fx.trunc12(Fx.w32(fr.sp * m + fr.cp * up))
	var d := fr.distance - e10
	fr.depth[2] = e10 + d
	fr.back = -d
	fr.z[0] += d
	fr.z[1] += d


## Moves the camera back until both targets fit across the screen with a margin, and sideways to
## centre them (state `lateral` of the source settles it over frames).
func _fit_horizontal(fr: Framing) -> void:
	var st := source_state[fr.src]
	if not fr.ball.is_empty():
		# A ball beyond the outer fighter replaces it, with a further 150-unit margin.
		var lo_k := 0 if fr.u[0] < fr.u[1] else 1
		var hi_k := 1 - lo_k
		if fr.ball[0] < fr.u[lo_k]:
			fr.u[lo_k] = fr.ball[0] - MARGIN
			fr.z[lo_k] = fr.ball[1]
		elif fr.u[hi_k] < fr.ball[0]:
			fr.u[hi_k] = fr.ball[0] + MARGIN
			fr.z[hi_k] = fr.ball[1]
	var lo := 0
	var hi := 1
	var left_px := 0
	var edge := 0
	var zr := 0
	if fr.u[1] <= fr.u[0]:
		left_px = _div(Fx.w32((fr.u[1] - MARGIN) * h), fr.z[1])
		edge = fr.u[0] + MARGIN
		fr.u[1] -= MARGIN
		fr.u[0] = edge
		zr = fr.z[0]
		lo = 1
		hi = 0
	else:
		left_px = _div(Fx.w32((fr.u[0] - MARGIN) * h), fr.z[0])
		edge = fr.u[1] + MARGIN
		fr.u[0] -= MARGIN
		fr.u[1] = edge
		zr = fr.z[1]
	var right_px := _div(Fx.w32(edge * h), zr)
	var backoff := 0
	if right_px - left_px < SPREAD_LIMIT:
		var centred := false
		if fr.restart == 0:
			var a7 := _div(fr.z[hi] * 0x30, h)
			var a13 := _div(fr.z[lo] * -0x30, h)
			if a7 - (fr.u[hi] - fr.u[lo]) < a13:
				centred = true
			else:
				a13 = fr.u[lo] - a13
				if left_px > -0x31:
					if right_px >= 0x31:
						fr.lateral += _div8(fr.u[hi] - a7)
				else:
					fr.lateral += _div8(a13)
		else:
			centred = true
		if centred:
			fr.lateral = _div8(fr.u[lo] + _div(Fx.w32((fr.u[hi] - fr.u[lo]) * fr.z[lo]), fr.z[lo] + fr.z[hi]))
		if fr.restart != 0 and centred:
			st.lateral = 0
			return
		backoff = _settle(st.lateral)
	else:
		var e10b := _div(Fx.w32(h * (fr.u[hi] - fr.u[lo]) + (fr.z[hi] - fr.z[lo]) * -0x8C), 0x118)
		backoff = fr.z[lo] - e10b
		if fr.restart == 0:
			var s := st.lateral
			if s < backoff:
				backoff = s + ((backoff - s) >> 5)
			else:
				backoff = s - _div8(s - backoff)
		fr.lateral = _div8(fr.u[lo] - _div(Fx.w32(e10b * -0x8C), h))
	st.lateral = backoff
	fr.back += backoff
	fr.depth[2] -= backoff
	fr.z[0] -= backoff
	fr.z[1] -= backoff


## Raises the camera so the higher target (or the ball) stays below the top of the screen (state
## `depth` of the source eases it); returns the camera's vertical offset.
func _fit_vertical(fr: Framing) -> int:
	var st := source_state[fr.src]
	var top := 100
	var ty_world := targets[1][1]
	var top_v := fr.v[1]
	var top_z := fr.z[1]
	if _div(Fx.w32(fr.v[0] * h), fr.z[0]) < _div(Fx.w32(fr.v[1] * h), fr.z[1]):
		top_v = fr.v[0]
		top_z = fr.z[0]
		ty_world = targets[0][1]
	var height := Fx.trunc12(ty_world * fr.cp)
	if not fr.ball.is_empty() and fr.ball[2] < top_v:
		top_v = fr.ball[2]
		top_z = fr.ball[1]
		height = Fx.trunc12(Fx.w32(fr.ball[3] * fr.cp))
	if fr.src == SOURCE_SCRIPT and fr.pitch < 0:
		top = 0x80
	_script_lift(fr, height)
	fr.scale = Fx.trunc12(fr.cp * (top - _div(Fx.w32(h * 0x1C2), fr.distance)))
	var want := _div(Fx.w32(Fx.w32((top_z - fr.depth[2]) * -0x70) - Fx.w32(h * (top_v - fr.e2))), fr.scale + 0x70) \
		- fr.depth[2]
	if want < 0:
		want = 0
	if fr.restart == 0:
		var cur := st.depth
		if want < cur:
			var step := cur - want
			var big := step * 16
			if step > 0x4B0:
				step = 0x4B0
				big = 0x4B00
			var q := Fx.w32((big - step) * 8)
			q = (q + 0x7F if q < 0 else q) >> 7
			st.depth_step = q - step
			want = cur + (q - step)
		elif want > cur:
			var step := mini(want - cur, 800)
			st.depth_step = _div8(step)
			want = cur + _div8(step)
	else:
		want = 0
		st.depth_step = 0
	st.depth = want
	if want > 0:
		fr.back -= want
		fr.depth[2] += want
	var vertical_scale := fr.scale
	if fr.src == SOURCE_FIGHT:
		var q := _div(Fx.w32(Fx.trunc12(Fx.w32(want * fr.cp)) * h), fr.distance)
		vertical_scale += (q + 0xF if q < 0 else q) >> 4
	return fr.e2 - _div(Fx.w32(vertical_scale * fr.depth[2]), h) + fr.lift


## Script cameras looking down lift with the target's height, at most 0x1C a frame.
func _script_lift(fr: Framing, height: int) -> void:
	var g := height_term
	var new_g := g
	if fr.src == SOURCE_SCRIPT and fr.pitch > 0:
		var lift := 0
		if height > -1001:
			lift = _div(Fx.w32((height + 1000) * 0x170), 0x280)
		if fr.restart == 0:
			if g < lift and lift - g > 0x1C:
				lift = g + 0x1C
			elif lift < g and g - lift > 0x1C:
				lift = g - 0x1C
		new_g = lift
		fr.lift = lift
	height_term = new_g


## The source's new position and angles from the offsets around the orbit centre; unless it
## restarts, the angles turn by the wrapped difference.
func _place_source(fr: Framing, vertical: int) -> void:
	var rec := sources[fr.src]
	var cam_x := rec[0]
	var cam_z := rec[2]
	var cam_p := rec[3]
	var cam_yw := rec[4]
	var sp2 := FightMath.sin12(_index18(fr.pitch), t)
	var cp2 := FightMath.cos12(_index18(fr.pitch), t)
	var sy2 := FightMath.sin12(_index18(fr.yaw), t)
	var cy2 := FightMath.cos12(_index18(fr.yaw), t)
	var r2 := Fx.trunc12(fr.back * cp2 - vertical * sp2)
	var r12 := Fx.trunc12(fr.back * sp2 + vertical * cp2)
	var xa := Fx.w32(fr.lateral * cy2 + r2 * -sy2)
	var za := Fx.w32(fr.lateral * sy2 + r2 * cy2)
	var new_x := Fx.w32(fr.mx + Fx.trunc12(xa))
	var new_z := Fx.w32(fr.mz + Fx.trunc12(za))
	if fr.restart == 0:
		var dx := Fx.w32(new_x - cam_x)
		var dz := Fx.w32(new_z - cam_z)
		if fr.src == SOURCE_FIGHT:
			source_state[fr.src].moved = 0 if Fx.w32(dx * dx + dz * dz) < 0x3E9 else 1
		cam_p = Fx.w32(cam_p + _s18(fr.pitch - cam_p))
		cam_yw = Fx.w32(cam_yw + _s18(fr.yaw - cam_yw))
	else:
		cam_p = fr.pitch
		cam_yw = fr.yaw
	var cam_y := Fx.w32(fr.cam_y + r12)
	sources[fr.src] = PackedInt32Array([new_x, cam_y, new_z, cam_p, cam_yw, rec[5]])


# ==== blending ====================================================================================

## CameraBlend (0x80062E5C): the positive-weight sources into source 3 and the view.
func _blend() -> void:
	var mask := 0
	for i in SOURCES:
		if weights[i] > 0:
			mask |= 1 << i
	var w0 := weights[0]
	match mask:
		1, 2, 4, 0x10:
			_use_source(_bit_index(mask))
		3, 5:
			_blend_pair(sources[0], sources[1 if mask == 3 else 2], w0)
		0x11:
			var e := FightMath.sin12((Fx.div_trunc(w0, 2) - 0x400) & 0xFFF, t)
			_blend_pair(sources[0], sources[4], Fx.div_trunc(e, 2) + 0x800)
		_:
			reset()
	for i in SOURCES:
		prev_weights[i] = weights[i]


static func _bit_index(mask: int) -> int:
	var i := 0
	while mask > 1:
		mask >>= 1
		i += 1
	return i


## CameraUseSource (0x80064368): source i becomes source 3 and the view.
func _use_source(i: int) -> void:
	var rec := sources[i]
	sources[SOURCE_OUTPUT] = rec.duplicate()
	view.x = rec[0]
	view.y = rec[1]
	view.z = rec[2]
	view.pitch = CameraMath.sar6(rec[3])
	view.yaw = CameraMath.sar6(rec[4])
	view.h = clampi(rec[5], h_min, h_max)


## CameraLookPoint (0x80063FE8): the mean distance r to the targets and the point r along
## the view. Bug #1 is not reproduced: the distance to target 1 uses target 1's z.
func _look_point(rec: PackedInt32Array) -> Array:
	var sp := FightMath.sin12(_index18(rec[3]), t)
	var cp := FightMath.cos12(_index18(rec[3]), t)
	var i := _index18(Fx.w32(rec[4] + 0x10000))
	var sy := FightMath.sin12(i, t)
	var cy := FightMath.cos12(i, t)
	var d0 := _distance(targets[0], rec)
	var d1 := _distance(targets[1], rec)
	var r := ((d0 + d1) & 0xFFFFFFFF) >> 1
	var look := PackedInt32Array([
		Fx.w32(rec[0] + Fx.trunc12(Fx.w32(Fx.trunc12(Fx.w32(r * cy)) * cp))),
		Fx.w32(rec[1] + Fx.trunc12(Fx.w32(r * sp))),
		Fx.w32(rec[2] + Fx.trunc12(Fx.w32(Fx.trunc12(Fx.w32(r * sy)) * cp)))])
	return [r, look]


static func _distance(target: PackedInt32Array, rec: PackedInt32Array) -> int:
	var dx := target[0] - rec[0]
	var dy := target[1] - rec[1]
	var dz := target[2] - rec[2]
	return CameraMath.isqrt(Fx.w32(Fx.w32(dx * dx) + Fx.w32(dy * dy) + Fx.w32(dz * dz)))


## CameraBlendPair (0x80064458): `a` and `b` (weight w of `a`) blended around their look
## points into source 3 and the view. Bug #6: a non-positive H keeps source 3's H.
func _blend_pair(a: PackedInt32Array, b: PackedInt32Array, w: int) -> void:
	var iw := Fx.ONE - w
	var la: Array = _look_point(a)
	var lb: Array = _look_point(b)
	var ra: int = la[0]
	var rb: int = lb[0]
	var r := Fx.trunc12(Fx.w32(ra * w + rb * iw))
	var pa: PackedInt32Array = la[1]
	var pb: PackedInt32Array = lb[1]
	var look := PackedInt32Array([0, 0, 0])
	for k in 3:
		look[k] = Fx.trunc12(Fx.w32(pa[k] * w + pb[k] * iw))
	var pitch := Fx.w32(a[3] + Fx.trunc12(Fx.w32(_s18(b[3] - a[3]) * iw)))
	var yaw := Fx.w32(a[4] + Fx.trunc12(Fx.w32(_s18(b[4] - a[4]) * iw)))
	var sp := FightMath.sin12(_index18(pitch), t)
	var cp := FightMath.cos12(_index18(pitch), t)
	var yi := (CameraMath.sar6(yaw) + 0x400) & 0xFFF
	var ys := FightMath.sin12(yi, t)
	var yc := FightMath.cos12(yi, t)
	var pos := PackedInt32Array([
		Fx.w32(look[0] - Fx.trunc12(Fx.w32(Fx.trunc12(Fx.w32(r * yc)) * cp))),
		Fx.w32(look[1] - Fx.trunc12(Fx.w32(r * sp))),
		Fx.w32(look[2] - Fx.trunc12(Fx.w32(Fx.trunc12(Fx.w32(r * ys)) * cp)))])
	var bh := Fx.trunc12(Fx.w32(a[5] * w + b[5] * iw))
	var old_h := sources[SOURCE_OUTPUT][5]
	sources[SOURCE_OUTPUT] = _look_source(pos, look, bh, old_h)
	_use_source(SOURCE_OUTPUT)


## FUN_800641D4: a source at `eye` looking at `target` with projection plane `plane` (the
## previous value `keep` when not positive).
func _look_source(eye: PackedInt32Array, target: PackedInt32Array, plane: int, keep: int) -> PackedInt32Array:
	var dx := target[0] - eye[0]
	var dz := target[2] - eye[2]
	var flat := CameraMath.isqrt(Fx.w32(dx * dx + dz * dz))
	var pitch := Fx.s16(CameraMath.atan2_units4096(flat, target[1] - eye[1], ct)) << 6
	var yaw := Fx.s16(CameraMath.atan2_units4096(dz, -dx, ct)) << 6
	return PackedInt32Array([eye[0], eye[1], eye[2], pitch, yaw, plane if plane > 0 else keep])


# ==== arithmetic ==================================================================================

## An 18-bit angle as a 4096-entry table index: `(a [+ 0x3F if negative]) >> 6 & 0xFFF`.
static func _index18(a: int) -> int:
	a = Fx.w32(a)
	return (((a + 0x3F) if a < 0 else a) >> 6) & 0xFFF


static func _s18(v: int) -> int:
	v &= 0x3FFFF
	return v - 0x40000 if v & 0x20000 else v


## C division; a zero divisor is taken as 1 (bug #2 is not reproduced).
static func _div(a: int, b: int) -> int:
	return Fx.div_trunc(Fx.w32(a), 1 if b == 0 else Fx.w32(b))


static func _div8(v: int) -> int:
	return (v + 7 if v < 0 else v) >> 3


static func _half(v: int) -> int:
	return (v + (1 if v < 0 else 0)) >> 1


static func _sar(v: int, n: int) -> int:
	return (v + (1 << n) - 1 if v < 0 else v) >> n


static func _settle(s: int) -> int:
	if s < 0:
		return s - ((s + 0x1F) >> 5)
	return s - (s >> 3) if s > 0 else 0
