class_name ArcadeEnbu
extends ArcadeScene
## The attract's demonstration (FUN_801E0DD4, FUN_801E0E30): the two start as Hwoarang and Paul on
## stage 4; the script changes who plays, the reel of 22 streams follows them.

const STAGE := 4
const START_DELAY := 4
const MUSIC := 0x66
const FIRST_MODELS: Array[int] = [0xC, 0]
const REEL_LIST := 0

enum Phase { SETTING_UP, MUSIC_WAIT, RUNNING, OVER }

var phase := Phase.SETTING_UP as int    ## 0x8021F96C
var variant := 0                        ## 0x8021F970


## FUN_801E0DD4.
func start() -> void:
	var fight := flow.fight
	phase = Phase.SETTING_UP
	fight.attract = 1
	variant = fight.rng.next() & 3
	fade_on = false


func drawn() -> bool:
	return phase == Phase.RUNNING or phase == Phase.OVER


## FUN_801E0E30: true when the script has ended.
func step() -> bool:
	match phase:
		Phase.SETTING_UP:
			_set_up()
			clock = START_DELAY
			phase = Phase.MUSIC_WAIT
		Phase.MUSIC_WAIT:
			clock -= 1
			if clock < 0:
				flow.music(MUSIC)
				clock = 0
				phase = Phase.RUNNING
		Phase.RUNNING:
			return _running()
	return false


func _set_up() -> void:
	var sim := flow.sim
	var fight := flow.fight
	_script = flow.data.enbu_script
	_cursor = 0
	fight.stage = STAGE
	sim.scene_fighters(PackedInt32Array(FIRST_MODELS))
	sim.scene_place()
	for i in 2:
		var m := moves[i]
		m.state = MoveState.IDLE
		m.model = FIRST_MODELS[i]
		m.slot = 0
		m.frame = 0
		_set_move(i, 0)
	_to_origin()
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	fight.camera_phase = CameraPhase.RESET
	sim.camera.step(f0, f1)
	(sim.camera as ArcadeCamera).scene_start(REEL_LIST, f0, f1)
	reel_over = false
	_replay_init(fight.replay as ArcadeReplay)
	sim.effect_objects.round_start()


## FUN_80194EFC(0), (1), (2): no kept fights, none stored, and the replay records again. A staff roll
## left with Start keeps playing its kept fight until then, which would move the fighters' roots.
func _replay_init(replay: ArcadeReplay) -> void:
	replay.clear_kept()
	replay.stored = 0
	replay.reset()


func _running() -> bool:
	var sim := flow.sim
	var fight := flow.fight
	var ended := _due_events()
	sim.frame_view()
	_step_moves()
	# FUN_801ADA60(1), FUN_801AE44C(1): the flipbooks and dust rings are drawn and advance.
	sim.events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
	_camera_step()
	_fade_step()
	clock += 1
	for f: FighterState in fight.fighters:
		f.event_frame = f.pose_frame
	if ended:
		phase = Phase.OVER
	return ended
