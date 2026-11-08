@abstract
class_name CpuMachinery
extends RefCounted
## What the PlayStation's CPU opponent (`CpuOpponent`) and the arcade's (`ArcadeCpu`) share: the fight, its
## tables and move system, the candidate table (one serves every CPU fighter, as in the game), the AI's
## two random generators, and the names of the branch rows' fields and of the AI byte of a move's attack
## word. The two builds' records, filters and hooks differ and stay in their own classes.

const MAX_CANDIDATES := 180
const END := MoveSystem.END
const SIDE_STEP := 0xC001
const CROUCH_DASH := 0xC002
## The AI byte of a move's attack word (+0x0A, ai.md#move-row-hint-bits).
const HINT_SAFE := 0x10000           ## a safe or priority attack
const HINT_CLOSE := 0x40000          ## reach bits: close, middle, far (none: close or middle)
const HINT_MIDDLE := 0x80000
const HINT_FAR := 0x100000
const HINT_REACH := HINT_CLOSE | HINT_MIDDLE | HINT_FAR
const HINT_SPECIAL := 0x200000       ## usable as an airborne or special move
const HINT_NEVER := 0x400000         ## never chosen by the AI
const GRAB := HINT_NEVER             ## the same bit of the opponent's move: a grab
const ROW_COMMAND := MoveSystem.ROW_COMMAND
const ROW_RESTRICTION := MoveSystem.ROW_RESTRICTION
const ROW_CONDITION := MoveSystem.ROW_CONDITION
const ROW_TARGET := MoveSystem.ROW_TARGET
const ROW_FLAGS := MoveSystem.ROW_FLAGS
const ROW_FIRST := MoveSystem.ROW_FIRST
const ROW_LAST := MoveSystem.ROW_LAST
const ROW_ENTRY := MoveSystem.ROW_ENTRY

var fight: FightState
var t: AiTables
var moves: MoveSystem
## The candidate table (0x8009FD20): target move, branch row, mark (−1 unusable, 0, 1 marked).
var cand_target: Array[MoveRow] = []
var cand_row: Array[PackedInt32Array] = []
var cand_mark := PackedInt32Array()


func _init(fight_state: FightState, move_system: MoveSystem) -> void:
	fight = fight_state
	moves = move_system
	t = fight.tables.ai
	cand_target.resize(MAX_CANDIDATES)
	cand_row.resize(MAX_CANDIDATES)
	cand_mark.resize(MAX_CANDIDATES)


## The round's reset: each build's own.
@abstract func init_round() -> void


# ---- random numbers -------------------------------------------------------------------------

## The AI generator 0x800AE168 (x = 5x + 3): returns the old value and advances it.
func lcg_next() -> int:
	var x := fight.ai_rng
	fight.ai_rng = (5 * x + 3) & 0xFFFFFFFF
	return x


## FUN_800569D0 and the draws like it: n · ((rand() + LCG) & 0x7FFF) >> 15.
func random_below(n: int) -> int:
	var r := fight.rng.next()
	var x := lcg_next()
	var p := n * ((r + x) & 0x7FFF)
	if p < 0:
		p += 0x7FFF
	return p >> 15


## Attack level `a` against the opponent state `g` (FUN_80057AC4, FUN_80057C88).
static func level_vs_state(g: int, a: int) -> bool:
	if g & 0xFFFF == StateWord.LAUNCHED:
		return true
	if g & StateBit.AIRBORNE:
		return a == AttackWord.HIGH or a == AttackWord.MID or a == AttackWord.MID_2
	if g & StateBit.DOWN:
		return a == AttackWord.LOW or a == AttackWord.LOW_2
	if g & StateBit.CROUCHING:
		return a == AttackWord.MID or a == AttackWord.LOW
	if g & StateBit.STANDING:
		return a == AttackWord.LOW or a == AttackWord.MID or a == AttackWord.HIGH
	return false
