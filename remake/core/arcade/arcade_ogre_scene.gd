class_name ArcadeOgreScene
extends ArcadeScene
## The scene before True Ogre (FUN_801E173C, FUN_801E1758): the human's fighter becomes Heihachi (Jin
## if the human plays Heihachi, in the ladder's boss costume), Ogre lifts him, the screen goes white;
## four white frames close it. Past fade level 0xBF the game stops drawing the stage: not shown here,
## the view keeps it under the fade.

const HEIHACHI := 13
const FIRST_MODEL := 0x16               ## no model: the script's first event always changes it
const JIN_MODELS: Array[int] = [0x12, 0x13]
const HEIHACHI_OTHER_COSTUME := 0x1B
const CLOSING_FRAMES := 3
const WHITE := 0x200
const LADDER_BOSS_COSTUME := 8 * 4 + 1  ## the ladder's entry of the ninth fight, its costume
const REEL_LIST := 1

enum Phase { SETTING_UP, RUNNING, CLOSING }

var phase := Phase.SETTING_UP as int    ## 0x8021F9A0
var _human_is_heihachi := false         ## 0x8021F9BC


## FUN_801E173C.
func start() -> void:
	phase = Phase.SETTING_UP
	fade_on = false
	_human_is_heihachi = false


## FUN_801E1758: true when the scene is over.
func step() -> bool:
	match phase:
		Phase.SETTING_UP:
			_set_up()
			phase = Phase.RUNNING
			clock = 0
			reel_over = false
		Phase.RUNNING:
			_running()
		Phase.CLOSING:
			flow.add_fade(WHITE)
			_camera_step()
			clock -= 1
			return clock < 0
	return false


func _set_up() -> void:
	var sim := flow.sim
	var fight := flow.fight
	sim.scene_place()
	var human := 0 if flow.match_flow.joined & 1 != 0 else 1
	_script = flow.data.ogre_scripts[human]
	_cursor = 0
	_human_is_heihachi = fight.fighters[human].char_id == HEIHACHI
	for m in moves:
		m.state = MoveState.IDLE
		m.model = FIRST_MODEL
		m.slot = 0
		m.frame = 0
	_to_origin()
	# The game draws whoever plays; a loser of the fight is no longer active here.
	for f: FighterState in fight.fighters:
		f.active = 1
	(sim.camera as ArcadeCamera).scene_start(REEL_LIST, fight.fighters[0], fight.fighters[1])


func _running() -> void:
	var sim := flow.sim
	var ended := _due_events()
	if ended:
		clock = CLOSING_FRAMES - 1
		phase = Phase.CLOSING
	sim.frame_view()
	_step_moves()
	_camera_step()
	_fade_step()
	clock += 1


## The ladder's costume picks who is shown lifted.
func _model_of(_i: int, model_slot: int) -> int:
	if flow.match_flow.ladder[LADDER_BOSS_COSTUME] == 0:
		return JIN_MODELS[0] if _human_is_heihachi else model_slot
	return JIN_MODELS[1] if _human_is_heihachi else HEIHACHI_OTHER_COSTUME


## The last frame is held.
func _move_ended(m: ScriptedMove) -> void:
	m.frame = m.end
