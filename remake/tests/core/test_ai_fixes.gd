extends TestSuite
## The Gameplay fixes of the CPU's move choice and the arcade unlock pace (game-bugs.md #18–#21,
## #23, #29) on small hand-made branch lists: each fix changes the case its entry describes, and
## the game's behaviour stays without it.

const END := MoveSystem.END
const COMMON := MoveSystem.CALL
const DISTANCE := 500
const OPEN_FRAME := 5


## A branch row: command, restriction, condition, parameter, target slot, flags, frames, entry.
static func _row(command: int, target: int, first: int, last: int, condition := 0, parameter := 0, entry := 0) -> PackedInt32Array:
	return PackedInt32Array([command, 0, condition, parameter, target, 0, first, last, entry])


## A CPU on a fight with one bank of moves: `lists[s]` is the branch list of the move in slot s,
## `common` the common rows.
class Bench:
	var fight: FightState
	var ai: CpuOpponent
	var rec: AiRecord
	var moves: Array[MoveRow] = []

	func _init(rules: RuleSet, lists: Array, common: Array[PackedInt32Array]) -> void:
		var tables := FightTables.new()
		tables.common_branches = common
		fight = FightState.new(tables, rules)
		ai = CpuOpponent.new(fight, MoveSystem.new(fight))
		var bank := MotionBank.new()
		for s in lists.size():
			var m := MoveRow.new()
			m.bank = bank
			m.index = s
			m.branches = bank.branches.size()
			for row: PackedInt32Array in lists[s]:
				bank.branches.append(row)
			moves.append(m)
		fight.slots[0] = moves
		rec = ai.records[0]
		rec.slot = 0
		var f := fight.fighters[0]
		f.ai_slot = 0
		f.pose_move = moves[0]
		f.pose_frame = OPEN_FRAME
		f.dist = DISTANCE
		ai.ai_self = f
		ai.ai_opp = fight.fighters[1]


static func _rules(fixed: bool) -> RuleSet:
	return RuleSet.with_gameplay_fixes() if fixed else RuleSet.original()


## #18: the look-ahead into the default continuation tests an ordinary row's condition on the
## list start. The continuation's second row opens at this distance (condition 0x18: distance ≤
## 1,000), its first does not (≤ 100): the game drops the second with the first's condition.
func test_lookahead_condition_row() -> void:
	for fixed: bool in [false, true]:
		var lists := [
			[_row(END, 1, 0, 100)],
			[_row(0x10, 2, 1, 50, 0x18, 100), _row(0x20, 3, 1, 50, 0x18, 1000), _row(END, 0, 0, 0)],
			[_row(END, 0, 0, 0)], [_row(END, 0, 0, 0)],
		]
		var b := Bench.new(_rules(fixed), lists, [])
		b.rec.collected_move = b.moves[0]
		expect_equal(b.ai.collect_candidates(b.rec, false), 1 if fixed else 0, "fixed %s: look-ahead candidates" % fixed)


## #19: the forward walk of AiExecuteCandidate stops at k ≤ 0, so the first of three marked
## candidates is picked for k = 0 and 1 and the last never; fixed, each k picks its own.
func test_candidate_pick() -> void:
	var marks := PackedInt32Array([1, 0, 1, 1])
	var game := PackedInt32Array()
	var fixed := PackedInt32Array()
	var backwards := PackedInt32Array()
	for k in 3:
		game.append(CpuOpponent.marked_pick(marks, 4, k, true, false))
		fixed.append(CpuOpponent.marked_pick(marks, 4, k, true, true))
		backwards.append(CpuOpponent.marked_pick(marks, 4, k, false, false))
	expect_equal(game, PackedInt32Array([0, 0, 2]), "the game's forward picks")
	expect_equal(fixed, PackedInt32Array([0, 2, 3]), "fixed forward picks")
	expect_equal(backwards, PackedInt32Array([3, 2, 0]), "backward picks (uniform in the game too)")
	expect_equal(CpuOpponent.marked_pick(marks, 0, 0, true, true), -1, "no candidates")


## #20: the running move's list ends with a common block. The game reads the continuation from
## the common row after the block (slot 2, which has no row to slot 7); fixed, from the terminator
## (slot 1, whose first frame opens slot 7).
func test_continuation_after_common_block() -> void:
	var common: Array[PackedInt32Array] = [_row(0x30, 5, 50, 60), _row(0x31, 2, 0, 100)]
	for fixed: bool in [false, true]:
		var lists := [
			[_row(COMMON, 0, 0, 0, 0, 0, 1), _row(END, 1, 0, 100)],
			[_row(0x40, 7, 1, 100), _row(END, 0, 0, 0)],
			[_row(END, 0, 0, 0)],
		]
		var b := Bench.new(_rules(fixed), lists, common)
		expect_equal(b.ai.branch_open_to(b.rec, 7), fixed, "fixed %s: a branch to slot 7 in reach" % fixed)


## #21: rushed at close range, the guard pass's count is replaced by the crouch-dash pass's.
func test_defence_count() -> void:
	for fixed: bool in [false, true]:
		var b := Bench.new(_rules(fixed), [[_row(END, 0, 0, 0)]], [])
		var guard := MoveRow.new()
		guard.state = StateWord.GUARD_HIGH
		var dash := MoveRow.new()
		b.ai.cand_target[0] = guard
		b.ai.cand_row[0] = _row(0x50, 0, 0, 0)
		b.ai.cand_target[1] = dash
		b.ai.cand_row[1] = _row(CpuOpponent.CROUCH_DASH, 0, 0, 0)
		b.ai.cand_mark[0] = 0
		b.ai.cand_mark[1] = 0
		b.rec.candidate_count = 2
		b.rec.opp_coming = 1
		b.rec.opp_attack = 0x217
		b.rec.distance_change = -0x50
		b.rec.reach_band = 2
		expect_equal(b.ai.filter_defence(b.rec), 2 if fixed else 1, "fixed %s: marked guard and dash rows" % fixed)


## #23: the repeated-move reaction compares only history slot 0.
func test_damage_history() -> void:
	var a := MoveRow.new()
	var b := MoveRow.new()
	var history: Array[MoveRow] = [a, b, null, null, null, null, null, null]
	expect(AiDecision.learned(history, a, false) and AiDecision.learned(history, a, true), "slot 0 in both")
	expect(not AiDecision.learned(history, b, false), "the game misses slot 1")
	expect(AiDecision.learned(history, b, true), "fixed, slot 1 counts")


## #29: eleven characters cleared, among them five outside 0x83FF: the game counts bit positions
## 0–10 of the mask (10 steps), fixed only the six cleared ones inside it.
func test_unlock_pace() -> void:
	var cleared := 0x3F | (0x1F << 10)
	expect_equal(ProgressRules.unlock_steps(cleared, false), 10, "the game's steps")
	expect_equal(ProgressRules.unlock_steps(cleared, true), 6, "fixed steps")
	expect_equal(ProgressRules.unlock_steps(ProgressRules.ALL_CHARACTERS, false), 11, "all cleared")
	expect_equal(ProgressRules.unlock_steps(ProgressRules.ALL_CHARACTERS, true), 11, "all cleared, fixed")
