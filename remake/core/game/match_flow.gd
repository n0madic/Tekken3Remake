class_name MatchFlow
extends FlowPart
## FightMain (0x80050710, game state 8; modes.md#match-flow): character select, the mode's start
## and fight hooks, the VS screen, loading the fighters, the rounds, the mode's end hook, and the
## continue, game over and new challenger screens (sub-states 9–14, screens_sim.fight_main).

const FIRST_ROUND_FRAMES := 0x3B
const CHALLENGER_WAIT := 8
const CONTINUE_FRAMES := 808
const DIGIT_FRAMES := 90
const GAME_OVER_FRAMES := 0x79
const CHALLENGER_FRAMES := 0x4A
const CHALLENGER_LOAD := 0x28
const CHALLENGER_FREEZE := 0x18
const SOUND_CHALLENGER := 0x49A1
const SYSTEM_CONTINUE := 0x16
const SYSTEM_GAME_OVER := 0x1017
const MUSIC_GAME_OVER := 3
const MUSIC_FADE := 0x3C
const QUICK_BYTES := 0xFFFF00FF      ## FUN_80051204: bytes 0, 2 and 3 of 0x800AFF5C
## The sub-states of game state 8 (modes.md#match-flow).
enum Sub {
	SELECT, MODE_START, NEXT_FIGHT, LOAD, LOAD_WAIT, DISPLAY_OFF, DISPLAY_ON, ROUND_START, FIGHT,
	CONTINUE_START, CONTINUE, GAME_OVER_START, GAME_OVER, CHALLENGER_START, CHALLENGER,
	OGRE_DISPLAY_ON, OGRE_SETUP, OGRE, OGRE_DISPLAY_OFF, TRUE_OGRE_DISPLAY_ON, TRUE_OGRE,
	AREA_DISPLAY_OFF, AREA_DISPLAY_ON, FORCE_BOSS, DEMO_OVER, EXIT,
}

var ogre: OgreScene


func _init(flow: GameFlow) -> void:
	super(flow)
	ogre = OgreScene.new(flow)


## FUN_80051204: the mode (or a challenger) asks for quick select.
func quick_select() -> bool:
	return g.region.u32(0x5C) & QUICK_BYTES != 0


func step() -> void:
	if g.menu_exit():
		return
	var region := g.region
	var sim := g.sim
	match g.sub:
		Sub.SELECT:
			_select()
		Sub.MODE_START:
			_mode_start()
		Sub.NEXT_FIGHT:
			_next_fight()
		Sub.LOAD, Sub.LOAD_WAIT:
			if g.sub == Sub.LOAD:
				var gl := g.globals
				sim.load_fighters(gl.player_char, gl.player_costume, gl.player_cpu)
				g.sub = Sub.LOAD_WAIT
			if (g.fight.vblank - sim.state_timer) & 0xFFFFFFFF > FIRST_ROUND_FRAMES:
				g.sub = Sub.DISPLAY_OFF
		Sub.DISPLAY_OFF:
			g.display(1)
			g.sub = Sub.DISPLAY_ON
		Sub.DISPLAY_ON:
			g.display(0)
			g.sub = Sub.ROUND_START
		Sub.ROUND_START:
			sim.camera.overhead = 0
			sim.round_start()
			g.fight.hud_shown = 1 if region.mode != GameMode.PRACTICE else 0
			g.fight.challenger_lock = 0
			region.challenger = 0
			sim.state_timer = CHALLENGER_WAIT
			g.sub = Sub.FIGHT
		Sub.FIGHT:
			_fight()
		Sub.CONTINUE_START, Sub.CONTINUE:
			_continue(g.sub == Sub.CONTINUE_START)
		Sub.GAME_OVER_START, Sub.GAME_OVER:
			_game_over(g.sub == Sub.GAME_OVER_START)
		Sub.CHALLENGER_START, Sub.CHALLENGER:
			_challenger(g.sub == Sub.CHALLENGER_START)
		Sub.OGRE_DISPLAY_ON:
			g.display(0)
			g.sub = Sub.OGRE_SETUP
		Sub.OGRE_SETUP:
			ogre.setup()
			g.sub = Sub.OGRE
		Sub.OGRE:
			var over := ogre.step()
			if ogre.fade_drawn >= 0:
				g.fades.append(ogre.fade_drawn)
			if over or g.pressed(region.human_index) & PadState.START:
				ogre.end()
				g.sub = Sub.OGRE_DISPLAY_OFF
		Sub.OGRE_DISPLAY_OFF:
			g.display(1)
			g.sub = Sub.TRUE_OGRE_DISPLAY_ON
		Sub.TRUE_OGRE_DISPLAY_ON:
			g.display(0)
			g.sub = Sub.TRUE_OGRE
		Sub.TRUE_OGRE:
			_true_ogre()
		Sub.AREA_DISPLAY_OFF:
			g.display(1)
			g.sub = Sub.AREA_DISPLAY_ON
		Sub.AREA_DISPLAY_ON:
			g.display(0)
			g.sub = Sub.FORCE_BOSS
		Sub.FORCE_BOSS:
			# Tekken Force's area change: the level's boss (FUN_800B2B3C).
			sim.force_boss()
			g.sub = Sub.FIGHT
		Sub.DEMO_OVER:
			# The demonstration fight is over: the ranking, or the title at attract step 3.
			g.controllers_reset()
			if g.progress.attract_step != 3:
				g.goto_ranking()
			else:
				g.goto_transition(GameFlow.State.TITLE)
		_:
			# Practice's RESET (EXIT) and others.
			g.controllers_reset()
			g.sound(GameFlow.SOUND_START)
			g.goto_transition(GameFlow.State.MENU)


## Character select (or quick select); the demonstration fight skips it.
func _select() -> void:
	var region := g.region
	g.fight.challenger_lock = 0
	if region.mode == GameMode.DEMO:
		g.globals.controller[0] = 0
		g.globals.controller[1] = 0
		g.sub = Sub.MODE_START
		_mode_start()
	else:
		g.globals.controller[0] = g.progress.controller(0)
		g.globals.controller[1] = g.progress.controller(1)
		region.vs_next_state = GameFlow.State.FIGHT
		region.vs_next_sub = Sub.MODE_START
		if not quick_select():
			g.queue_overlay(GameFlow.SLOT_SCREEN, GameFlow.OVERLAY_SELECT)
			g.goto_loader(GameFlow.State.SELECT, 0)
		else:
			g.display(1)
			g.state = GameFlow.State.QUICK_SELECT
			g.sub = Sub.SELECT


## CONTINUE?: the loser's countdown over the frozen fight; the same fight, select again, or game
## over.
func _continue(first: bool) -> void:
	var region := g.region
	var sim := g.sim
	if first:
		g.system_sound(SYSTEM_CONTINUE)
		g.music_volume(MUSIC_FADE, MUSIC_FADE)
		sim.state_timer = CONTINUE_FRAMES
		region.continuing = 1
		g.sub = Sub.CONTINUE
	sim.fight_frame()
	var r := _continue_countdown(region.match_loser)
	if r == 1 or r == 2:
		g.sub = Sub.NEXT_FIGHT if r == 1 else Sub.SELECT
		region.continuing = 0
		g.globals.set_tie_winner(g.fight, region.match_winner)
	elif r != 0:
		g.sub = Sub.GAME_OVER_START
		region.continuing = 0


## GAME OVER over the fight, then the ranking.
func _game_over(first: bool) -> void:
	var region := g.region
	var sim := g.sim
	if first:
		sim.state_timer = 0
		g.globals.player_active[region.match_loser] = 0
		g.system_sound(SYSTEM_GAME_OVER)
		g.music(MUSIC_GAME_OVER)
		g.sub = Sub.GAME_OVER
	g.texts.append(RoundHud.Message.new("GAME OVER", 1, 2, 0x55, 200))
	sim.fight_frame()
	sim.state_timer += 1
	if sim.state_timer >= GAME_OVER_FRAMES:
		g.goto_ranking()


## A NEW CHALLENGER ENTERS!!: the fight freezes, then character select (or quick select at once).
func _challenger(first: bool) -> void:
	var region := g.region
	var sim := g.sim
	var done := false
	if first:
		g.sound(SOUND_CHALLENGER)
		g.music_volume(0, 0x1E)
		sim.state_timer = CHALLENGER_WAIT
		region.challenger = 1
		done = quick_select()
		if not done:
			g.sub = Sub.CHALLENGER
	if not done:
		if sim.fight_frame() > 0 or sim.state_timer >= CHALLENGER_FREEZE:
			g.fight.freeze = 1
		var t := sim.state_timer
		if t & 0x18:
			g.texts.append(RoundHud.Message.new("A NEW CHALLENGER\n     ENTERS!!", 7, 2, 8, 0x120))
		if t == CHALLENGER_LOAD:
			g.slots[GameFlow.SLOT_SCREEN] = GameFlow.OVERLAY_SELECT
		sim.state_timer = t + 1
		done = t + 1 >= CHALLENGER_FRAMES
	if done:
		g.display(1)
		if region.team_members != 0:
			g.globals.player_keep[1] = 0
			g.globals.player_keep[0] = 0
		g.sub = Sub.SELECT


## Sub-state TRUE_OGRE: the boss of the last stage becomes True Ogre, and the match goes on with the
## same round score (RoundTallySave / RoundTallyRestore; one-round matches restart at 0).
func _true_ogre() -> void:
	var region := g.region
	var fight := g.fight
	var gl := g.globals
	region.ctx_put8(ModeRules.LADDER + 4 * 9, Character.TRUE_OGRE)
	region.match_result = 0
	region.match_winner = 0
	region.match_loser = 0
	region.put8(0x69, 0)
	g.modes.fight_start()
	g.modes.stage_and_music()
	if fight.max_rounds < 2:
		fight.rounds_played = 0
		fight.fighters[0].round_wins = 0
		fight.fighters[1].round_wins = 0
	var played := fight.rounds_played
	var wins := PackedInt32Array([fight.fighters[0].round_wins, fight.fighters[1].round_wins])
	g.sim.load_fighters(gl.player_char, gl.player_costume, gl.player_cpu)
	fight.rounds_played = played
	fight.fighters[0].round_wins = wins[0]
	fight.fighters[1].round_wins = wins[1]
	g.sub = Sub.DISPLAY_OFF


## Sub-state MODE_START: the mode's start hook, then the match counters (falls into NEXT_FIGHT).
func _mode_start() -> void:
	g.modes.mode_start()
	g.region.mode_started = 1
	g.sub = Sub.NEXT_FIGHT
	g.fight.command_scroll_reset()
	_next_fight()


## Sub-state NEXT_FIGHT: the humans, the mode's fight hook, the stage and music, then the VS screen.
func _next_fight() -> void:
	var region := g.region
	var active := g.globals.player_active
	region.human_count = (1 if active[0] != 0 else 0) + (1 if active[1] != 0 else 0)
	region.human_mask = (1 if active[0] != 0 else 0) | (2 if active[1] != 0 else 0)
	g.fight.human_mask = region.human_mask
	match region.human_mask:
		0, 3:
			region.human_index = 0
			region.cpu_index = 0
		1:
			region.human_index = 0
			region.cpu_index = 1
		2:
			region.human_index = 1
			region.cpu_index = 0
	region.match_result = 0
	region.match_winner = 0
	region.match_loser = 0
	region.fight_clock = region.clock_start
	g.modes.fight_start()
	if region.mode == GameMode.FORCE:
		# FUN_800B5910 with the human's pad, and one human on side 0.
		g.fight.force.manual_target_setup(g.sim.pads.physical[g.fight.force.human()])
		region.human_mask = 1
		g.fight.human_mask = 1
		region.human_index = 0
		region.cpu_index = 1
	g.sim.state_timer = g.fight.vblank
	g.modes.stage_and_music()
	region.vs_next_state = GameFlow.State.FIGHT
	region.vs_next_sub = Sub.LOAD
	g.state = GameFlow.State.VS
	g.sub = Sub.SELECT
	g.display(1)


## Sub-state FIGHT: the fight, challengers, and the round's hand-over.
func _fight() -> void:
	var region := g.region
	var sim := g.sim
	var timer := sim.state_timer - 1
	if sim.state_timer == 0:
		timer = 0
		if region.challengers != 0:
			var a := challenger_join(0)
			var b := challenger_join(1)
			if a or b:
				g.sub = Sub.CHALLENGER_START
				return
	sim.state_timer = timer
	var result := sim.fight_frame()
	if region.mode == GameMode.DEMO and result > RoundState.RESULT:
		g.sub = Sub.DEMO_OVER
		return
	if result == RoundState.AREA_CHANGE:
		g.sub = Sub.AREA_DISPLAY_OFF
		return
	if result < RoundState.END:
		return
	if result == RoundState.OGRE_SCENE:
		g.display(1)
		if region.mode != GameMode.TIME_ATTACK:
			g.sub = Sub.OGRE_DISPLAY_ON
		else:
			g.sub = Sub.TRUE_OGRE_DISPLAY_ON
		return
	if result == RoundState.PRACTICE_EXIT:
		g.sub = Sub.EXIT
		return
	if region.mode == GameMode.PRACTICE:
		g.sub = Sub.SELECT
		g.globals.player_active[g.globals.other_player] = 0
		g.globals.player_keep[1] = 0
		g.globals.player_keep[0] = 0
		return
	if region.match_result == 0:
		g.sub = Sub.DISPLAY_OFF
		return
	g.modes.match_end()


## ChallengerJoin (FUN_80051244): a player who is not playing presses Start.
func challenger_join(player: int) -> bool:
	if g.pressed(player) & PadState.START == 0 or g.fight.challenger_lock != 0:
		return false
	if g.globals.player_active[player] != 0:
		return false
	var held := g.held(player)
	if held & PadState.START:
		g.region.challenger_quick = 1 if held == ModeStart.QUICK_CHALLENGE else 0
	g.globals.player_active[player] = 1
	g.globals.player_keep[player] = 0
	g.globals.other_player = player
	return true


## FUN_800502D8: 1 the same fight again, 2 back to select, 0 counting, −1 over. CONTINUE? n
## counts down from 9, with system sound 4 + n for each digit from 8 on.
func _continue_countdown(player: int) -> int:
	var pressed := g.pressed(player)
	var sim := g.sim
	if pressed & PadState.START:
		g.globals.player_active[player] = 1
		g.sound(GameFlow.SOUND_START)
		if g.region.character_change == 0:
			g.globals.player_keep[player] = 1
			return 1
		g.globals.player_keep[player] = 0
		return 2
	var t := sim.state_timer
	if pressed & GameFlow.FACE_BUTTONS:
		t = 0 if t < DIGIT_FRAMES else t - DIGIT_FRAMES
		sim.state_timer = t
	if t == 0:
		return -1
	if t > 0:
		sim.state_timer = t - 1
	var shown := sim.state_timer + DIGIT_FRAMES
	var n := Fx.div_trunc(shown, DIGIT_FRAMES)
	if n >= 0 and n < 9 and shown - DIGIT_FRAMES * n == DIGIT_FRAMES - 1:
		g.system_sound(0x1004 + n if n != 0 else SYSTEM_GAME_OVER)
	g.texts.append(RoundHud.Message.new("CONTINUE? %d" % n, 9, 2, 0x3F, 200))
	return 0
