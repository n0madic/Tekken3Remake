class_name ArcadeAiRecord
extends RefCounted
## A CPU fighter's AI record in the arcade (0x364 bytes at 0x8029CF00 + 0x364 · slot). Field comments
## give the record offsets; the names are those of `AiRecord` where a PlayStation field matches.

const PARAM_WORDS := 60
const BAND_WORDS := 6
const HISTORY := 3

## The difficulty words by index (record +0x2D4 + 2 · word): mostly chances out of 4096, else frames.
enum Param {
	HOLD = 0,             ## 0–3: four held-input lengths
	WAIT = 4,             ## wait after starting an attack, plus a random one of WAIT_EXTRA..+3
	WAIT_EXTRA = 5,
	THROW_STEPS = 9,      ## follow-up steps of a multi-part throw
	THROW_TRY = 10,
	THROW_ESCAPE = 11,
	THROW_LIST = 13,      ## the choice between the two throw lists; King's hook
	FILTER_POSTURE = 14,  ## the extra candidate filters while collecting attacks
	FILTER_FAST = 15,
	GUARD = 16,           ## guard or evade an attack that is coming (raised per hit up to the cap)
	GUARD_CAP = 17,
	PUNISH = 18,          ## punish and hold guard
	PUNISH_CAP = 19,
	SIDE_STEP = 20,
	COUNTER = 21,         ## counter-attack an attack that is coming
	COUNTER_CAP = 22,
	DUCK = 23,            ## duck or step back from an attack that is coming
	DUCK_CAP = 24,
	STRINGS_MAX = 25,
	STRINGS_CHANCE = 26,
	ATTACKS_A = 27,       ## the larger of the two: attacks in a row before a pause; also the planned maximum
	PLANNED_KEEP = 28,
	ATTACKS_B = 29,       ## also the links' maximum
	LINKS_CHANCE = 30,
	HOOKS = 31,           ## consult the character hooks; the evasion pick and forced escapes
	VS_LAUNCHED = 32,     ## attack a launched opponent
	FOCUS = 37,           ## the general threshold of most secondary draws
	AIR_RETREAT = 38,     ## back away from an air attack at close range
	KEEP_RETREAT = 40,    ## keep movement choices 3 and 6
	BANK_COUNTER = 47,    ## bank-specific counter moves
	GRAB_GUARD = 49,      ## guard or evade a grab
	STANCE = 51,          ## a stance action
	STANCE_ESCAPE = 52,   ## leave a stance (flags 0x1E)
}

var slot := 0                    ## +0x00
var frame_count := 0             ## +0x04: grows whenever the pose frame changes (bit 0 picks the walk)
var pad := 0                     ## +0x06: held pad produced this frame
var prev_pad := 0                ## +0x08
var script_steps := PackedInt32Array()   ## +0x0C: the pending input script
var script_at := -1              ## +0x0C: its next step, −1 none
var move_changed := 0            ## +0x1C
var band := 0                    ## +0x20: distance band 0–5
var reach_band := 0              ## +0x24: the opponent's reach band 1–5
var wobble := 0                  ## +0x28
var wobble_phase := 0            ## +0x2C
var prev_distance := 0           ## +0x30
var distance_change := 0         ## +0x34
var far_count := 0               ## +0x38
var move_frames := 0             ## +0x3C
var health_seen := 0             ## +0x40
var pose_frame_seen := 0         ## +0x44
var neutral_action := 0          ## +0x48
var approach := 0                ## +0x4C
var approach_kind := 0           ## +0x50: 2 a long approach
var crouching := 0               ## +0x54
var guarding := 0                ## +0x58
var approach_hold := 0           ## +0x5C
var setup_cooldown := 0          ## +0x60
var neutral_cooldown := 0        ## +0x64
var air_cooldown := 0            ## +0x68
var direction_hold := 0          ## +0x6C
var crouch_timer := 0            ## +0x70
var crouch_attack_hold := 0      ## +0x74
var move_frame_seen := 0         ## +0x78
var attacking := 0               ## +0x7C: the CPU's move has an active window
var special_open := 0            ## +0x80: an air or special move with its window open
var whiff_timer := 0             ## +0x84
var collected_move: MoveRow      ## +0x88: the move the candidates were collected from
var pressed_move: MoveRow        ## +0x8C
var last_attack: MoveRow         ## +0x90
var continuation: MoveRow        ## +0x94: the move the collected list ends in
var wait := 0                    ## +0x98: frames before the next attack (−1: attack now)
var guard_holds := 0             ## +0x9C
var guard_delay := 0             ## +0xA0
var cancel_wait := 0             ## +0xA4: the wait before leaving the stand-up rows
var candidate_count := 0         ## +0xB0
var marked_count := 0            ## +0xB4
var hook_opponent := AiTables.Hook.NONE     ## +0xB8: hook A of the opponent's bank
var hook_own := AiTables.Hook.NONE          ## +0xBC: hook B of the CPU's own bank
var filter_no_lows := false      ## +0xC0: the predicate installed for this frame
var announced_frames := 0        ## +0xC4
var passed_frames := 0           ## +0xC8
var vs_stance := 0               ## +0xCC: the opponent is Yoshimitsu in slot 0x470
var move_block := 0              ## +0xD0
var guard_suspend := 0           ## +0xD4
var parried := 0                 ## +0xE4
var punish := 0                  ## +0xE8
var throw_next := 0              ## +0xEC
var throw_chance := 0            ## +0xF0
var evade_reason := 0            ## +0xF4
var guard_memory := 0            ## +0xF8
var evasion := 0                 ## +0xFC
var throw_steps := 0             ## +0x100
var throw_list := 0              ## +0x104
var throw_move: MoveRow          ## +0x10C
var throw_press_frame := 0       ## +0x128
var throw_row := -1              ## +0x12C: a branch row's index, −1 none
var strings_on := 0              ## +0x130
var strings := PackedInt32Array()   ## +0x138: branch row indices, the size is +0x134
var no_strings := 0              ## +0x148
var planned_on := 0              ## +0x150
var planned := PackedInt32Array()   ## +0x158: branch row indices, the size is +0x154
var link_skip := 0               ## +0x220
var links_on := 0                ## +0x224
var links := PackedInt32Array()  ## +0x22C: branch row indices, the size is +0x228
var link_last := 0               ## +0x258
var attacks_in_row := 0          ## +0x25C
var attack_limit := 0            ## +0x260
var history := PackedInt64Array([0, 0, 0])   ## +0x268: game addresses of moves, newest first
## +0x274: the opponent is in Ogre's breath, or (FUN_801C3730's shift) a move's game address.
var opp_breath := 0
var history_same := 0            ## +0x278: all three history entries are equal
var opp_move_changed := 0        ## +0x27C
var opp_down := 0                ## +0x284
var opp_until := 0               ## +0x288: frames until the opponent's attack is active (999: none)
var opp_coming := 0              ## +0x28C
var opp_unblockable := 0         ## +0x290
var opp_charging := 0            ## +0x294
var coming_seen := 0             ## +0x298
var opp_grabs := 0               ## +0x29C
var opp_string := -1             ## +0x2A0
var opp_joint_y := 0             ## +0x2A4
var opp_high := 0                ## +0x2AC
var neutral_block := 0           ## +0x2B0: 0x32 after a neutral-action attack
var neutral_frames := 0          ## +0x2B4
var neutral_actions := 0         ## +0x2B8
var own_word := 0                ## +0x2BC: the CPU's move +0x08
var own_state := 0               ## +0x2C0: the CPU's move +0x04
var own_attack := 0              ## +0x2C4
var opp_word := 0                ## +0x2C8
var opp_state := 0               ## +0x2CC
var opp_attack := 0              ## +0x2D0
var params := PackedInt32Array() ## +0x2D4: the difficulty words
var own_bands := PackedInt32Array()   ## +0x34C
var opp_bands := PackedInt32Array()   ## +0x358


func _init() -> void:
	params.resize(PARAM_WORDS)
	own_bands.resize(BAND_WORDS)
	opp_bands.resize(BAND_WORDS)


## Difficulty word `i`.
func word(i: int) -> int:
	return params[i]


## Word `i` raised by `amount` up to the word `cap` names; both as s16 (FUN_801C3730).
func raise_word(i: int, amount: int, cap: int) -> void:
	params[i] = mini(Fx.s16(params[i] + amount), params[cap])


func script_pending() -> bool:
	return script_at >= 0


func clear_script() -> void:
	script_steps = PackedInt32Array()
	script_at = -1
