@abstract
class_name CpuMachinery
extends RefCounted
## What the PlayStation's CPU opponent (`CpuOpponent`) and the arcade's (`ArcadeCpu`) share: the fight, its
## tables and move system, the candidate table (one serves every CPU fighter, as in the game), the AI's
## two random generators, and the names of the branch rows' fields and of the AI byte of a move's attack
## word, the scripts and presses both builds start the same way, and the hooks' common rules. The two
## builds' records, filters and the rest of their hooks differ and stay in their own classes.

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
const APPROACH_HOLD := 0x28             ## the approach timer after an approach starts or stops
const SIDE_STEP_AUTO := -1              ## a side step told to pick its side
const NO_SIDE := -1
## The side step's choice reads the opponent's heading difference by the half turn: this range of
## headings is side 0, the half turn around the reversed heading side 1, any other none.
const HEADING_SIDE_A := 0x101
const HEADING_SIDE_A_SPAN := 0x7EFF
const HEADING_SIDE_B := 0x7FFF
const HEADING_SIDE_B_SPAN := 0x7EFE
## Hook results (the arcade's FUN_801CD708): a pad word otherwise.
const HOOK_NOTHING := -1
const HOOK_ACTED := -2
const PAUL_BACK_FRAME := 0x10           ## the frame of Paul's move from which the CPU backs away
const OGRE_NEAR := 0x1B59               ## closer than this Ogre's moves are answered by stepping aside
const STATE_BIT22 := 0x400000           ## a move state bit the code names only by number

var fight: FightState
var t: AiTables
var moves: MoveSystem
## The pad words of a script step's four buttons (step bits 8–11), the build's own.
var step_buttons := PackedInt32Array()
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


# ---- scripts, presses and the approach ------------------------------------------------------

## A script step's pad word (AiPadFromStep 0x80061AC4, the arcade's FUN_801C3EA0): the numpad
## direction in bits 0–3 and the buttons in bits 8–11.
func pad_from_step(step: int) -> int:
	var pad := 0
	for k in 4:
		if step & (0x100 << k):
			pad |= step_buttons[k]
	return pad | t.numpad_pads[step & 0xF]


## AiStartScript (0x80061B24, the arcade's FUN_801C3EA0): presses the first step now and keeps the
## rest pending.
func start_script(rec: CpuRecord, steps: PackedInt32Array) -> void:
	rec.script_steps = steps
	rec.script_at = 1 if steps.size() > 1 else -1
	rec.pad = pad_from_step(steps[0] if not steps.is_empty() else 0)


## A branch command's directions and buttons as a pad word (AiPressCommand 0x80061BA8, the arcade's
## FUN_801C3F30): the direction whose mask the command's bits 5–13 reach, from the highest down.
func command_pad(command: int) -> int:
	var d := 9
	while d > 0 and t.direction_masks[d] & (command >> 5) & 0x1FF == 0:
		d -= 1
	var buttons := 0
	for k in 4:
		if (command >> k) & 1:
			buttons |= t.button_pads[k]
	return (t.direction_pads[d] | buttons) & 0xFFFF


## FUN_80056A30 (the arcade's FUN_801C3118 family): restarts the approach timers.
static func reset_approach(rec: CpuRecord) -> void:
	rec.approach_hold = APPROACH_HOLD
	rec.approach_kind = 0
	rec.approach = 0
	rec.direction_hold = -1


# ---- side steps and the hooks' common rules ------------------------------------------------

## The side a heading difference (a u16) gives, as AiSideStep and the hooks against Ogre read it:
## NO_SIDE when it is nearly straight or reversed.
static func heading_side(heading: int) -> int:
	heading &= 0xFFFF
	if heading >= HEADING_SIDE_A and heading - HEADING_SIDE_A < HEADING_SIDE_A_SPAN:
		return 0
	if (heading + HEADING_SIDE_B) & 0xFFFF < HEADING_SIDE_B_SPAN:
		return 1
	return NO_SIDE


## `side` mirrored when the opponent stands to the left of the CPU on the screen.
static func side_toward(side: int, opp_x: int, own_x: int) -> int:
	return 1 - side if Fx.s16(opp_x) < Fx.s16(own_x) else side


## The side AiSideStep (0x80061D40, the arcade's FUN_801CDA04) takes when it is told to pick one: from
## the heading, at random when that is ambiguous, mirrored by the fighters' order on the screen.
func auto_side(heading: int, opp_x: int, own_x: int) -> int:
	var side := heading_side(heading)
	if side == NO_SIDE:
		side = (fight.rng.next() >> 4) & 1
	return side_toward(side, opp_x, own_x)


## The side to step to from Ogre's fire breath (inlined in the PlayStation's hook, the arcade's
## FUN_801CDBE8): the opponent's heading gives it unless the CPU's own move has state bit 22 or the
## fighters are 7,001 or more apart. NO_SIDE for none.
static func ogre_breath_side(own: FighterState, opp: FighterState, heading: int, distance: int) -> int:
	if own.pose_move.state & STATE_BIT22 != 0 or (distance & 0xFFFFFFFF) >= OGRE_NEAR:
		return NO_SIDE
	var side := heading_side(heading)
	if side == NO_SIDE:
		return NO_SIDE
	return side_toward(side, opp.screen_x, own.screen_x)


## The side to step to from Ogre's sweep (the arcade's FUN_801CDB78): toward the opponent, when the
## CPU's own heading is within a quarter turn of straight, its move has no state bit 22 and the
## fighters are less than 7,001 apart. NO_SIDE for none.
static func ogre_sweep_side(own: FighterState, opp: FighterState, distance: int) -> int:
	if (((own.heading_delta & 0xFFFF) + 0x2000) & 0xFFFF) > 0x4000 or own.pose_move.state & STATE_BIT22 != 0 \
			or (distance & 0xFFFFFFFF) >= OGRE_NEAR:
		return NO_SIDE
	return 1 if Fx.s16(own.screen_x) < Fx.s16(opp.screen_x) else 0


## The hook against Paul (the arcade's 0x801CE078): while he is in his slot `slot` and the CPU is at
## close reach it backs away (`back`, the build's pad word) once the move is under way, else it attacks
## at once.
func vs_paul(rec: CpuRecord, opp: FighterState, slot: int, back: int) -> int:
	if Fx.s16(opp.cur_slot) == slot and rec.reach_band < 3:
		if Fx.s16(opp.pose_frame) >= PAUL_BACK_FRAME:
			return back
		rec.wait = -1
	return HOOK_NOTHING


## The hook as Hwoarang (the arcade's 0x801CE984): in his slot `slot`, outside frames 0xD–0x11 or with
## the opponent's attack 10 or more frames away, the CPU walks forward (`forward`, the build's pad word)
## unless one draw in 16 says otherwise.
func as_hwoarang(rec: CpuRecord, own: FighterState, slot: int, forward: int) -> int:
	if Fx.s16(own.cur_slot) != slot:
		return HOOK_NOTHING
	var in_window := ((own.pose_frame & 0xFFFF) - 0xD) & 0xFFFFFFFF <= 4
	if in_window and rec.opp_until < 10:
		return HOOK_NOTHING
	return forward if fight.rng.next() & 0xF != 0 else HOOK_NOTHING
