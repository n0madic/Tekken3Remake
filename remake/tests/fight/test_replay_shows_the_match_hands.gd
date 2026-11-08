extends TestSuite
## A round's KO replay draws the arcade models' hands as the match had them (issue
## n0madic/Tekken3Remake#23): Ogre's fists stay clenched, where the replay's start rests the live
## hand channels at the costume's shape (open hands). Ogre throws punches, the KO is started by hand
## (as the combat code does on a lethal hit) and the replay is stepped to its end, each frame's
## `FighterHands.shown` compared with the channel values of the match frame it plays.

const DISC_DATA := true
const FRAMES := 300                     ## the replay's ring (ReplayState.FRAMES)
const PUNCH_FROM := 250
const KO_STEP := 500
const MAX_STEPS := 3000


func test_the_replay_draws_the_hands_of_the_match() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.OGRE, Character.PAUL])
	setup.seed = 3
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())
	var ogre := sim.fight.fighters[0]
	var other := sim.fight.fighters[1]
	var match_hands := {}               ## recorded frame → the channel values the match drew there
	var played := 0
	var differing := 0                  ## frames whose live channels are not those of the match
	var fists := 0
	for step in MAX_STEPS:
		var pad := PadState.SQUARE if step >= PUNCH_FROM and (step / 7) % 2 == 0 else 0
		sim.step(PackedInt32Array([pad, 0]))
		var replay := sim.fight.replay
		if step == KO_STEP:
			other.health = 0
			other.ko = 1
			replay.start_ko(ogre)
			sim.fight.ko_started = 1
		if replay.mode == ReplayState.RECORDING:
			match_hands[replay.record] = ogre.hands.current.duplicate()
		elif replay.mode == ReplayState.PLAYING:
			var want: PackedInt32Array = match_hands.get((replay.play >> 1) % FRAMES, PackedInt32Array())
			played += 1
			expect_equal(ogre.hands.shown(), want, "replay frame %d" % played)
			if ogre.hands.current != want:
				differing += 1
			if not want.is_empty() and want[0] >= FighterHands.FIST:
				fists += 1
		elif replay.mode == ReplayState.DONE:
			break
	expect(played > 100, "the replay played (%d frames)" % played)
	expect(fists > 0, "Ogre's fists are clenched in the match")
	expect(differing > 0, "the live channels are not the match's: the replay's own values are what draws them")
