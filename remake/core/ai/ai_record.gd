class_name AiRecord
extends RefCounted
## A CPU fighter's AI record (0x330 bytes at 0x8009F6C0 + 0x330 · slot; ai.md#entry-and-state).
## Field comments give the record offsets; the port keeps the game's widths where values wrap.

const PARAM_WORDS := 55
const HISTORY := 8

## The difficulty words (ai.md#difficulty-parameters) by index, where identified: mostly
## probabilities out of 4096 drawn against the 12-bit LCG, else frame counts.
enum Param {
	HOLD_BYTES = 0,       ## 0–1: four held-input lengths
	WAIT = 2,             ## wait after starting an attack, plus a random one of WAIT_EXTRA..+3
	WAIT_EXTRA = 3,
	THROW_STEPS = 7,      ## follow-up steps of a multi-part throw
	THROW_TRY = 8,
	THROW_ESCAPE = 9,
	THROW_CONTINUE = 10,
	THROW_LIST = 11,      ## the choice between the two throw lists; King's hook
	FILTER_POSTURE = 12,  ## the extra candidate filters while collecting attacks
	FILTER_FAST = 13,
	GUARD = 14,           ## guard or evade an attack that is coming (raised per hit up to the cap)
	GUARD_CAP = 15,
	PUNISH = 16,          ## punish and hold guard
	PUNISH_CAP = 17,      ## also the chance to answer a move that already hurt the CPU
	SIDE_STEP = 18,
	COUNTER = 19,         ## counter-attack an attack that is coming
	COUNTER_CAP = 20,
	DUCK = 21,            ## duck or step back from an attack that is coming
	DUCK_CAP = 22,
	ATTACKS_A = 25,       ## the larger of the two: attacks in a row before a pause
	ATTACKS_B = 27,
	HOOKS = 29,           ## consult the character hooks; the evasion pick and forced escapes
	VS_LAUNCHED = 30,     ## attack a launched opponent
	FOCUS = 35,           ## the general threshold of most secondary draws
	AIR_RETREAT = 36,     ## back away from an air attack at close range
	KEEP_RETREAT = 38,    ## keep movement choices 3 and 6
	BANK_COUNTER = 45,    ## bank-specific counter moves
	GRAB_GUARD = 47,      ## guard or evade a grab
	STANCE = 49,          ## a stance action
}

var slot := 0                    ## +0x00
var frame_count := 0             ## +0x02: grows whenever the pose frame changes (bit 0 picks the walk)
var pad := 0                     ## +0x04: held pad produced this frame
var prev_pad := 0                ## +0x06
var script_steps := PackedInt32Array()   ## +0x08: the pending input script
var script_at := -1              ## +0x08: its next step, −1 none
var target: FighterState         ## +0x10
var band := 0                    ## +0x14: distance band 0–5
var reach_band := 0              ## +0x18: the opponent's reach band 1–5
var distance := 0                ## +0x1C
var prev_distance := 0           ## +0x20
var distance_change := 0         ## +0x24
var move_changed := 0            ## +0x28
var far_count := 0               ## +0x2A
var move_frames := 0             ## +0x2C
var angle := 0                   ## +0x2E: the CPU's relAngle
var health_seen := 0             ## +0x30
var pose_frame_seen := 0         ## +0x34
var neutral_action := 0          ## +0x36
var approach := 0                ## +0x38
var approach_kind := 0           ## +0x3A: 2 a long approach
var crouching := 0               ## +0x3C
var guarding := 0                ## +0x3E
var approach_hold := 0           ## +0x40
var setup_cooldown := 0          ## +0x42
var neutral_cooldown := 0        ## +0x44
var air_cooldown := 0            ## +0x46
var direction_hold := 0          ## +0x48
var crouch_timer := 0            ## +0x4A
var crouch_attack_hold := 0      ## +0x4C
var move_frame_seen := 0         ## +0x4E
var attacking := 0               ## +0x50: the CPU's move has an active window
var special_open := 0            ## +0x52: an air or special move with its window open
var whiff_timer := 0             ## +0x54
var collected_move: MoveRow      ## +0x58: the move the candidates were collected from
var pressed_move: MoveRow        ## +0x5C
var last_attack: MoveRow         ## +0x60
var situation := 0               ## +0x64
var wait := 0                    ## +0x68: frames before the next attack (−1: attack now)
var guard_holds := 0             ## +0x6A
var guard_delay := 0             ## +0x6C
var cancel_wait := 0             ## +0x6E
var candidate_count := 0         ## +0x70
var marked_count := 0            ## +0x72
var hook_opponent := AiTables.Hook.NONE     ## +0x74: hook A of the opponent's bank
var hook_own := AiTables.Hook.NONE          ## +0x78: hook B of the CPU's own bank
var filter_no_lows := false      ## +0x7C: FUN_800616B4 installed for this frame
var announced_frames := 0        ## +0x80
var passed_frames := 0           ## +0x84
var vs_stance := 0               ## +0x88: the opponent is Yoshimitsu in slot 0x456
var move_block := 0              ## +0x8A
var guard_suspend := 0           ## +0x8C
var parried := 0                 ## +0x8E
var punish := 0                  ## +0x8F
var throw_next := 0              ## +0x90
var throw_chance := 0            ## +0x91
var evade_reason := 0            ## +0x92
var guard_memory := 0            ## +0x93
var evasion := 0                 ## +0x94
var throw_steps := 0             ## +0x96
var throw_list := 0              ## +0x98
var throw_press_frame := 0       ## +0x9C
var throw_move: MoveRow          ## +0xA0
var throw_row := PackedInt32Array()   ## +0xBC
var strings_on := 0              ## +0xC0
var strings_count := 0           ## +0xC2
var strings: Array[PackedInt32Array] = []    ## +0xC4
var no_strings := 0              ## +0xD4
var planned_on := 0              ## +0xD8
var planned_count := 0           ## +0xDA
var planned: Array[PackedInt32Array] = []    ## +0xDC
var links_on := 0                ## +0x1A0
var links_count := 0             ## +0x1A2
var links: Array[PackedInt32Array] = []      ## +0x1A4
var link_skip := 0               ## +0x1CC
var link_last := 0               ## +0x1D0
var attacks_in_row := 0          ## +0x1D2
var attack_limit := 0            ## +0x1D4
var history: Array[MoveRow] = [] ## +0x1DC: the opponent's moves that hurt the CPU
var history_at := 0              ## +0x1FC
var reload_timer := 0            ## +0x1FE
var opp_breath := 0              ## +0x200
var opp_gon_special := 0         ## +0x201
var adaptive := 0                ## +0x202
var opp_move_changed := 0        ## +0x204
var opp_down := 0                ## +0x208
var opp_until := 0               ## +0x20A: frames until the opponent's attack is active (999: none)
var opp_coming := 0              ## +0x20C
var opp_unblockable := 0         ## +0x20E
var opp_charging := 0            ## +0x210
var coming_seen := 0             ## +0x212
var opp_grabs := 0               ## +0x214
var opp_string := -1             ## +0x216
var opp_high := 0                ## +0x21A
var input_mode := 0              ## +0x21E: 0 no input, 1 hold up while crouching, else AI
var own_word := 0                ## +0x220: the CPU's move +0x08
var own_state := 0               ## +0x224: the CPU's move +0x04
var own_attack := 0              ## +0x228
var opp_word := 0                ## +0x22C
var opp_state := 0               ## +0x230
var opp_attack := 0              ## +0x234
var params := PackedInt32Array() ## +0x238: the difficulty words
var own_bands := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## +0x314
var opp_bands := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## +0x320
var force_words := 0              ## +0x32C: Tekken Force's pattern (index into AiTables.force_words)


func _init() -> void:
	params.resize(PARAM_WORDS)
	for i in HISTORY:
		history.append(null)


## Difficulty word `i` (record +0x238 + 2·i).
func word(i: int) -> int:
	return params[i]


## Byte `i` of the difficulty words (words 0–1 hold four bytes).
func param_byte(i: int) -> int:
	return ((params[i >> 1] & 0xFFFF) >> (8 * (i & 1))) & 0xFF


func script_pending() -> bool:
	return script_at >= 0
