extends TestSuite
## The tables and rules the PlayStation and the arcade versions share: the CPU's movement by draw, the
## guard its posture must hold, the ladder's costumes, the costume a clash changes, the branch rows'
## restrictions and the strike sounds. The golden traces prove them against the programs when the
## traces exist; these name the thresholds and need no game data.

const OTHER_BAND := 6                ## a band the tables do not have


func test_the_movement_by_distance_band_changes_kind_at_its_thresholds() -> void:
	var by_band := CpuDecision.movement_by_band
	expect_equal(by_band.call(0, 0, 0, 0, 0x13), CpuDecision.MOVE_RETREAT, "bands 0 and 1 step back below 0x14")
	expect_equal(by_band.call(1, 0, 0, 0, 0x14), CpuDecision.MOVE_NONE, "and do nothing from it")
	expect_equal(by_band.call(2, 0, 0, 0, 0x79), CpuDecision.MOVE_LONG_WALK, "band 2")
	expect_equal(by_band.call(2, 0, 0, 0, 0x7A), CpuDecision.MOVE_DASH)
	expect_equal(by_band.call(2, 0, 0, 0, 0x1EB), CpuDecision.MOVE_RETREAT)
	expect_equal(by_band.call(2, 0, 0, 0, 0x214), CpuDecision.MOVE_NONE, "no side step without its share")
	expect_equal(by_band.call(2, 0, 0, 1000, 0x214), CpuDecision.MOVE_SIDE_STEP, "a full share (1000 per mille of 0x1000)")
	expect_equal(by_band.call(3, 0, 0, 0, 0x665), CpuDecision.MOVE_WALK, "band 3")
	expect_equal(by_band.call(3, 0, 0, 0, 0x666), CpuDecision.MOVE_DASH)
	expect_equal(by_band.call(3, 0, 0, 0, 0xB33), CpuDecision.MOVE_NONE)
	expect_equal(by_band.call(4, 0, 0, 0, 0xCB), CpuDecision.MOVE_WALK, "band 4")
	expect_equal(by_band.call(4, 0, 0, 0, 0xCC), CpuDecision.MOVE_LONG_DASH)
	expect_equal(by_band.call(4, 0, 0, 0, 0x599), CpuDecision.MOVE_DASH)
	expect_equal(by_band.call(5, 0x2D0, 0, 0, 0x11D), CpuDecision.MOVE_LONG_DASH, "band 5 dashes in from 0x11E")
	expect_equal(by_band.call(5, 0x2D0, 0, 0, 0x11E), CpuDecision.MOVE_DASH)
	expect_equal(by_band.call(5, 0x2D1, 0, 0, 0x11E), CpuDecision.MOVE_LONG_DASH, "but not after a long far count")
	expect_equal(by_band.call(5, 0, 1, 0, 0x11E), CpuDecision.MOVE_LONG_DASH, "nor against a fallen opponent")
	expect_equal(by_band.call(OTHER_BAND, 0, 0, 0, 0), CpuDecision.MOVE_NONE, "no such band")


func test_the_movement_by_reach_band_changes_kind_at_its_thresholds() -> void:
	var by_reach := CpuDecision.movement_by_reach
	expect_equal(by_reach.call(0, 0, 0, true, 0x198), CpuDecision.MOVE_BACK_DASH, "bands 0 and 1")
	expect_equal(by_reach.call(1, 0, 0, true, 0x199), CpuDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(1, 0, 0, true, 0x333), CpuDecision.MOVE_NONE)
	expect_equal(by_reach.call(2, 0, 0, true, 0x27), CpuDecision.MOVE_WALK, "band 2")
	expect_equal(by_reach.call(2, 0, 0, true, 0x28), CpuDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(2, 0, 0, true, 0x170), CpuDecision.MOVE_NONE)
	expect_equal(by_reach.call(3, 0, 0, true, 0x1EA), CpuDecision.MOVE_WALK, "band 3")
	expect_equal(by_reach.call(3, 0, 0, true, 0x1EB), CpuDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(3, 0, 0, true, 0x214), CpuDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(3, 0, 0, true, 0x218), CpuDecision.MOVE_DASH)
	expect_equal(by_reach.call(3, 0, 0, true, 0x22D), CpuDecision.MOVE_SIDE_STEP, "a standing fighter side steps")
	expect_equal(by_reach.call(3, 0, 0, false, 0x22D), CpuDecision.MOVE_NONE, "a crouching one does not")
	expect_equal(by_reach.call(3, 0, 0, true, 0x241), CpuDecision.MOVE_NONE)
	expect_equal(by_reach.call(4, 0, 0, true, 0x7F), CpuDecision.MOVE_WALK, "band 4")
	expect_equal(by_reach.call(4, 0, 0, true, 0x80), CpuDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(4, 0, 0, true, 0x90), CpuDecision.MOVE_SIDE_STEP)
	expect_equal(by_reach.call(4, 0, 0, true, 0xC0), CpuDecision.MOVE_DASH)
	expect_equal(by_reach.call(4, 0, 0, true, 0x3C0), CpuDecision.MOVE_NONE)
	expect_equal(by_reach.call(5, 0, 0, true, 0x50), CpuDecision.MOVE_LONG_DASH, "band 5 below 0x51")
	expect_equal(by_reach.call(5, 0, 0, true, 0x51), CpuDecision.MOVE_WALK)
	expect_equal(by_reach.call(5, 0, 0, true, 0xCC), CpuDecision.MOVE_DASH)
	expect_equal(by_reach.call(5, 0, 0, true, 0x400), CpuDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(5, 0, 0, true, 0x5EB), CpuDecision.MOVE_NONE)
	expect_equal(by_reach.call(5, 0x2D1, 0, true, 0x400), CpuDecision.MOVE_LONG_DASH, "after a long far count")
	expect_equal(by_reach.call(OTHER_BAND, 0, 0, true, 0), CpuDecision.MOVE_NONE, "no such band")


func test_a_posture_holds_the_guard_of_the_attack_level() -> void:
	var holds := CpuDecision.guard_posture_holds
	var postures := [StateWord.STAND, StateWord.CROUCH, StateWord.GUARD_LOW, StateWord.GUARD_HIGH]
	# attack → the postures that stop it
	var table := {
		AttackWord.HIGH: [StateWord.CROUCH, StateWord.GUARD_LOW, StateWord.GUARD_HIGH],
		AttackWord.MID: [StateWord.GUARD_HIGH],
		AttackWord.LOW: [StateWord.GUARD_LOW],
		AttackWord.MID_2: [StateWord.GUARD_LOW, StateWord.GUARD_HIGH],
		AttackWord.UNBLOCKABLE_2: [StateWord.GUARD_LOW, StateWord.CROUCH],
		AttackWord.UNBLOCKABLE: [],
	}
	for attack: int in table:
		for posture: int in postures:
			var expected: bool = posture in (table[attack] as Array)
			expect_equal(holds.call(posture, attack, 0, 1, 0), expected, "attack %X against posture %X" % [attack, posture])
		expect_equal(holds.call(StateWord.GUARD_HIGH, attack, 0, 0, 0), false, "nothing comes: no guard needed")
		expect_equal(holds.call(StateWord.GUARD_HIGH, attack, 0, 1, 0x3001), false, "it comes from the side")
	for posture: int in postures:
		var low := posture == StateWord.CROUCH or posture == StateWord.GUARD_LOW
		expect_equal(holds.call(posture, AttackWord.HIGH, 1, 0, 0), low, "a grab needs the low postures")
		expect_equal(holds.call(posture, AttackWord.MID, 1, 0, 0), false, "except a mid grab")


func test_the_ladder_costume_follows_the_players_unless_it_is_ogre() -> void:
	expect_equal(Opponents.ladder_costume(Character.PAUL, 0), 0, "costume 0 of the player")
	expect_equal(Opponents.ladder_costume(Character.PAUL, 1), 1, "another costume")
	expect_equal(Opponents.ladder_costume(Character.PAUL, 0x58 | 3), 1, "only the key's low bits count")
	expect_equal(Opponents.ladder_costume(Character.OGRE, 3), 0, "Ogre has one")
	expect_equal(Opponents.ladder_costume(Character.TRUE_OGRE, 3), 0, "so has True Ogre")


func test_the_strike_sound_follows_the_damage_and_the_first_joint() -> void:
	var tables := FightTables.new()
	tables.strike_sounds = PackedInt32Array([0x7031, 0x7032])
	var fight := FightState.new(tables, RuleSet.original())
	var damage_tiers := [[0, 0], [0xC, 0], [0xD, 1], [0x16, 1], [0x17, 2], [0x20, 2], [0x21, 3]]
	for pair: Array in damage_tiers:
		var before := fight.rng.state
		expect_equal(FighterSounds.strike_code(fight, pair[0] as int, FighterSounds.GUARD_JOINT), 0x7045 + (pair[1] as int),
			"damage %X from a joint at or above the guard joint" % pair[0])
		expect_equal(fight.rng.state, before, "needs no draw")
	for pair: Array in damage_tiers:
		if pair[1] == 0:
			continue
		var before := fight.rng.state
		expect_equal(FighterSounds.strike_code(fight, pair[0] as int, FighterSounds.GUARD_JOINT - 1), 0x7041 + (pair[1] as int),
			"damage %X from a joint below it" % pair[0])
		expect(fight.rng.state != before, "draws once even when the tier decides")
	var seen := {}
	for i in 16:
		seen[FighterSounds.strike_code(fight, 0, 0)] = true
	expect_equal(seen.keys().size(), 2, "the lightest strike is one of the table's two sounds")
	for code: int in seen:
		expect(code in tables.strike_sounds, "%X is from the table" % code)


func test_a_costume_taken_twice_goes_to_the_other_of_the_pair_or_back_to_the_first() -> void:
	expect_equal(Opponents.costume_after_clash(0), 1, "0 becomes 1")
	expect_equal(Opponents.costume_after_clash(1), 0, "1 becomes 0")
	expect_equal(Opponents.costume_after_clash(2), 0, "a Start costume becomes 0")
	expect_equal(Opponents.costume_after_clash(3), 0)


func test_the_side_that_is_not_active_yields_to_an_active_one() -> void:
	expect(Opponents.clash_yields_other(1, 0), "an active side against an idle one: the idle one changes")
	expect(not Opponents.clash_yields_other(1, 1), "two active sides: the later one changes")
	expect(not Opponents.clash_yields_other(0, 0), "two idle sides: the later one changes")
	expect(not Opponents.clash_yields_other(0, 1), "an idle side against an active one: the idle one changes")


func test_a_mirror_match_changes_the_costume_of_the_side_that_chose_later() -> void:
	var g := GameGlobals.new()
	g.player_char = PackedInt32Array([Character.PAUL, Character.PAUL])
	g.player_costume = PackedInt32Array([0, 0])
	g.player_keep = PackedInt32Array([0, 1])
	g.player_active = PackedInt32Array([1, 1])
	ModeStart.mirror_costumes(g, 0)
	expect_equal(g.player_costume, PackedInt32Array([1, 0]), "side 0 chose later and takes costume 1")
	expect_equal(g.player_keep[0], 1, "its pick is kept")
	g.player_costume = PackedInt32Array([0, 0])
	g.player_active = PackedInt32Array([1, 0])
	ModeStart.mirror_costumes(g, 0)
	expect_equal(g.player_costume, PackedInt32Array([0, 1]), "the idle side yields to the human")
	g.player_costume = PackedInt32Array([2, 2])
	g.player_active = PackedInt32Array([1, 1])
	ModeStart.mirror_costumes(g, 0)
	expect_equal(g.player_costume, PackedInt32Array([0, 2]), "costume 2 becomes 0")
	g.player_costume = PackedInt32Array([0, 0])
	g.player_keep = PackedInt32Array([0, 0])
	ModeStart.mirror_costumes(g, 0)
	expect_equal(g.player_costume, PackedInt32Array([0, 0]), "the other side has not chosen: no clash")
	g.player_keep = PackedInt32Array([0, 1])
	g.player_char = PackedInt32Array([Character.PAUL, Character.KING])
	ModeStart.mirror_costumes(g, 0)
	expect_equal(g.player_costume, PackedInt32Array([0, 0]), "another character: no clash")


func test_the_select_records_of_a_clash_change_one_costume() -> void:
	var block := ByteBlock.new(32)
	var a := 0
	var b := 16
	# (key, costume, decided, active) as u32 words
	var set_record := func(at: int, key: int, costume: int, decided: int, active: int) -> void:
		block.put32(at, key)
		block.put32(at + 4, costume)
		block.put32(at + 8, decided)
		block.put32(at + 12, active)
	set_record.call(a, 5, 0, 1, 1)
	set_record.call(b, 5, 0, 1, 1)
	QuickSelect.costume_clash(block, a, b)
	expect_equal([block.s32(a + 4), block.s32(b + 4)], [1, 0], "two active sides: the first record changes")
	set_record.call(b, 5, 0, 1, 0)
	set_record.call(a, 5, 0, 1, 1)
	QuickSelect.costume_clash(block, a, b)
	expect_equal([block.s32(a + 4), block.s32(b + 4)], [0, 1], "an idle second side yields")
	set_record.call(b, 5, 0, 0, 0)
	QuickSelect.costume_clash(block, a, b)
	expect_equal([block.s32(a + 4), block.s32(b + 4)], [0, 0], "the second side has not decided: nothing changes")
	set_record.call(b, 6, 0, 1, 1)
	QuickSelect.costume_clash(block, a, b)
	expect_equal([block.s32(a + 4), block.s32(b + 4)], [0, 0], "another key: nothing changes")


func test_a_branch_restriction_names_a_bank_or_a_character() -> void:
	var f := FighterState.new()
	var opp := FighterState.new()
	f.bank_type = 2
	opp.bank_type = 5
	f.char_id = 7
	var end := MoveSystem.RESTRICTION_CHARACTERS_END
	expect(_restricted(f, opp, 0), "0: any")
	expect(_restricted(f, opp, 3), "1–0x17: this bank, 3 is bank 2")
	expect(not _restricted(f, opp, 2), "bank 1 is not it")
	expect(_restricted(f, opp, 0x18 + 3), "0x18–0x2E: any other bank")
	expect(not _restricted(f, opp, 0x18 + 2), "but not this one")
	expect(_restricted(f, opp, 0x2F + 5), "0x2F–0x45: the opponent's bank")
	expect(not _restricted(f, opp, 0x2F + 2), "not the fighter's own")
	expect(_restricted(f, opp, 0x46 + 7), "0x46 on: this character")
	expect(not _restricted(f, opp, 0x46 + 6), "not another")
	expect(_restricted(f, opp, end), "the range's end itself already means any character but 0")
	expect(_restricted(f, opp, end + 6), "from the range's end: any other character")
	expect(not _restricted(f, opp, end + 7), "but not this one")
	f.char_id = 0x16
	expect(MoveSystem.restriction_holds(f, opp, 0x5C, 0x5D), "byte 0x5C names character 0x16 when the range ends at 0x5D")
	expect(MoveSystem.restriction_holds(f, opp, 0x5C, 0x5C), "and means any character but 0 when it ends at 0x5C")
	f.char_id = 0
	expect(not MoveSystem.restriction_holds(f, opp, 0x5C, 0x5C), "which character 0 fails")
	f.char_id = 7
	expect(CpuOpponent.restriction_ok(f, opp, CpuOpponent.RESTRICTION_LAST), "the AI reads the same bytes")
	expect(not CpuOpponent.restriction_ok(f, opp, CpuOpponent.RESTRICTION_LAST + 1), "but none above its last")


func test_the_arcade_keeps_the_row_flag_bits_masked_and_ends_the_character_range_one_earlier() -> void:
	var fight := FightState.new(FightTables.new(), RuleSet.new())
	var ps1 := MoveSystem.new(fight)
	var arcade := ArcadeMoveSystem.new(fight)
	expect_equal(ps1._flag_bit(0xC1, MoveSystem.ROW_FLAG_BIT7), 1, "the PlayStation keeps a set flag bit as 1")
	expect_equal(ps1._flag_bit(0x41, MoveSystem.ROW_FLAG_BIT7), 0, "and a clear one as 0")
	expect_equal(arcade._flag_bit(0xC1, MoveSystem.ROW_FLAG_BIT7), 0x80, "the arcade keeps the masked bit itself")
	expect_equal(arcade._flag_bit(0x41, MoveSystem.ROW_FLAG_BIT6), 0x40)
	expect_equal(arcade._flag_bit(0x81, MoveSystem.ROW_FLAG_BIT6), 0, "a clear bit stays 0")
	var f := FighterState.new()
	var opp := FighterState.new()
	f.char_id = 5
	# Byte 0x5C is the PlayStation's character 0x16 and the arcade's first "any other character" byte.
	expect(not ps1._restriction_ok(f, opp, 0x5C), "the PlayStation: 0x5C names character 0x16, this one is 5")
	expect(arcade._restriction_ok(f, opp, 0x5C), "the arcade: 0x5C means any character but 0")


func _restricted(f: FighterState, opp: FighterState, value: int) -> bool:
	return MoveSystem.restriction_holds(f, opp, value, MoveSystem.RESTRICTION_CHARACTERS_END)
