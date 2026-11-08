@abstract
class_name CpuDecision
extends RefCounted
## What the PlayStation's AI update (`AiDecision`) and the arcade's (`ArcadeAiDecision`) share: the frame's
## context (the CPU and its opponent, their running moves), the kinds of movement a random draw picks by
## the distance and the reach band, the guard a posture must hold and the names of the move and row
## fields. Each build's steps and records stay in its own class.

## The kinds of movement the random pick chooses (arcade FUN_801CB2F0; `_do_movement` takes them).
const MOVE_NONE := 0
const MOVE_DASH := 1                 ## side step or walk in
const MOVE_WALK := 2
const MOVE_RETREAT := 3
const MOVE_LONG_DASH := 4            ## side step with a long approach, or dash in
const MOVE_LONG_WALK := 5
const MOVE_BACK_DASH := 6            ## crouch dash or step back
const MOVE_SIDE_STEP := 8
const WAIT_LONG := 0x23              ## beyond this wait the pick follows the reach band
const GUARD_ANGLE := 0x3000          ## least angle to the opponent at which an attack no longer comes at the CPU
const ROW_COMMAND := CpuMachinery.ROW_COMMAND
const ROW_CONDITION := CpuMachinery.ROW_CONDITION
const ROW_TARGET := CpuMachinery.ROW_TARGET
const ROW_FLAGS := CpuMachinery.ROW_FLAGS
const ROW_FIRST := CpuMachinery.ROW_FIRST
const ROW_LAST := CpuMachinery.ROW_LAST
const ROW_ENTRY := CpuMachinery.ROW_ENTRY
const ROW_RESTRICTION := CpuMachinery.ROW_RESTRICTION
const HINT_NEVER := CpuMachinery.HINT_NEVER
const HINT_SAFE := CpuMachinery.HINT_SAFE
const HINT_CLOSE := CpuMachinery.HINT_CLOSE
const HINT_MIDDLE := CpuMachinery.HINT_MIDDLE
const HINT_REACH := CpuMachinery.HINT_REACH
const HINT_SPECIAL := CpuMachinery.HINT_SPECIAL
const GRAB := CpuMachinery.GRAB

var fight: FightState
var t: AiTables

# The frame's context.
var f: FighterState
var o: FighterState
var sm: MoveRow
var om: MoveRow
var my_first := 0
var my_last := 0
var my_frame := 0
var op_first := 0
var op_last := 0
var op_frame := 0


func _init(opponent: CpuMachinery) -> void:
	fight = opponent.fight
	t = opponent.t


## The held and the newly pressed pad words of CPU fighter `fighter` for one frame: each build's own.
@abstract func update(fighter: FighterState) -> PackedInt32Array


## Whether the posture is one that stops the attack level: a grab needs a crouch or a low guard unless
## it is a mid, an attack that comes at the CPU needs the guard of its level.
static func guard_posture_holds(posture: int, attack: int, grabs: int, coming: int, angle: int) -> bool:
	if grabs != 0:
		return attack != AttackWord.MID and (posture == StateWord.CROUCH or posture == StateWord.GUARD_LOW)
	if coming == 0 or angle > GUARD_ANGLE:
		return false
	match attack:
		AttackWord.HIGH:
			return posture == StateWord.CROUCH or posture == StateWord.GUARD_LOW or posture == StateWord.GUARD_HIGH
		AttackWord.MID:
			return posture == StateWord.GUARD_HIGH
		AttackWord.LOW:
			return posture == StateWord.GUARD_LOW
		AttackWord.MID_2:
			return posture == StateWord.GUARD_LOW or posture == StateWord.GUARD_HIGH
		AttackWord.UNBLOCKABLE_2:
			return posture == StateWord.GUARD_LOW or posture == StateWord.CROUCH
	return false


## The movement for a random draw `v` (0 to 0xFFF) by the distance band; `side_step_word` is the
## difficulty word that sets the side step's share.
static func movement_by_band(band: int, far_count: int, opp_down: int, side_step_word: int, v: int) -> int:
	match band:
		0, 1:
			return MOVE_RETREAT if v < 0x14 else MOVE_NONE
		2:
			if v < 0x7A:
				return MOVE_LONG_WALK
			if v < 0x1EB:
				return MOVE_DASH
			if v < 0x214:
				return MOVE_RETREAT
			return MOVE_SIDE_STEP if v < Fx.div_trunc(side_step_word << 12, 1000) else MOVE_NONE
		3:
			return MOVE_WALK if v < 0x666 else (MOVE_DASH if v < 0xB33 else MOVE_NONE)
		4:
			return MOVE_WALK if v < 0xCC else (MOVE_LONG_DASH if v < 0x599 else MOVE_DASH)
		5:
			if far_count < 0x2D1 and opp_down == 0 and v > 0x11D:
				return MOVE_DASH
			return MOVE_LONG_DASH
	return MOVE_NONE


## The movement for a random draw `v` while waiting long, by the reach band.
static func movement_by_reach(reach_band: int, far_count: int, opp_down: int, standing: bool, v: int) -> int:
	match reach_band:
		0, 1:
			return MOVE_BACK_DASH if v < 0x199 else (MOVE_RETREAT if v < 0x333 else MOVE_NONE)
		2:
			if v <= 0x27:
				return MOVE_WALK
			return MOVE_RETREAT if v < 0x170 else MOVE_NONE
		3:
			if v < 0x1EB:
				return MOVE_WALK
			if v < 0x214:
				return MOVE_LONG_WALK
			if v < 0x218:
				return MOVE_RETREAT
			if v < 0x22D:
				return MOVE_DASH
			return MOVE_SIDE_STEP if v < 0x241 and standing else MOVE_NONE
		4:
			if v < 0x80:
				return MOVE_WALK
			if v < 0x90:
				return MOVE_LONG_WALK
			if v < 0xC0:
				return MOVE_SIDE_STEP
			return MOVE_DASH if v < 0x3C0 else MOVE_NONE
		5:
			if far_count < 0x2D1 and opp_down == 0 and v > 0x50:
				if v < 0xCC:
					return MOVE_WALK
				if v < 0x400:
					return MOVE_DASH
				return MOVE_LONG_WALK if v < 0x5EB else MOVE_NONE
			return MOVE_LONG_DASH
	return MOVE_NONE


static func _dec(v: int) -> int:
	return v - 1 if v >= 0 else v
