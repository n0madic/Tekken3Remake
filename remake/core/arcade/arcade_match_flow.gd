class_name ArcadeMatchFlow
extends ArcadeFlowPart
## The game flow's state 4 (FUN_801B6BA4): the ladder, the VS screen, the fighters' load, the rounds,
## CONTINUE?, GAME OVER, a new challenger and the Ogre scene.

enum Sub {
	SELECT = 0, LADDER = 1, NEXT_FIGHT = 2, VS = 3, LOAD = 4, LOAD_WAIT = 5, ROUND = 6, FIGHT = 7,
	CONTINUE_START = 8, CONTINUE = 9, GAME_OVER_START = 10, GAME_OVER = 11,
	CHALLENGER_START = 12, CHALLENGER = 13, OGRE_START = 14, OGRE = 15, TRUE_OGRE = 16,
	VERSUS_END = 17, DEMO_END = 18, TO_TITLE = 19,
}

const LOAD_WAIT_FRAMES := 0x2A
const VS_SLIDE_FRAMES := 8
const CONTINUE_FRAMES := 0x328
const CONTINUE_DIGIT := 0x5A
const CONTINUE_BUTTONS := 0x360
const CONTINUE_LAST_DIGIT := 8
const CONTINUE_VOICE_BASE := 0x1004
const CONTINUE_VOICE_END := 0x1017
const CONTINUE_VOICE := 0x1016
const CONTINUE_WAIT := 0
const CONTINUE_SAME := 1
const CONTINUE_RESELECT := 2
const CONTINUE_GIVE_UP := -1
const GAME_OVER_FRAMES := 0x97
const GAME_OVER_MUSIC := 100
const CONTINUE_MUSIC := 99
const CHALLENGER_FIRST := 8
const CHALLENGER_END := 0x5B
const CHALLENGER_FREEZE := 0x17
const CHALLENGER_BLINK := 0x18
const CHALLENGER_SOUND := 0x110
const CHALLENGER_CHANNEL := 0x1E
const DEMO_ENDS_AT := 3                 ## the round state that ends the demonstration's fight
const ROUND_LEAVES_THE_MODE := 9
const LADDER_FIGHTS := 10
const LAST_FIGHT := 9
const OGRE := 14
const HEIHACHI := 13
const JIN := 9
const TRUE_OGRE_ID := 20
const FIRST_RANDOM := 3
const LAST_RANDOM := 8
const ORIGINALS := 0x3FF
const NOT_IN_LADDER := 0xFFEF9FFF       ## no Heihachi, Ogre, True Ogre
const DEMO_LEVELS := 0x200              ## FUN_801BE014: this bit of all the plays picks the costumes
const INTRUDER_WINDOW_LAST := 7
const JULIA := 10
const KUMA := 11
const BRYAN := 12
const MOKUJIN := 15
const GUN_JACK := 16
const GUN_JACK_TIME := 0x5DC
const RESULT_PERFECT := 8               ## FUN_8019E7A4: the last round's result
const NAME_ENTRY_WAIT := 0x708
const NAME_ENTRY_BUTTONS := 300
const NAME_DONE_WAIT := 0x3B

var rounds := 0                         ## 0x80374F36
var humans: int:                        ## 0x80374F32
	get: return flow.fight.region.human_count
	set(v): flow.fight.region.human_count = v
var joined: int:                        ## 0x80374F33
	get: return flow.fight.region.human_mask
	set(v): flow.fight.region.human_mask = v
var human_index: int:                   ## 0x80374F34
	get: return flow.fight.region.human_index
	set(v): flow.fight.region.human_index = v
var cpu_index: int:                     ## 0x80374F35
	get: return flow.fight.region.cpu_index
	set(v): flow.fight.region.cpu_index = v
var continues := 0                      ## 0x80374F24
var joins := 0                          ## 0x80374F26
var start_held := PackedInt32Array([0, 0])   ## 0x80374F28
var banner_shown := 0                   ## 0x80374F2E
var stage := 0                          ## 0x80374F30
var stage_music := 0                    ## 0x80374F31
var fight_number: int:                  ## 0x80374F3C
	get: return flow.fight.region.fight_index
	set(v): flow.fight.region.fight_index = v
var versus_count: int:                  ## 0x80374F40
	get: return flow.fight.region.match_count
	set(v): flow.fight.region.match_count = v
var total_time := 0                     ## 0x80374F4C
var previous_time := 0                  ## 0x80374F48
var banner_every_other := 0             ## 0x80374FD0
var ladder := PackedInt32Array()        ## 0x80374FA8: character, costume, level, (pad) per fight
var ladder_built := 0                   ## 0x8021FD34
var lead := 0                           ## 0x8021FCC0
var other := 0                          ## 0x8021FDFC
var win_streak := 0                     ## 0x8021FBE4
var level := 0                          ## 0x8021FD40, low byte
var vs_step := 0                        ## 0x80273244
var vs_kind := 0                        ## 0x80273248: 0 one human, 1 two or demo, 2 COMING SOON!, 3 WHO IS IT?
var vs_stage_number := 0                ## 0x80273250
var vs_slide := 0                       ## 0x8027324C
var vs_shown_character := PackedInt32Array([0, 0])   ## 0x8027325C
var vs_shown_key := PackedInt32Array([0, 0])         ## 0x80273260
var continue_digit := 0                 ## 0x8021F868
var continue_part := 0                  ## 0x8021F86C
var in_continue := 0                    ## 0x8021FCE4
var freeze_on_challenger := 0           ## 0x8021FB70
var stage_times := PackedInt32Array()   ## 0x80375134: u32 time, then the fight's id
var stage_records := PackedInt32Array() ## 0x80375138: character, costume, side
var demo_next := 0                      ## 0x8021F8C8
var name_entry := ArcadeNameEntry.new() ## 0x802732EC…
var ogre: ArcadeOgreScene


func _init(game: ArcadeGameFlow) -> void:
	super(game)
	ogre = ArcadeOgreScene.new(game)
	ladder.resize(LADDER_FIGHTS * 4)
	stage_times.resize(LADDER_FIGHTS + 1)
	stage_records.resize((LADDER_FIGHTS + 1) * 3)


## FUN_801BDA64's clearing of the context.
func reset_context() -> void:
	continues = 0
	joins = 0
	start_held.fill(0)
	(flow.fight.replay as ArcadeReplay).clear_kept()
	fight_number = 0
	versus_count = 0
	previous_time = 0
	total_time = 0
	flow.fight.fight_clock = 0
	in_continue = 0
	freeze_on_challenger = 0
	level = 0


## FUN_801B481C.
func reset_stage_times() -> void:
	stage_times.fill(0)
	stage_records.fill(0)


## FUN_801B7B04.
func lead_player(p: int) -> void:
	lead = p
	other = 1 - p
	win_streak = 0


## FUN_801B7B2C.
func _won(p: int) -> void:
	if p == lead:
		win_streak += 1
	else:
		lead = p
		other = 1 - p
		win_streak = 1


func step() -> void:
	var g := flow
	if g.mode == ArcadeGameFlow.MODE_DEMO and g.start_check():
		return
	match g.sub:
		Sub.SELECT:
			if g.mode != ArcadeGameFlow.MODE_DEMO:
				g.return_state = ArcadeGameFlow.State.MATCH
				g.return_sub = Sub.LADDER
				g.state = ArcadeGameFlow.State.SELECT
				g.sub = 0
				return
			g.sub = Sub.LADDER
			_ladder()
		Sub.LADDER:
			_ladder()
		Sub.NEXT_FIGHT:
			_next_fight()
		Sub.VS:
			_vs()
		Sub.LOAD:
			_load()
			g.sub = Sub.LOAD_WAIT
			_load_wait()
		Sub.LOAD_WAIT:
			_load_wait()
		Sub.ROUND:
			_round()
		Sub.FIGHT:
			_fight()
		Sub.CONTINUE_START:
			g.voice(CONTINUE_VOICE)
			g.music(CONTINUE_MUSIC)
			g.timer = CONTINUE_FRAMES
			continue_digit = 9
			continue_part = 0
			in_continue = 1
			g.sub = Sub.CONTINUE
			_continue()
		Sub.CONTINUE:
			_continue()
		Sub.GAME_OVER_START:
			_game_over_start()
			_game_over()
		Sub.GAME_OVER:
			_game_over()
		Sub.CHALLENGER_START:
			g.silence_players()
			g.sound(CHALLENGER_SOUND, CHALLENGER_CHANNEL)
			name_entry.finish(g)
			g.timer = CHALLENGER_FIRST
			freeze_on_challenger = 1
			g.sub = Sub.CHALLENGER
			_challenger()
		Sub.CHALLENGER:
			_challenger()
		Sub.OGRE_START:
			ogre.start()
			g.sub = Sub.OGRE
		Sub.OGRE:
			if ogre.step() or g.pressed(human_index) & ArcadeGameFlow.START != 0:
				g.sub = Sub.TRUE_OGRE
		Sub.TRUE_OGRE:
			_true_ogre()
		Sub.VERSUS_END:
			g.stop_sounds(1)
			g.active.fill(0)
			g.chosen.fill(0)
			g.plays.fill(0)
			g.loser_timer.fill(0)
			g.state = ArcadeGameFlow.State.RANKING
			g.sub = 0
		Sub.DEMO_END:
			g.stop_sounds(1)
			if g.attract_step == ArcadeGameFlow.ATTRACT_MOVIE or g.attract_step == ArcadeGameFlow.ATTRACT_ENBU:
				g.state = ArcadeGameFlow.State.RANKING
				g.sub = 0
			else:
				g.goto_transition(ArcadeGameFlow.State.ATTRACT)
		_:
			g.goto_transition(ArcadeGameFlow.State.TITLE)


# ==== the ladder ==================================================================================

## Sub-state 1, FUN_801B6664.
func _ladder() -> void:
	var g := flow
	if g.mode == ArcadeGameFlow.MODE_ARCADE and ladder_built == 0:
		var human := 0 if g.active[0] != 0 else 1
		_build_ladder(g.chars[human] * 4 + g.costumes[human])
		g.fight.region.ctx_put32(RoundFlow.OGRE_SCENE, 0)
	ladder_built = 1
	g.sub = Sub.NEXT_FIGHT
	_next_fight()


## FUN_801B557C.
func _build_ladder(key: int) -> void:
	var g := flow
	var character := key >> 2
	var boss := JIN if character == HEIHACHI else HEIHACHI
	var pool: int = g.progress.unlocked & NOT_IN_LADDER & ~(1 << character) & ~(1 << boss)
	var bag := _bag(pool & ORIGINALS)
	var at := 0
	while at < FIRST_RANDOM:
		var pick := _draw(bag)
		ladder[at * 4] = pick
		pool &= ~(1 << pick)
		at += 1
	bag = _bag(pool)
	while at < LAST_RANDOM:
		ladder[at * 4] = _draw(bag)
		at += 1
	ladder[at * 4] = boss
	ladder[(at + 1) * 4] = OGRE
	for i in LADDER_FIGHTS:
		var who := ladder[i * 4]
		ladder[i * 4 + 2] = i
		ladder[i * 4 + 1] = 0 if who == TRUE_OGRE_ID or who == OGRE else (1 if key & 3 != 0 else 0)


## FUN_801B54D8.
func _bag(mask: int) -> Array[int]:
	var out: Array[int] = []
	for i in ArcadeProgress.CHARACTERS:
		if mask >> i & 1:
			out.append(i)
	return out


## FUN_801B551C.
func _draw(bag: Array[int]) -> int:
	var at := Opponents.frame_random(flow.fight) % bag.size()
	var pick := bag[at]
	bag[at] = bag[bag.size() - 1]
	bag.pop_back()
	return pick


## FUN_801B5C50: after a win the next fight may be the COMING SOON! fighter's.
func _intruder(next: int) -> void:
	var g := flow
	var progress := g.progress
	if progress.intruder_done != 0 or next <= 0:
		return
	if next > INTRUDER_WINDOW_LAST:
		progress.intruder_done = 1
		return
	match progress.intruder:
		JULIA:
			if win_streak < 3:
				return
			_set_intruder(next, next + 2)
		KUMA:
			if next != 3:
				return
			_set_intruder(3, 5)
		BRYAN:
			if g.fight.result_flags & RESULT_PERFECT == 0:
				return
			_set_intruder(next, next + 2)
		MOKUJIN:
			if continues == 0:
				return
			_set_intruder(next, next + 2)
		GUN_JACK:
			if next != 2:
				return
			if _time_of_fights(2) < (g.settings.rounds_one + 1) * GUN_JACK_TIME:
				_set_intruder(2, 4)
	progress.intruder_done = 1


func _set_intruder(entry: int, entry_level: int) -> void:
	ladder[entry * 4] = flow.progress.intruder
	ladder[entry * 4 + 2] = entry_level


## FUN_801B4884: the time of the whole ladder.
func all_fights_time() -> int:
	return _time_of_fights(LADDER_FIGHTS)


## FUN_801B4924.
func _time_of_fights(count: int) -> int:
	var total := 0
	for i in mini(count, LADDER_FIGHTS):
		total += stage_times[i]
	return mini(total, ArcadeProgress.TIME_NONE)


# ==== the next fight ==============================================================================

## Sub-state 2.
func _next_fight() -> void:
	var g := flow
	joined = (1 if g.active[0] != 0 else 0) | (2 if g.active[1] != 0 else 0)
	humans = (1 if g.active[0] != 0 else 0) + (1 if g.active[1] != 0 else 0)
	match joined:
		1:
			human_index = 0
			cpu_index = 1
		2:
			human_index = 1
			cpu_index = 0
		_:
			human_index = 0
			cpu_index = 0
	var fight := g.fight
	fight.human_mask = joined
	fight.match_result = 0
	fight.match_winner = 0
	fight.match_loser = 0
	fight.fight_clock = previous_time
	if g.mode == ArcadeGameFlow.MODE_ARCADE:
		_set_opponent()
	g.timer = g.frame()
	_stage_and_music()
	vs_step = 0
	g.sub = Sub.VS
	_vs()


## FUN_801B66D8.
func _set_opponent() -> void:
	var g := flow
	var at := fight_number * 4
	level = ladder[at + 2]
	if humans == 1:
		g.chars[cpu_index] = ladder[at]
		g.costumes[cpu_index] = ladder[at + 1]
		g.cpu_control[cpu_index] = 1
		_clash(cpu_index)
		ladder[at] = g.chars[cpu_index]
		ladder[at + 1] = g.costumes[cpu_index]
	rounds = g.settings.rounds_one if humans < 2 else g.settings.rounds_versus


## FUN_801B4FAC, FUN_801B4F14: the two sides may not wear the same costume.
func _clash(p: int) -> void:
	var g := flow
	var o := 1 - p
	if g.chosen[o] != 0 and g.chars[p] == g.chars[o] and g.costumes[p] == g.costumes[o]:
		var costume := g.costumes[p]
		if g.active[o] == 0 and g.active[p] != 0:
			g.costumes[o] = costume ^ 1 if costume < 2 else 0
		else:
			g.costumes[p] = costume ^ 1 if costume < 2 else 0
	g.chosen[p] = 1


## FUN_801B5270 for the modes that exist: the stage and music of the human's fighter or, with no
## human, of the first; with one human of the CPU's.
func _stage_and_music() -> void:
	var g := flow
	var side := 0
	if humans == 1:
		side = cpu_index
	elif humans >= 2:
		side = other
	var key := g.chars[side] << 2 | g.costumes[side] & 3
	stage = g.data.stage_of(key)
	stage_music = g.data.music_of(key)
	g.sim.round_sounds.stage_music = stage_music


## FUN_801B8A44: the VS screen's steps; the pictures load on the third, then they slide in.
func _vs() -> void:
	var g := flow
	match vs_step:
		0:
			_vs_set_up()
			vs_step = 1
		1:
			vs_step = 2
		2:
			vs_slide = VS_SLIDE_FRAMES
			vs_step = 3
		3:
			vs_slide -= 1
			if vs_slide <= 0:
				vs_step = 4
		4:
			vs_step = 5
		5:
			g.sub = Sub.LOAD


func _vs_set_up() -> void:
	var g := flow
	var p := g.progress
	for i in 2:
		vs_shown_character[i] = g.chars[i]
		vs_shown_key[i] = g.chars[i] << 2 | g.costumes[i]
	vs_kind = 0 if humans == 1 else 1
	if g.mode != ArcadeGameFlow.MODE_DEMO:
		vs_stage_number = fight_number + 1
		return
	if p.who_is_it < ArcadeProgress.NONE:
		vs_kind = 3
		vs_shown_character[0] = p.who_is_it
		vs_shown_key[0] = p.who_is_it << 2
	if p.coming_soon < ArcadeProgress.NONE:
		vs_kind = 2
		vs_shown_character[0] = p.coming_soon
		vs_shown_key[0] = p.coming_soon << 2
	vs_stage_number = 1


## Sub-state 4, FUN_8018A44C.
func _load() -> void:
	var g := flow
	var m := ArcadeSimulation.Match.new()
	m.mode = g.mode
	m.chars = g.chars.duplicate()
	m.costumes = g.costumes.duplicate()
	m.cpu = g.cpu_control.duplicate()
	m.joined = joined
	m.start_locked = g.settings.event_mode
	m.stage = stage
	m.rounds = rounds
	m.round_time = g.settings.round_time
	m.neutral_guard = g.settings.neutral_guard
	m.one_player_table = g.settings.cabinet == 1
	m.cpu_group = g.settings.cabinet
	m.difficulty = g.settings.difficulty
	m.level = level
	m.attract = g.attract_silent
	m.life = g.settings.life_versus if humans == 2 else g.settings.life_one
	g.sim.start_match(m)


func _load_wait() -> void:
	var g := flow
	_note_starts()
	if g.frame() - g.timer >= LOAD_WAIT_FRAMES:
		g.sub = Sub.ROUND


## FUN_801B78E4 for both.
func _note_starts() -> void:
	for p in 2:
		if flow.pressed(p) & ArcadeGameFlow.START != 0:
			start_held[p] = 1


## Sub-state 6.
func _round() -> void:
	var g := flow
	g.round_started = 1
	g.sim.round_start()
	g.challenger_lock = 0
	freeze_on_challenger = 0
	if g.mode != ArcadeGameFlow.MODE_DEMO:
		_note_starts()
	g.sub = Sub.FIGHT


## Sub-state 7.
func _fight() -> void:
	var g := flow
	name_entry.step(g)
	if g.flags & ArcadeGameFlow.FLAG_CHALLENGERS != 0:
		var first := g.challenger(0)
		var second := g.challenger(1)
		if first != 0 or second != 0:
			g.sub = Sub.CHALLENGER_START
			return
	var result := g.sim.fight_frame()
	if g.mode == ArcadeGameFlow.MODE_DEMO:
		if result >= DEMO_ENDS_AT:
			g.sub = Sub.DEMO_END
			return
	if result < ArcadeRoundFlow.FINISHED:
		return
	if result == ArcadeRoundFlow.OGRE_SCENE_STATE:
		g.sub = Sub.OGRE_START
		return
	if result == ROUND_LEAVES_THE_MODE:
		g.sub = Sub.TO_TITLE
		return
	round_finished()


## The round is over: the next one or the match's end.
func round_finished() -> void:
	var g := flow
	(g.fight.replay as ArcadeReplay).store_round(g.fight)
	if g.fight.match_result == 0:
		g.sub = Sub.ROUND
		return
	name_entry.finish(g)
	_match_end()


## FUN_801B67E0.
func _match_end() -> void:
	var g := flow
	var fight := g.fight
	var winner := fight.match_winner
	var loser := fight.match_loser
	if humans == 1:
		if winner == human_index:
			previous_time = 0
			total_time += fight.fight_clock
			stage_times[fight_number] = fight.fight_clock
			var at := fight_number * 3
			stage_records[at] = g.chars[winner]
			stage_records[at + 1] = g.costumes[winner]
			stage_records[at + 2] = winner
			fight_number += 1
			if fight_number < LADDER_FIGHTS:
				_intruder(fight_number)
				g.sub = Sub.NEXT_FIGHT
			else:
				_ladder_won(winner)
		else:
			previous_time = fight.fight_clock
			g.active[loser] = 0
			g.chosen[loser] = 0
			g.progress.count_play(g.chars[loser] * 4)
			g.sub = Sub.CONTINUE_START
	elif humans == 2:
		versus_count += 1
		if g.settings.event_mode == 0:
			g.progress.count_play(g.chars[winner] * 4 + 1)
			g.progress.count_play(g.chars[loser] * 4 + 2)
			if lead != winner:
				name_entry.begin(g, loser, g.chars[loser], win_streak)
			_loser_leaves(loser)
			_won(winner)
			g.sub = Sub.NEXT_FIGHT
		else:
			g.sub = Sub.VERSUS_END


## FUN_801B6488.
func _loser_leaves(p: int) -> void:
	var g := flow
	g.active[p] = 0
	g.chosen[p] = 0
	g.loser_timer[p] = CONTINUE_FRAMES


## The last fight won: the records, then the ending.
func _ladder_won(winner: int) -> void:
	var g := flow
	var character := g.chars[winner]
	g.ranking.note_wins(winner, character, win_streak)
	g.ranking.note_time(self, winner)
	g.progress.count_play(character * 4)
	g.round_started = 0
	g.active[winner] = 0
	g.plays.fill(0)
	g.loser_timer.fill(0)
	g.state = ArcadeGameFlow.State.ENDING
	g.sub = 0
	g.ending.start(winner)


# ==== continue, game over, challenger ============================================================

## FUN_801B6230 and the state's handling of its answer.
func _continue() -> void:
	var g := flow
	g.sim.fight_frame()
	var loser := g.fight.match_loser
	var answer := _continue_answer(loser)
	if answer == CONTINUE_WAIT:
		return
	in_continue = 0
	if answer == CONTINUE_GIVE_UP:
		g.sub = Sub.GAME_OVER_START
		return
	g.sub = Sub.NEXT_FIGHT if answer == CONTINUE_SAME else Sub.SELECT
	name_entry.begin(g, loser, g.chars[loser], win_streak)
	name_entry.finish(g)
	lead_player(g.fight.match_winner)


func _continue_answer(p: int) -> int:
	var g := flow
	if g.pressed(p) & ArcadeGameFlow.START != 0:
		g.credit_sound()
		continues += 1
		g.active[p] = 1
		g.plays[p] += 1
		if g.settings.reselect == 0:
			g.chosen[p] = 1
			return CONTINUE_SAME
		g.chosen[p] = 0
		return CONTINUE_RESELECT
	if (g.pressed(0) | g.pressed(1)) & CONTINUE_BUTTONS != 0:
		g.timer = maxi(g.timer - CONTINUE_DIGIT, 0)
	if g.timer == 0:
		g.plays[p] = 0
		return CONTINUE_GIVE_UP
	if g.timer > 0:
		g.timer -= 1
	continue_digit = (g.timer + CONTINUE_DIGIT) / CONTINUE_DIGIT
	continue_part = g.timer + CONTINUE_DIGIT - continue_digit * CONTINUE_DIGIT
	if continue_digit <= CONTINUE_LAST_DIGIT and continue_part == CONTINUE_DIGIT - 1:
		g.voice(continue_digit + CONTINUE_VOICE_BASE)
	g.add_text(ArcadeGameFlow.TEXT_CONTINUE)
	return CONTINUE_WAIT


## Sub-state 10.
func _game_over_start() -> void:
	var g := flow
	var loser := g.fight.match_loser
	g.ranking.note_wins(loser, g.chars[loser], win_streak)
	g.timer = 0
	g.active[loser] = 0
	g.plays.fill(0)
	g.loser_timer.fill(0)
	g.stop_music()
	g.voice(CONTINUE_VOICE_END)
	g.music(GAME_OVER_MUSIC)
	g.sub = Sub.GAME_OVER


func _game_over() -> void:
	var g := flow
	g.add_text(ArcadeGameFlow.TEXT_GAME_OVER)
	g.sim.fight_frame()
	g.timer += 1
	if g.timer >= GAME_OVER_FRAMES:
		g.state = ArcadeGameFlow.State.RANKING
		g.sub = 0


## Sub-state 13.
func _challenger() -> void:
	var g := flow
	var result := g.sim.fight_frame()
	if result > 0 or g.timer > CHALLENGER_FREEZE:
		g.fight.freeze = 1
	if g.timer & CHALLENGER_BLINK != 0:
		g.add_text(ArcadeGameFlow.TEXT_CHALLENGER)
	g.timer += 1
	if g.timer >= CHALLENGER_END:
		if g.flags & ArcadeGameFlow.FLAG_RELOAD_ON_JOIN != 0:
			g.chosen.fill(0)
		g.sub = Sub.SELECT


## Sub-state 16: Ogre becomes True Ogre, the rounds won stay.
func _true_ogre() -> void:
	var g := flow
	ladder[LAST_FIGHT * 4] = TRUE_OGRE_ID
	g.fight.match_result = 0
	g.fight.match_winner = 0
	g.fight.match_loser = 0
	_set_opponent()
	_stage_and_music()
	vs_step = 0
	var wins := PackedInt32Array([g.fight.fighters[0].round_wins, g.fight.fighters[1].round_wins])
	var rounds_played := g.fight.rounds_played
	var sounds := g.sim.round_sounds
	var ogre_section := sounds.ogre_section
	var section := sounds.section
	_load()
	for i in 2:
		g.fight.fighters[i].round_wins = wins[i]
	g.fight.rounds_played = rounds_played
	sounds.ogre_section = ogre_section
	sounds.section = section
	g.sub = Sub.ROUND


# ==== the demonstration's fight ===================================================================

## FUN_801BE014.
func demo_fighters() -> void:
	var g := flow
	var plays_total := 0
	for i in ArcadeProgress.CHARACTERS:
		plays_total += g.ranking.usage_of(i)
	var list: Array[int] = []
	for character in g.data.demo_characters:
		if g.progress.unlocked >> character & 1:
			list.append(character)
	demo_next += 1
	if demo_next >= list.size():
		demo_next = 0
	var costume := 1 if plays_total & DEMO_LEVELS != 0 else 0
	g.cpu_control[0] = 1
	g.chars[0] = list[demo_next]
	g.costumes[0] = costume
	_clash(0)
	g.cpu_control[1] = 1
	g.chars[1] = list[((g.frame() & 0xFFF) % (list.size() - 1) + demo_next + 1) % list.size()]
	g.costumes[1] = costume
	_clash(1)


## FUN_801B75B4.
func demo_banner() -> void:
	var p := flow.progress
	banner_shown = 1 if banner_every_other == 0 else 0
	banner_every_other = (banner_every_other + 1) & 1
	if p.new_fighter >= ArcadeProgress.NONE:
		banner_shown = 0
