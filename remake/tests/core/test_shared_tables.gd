extends TestSuite
## The tables the PlayStation and the arcade versions share: the CPU's movement by draw, the guard its
## posture must hold, the ladder's costumes and the strike sounds. The golden traces prove them against
## the programs when the traces exist; these name the thresholds and need no game data.

const OTHER_BAND := 6                ## a band the tables do not have


func test_the_movement_by_distance_band_changes_kind_at_its_thresholds() -> void:
	var by_band := AiDecision.movement_by_band
	expect_equal(by_band.call(0, 0, 0, 0, 0x13), AiDecision.MOVE_RETREAT, "bands 0 and 1 step back below 0x14")
	expect_equal(by_band.call(1, 0, 0, 0, 0x14), AiDecision.MOVE_NONE, "and do nothing from it")
	expect_equal(by_band.call(2, 0, 0, 0, 0x79), AiDecision.MOVE_LONG_WALK, "band 2")
	expect_equal(by_band.call(2, 0, 0, 0, 0x7A), AiDecision.MOVE_DASH)
	expect_equal(by_band.call(2, 0, 0, 0, 0x1EB), AiDecision.MOVE_RETREAT)
	expect_equal(by_band.call(2, 0, 0, 0, 0x214), AiDecision.MOVE_NONE, "no side step without its share")
	expect_equal(by_band.call(2, 0, 0, 1000, 0x214), AiDecision.MOVE_SIDE_STEP, "a full share (1000 per mille of 0x1000)")
	expect_equal(by_band.call(3, 0, 0, 0, 0x665), AiDecision.MOVE_WALK, "band 3")
	expect_equal(by_band.call(3, 0, 0, 0, 0x666), AiDecision.MOVE_DASH)
	expect_equal(by_band.call(3, 0, 0, 0, 0xB33), AiDecision.MOVE_NONE)
	expect_equal(by_band.call(4, 0, 0, 0, 0xCB), AiDecision.MOVE_WALK, "band 4")
	expect_equal(by_band.call(4, 0, 0, 0, 0xCC), AiDecision.MOVE_LONG_DASH)
	expect_equal(by_band.call(4, 0, 0, 0, 0x599), AiDecision.MOVE_DASH)
	expect_equal(by_band.call(5, 0x2D0, 0, 0, 0x11D), AiDecision.MOVE_LONG_DASH, "band 5 dashes in from 0x11E")
	expect_equal(by_band.call(5, 0x2D0, 0, 0, 0x11E), AiDecision.MOVE_DASH)
	expect_equal(by_band.call(5, 0x2D1, 0, 0, 0x11E), AiDecision.MOVE_LONG_DASH, "but not after a long far count")
	expect_equal(by_band.call(5, 0, 1, 0, 0x11E), AiDecision.MOVE_LONG_DASH, "nor against a fallen opponent")
	expect_equal(by_band.call(OTHER_BAND, 0, 0, 0, 0), AiDecision.MOVE_NONE, "no such band")


func test_the_movement_by_reach_band_changes_kind_at_its_thresholds() -> void:
	var by_reach := AiDecision.movement_by_reach
	expect_equal(by_reach.call(0, 0, 0, true, 0x198), AiDecision.MOVE_BACK_DASH, "bands 0 and 1")
	expect_equal(by_reach.call(1, 0, 0, true, 0x199), AiDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(1, 0, 0, true, 0x333), AiDecision.MOVE_NONE)
	expect_equal(by_reach.call(2, 0, 0, true, 0x27), AiDecision.MOVE_WALK, "band 2")
	expect_equal(by_reach.call(2, 0, 0, true, 0x28), AiDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(2, 0, 0, true, 0x170), AiDecision.MOVE_NONE)
	expect_equal(by_reach.call(3, 0, 0, true, 0x1EA), AiDecision.MOVE_WALK, "band 3")
	expect_equal(by_reach.call(3, 0, 0, true, 0x1EB), AiDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(3, 0, 0, true, 0x214), AiDecision.MOVE_RETREAT)
	expect_equal(by_reach.call(3, 0, 0, true, 0x218), AiDecision.MOVE_DASH)
	expect_equal(by_reach.call(3, 0, 0, true, 0x22D), AiDecision.MOVE_SIDE_STEP, "a standing fighter side steps")
	expect_equal(by_reach.call(3, 0, 0, false, 0x22D), AiDecision.MOVE_NONE, "a crouching one does not")
	expect_equal(by_reach.call(3, 0, 0, true, 0x241), AiDecision.MOVE_NONE)
	expect_equal(by_reach.call(4, 0, 0, true, 0x7F), AiDecision.MOVE_WALK, "band 4")
	expect_equal(by_reach.call(4, 0, 0, true, 0x80), AiDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(4, 0, 0, true, 0x90), AiDecision.MOVE_SIDE_STEP)
	expect_equal(by_reach.call(4, 0, 0, true, 0xC0), AiDecision.MOVE_DASH)
	expect_equal(by_reach.call(4, 0, 0, true, 0x3C0), AiDecision.MOVE_NONE)
	expect_equal(by_reach.call(5, 0, 0, true, 0x50), AiDecision.MOVE_LONG_DASH, "band 5 below 0x51")
	expect_equal(by_reach.call(5, 0, 0, true, 0x51), AiDecision.MOVE_WALK)
	expect_equal(by_reach.call(5, 0, 0, true, 0xCC), AiDecision.MOVE_DASH)
	expect_equal(by_reach.call(5, 0, 0, true, 0x400), AiDecision.MOVE_LONG_WALK)
	expect_equal(by_reach.call(5, 0, 0, true, 0x5EB), AiDecision.MOVE_NONE)
	expect_equal(by_reach.call(5, 0x2D1, 0, true, 0x400), AiDecision.MOVE_LONG_DASH, "after a long far count")
	expect_equal(by_reach.call(OTHER_BAND, 0, 0, true, 0), AiDecision.MOVE_NONE, "no such band")


func test_a_posture_holds_the_guard_of_the_attack_level() -> void:
	var holds := AiDecision.guard_posture_holds
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
