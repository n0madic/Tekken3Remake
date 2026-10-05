class_name AttackRecords
## Access to a move's attack descriptor (move +0x28): a record of section 9 of the move's bank,
## or one of the 13 built-in descriptors of the executable. A descriptor starts with the joint
## pairs (a0, b0, a1, b1); a record continues with a big-endian layout word and the baked points
## (divmot-banks.md#attack-records-section-9). The game reads past a built-in descriptor into the
## bytes after it, so those come from `FightTables.builtin_blob` as they lie in memory.


## The bytes a descriptor pointer reaches and its offset in them, or an empty array for none.
static func bytes_of(move: MoveRow, t: FightTables) -> PackedByteArray:
	if move.builtin_attack >= 0:
		return t.builtin_blob
	return move.bank.attacks


static func offset_of(move: MoveRow, t: FightTables) -> int:
	if move.builtin_attack >= 0:
		return t.builtin_attack_offsets[move.builtin_attack]
	return move.attack_record


static func has_descriptor(move: MoveRow) -> bool:
	return move.builtin_attack >= 0 or move.attack_record >= 0


## The descriptor's first joint (a0), 0 without one (the game reads address 0 then, which
## holds a small value on the console and in the harness).
static func first_joint(move: MoveRow, t: FightTables) -> int:
	if not has_descriptor(move):
		return 0
	return bytes_of(move, t)[offset_of(move, t)]


## The first six bytes: a0, b0, a1, b1 and the layout word's two bytes.
static func header(move: MoveRow, t: FightTables) -> PackedByteArray:
	if not has_descriptor(move):
		return PackedByteArray([0, 0, 0, 0, 0, 0])
	var at := offset_of(move, t)
	return bytes_of(move, t).slice(at, at + 6)


## AttackUsesJoint (0x8002EDA0): the running move's descriptor names the joint (0: any).
static func uses_joint(f: FighterState, joint: int, t: FightTables) -> bool:
	if joint == 0:
		return true
	var h := header(f.pose_move, t)
	for i in 4:
		if h[i] == joint:
			return true
	return false
