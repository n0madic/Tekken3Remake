class_name ArcadeGameFlow
extends RefCounted
## The arcade's whole game (`main` at 0x801899F4, World ver. E1): boot, the transition with its
## NAMCO PRESENTS, the attract, the match flow, the character select, the ranking and the ending,
## on free play (the remake has no coins, so the title's coin state is reached by nothing).
## Written from the code and proven by tests/game/test_arcade_flow_traces.gd.
##

enum State { BOOT = 0, TRANSITION = 1, ATTRACT = 2, TITLE = 3, MATCH = 4, SELECT = 5, RANKING = 7, ENDING = 8 }
## The attract's picture (FUN_801BD318's kinds).
enum Picture { NONE = 0, MOVIE = 1, TITLE_PROMPT = 2, TITLE = 5, ENBU = 6, BLACK = 7 }

const MODE_ARCADE := 0
const MODE_DEMO := 6
const START := 0x8000
const FLAG_CHALLENGERS := 2             ## 0x80374F1C: a second player may join
const FLAG_RELOAD_ON_JOIN := 4
const ATTRACT_MOVIE := 0
const ATTRACT_FLASH := 1
const ATTRACT_ENBU := 2
const ATTRACT_LAST := 3
const PRESENTS_FADE_FRAMES := 0x20
const PRESENTS_HOLD := 0x5A
const FLASH_STEP := 10
const FLASH_HOLD := 0xB
const FADE_FULL := 0x100
const TITLE_FADE_STEP := 3
const TITLE_FRAMES := 300
const TITLE_OUT_STEP := 8
const TITLE_WAIT := 0x1E0
const SOUND_MOVIE := 0x60
const CREDIT_SEQUENCE := 0x103
const CREDIT_CHANNEL := 0x17
const ATTRACT_ENBU_RUNNING := 4         ## FUN_801BD97C's sub-state of the demonstration
const MOVIE_VBLANKS := 4                ## FUN_801BD318: a movie frame waits for its fourth vblank
const LOADED_ON_TRANSITION := 6         ## 0x8021F230: the set of pictures FUN_801B1E58 loads
const STAGES := 13
const TEXT_CONTINUE := "continue"
const TEXT_GAME_OVER := "game_over"
const TEXT_CHALLENGER := "challenger"

var data: ArcadeFlowData
var settings: ArcadeSettings
var progress := ArcadeProgress.new()
var sim: ArcadeSimulation
var fight: FightState
var match_flow: ArcadeMatchFlow
var select: ArcadeSelect
var ranking: ArcadeRanking
var ending: ArcadeEnding

var state := State.BOOT as int          ## 0x8021FD20
var sub := 0                            ## 0x8021FD64
var timer := 0                          ## 0x8021FD4C
var mode := MODE_ARCADE                 ## 0x80374F18
var flags := 0                          ## 0x80374F1C, low half
var return_state := 0                   ## 0x80374F1E
var return_sub := 0                     ## 0x80374F1F
var attract_silent := 1                 ## 0x8021FC64: the sounds are off while it is set

# The players, u16 pairs in the game's globals.
var active := PackedInt32Array([0, 0])  ## 0x8021FD18: in the game
var chosen := PackedInt32Array([0, 0])  ## 0x8021FCF8: has a fighter
var cpu_control := PackedInt32Array([0, 0])   ## 0x8021FB58
var chars := PackedInt32Array([0, 0])   ## 0x8021FBF0
var costumes := PackedInt32Array([0, 0])   ## 0x8021FC0C
var plays := PackedInt32Array([0, 0])   ## 0x8021FC74: games paid for
var loser_timer := PackedInt32Array([0, 0])   ## 0x8021FB4C: the HUD's CONTINUE?
var picks_character := PackedInt32Array([Character.NONE, Character.NONE])   ## 0x80374F20
var picks_costume := PackedInt32Array([0, 0])   ## 0x80374F22
var challenger_lock: int:               ## 0x8021FD48
	get: return fight.challenger_lock
	set(v): fight.challenger_lock = v
var round_started := 0                  ## 0x8021FD1C

# The transition.
var transition_ready := 0               ## 0x8021F22C
var transition_target := State.ATTRACT as int  ## 0x8021F22D
var transition_from := State.MATCH as int     ## 0x8021F22E
var transition_loaded := 0              ## 0x8021F22F
var transition_set := 0                 ## 0x8021F230

# The attract.
var attract_step := ATTRACT_ENBU        ## 0x8021F231
var attract_previous := 4               ## 0x8021F232
var picture := Picture.NONE as int      ## 0x8021F288
var movie_length := 0                   ## 0x8021F284
var enbu: ArcadeEnbu

# What the views show of this frame.
var texts := PackedStringArray()         ## the keys of the flow's texts this frame (ArcadeFightHud)
var fades := PackedInt32Array()         ## FUN_801B354C's levels this frame
var presents_level := 0
var presents_shown := false


func _init(fight_content: ArcadeFightContent, flow_data: ArcadeFlowData, rules: RuleSet, operator: ArcadeSettings, seed_value: int) -> void:
	data = flow_data
	settings = operator
	sim = ArcadeSimulation.new(fight_content, null, rules)
	fight = sim.fight
	fight.rng.set_seed(seed_value)
	fight.camera_rng = seed_value
	fight.frame_rng = seed_value
	match_flow = ArcadeMatchFlow.new(self)
	select = ArcadeSelect.new(self)
	ranking = ArcadeRanking.new(self)
	ending = ArcadeEnding.new(self)
	enbu = ArcadeEnbu.new(self)
	progress.reset_records(data)
	progress.apply_schedule(data)


## One frame of `main`'s loop with the panels' words.
func step(panel_0: int, panel_1: int) -> void:
	sim.begin_panels(PackedInt32Array([panel_0, panel_1]))
	sim.round_sounds.silent = attract_silent != 0 or match_flow.freeze_on_challenger != 0
	fight.unlocked = progress.unlocked
	sim.in_match = state == State.MATCH
	texts.clear()
	fades.clear()
	presents_shown = false
	match state:
		State.BOOT:
			_boot()
		State.TRANSITION:
			_transition()
		State.ATTRACT:
			_attract()
		State.TITLE:
			_title()
		State.MATCH:
			match_flow.step()
		State.SELECT:
			select.step()
		State.RANKING:
			ranking.step()
		State.ENDING:
			ending.step()
	fight.frame_counter += _counted_vblanks() - 1


## Whether the frame shows a fight running: the rounds (from their first frame, the frame the load
## ends still shows the VS screen), CONTINUE?, GAME OVER, a new challenger, the scenes, the ending's
## replays.
func showing_fight() -> bool:
	match state:
		State.ENDING:
			return ending.in_fight()
		State.ATTRACT:
			return sub == ATTRACT_ENBU_RUNNING and enbu.drawn()
		State.MATCH:
			if sub == ArcadeMatchFlow.Sub.OGRE:
				return true
			return round_started != 0 and sub >= ArcadeMatchFlow.Sub.ROUND and sub <= ArcadeMatchFlow.Sub.CHALLENGER
	return false


## The vblanks the game's counter sees in the frame just stepped: one, but for the movie's.
func _counted_vblanks() -> int:
	return MOVIE_VBLANKS if state == State.ATTRACT and picture == Picture.MOVIE else 1


## How long the frame just stepped lasts in the original: its counted vblanks and the ending's
## blocking wait, whose vblanks the frame counter leaves out as the oracle's VSync does (on the
## board it counts them: an even number, which changes no parity the game reads).
func frame_vblanks() -> int:
	return _counted_vblanks() + (ending.wait_vblanks if state == State.ENDING else 0)


## 0x8021FD58: the frame's snapshot of the vblank counter.
func frame() -> int:
	return fight.frame_counter


func pressed(player: int) -> int:
	return sim.panels.pressed[player]


func held(player: int) -> int:
	return sim.panels.held[player]


func repeat(player: int) -> int:
	return sim.panels.repeat[player]


## FUN_801B7A8C: bit 1 in the game, bit 0 has a fighter.
func side_kind(player: int) -> int:
	return (2 if active[player] != 0 else 0) | (1 if chosen[player] != 0 else 0)


func add_text(key: String) -> void:
	texts.append(key)


func add_fade(level: int) -> void:
	fades.append(level)


## The test of FUN_801B0810, FUN_801B0968 and FUN_801B0A30: the sound board hears nothing in a silent attract.
func sounds_on() -> bool:
	return settings.attract_sound != 0 or attract_silent == 0


## FUN_801B0968: what the sound board plays, unless the attract is silent.
func sound(code: int, channel: int = 0) -> void:
	if sounds_on():
		sim.events.add(SimEvents.Kind.SYSTEM_SOUND, -1, code, channel)


func music(track: int) -> void:
	if sounds_on():
		sim.events.add(SimEvents.Kind.MUSIC, -1, track)


## FUN_801B09C4 on channel 0: with neither of the command's top bits, the music's channel ends.
func stop_music() -> void:
	if sounds_on():
		sim.events.add(SimEvents.Kind.MUSIC_STOP, -1)


## FUN_801B0ACC: every channel ends, with `keep` but the last.
func stop_sounds(keep: int) -> void:
	sim.events.add(SimEvents.Kind.VOICES_OFF, -1, keep)


## FUN_801B0B14: the player channels fall silent.
func silence_players() -> void:
	sim.events.add(SimEvents.Kind.VOICE_OFF, -1, 0)


## FUN_801B0A88: a credit taken.
func credit_sound() -> void:
	sim.events.add(SimEvents.Kind.SYSTEM_SOUND, -1, CREDIT_SEQUENCE, CREDIT_CHANNEL)


## FUN_801A0C10.
func voice(code: int) -> void:
	sim.events.add(SimEvents.Kind.SOUND, -1, code, 0)


## FUN_801B7924 on free play: 1 when the player joins now. A Start noted while the fighters loaded
## counts too.
func challenger(p: int) -> int:
	_loser_clock(p)
	var waiting := match_flow.start_held[p]
	if pressed(p) & START == 0 and waiting == 0:
		return 0
	match_flow.start_held[p] = 0
	if challenger_lock != 0 or active[p] != 0:
		return 0
	match_flow.joins += 1
	active[p] = 1
	chosen[p] = 0
	plays[p] = 1
	loser_timer[p] = 0
	match_flow.other = p
	return 1


## FUN_801B64C8: the HUD's countdown of the player who lost a versus fight.
func _loser_clock(p: int) -> void:
	if loser_timer[p] == 0:
		return
	loser_timer[p] -= 1
	if pressed(p) & ArcadeMatchFlow.CONTINUE_BUTTONS != 0:
		loser_timer[p] = maxi(loser_timer[p] - ArcadeMatchFlow.CONTINUE_DIGIT, 0)
	if loser_timer[p] == 0:
		plays[p] = 0


## FUN_801B5EC0.
func goto_transition(target: int) -> void:
	transition_from = state
	transition_target = target
	state = State.TRANSITION
	sub = 0


## FUN_801B7810 on free play: a Start starts a game from the attract's states.
func start_check() -> bool:
	var starting := 0
	for p in 2:
		if pressed(p) & START != 0:
			starting |= 1 << p
	if starting == 0:
		return false
	start_mode(MODE_ARCADE, starting)
	return true


## FUN_801BDA64.
func start_mode(new_mode: int, players: int) -> void:
	stop_sounds(0)
	if new_mode != MODE_DEMO:
		credit_sound()
	mode = new_mode
	match_flow.reset_context()
	for p in 2:
		picks_character[p] = Character.NONE
		picks_costume[p] = 0
		chosen[p] = 0
		active[p] = 0
		plays[p] = 0
		loser_timer[p] = 0
	# FUN_801BAE34 (the kept fights went with the context: FUN_80194EFC(0)).
	progress.apply_schedule(data)
	round_started = 0
	attract_silent = 0
	challenger_lock = 0
	flags = (flags & ~0x300) | (settings.reselect & 1) << 8
	match_flow.ladder_built = 0
	match_flow.rounds = settings.rounds_one
	if new_mode == MODE_ARCADE and settings.event_mode != 0:
		players = 3
	for p in 2:
		if players >> p & 1:
			match_flow.lead_player(p)
			active[p] = 1
			plays[p] = 1
	match new_mode:
		MODE_ARCADE:
			match_flow.name_entry.phase = 0     # FUN_801B901C
			var versus_change := (settings.versus_change & 1) << 2
			if settings.event_mode == 0:
				flags = (flags & ~0x14) | 3 | versus_change | 8
			else:
				flags = (flags & ~4) | 3 | versus_change | 0x18
			flags &= ~0xE0
			match_flow.reset_stage_times()
			ranking.kind = ArcadeRanking.PAGE_USAGE
		MODE_DEMO:
			attract_silent = 1
			flags = (flags & ~0xBF) | 0x40
			match_flow.demo_fighters()
			match_flow.demo_banner()
	state = State.MATCH
	sub = 0


## FUN_80189EC8.
func _boot() -> void:
	match sub:
		0:
			sub = 1
		1:
			sub = 2
		2:
			goto_transition(State.ATTRACT)


## FUN_801B5EEC.
func _transition() -> void:
	if transition_ready != 0 and sub > 2 and start_check():
		return
	match sub:
		0, 1:
			sub += 1
			return
		2:
			attract_silent = 1
			if transition_ready == 0:
				transition_target = State.ATTRACT
				transition_from = State.MATCH
				transition_loaded = 0
				transition_ready = 1
			if transition_from == State.TRANSITION or transition_from == State.TITLE:
				transition_loaded = mini(transition_loaded, 2)
			else:
				transition_loaded = 0
			if transition_loaded == 0 or transition_set != LOADED_ON_TRANSITION:
				transition_set = LOADED_ON_TRANSITION
				transition_loaded = 1
			transition_loaded = maxi(transition_loaded, 2)
			if transition_target != State.ATTRACT or attract_step == ATTRACT_FLASH or attract_step == ATTRACT_LAST:
				_transition_end()
				return
			sub = 3
			timer = 0
			_presents_in()
		3:
			_presents_in()
		4:
			sub = 5
			_presents_hold()
		5:
			_presents_hold()
		6:
			timer -= 1
			if timer < 1:
				timer = 0
				sub = 7
			add_fade(timer << 3)
		7:
			_transition_end()
			return
	presents_shown = true


func _presents_in() -> void:
	add_fade(timer << 3)
	timer += 1
	if timer > PRESENTS_FADE_FRAMES:
		sub = 4
		timer = frame()


func _presents_hold() -> void:
	if frame() - timer > PRESENTS_HOLD:
		timer = PRESENTS_FADE_FRAMES
		sub = 6


func _transition_end() -> void:
	sub = 0
	state = transition_target


## FUN_801BD5A0.
func _attract() -> void:
	if start_check():
		return
	match sub:
		0:
			match attract_step:
				ATTRACT_FLASH, ATTRACT_LAST:
					sub = 6
				ATTRACT_ENBU:
					sub = 3
				_:
					sub = 1
			picture = Picture.BLACK
			timer = 0
		1:
			picture = Picture.MOVIE
			movie_length = data.movie_frames + 1
			music(SOUND_MOVIE)
			sub = 2
		2:
			picture = Picture.MOVIE
			timer += 1
			if timer > movie_length:
				sub = 9
		3:
			picture = Picture.NONE
			enbu.start()
			attract_silent = 1
			sub = 4
		4:
			picture = Picture.ENBU
			if enbu.step():
				sub = 5
		5:
			picture = Picture.ENBU
			sub = 9
		6:
			picture = Picture.NONE
			timer = 0
			sub = 7
			_flash()
		7:
			_flash()
		8:
			_flash_hold()
		9:
			picture = Picture.TITLE
			timer = FADE_FULL
			sub = 10
			_title_fade()
		10:
			_title_fade()
		11:
			picture = Picture.TITLE_PROMPT
			timer -= 1
			if timer == 0:
				timer = FADE_FULL
				sub = 12
		12:
			if timer < 1:
				picture = Picture.BLACK
				sub = 13
			else:
				timer -= TITLE_OUT_STEP
				add_fade(timer)
		_:
			attract_previous = attract_step
			attract_step += 1
			if attract_step > ATTRACT_LAST:
				attract_step = ATTRACT_MOVIE
			picture = Picture.BLACK
			start_mode(MODE_DEMO, 0)


func _flash() -> void:
	if timer + FLASH_STEP < FADE_FULL:
		timer += FLASH_STEP
		add_fade(timer + FADE_FULL + FLASH_STEP)
		return
	timer = 0
	sub = 8
	_flash_hold()


func _flash_hold() -> void:
	add_fade(2 * FADE_FULL)
	timer += 1
	if timer >= FLASH_HOLD:
		sub = 9


func _title_fade() -> void:
	if timer < 1:
		timer = TITLE_FRAMES
		sub = 11
		return
	var level := timer + 0xFD
	timer -= TITLE_FADE_STEP
	add_fade(level)


## FUN_801BD97C: reached only through a coin's edge, kept for the state's table.
func _title() -> void:
	if start_check():
		return
	match sub:
		0:
			attract_step = (attract_step + 2) & 2
			stop_sounds(1)
			timer = 0
			sub = 1
		1:
			timer += 1
			if timer > TITLE_WAIT:
				sub = 2
		_:
			goto_transition(State.ATTRACT)
	picture = Picture.TITLE_PROMPT


