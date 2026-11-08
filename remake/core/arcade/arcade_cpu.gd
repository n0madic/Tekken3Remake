class_name ArcadeCpu
extends CpuMachinery
## The arcade's CPU opponent: the round's reset (FUN_801C3178) and what the decision steps
## (`ArcadeAiDecision`) share in the family 0x801C2F6C–0x801CEA0C: the draws, branch lists, the
## candidate table and its filters, presses and scripts, and the character hooks.
##
## The same design as the PlayStation's `CpuOpponent` on an older build with its own record, so the
## two share only what `CpuMachinery` holds. Addresses are the arcade's.

const RECORDS := 2
const LEVELS := 10
const DIFFICULTIES := 5
const REGION_GROUPS := 2
const OUT_OF_RANGE_DIFFICULTY := 1      ## FUN_801C2FCC falls back to group 0, this difficulty and level
const OUT_OF_RANGE_LEVEL := 6
const ATTRACT_LEVEL := 4
const DRAW_MASK := 0xFFF                ## word draws: chances out of 4096
const ROW_ADDRESSES := 0x80025E8C       ## the game address of a move row (kept by the hit history)
const ROW_BYTES := 0x3C
const LONG_APPROACH_HOLD := 0x3C
const FIRST_WAIT := 0x3C
const FIRST_HOLD := 0x32

# Panel bits (FUN_8018E220).
const UP := 0x2000
const DOWN := 0x1000
const BACK := 0x800
const FORWARD := 0x400
const DOWN_FORWARD := DOWN | FORWARD
const DOWN_BACK := DOWN | BACK
const LP := 0x200
const RP := 0x100
const LK := 0x40
const RK := 0x20

const SEQUENCES_B_FIRST := 0xC7FF
const ATTRACT_BANK := 4                 ## the demonstration keeps this bank's slot out of the lists
const BANK_PAUL := 0
const BANK_YOSHIMITSU := 4
const BANK_THIRTEEN := 13
const BANK_OGRE := 14
# Slots the branch-list walks treat specially (FUN_801C560C and its copies).
const SLOT_NEVER := 0x3B5
const SLOT_RARE_FOR_PAUL := 0x2E2
const SLOT_NOT_IN_ATTRACT := 0xB68
const SLOTS_RARE_FOR_PAUL_AND_13: Array[int] = [0xE13, 0xE21]
const SLOTS_BARRED_FOR_PAUL_AND_13: Array[int] = [0xE14, 0xE23]
const SLOT_USUAL_FOR_YOSHIMITSU := 0xE30
const RARE_BITS := 0x70
# The reaction slots of the bank counter predicates (0x8017A5A4, 0x8017A5B4).
const COUNTER_SLOTS: Array[int] = [0x1DA, 0x6DE]
const COUNTER_SLOT_B := 0x21B
const STANCE_CONDITION := 0x35          ## the first row of a move for a stance
const STANCE_FLAGS: Array[int] = [0x1C, 0x1D]
const STANCE_ESCAPE_FLAGS := 0x1E
const THROW_ESCAPE_ROWS := 16
const THROW_ROWS := 6
const KING_THROW_SLOT := 8
const FAR_DISTANCE := 0xB86             ## beyond it nothing that comes reaches the CPU
const REACH_ROWS := 0xFFFF0000
const REACH_DEFAULT := HINT_CLOSE | HINT_MIDDLE
# State bits of a move row the code names only by number (StateBit's doc).
const STATE_BIT19 := 0x80000
const STATE_BIT21 := 0x200000
const QUICK_ATTACK := 0xC               ## FUN_801C689C: active before this frame
const WALK_COMMANDS := 0x3FE0
const DIRECTION_COMMANDS := 0xFFE0
const MOTION_COMMANDS := 0xC200
const NO_MOTION := 0x200

var arcade_records: Array[ArcadeAiRecord] = []
var r: ArcadeAiRecord                   ## 0x8021FB84
var me: FighterState                    ## 0x8021FDAC
var opp: FighterState                   ## 0x8021FAE0
var region_word := 0                    ## 0x8021FB74
var cand_index := PackedInt32Array()    ## the candidates' branch rows by index
var last_step := -1                     ## 0x8021F394: the chain's step that gave the last input
var _collected := 0
var _skip_last := false


func _init(fight_state: FightState, move_system: MoveSystem) -> void:
	super(fight_state, move_system)
	step_buttons = PackedInt32Array([LP, RP, LK, RK])
	for i in RECORDS:
		arcade_records.append(ArcadeAiRecord.new())
	cand_index.resize(MAX_CANDIDATES)


## FUN_801C3634: the record and the fighters of a CPU.
func select(slot: int) -> void:
	r = arcade_records[slot]
	me = fight.fighters[slot]
	opp = fight.fighters[1 - slot]


# ---- the round's reset ------------------------------------------------------------------------

## FUN_801C3158 / FUN_801C3178. Some fields carry over between rounds as they do in the game.
func init_round() -> void:
	for i in RECORDS:
		_reset_record(i)


func _reset_record(i: int) -> void:
	select(i)
	r.slot = i
	r.frame_count = i
	r.prev_pad = 0
	r.pad = 0
	r.pose_frame_seen = -1
	r.neutral_action = 0
	r.crouching = 0
	r.crouch_timer = -1
	r.crouch_attack_hold = 0
	r.move_block = -1
	r.direction_hold = -1
	r.approach = -1
	r.approach_kind = 0
	r.continuation = null
	r.collected_move = null
	r.throw_move = null
	r.whiff_timer = -1
	r.guarding = 0
	r.air_cooldown = -1
	r.neutral_cooldown = -1
	r.move_frame_seen = -1
	r.move_frames = 0
	r.far_count = 0
	r.setup_cooldown = -1
	r.last_attack = null
	r.wobble = 0
	r.wobble_phase = 0
	r.guard_suspend = -1
	r.neutral_frames = 0
	r.neutral_block = -1
	r.health_seen = me.health
	r.neutral_actions = 0
	r.guard_delay = -1
	r.guard_holds = 0
	r.marked_count = 0
	r.candidate_count = 0
	r.strings_on = 0
	r.strings.clear()
	r.no_strings = 0
	r.planned.clear()
	r.link_skip = 0
	r.links_on = 0
	r.links.clear()
	r.attacks_in_row = 0
	r.throw_steps = 0
	r.throw_list = 0
	r.throw_press_frame = -1
	r.throw_row = -1
	r.clear_script()
	r.cancel_wait = 0
	r.opp_string = -1
	r.opp_joint_y = 0
	r.history.fill(0)
	r.punish = 0
	r.parried = 0
	r.throw_chance = 0
	r.throw_next = 0
	r.evade_reason = 0
	r.guard_memory = 0
	r.evasion = 0
	_load_params()
	r.own_bands = t.band_thresholds[me.char_id].duplicate()
	r.opp_bands = t.band_thresholds[opp.char_id].duplicate()
	r.hook_opponent = t.hook(opp.bank_type, false)
	r.hook_own = t.hook(me.bank_type, true)
	if fight.attract != 0:
		for k in 4:
			r.params[ArcadeAiRecord.Param.WAIT_EXTRA + k] = r.params[ArcadeAiRecord.Param.WAIT_EXTRA + k] / 2
		r.params[ArcadeAiRecord.Param.GUARD] = r.params[ArcadeAiRecord.Param.GUARD] / 4
	r.wait = r.word(ArcadeAiRecord.Param.WAIT_EXTRA) * random_below(0x80) / 0x100 + FIRST_WAIT
	r.approach_hold = random_below(0x30) + FIRST_HOLD
	cand_mark.fill(-1)


## FUN_801C2FCC.
func _load_params() -> void:
	var group := 0 if region_word == 0 or region_word == 1 else 1
	var difficulty := fight.ai_difficulty
	var level := ATTRACT_LEVEL if fight.attract != 0 else mini(fight.ai_level, LEVELS)
	if group >= REGION_GROUPS or difficulty >= DIFFICULTIES or level >= LEVELS:
		group = 0
		difficulty = OUT_OF_RANGE_DIFFICULTY
		level = OUT_OF_RANGE_LEVEL
	var levels: Array = t.params[group * DIFFICULTIES + difficulty]
	var words: PackedInt32Array = levels[level]
	r.params = words.duplicate()
	r.attack_limit = maxi(r.word(ArcadeAiRecord.Param.ATTACKS_B), r.word(ArcadeAiRecord.Param.ATTACKS_A))


# ---- draws, moves and rows --------------------------------------------------------------------

## `rand() & 0xFFF`, the draw most choices compare with a word.
func draw() -> int:
	return fight.rng.next() & DRAW_MASK


## The move a slot leads to in the fighter's table (FUN_8018ED00).
func slot_row(slot: int) -> MoveRow:
	var table: Array = fight.slots[me.index]
	return table[slot] as MoveRow


## The game address of a move, as the hit history keeps it (0 for none).
static func row_address(m: MoveRow) -> int:
	return 0 if m == null else ROW_ADDRESSES + ROW_BYTES * m.index


## A branch row's restriction as the AI reads it: 0 any, else the fighter's bank.
func restriction_passes(value: int) -> bool:
	if value == 0:
		return true
	if value < 0x18:
		return me.bank_type == value - 1
	if value < 0x2F:
		return me.bank_type == value - 0x18
	return false


## The slots no walk takes as they stand; some draw on `rand`.
func slot_allowed(slot: int) -> bool:
	var bank := me.bank_type
	if slot == SLOT_NEVER:
		return false
	if slot == SLOT_RARE_FOR_PAUL:
		return bank != BANK_PAUL or fight.rng.next() & RARE_BITS == 0
	if slot == SLOT_NOT_IN_ATTRACT:
		return not (fight.attract != 0 and bank == ATTRACT_BANK)
	if slot in SLOTS_RARE_FOR_PAUL_AND_13:
		return (bank != BANK_PAUL and bank != BANK_THIRTEEN) or fight.rng.next() & RARE_BITS == 0
	if slot in SLOTS_BARRED_FOR_PAUL_AND_13:
		return bank != BANK_PAUL and bank != BANK_THIRTEEN
	if slot == SLOT_USUAL_FOR_YOSHIMITSU:
		return bank != BANK_YOSHIMITSU or fight.rng.next() & RARE_BITS != 0
	return true


## A branch row the fighter could take whatever the frame: restriction, slot, condition.
func row_usable(row: PackedInt32Array) -> bool:
	return restriction_passes(row[ROW_RESTRICTION]) and slot_allowed(row[ROW_TARGET]) \
		and moves.condition(row, me, opp)


## The same on the frame of the fighter's pose.
func row_open(row: PackedInt32Array) -> bool:
	return row[ROW_FIRST] <= me.pose_frame and me.pose_frame <= row[ROW_LAST] and row_usable(row)


## The open rows among `indices` (branch rows of the fighter's bank).
func open_rows(indices: PackedInt32Array) -> PackedInt32Array:
	var rows := me.pose_move.bank.branches
	var out := PackedInt32Array()
	for i in indices:
		if row_open(rows[i]):
			out.append(i)
	return out


## FUN_801C4108: the command of a random open row of the pose's list, 0 for none.
func throw_escape_command() -> int:
	var rows := me.pose_move.bank.branches
	var open := PackedInt32Array()
	var i := me.pose_move.branches
	while rows[i][ROW_COMMAND] != END and open.size() < THROW_ESCAPE_ROWS:
		if row_open(rows[i]):
			open.append(i)
		i += 1
	if open.is_empty():
		return 0
	return rows[open[random_below(open.size())]][ROW_COMMAND]


## FUN_801C43D4: the usable rows of the pose's list, at most THROW_ROWS.
func throw_step_rows() -> PackedInt32Array:
	var rows := me.pose_move.bank.branches
	var out := PackedInt32Array()
	var i := me.pose_move.branches
	while rows[i][ROW_COMMAND] != END:
		if row_usable(rows[i]):
			out.append(i)
			if out.size() >= THROW_ROWS:
				break
		i += 1
	return out


## FUN_801C5FE4: an open row of the pose's list leads to a grab.
func grab_open() -> bool:
	var rows := me.pose_move.bank.branches
	var i := me.pose_move.branches
	while rows[i][ROW_COMMAND] != END:
		if row_open(rows[i]) and slot_row(rows[i][ROW_TARGET]).attack_word & HINT_NEVER != 0:
			return true
		i += 1
	return false


## FUN_801C832C: a branch into `slot` is open, in the pose's list or the entry rows of the move its
## list ends in.
func branch_open(slot: int) -> bool:
	var rows := me.pose_move.bank.branches
	var i := me.pose_move.branches
	while rows[i][ROW_COMMAND] != END:
		if rows[i][ROW_TARGET] == slot and row_open(rows[i]):
			return true
		i += 1
	var end_row := rows[i]
	var next := slot_row(end_row[ROW_TARGET])
	if next == me.pose_move or end_row[ROW_FIRST] > me.pose_frame or me.pose_frame > end_row[ROW_LAST]:
		return false
	i = next.branches
	while rows[i][ROW_COMMAND] != END:
		var row := rows[i]
		if row[ROW_TARGET] == slot and row[ROW_FIRST] == 1 and me.pose_frame > 0 and me.pose_frame <= row[ROW_LAST] \
				and row_usable(row):
			return true
		i += 1
	return false


## FUN_801C88A0: a row of the pose's list has this condition.
func pose_has_condition(condition: int) -> bool:
	var rows := me.pose_move.bank.branches
	var i := me.pose_move.branches
	while rows[i][ROW_COMMAND] != END:
		if rows[i][ROW_CONDITION] == condition:
			return true
		i += 1
	return false


# ---- the candidate table ----------------------------------------------------------------------

## FUN_801C5CB8: the candidates of the collected move's list that are open now.
func collect_current() -> int:
	_begin_collecting(false)
	var move := r.collected_move
	var rows := move.bank.branches
	var i := move.branches
	while rows[i][ROW_COMMAND] != END:
		if row_open(rows[i]) and not _add_candidate(rows, i):
			break
		i += 1
	return _collected


## FUN_801C560C: the same plus the entry rows of the move the list ends in, skipping (7 times in 8)
## one candidate that leads to the last attack.
func collect_all() -> int:
	_begin_collecting(fight.rng.next() & 7 != 0 or fight.attract != 0)
	var move := r.collected_move
	var rows := move.bank.branches
	var i := move.branches
	while rows[i][ROW_COMMAND] != END:
		if row_open(rows[i]) and not _add_candidate(rows, i):
			break
		i += 1
	var end_row := rows[i]
	r.continuation = slot_row(end_row[ROW_TARGET])
	if end_row[ROW_FIRST] <= me.pose_frame and me.pose_frame <= end_row[ROW_LAST] and r.continuation != me.pose_move:
		i = r.continuation.branches
		while rows[i][ROW_COMMAND] != END:
			if rows[i][ROW_FIRST] < 2 and row_open(rows[i]) and not _add_candidate(rows, i):
				break
			i += 1
	if r.filter_no_lows:
		r.candidate_count = _collected
		_collected -= unmark(p_low)
	return _collected


func _begin_collecting(skip_last: bool) -> void:
	_collected = 0
	_skip_last = skip_last


## The candidate of an open row; false when the table is full.
func _add_candidate(rows: Array[PackedInt32Array], i: int) -> bool:
	if _collected >= MAX_CANDIDATES:
		return false
	var target := slot_row(rows[i][ROW_TARGET])
	if target.state & StateBit.AI_UNUSABLE != 0:
		return true
	if _skip_last and target == r.last_attack:
		_skip_last = false
		return true
	cand_target[_collected] = target
	cand_row[_collected] = rows[i]
	cand_index[_collected] = i
	cand_mark[_collected] = 0
	_collected += 1
	return true


## FUN_801C64D4: marks the unmarked candidates a filter takes; returns how many.
func mark(pred: Callable) -> int:
	var n := 0
	for i in r.candidate_count:
		if cand_mark[i] == 0 and pred.call(cand_target[i], cand_row[i]) as bool:
			cand_mark[i] = 1
			n += 1
	r.marked_count += n
	return n


## FUN_801C6598: removes the candidates a filter takes; returns how many of them were marked.
func unmark(pred: Callable) -> int:
	var n := 0
	for i in r.candidate_count:
		if cand_mark[i] >= 0 and pred.call(cand_target[i], cand_row[i]) as bool:
			if cand_mark[i] > 0:
				n += 1
			cand_mark[i] = -1
	r.marked_count -= n
	return n


## FUN_801C7A88: the k-th marked candidate, from the end on every other frame count of the other slot.
func _marked_at(k: int) -> int:
	if r.frame_count & 1 == r.slot:
		for i in r.candidate_count:
			if cand_mark[i] > 0:
				k -= 1
				if k < 0:
					return i
		return -1
	for i in range(r.candidate_count - 1, -1, -1):
		if cand_mark[i] > 0:
			k -= 1
			if k < 0:
				return i
	return -1


## FUN_801C7B5C: presses a random marked candidate; returns its index or −1.
func execute() -> int:
	if r.marked_count <= 0:
		return -1
	var i := _marked_at(random_below(r.marked_count))
	if i < 0:
		return -1
	press(cand_row[i][ROW_COMMAND], cand_target[i])
	after_press(cand_row[i])
	return i


# ---- pads and scripts -------------------------------------------------------------------------

## FUN_8018EA28: whether a command has an input sequence, and its steps.
func _has_sequence(command: int) -> bool:
	if command < ArcadeMoveSystem.SEQUENCES_A_FIRST:
		return command == SIDE_STEP or command == CROUCH_DASH
	if command < SEQUENCES_B_FIRST:
		return command - ArcadeMoveSystem.SEQUENCES_A_FIRST < fight.tables.sequences_a.size()
	return command - SEQUENCES_B_FIRST < fight.tables.sequences_b.size()


func _sequence_steps(command: int) -> PackedInt32Array:
	if command == SIDE_STEP:
		return t.tap_forward
	if command == CROUCH_DASH:
		return t.tap_back
	if command < SEQUENCES_B_FIRST:
		return fight.tables.sequences_a[command - ArcadeMoveSystem.SEQUENCES_A_FIRST].slice(1)
	return fight.tables.sequences_b[command - SEQUENCES_B_FIRST].slice(1)


## FUN_801C3F30: a branch command as pad input, remembering the target move (+0x8C). Returns the pad
## word, −1 for a motion script, 0 when the command has none.
func press(command: int, target: MoveRow) -> int:
	command &= 0xFFFF
	var result := -1
	if command & 0xC000 == 0:
		r.pad = command_pad(command)
		result = r.pad
	else:
		if command & 0xC000 != 0xC000 or not _has_sequence(command):
			return 0
		start_script(r, _sequence_steps(command))
	r.pressed_move = target
	return result


## FUN_801C79A8: what pressing a row starts: another throw step, a wait after an attack.
func after_press(row: PackedInt32Array) -> void:
	var target := slot_row(row[ROW_TARGET])
	if target.attack_word & HINT_NEVER != 0:
		r.throw_steps += 1
	if target.active_first != 0:
		var extra := fight.rng.next() & 3
		r.neutral_cooldown = -1
		r.wait = r.word(ArcadeAiRecord.Param.WAIT) + r.word(ArcadeAiRecord.Param.WAIT_EXTRA + extra)
		if r.air_cooldown > 0:
			r.air_cooldown = -1
		reset_approach(r)


## FUN_801C3134.
func set_approach(frames: int) -> void:
	r.approach = frames
	r.approach_kind = 0
	r.approach_hold = frames + APPROACH_HOLD


## FUN_801C3118.
func set_long_approach(frames: int, kind: int) -> void:
	r.approach = frames
	r.approach_kind = kind
	r.approach_hold = frames + LONG_APPROACH_HOLD


## FUN_801CDA04: a side step; SIDE_STEP_AUTO picks the side from the opponent's heading.
func step_aside(side: int) -> void:
	if side == SIDE_STEP_AUTO:
		side = auto_side(opp.heading_delta, opp.screen_x, me.screen_x)
	start_script(r, t.side_steps[side])
	reset_approach(r)


static func _span(value: int, count: int) -> bool:
	return value >= 0 and value < count


## A fighter's facing away from its opponent, as an s16.
func rel_of(f: FighterState) -> int:
	return Fx.s16(f.rel_angle)


# ---- the candidates' filters (0x801C6668–0x801C7558) --------------------------------------------

## FUN_801C62A8, row 0 of the table: the target's reach bits against the distance band.
func in_band(m: MoveRow) -> bool:
	return reach_bits(m) & t.band_reach[r.band] != 0


## The reach bits of a move: without any, close and middle.
static func reach_bits(m: MoveRow) -> int:
	var bits := m.attack_word & REACH_ROWS
	if m.attack_word & HINT_REACH == 0:
		bits |= REACH_DEFAULT
	return bits


## FUN_801C644C: an attack is coming that reaches the CPU, by row `which` of the table.
func coming_reaches(approach_row: bool) -> bool:
	if r.opp_coming == 0 or fight.fighter_distance > FAR_DISTANCE or rel_of(opp) > 0x4FFF or r.guard_holds != 0:
		return false
	var table := t.approach_reach if approach_row else t.band_reach
	return reach_bits(opp.pose_move) & table[r.reach_band] != 0


static func _is_attacky(m: MoveRow) -> bool:
	return m.state & STATE_BIT19 != 0 or m.attack_word & HINT_SPECIAL != 0


static func damage(m: MoveRow) -> int:
	return Fx.s16(m.damage_word)


func p_any(_m: MoveRow, _row: PackedInt32Array) -> bool:
	return true


func p_power(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.flags & MoveFlag.POWER != 0


func p_string_start(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.flags & MoveFlag.BUFFER_INPUT != 0


func _reach_or_any(m: MoveRow) -> bool:
	return in_band(m) or m.state & StateBit.REACH_ANY != 0


## FUN_801C6698.
func p_approach(m: MoveRow, row: PackedInt32Array) -> bool:
	if m.air_first != 0 and not _is_attacky(m):
		return false
	if row[ROW_COMMAND] == SIDE_STEP or m.state & STATE_BIT19 != 0:
		return true
	if m.active_first == 0 or m.attack_word & HINT_NEVER != 0 or m.state & StateBit.NOT_AI_ATTACK != 0:
		return false
	return _reach_or_any(m)


## FUN_801C6784.
func p_attack_no_high(m: MoveRow, _row: PackedInt32Array) -> bool:
	if m.air_first != 0 and not _is_attacky(m):
		return false
	if m.active_first == 0 or m.attack == AttackWord.HIGH or m.attack == AttackWord.UNBLOCKABLE_2:
		return false
	if m.attack_word & HINT_NEVER != 0 or m.state & StateBit.NOT_AI_ATTACK != 0:
		return false
	return _reach_or_any(m)


## FUN_801C6864.
func p_low(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.attack == AttackWord.LOW or m.attack_word & HINT_SAFE != 0


## FUN_801C689C.
func p_fast(m: MoveRow, _row: PackedInt32Array) -> bool:
	return damage(m) > 0 and m.state & StateBit.AI_UNUSABLE == 0 and m.active_first != 0 and m.air_first == 0 \
		and m.attack_word & HINT_NEVER == 0 and m.active_first < QUICK_ATTACK \
		and m.state & StateBit.NOT_AI_ATTACK == 0 and _reach_or_any(m)


## FUN_801C698C.
func p_vs_posture(m: MoveRow, _row: PackedInt32Array) -> bool:
	if m.state & StateBit.NOT_AI_ATTACK != 0 or m.attack_word & HINT_NEVER != 0 or m.active_first == 0 \
			or m.air_first != 0 or damage(m) < 0 or m.state & StateBit.AI_UNUSABLE != 0 or not in_band(m):
		return false
	if r.opp_state & StateBit.STANDING:
		return m.attack != AttackWord.HIGH
	if r.opp_state & StateBit.CROUCHING:
		return m.attack != AttackWord.HIGH and m.attack != AttackWord.LOW
	if r.opp_state & StateBit.DOWN:
		return m.attack != AttackWord.HIGH and m.attack != AttackWord.MID
	return true


## FUN_801C6ABC.
func p_neutral_follow(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.state & STATE_BIT19 != 0 and m.air_first == 0 and m.state & StateBit.NOT_AI_ATTACK == 0


## FUN_801C6AFC.
func p_level(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.active_first != 0 and m.air_first == 0 and m.attack_word & HINT_NEVER == 0 \
		and m.state & StateBit.NOT_AI_ATTACK == 0 and in_band(m) and level_vs_state(r.opp_state, m.attack)


## FUN_801C6BA8.
func p_level_no_high(m: MoveRow, row: PackedInt32Array) -> bool:
	return m.attack != AttackWord.HIGH and p_level(m, row)


## FUN_801C6C60.
func p_plain(m: MoveRow, row: PackedInt32Array) -> bool:
	return m.active_first != 0 and m.state & StateBit.NOT_AI_ATTACK == 0 and damage(m) >= 0 \
		and m.state & StateBit.AI_UNUSABLE == 0 and m.attack_word & HINT_NEVER == 0 and m.air_first == 0 \
		and in_band(m) and row[ROW_COMMAND] & WALK_COMMANDS == 0


## FUN_801C6D30.
func p_side_step(m: MoveRow, row: PackedInt32Array) -> bool:
	if row[ROW_COMMAND] == SIDE_STEP:
		return true
	return m.state & STATE_BIT19 != 0 and m.attack_word & (HINT_NEVER | HINT_SPECIAL) == 0 \
		and m.state & StateBit.NOT_AI_ATTACK == 0


## FUN_801C6E30.
func p_grab_plain(m: MoveRow, row: PackedInt32Array) -> bool:
	return m.attack_word & HINT_NEVER != 0 and row[ROW_COMMAND] & DIRECTION_COMMANDS == 0


## FUN_801C6E6C.
func p_grab(m: MoveRow, row: PackedInt32Array) -> bool:
	return m.attack_word & HINT_NEVER != 0 and row[ROW_COMMAND] & MOTION_COMMANDS != NO_MOTION


## FUN_801C6EE4.
func p_ground_low(m: MoveRow, _row: PackedInt32Array) -> bool:
	return (m.attack_word & HINT_SAFE != 0 or m.attack == AttackWord.LOW_2) and m.attack_word & HINT_NEVER == 0


## FUN_801C6F2C.
func p_ground_any_low(m: MoveRow, _row: PackedInt32Array) -> bool:
	return (m.attack_word & HINT_SAFE != 0 or m.attack == AttackWord.LOW_2 or m.attack == AttackWord.LOW) \
		and m.attack_word & HINT_NEVER == 0


## FUN_801C6F7C.
func p_stance(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.bank.branches[m.branches][ROW_CONDITION] == STANCE_CONDITION and m.attack_word & HINT_NEVER == 0


## FUN_801C6FB4.
func p_counter(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.attack_word & HINT_NEVER == 0 and damage(m) > 0 and m.state & StateBit.AI_UNUSABLE == 0 \
		and m.active_first != 0 and (m.air_first == 0 or m.state & STATE_BIT19 != 0) \
		and m.active_first < r.opp_until and m.state & StateBit.NOT_AI_ATTACK == 0 and in_band(m)


## FUN_801C707C.
func p_counter_no_high(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.attack_word & HINT_NEVER == 0 and damage(m) > 0 and m.state & StateBit.AI_UNUSABLE == 0 \
		and m.active_first != 0 and m.attack != AttackWord.HIGH and m.active_first < r.opp_until \
		and m.state & StateBit.NOT_AI_ATTACK == 0 and in_band(m)


## FUN_801C719C.
func p_crouching_attack(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.active_first != 0 and m.state & StateBit.CROUCHING != 0 and m.state & StateBit.NOT_AI_ATTACK == 0 \
		and in_band(m)


## FUN_801C721C.
func p_guard_high(m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_COMMAND] != CROUCH_DASH and m.state & StateBit.HUMAN_GUARD == 0 \
		and m.state & 0xFFFF == StateWord.GUARD_HIGH


## FUN_801C7260.
func p_guard_low(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.state & StateBit.HUMAN_GUARD == 0 and m.state & 0xFFFF == StateWord.GUARD_LOW


## FUN_801C7290.
func p_crouch(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.state & StateBit.CROUCHING != 0 and m.active_first == 0


## FUN_801C72C0.
func p_safe_still(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.attack_word & HINT_SAFE != 0 and m.air_first == 0 and m.active_first == 0


## FUN_801C7300.
func p_tap_forward(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_COMMAND] == SIDE_STEP


## FUN_801C731C.
func p_tap_back(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_COMMAND] == CROUCH_DASH


## FUN_801C7338.
func p_not_ai_attack(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.state & StateBit.NOT_AI_ATTACK != 0


## FUN_801C7350.
func p_counter_slot(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_TARGET] in COUNTER_SLOTS


## FUN_801C7390.
func p_counter_slot_b(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_TARGET] == COUNTER_SLOT_B


## FUN_801C73CC.
func p_still(m: MoveRow, row: PackedInt32Array) -> bool:
	return m.active_first == 0 and m.air_first == 0 and m.state & StateBit.NOT_AI_ATTACK == 0 \
		and not p_counter_slot(m, row)


## FUN_801C7484.
func p_air_start(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.air_first != 0 and m.state & StateBit.NOT_AI_ATTACK == 0 and _is_attacky(m)


## FUN_801C74E0.
func p_air_attack(m: MoveRow, _row: PackedInt32Array) -> bool:
	return m.active_first != 0 and _is_attacky(m) and m.state & StateBit.NOT_AI_ATTACK == 0


## FUN_801C753C.
func p_stance_row(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_FLAGS] in STANCE_FLAGS


## FUN_801C7558.
func p_stance_escape(_m: MoveRow, row: PackedInt32Array) -> bool:
	return row[ROW_FLAGS] == STANCE_ESCAPE_FLAGS


# ---- the character hooks (0x801CDB78–0x801CE9F4) ------------------------------------------------

## FUN_801CDAC4: the frame's collection leaves out lows.
func no_lows() -> void:
	r.filter_no_lows = true


## The hook's result: a pad word, HOOK_NOTHING or HOOK_ACTED. The arcade's hooks never ask the step
## to execute the marked candidates (FUN_801CD708's −3).
func run_hook(hook: AiTables.Hook) -> int:
	match hook:
		AiTables.Hook.VS_PAUL:
			return _vs_paul()
		AiTables.Hook.VS_YOSHIMITSU:
			return _vs_yoshimitsu()
		AiTables.Hook.VS_OGRE:
			return _vs_ogre()
		AiTables.Hook.AS_KING:
			return _as_king()
		AiTables.Hook.AS_HWOARANG:
			return _as_hwoarang()
	return HOOK_NOTHING


const PAUL_SLOT := 0x2CB


## 0x801CE078.
func _vs_paul() -> int:
	return vs_paul(r, opp, PAUL_SLOT, BACK)


const YOSHI_SLOT_A := 0x157
const YOSHI_SLOT_B := 0x470
const YOSHI_SLOTS_C_FIRST := 0x473
const YOSHI_SLOTS_C_LAST := 0x475
const YOSHI_SLOTS_D: Array[int] = [0x453, 0x152]
const YOSHI_SLOT_E := 0x472
const YOSHI_SLOTS_E_FIRST := 0x4C0
const YOSHI_SLOTS_E_LAST := 0x4C2
const YOSHI_DASH_DISTANCE := 0xA8D


## 0x801CDC98.
func _vs_yoshimitsu() -> int:
	var slot := opp.cur_slot
	if slot == YOSHI_SLOT_A:
		if r.reach_band < 3:
			r.wait = -1
		return HOOK_NOTHING
	if slot == YOSHI_SLOT_B:
		if r.reach_band >= 3:
			return FORWARD
		r.guard_suspend = 4
		return _no_lows_now()
	if slot >= YOSHI_SLOTS_C_FIRST and slot <= YOSHI_SLOTS_C_LAST:
		return _vs_yoshimitsu_c()
	if slot in YOSHI_SLOTS_D:
		return _vs_yoshimitsu_d()
	if slot == YOSHI_SLOT_E or (slot >= YOSHI_SLOTS_E_FIRST and slot <= YOSHI_SLOTS_E_LAST):
		return _vs_yoshimitsu_e()
	return HOOK_NOTHING


func _no_lows_now() -> int:
	no_lows()
	r.wait = -1
	return HOOK_NOTHING


func _vs_yoshimitsu_c() -> int:
	if r.band <= 0:
		var move := opp.pose_move
		if move.active_first <= opp.pose_frame and opp.pose_frame <= move.active_last:
			return 0
		no_lows()
		r.wait = -1
		r.guard_suspend = 4
		return HOOK_ACTED
	if _span((opp.rel_angle & 0xFFFF) - 0x2000, 0x4001):
		r.guard_suspend = 0x14
		return _no_lows_now() if r.band < 2 else FORWARD
	if r.band >= 3:
		r.guard_suspend = 10
		return FORWARD
	if fight.rng.next() & 7 != 0 or r.own_state & (STATE_BIT22 | StateBit.CROUCHING) != 0:
		return 0
	step_aside(SIDE_STEP_AUTO)
	return HOOK_ACTED


func _vs_yoshimitsu_d() -> int:
	var move := opp.pose_move
	if move.active_first != 0 and move.active_last < opp.pose_frame:
		r.wait = -1
		return 0
	if rel_of(opp) > 0x1000:
		return HOOK_NOTHING if r.reach_band < 2 else FORWARD
	if r.reach_band >= 3 and fight.fighter_distance < YOSHI_DASH_DISTANCE:
		start_script(r, t.back_dash)
		return HOOK_ACTED
	if r.opp_until >= 11:
		if r.reach_band < 2:
			return HOOK_NOTHING
		if r.reach_band < 3:
			step_aside(fight.rng.next() & 1)
			return HOOK_ACTED
	return 0


func _vs_yoshimitsu_e() -> int:
	if rel_of(opp) >= 0x4000:
		if r.band < 2:
			r.wait = -1
		return HOOK_NOTHING
	if r.band < 2:
		r.wait = 1
		return 0
	if r.band < 3:
		return _no_lows_now()
	return FORWARD


const OGRE_SLOT_BREATH := 0x904
const OGRE_SLOT_SWEEP := 0x156
const OGRE_WAIT := 8


## 0x801CDBE8: steps aside from Ogre's breath when his heading allows it; the side, −1 for none.
func _ogre_breath_side() -> int:
	var side := ogre_breath_side(me, opp, opp.heading_delta, fight.fighter_distance)
	if side != NO_SIDE:
		step_aside(side)
	return side


func _forward_rarely() -> int:
	return FORWARD if fight.rng.next() & 7 == 0 else 0


func _step_then_acted(side: int) -> int:
	step_aside(side)
	return HOOK_ACTED


## 0x801CE160.
func _vs_ogre() -> int:
	if opp.cur_slot == OGRE_SLOT_SWEEP:
		return _vs_ogre_sweep()
	if opp.cur_slot == OGRE_SLOT_BREATH:
		return _vs_ogre_breath()
	return HOOK_NOTHING


func _vs_ogre_breath() -> int:
	r.guard_suspend = OGRE_WAIT
	var frame := opp.pose_frame
	var move := opp.pose_move
	if _span(frame - 9, 5) and r.band < 2 and fight.rng.next() & 0x1F == 0:
		no_lows()
		r.wait = -1
		return FORWARD
	if frame < move.active_first - 0x1E:
		if r.band < 2:
			r.wait = -1
			return FORWARD
		if r.band < 3:
			r.wait -= 4
			return FORWARD
		var side := _ogre_breath_side()
		return FORWARD if side == NO_SIDE else _step_then_acted(side)
	if frame < move.active_first - 0x14:
		if rel_of(me) >= 0x3800:
			if r.band < 3:
				return FORWARD
			var side := _ogre_breath_side()
			return FORWARD if side == NO_SIDE else _step_then_acted(side)
		if r.band < 3:
			return 0
		return FORWARD if r.band < 4 else _forward_rarely()
	if frame < move.active_last:
		var rel := rel_of(me)
		if rel >= 0x6000:
			r.wait = OGRE_WAIT
			return BACK
		if rel >= 0x3800:
			if r.band < 2:
				r.wait = OGRE_WAIT
				return 0
			return FORWARD
		var side := _ogre_breath_side()
		if side != NO_SIDE:
			return _step_then_acted(side)
		return FORWARD if me.facing_quadrant == 0 else 0
	if frame < move.active_last + 0x28:
		if r.band >= 2:
			return _forward_rarely()
	elif r.band >= 3:
		return _forward_rarely()
	r.wait = -1
	return FORWARD


func _vs_ogre_sweep() -> int:
	r.guard_suspend = OGRE_WAIT
	var frame := opp.pose_frame
	var move := opp.pose_move
	if frame < move.active_first - 8:
		var side := ogre_sweep_side(me, opp, fight.fighter_distance)
		if r.band <= 0:
			r.wait = -1
			return FORWARD
		if r.band < 3:
			return FORWARD
		if fight.rng.next() & 7 != 0 or me.facing_quadrant != 0 or side == NO_SIDE:
			return _forward_rarely()
		return _step_then_acted(side)
	if frame >= move.active_last:
		return HOOK_NOTHING
	if me.facing_quadrant == 0:
		return DOWN_FORWARD if fight.fighter_distance < OGRE_NEAR else 0
	if r.band < 2:
		return t.ogre_escapes[fight.rng.next() & 3]
	return DOWN_FORWARD if r.band < 3 else _forward_rarely()


const KING_SAFE_UNTIL := 9


## 0x801CE618.
func _as_king() -> int:
	var chance := draw()
	if r.wait > 0 or chance >= r.word(ArcadeAiRecord.Param.THROW_LIST):
		return HOOK_NOTHING
	if fight.rng.next() & 7 == 0 and r.opp_state & StateBit.STANDING != 0 and r.band < 3 and opp.in_air == 0 \
			and _king_may_start() and branch_open(KING_THROW_SLOT):
		start_script(r, t.king_throws[draw() % t.king_throws.size()])
		r.planned_on = 1
		return HOOK_ACTED
	if r.opp_state & StateBit.CROUCHING != 0 and r.band < 2 and _king_may_start() and grab_open():
		start_script(r, t.king_vs_crouch[fight.rng.next() & 1])
		return HOOK_ACTED
	if r.opp_down != 0 and r.band < 2 and (opp.facing_quadrant == 0 or opp.facing_quadrant == 2) \
			and me.facing_quadrant == 0 and opp.about_to_hit == 0 and me.pose_move.active_first == 0 \
			and r.opp_until >= KING_SAFE_UNTIL and r.vs_stance == 0 and grab_open():
		start_script(r, t.king_ground[fight.rng.next() & 1])
		return HOOK_ACTED
	return HOOK_NOTHING


func _king_may_start() -> bool:
	return opp.about_to_hit == 0 and me.pose_move.active_first == 0 and r.opp_until >= KING_SAFE_UNTIL \
		and me.facing_quadrant == 0 and opp.facing_quadrant == 0


const HWOARANG_SLOT := 0x827


## 0x801CE984.
func _as_hwoarang() -> int:
	return as_hwoarang(r, me, HWOARANG_SLOT, FORWARD)
