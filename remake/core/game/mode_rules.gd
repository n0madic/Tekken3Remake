class_name ModeRules
extends FlowPart
## The modes' hooks that FightMain calls (arcade.ovl and the resident code; modes.md#match-flow):
## the start hook (sub-state 1), the fight hook (sub-state 2) with StageAndMusicSelect, and the
## end hook when a match is decided; and the records the modes keep (FUN_80051674, the time
## attack record FUN_800B4B80, the survivors FUN_800B4C94).
##
## Tekken Ball's hooks are volley.ovl's, Tekken Force's force.ovl's.

const KEY_NONE := 0x58
const TEKKEN_BALL_STAGE := 0x13
const VS_STAGE_KEY := 0x44            ## mode context +0x44/+0x48/+0x4C: the VS stage memory
const LADDER := 0x90                  ## mode context: ten (character, costume, stage) entries
const OGRE_SCENE := 0xBC              ## mode context: the Ogre scene has played
const STAGE_RECORDS := 0x40           ## mode context: ten (u32 time, u8 character, u8 costume, u16 player)
const LAST_STAGE := 9
const TEAMS := 0x59                   ## mode context: two teams of 13 bytes
const TEAM_SIZE := 0xD
const TEAM_ROUND := 0x58
const TEAM_OUTCOMES := 0x38           ## mode context: u16 per team round, the outcome
const SURVIVAL_RANK := 0x40           ## mode context: the survivor rank the wins would reach
const BLANK_NAME := "   "             ## arcade.ovl 0x800B0C58: a new record's name before entry
const SURVIVOR_COUNT := 10
const RECORD_TIME := 1                ## the name entry's kinds (0x800984DE)
const RECORD_SURVIVOR := 2
const FORCE_FIRST_STAGE := 0xF
const FORCE_LAST_STAGE := 0x12
const FORCE_EXTRA_MUSIC := 0x19
const BALL_POOL := 0x53FFF            ## FUN_800B528C: the opponents Tekken Ball may pick
const BALL_MET := 0x44                ## mode context: u16 per character, the Tekken Ball met counts
const BALL_OPPONENT := 0x70           ## mode context: the chosen costume key
const BALL_FIRST_OPPONENT := 0x44     ## Gon, costume 0


func _team(side: int) -> int:
	return ModeRegion.CONTEXT + TEAMS + TEAM_SIZE * side


## The start hook (FightMain sub-state 1).
func mode_start() -> void:
	match g.region.mode:
		GameMode.ARCADE, GameMode.TIME_ATTACK:
			_arcade_start()
		GameMode.TEAM:
			_team_start()
		GameMode.BALL:
			# FUN_800B4C58: both players' move tuning cleared.
			g.sim.ball.drift_clear(0)
			g.sim.ball.drift_clear(1)
		GameMode.FORCE:
			_force_start()


## The fight hook (FightMain sub-state 2).
func fight_start() -> void:
	match g.region.mode:
		GameMode.ARCADE, GameMode.TIME_ATTACK:
			_arcade_fight()
		GameMode.TEAM:
			_team_fight()
		GameMode.SURVIVAL:
			_survival_fight()
		GameMode.BALL:
			_ball_fight()
		GameMode.FORCE:
			_force_fight()


## The end hook of a decided match.
func match_end() -> void:
	match g.region.mode:
		GameMode.ARCADE:
			_arcade_end()
		GameMode.VS:
			_vs_end()
		GameMode.TEAM:
			_team_end()
		GameMode.TIME_ATTACK:
			_time_attack_end()
		GameMode.SURVIVAL:
			_survival_end()
		GameMode.BALL:
			_ball_end()
		GameMode.FORCE:
			_force_end()
		_:
			g.sub = MatchFlow.Sub.SELECT


# ---- arcade and time attack ---------------------------------------------------------------

## FUN_800B0C5C: a new run builds the ladder for the human's character (not on a challenger's return).
func _arcade_start() -> void:
	var region := g.region
	if region.mode_started != 0:
		return
	var gl := g.globals
	var p := 1 if gl.player_active[0] == 0 else 0
	Opponents.build_ladder(g, gl.player_char[p] * 4 + gl.player_costume[p])
	region.ctx_put32(OGRE_SCENE, 0)


## FUN_800B0DC0: the CPU level of the ladder stage and, with one human, its opponent.
func _arcade_fight() -> void:
	var region := g.region
	var gl := g.globals
	var entry := LADDER + 4 * region.fight_index
	g.fight.ai_level = region.ctx8(entry + 2)
	if region.human_count != 1:
		return
	var cpu := region.cpu_index
	gl.player_char[cpu] = region.ctx8(entry)
	gl.player_costume[cpu] = region.ctx8(entry + 1)
	gl.player_cpu[cpu] = 1
	ModeStart.mirror_costumes(gl, cpu)
	region.ctx_put8(entry, gl.player_char[cpu])
	region.ctx_put8(entry + 1, gl.player_costume[cpu])


## FUN_800B134C: with one human a win moves up the ladder (the tenth: the ending), a loss offers
## the continue; with two humans the loser drops out.
func _arcade_end() -> void:
	var region := g.region
	var gl := g.globals
	match region.human_count:
		1:
			if region.match_winner != region.human_index:
				_lost()
				return
			_ladder_win()
			g.rules.gon_check(gl.player_char[region.cpu_index])
			if region.fight_index < 10:
				g.sub = MatchFlow.Sub.NEXT_FIGHT
				return
			var w := region.match_winner
			_run_over(w)
			g.rules.record_clear(gl.player_char[w], gl.player_costume[w])
			g.rules.count_play(gl.player_char[w])
			g.fight.hud_shown = 0
			gl.player_active[w] = 0
			g.goto_screen_loader(GameFlow.State.ENDING)
		2:
			region.match_count += 1
			g.rules.count_result(gl.player_char[region.match_winner], gl.player_char[region.match_loser])
			gl.player_active[region.match_loser] = 0
			gl.player_keep[region.match_loser] = 0
			gl.count_win(g.fight, region.match_winner)
			g.sub = MatchFlow.Sub.NEXT_FIGHT


## FUN_800B197C: time attack is arcade without the Gon check, ending on its result screen.
func _time_attack_end() -> void:
	var region := g.region
	var gl := g.globals
	if region.match_winner != region.human_index:
		_lost()
		return
	_ladder_win()
	if region.fight_index < 10:
		g.sub = MatchFlow.Sub.NEXT_FIGHT
		return
	var w := region.match_winner
	_run_over(w)
	_time_record()
	g.rules.count_play(gl.player_char[w])
	gl.player_active[w] = 0
	g.goto_screen_loader(GameFlow.State.TIME_RESULT)


## The won ladder fight: its time counts and is kept per stage, and the ladder moves on.
func _ladder_win() -> void:
	var region := g.region
	var gl := g.globals
	var w := region.match_winner
	region.clock_start = 0
	region.total_time += region.fight_clock
	_stage_record(region.fight_index, gl.player_char[w], gl.player_costume[w], w, region.fight_clock)
	region.fight_index += 1


## The run's winner and costume key (mode context +0x38, +0x3C).
func _run_over(w: int) -> void:
	var gl := g.globals
	g.region.ctx_put32(0x38, w)
	g.region.ctx_put32(0x3C, gl.player_char[w] * 4 + gl.player_costume[w])


## The human lost: the fight's time carries into the retry, and the continue starts.
func _lost() -> void:
	var region := g.region
	var gl := g.globals
	var loser := region.match_loser
	region.clock_start = region.fight_clock
	gl.player_active[loser] = 0
	gl.player_keep[loser] = 0
	g.rules.count_play(gl.player_char[loser])
	g.sub = MatchFlow.Sub.CONTINUE_START


## FUN_80051674: a ladder stage's record (time, character, costume, player).
func _stage_record(stage: int, character: int, costume: int, player: int, frames: int) -> void:
	var at := STAGE_RECORDS + 8 * stage
	g.region.ctx_put32(at, frames)
	g.region.ctx_put8(at + 4, character)
	g.region.ctx_put8(at + 5, costume)
	g.region.ctx_put16(at + 6, player)


## FUN_800B4B80: a run with one character and player on every stage beating the character's best
## time sets the record (named blank until the name entry).
func _time_record() -> bool:
	var region := g.region
	var progress := g.progress
	progress.ranking_page = 0
	var last := STAGE_RECORDS + 8 * LAST_STAGE
	var character := region.ctx8(last + 4)
	var player := region.ctx_s16(last + 6)
	var total := 0
	for i in 10:
		var at := STAGE_RECORDS + 8 * i
		if region.ctx_s16(at + 6) != player or region.ctx8(at + 4) != character:
			return false
		total = (total + region.ctx32(at)) & 0xFFFFFFFF
	if not total < progress.time_record(character):
		return false
	progress.name_entry |= RECORD_TIME
	var at := GameProgress.TIME_RECORDS + 8 * character
	progress.record_entry = GameProgress.BASE + at
	progress.entry_character = character
	progress.entry_player = player & 0xFF
	progress.set_time_record(character, total)
	progress.put_name(at + 4, BLANK_NAME)
	return true


# ---- VS ---------------------------------------------------------------------------------------

## FUN_800B15CC: VS: the win or the draw counted, then back to select.
func _vs_end() -> void:
	var region := g.region
	var result := region.match_result
	region.match_count += 1
	if result != 0:
		if result < 3:
			g.globals.count_win(g.fight, region.match_winner)
			var at := 0x38 + 4 * region.match_winner
			region.ctx_put16(at, region.ctx16(at) + 1)
			g.rules.count_result(g.globals.player_char[region.match_winner], g.globals.player_char[region.match_loser])
			g.rules.count_play(g.globals.player_char[region.match_winner])
		elif result == 3:
			g.globals.set_tie_winner(g.fight, g.fight.tie_choice)
			region.ctx_put16(0x40, region.ctx16(0x40) + 1)
			g.rules.count_draw(g.globals.player_char[0], g.globals.player_char[1])
	g.globals.player_keep[1] = 0
	g.globals.player_keep[0] = 0
	g.sub = MatchFlow.Sub.SELECT


# ---- Tekken Ball --------------------------------------------------------------------------------

## FUN_800B4C80: the CPU level from the difficulty and, with one human, the opponent
## (FUN_800B528C) on the CPU side.
func _ball_fight() -> void:
	var region := g.region
	var gl := g.globals
	g.fight.ai_level = (g.fight.ai_difficulty * 4 + 1) & 0xFF
	if region.human_count != 1:
		return
	var key := _ball_opponent()
	var cpu := region.cpu_index
	gl.player_char[cpu] = key >> 2
	gl.player_costume[cpu] = key & 3
	gl.player_cpu[cpu] = 1
	ModeStart.mirror_costumes(gl, cpu)


## FUN_800B528C: the first single-player game always meets Gon (costume key 0x44); later ones a
## random character among those met at most 4 times more than the least met (bug #30: the list
## is sorted the wrong way, so every unlocked candidate stays in). The met counts are the mode
## context's u16s at +0x44; Gon's first game counts nowhere (bug #31: a stray write).
func _ball_opponent() -> int:
	var region := g.region
	var pairs: Array[Vector2i] = []
	var mask := g.progress.unlocked & BALL_POOL
	for c in Opponents.CHARACTERS:
		if (mask >> c) & 1:
			pairs.append(Vector2i(c, region.ctx16(BALL_MET + 2 * c)))
	var fixed := g.fight.rules.fix_ball_opponent
	Opponents.sort_pairs(pairs, fixed)
	var count := 0
	while count < pairs.size() and not pairs[0].y + 4 < pairs[count].y:
		count += 1
	var key := BALL_FIRST_OPPONENT
	var met := Character.GON if fixed else -1
	if g.progress.ball_played == 0:
		g.progress.ball_played = 1
	else:
		met = pairs[Opponents.frame_random(g.fight) % count].x
		key = met * 4 + (g.fight.vblank & 1)
	region.ctx_put32(BALL_OPPONENT, key)
	if met >= 0:
		region.ctx_put16(BALL_MET + 2 * met, region.ctx16(BALL_MET + 2 * met) + 1)
	return key


## FUN_800B4D24: the plays counted (and Gon unlocked when the single player beat him), then back
## to select; with two players the loser leaves.
func _ball_end() -> void:
	var region := g.region
	var gl := g.globals
	match region.human_count:
		1:
			g.rules.count_play(gl.player_char[region.human_index])
			if region.match_winner == region.human_index:
				g.rules.gon_check(gl.player_char[region.cpu_index])
		2:
			g.rules.count_play(gl.player_char[0])
			g.rules.count_play(gl.player_char[1])
			gl.player_active[region.match_loser] = 0
	gl.player_keep[1] = 0
	gl.player_keep[0] = 0
	g.sub = MatchFlow.Sub.SELECT


# ---- Tekken Force -------------------------------------------------------------------------------

## FUN_800B60A4 (and FUN_800B58FC): the keys, score and hi-score (FUN_800B1508), the run's result
## words cleared (the boss records to "none"), the boss list when Doctor B. is unlocked, and the
## manual target switch off.
func _force_start() -> void:
	var region := g.region
	var force := g.fight.force
	force.mode_start()
	region.ctx_put32(TekkenForce.FINAL_SCORE, 0)
	region.ctx_put8(TekkenForce.NEW_RECORD, 0)
	region.ctx_put16(TekkenForce.DEFEATED, 0)
	region.ctx_put8(TekkenForce.RESULT_FLAGS, 0)
	if (g.progress.unlocked >> 19) & 1:
		region.ctx_put8(TekkenForce.RESULT_FLAGS, region.ctx8(TekkenForce.RESULT_FLAGS) | 0x10)
	for k in 4:
		region.ctx_put8(TekkenForce.BOSSES + k, KEY_NONE)
	force.manual_target_off()


## FUN_800B6110: the enemies' CPU level by level (0, 3, 4, 5, 5) and the CPU side's character 21.
func _force_fight() -> void:
	var region := g.region
	var gl := g.globals
	var lv := region.fight_index
	g.fight.ai_level = TekkenForce.FORCE_AI_LEVELS[lv] if lv < TekkenForce.FORCE_AI_LEVELS.size() else 0
	var cpu := region.cpu_index
	gl.player_char[cpu] = TekkenForce.ENEMY
	gl.player_costume[cpu] = 0
	gl.player_cpu[cpu] = 1
	g.fight.force.put32(TekkenForce.HUMAN, region.human_index)
	region.ctx_put8(0x3E, region.human_index)


## FUN_800B61D4: a lost level ends the run (the play counted, the hi-score saved, game over); a
## cleared one goes to the next level, and after the last (the fourth, or the Doctor B. level when
## the keys earned it) to the Tekken Force result (Doctor B. unlocked after his level).
func _force_end() -> void:
	var region := g.region
	var gl := g.globals
	var force := g.fight.force
	var p := force.player()
	if force.gu32(TekkenForce.LEVEL_ENDED) == 0 or region.match_winner != region.human_index:
		gl.player_active[1] = 0
		gl.player_active[0] = 0
		gl.player_keep[1] = 0
		gl.player_keep[0] = 0
		g.rules.count_play(p.char_id)
		_force_save_hiscore(force)
		g.sub = MatchFlow.Sub.GAME_OVER_START
		return
	region.fight_index += 1
	if region.fight_index < 4:
		g.sub = MatchFlow.Sub.NEXT_FIGHT
		return
	if region.fight_index == 4:
		if force.gu32(TekkenForce.FINAL_CHALLENGE) != 0:
			g.sub = MatchFlow.Sub.NEXT_FIGHT
			return
		g.rules.count_play(p.char_id)
		_force_leave(gl)
		g.fight.hud_shown = 0
	else:
		g.rules.count_play(p.char_id)
		_force_leave(gl)
		g.fight.hud_shown = 0
		if (g.progress.unlocked >> 19) & 1 == 0:
			g.rules.unlock_character(Character.DOCTOR_B)
	_force_save_hiscore(force)
	region.ctx_put32(TekkenForce.FINAL_SCORE, force.score())
	g.goto_screen_loader(GameFlow.State.FORCE_RESULT)


static func _force_leave(gl: GameGlobals) -> void:
	gl.player_active[1] = 0
	gl.player_active[0] = 0
	gl.player_keep[1] = 0
	gl.player_keep[0] = 0


## FUN_800B6414: the run's hi-score into the save (save pending).
func _force_save_hiscore(force: TekkenForce) -> void:
	g.progress.force_hi_score = force.gu32(TekkenForce.HISCORE)
	g.rules.request_save()


# ---- team battle ------------------------------------------------------------------------------

## FUN_800B0CD0: the rounds cleared, and each team completed (a CPU team takes the size of the
## other and the other costume).
func _team_start() -> void:
	var region := g.region
	region.fight_index = 0
	region.ctx_put32(0x28, 0)
	region.ctx_put8(TEAM_ROUND, 0)
	for i in 16:
		region.ctx_put16(TEAM_OUTCOMES + 2 * i, 0)
	for side in 2:
		var team := _team(side)
		var other := _team((side + 1) & 1)
		region.put8(team + 8, 0xFF)
		region.put8(team + 9, 0)
		if g.globals.player_active[side] == 0:
			region.put8(team + 10, 0)
			region.put8(team + 12, region.u8(other + 12))
			region.put8(team + 11, 1 if region.u8(other + 11) == 0 else 0)
		# Bug #60: the game passes the side's active flag where the CPU flag is meant.
		var active := g.globals.player_active[side]
		var cpu_side := (1 if active == 0 else 0) if g.fight.rules.fix_team_least_used else active
		Opponents.team_fill(g, cpu_side, team, other)


## FUN_800B0E78: a side whose member changed fields the next one; the CPU level from the options
## and the members left.
func _team_fight() -> void:
	var region := g.region
	var gl := g.globals
	for side in 2:
		var team := _team(side)
		var current := region.u8(team + 9)
		if current == region.u8(team + 8):
			continue
		region.put8(team + 8, current)
		fighter_reset(side)
		var key := region.u8(team + current)
		gl.player_char[side] = key >> 2
		gl.player_costume[side] = key & 3
		gl.player_cpu[side] = 1 if gl.player_active[side] == 0 else 0
		ModeStart.mirror_costumes(gl, side)
		region.put8(team + current, ((gl.player_char[side] << 2) | gl.player_costume[side]) & 0xFF)
	g.fight.ai_level = 0
	if region.human_count == 1:
		var team := _team(region.cpu_index)
		var current := region.u8(team + 9)
		var size := region.u8(team + 0xC)
		var level := g.fight.ai_difficulty + 3 + (g.fight.vblank & 3)
		if current + 2 == size:
			level += 1
		elif current + 1 == size:
			level += 3
		g.fight.ai_level = mini(level & 0xFF, 9)


## FUN_800B16F0: the round's outcome counts; a side with no members left ends the match on the
## team result screen.
func _team_end() -> void:
	var region := g.region
	var gl := g.globals
	var result := region.match_result
	var round_at := TEAM_OUTCOMES + 2 * region.ctx8(TEAM_ROUND)
	region.ctx_put16(round_at, result)
	var played := -1
	if result != 0 and result < 3:
		gl.count_win(g.fight, region.match_winner)
		var loser_team := _team(region.match_loser)
		region.put8(loser_team + 9, region.u8(loser_team + 9) + 1)
		if region.human_count == 2:
			g.rules.count_result(gl.player_char[region.match_winner], gl.player_char[region.match_loser])
		elif region.human_count == 1 and region.match_loser == region.human_index:
			played = region.human_index
	elif result == 3:
		region.put8(_team(1) + 9, region.u8(_team(1) + 9) + 1)
		region.put8(_team(0) + 9, region.u8(_team(0) + 9) + 1)
		if region.human_count == 2:
			g.rules.count_draw(gl.player_char[0], gl.player_char[1])
		elif region.human_count == 1:
			played = region.human_index
	if played >= 0:
		g.rules.count_play(gl.player_char[played])
	region.ctx_put8(TEAM_ROUND, region.ctx8(TEAM_ROUND) + 1)
	var t0 := _team(0)
	var t1 := _team(1)
	if region.u8(t0 + 9) < region.u8(t0 + 12) and region.u8(t1 + 9) < region.u8(t1 + 12):
		g.sub = MatchFlow.Sub.NEXT_FIGHT
		return
	for side in 2:
		var team := _team(side)
		if region.u8(team + 9) < region.u8(team + 12) and (region.human_mask >> side) & 1 \
				and region.match_result != 3:
			g.rules.count_play(gl.player_char[side])
		gl.player_active[side] = 0
		gl.player_keep[side] = 0
	g.goto_screen_loader(GameFlow.State.TEAM_RESULT)


## FUN_80051A98: a fighter's health and carried health cleared (a new member or opponent).
func fighter_reset(fighter: int) -> void:
	var f := g.fight.fighters[fighter]
	f.health = 0
	f.carried_health = 0


# ---- survival ---------------------------------------------------------------------------------

## FUN_800B104C: the next opponent and the CPU level from the wins.
func _survival_fight() -> void:
	var region := g.region
	var gl := g.globals
	var fight := g.fight
	var wins := region.ctx_s32(Opponents.SURVIVAL_WINS)
	region.ctx_put32(SURVIVAL_RANK, _survivor_rank(wins))
	Opponents.survival_pick(g)
	var cpu := region.cpu_index
	var key := region.ctx32(Opponents.SURVIVAL_NEXT)
	gl.player_char[cpu] = (key >> 2) & 0xFFFF
	gl.player_costume[cpu] = key & 3
	gl.player_cpu[cpu] = 1
	ModeStart.mirror_costumes(gl, cpu)
	fighter_reset(cpu)
	fight.ai_difficulty = 1
	var level := 0
	var hard := false
	if wins < 5:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 3 + 1
	elif wins < 10:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 3 + 2
	elif wins < 0x14:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 5 + 3
	elif wins < 0x32:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 5 + 3
		hard = fight.vblank & 0x10 != 0
	elif wins % 10 == 0:
		level = 0
	elif wins % 5 != 3:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 7 + 3
		hard = fight.vblank & 0x14 != 0
	else:
		level = (Opponents.frame_random(fight) & 0xFFFF) % 4 + 6
		hard = true
	if hard:
		fight.ai_difficulty = 2
	fight.ai_level = mini(level & 0xFF, 9)
	fight.ai_difficulty = mini(fight.ai_difficulty, 2)


## FUN_800B4B44: the survivor rank (1–10) the wins would take, 0 for none.
func _survivor_rank(wins: int) -> int:
	for i in SURVIVOR_COUNT:
		if g.progress.survivor(i).y < wins:
			return i + 1
	return 0


## FUN_800B1B10: a win counts per defeated character; the loss ends the run on the survival
## result screen with its record.
func _survival_end() -> void:
	var region := g.region
	var gl := g.globals
	var human := region.human_index
	var character := gl.player_char[region.match_loser]
	if region.match_winner == human:
		gl.count_win(g.fight, human)
		region.fight_index += 1
		var met := Opponents.SURVIVAL_MET + 2 * character
		region.ctx_put16(met, region.ctx16(met) + 1)
		var total := 0
		for c in Opponents.CHARACTERS:
			total += region.ctx16(Opponents.SURVIVAL_MET + 2 * c)
		region.ctx_put32(Opponents.SURVIVAL_WINS, total)
		g.sub = MatchFlow.Sub.NEXT_FIGHT
		return
	region.ctx_put32(0x38, human)
	region.ctx_put32(0x3C, (character << 2) | gl.player_costume[human])
	_survivor_record(human, character, gl.win_streak)
	gl.player_active[human] = 0
	gl.player_keep[human] = 0
	g.rules.count_play(character)
	g.goto_screen_loader(GameFlow.State.SURVIVAL_RESULT)


## FUN_800B4C94: a run of `wins` enters the survivors (sorted by wins, a new entry after equal
## ones) with a blank name.
func _survivor_record(player: int, character: int, wins: int) -> bool:
	var progress := g.progress
	progress.ranking_page = 1
	if _survivor_rank(wins) == 0:
		return false
	progress.entry_character = character & 0xFF
	progress.entry_player = player & 0xFF
	var entries: Array[PackedByteArray] = []
	var pairs: Array[Vector2i] = []
	for i in SURVIVOR_COUNT:
		var at := GameProgress.SURVIVORS + 8 * i
		entries.append(progress.bytes.slice(at, at + 8))
		pairs.append(Vector2i(i, progress.u16(at + 2)))
	var fresh := ByteBlock.new(8)
	fresh.put16(0, character)
	fresh.put16(2, wins)
	var name := BLANK_NAME.to_ascii_buffer()
	for k in name.size():
		fresh.put8(4 + k, name[k])
	entries.append(fresh.bytes)
	pairs.append(Vector2i(SURVIVOR_COUNT, wins))
	Opponents.sort_pairs(pairs, false)
	for i in SURVIVOR_COUNT:
		var at := GameProgress.SURVIVORS + 8 * i
		var e := entries[pairs[i].x]
		progress.put16(at, e.decode_u16(0))
		progress.put16(at + 2, e.decode_u16(2))
		var n := 0
		while n < 4 and e[4 + n] != 0:
			n += 1
		progress.put_name(at + 4, e.slice(4, 4 + n).get_string_from_ascii())
		if pairs[i].x == SURVIVOR_COUNT:
			progress.survivor_entry = GameProgress.BASE + at
	progress.name_entry |= RECORD_SURVIVOR
	return true


## StageAndMusicSelect (0x8004F698): the stage and music of the fight from a character record:
## the human's (or the side that won ties) in most modes, VS keeps its stage until both players
## change characters, Tekken Ball plays on stage 19, Tekken Force by its level.
func stage_and_music() -> void:
	var region := g.region
	var gl := g.globals
	var t := g.fight.tables
	var key := 0
	var stage := 0
	match region.mode:
		GameMode.VS:
			var c0 := gl.player_char[0]
			var k0 := 0
			if c0 > 0x15 or gl.player_costume[0] > 3:
				k0 = (0x16 << 2) & 0xFF
			else:
				k0 = ((c0 << 2) | gl.player_costume[0]) & 0xFF
			var k1 := KEY_NONE
			if not (gl.player_char[1] > 0x15 or gl.player_costume[1] > 3):
				k1 = ((gl.player_char[1] << 2) | gl.player_costume[1]) & 0xFF
			var keys := PackedInt32Array([k0, k1])
			key = keys[gl.other_player]
			var kept := region.ctx32(VS_STAGE_KEY)
			if kept != 0xFFFFFFFF and k0 != region.ctx32(VS_STAGE_KEY + 4) and k1 != region.ctx32(VS_STAGE_KEY + 8):
				key = kept
			region.ctx_put32(VS_STAGE_KEY, key)
			region.ctx_put32(VS_STAGE_KEY + 4, k0)
			region.ctx_put32(VS_STAGE_KEY + 8, k1)
			if key > 0x5C:
				key = KEY_NONE
			stage = JsonFile.number(t.character(key)["stage"])
		GameMode.TEAM, GameMode.PRACTICE:
			key = _key(gl.other_player)
			stage = JsonFile.number(t.character(key)["stage"])
		GameMode.BALL:
			key = _key(_player_of_humans())
			stage = TEKKEN_BALL_STAGE
		GameMode.FORCE:
			# The level's stage (15 + level); the Doctor B. level plays on stage 15 with track 0x19.
			key = _key(g.fight.force.human())
			stage = FORCE_FIRST_STAGE + region.fight_index
			if stage > FORCE_LAST_STAGE:
				g.fight.music = FORCE_EXTRA_MUSIC
				g.fight.stage = FORCE_FIRST_STAGE
				region.put8(0x6A, FORCE_FIRST_STAGE)
				region.put8(0x6B, FORCE_EXTRA_MUSIC)
				return
		_:
			key = _key(_player_of_humans())
			stage = JsonFile.number(t.character(key)["stage"])
	g.fight.music = JsonFile.number(t.character(key)["music"])
	g.fight.stage = stage
	region.put8(0x6A, stage)
	region.put8(0x6B, g.fight.music)


## The player whose character decides: the CPU's side with one human, else the tie loser.
func _player_of_humans() -> int:
	match g.region.human_count:
		0:
			return 0
		1:
			return g.region.cpu_index
		2:
			return g.globals.other_player
	return 0


func _key(player: int) -> int:
	var key := (g.globals.player_char[player] << 2) | g.globals.player_costume[player]
	return KEY_NONE if key > 0x5C else key
