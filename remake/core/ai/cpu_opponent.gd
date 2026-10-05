class_name CpuOpponent
extends RefCounted
## The CPU opponent's shared machinery (ai.md), written from the verified port
## `tools/research/ai_sim.py`: the candidate table filled from the running move's branch list and its
## filters, executing a candidate as pad input, input scripts, the character hooks, and the
## record set-up (AiInitRound, AiReset, AiLoadParams). AiDecision runs AiUpdate on top of it.
##
## As in the game, one candidate table serves every CPU fighter, and `ai_self` / `ai_opp` are
## globals set by the last AiInitRound or AiUpdate (AiReset reads them, not its argument).

const MAX_CANDIDATES := 180
const END := MoveSystem.END
const COMMON := MoveSystem.CALL
const SIDE_STEP := 0xC001
const CROUCH_DASH := 0xC002
## The CPU's pad words are in its own frame (ai.md#per-frame-behaviour).
const PAD_UP := PadState.UP
const PAD_FORWARD := PadState.RIGHT
const PAD_DOWN := PadState.DOWN
const PAD_BACK := PadState.LEFT
const PAD_DOWN_FORWARD := PAD_DOWN | PAD_FORWARD
const PAD_DOWN_BACK := PAD_DOWN | PAD_BACK
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
## Branch conditions answered from the cached situation bits (record +0x64).
const SITUATION_CONDITIONS := [BranchCondition.TURNED_AWAY, BranchCondition.TURNED_SIDE_A,
	BranchCondition.TURNED_SIDE_B, BranchCondition.HIGH_ATTACK_COMING, BranchCondition.FACING_QUADRANT_0]
const SIT_TURNED_AWAY := 1
const SIT_SIDE_A := 2
const SIT_SIDE_B := 4
const SIT_HIGH_COMING := 8
const SIT_FACING := 0x10
const SITUATION_BITS := [SIT_TURNED_AWAY, SIT_SIDE_A, SIT_SIDE_B, SIT_HIGH_COMING, SIT_FACING]
const BANK_HWOARANG_SLOT := 0xDE3
const YOSHIMITSU_STANCE := 0x456
const FORCE_LEVELS := 4              ## Tekken Force's pattern words (0x80023210): levels per group
const FORCE_LEVEL_WORDS := 3
const FORCE_GROUP_WORDS := 15

var fight: FightState
var t: AiTables
var moves: MoveSystem
var records: Array[AiRecord] = []
var ai_self: FighterState:           ## 0x800AFF24: the fighter being driven (in the mode region)
	set(v):
		ai_self = v
		fight.region.put32(ModeRegion.AI_SELF, FighterState.address(v.index))
var ai_opp: FighterState             ## 0x800A8B44: its target
var multi := 0                       ## 0x8009F6A4: team, survival or Tekken Force: odd slots think every other frame
var force_timers := PackedInt32Array([-1, -1, -1, -1])   ## 0x8009F6A8 (Tekken Force)
## The candidate table (0x8009FD20): target move, branch row, mark (−1 unusable, 0, 1 marked).
var cand_target: Array[MoveRow] = []
var cand_row: Array[PackedInt32Array] = []
var cand_mark := PackedInt32Array()


func _init(fight_state: FightState, move_system: MoveSystem) -> void:
	fight = fight_state
	moves = move_system
	t = fight.tables.ai
	for i in 3:
		records.append(AiRecord.new())
	cand_target.resize(MAX_CANDIDATES)
	cand_row.resize(MAX_CANDIDATES)
	cand_mark.resize(MAX_CANDIDATES)


func record(f: FighterState) -> AiRecord:
	return records[f.ai_slot]


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


# ---- branch lists ----------------------------------------------------------------------------

## The move a branch row leads to through the index of AI slot `slot` (record +0x0C).
func slot_move(slot: int, row: PackedInt32Array) -> MoveRow:
	var table: Array = fight.slots[slot]
	var s := row[ROW_TARGET] & 0xFFFF
	return table[s] as MoveRow if s < table.size() else null


## The rows of a branch list with the common blocks (0xC00C) expanded by their count, without
## the terminator.
func list_rows(move: MoveRow) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var list := move.bank.branches
	var i := move.branches
	while list[i][ROW_COMMAND] != END:
		var row := list[i]
		if row[ROW_COMMAND] == COMMON:
			var base := row[ROW_TARGET]
			for k in row[ROW_ENTRY]:
				out.append(fight.tables.common_branches[base + k])
		else:
			out.append(row)
		i += 1
	return out


## The branch-row restriction byte as the AI tests it (values above 0x73 never match).
static func restriction_ok(f: FighterState, opp: FighterState, value: int) -> bool:
	if value == 0:
		return true
	if value < 0x18:
		return f.bank_type == value - 1
	if value < 0x2F:
		return f.bank_type != value - 0x18
	if value < 0x46:
		return opp.bank_type == value - 0x2F
	if value < 0x5D:
		return f.char_id == value - 0x46
	if value > 0x73:
		return false
	return f.char_id != value - 0x5D


## A row's condition with the situation bits standing in for the conditions they cache.
func cond_ok(row: PackedInt32Array, f: FighterState, opp: FighterState, sit: int) -> bool:
	var c := row[ROW_CONDITION]
	if c == BranchCondition.ALWAYS:
		return true
	var k := SITUATION_CONDITIONS.find(c)
	if k >= 0:
		return sit & situation_bit(c) != 0
	return moves.condition(row, f, opp)


static func situation_bit(condition: int) -> int:
	return SITUATION_BITS[SITUATION_CONDITIONS.find(condition)]


## AiCollectCandidates (0x80056A4C): the rows of the running move (record +0x58) open now into
## the table; unless `current_only`, also those opening on frame 1 of the default continuation.
## Returns the count. Two quirks are kept: the look-ahead tests an ordinary row's condition on
## the row after the last common block (or the list start; bug #18, fixed by
## RuleSet.fix_ai_lookahead_row), and the stale-word test of bug #17 never matches.
func collect_candidates(rec: AiRecord, current_only: bool) -> int:
	var f := ai_self
	var opp := ai_opp
	var sit := rec.situation
	var count := 0
	var move := rec.collected_move
	# First walk: the rows open on the current pose frame.
	var list := move.bank.branches
	var i := move.branches
	var stop_list := list
	var stop_i := -1
	while list[i][ROW_COMMAND] != END:
		var r := list[i]
		if r[ROW_COMMAND] == COMMON:
			var base := r[ROW_TARGET]
			var filled := false
			for k in r[ROW_ENTRY]:
				var row := fight.tables.common_branches[base + k]
				if _open_now(row, f, opp) and _cond_ok_lookahead(row, row, false, f, opp, sit):
					if count > MAX_CANDIDATES - 1:
						filled = true
						break
					count = _add(rec, count, row)
			if filled:
				stop_i = i
				break
		elif _open_now(r, f, opp) and _cond_ok_lookahead(r, r, false, f, opp, sit):
			if count > MAX_CANDIDATES - 1:
				stop_i = i
				break
			count = _add(rec, count, r)
		i += 1
	if stop_i < 0:
		stop_list = list
		stop_i = i
	if current_only:
		return count
	var stop := stop_list[stop_i]
	var nxt := slot_move(rec.slot, stop)
	if nxt != null and stop[ROW_FIRST] <= f.pose_frame and f.pose_frame <= stop[ROW_LAST] and nxt != f.pose_move:
		count = _walk_lookahead(rec, nxt, count, f, opp, sit)
	for k in count:
		if cand_target[k].state & StateBit.AI_UNUSABLE:
			cand_mark[k] = -1
	if rec.filter_no_lows:
		rec.candidate_count = Fx.s16(count)
		filter_no_lows(rec)
	return count


func _walk_lookahead(rec: AiRecord, move: MoveRow, count: int, f: FighterState, opp: FighterState, sit: int) -> int:
	var list := move.bank.branches
	var i := move.branches
	var cond_row := list[i]
	while list[i][ROW_COMMAND] != END:
		var r := list[i]
		if r[ROW_COMMAND] == COMMON:
			var base := r[ROW_TARGET]
			for k in r[ROW_ENTRY]:
				var row := fight.tables.common_branches[base + k]
				if _open_lookahead(row, f, opp) and _cond_ok_lookahead(row, row, true, f, opp, sit):
					if count > MAX_CANDIDATES - 1:
						return count
					count = _add(rec, count, row)
			cond_row = fight.tables.common_branches[base + r[ROW_ENTRY]]
		elif _open_lookahead(r, f, opp) and _cond_ok_lookahead(r, r if fight.rules.fix_ai_lookahead_row else cond_row,
				true, f, opp, sit):
			if count > MAX_CANDIDATES - 1:
				return count
			count = _add(rec, count, r)
		i += 1
	return count


func _cond_ok_lookahead(row: PackedInt32Array, cond_row: PackedInt32Array, lookahead: bool,
		f: FighterState, opp: FighterState, sit: int) -> bool:
	var c := row[ROW_CONDITION]
	if c == 0:
		return true
	if c == 0x24 or c == 0x25:
		return sit & situation_bit(c) != 0
	if c == 0x26 or c == 0x30 or c == 0x27:
		return true if lookahead else sit & situation_bit(c) != 0
	return moves.condition(cond_row, f, opp)


func _open_now(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	return row[ROW_FIRST] <= f.pose_frame and f.pose_frame <= row[ROW_LAST] \
		and restriction_ok(f, opp, row[ROW_RESTRICTION])


func _open_lookahead(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	return row[ROW_FIRST] < 2 and f.pose_frame <= row[ROW_LAST] and restriction_ok(f, opp, row[ROW_RESTRICTION])


func _add(rec: AiRecord, count: int, row: PackedInt32Array) -> int:
	var target := slot_move(rec.slot, row)
	if target == null:
		return count
	cand_target[count] = target
	cand_row[count] = row
	cand_mark[count] = 0
	return count + 1


# ---- filters ----------------------------------------------------------------------------------

## The loop every filter shares: marks each unmarked candidate that passes `pred(target, row)`,
## adds the number to the marked count (+0x72) and returns it.
func mark_candidates(rec: AiRecord, pred: Callable) -> int:
	var n := rec.candidate_count
	var marked := 0
	for k in n:
		if cand_mark[k] == 0 and pred.call(cand_target[k], cand_row[k]):
			cand_mark[k] = 1
			marked += 1
	if n > 0:
		rec.marked_count = Fx.s16(rec.marked_count + marked)
	return marked


## The target's reach bits (none: close or middle) against the distance band's mask.
func reach_ok(rec: AiRecord, target: MoveRow) -> bool:
	var w := target.attack_word
	var reach := w & 0xFFFF0000
	if w & HINT_REACH == 0:
		reach |= HINT_CLOSE | HINT_MIDDLE
	return reach & t.band_reach[rec.band] != 0


static func is_attack(m: MoveRow) -> bool:
	return m.active_first != 0 and m.air_first == 0 and m.attack_word & HINT_NEVER == 0 and m.state & StateBit.NOT_AI_ATTACK == 0


static func grounded_or_special(m: MoveRow) -> bool:
	return m.air_first == 0 or m.state & 0x80000 != 0 or m.attack_word & HINT_SPECIAL != 0


func _attack_in_reach(rec: AiRecord, m: MoveRow) -> bool:
	return m.attack_word & HINT_NEVER == 0 and m.state & StateBit.NOT_AI_ATTACK == 0 \
		and (reach_ok(rec, m) or m.state & StateBit.REACH_ANY != 0)


static func damage_of(m: MoveRow) -> int:
	return Fx.s16(m.damage_word)


## FUN_8005758C: side steps (0xC001), state bit 19 moves, and attacks in reach.
func filter_attacks(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, br: PackedInt32Array) -> bool:
		if not grounded_or_special(m):
			return false
		if br[ROW_COMMAND] == SIDE_STEP or m.state & 0x80000:
			return true
		return m.active_first != 0 and _attack_in_reach(rec, m))


## FUN_800576DC: attacks in reach except the attack words 0x412 and 0x706.
func filter_attacks_no_special(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		var a := m.attack_word & 0xFFFF
		return grounded_or_special(m) and m.active_first != 0 and a != AttackWord.HIGH and a != AttackWord.UNBLOCKABLE_2 \
			and _attack_in_reach(rec, m))


## FUN_80057820: damaging ground attacks with startup below 14 frames.
func filter_fast_attacks(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		return damage_of(m) > 0 and m.active_first != 0 and m.air_first == 0 and m.active_first < 14 \
			and _attack_in_reach(rec, m))


## FUN_80057954: attacks in reach whose level suits the opponent's posture (+0x230).
func filter_vs_posture(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		if not is_attack(m) or damage_of(m) < 0 or not reach_ok(rec, m):
			return false
		var g := rec.opp_state
		var a := m.attack_word & 0xFFFF
		if g & StateBit.STANDING:
			return a != AttackWord.HIGH
		if g & StateBit.CROUCHING:
			return a != AttackWord.HIGH and a != AttackWord.LOW
		return not (g & StateBit.DOWN and (a == AttackWord.HIGH or a == AttackWord.MID)))


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


## FUN_80057AC4: attacks in reach whose level hits the opponent's current state.
func filter_punish_level(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		return is_attack(m) and reach_ok(rec, m) and level_vs_state(rec.opp_state, m.attack_word & 0xFFFF))


## FUN_80057C88: as FUN_80057AC4 without the attack word 0x412.
func filter_punish_level_no_high(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		var a := m.attack_word & 0xFFFF
		return a != AttackWord.HIGH and is_attack(m) and reach_ok(rec, m) and level_vs_state(rec.opp_state, a))


## FUN_80057E48: attacks in reach from rows without command bits 5–13 (plain buttons).
func filter_plain_attacks(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, br: PackedInt32Array) -> bool:
		return is_attack(m) and br[ROW_COMMAND] & 0x3FE0 == 0 and damage_of(m) >= 0 and reach_ok(rec, m))


## FUN_80058040: damaging attacks in reach faster than +0x20A (air ones only with state bit 19).
func filter_quick_attacks(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		var s := m.state
		return m.attack_word & HINT_NEVER == 0 and damage_of(m) > 0 and m.active_first != 0 \
			and (m.air_first == 0 or s & 0x80000 != 0) and m.active_first < rec.opp_until \
			and s & 0x20000 == 0 and reach_ok(rec, m))


## FUN_8005817C: the same without the attack word 0x412.
func filter_quick_attacks_no_high(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		var w := m.attack_word
		return w & HINT_NEVER == 0 and damage_of(m) > 0 and m.active_first != 0 \
			and m.active_first < rec.opp_until and w & 0xFFFF != AttackWord.HIGH \
			and m.state & StateBit.NOT_AI_ATTACK == 0 and reach_ok(rec, m))


func mark_command(rec: AiRecord, command: int) -> int:
	return mark_candidates(rec, func(_m: MoveRow, br: PackedInt32Array) -> bool:
		return br[ROW_COMMAND] == command)


## FUN_80058AC0: side steps with probability 32/4096 at band 2 or 1024/4096 at band 3, then
## FUN_8005817C against a standing opponent (+0x230 bit 0), else FUN_80058040.
func filter_side_steps_then_quick(rec: AiRecord) -> int:
	var r := (lcg_next() >> 1) & 0xFFF
	var count := 0
	if (rec.band == 2 and r < 0x20) or (rec.band == 3 and r < 0x400):
		count = mark_command(rec, SIDE_STEP)
	if rec.opp_state & StateBit.CROUCHING:
		return count + filter_quick_attacks_no_high(rec)
	return count + filter_quick_attacks(rec)


static func is_neutral(m: MoveRow) -> bool:
	return m.state & StateBit.CROUCHING == StateBit.CROUCHING and m.active_first == 0


func mark_neutral(rec: AiRecord) -> int:
	return mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		return is_neutral(m))


## FUN_800582A0: guard and evasion candidates against the opponent's attack word (+0x234). The
## last block's count replaces the earlier ones (bug #21; RuleSet.fix_ai_guard_count adds it).
func filter_defence(rec: AiRecord) -> int:
	if rec.distance > 0xB86:
		return 0
	var attack := rec.opp_attack
	if rec.opp_grabs != 0:
		var grabbed := mark_neutral(rec) if attack != AttackWord.MID else 0
		return grabbed + _crouch_dashes_if_closing(rec)
	var count := 0
	if rec.opp_coming != 0:
		match attack:
			AttackWord.MID_2:
				count = _mark_guard(rec, [StateWord.GUARD_HIGH, StateWord.GUARD_LOW], true)
			AttackWord.MID:
				count = _mark_guard(rec, [StateWord.GUARD_HIGH], false)
			AttackWord.LOW:
				count = mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
					return m.state & 0xFFFF == StateWord.GUARD_LOW)
				count += _crouch_dashes_if_closing(rec)
			AttackWord.HIGH:
				var posture := ai_self.state & 0xFFFF
				if posture == StateWord.CROUCH or posture == StateWord.GUARD_LOW:
					count = mark_neutral(rec)
				else:
					count = _mark_guard(rec, [StateWord.GUARD_HIGH], false)
					var r := lcg_next() & 0xFFF
					if r % 50 == 0:
						count += mark_neutral(rec)
					count += _crouch_dashes_if_closing(rec)
			AttackWord.UNBLOCKABLE_2:
				count = mark_neutral(rec)
				count += _crouch_dashes_if_closing(rec)
	if rec.distance_change < -0x46 and rec.reach_band < 3:
		var dashes := mark_command(rec, CROUCH_DASH)
		count = count + dashes if fight.rules.fix_ai_guard_count else dashes
	return count


func _mark_guard(rec: AiRecord, states: Array, low_bit_clear: bool) -> int:
	return mark_candidates(rec, func(m: MoveRow, br: PackedInt32Array) -> bool:
		if br[ROW_COMMAND] == CROUCH_DASH or (low_bit_clear and m.state & StateBit.HUMAN_GUARD):
			return false
		return (m.state & 0xFFFF) in states)


func _crouch_dashes_if_closing(rec: AiRecord) -> int:
	if rec.reach_band < 3:
		return 0
	return mark_command(rec, CROUCH_DASH)


## FUN_800616B4: unmarks candidates with AI hint bit 0 or the low attack word 0x10F.
func filter_no_lows(rec: AiRecord) -> int:
	var removed := 0
	for k in rec.candidate_count:
		var mark := cand_mark[k]
		if mark >= 0:
			var w := cand_target[k].attack_word
			if w & HINT_SAFE or w & 0xFFFF == AttackWord.LOW:
				if mark > 0:
					removed += 1
				cand_mark[k] = -1
	rec.marked_count = Fx.s16(rec.marked_count - removed)
	return removed


## FUN_80057300: a branch of the running move open now leads to a move the AI never chooses
## (such moves are reserved for the hooks).
func hint_never_open(rec: AiRecord) -> bool:
	var f := ai_self
	var opp := ai_opp
	for row in list_rows(f.pose_move):
		if row[ROW_FIRST] <= f.pose_frame and f.pose_frame <= row[ROW_LAST] \
				and restriction_ok(f, opp, row[ROW_RESTRICTION]) and cond_ok(row, f, opp, rec.situation):
			var target := slot_move(rec.slot, row)
			if target != null and target.attack_word & HINT_NEVER:
				return true
	return false


# ---- pad input -------------------------------------------------------------------------------

## AiPadFromStep (0x80061AC4): numpad direction in bits 0–3, buttons in bits 8–11.
func pad_from_step(step: int) -> int:
	var pad := 0x80 if step & 0x100 else 0
	if step & 0x200:
		pad |= 0x10
	if step & 0x400:
		pad |= 0x40
	if step & 0x800:
		pad |= 0x20
	return pad | t.numpad_pads[step & 0xF]


## AiStartScript (0x80061B24): presses the first step now and keeps the rest pending.
func start_script(rec: AiRecord, script: PackedInt32Array) -> void:
	rec.script_steps = script
	rec.script_at = 1 if script.size() > 1 else -1
	rec.pad = pad_from_step(script[0] if not script.is_empty() else 0)


## FUN_8002CFD0: the steps of a motion command's input sequence (empty when it has none).
func input_sequence(command: int) -> PackedInt32Array:
	if command < 0xC00E:
		if command == SIDE_STEP:
			return t.tap_forward
		if command == CROUCH_DASH:
			return t.tap_back
		return PackedInt32Array()
	if command < 0xC7FF:
		if command - 0xC00E < 0x3F:
			return fight.tables.sequences_a[command - 0xC00E].slice(1)
		return PackedInt32Array()
	if command - 0xC7FF < 0x29:
		return fight.tables.sequences_b[command - 0xC7FF].slice(1)
	return PackedInt32Array()


## AiPressCommand (0x80061BA8): a branch command as pad input, remembering the target move
## (+0x5C). Returns the pad word, −1 for a motion script, 0 when the command has no script.
func press_command(rec: AiRecord, command: int, target: MoveRow) -> int:
	command &= 0xFFFF
	var result := 0
	if command & 0xC000 == 0:
		var d := 9
		while d > 0 and t.direction_masks[d] & (command >> 5) & 0x1FF == 0:
			d -= 1
		var buttons := 0
		for k in 4:
			if (command >> k) & 1:
				buttons |= t.button_pads[k]
		rec.pad = (t.direction_pads[d] | buttons) & 0xFFFF
		result = rec.pad
	else:
		var seq := input_sequence(command)
		if seq.is_empty() or command & 0xC000 != 0xC000:
			return 0
		start_script(rec, seq)
		result = -1
	rec.pressed_move = target
	return result


## FUN_80056A30: restarts the approach timers.
static func reset_approach(rec: AiRecord) -> void:
	rec.approach_hold = 0x28
	rec.approach_kind = 0
	rec.approach = 0
	rec.direction_hold = -1


## AiSideStep (0x80061D40). `side` −1 chooses from the heading difference (random when nearly
## straight or reversed) and the fighters' order on screen.
func side_step(rec: AiRecord, side: int) -> void:
	if side == -1:
		var h := ai_self.opp_heading_delta & 0xFFFF
		side = 0
		if ((h - 0x101) & 0xFFFFFFFF) > 0x7EFE:
			side = 1
			if ((h + 0x7FFF) & 0xFFFF) > 0x7EFD:
				side = (fight.rng.next() >> 4) & 1
		if Fx.s16(ai_opp.screen_x) < Fx.s16(ai_self.screen_x):
			side = 1 - side
	start_script(rec, t.side_steps[side])
	reset_approach(rec)


# ---- executing a candidate --------------------------------------------------------------------

## AiAfterAttack (0x80058C40): counts forced "never chosen" moves and, for an attack, sets the
## wait (+0x68) to word 2 plus a random one of words 3–6 and resets the approach timers.
func after_attack(rec: AiRecord, row: PackedInt32Array) -> void:
	var target := slot_move(ai_self.ai_slot, row)
	if target.attack_word & HINT_NEVER:
		rec.throw_steps = Fx.s16(rec.throw_steps + 1)
	if target.active_first == 0:
		return
	var u := lcg_next() & 3
	rec.wait = Fx.s16(rec.word(AiRecord.Param.WAIT) + rec.word(AiRecord.Param.WAIT_EXTRA + u))
	if fight.mode == GameMode.FORCE:
		# Tekken Force: the other enemy holds off, and this one pauses unless already pausing.
		var i := 2 - ai_self.index
		force_timers[i] = t.force_words[rec.force_words]
		if force_timers[2 + i] < 0:
			force_timers[2 + i] = t.force_words[rec.force_words + 1]
	rec.neutral_cooldown = -1
	if rec.air_cooldown > 0:
		rec.air_cooldown = -1
	rec.approach_kind = 0
	rec.approach = 0
	rec.approach_hold = 0x28
	rec.direction_hold = -1


## AiExecuteCandidate (0x80058D6C): picks the k-th marked candidate (k random below +0x72) and
## presses it. On odd frame counts the walk goes forwards and stops at k ≤ 0 (bug #19: the first
## marked candidate is twice as likely, the last never chosen; RuleSet.fix_ai_candidate_pick stops
## at k < 0 as backwards); backwards is uniform. Returns the table index, or −1.
func execute_candidate(rec: AiRecord) -> int:
	var m := rec.marked_count
	if m <= 0:
		return -1
	var k := random_below(m)
	var pick := marked_pick(cand_mark, rec.candidate_count, k, rec.frame_count & 1 != 0, fight.rules.fix_ai_candidate_pick)
	if pick < 0:
		return -1
	press_command(rec, cand_row[pick][ROW_COMMAND], cand_target[pick])
	after_attack(rec, cand_row[pick])
	return pick


## The k-th marked entry of the first `n` marks, walking forwards (stopping at k ≤ 0 as the game
## does, or at k < 0 when `fixed`) or backwards (k < 0); −1 without candidates.
static func marked_pick(marks: PackedInt32Array, n: int, k: int, forward: bool, fixed: bool) -> int:
	if forward:
		if n <= 0:
			return -1
		var last := -1 if fixed else 0
		for i in n:
			if marks[i] > 0:
				k -= 1
				if k <= last:
					return i
		return n - 1
	var i := n - 1
	while i >= 0:
		if marks[i] > 0:
			k -= 1
			if k < 0:
				return i
		i -= 1
	return 0 if n > 0 else n


## FUN_80058ED0: a branch of the running move to `slot` is open now or, failing that, opens on
## frame 1 of the default continuation, which is read from the row after the last walked row
## (bug #20: a common row when the list ends with a common block; RuleSet.fix_ai_continuation
## reads the terminator row, as AiCollectCandidates does).
func branch_open_to(rec: AiRecord, slot: int) -> bool:
	var f := ai_self
	var opp := ai_opp
	slot &= 0xFFFF
	var walked := _walk_to(rec, f.pose_move, slot, false, f, opp)
	if walked[0]:
		return true
	var after: PackedInt32Array = walked[2] if fight.rules.fix_ai_continuation else walked[1]
	var nxt := slot_move(f.ai_slot, after)
	if nxt == null or nxt == f.pose_move or not (after[ROW_FIRST] <= f.pose_frame and f.pose_frame <= after[ROW_LAST]):
		return false
	return _walk_to(rec, nxt, slot, true, f, opp)[0]


## Walks a branch list for an open row to `slot`: [found, the row after the last walked row, and
## when none is found the list's terminator row].
func _walk_to(rec: AiRecord, move: MoveRow, slot: int, first_frame_one: bool, f: FighterState, opp: FighterState) -> Array:
	var list := move.bank.branches
	var i := move.branches
	var after_list := list
	var after_i := i
	while list[i][ROW_COMMAND] != END:
		var r := list[i]
		var base_list := list
		var base := i
		var n := 1
		if r[ROW_COMMAND] == COMMON:
			base_list = fight.tables.common_branches
			base = r[ROW_TARGET]
			n = r[ROW_ENTRY]
		after_list = base_list
		after_i = base
		for k in n:
			var row := base_list[base + k]
			if row[ROW_TARGET] & 0xFFFF == slot and not (first_frame_one and row[ROW_FIRST] != 1) \
					and row[ROW_FIRST] <= f.pose_frame and f.pose_frame <= row[ROW_LAST] \
					and restriction_ok(f, opp, row[ROW_RESTRICTION]) and cond_ok(row, f, opp, rec.situation):
				return [true, after_list[after_i], list[i]]
			after_i = base + k + 1
		i += 1
	return [false, after_list[after_i], list[i]]


# ---- character hooks -------------------------------------------------------------------------
# Hooks return a pad word to hold, −1 (nothing), −2 (input set, for example a script) or −3
# (execute a marked candidate).

## FUN_8005967C: FUN_800616B4 filters this frame's candidates.
static func install_no_lows(rec: AiRecord) -> void:
	rec.filter_no_lows = true


## AiCallHook (0x800594C4): with no script pending (+0x8A < 0) and a draw below word 29, runs the
## hook of the opponent's bank (`own` false) or the CPU's own. True when it produced input.
func call_hook(rec: AiRecord, own: bool) -> bool:
	if rec.move_block >= 0:
		return false
	var x := lcg_next()
	if rec.word(AiRecord.Param.HOOKS) <= x & 0xFFF:
		return false
	var hook := rec.hook_own if own else rec.hook_opponent
	if hook == AiTables.Hook.NONE:
		return false
	var r := _run_hook(rec, hook)
	if r == -2:
		return true
	if r == -3:
		return rec.marked_count > 0 and execute_candidate(rec) >= 0
	if r == -1:
		return false
	if r == PAD_FORWARD or r == PAD_BACK:
		rec.approach = 0x10
		rec.approach_kind = 0
		rec.approach_hold = 0x38
	rec.pad = r & 0xFFFF
	return true


func _run_hook(rec: AiRecord, hook: AiTables.Hook) -> int:
	match hook:
		AiTables.Hook.VS_PAUL:
			return _hook_vs_paul(rec)
		AiTables.Hook.AS_KING:
			return _hook_as_king(rec)
		AiTables.Hook.VS_YOSHIMITSU:
			return _hook_vs_yoshimitsu(rec)
		AiTables.Hook.AS_HWOARANG:
			return _hook_as_hwoarang(rec)
		AiTables.Hook.VS_OGRE:
			return _hook_vs_ogre(rec)
		AiTables.Hook.VS_GON:
			return _hook_vs_gon(rec)
	return -1


func _hook_vs_paul(rec: AiRecord) -> int:
	var opp := ai_opp
	if Fx.s16(opp.cur_slot) == 0x2C7 and rec.reach_band < 3:
		if Fx.s16(opp.pose_frame) > 15:
			return PAD_BACK
		rec.wait = -1
	return -1


func _hook_vs_gon(rec: AiRecord) -> int:
	if Fx.s16(ai_opp.cur_slot) != 0x137:
		return -1
	if rec.reach_band < 2:
		rec.wait = -1
		return -2
	return -1 if rec.reach_band < 4 else PAD_BACK


## Reacts to its own slot 0xDE3, which no bank defines (bug #11).
func _hook_as_hwoarang(rec: AiRecord) -> int:
	var f := ai_self
	if Fx.s16(f.cur_slot) != BANK_HWOARANG_SLOT:
		return -1
	if ((f.pose_frame & 0xFFFF) - 0xD) & 0xFFFFFFFF > 4 or rec.opp_until > 9:
		return -1 if fight.rng.next() & 0xF == 0 else PAD_FORWARD
	return -1


func _hook_vs_yoshimitsu(rec: AiRecord) -> int:
	var f := ai_self
	var opp := ai_opp
	var frame := Fx.s16(opp.pose_frame)
	var move := Fx.s16(opp.cur_slot)
	var band := rec.band
	var closing := rec.reach_band
	var pm := opp.pose_move
	if move == 0x16F:
		if closing < 3:
			rec.wait = -1
		return -1
	if move == YOSHIMITSU_STANCE:
		if closing > 2:
			return PAD_FORWARD
		rec.guard_suspend = 4
		install_no_lows(rec)
		rec.wait = -1
		return -1
	if ((opp.cur_slot & 0xFFFF) - 0x459) & 0xFFFFFFFF > 2:
		if move == 0x472:
			return -1
		if move != 0x16A and move != 0x43A:
			if not move in [0x458, 0x49C, 0x49D, 0x49E]:
				return -1
			if Fx.s16(f.opp_rel_angle) >= FightMath.QUARTER_TURN:
				if band < 2:
					rec.wait = -1
				return -1
			if band < 2:
				rec.wait = 1
				return 0
			if band < 3:
				install_no_lows(rec)
				rec.wait = -1
				return -1
			return PAD_FORWARD
		if pm.active_first == 0 or frame <= pm.active_last:
			if Fx.s16(f.opp_rel_angle) > 0x1000:
				return -1 if closing < 2 else PAD_FORWARD
			if closing > 2 and (rec.distance & 0xFFFFFFFF) < 0xA8D:
				start_script(rec, t.back_dash)
				return -2
			if closing < 2 and rec.opp_until > 10:
				return -1
			if closing < 3 and rec.opp_until > 10:
				side_step(rec, fight.rng.next() & 1)
				return -2
		else:
			rec.wait = -1
		return 0
	# The opponent's slots 0x459–0x45B.
	if band < 1:
		if pm.active_first <= frame and frame <= pm.active_last:
			return 0
		install_no_lows(rec)
		rec.wait = -1
		rec.guard_suspend = 4
		return -2
	var limit := 0
	if ((opp.rel_angle & 0xFFFF) - 0x2000) & 0xFFFFFFFF < 0x4001:
		rec.guard_suspend = 0x14
		if band < 2:
			install_no_lows(rec)
			rec.wait = -1
			return -1
		limit = 1
	else:
		if band < 3:
			if fight.rng.next() & 7:
				return 0
			if rec.own_state & 0x400001:
				return 0
			side_step(rec, -1)
			return -2
		rec.guard_suspend = 10
		limit = 2
	return PAD_FORWARD if band > limit else -1


## Inlined in the hook against Ogre: a side from the heading unless the CPU's own move has state
## bit 22, the fighters are 7,001+ apart or the heading is ambiguous; side-steps at once.
func _ogre_side(rec: AiRecord) -> int:
	var f := ai_self
	if f.pose_move.state & 0x400000 or (rec.distance & 0xFFFFFFFF) >= 0x1B59:
		return -1
	var h := f.opp_heading_delta & 0xFFFF
	var side := 0
	if ((h - 0x101) & 0xFFFFFFFF) < 0x7EFF:
		side = 0
	elif ((h + 0x7FFF) & 0xFFFF) < 0x7EFE:
		side = 1
	else:
		return -1
	if Fx.s16(ai_opp.screen_x) < Fx.s16(f.screen_x):
		side = 1 - side
	side_step(rec, side)
	return side


## Against Ogre's fire breath (slot 0x16E); the 0xDE4 branch is dead (bug #11).
func _hook_vs_ogre(rec: AiRecord) -> int:
	var f := ai_self
	var opp := ai_opp
	var pm := opp.pose_move
	var frame := Fx.s16(opp.pose_frame)
	var band := rec.band
	var move := Fx.s16(opp.cur_slot)
	if move == 0xDE4:
		rec.guard_suspend = 8
		if ((frame - 9) & 0xFFFFFFFF) < 5 and band < 2 and fight.rng.next() & 0x1F == 0:
			install_no_lows(rec)
			rec.wait = -1
			return PAD_FORWARD
		if frame < pm.active_first - 0x1E:
			if band <= 1:
				rec.wait = -1
				return PAD_FORWARD
			if band < 3:
				rec.wait = Fx.s16(rec.wait - 4)
				return PAD_FORWARD
			var side := _ogre_side(rec)
			return PAD_FORWARD if side == -1 else _step_again(rec, side)
		if frame < pm.active_first - 0x14:
			if Fx.s16(f.rel_angle) > 0x37FF:
				if band < 3:
					return PAD_FORWARD
				var side2 := _ogre_side(rec)
				return PAD_FORWARD if side2 == -1 else _step_again(rec, side2)
			if band < 3:
				return 0
			if band < 4:
				return PAD_FORWARD
		elif frame < pm.active_last:
			if Fx.s16(f.rel_angle) > 0x5FFF:
				rec.wait = 8
				return PAD_BACK
			if Fx.s16(f.rel_angle) > 0x37FF:
				if band > 1:
					return PAD_FORWARD
				rec.wait = 8
				return 0
			var side3 := _ogre_side(rec)
			if side3 != -1:
				return _step_again(rec, side3)
			return PAD_FORWARD if f.facing_quadrant == 0 else 0
		elif frame < pm.active_last + 0x28:
			if band < 2:
				rec.wait = -1
				return PAD_FORWARD
		elif band < 3:
			rec.wait = -1
			return PAD_FORWARD
	elif move == 0x16E:
		rec.guard_suspend = 8
		if frame < pm.active_first - 8:
			var side := -1
			if ((f.heading_delta & 0xFFFF) + 0x2000) & 0xFFFF < 0x4001 \
					and f.pose_move.state & 0x400000 == 0 and (rec.distance & 0xFFFFFFFF) < 0x1B59:
				side = 1 if Fx.s16(f.screen_x) < Fx.s16(opp.screen_x) else 0
			if band < 1:
				rec.wait = -1
				return PAD_FORWARD
			if band < 3:
				return PAD_FORWARD
			if fight.rng.next() & 7 == 0 and f.facing_quadrant == 0 and side != -1:
				return _step_again(rec, side)
		else:
			if pm.active_last <= frame:
				return -1
			if f.facing_quadrant == 0:
				return PAD_DOWN_FORWARD if rec.distance < 0x1B59 else 0
			if band < 2:
				return t.ogre_escapes[fight.rng.next() & 3]
			if band < 3:
				return PAD_DOWN_FORWARD
	else:
		return -1
	return PAD_FORWARD if fight.rng.next() & 7 == 0 else 0


## A chosen side step is started again (the second call repeats the first).
func _step_again(rec: AiRecord, side: int) -> int:
	side_step(rec, side)
	return -2


## King's command throws (slot 0x15 open) and the scripts against crouching or downed opponents.
func _hook_as_king(rec: AiRecord) -> int:
	var f := ai_self
	var opp := ai_opp
	var u := lcg_next() & 0xFFF
	if rec.wait > 0 or u >= rec.word(AiRecord.Param.THROW_LIST):
		return -1
	var band := rec.band
	var own := f.pose_move
	if opp.bank_type != BankType.GON and rec.opp_state & StateBit.STANDING and band < 3 \
			and opp.in_air == 0 and opp.about_to_hit == 0 and own.active_first == 0 \
			and rec.opp_until > 8 and f.facing_quadrant == 0 and f.opp_quadrant == 0 \
			and fight.rng.next() & 7 == 0 and branch_open_to(rec, 0x15):
		start_script(rec, t.king_throws[(fight.rng.next() & 0xFFF) % 3])
		rec.planned_on = 1
		return -2
	var scripts: Array[PackedInt32Array]
	if rec.opp_state & StateBit.CROUCHING and band <= 1 and opp.about_to_hit == 0 and own.active_first == 0 \
			and rec.opp_until >= 9 and f.facing_quadrant == 0 and f.opp_quadrant == 0 \
			and hint_never_open(rec):
		scripts = t.king_vs_crouch
	else:
		if rec.opp_down == 0 or band > 1 or not (f.opp_quadrant == 0 or f.opp_quadrant == 2) \
				or f.facing_quadrant != 0 or opp.about_to_hit != 0 or own.active_first != 0 \
				or rec.opp_until < 9 or rec.vs_stance != 0 or not hint_never_open(rec):
			return -1
		scripts = t.king_ground
	start_script(rec, scripts[fight.rng.next() & 1])
	return -2


# ---- reset and parameters ---------------------------------------------------------------------

## AiLoadParams (0x80061770).
func load_params(rec: AiRecord, group: int, level: int, disabled: int) -> void:
	if group < 1:
		group = fight.ai_difficulty & 0xFFFF
	if level < 1:
		level = fight.ai_level & 0xFF
	rec.input_mode = disabled & 0xFFFF
	if fight.attract != 0:
		level = 4
	rec.params = t.words(group, level).duplicate()
	rec.own_bands = t.band_thresholds[ai_self.char_id].duplicate()
	rec.opp_bands = t.band_thresholds[ai_opp.char_id].duplicate()
	rec.attack_limit = maxi(rec.word(AiRecord.Param.ATTACKS_B), rec.word(AiRecord.Param.ATTACKS_A))
	if fight.mode == GameMode.FORCE:
		# Three words per level (up to 3), fifteen per group: the other enemy's hold after an
		# attack, this enemy's pause, and the chance of attacking while not the player's target.
		var g := mini(group & 0xFFFFFFFF, 2)
		var l := mini(mini(level & 0xFFFFFFFF, 9), FORCE_LEVELS - 1)
		rec.force_words = FORCE_GROUP_WORDS * g + FORCE_LEVEL_WORDS * l


## AiReset (0x800596B0) for `f`'s record. The hooks, the band tables and the health come from
## the `ai_self` / `ai_opp` globals, not from `f`.
func reset(f: FighterState, group: int, level: int, disabled: int) -> void:
	var rec := records[f.ai_slot]
	var me := ai_self
	var opp := ai_opp
	rec.pose_frame_seen = -1
	rec.neutral_action = 0
	rec.crouching = 0
	rec.crouch_timer = -1
	rec.crouch_attack_hold = 0
	rec.move_block = -1
	rec.direction_hold = -1
	rec.approach = -1
	rec.approach_kind = 0
	rec.collected_move = null
	rec.throw_move = null
	rec.whiff_timer = -1
	rec.guarding = 0
	rec.air_cooldown = -1
	rec.neutral_cooldown = -1
	rec.move_frame_seen = -1
	rec.move_frames = 0
	rec.far_count = 0
	rec.setup_cooldown = -1
	rec.last_attack = null
	rec.guard_suspend = -1
	rec.reload_timer = -1
	rec.guard_delay = -1
	rec.guard_holds = 0
	rec.marked_count = 0
	rec.candidate_count = 0
	rec.strings_on = 0
	rec.strings_count = 0
	rec.health_seen = me.health
	rec.no_strings = 0
	rec.planned_on = 0
	rec.planned_count = 0
	rec.link_skip = 0
	rec.links_on = 0
	rec.links_count = 0
	rec.attacks_in_row = 0
	rec.throw_steps = 0
	rec.throw_list = 0
	rec.throw_press_frame = -1
	rec.throw_row = PackedInt32Array()
	rec.cancel_wait = 0
	rec.script_at = -1
	rec.opp_string = -1
	rec.history_at = 0
	for k in AiRecord.HISTORY:
		rec.history[k] = null
	rec.punish = 0
	rec.parried = 0
	rec.throw_chance = 0
	rec.throw_next = 0
	rec.evade_reason = 0
	rec.guard_memory = 0
	rec.evasion = 0
	load_params(rec, group, level, disabled)
	rec.hook_opponent = t.hook(opp.bank_type, false)
	rec.hook_own = t.hook(me.bank_type, true)
	if fight.attract != 0:
		for w: int in range(AiRecord.Param.WAIT_EXTRA, AiRecord.Param.WAIT_EXTRA + 4):
			rec.params[w] = Fx.div_trunc(rec.params[w], 2)
		rec.params[AiRecord.Param.GUARD] = Fx.div_trunc(rec.params[AiRecord.Param.GUARD], 4)
	rec.wait = rec.word(AiRecord.Param.WAIT_EXTRA)
	var r := fight.rng.next()
	var u := (r + lcg_next()) & 0x7FFF
	rec.approach_hold = ((u * 30) >> 15) + 30
	for k in MAX_CANDIDATES:
		cand_mark[k] = -1


## AiInitRound (0x8005993C): the AI slots and targets of the fighters, each record reset. Tekken
## Force gives its two enemy records the AI slots 0 and 1, both after the player.
func init_round() -> void:
	multi = 1 if fight.attract != 0 or fight.mode == GameMode.FORCE else 0
	for k in 4:
		force_timers[k] = -1
	var slots: Array[int] = [0, 1, -1]
	var targets: Array[int] = [1, 0, -1]
	if fight.mode == GameMode.FORCE:
		if fight.human_mask == 1:
			slots = [-1, 0, 1]
			targets = [-1, 0, 0]
		elif fight.human_mask == 2:
			slots = [0, -1, 1]
			targets = [1, -1, 1]
		else:
			return
	for f in fight.fighters:
		var i := f.index
		f.ai_slot = slots[i]
		f.ai_target = targets[i]
		if slots[i] < 0:
			continue
		var rec := records[slots[i]]
		rec.frame_count = slots[i]
		rec.slot = slots[i]
		var opp := fight.fighters[targets[i]]
		ai_opp = opp
		rec.target = opp
		ai_self = f
		rec.prev_pad = 0
		rec.pad = 0
		reset(f, -1, -1, -1)
