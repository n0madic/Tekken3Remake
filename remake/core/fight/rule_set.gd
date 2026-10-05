class_name RuleSet
extends RefCounted
## Rule flags of the simulation (remake-plan.md#original-bugs): the Gameplay fixes, each named
## after its entry in docs/research/code/game-bugs.md. The Gameplay fixes option sets
## every fix flag at once; the individual flags exist for tests. The text region is not a rule:
## both regions play as Japan Rev.1 and differ only in their texts (GameRam, FlowData).

const FIX_PREFIX := "fix_"

var fix_juggle_arc_overflow := false     ## #7 LaunchTrajectory's wrapped flight time
var fix_elbow_bend_overflow := false     ## #8 IkSolveLimb's 32-bit product
var fix_segment_hit_overflow := false    ## #9 SegmentHitsCylinder's 32-bit products
var fix_tap_latch_register := false      ## #52 LatchButtonTaps stores a stale register
var fix_ai_lookahead_row := false        ## #18 AiCollectCandidates tests the look-ahead condition on the wrong row
var fix_ai_candidate_pick := false       ## #19 AiExecuteCandidate's forward walk stops at k ≤ 0
var fix_ai_continuation := false         ## #20 FUN_80058ED0 reads the continuation after a common block
var fix_ai_guard_count := false          ## #21 FUN_800582A0 returns only its last pass's count
var fix_ai_damage_history := false       ## #23 the repeated-move reaction compares with history slot 0 only
var fix_unlock_pace := false             ## #29 FUN_800B2350 counts bit positions, not the cleared mask
var fix_team_least_used := false         ## #60 team battle's least-used member goes to human teams
var fix_ball_opponent := false           ## #30, #31 Tekken Ball's opponent: least met first, Gon counted
var fix_ball_cpu := false                ## #3, #24 Tekken Ball's CPU: its attack filter and projection
var fix_force_slot_timers := false       ## #41 Tekken Force's 16-bit enemy slot timers


static func original() -> RuleSet:
	return RuleSet.new()


static func with_gameplay_fixes() -> RuleSet:
	var r := RuleSet.new()
	r.set_gameplay_fixes(true)
	return r


## The Gameplay fixes option: every fix flag (the `fix_` variables) on or off.
func set_gameplay_fixes(on: bool) -> void:
	for property: Dictionary in get_property_list():
		var field: String = property["name"]
		if field.begins_with(FIX_PREFIX):
			set(field, on)
