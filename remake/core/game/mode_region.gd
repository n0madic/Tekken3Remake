class_name ModeRegion
extends ByteBlock
## The fight's globals and the mode context at 0x800AFF00 (modes.md#match-flow): the frame
## counter, the rule bytes the mode start sets, the match result, and the mode context
## (0x800AFF50) the mode overlays use with a layout of their own per mode (the arcade ladder,
## team records, survival counters). `ctx_*` accessors take offsets from the mode context.

const BASE := 0x800AFF00
const SIZE := 0x110
const CONTEXT := 0x50                  ## 0x800AFF50
const AI_SELF := 0x24                  ## 0x800AFF24: the fighter the AI drives this frame (its address)

var fighter_distance: int:             ## 0x800AFF04 g_fighterDistance
	get: return u32(0x04)
	set(v): put32(0x04, v)
var frame_counter: int:                ## 0x800AFF14 main-loop frames
	get: return u32(0x14)
	set(v): put32(0x14, v)
var chip_damage: int:                  ## 0x800AFF20 GUARD DAMAGE
	get: return u16(0x20)
	set(v): put16(0x20, v)
var mode: int:                         ## 0x800AFF50 g_gameMode
	get: return u32(0x50)
	set(v): put32(0x50, v)
var pause_allowed: int:                ## 0x800AFF54
	get: return u8(0x54)
	set(v): put8(0x54, v)
var challengers: int:                  ## 0x800AFF55: a player may join (new challenger)
	get: return u8(0x55)
	set(v): put8(0x55, v)
var team_members: int:                 ## 0x800AFF56
	get: return u8(0x56)
	set(v): put8(0x56, v)
var team_hud: int:                     ## 0x800AFF57: the team members' HUD
	get: return u8(0x57)
	set(v): put8(0x57, v)
var draw_wins: int:                    ## 0x800AFF58: a draw may decide the match
	get: return u8(0x58)
	set(v): put8(0x58, v)
var carry_health: int:                 ## 0x800AFF59
	get: return u8(0x59)
	set(v): put8(0x59, v)
var team_round: int:                   ## 0x800AFF5A
	get: return u8(0x5A)
	set(v): put8(0x5A, v)
var collapse_on_ko: int:               ## 0x800AFF5B
	get: return u8(0x5B)
	set(v): put8(0x5B, v)
var quick_select_mode: int:            ## 0x800AFF5C: the mode uses quick select
	get: return u8(0x5C)
	set(v): put8(0x5C, v)
var character_change: int:             ## 0x800AFF5D: CHARACTER CHANGE AT CONTINUE
	get: return u8(0x5D)
	set(v): put8(0x5D, v)
var quick_select_option: int:          ## 0x800AFF5E: QUICK SELECT
	get: return u8(0x5E)
	set(v): put8(0x5E, v)
var challenger_quick: int:             ## 0x800AFF5F: a challenger held L1 + R1
	get: return u8(0x5F)
	set(v): put8(0x5F, v)
var mode_started: int:                 ## 0x800AFF61
	get: return u8(0x61)
	set(v): put8(0x61, v)
var continuing: int:                   ## 0x800AFF62
	get: return u8(0x62)
	set(v): put8(0x62, v)
var challenger: int:                   ## 0x800AFF63: a new challenger is entering
	get: return u8(0x63)
	set(v): put8(0x63, v)
var vs_next_state: int:                ## 0x800AFF64: the game state after the VS screen
	get: return u8(0x64)
	set(v): put8(0x64, v)
var vs_next_sub: int:                  ## 0x800AFF65
	get: return u8(0x65)
	set(v): put8(0x65, v)
var mode_overlay: int:                 ## 0x800AFF66: the mode overlay the mode needs
	get: return u8(0x66)
	set(v): put8(0x66, v)
var loaded_mode_overlay: int:          ## 0x800AFF67
	get: return u8(0x67)
	set(v): put8(0x67, v)
var true_ogre_mask: int:               ## 0x800AFF68
	get: return u8(0x68)
	set(v): put8(0x68, v)
var human_count: int:                  ## 0x800AFF6C
	get: return u8(0x6C)
	set(v): put8(0x6C, v)
var human_mask: int:                   ## 0x800AFF6D
	get: return u8(0x6D)
	set(v): put8(0x6D, v)
var human_index: int:                  ## 0x800AFF6E
	get: return u8(0x6E)
	set(v): put8(0x6E, v)
var cpu_index: int:                    ## 0x800AFF6F
	get: return u8(0x6F)
	set(v): put8(0x6F, v)
var rounds_option: int:                ## 0x800AFF70: rounds to win − 1
	get: return u8(0x70)
	set(v): put8(0x70, v)
var match_result: int:                 ## 0x800AFF71: 0 undecided, 1/2 winner + 1, 3 draw
	get: return u8(0x71)
	set(v): put8(0x71, v)
var match_winner: int:                 ## 0x800AFF72
	get: return u8(0x72)
	set(v): put8(0x72, v)
var match_loser: int:                  ## 0x800AFF73
	get: return u8(0x73)
	set(v): put8(0x73, v)
var fight_index: int:                  ## 0x800AFF74: the ladder fight (arcade, time attack)
	get: return u32(0x74)
	set(v): put32(0x74, v)
var match_count: int:                  ## 0x800AFF78: VS and two-player arcade matches played
	get: return u32(0x78)
	set(v): put32(0x78, v)
var fight_clock: int:                  ## 0x800AFF7C: the fight's time in frames (RoundFlow counts it)
	get: return s32(0x7C)
	set(v): put32(0x7C, v)
var clock_start: int:                  ## 0x800AFF80: the next fight's clock (a lost fight's, on continue)
	get: return s32(0x80)
	set(v): put32(0x80, v)
var total_time: int:                   ## 0x800AFF84: arcade and time attack: the won fights' time
	get: return s32(0x84)
	set(v): put32(0x84, v)


func _init(size: int = SIZE) -> void:
	super(size)


func ctx8(at: int) -> int:
	return u8(CONTEXT + at)


func ctx16(at: int) -> int:
	return u16(CONTEXT + at)


func ctx_s16(at: int) -> int:
	return s16(CONTEXT + at)


func ctx32(at: int) -> int:
	return u32(CONTEXT + at)


func ctx_s32(at: int) -> int:
	return s32(CONTEXT + at)


func ctx_put8(at: int, v: int) -> void:
	put8(CONTEXT + at, v)


func ctx_put16(at: int, v: int) -> void:
	put16(CONTEXT + at, v)


func ctx_put32(at: int, v: int) -> void:
	put32(CONTEXT + at, v)
