class_name EnbuPerformance
extends RefCounted
## The attract demonstration's performance (`enbu.ovl` FUN_800D3D64, one call per frame;
## modes.md#enbu-attract-demonstration).
##
## The first step sets both fighters up at the origin facing +x on their starting costumes and
## starts the camera reel; the next five steps wait for the music; then every step runs the due
## script events, steps each scripted move one pose frame (with its frame events), steps the
## camera reel and advances the fade. The step that runs the end event returns true. Each script
## frame's background (FUN_8006DAB4) turns the panorama with the camera (BackdropTurn): GameFlow
## hands the game's own turn state, round state and camera in.
##
## Game bug #49 (fighter 0's frame events fire twice while fighter 1 plays a move) is not
## reproduced: each fighter's events fire once.

enum Phase { SETUP, MUSIC_WAIT, SCRIPT }

const MUSIC_WAIT_FRAMES := 4           ## the wait counts down from 4 to −1
const FACING := 0x4000                 ## both fighters face +x (facing and heading)
const FADE_MAX := 0x100
const FADE_BASE := 0x100               ## FUN_8004E2E8's neutral level; the fade brightens above it
const EVENT_END := -1
const EVENT_COSTUME_0 := 0
const EVENT_COSTUME_1 := 1
const EVENT_MOVE_0 := 2
const EVENT_MOVE_1 := 3
const EVENT_FADE := 5

var demo: EnbuData.Demo
var motions: MotionSet
var fighter_tables: FighterTables
var pose_tables: PoseTables
var models: Dictionary                 ## costume slot → CharacterModel
var reel: CameraReel
var projection := 500                  ## H: CameraReset sets 500 and clamps to [500, 500]

var phase := Phase.SETUP
var wait := 0
var frame := 0                         ## script frame counter (0x8010C41C)
var cursor := 0                        ## next script event
var fighters: Array[ScriptedFighter] = [ScriptedFighter.new(), ScriptedFighter.new()]
var fade_on := false
var fade_level := 0
var fade_speed := 0
var fade_drawn := -1                   ## the FUN_8004E2E8 level drawn this frame, −1 for none
var camera: CameraView                 ## after this step's reel step (g_camera)
var camera_drawn: CameraView           ## the view this frame's picture uses (CameraFrame)
var drawn := false                     ## the stage and fighters were drawn this frame
var events := SimEvents.new()
var finished := false
var backdrop := BackdropTurn.new()     ## the panorama's turn (GameFlow: the fight's)
var round_state := 0                   ## 0x80097350 as the last fight left it
var setup_view := CameraView.new(0, 0, 0, 0, 0, 500)   ## g_camera when the performance starts


func _init(demonstration: EnbuData.Demo, motion_set: MotionSet, tables: FighterTables,
		poses: PoseTables, costume_models: Dictionary, camera_reel: CameraReel) -> void:
	demo = demonstration
	motions = motion_set
	fighter_tables = tables
	pose_tables = poses
	models = costume_models
	reel = camera_reel


## One frame; true on the frame that ran the end event. `music_ready`: FUN_8006BCC8's answer
## this frame (the music wait only counts down once the music is ready).
func step(music_ready := true) -> bool:
	events.clear()
	fade_drawn = -1
	drawn = false
	for sf in fighters:
		sf.drawn = false
	match phase:
		Phase.SETUP:
			_setup()
		Phase.MUSIC_WAIT:
			if music_ready:
				wait -= 1
			if music_ready and wait < 0:
				camera = reel.step(projection)
				phase = Phase.SCRIPT
		Phase.SCRIPT:
			return _script_frame()
	return false


func _setup() -> void:
	# FUN_8006CC44 (the stage set up), then FUN_8006CB40.
	backdrop.setup(setup_view)
	backdrop.reset()
	for i in 2:
		var sf := fighters[i]
		var f := sf.fighter
		f.index = i
		f.opp_index = 1 - i
		f.cur_opp_index = 1 - i
		f.player_index = i
		f.active = 1
		sf.state = ScriptedFighter.State.IDLE
		sf.frame = 0
		sf.slot = 0
		sf.costume = demo.start_costumes[i]
		f.set_costume(sf.costume, fighter_tables)
		_bind_model(sf)
		f.hands.command(3, fighter_tables.hand_shape(f.costume_slot), 10, f.char_id)
		f.move = motions.row_for_slot(0)
		f.pose_frame = 1
		f.root_frame = 1
		f.event_frame = 0
		f.anchor = PackedInt32Array([0, 0, 0])
		f.facing = FACING
		f.heading = FACING
	reel.start()
	camera = reel.step(projection)
	camera_drawn = camera
	wait = MUSIC_WAIT_FRAMES
	phase = Phase.MUSIC_WAIT


func _script_frame() -> bool:
	var ended := false
	while cursor < demo.events.size() and demo.events[cursor][0] <= frame:
		var e := demo.events[cursor]
		if e[1] == EVENT_END:
			ended = true
			break
		_run_event(e)
		cursor += 1
	camera_drawn = camera
	drawn = true
	backdrop.step(camera, round_state, pose_tables, reel.tables)   # FUN_8006DAB4
	for sf in fighters:
		_step_fighter(sf)
	# FUN_80077744(1), FUN_8004AEBC(1): the flipbooks and dust rings are drawn and advance.
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
	camera = reel.step(projection)
	if fade_on:
		fade_level = mini(fade_level, FADE_MAX)
		fade_drawn = fade_level + FADE_BASE
		fade_level += fade_speed
	frame += 1
	for sf in fighters:
		sf.fighter.event_frame = sf.fighter.pose_frame
	finished = ended
	return ended


func _run_event(e: PackedInt32Array) -> void:
	match e[1]:
		EVENT_COSTUME_0, EVENT_COSTUME_1:
			var sf := fighters[e[1] - EVENT_COSTUME_0]
			if sf.costume != e[2]:
				sf.fighter.set_costume(e[2], fighter_tables)
				sf.frame = ScriptedFighter.RELOAD_DELAY
				sf.state = ScriptedFighter.State.RELOAD_WAIT
			sf.costume = e[2]
		EVENT_MOVE_0, EVENT_MOVE_1:
			var sf := fighters[e[1] - EVENT_MOVE_0]
			if sf.slot != e[2]:
				sf.fighter.move = motions.row_for_slot(e[2])
			sf.slot = e[2]
			sf.frame = e[3]
			sf.end_frame = e[4]
			sf.state = ScriptedFighter.State.MOVE
		EVENT_FADE:
			fade_level = 0
			fade_on = true
			fade_speed = e[2]


func _step_fighter(sf: ScriptedFighter) -> void:
	var f := sf.fighter
	match sf.state:
		ScriptedFighter.State.MOVE:
			f.pose_frame = sf.frame + 1
			f.root_frame = f.pose_frame
			var first := events.items.size()
			MoveEvents.run(f, fighter_tables, events)
			for i in range(first, events.items.size()):
				events.items[i].point = _event_point(sf, events.items[i])
			_animate(sf)
			sf.frame += 1
			if sf.end_frame < sf.frame:
				sf.state = ScriptedFighter.State.IDLE
		ScriptedFighter.State.RELOAD_WAIT:
			sf.frame = Fx.s16(sf.frame - 1)
			if sf.frame < 0:
				sf.state = ScriptedFighter.State.RELOAD_START
		ScriptedFighter.State.RELOAD_START:
			sf.state = ScriptedFighter.State.RELOAD_LOAD
		ScriptedFighter.State.RELOAD_LOAD:
			sf.state = ScriptedFighter.State.RELOAD_MODEL
		ScriptedFighter.State.RELOAD_MODEL:
			_bind_model(sf)
			sf.state = ScriptedFighter.State.RELOAD_PARTS
		ScriptedFighter.State.RELOAD_PARTS:
			sf.state = ScriptedFighter.State.IDLE


## FighterSetupModel: the fighter now uses the model of its costume slot. The joint blocks
## keep the last frame's joints until the next animated frame.
func _bind_model(sf: ScriptedFighter) -> void:
	sf.model_costume = sf.fighter.costume_slot
	var old := sf.skeleton
	sf.skeleton = FighterSkeleton.new(pose_tables, models[sf.model_costume] as CharacterModel, fighter_tables)
	if old != null:
		sf.skeleton.root = old.root
		sf.skeleton.joints = old.joints.duplicate()


## FUN_8003AA6C → FighterAnimate: hands, pose, root and joints of the current frame.
func _animate(sf: ScriptedFighter) -> void:
	var f := sf.fighter
	# FUN_800363B0: Mokujin's stick needs Yoshimitsu's moves, which a demonstration never uses.
	if f.char_id == Character.MOKUJIN:
		sf.stick_shown = f.bank_type == BankType.YOSHIMITSU
	f.hands.update(f.char_id, 0, fighter_tables)
	var pose := f.move.anim_bank.pose(f.move.anim, f.pose_frame - 1)
	sf.skeleton.update(pose, f.anchor, f.facing, f.heading)
	sf.drawn = true


## Where an event happens: the joint's translation, or the root for dust. MoveEvents runs
## before FighterAnimate, so these are the joints of the fighter's previous animated frame.
func _event_point(sf: ScriptedFighter, e: SimEvents.Event) -> PackedInt32Array:
	var joints := sf.skeleton.joints
	match e.kind:
		SimEvents.Kind.EFFECT, SimEvents.Kind.SPARK:
			return joints[e.b].t if e.b < joints.size() else sf.skeleton.root.t
		SimEvents.Kind.DUST:
			return sf.skeleton.root.t
	return PackedInt32Array()
