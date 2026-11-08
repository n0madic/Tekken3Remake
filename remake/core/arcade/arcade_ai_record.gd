class_name ArcadeAiRecord
extends CpuRecord
## A CPU fighter's AI record in the arcade (0x364 bytes at 0x8029CF00 + 0x364 · slot): what
## `CpuRecord` does not hold. Field comments give the record offsets.

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

var wobble := 0                  ## +0x28
var wobble_phase := 0            ## +0x2C
var continuation: MoveRow        ## +0x94: the move the collected list ends in
var throw_row := -1              ## +0x12C: a branch row's index, −1 none
var strings := PackedInt32Array()   ## +0x138: branch row indices, the size is +0x134
var planned := PackedInt32Array()   ## +0x158: branch row indices, the size is +0x154
var links := PackedInt32Array()  ## +0x22C: branch row indices, the size is +0x228
var history := PackedInt64Array([0, 0, 0])   ## +0x268: game addresses of moves, newest first
## +0x274: the opponent is in Ogre's breath, or (FUN_801C3730's shift) a move's game address.
var opp_breath := 0
var history_same := 0            ## +0x278: all three history entries are equal
var opp_joint_y := 0             ## +0x2A4
var neutral_block := 0           ## +0x2B0: 0x32 after a neutral-action attack
var neutral_frames := 0          ## +0x2B4
var neutral_actions := 0         ## +0x2B8
var own_bands := PackedInt32Array()   ## +0x34C
var opp_bands := PackedInt32Array()   ## +0x358


func _init() -> void:
	params.resize(PARAM_WORDS)
	own_bands.resize(BAND_WORDS)
	opp_bands.resize(BAND_WORDS)


## Word `i` raised by `amount` up to the word `cap` names; both as s16 (FUN_801C3730).
func raise_word(i: int, amount: int, cap: int) -> void:
	params[i] = mini(Fx.s16(params[i] + amount), params[cap])


func clear_script() -> void:
	script_steps = PackedInt32Array()
	script_at = -1
