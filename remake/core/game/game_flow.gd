class_name GameFlow
extends RefCounted
## The whole game as a frame-stepped state machine (modes.md#game-states): the main loop's frame
## work and the handler of the game state 0x800AE6CC, with the game's own states and sub-states,
## so that `tests/app/test_game_flow.gd` can compare every frame with the game running in the
## CPU harness (tools/research/flow_trace.py).
##
## The fight is the session's FightSimulation; its FightState holds the game's globals the fight
## code shares (the mode region, the progress block, the random generators). Screens with state of
## their own are separate objects (MainMenu, QuickSelect, CharacterSelect, VsScreen, the results,
## the ranking, the ending and Theater, the options). Loading takes no time: an overlay load costs
## the frames the loader state takes with an idle disc, as in the harness.

enum State { BOOT = 0, LOADER = 1, TRANSITION = 2, TITLE = 3, MENU = 4, OPTIONS = 5, ENBU = 6,
	PREPARE = 7, FIGHT = 8, SELECT = 9, QUICK_SELECT = 10, VS = 11, TEAM_RESULT = 12,
	TIME_RESULT = 13, SURVIVAL_RESULT = 14, FORCE_RESULT = 15, RANKING_LOAD = 16, RANKING = 17,
	SCREEN_LOADER = 18, ENDING = 19 }

const FACE_BUTTONS := PadState.FACE_BUTTONS
const SOUND_START := 0x4CC0
const PRESENTS_FADE_FRAMES := 0x20
const PRESENTS_HOLD := 0x5A
const WHITE_HOLD := 11
const TITLE_FRAMES := 300
const MUSIC_ENBU := 0
const ENBU_STAGE := 4
## Title picture kinds (FUN_800DAAD8): every other kind is a black fade.
const PICTURE_BLACK := 0
const PICTURE_MOVIE := 1
const PICTURE_TITLE_PROMPT := 2
const PICTURE_TITLE := 5
const PICTURE_NONE := 7
const PICTURE_FADE := 8
const PICTURES_DRAWN: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
## The loader's overlays (the slot and the overlay kept in it).
const SLOT_MODE := 0
const SLOT_SCREEN := 1
const OVERLAY_TITLE := 5
const OVERLAY_ENBU := 7
const OVERLAY_SELECT := 4
const OVERLAY_RESULT := 9
const OVERLAY_ENDING := 8
const OVERLAY_RANKING := 6

var content: FightContent
var data: FlowData
var sim: FightSimulation
var fight: FightState
var progress: GameProgress
var region: ModeRegion
var globals := GameGlobals.new()
var rules: ProgressRules
var modes: ModeRules
var key_tables: Array[PackedInt32Array] = []   ## 0x80098290: per player the mapped word of each physical bit

var state := State.BOOT                  ## 0x800AE6CC
var sub := 0                             ## 0x800AE6EC
var movies_available := true
var movie := 0                           ## 0x800B09B8: the title's movie
var movie_result := 0                    ## 1 finished, −1 skipped or failed, 0 playing
## A movie the game plays inside one frame (the ending, Theater): the frames wait for it.
var movie_blocking := false
var music_countdown := 0                 ## 0x800A0986: the music stream's start timer (s16)

# The overlay loader (FUN_80052EC8, FUN_80052F18, FUN_80052FAC).
var loader_queue: Array[PackedInt32Array] = []   ## (slot, overlay) per queued load
var loader_target := Vector2i(0, 0)              ## 0x8009853E/F
var slots := PackedInt32Array([-1, -1])          ## the overlay in each slot

# Screens with their own state.
var menu: MainMenu
var quick: QuickSelect
var select: CharacterSelect
var ranking: RankingScreen
var results: ResultScreens
var ending: EndingScreen
var theater: TheaterScreen
var options: OptionsScreen
var practice: PracticeMode
var escape_pressed := false          ## the remake's Escape on a pause menu, pending until the menu takes it (not a button of the game's pads)
var vs_screen: VsScreen
var match_flow: MatchFlow

## The demonstration's performance: a callable taking the demonstration number and returning an
## EnbuPerformance (or null to count `performance_frames` frames instead, for tests).
var performance_factory: Callable
var performance: EnbuPerformance
var performance_frames := 3549
var _performance_count := 0
var title_kind := PICTURE_FADE           ## 0x800EB290
var enbu_kind := PICTURE_FADE            ## 0x800DDE28

## Per frame: what the screen shows (the sounds and music go out as the fight's SimEvents).
var presents_mode := -1                  ## FUN_8004FA38: 0 text fading (level), 1 text, 2 black, 3 nothing
var presents_level := 0
var picture := -1                        ## FUN_800DAAD8's picture kind this frame
var fades := PackedInt32Array()          ## FUN_8004E2E8 levels drawn this frame
var movie_started := -1
var performed := false
var texts: Array[RoundHud.Message] = []  ## FightMain's own texts: CONTINUE?, GAME OVER, A NEW CHALLENGER
var save_requested := false              ## the transition screen saves (auto save)
## Reads the save file at the first transition screen (FUN_8004C658): returns its data, or an
## empty array when there is none (the defaults stay).
var card_loader: Callable


func _init(fight_content: FightContent, flow_data: FlowData, fight_rules: RuleSet, seed: int) -> void:
	content = fight_content
	data = flow_data
	sim = FightSimulation.new(content, null, fight_rules)
	fight = sim.fight
	progress = fight.progress
	region = fight.region
	progress.bytes = GameProgress.defaults(data.progress).bytes
	key_tables = data.key_tables.duplicate(true)
	rules = ProgressRules.new(progress, globals, region, data, fight_rules)
	modes = ModeRules.new(self)
	menu = MainMenu.new(self)
	quick = QuickSelect.new(self)
	select = CharacterSelect.new(self)
	ranking = RankingScreen.new(self)
	results = ResultScreens.new(self)
	ending = EndingScreen.new(self)
	theater = TheaterScreen.new(self)
	options = OptionsScreen.new(self)
	practice = PracticeMode.new(self)
	sim.practice = practice
	fight.practice_pads = practice.record_pad
	vs_screen = VsScreen.new(self)
	match_flow = MatchFlow.new(self)
	# The globals' values in the executable image (the fight simulation's own defaults are VS's).
	fight.round_time_option = 0
	fight.human_mask = 0
	fight.ai_difficulty = 0
	fight.ai_level = 0
	fight.tie_choice = 0
	fight.stage = 0
	fight.music = 0
	# BootInit: the random generators (seeded from the scratchpad's contents by the game).
	fight.rng.set_seed(seed)
	fight.camera_rng = seed & 0xFFFFFFFF
	fight.frame_rng = seed & 0xFFFFFFFF
	fight.attract = 1
	globals.display_on = 1


## One frame of the main loop with the pads' physical buttons.
func step(buttons: PackedInt32Array) -> void:
	if movie_blocking:
		if movie_result == 0:
			# The ending's movie player reads the pads every frame it plays (FUN_8010D7E0 calls
			# FUN_8002A014): the button that skips it, still held after it, is no new press. The
			# step that finishes the frame reads none (a press there reaches the next frame).
			sim.pads.read(buttons, key_tables)
			return
		# The rest of the frame that started the movie: the movie it asked for has played, so the
		# owner must not start it again (the other outputs stay those of that frame).
		movie_blocking = false
		movie_started = -1
		ending.after_movie()
		return
	sim.begin_frame(buttons, key_tables)
	presents_mode = -1
	picture = -1
	fades = PackedInt32Array()
	movie_started = -1
	performed = false
	texts.clear()
	save_requested = false
	_update_escape()
	match state:
		State.BOOT:
			_boot()
		State.LOADER:
			_loader()
		State.TRANSITION:
			_transition()
		State.TITLE:
			_title()
		State.MENU:
			menu.step()
		State.OPTIONS:
			options.step()
		State.ENBU:
			_enbu()
		State.PREPARE:
			_fight_prepare()
		State.FIGHT:
			match_flow.step()
			if fight.save_request:
				fight.save_request = false
				rules.request_save()
		State.SELECT:
			select.step()
		State.QUICK_SELECT:
			quick.step()
		State.VS:
			vs_screen.step()
		State.TEAM_RESULT:
			results.team_step()
		State.TIME_RESULT:
			results.time_attack_step()
		State.SURVIVAL_RESULT:
			results.survival_step()
		State.FORCE_RESULT:
			results.force_step()
		State.RANKING_LOAD:
			ranking.load_step()
		State.RANKING:
			ranking.step()
		State.SCREEN_LOADER:
			_screen_loader()
		State.ENDING:
			ending.step()
		_:
			goto_transition(State.MENU)


## The pads as the screens read them.
func pressed(player: int) -> int:
	return sim.pads.physical_pressed[player]


func held(player: int) -> int:
	return sim.pads.physical[player]


func repeat(player: int) -> int:
	return sim.pads.repeat[player]


func pressed_any() -> int:
	return pressed(0) | pressed(1)


## SoundPlayFighter(0, code, 0): the menus' sounds.
func sound(code: int) -> void:
	sim.events.add(SimEvents.Kind.SOUND, -1, code, 0)


func system_sound(code: int) -> void:
	sim.events.add(SimEvents.Kind.SYSTEM_SOUND, -1, code & 0xFFF)


## MusicPlay (the track, −1 stops).
func music(track: int) -> void:
	sim.events.add(SimEvents.Kind.MUSIC, -1, track)


## FUN_8006C870: the music stops.
func music_stop() -> void:
	sim.events.add(SimEvents.Kind.MUSIC_STOP, -1)


## A disc read (BnsStartQueuedLoads: the overlay loader, the menu's overlay, the VS screen's
## pictures, Tekken Ball's and Force's stages; a movie, as the movie players start):
## FUN_8006B834(0) pauses the drive, and with it the XA music, which does not resume.
func disc_read() -> void:
	music_stop()


func music_volume(volume: int, frames: int) -> void:
	sim.events.add(SimEvents.Kind.MUSIC_VOLUME, -1, volume, frames)


## A movie played within the frame (FUN_8010D474): the frame finishes when it ends.
func start_blocking_movie(id: int) -> void:
	disc_read()
	fight.stage_cached = -1           # FUN_8006C870(0x1F): the movie's buffers overwrite it
	movie_result = 0
	movie_started = id
	movie_blocking = true
	if not movies_available:
		movie_result = 1


## FUN_8006BCC8: whether the music has started. The remake's music starts at once, as the game's
## does with no stream playing: the first call of the session only counts the stream's timer
## down, later calls run FUN_8006AE4C (the volume up).
func music_ready() -> bool:
	if music_countdown < 0:
		music_volume(0x7F, -1)
	else:
		music_countdown -= 1
	return true


## FUN_80029860: the display switch (0: on).
func display(off: int) -> void:
	globals.display_on = 1 if off == 0 else 0


# ---- state changes ----------------------------------------------------------------------------

## FUN_8004FBE0: go to a state through the transition screen. Going to the title plays the next
## attract demonstration at attract step 1 (or the one R1 / L1 / L1 + R1 choose).
func goto_transition(target: int) -> void:
	display(1)
	progress.enbu_target = 0
	if target == State.TITLE:
		var demo := progress.demo_number
		var buttons := held(0)
		if buttons & ~(PadState.L1 | PadState.R1) & 0xFFFF:
			buttons = 0
		var top := progress.unlock_class
		if top == 0 or buttons == 0:
			if progress.attract_step == 1:
				demo += 1
		else:
			var choice := demo
			match buttons:
				PadState.R1:
					choice = 0
				PadState.L1:
					choice = 1
				PadState.L1 | PadState.R1:
					choice = 2
			if top < choice:
				choice = progress.demo_number
			else:
				progress.attract_step = 1
			demo = choice
		if top < demo:
			demo = 0
		progress.demo_number = demo
		progress.enbu_target = 1
		if progress.attract_step == 1:
			target = State.ENBU
		else:
			progress.enbu_target = 0
	progress.transition_target = target
	progress.previous_state = state
	state = target_state(State.TRANSITION)
	sub = 0


static func target_state(s: int) -> State:
	return s as State


## FUN_80050208: go to a state through the screen-overlay loader.
func goto_screen_loader(target: int) -> void:
	display(1)
	progress.previous_state = state
	state = State.SCREEN_LOADER
	progress.transition_target = target
	sub = 0


## FUN_80050478.
func goto_ranking() -> void:
	display(1)
	state = State.RANKING_LOAD
	sub = 0


## FUN_80052EC8: a load for the overlay loader.
func queue_overlay(slot: int, overlay: int) -> void:
	if loader_queue.size() < 8:
		loader_queue.append(PackedInt32Array([slot, overlay]))


## FUN_80052F18: to `to` (and `to_sub`), through the loader when loads are queued.
func goto_loader(to: int, to_sub: int) -> void:
	if loader_queue.is_empty():
		state = target_state(to)
		sub = to_sub
		return
	display(1)
	loader_target = Vector2i(to, to_sub)
	state = State.LOADER
	sub = 0


## FUN_80052FAC (game state 1): one load per frame with an idle disc.
func _loader() -> void:
	match sub:
		0:
			display(0)
			sub = 1
		1, 2:
			if sub == 1:
				var load := loader_queue[0]
				slots[load[0]] = load[1]
				disc_read()
				sub = 2
			loader_queue.remove_at(0)
			if loader_queue.is_empty():
				state = target_state(loader_target.x)
				sub = loader_target.y
			else:
				sub = 1
		3:
			if loader_queue.is_empty():
				state = target_state(loader_target.x)
				sub = loader_target.y
			else:
				sub = 1
		4:
			state = target_state(loader_target.x)
			sub = loader_target.y


## ScreenOverlayLoad (0x8005025C, game state 18).
func _screen_loader() -> void:
	display(0)
	fight.stage_cached = -1           # FUN_8006C870(0x1F): the overlay goes where the stage was
	controllers_reset()
	var target := progress.transition_target
	if target == State.ENDING:
		ending.loaded()
	queue_overlay(SLOT_SCREEN, OVERLAY_ENDING if target == State.ENDING else OVERLAY_RESULT)
	goto_loader(target, 0)


## FUN_800291B0: the vibration off and the controller settings cleared.
func controllers_reset() -> void:
	for p in 2:
		globals.controller[p] = 0


## MenuExitCheck (FUN_80051304): Select + Start (Start alone in the demonstration fight) or the
## pause menu's RESET returns to the main menu.
## The remake's Escape on an open pause menu: leaves it as CANCEL (practice: OK) does; false
## while the menu is not taking input yet.
func _escape() -> bool:
	if region.mode == GameMode.PRACTICE and practice != null:
		return practice.escape()
	return PauseMenu.escape(fight, sim.events)


## The remake's Escape on a pause menu, once per frame while it is pending: the menu takes it
## (`_escape`) as soon as it listens. It stays pending through the menu's inert frames and is
## dropped once taken, when no menu is open or when the menu has left its list (Tekken Ball's HOW TO
## page, a confirmed item): Escape does not wait for the page to close.
func _update_escape() -> void:
	if not escape_pressed:
		return
	if not pause_menu_open() or fight.pause_page != 0:
		escape_pressed = false
		return
	escape_pressed = not _escape()


## A pause menu is open and takes the remake's Escape (the move lists take it as Start).
func pause_menu_open() -> bool:
	if state != State.FIGHT:
		return false
	if region.mode == GameMode.PRACTICE and practice != null:
		return practice.s.u8(PracticeMode.PAUSED) != 0 and practice.s.u8(PracticeMode.COMMAND_LIST) == 0
	return fight.paused_player != 0 and fight.pause_page != PauseMenu.PAGE_COMMAND


## The pad the fight's human plays on (practice: its player's): the one whose Start pauses, or −1
## with no human (the demonstration).
func fight_pad() -> int:
	var humans := human_pads()
	if humans & 1 != 0:
		return 0
	return 1 if humans & 2 != 0 else -1


## The pads humans play the fight on, a bit per pad: practice its player's only, else the human
## mask's.
func human_pads() -> int:
	if region.mode == GameMode.PRACTICE:
		return 1 << fight.tie_choice
	return fight.human_mask & 3


## Whether a pad is played by a human in the fight.
func plays_fight(pad: int) -> bool:
	return human_pads() & (1 << pad) != 0


## The pad the remake's Escape presses for when the keyboard is `keyboard_pad`'s, or −1 for that
## pad itself: in a fight (and its preparation) the human's when the keyboard's player does not
## play there (Start of a pad nobody plays would join as a challenger).
func escape_pad(keyboard_pad: int) -> int:
	if state != State.FIGHT and state != State.PREPARE:
		return -1
	var human := fight_pad()
	if human < 0 or plays_fight(keyboard_pad):
		return -1
	return human


## The pad whose Start opens the pause now (the press FightSimulation._pause_check reads), or −1
## when none can: outside a fight or its round state FIGHT, in the demonstration and a practice
## replay (no human), or with a pause already open.
func pause_pad() -> int:
	if state != State.FIGHT or fight.pause_allowed == 0 or fight.round_state != RoundState.FIGHT \
			or fight.pause_request != 0 or fight.paused_player != 0:
		return -1
	if region.mode == GameMode.PRACTICE and fight.replay_playing != 0:
		return -1
	return fight_pad()


## The pad a tap or click presses Start on, or −1 for none: player 1's, but in a fight the human's
## (Start of a pad nobody plays there joins as a challenger), and not while a pause is open (the
## click that brings the window back would resume the fight).
func tap_pad() -> int:
	if state != State.FIGHT:
		return 0
	if fight.paused_player != 0 or fight.pause_request != 0:
		return -1
	return maxi(fight_pad(), 0)


func menu_exit() -> bool:
	var p0 := pressed(0)
	var p1 := pressed(1)
	if region.mode == GameMode.DEMO:
		if (p0 | p1) & PadState.START == 0:
			return false
	elif not ((held(0) & PauseMenu.SOFT_RESET_MASK) == PauseMenu.SOFT_RESET and p0 & PadState.SELECT) \
			and not ((held(1) & PauseMenu.SOFT_RESET_MASK) == PauseMenu.SOFT_RESET and p1 & PadState.SELECT) \
			and fight.pause_page != PauseMenu.PAGE_RESET:
		return false
	fight.pause_page = 0
	controllers_reset()
	sound(SOUND_START)
	goto_transition(State.MENU)
	return true


func next_attract_step() -> void:
	progress.attract_step = 0 if progress.attract_step + 1 > 3 else progress.attract_step + 1


## FUN_8004FB9C: the next attract step, skipping the title at step 3.
func attract_advance() -> void:
	next_attract_step()
	if progress.attract_step == 3:
		next_attract_step()


func _to_menu() -> void:
	sound(SOUND_START)
	goto_transition(State.MENU)


# ---- boot (game state 0, BootState 0x800B0BD0) -------------------------------------------------

func _boot() -> void:
	if sub == 0:
		sub = 1
	else:
		region.loaded_mode_overlay = 0xFF
		goto_transition(State.TITLE)


# ---- transition screen (TransitionScreen 0x8004FD48, menu_sim.transition_screen) ------------

func _transition() -> void:
	if progress.card_read != 0 and sub > 5 and sub < 11 and pressed_any() & PadState.START:
		goto_transition(State.MENU)
		sound(SOUND_START)
		return
	var mode := 3
	var level := 0
	match sub:
		0:
			display(0)
			fight.attract = 1
			var previous := progress.previous_state
			if ((previous - 2) & 0xFFFFFFFF) >= 4 or progress.screen_cached >= 4:
				progress.screen_cached = 0
			if progress.enbu_target != progress.enbu_cached:
				progress.screen_cached = 0
				progress.enbu_cached = progress.enbu_target
			sub = 5
			var t := progress.transition_target
			if t != State.ENBU and (t != State.TITLE or progress.attract_step == 3):
				sub = 1
		1, 2, 3, 4:
			if sub == 1:
				_queue_menu_overlay()
			if sub <= 2:
				auto_save()
			_overlay_loaded()
			_overlay_ready()
			sub = 12
		5, 6:
			if sub == 5:
				_queue_menu_overlay()
				sim.state_timer = 0
				sub = 6
			level = sim.state_timer << 3
			sim.state_timer += 1
			mode = 0
			if sim.state_timer > PRESENTS_FADE_FRAMES:
				mode = 1
				sub = 7
				sim.state_timer = fight.vblank
		7, 8, 9:
			mode = 1
			if sub == 7:
				if progress.card_read == 0:
					# FUN_8004C658: the save is read at start-up.
					if card_loader.is_valid():
						var saved: PackedByteArray = card_loader.call()
						if not saved.is_empty():
							progress.load_save_data(saved)
					progress.card_read = 1
				else:
					auto_save()
				sub = 8
			if sub <= 8:
				_overlay_loaded()
				sub = 9
			_overlay_ready()
			if ((fight.vblank - sim.state_timer) & 0xFFFFFFFF) > PRESENTS_HOLD:
				sim.state_timer = PRESENTS_FADE_FRAMES
				sub = 10
		10:
			level = sim.state_timer << 3
			sim.state_timer -= 1
			mode = 0
			if sim.state_timer < 1:
				sim.state_timer = 0
				sub = 11
				mode = 2
		11, 12:
			if sub == 11:
				mode = 2
				sub = 12
			if auto_save_error():
				return
			sub = 0
			state = target_state(progress.transition_target)
	presents_mode = mode
	presents_level = level if mode == 0 else 0


func _queue_menu_overlay() -> void:
	if progress.screen_cached == 0:
		slots[SLOT_SCREEN] = OVERLAY_ENBU if progress.enbu_target != 0 else OVERLAY_TITLE
		disc_read()
		progress.screen_cached = 0


func _overlay_loaded() -> void:
	if progress.screen_cached == 0:
		progress.screen_cached = 2


func _overlay_ready() -> void:
	if progress.screen_cached < 3:
		if progress.enbu_target != 0:
			# enbu.ovl FUN_800D3CA8: the demonstration's music is prepared.
			sim.events.add(SimEvents.Kind.MUSIC_PREPARE, -1, MUSIC_ENBU)
		progress.screen_cached = 3


## AutoSave (FUN_8004C6A0): with AUTO SAVE on and a save pending, the owner writes the save file.
func auto_save() -> void:
	if progress.auto_save != 0 and globals.save_pending != 0:
		save_requested = true
		globals.save_error = 0
	globals.save_pending = 0


## AutoSaveErrorShow (FUN_8004C758): 120 frames of AUTO SAVE ERROR! after a failed save.
func auto_save_error() -> bool:
	if globals.save_error == 0:
		return false
	globals.save_error -= 1
	return true


## The owner reports a failed save: AUTO SAVE ERROR! shows for 120 frames.
func save_failed() -> void:
	globals.save_error = 0x78


# ---- title sequence (title.ovl FUN_800DB7D4, menu_sim.title_sequence) ----------------------

func _title() -> void:
	var fade := -1
	match sub:
		0:
			movie_result = 0
			if progress.attract_step == 3 or not movies_available:
				sub = 3
			else:
				movie = 1 if progress.attract_step == 2 else 0
				sub = 1
			title_kind = PICTURE_FADE
			sim.state_timer = 0
		1:
			title_kind = PICTURE_MOVIE
			movie_started = movie
			disc_read()
			fight.stage_cached = -1   # FUN_800E1614: FUN_8006C870(0x1F), as every movie player
			sub = 2
		2:
			if movie_result > 0:
				sub = 6
		3, 4, 5:
			if sub == 3:
				title_kind = PICTURE_BLACK
				sim.state_timer = 0
				sub = 4
			if sub != 5 and sim.state_timer + 10 < 0x100:
				fade = sim.state_timer + 0x10A
				sim.state_timer += 10
			else:
				if sub != 5:
					sim.state_timer = 0
					sub = 5
				fades.append(0x200)
				sim.state_timer += 1
				if sim.state_timer >= WHITE_HOLD:
					sub = 6
		6, 7:
			if sub == 6:
				title_kind = PICTURE_TITLE
				sim.state_timer = 0x100
				sub = 7
			if sim.state_timer <= 0:
				sim.state_timer = TITLE_FRAMES
				sub = 8
			else:
				fade = sim.state_timer + 0xFD
				sim.state_timer -= 3
		8:
			title_kind = PICTURE_TITLE_PROMPT
			sim.state_timer -= 1
			if sim.state_timer == 0:
				sim.state_timer = 0x100
				sub = 9
		9:
			if sim.state_timer <= 0:
				title_kind = PICTURE_FADE
				sub = 10
			else:
				sim.state_timer -= 8
				fade = sim.state_timer
		_:
			next_attract_step()
			title_kind = PICTURE_FADE
			ModeStart.start(self, 6, 0)
	if fade >= 0:
		fades.append(fade)
	if pressed_any() & PadState.START or movie_result == -1:
		next_attract_step()
		controllers_reset()
		_to_menu()
		return
	_draw_picture(title_kind)


# ---- attract demonstration (enbu.ovl FUN_800D3844) -----------------------------------------

func _enbu() -> void:
	if sub > 0 and pressed_any() & PadState.START:
		next_attract_step()
		controllers_reset()
		music_stop()
		_to_menu()
		return
	match sub:
		0:
			music_stop()
			sub = 1
			enbu_kind = PICTURE_FADE
			sim.state_timer = 0
		1:
			enbu_kind = PICTURE_BLACK
			_performance_count = 0
			fight.stage_cached = -1   # FUN_800D3844: FUN_8006C870(0x1F)
			_enbu_setup()
			performance = null
			if performance_factory.is_valid():
				performance = performance_factory.call(progress.demo_number) as EnbuPerformance
			if performance != null:
				performance.backdrop = fight.backdrop
				performance.round_state = fight.round_state
				performance.setup_view = sim.camera.view
			sub = 2
		2:
			enbu_kind = PICTURE_NONE
			var done := false
			if performance != null:
				var chooses := performance.reel.chooses
				var ready := true
				if performance.phase == EnbuPerformance.Phase.MUSIC_WAIT:
					ready = music_ready()
				if performance.phase == EnbuPerformance.Phase.SETUP:
					music(MUSIC_ENBU)
					# FUN_800D3D64's set-up: the attract stage; CameraReset and the camera
					# restart draw two random numbers before the reel's first choice.
					fight.stage = ENBU_STAGE
					fight.stage_cached = ENBU_STAGE   # the performance loads its stage itself
					fight.rng.next()
					fight.rng.next()
				done = performance.step(ready)
				_performance_calls()
				# Each camera choice of the reel draws a random number (CameraChoose).
				for i in performance.reel.chooses - chooses:
					fight.rng.next()
				performed = true
				if performance.fade_drawn >= 0:
					fades.append(performance.fade_drawn)
			else:
				_performance_count += 1
				done = _performance_count == performance_frames
			if done:
				sub = 3
		3:
			enbu_kind = PICTURE_NONE
			sub = 4
		4, 5:
			if sub == 4:
				enbu_kind = PICTURE_TITLE
				sim.state_timer = 0x100
				sub = 5
			if sim.state_timer < 1:
				sim.state_timer = TITLE_FRAMES
				sub = 6
			else:
				fades.append(sim.state_timer + 0xFD)
				sim.state_timer -= 3
		6:
			enbu_kind = PICTURE_TITLE_PROMPT
			sim.state_timer -= 1
			if sim.state_timer == 0:
				sim.state_timer = 0x100
				sub = 7
		7:
			if sim.state_timer < 1:
				enbu_kind = PICTURE_FADE
				sub = 8
			else:
				sim.state_timer -= 8
				fades.append(sim.state_timer)
		_:
			sim.state_timer = 0x100
			next_attract_step()
			enbu_kind = PICTURE_FADE
			performance = null
			music_stop()
			ModeStart.start(self, 6, 0)
	_draw_picture(enbu_kind)


## The engine calls of the performance's move events (PadVibrate and CameraShakeStart run as in
## the fight; the rest is the demonstration's own presentation).
func _performance_calls() -> void:
	for e in performance.events.items:
		match e.kind:
			SimEvents.Kind.FIGHTER_VIBRATE:
				Vibration.fighter(fight, e.fighter, e.a, sim.events)
			SimEvents.Kind.SHAKE_REQUEST:
				CameraShake.start(fight, e.a, sim.events)


## enbu.ovl FUN_800D3CCC: the performance's globals: a scripted scene (0x800AFF69), the attract
## flag, no freeze or pause, and fighters without a motion bank until the script sets them.
func _enbu_setup() -> void:
	fight.attract = 1
	fight.freeze = 0
	fight.pause_request = 0
	fight.paused_player = 0
	fight.pause_shown = 0
	for i in 2:
		fight.fighters[i].bank_type = -2
	region.put8(0x69, 1)


## FUN_800DAAD8 / FUN_800D2C30: kind 0 black, 1 and 7 nothing, 2–4 the title with the start
## prompt, the logo or the copyright, 5 the title, 6 the options backdrop, other kinds a black
## fade (level 0).
func _draw_picture(kind: int) -> void:
	picture = kind
	if kind not in PICTURES_DRAWN:
		fades.append(0)


# ---- fight preparation (FightPrepare 0x80050600, game state 7) ------------------------------

func _fight_prepare() -> void:
	match sub:
		0:
			display(1)
			sub = 1
		1:
			display(0)
			sub = 2
		2:
			if region.loaded_mode_overlay != region.mode_overlay:
				region.loaded_mode_overlay = region.mode_overlay
				queue_overlay(SLOT_MODE, region.mode_overlay)
				sim.mode_overlay_loaded()
				goto_loader(State.PREPARE, 2)
			sub = 3
		3:
			sim.prepare_mode()
			state = State.FIGHT
			sub = 0
