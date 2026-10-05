class_name MotionSet
extends RefCounted
## A fighter's motion bank together with the common bank `divmot99`: resolves move slots
## and animation words that point into the common bank (`MoveLookup`).


## A move row or an animation stream in one of the two banks.
class Ref:
	var bank: MotionBank
	var value: int      ## row index or stream offset

	func _init(in_bank: MotionBank, in_value: int) -> void:
		bank = in_bank
		value = in_value


var own: MotionBank
var common: MotionBank


func _init(own_bank: MotionBank, common_bank: MotionBank) -> void:
	own = own_bank
	common = common_bank


## The move row of a slot, or null for an empty slot.
func move_for_slot(slot: int) -> Ref:
	var entry := own.move_index[slot]
	if entry == MotionBank.EMPTY_SLOT:
		return null
	if entry >= MotionBank.COMMON_FLAG:
		return Ref.new(common, entry - MotionBank.COMMON_FLAG)
	return Ref.new(own, entry)


## The animation stream of a move row.
func anim_of(move: Ref) -> Ref:
	var word := move.bank.moves[move.value][MotionBank.ROW_ANIM]
	if word >= MotionBank.COMMON_FLAG:
		return Ref.new(common, word - MotionBank.COMMON_FLAG)
	return Ref.new(move.bank, word)


## The animation of a slot's move, or null when the slot is empty or has no stream.
func anim_for_slot(slot: int) -> Ref:
	var move := move_for_slot(slot)
	if move == null:
		return null
	var anim := anim_of(move)
	return anim if anim.bank.has_anim(anim.value) else null


## The decoded move row of a slot (a fresh MoveRow, not the fight's linked rows), or null.
func row_for_slot(slot: int) -> MoveRow:
	var move := move_for_slot(slot)
	if move == null:
		return null
	return MoveRow.link(move.bank, move.value, common, PackedInt32Array())
