class_name AiRecord
extends CpuRecord
## A CPU fighter's AI record (0x330 bytes at 0x8009F6C0 + 0x330 · slot; ai.md#entry-and-state): what
## `CpuRecord` does not hold. Field comments give the record offsets; the port keeps the game's
## widths where values wrap.

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

var target: FighterState         ## +0x10
var distance := 0                ## +0x1C
var angle := 0                   ## +0x2E: the CPU's relAngle
var situation := 0               ## +0x64
var throw_row := PackedInt32Array()   ## +0xBC
var strings_count := 0           ## +0xC2
var strings: Array[PackedInt32Array] = []    ## +0xC4
var planned_count := 0           ## +0xDA
var planned: Array[PackedInt32Array] = []    ## +0xDC
var links_count := 0             ## +0x1A2
var links: Array[PackedInt32Array] = []      ## +0x1A4
var history: Array[MoveRow] = [] ## +0x1DC: the opponent's moves that hurt the CPU
var history_at := 0              ## +0x1FC
var reload_timer := 0            ## +0x1FE
var opp_breath := 0              ## +0x200
var opp_gon_special := 0         ## +0x201
var adaptive := 0                ## +0x202
var input_mode := 0              ## +0x21E: 0 no input, 1 hold up while crouching, else AI
var own_bands := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## +0x314
var opp_bands := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## +0x320
var force_words := 0              ## +0x32C: Tekken Force's pattern (index into AiTables.force_words)


func _init() -> void:
	params.resize(PARAM_WORDS)
	for i in HISTORY:
		history.append(null)


## Byte `i` of the difficulty words (words 0–1 hold four bytes).
func param_byte(i: int) -> int:
	return ((params[i >> 1] & 0xFFFF) >> (8 * (i & 1))) & 0xFF
