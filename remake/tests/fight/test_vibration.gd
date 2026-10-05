extends TestSuite
## HitVibration (Vibration.hits): the patterns of a frame's hit outcomes on the fighters' pads.


func _fight() -> FightState:
	var fight := FightState.new(null, RuleSet.original())
	for f in fight.fighters:
		f.pose_move = MoveRow.new()
	return fight


func _vibrations(fight: FightState) -> Array[String]:
	var events := SimEvents.new()
	Vibration.hits(fight, events)
	var out: Array[String] = []
	for e in events.items:
		if e.kind == SimEvents.Kind.VIBRATE:
			out.append("%d %d" % [e.a, e.b])
	return out


func test_clean_hit_ko_flags_the_attacker() -> void:
	var fight := _fight()
	var f := fight.fighters[0]
	f.last_attacker = 1
	f.hit_clean = 1
	f.last_damage = 30
	f.ko = 1
	expect_equal(_vibrations(fight), ["0 18", "0 22", "1 6", "1 11"] as Array[String], "heavy hit and KO")


## game-bugs.md #58: a KO without a clean hit or throw damage still vibrates the attacker's pad.
func test_ko_without_a_hit_flags_the_attacker() -> void:
	var fight := _fight()
	var f := fight.fighters[0]
	f.last_attacker = 1
	f.guarded = 1
	f.ko = 1
	expect_equal(_vibrations(fight), ["0 16", "0 22", "1 4", "1 11"] as Array[String], "guard-damage KO")


func test_replay_is_silent() -> void:
	var fight := _fight()
	fight.replay_playing = 1
	fight.fighters[0].ko = 1
	expect_equal(_vibrations(fight).size(), 0, "no vibration during a replay")
