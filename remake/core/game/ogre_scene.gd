class_name OgreScene
extends FlowPart
## The Ogre scene (arcade.ovl FUN_800B4168 set-up, FUN_800B4528 per frame; modes.md#match-flow),
## written from the verified port `tools/research/ogre_scene_sim.py`: the defeated human's fighter is
## reloaded as the stage-9 boss, both fighters stand at the origin, and a script in the Enbu
## event format plays: music track 5, the two scripted moves (Ogre lifts the boss), a fade to
## white from frame 192, the end at 256; then a white screen for two more frames. The camera
## plays the reel of Ogre's camera id 0x4B (CameraDirector.ogre_start), then CameraDirector
## takes over.

const EVENT_END := -1
const EVENT_MOVE_0 := 2
const EVENT_MOVE_1 := 3
const EVENT_FADE := 5
const EVENT_MUSIC := 6
const MUSIC_OGRE := 5
const BLACK_LEVEL := 0xD0
const FADE_MAX := 0x100
const FADE_BASE := 0x100
const CLOSING_FRAMES := 2
const LETTERBOX_FROM := 5
const FACING := 0x4000
const JIN_SLOTS: Array[int] = [0x12, 0x13]      ## the boss when the player is Heihachi
const HEIHACHI_SLOTS: Array[int] = [0x1A, 0x1B]
const LADDER_BOSS_COSTUME := 0x90 + 4 * 8 + 1   ## mode context: ladder entry 8's costume

enum { START, SCRIPT, CLOSING }

var state := START                   ## 0x800B4F18
var frame := 0                       ## 0x800B4F1C
var events: Array[PackedInt32Array] = []
var cursor := 0                      ## 0x800B4F14: the next event
var fade_on := false
var fade_level := 0
var fade_speed := 0
var black := false                   ## 0x800B4F50: the stage is no longer drawn
var letterbox := false               ## from frame 5 only the top 100 lines are cleared
var fade_drawn := -1                 ## this frame's FUN_8004E2E8 level, −1 none
var reel_over := false               ## 0x800B4F48: the camera reel has ended
var moves: Array[ScriptedMove] = [ScriptedMove.new(), ScriptedMove.new()]   ## 0x800B4F34


## A fighter's scripted move (10 bytes in the game).
class ScriptedMove:
	extends RefCounted
	var active := 0
	var slot := 0
	var end := 0
	var frame := 0


## FUN_800B4168: the scene's set-up.
func setup() -> void:
	var fight := g.fight
	var region := g.region
	state = START
	fade_on = false
	black = false
	letterbox = false
	region.put8(0x69, 1)
	g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
	# FUN_8003C4AC for each, then FUN_8002BFCC facing each other (their third argument is a leftover
	# register; the scene places both at the origin below either way).
	for f in fight.active():
		f.blend_mode = FighterAnimation.Blend.NONE
		f.blend_mode_b = 0
	fight.blend_hold = 0x14
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	g.sim.place(f0, f1)
	g.sim.place(f1, f0)
	for m in moves:
		m.active = 0
		m.slot = 0
		m.frame = 0
	fight.undrawn_mask = 3
	var human := 0 if region.human_mask & 1 else 1
	events = g.data.ogre_scripts[human]
	cursor = 0
	var f := fight.fighters[human]
	var slots := JIN_SLOTS if f.char_id == Character.HEIHACHI else HEIHACHI_SLOTS
	f.set_costume(slots[1 if region.ctx8(LADDER_BOSS_COSTUME) != 0 else 0], fight.tables.fighter)
	f.bank_type = f.char_id
	g.sim.reload_fighter(human)
	g.sim.setup_parts(fight.fighters[1 - human])   # the other's parts bound again (FighterSetupParts)
	for other in fight.active():
		other.facing = FACING
		other.tilt_x = 0
		other.pos_x = 0
		other.pos_y = 0
		other.tilt_z = 0
		other.pos_z = 0
		other.heading = other.facing


## FUN_800B4528: one frame; true when the scene is over.
func step() -> bool:
	fade_drawn = -1
	g.fight.undrawn_mask = 3
	match state:
		START:
			g.sim.camera.ogre_start(g.fight.fighters[0], g.fight.fighters[1])
			reel_over = false
			frame = 0
			state = SCRIPT
			return false
		CLOSING:
			fade_drawn = 0x200
			_camera()
			frame -= 1
			return frame < 0
	if frame >= LETTERBOX_FROM:
		letterbox = true
	if frame >= events[cursor][0]:
		while true:
			var e := events[cursor]
			if _event(e):
				break
			cursor += 1
			if frame < events[cursor][0]:
				break
	_step_moves()
	_camera()
	g.sim.view_frame()
	if not black:
		g.sim.background()            # FUN_8006DAB4 until the fade passes 0xD0
	if fade_on:
		if fade_level >= BLACK_LEVEL:
			black = true
		fade_level = mini(fade_level, FADE_MAX)
		fade_drawn = fade_level + FADE_BASE
		fade_level += fade_speed
	frame += 1
	return false


## The scene is left: the fight's fighters are drawn again.
func end() -> void:
	g.fight.undrawn_mask = 0


## One event; true at the end of the script.
func _event(e: PackedInt32Array) -> bool:
	match e[1]:
		EVENT_END:
			frame = CLOSING_FRAMES
			state = CLOSING
			return true
		EVENT_MOVE_0, EVENT_MOVE_1:
			var i: int = e[1] - EVENT_MOVE_0
			var m := moves[i]
			var f := g.fight.fighters[i]
			if m.slot != e[2]:
				var row := g.fight.move_for_slot(f, e[2])
				f.pose_move = row
				f.root_move = row
			m.slot = e[2]
			m.frame = e[3]
			m.active = 1
			m.end = e[4]
		EVENT_FADE:
			fade_level = 0
			fade_on = true
			fade_speed = e[2]
		EVENT_MUSIC:
			g.music(MUSIC_OGRE)
	return false


## The reel until it ends, then the director (with g_cameraPhase as the fight left it).
func _camera() -> void:
	var camera := g.sim.camera
	if not reel_over:
		reel_over = camera.reel_step()
	else:
		camera.step(g.fight.fighters[0], g.fight.fighters[1])


## Each scripted move one pose frame on (its frame events without sounds), then animated.
func _step_moves() -> void:
	var fight := g.fight
	for i in 2:
		var m := moves[i]
		if m.active != 1:
			continue
		var f := fight.fighters[i]
		fight.undrawn_mask &= ~(1 << i)
		f.pose_frame = (m.frame + 1) & 0xFFFF
		f.root_frame = f.pose_frame
		var first := g.sim.events.items.size()
		MoveEvents.run(f, fight.tables.fighter, g.sim.events)
		g.sim.move_event_calls(first)
		fight.blend_skip = 1
		g.sim.animation.animate(f, g.sim.fighter_view, fight.blend_enabled != 0, true)
		m.frame = (m.frame + 1) & 0xFFFF
		if Fx.s16(m.end) < Fx.s16(m.frame):
			m.frame = m.end
