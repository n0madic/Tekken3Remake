class_name ArcadeScene
extends ArcadeFlowPart
## What the arcade's scripted scenes share (the attract's demonstration FUN_801E0E30, Ogre's
## FUN_801E1758): a script of events by the frame gives each fighter a model and a move; a move plays
## one frame per frame, its frames set by hand, and a fighter is drawn only while its move plays. The
## camera plays a reel of streams, then the director takes over; the fade brightens to white.

const EVENT_VALUES := ArcadeFlowData.ENBU_EVENT
const EVENT_END := -1
const EVENT_MODEL_0 := 0
const EVENT_MODEL_1 := 1
const EVENT_MOVE_0 := 2
const EVENT_MOVE_1 := 3
const EVENT_FLIPBOOK := 4
const EVENT_FADE := 5
const FACING := 0x4000
const MODEL_WAIT := 2                   ## frames before the new model's textures start loading
const FADE_NEUTRAL := 0x100
const FADE_MAX := 0x100
const ALL_UNDRAWN := 3

## What a fighter is doing (the record's +0): after a new model, the frames its textures take.
enum MoveState { IDLE, PLAY, MODEL_WAIT, LOAD_1, LOAD_2, LOAD_3, LOAD_4, FLIPBOOK }

## A fighter's part of the script (10 bytes in the game).
class ScriptedMove:
	var state := MoveState.IDLE as int  ## +0
	var model := 0                      ## +2
	var slot := 0                       ## +4
	var end := 0                        ## +6
	var frame := 0                      ## +8


var clock := 0
var moves: Array[ScriptedMove] = [ScriptedMove.new(), ScriptedMove.new()]
var fade_on := false
var fade_level := 0
var fade_speed := 0
var reel_over := false

var _script := PackedInt32Array()
var _cursor := 0
var _book_character := 0                ## 0x8021F984


func _value(index: int) -> int:
	return _script[_cursor * EVENT_VALUES + index]


## The events due; true when the script's end was among them.
func _due_events() -> bool:
	while _value(0) <= clock:
		var kind := _value(1)
		if kind == EVENT_END:
			return true
		match kind:
			EVENT_MODEL_0, EVENT_MODEL_1:
				_model_event(kind - EVENT_MODEL_0, _value(2))
			EVENT_MOVE_0, EVENT_MOVE_1:
				_move_event(kind - EVENT_MOVE_0, _value(2), _value(3), _value(4))
			EVENT_FLIPBOOK:
				_flipbook_event(_value(2), _value(3))
			EVENT_FADE:
				fade_speed = _value(2)
				fade_level = 0
				fade_on = true
		_cursor += 1
	return false


## The script's model: the scene's own choice in `_model_of`.
func _model_event(i: int, model_slot: int) -> void:
	var m := moves[i]
	if m.model != model_slot:
		flow.sim.scene_model(i, _model_of(i, model_slot))
		m.frame = MODEL_WAIT
		m.state = MoveState.MODEL_WAIT
	m.model = model_slot


func _model_of(_i: int, model_slot: int) -> int:
	return model_slot


func _move_event(i: int, slot: int, frame: int, end: int) -> void:
	var m := moves[i]
	if m.slot != slot:
		_set_move(i, slot)
	m.slot = slot
	m.frame = frame
	m.end = end
	m.state = MoveState.PLAY


## The side's flipbook is another character's, from the fighters' next frame.
func _flipbook_event(side: int, character: int) -> void:
	_book_character = character
	moves[side].state = MoveState.FLIPBOOK


func _set_move(i: int, slot: int) -> void:
	var f := flow.fight.fighters[i]
	var row := flow.fight.move_for_slot(f, slot)
	f.pose_move = row
	f.root_move = row


## Both at the origin, facing +x.
func _to_origin() -> void:
	for f: FighterState in flow.fight.fighters:
		f.facing = FACING
		f.tilt_x = 0
		f.pos_x = 0
		f.pos_y = 0
		f.tilt_z = 0
		f.pos_z = 0
		f.heading = FACING


## The fighters' frame: each by its state, drawn only while playing.
func _step_moves() -> void:
	var fight := flow.fight
	fight.undrawn_mask = ALL_UNDRAWN
	for i in 2:
		var m := moves[i]
		match m.state:
			MoveState.PLAY:
				fight.undrawn_mask &= ~(1 << i)
				_play(fight.fighters[i], m)
			MoveState.MODEL_WAIT:
				m.frame -= 1
				if m.frame < 0:
					m.state = MoveState.LOAD_1
			MoveState.LOAD_1, MoveState.LOAD_2, MoveState.LOAD_3:
				m.state += 1
			MoveState.LOAD_4:
				flow.sim.model_draws(fight.fighters[i])
				m.state = MoveState.IDLE
			MoveState.FLIPBOOK:
				var slot: int = flow.sim.t.fighter.costume_keys[_book_character << 2]
				flow.sim.events.add(SimEvents.Kind.EFFECT_BOOK, i, i, slot)
				m.state = MoveState.IDLE


## A move's frame; the game clears the row's head look-at (its byte +0x17) around the step.
func _play(f: FighterState, m: ScriptedMove) -> void:
	f.pose_frame = m.frame + 1
	f.root_frame = f.pose_frame
	var row := f.pose_move
	var flags := row.flags
	row.flags &= ~MoveFlag.LOOK_AT
	flow.sim.scene_frame(f)
	row.flags = flags
	m.frame += 1
	if m.end < m.frame:
		_move_ended(m)


func _move_ended(m: ScriptedMove) -> void:
	m.state = MoveState.IDLE


func _camera_step() -> void:
	var fight := flow.fight
	if not reel_over:
		reel_over = flow.sim.camera.reel_step()
	else:
		flow.sim.camera.step(fight.fighters[0], fight.fighters[1])


func _fade_step() -> void:
	if not fade_on:
		return
	fade_level = mini(fade_level, FADE_MAX)
	flow.add_fade(fade_level + FADE_NEUTRAL)
	fade_level += fade_speed
