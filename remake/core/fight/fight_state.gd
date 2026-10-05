class_name FightState
extends RefCounted
## The whole state of a fight (remake-plan.md#simulation-core): both fighter records and the
## game globals the fight code keeps between frames. Names follow the documentation; the
## comment gives the global's address (Japan Rev.1) where it helps to follow the RE notes.

const FIGHTERS := 2
const RECORDS := 3                       ## fighter records: 0x800A96F0, 0x800AAF7C, 0x800AC808

var rules: RuleSet
var region := ModeRegion.new()                 ## the mode context and the fight's globals (0x800AFF00)
var progress := GameProgress.new()             ## the save block and records (0x800982D0)
var tables: FightTables
var fighters: Array[FighterState] = []   ## the three records; the third fights in Tekken Force only
var count := FIGHTERS                    ## the records that fight: 3 in Tekken Force (mode 8)
var slots: Array[Array] = [[], []]          ## per player: the merged move index (MoveRow per slot)

# ---- mode and match (the mode context 0x800AFF50)
var mode: int:                          ## g_gameMode 0x800AFF50
	get: return region.mode
	set(v): region.mode = v
var frame_counter: int:                 ## 0x800AFF14 (main loop frames)
	get: return region.frame_counter
	set(v): region.frame_counter = v
var vblank := 0                             ## 0x800AE6E0: video frames when the main-loop frame began (FUN_80029B78); the frame counter at a steady 60 fps
var round_time_option := 2                  ## 0x800AE3C0: timer = (option + 2) · 600
var rounds_option: int:                 ## 0x800AFF70: rounds to win − 1
	get: return region.rounds_option
	set(v): region.rounds_option = v
var chip_damage: int:                   ## 0x800AFF20 GUARD DAMAGE
	get: return region.chip_damage
	set(v): region.chip_damage = v
var pause_allowed: int:                 ## 0x800AFF54
	get: return region.pause_allowed
	set(v): region.pause_allowed = v
var collapse_on_ko: int:                ## 0x800AFF5B
	get: return region.collapse_on_ko
	set(v): region.collapse_on_ko = v
var carry_health: int:                  ## 0x800AFF59
	get: return region.carry_health
	set(v): region.carry_health = v
var human_mask := 3                         ## 0x800AE3D8
var hud_shown := 0                          ## 0x800AE6C8: the HUD's bars, timer and marks are drawn (from the first round start)
## Health bars (0x800980F4, 0x10 per player): the health last seen, then the target, drawn and
## recent-damage lengths in pixels (hud.md#elements).
var hud_bars: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0])]
var hud_wins_seen := PackedInt32Array([0, 0])  ## 0x80098114: round wins at the round start (the newest mark blinks)
var stage := 0                              ## g_stage 0x800AE14C
## The stage whose archive is in memory: the load cache's stage slot (0x800A0C48, FUN_8006C924(0x10));
## −1 once something overwrote it (FUN_8006C870: a mode start, a screen overlay, a movie).
var stage_cached := -1
var backdrop := BackdropTurn.new()          ## the panorama's turn (StageBackgroundDraw)
var music := 0                              ## 0x800AE1D0

# ---- round flow
var round_state := 0                        ## 0x80097350
var round_counter := 0                      ## 0x80097354
var round_frame := 0                        ## 0x80095884 frames of the round (input frames)
var round_frame_seen := 0                   ## 0x80095888 its value at the last move step
var rounds_played := 0                      ## 0x800958A8
var timer := 0                              ## 0x800AE094
var result_flags := 0                       ## 0x800AE340
var rounds_to_win := 0                      ## 0x800AE2C4
var max_rounds := 0                         ## 0x800AE404
var input_mode := PackedInt32Array([0, 0, 0])   ## 0x80095894: 0 none, 1 pad or CPU, 2 script
var freeze := 0                             ## 0x8009588C: the fight only draws
var undrawn_mask := 0                       ## fighters the Ogre scene does not draw this step (it draws the ones it stepped), a bit each
var paused_player := 0                      ## 0x800958B8
var no_damage := 0                          ## 0x800958A0
var ko_started := 0                         ## 0x800958BC
var replay_playing := 0                     ## 0x800958C8
var throw_count := 0                        ## 0x800958C4
var blend_enabled := 1                      ## 0x800958C0: FighterAnimate may blend transitions
var pause_request := 0                      ## 0x800958B0: 1/2 the player who asked for the pause
var pause_shown := 0                        ## 0x800958B4
var pause_close := 0                        ## 0x800958AC: the pause closes itself
var pause_cursor := 0                       ## 0x80098DDC: the menu's item (−1: just opened)
var pause_page := 0                         ## 0x80098DDD: the confirmed item + 1 (1 CANCEL, 3 RESET)
var pause_delay := 0                        ## 0x800A8B3A: frames before the menu takes input
var command_cursor := PackedInt32Array([0, 0])   ## 0x800A39C0: per player the move list's first move
var command_offset := PackedInt32Array([0, 0])   ## 0x800A39C4: per player the slide still to go (pixels)
var replay_skip := 0                        ## 0x800958A4: Start skipped the replay
var replay_request := 0                     ## 0x80097358: the round flow asks for the replay
var win_pose_done := PackedInt32Array([0, 0])   ## 0x8009E9A0 / 0x8009E9A4
var round_end_hold := 0                     ## 0x8009735C: frames the round result is shown
var round_end_done := 0                     ## 0x80097360
var match_result: int:                  ## 0x800AFF71: 0 undecided, 1/2 winner + 1, 3 draw
	get: return region.match_result
	set(v): region.match_result = v
var match_winner: int:                  ## 0x800AFF72
	get: return region.match_winner
	set(v): region.match_winner = v
var match_loser: int:                   ## 0x800AFF73
	get: return region.match_loser
	set(v): region.match_loser = v
var timer_stopped := 0                      ## 0x800958D4: infinite round time
var practice := 0                           ## 0x800958D8: practice mode's fight (no damage)
var practice_intro := 0                     ## 0x800958E0: practice waits for its first pause
var practice_paused := 0                    ## 0x800958DC: FUN_800B3084's paused flag
var counter_forced := PackedInt32Array([0, 0, 0])   ## 0x800958E4: practice's COUNTER ATTACKS per fighter
var signal_colour: Array[Color] = [Color8(0, 0, 0, 0), Color8(0, 0, 0, 0)]   ## 0x800AE430: the freeze signal's back light
var practice_swap := false                  ## practice S+0x86: the dummy on CONTROLLER reads the other pad
var practice_pads: Callable                 ## FUN_800B7AEC: practice records each fighter's pad word
var fight_clock: int:                 ## 0x800AFF7C: the fight's time in frames
	get: return region.fight_clock
	set(v): region.fight_clock = v
var true_ogre_mask: int:                ## 0x800AFF68
	get: return region.true_ogre_mask
	set(v): region.true_ogre_mask = v
var draw_wins: int:                     ## 0x800AFF58: a draw may decide the match
	get: return region.draw_wins
	set(v): region.draw_wins = v
var team_round: int:                    ## 0x800AFF5A
	get: return region.team_round
	set(v): region.team_round = v
var tie_choice := 0                         ## 0x800AE406: who wins a tie between two humans
var unlocked: int:                      ## 0x800982D0: the characters Mokujin may copy
	get: return progress.unlocked
	set(v): progress.unlocked = v
var throw_count_seen := 0                   ## 0x80097E84: the count the throw link last saw

# ---- camera
var camera_phase := 0                       ## g_cameraPhase 0x80095890
var shake_script := -1                      ## 0x80097EC4: the running camera shake script
var shake_pos := 0

# ---- fight globals of the move and combat code
var fighter_distance: int:              ## g_fighterDistance 0x800AFF04
	get: return region.fighter_distance
	set(v): region.fighter_distance = v
var pair_distance := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])   ## 0x8009EA08 per pair bit sum
var pair_dx := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var pair_dz := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var pair_dir := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var situation := PackedInt32Array([0, 0, 0])      ## 0x80095B88 throw situation per player
var step_accum_x := PackedInt32Array([0, 0, 0])   ## 0x8009E9A8
var step_accum_z := PackedInt32Array([0, 0, 0])   ## 0x8009E9B8
var tap_previous := PackedInt32Array([0, 0, 0])   ## 0x8009746C newest history entry at the last latch
var latch_register := 0                     ## the value LatchButtonTaps finds in $a2 (bug #52)
var script_previous := PackedInt32Array([0, 0, 0])   ## 0x80095A94 the scripted input's last word
var step_helper_side := PackedInt32Array([0, 0])  ## 0x80095AA0 STEP key direction per player
var step_helper_timer := PackedInt32Array([0, 0]) ## 0x80095AA4
var air_frames := PackedInt32Array([0, 0, 0])     ## 0x80095B94 LaunchTrajectory's flight frames
var bound_ramp := PackedInt32Array([0, 0, 0])              ## 0x80097E68 (never reset: the image's values)
var bound_ramp_step := PackedInt32Array([2000, 2000, 2000]) ## 0x80097E74
var throw_link := 0                         ## 0x80097E80
var prev_roots: Array[PackedInt32Array] = []   ## 0x8009EAA0: previous roots (u16) for BodySeparate
var blend_hold := 0                         ## 0x800A9234
var segment_anchor: Array[PackedInt32Array] = []   ## 0x800A0920 anchors of the last frame
var segment_end0: Array[PackedInt32Array] = []     ## 0x800A08D0 segment 0 end of the last frame
var segment_end1: Array[PackedInt32Array] = []     ## 0x800A08F4
var alt_points := PackedInt32Array([0, 0, 0])      ## 0x800A0950 alternative attack point block

# ---- animation globals
var blend_skip := 0                         ## 0x800972CC: the next FighterAnimate skips blending
var gon_mouth := PackedInt32Array([0, 0])   ## 0x8009C098 per player: Gon's mouth variant
var ogre_phase_x := 0
var ogre_phase_y := 0
var ogre_height := 0

# ---- the modes' own state
var ball: TekkenBall                        ## Tekken Ball (volley.ovl): the ball, its tuning and gauges
var force: TekkenForce                      ## Tekken Force (force.ovl): the level, its enemies, camera and score
var health_flash := PackedInt32Array([0, 0])   ## 0x8009E998: per player a lighting flash (a pick-up in Tekken Force)
var flash_level := PackedInt32Array([0, 0, 0])  ## per fighter record the health_flash count FUN_8003A3B8 lit it with last (0: none; FighterAnimation.LIT_BLACK: a burning body), read by the views
var save_request := false                   ## the fight asks for a save (FUN_8004C678; the game flow runs it)

# ---- replay and effects
var replay := ReplayState.new()
var effects := EffectPool.new()
var display_buffer := 0                     ## 0x800AE3C4: the drawing buffer (frame parity)

# ---- sounds
var voice_cooldown := PackedInt32Array([0, 0, 0])     ## 0x8009760C per player
var damage_voice_timer := PackedInt32Array([0, 0, 0]) ## 0x80097600
var sound_hold := PackedInt32Array([0, 0, 0])         ## 0x80097614: no jump or landing sound
var wooden_sounds := PackedInt32Array([0, 0])         ## 0x800958CC: Mokujin's wooden sounds

# ---- random numbers
var rng := CRand.new()                      ## libc rand() (0x800A3E80)
var camera_rng := 0                         ## 0x800A95F4: (x + 1) · 0x10DCD per main-loop frame
var frame_rng := 0                          ## 0x8009F650: 5x + 1 per main-loop frame
var ai_rng := 0                             ## 0x800AE168: 5x + 3 per AiReset
var ai_difficulty := 1                      ## 0x800AE6D0: the AI group (DIFFICULTY LEVEL, 0–2)
var ai_level := 0                           ## 0x800AE6D9: the CPU level (arcade stage 0–9)
var challenger_lock := 0                   ## 0x800AE6DA: no challenger may join (a human lost in arcade; Force)
var challenger: int:                    ## 0x800AFF63: a new challenger is entering (no announcements)
	get: return region.challenger
	set(v): region.challenger = v
var attract := 0                            ## 0x800AE39C: outside a started mode (the demonstration fight): CPUs at level 4, halved waits


func _init(fight_tables: FightTables, fight_rules: RuleSet) -> void:
	tables = fight_tables
	rules = fight_rules
	for i in RECORDS:
		var f := FighterState.new()
		# BootInit: the third record belongs to player 1's side (its move index and pad).
		f.index = i
		f.player_index = mini(i, 1)
		f.opp_index = 1 - mini(i, 1)
		f.cur_opp_index = f.opp_index
		fighters.append(f)
	for i in 3:
		prev_roots.append(PackedInt32Array([0, 0, 0, 0]))
		segment_anchor.append(PackedInt32Array([0, 0, 0]))
		segment_end0.append(PackedInt32Array([0, 0, 0]))
		segment_end1.append(PackedInt32Array([0, 0, 0]))


## The records that fight (two, three in Tekken Force).
func active() -> Array[FighterState]:
	return fighters.slice(0, count)


## MoveLookup (0x8002D3CC): the move row of a slot in the fighter's merged move index.
func move_for_slot(f: FighterState, slot: int) -> MoveRow:
	return slots[f.player_index][Fx.s16(slot) & 0xFFFF] as MoveRow if Fx.s16(slot) >= 0 else null


## FighterOpponentIndex (0x80045E50): the throw partner during a throw, else the last attacker
## when this move was interrupted by a hit, else the last fighter this move touched, else the
## default opponent.
func opponent_index(f: FighterState) -> int:
	if f.in_throw != 0:
		return f.throw_partner
	if f.was_hit_this_move != 0:
		return f.last_attacker
	if f.contact != 0:
		return f.last_hit_target
	return f.opp_index


## FighterOpponent (0x80045EB0).
func opponent(f: FighterState) -> FighterState:
	return fighters[opponent_index(f)]


## FUN_80078940: the move lists start at their first move.
func command_scroll_reset() -> void:
	command_cursor = PackedInt32Array([0, 0])
	command_offset = PackedInt32Array([0, 0])
