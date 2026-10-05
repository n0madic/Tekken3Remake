class_name AiDecision
extends RefCounted
## AiUpdate (0x80059B78; ai.md#per-frame-behaviour), written from the verified port
## `tools/research/ai_update.py`: the CPU fighter's held and newly pressed pad words for one frame.
## The steps run in the game's order until one produces the frame's input; the bookkeeping at
## the end always runs.

const FORCED_ESCAPES: Array[int] = [0x189, 0x18E, 0x17F, 0x181]

const THROW_ROWS := 48
const DIRECT := 0x7FFFFFFF           ## _choose: execute the marked neutral move directly
const ROW_COMMAND := CpuOpponent.ROW_COMMAND
const ROW_CONDITION := CpuOpponent.ROW_CONDITION
const ROW_TARGET := CpuOpponent.ROW_TARGET
const ROW_FLAGS := CpuOpponent.ROW_FLAGS
const ROW_FIRST := CpuOpponent.ROW_FIRST
const ROW_LAST := CpuOpponent.ROW_LAST
const ROW_ENTRY := CpuOpponent.ROW_ENTRY
const ROW_RESTRICTION := CpuOpponent.ROW_RESTRICTION
const HINT_NEVER := CpuOpponent.HINT_NEVER
const HINT_SAFE := CpuOpponent.HINT_SAFE
const HINT_CLOSE := CpuOpponent.HINT_CLOSE
const HINT_MIDDLE := CpuOpponent.HINT_MIDDLE
const HINT_REACH := CpuOpponent.HINT_REACH
const HINT_SPECIAL := CpuOpponent.HINT_SPECIAL
const GRAB := CpuOpponent.GRAB
const PAD_UP := CpuOpponent.PAD_UP
const PAD_FORWARD := CpuOpponent.PAD_FORWARD
const PAD_DOWN := CpuOpponent.PAD_DOWN
const PAD_BACK := CpuOpponent.PAD_BACK
const PAD_DOWN_FORWARD := CpuOpponent.PAD_DOWN_FORWARD
const PAD_DOWN_BACK := CpuOpponent.PAD_DOWN_BACK

var ai: CpuOpponent
var fight: FightState
var t: AiTables

# The frame's context.
var rec: AiRecord
var f: FighterState
var o: FighterState
var sm: MoveRow
var om: MoveRow
var my_first := 0
var my_last := 0
var my_frame := 0
var op_first := 0
var op_last := 0
var op_frame := 0


func _init(opponent: CpuOpponent) -> void:
	ai = opponent
	fight = ai.fight
	t = ai.t


## AiUpdate for CPU fighter `fighter`: (held pad, newly pressed pad).
func update(fighter: FighterState) -> PackedInt32Array:
	rec = ai.records[fighter.ai_slot]
	f = fighter
	o = rec.target
	ai.ai_opp = o
	ai.ai_self = f
	if fight.mode == GameMode.BALL:
		_ball_project()
	_decide()
	return _finish()


func _decide() -> void:
	_situation()
	if _fixed_input():
		return
	_track()
	if _throws() or _stance():
		return
	if f.move_row != null:
		return
	if _crouch_and_actions():
		return
	if ai.call_hook(rec, false) or ai.call_hook(rec, true):
		return
	if _hold_guard() or _new_move() or _follow_through() or _counter():
		return
	if _react(_reaction_kind()):
		return
	_expire_lists()
	if _avoid_air_attack() or _attack():
		return
	_move()


func _draw(word_index: int) -> bool:
	return ai.lcg_next() & 0xFFF < rec.word(word_index)


# ---- bookkeeping --------------------------------------------------------------------------

func _situation() -> void:
	rec.pressed_move = null
	var frame := Fx.s16(f.pose_frame)
	var prev := rec.pose_frame_seen
	rec.pose_frame_seen = frame
	if frame != prev:
		rec.frame_count = Fx.s16(rec.frame_count + 1)
	var smv := f.pose_move
	var omv := o.pose_move
	rec.own_state = smv.state
	rec.own_word = smv.attack_word
	rec.own_attack = smv.attack
	rec.opp_state = omv.state
	rec.opp_word = omv.attack_word
	rec.opp_attack = omv.attack
	rec.distance = Fx.w32(f.dist)
	var sit := CpuOpponent.SIT_TURNED_AWAY if Fx.s16(f.rel_angle) > FightMath.QUARTER_TURN else 0
	rec.angle = Fx.s16(f.rel_angle)
	var heading := f.heading_delta & 0xFFFF
	if ((heading - 0x4E38) & 0xFFFFFFFF) < 0x31C8:
		sit |= CpuOpponent.SIT_SIDE_A
	if ((heading + FightMath.HALF_TURN) & 0xFFFF) < 0x31C7:
		sit |= CpuOpponent.SIT_SIDE_B
	if Fx.s16(o.attack) == AttackWord.HIGH and Fx.s16(o.pose_frame) <= omv.active_last \
			and (fight.fighter_distance & 0xFFFFFFFF) < MoveSystem.HIGH_ATTACK_RANGE:
		sit |= CpuOpponent.SIT_HIGH_COMING
	if Fx.s16(f.facing_quadrant) == 0:
		sit |= CpuOpponent.SIT_FACING
	rec.opp_gon_special = 0
	rec.opp_breath = 0
	rec.situation = sit
	var first_byte := AttackRecords.header(omv, fight.tables)[0]
	if o.bank_type == BankType.OGRE and first_byte == 0x18:
		rec.opp_breath = 1
	elif o.bank_type == BankType.GON and first_byte == 0x1A:
		rec.opp_gon_special = 1
		rec.opp_word |= 0x10000


## Pending script steps, the disabled input modes and the alternate-frame rule.
func _fixed_input() -> bool:
	if rec.script_pending():
		var step := rec.script_steps[rec.script_at]
		rec.script_at += 1
		if rec.script_at >= rec.script_steps.size():
			rec.script_at = -1
		rec.pad = ai.pad_from_step(step)
		return true
	var mode := Fx.s16(rec.input_mode)
	if mode == 0:
		rec.pad = 0
		return true
	if mode == 1:
		rec.pad = PAD_UP if rec.own_state & StateBit.DOWN else 0      # state bit 2 (down): get up
		return true
	var slot := rec.slot & 0xFFFF
	if (ai.multi != 0 and fight.frame_counter & slot & 1) \
			or (fight.mode == GameMode.FORCE and ai.force_timers[2 + slot] > 0):
		rec.pad = rec.prev_pad & PadState.DIRECTIONS
		return true
	return false


## Per-frame bookkeeping before the decision: windows, distance bands, guard needs.
func _track() -> void:
	om = o.pose_move
	sm = f.pose_move
	my_first = sm.active_first
	my_last = sm.active_last
	my_frame = Fx.s16(f.pose_frame)
	op_first = om.active_first
	op_last = om.active_last
	op_frame = Fx.s16(o.pose_frame)
	rec.filter_no_lows = false
	if sm.flags & MoveFlag.BUFFER_INPUT == 0:
		rec.no_strings = 0
	var parried := rec.parried
	var throw_next := rec.throw_next
	rec.parried = 0
	rec.throw_next = 0
	rec.punish = parried
	rec.throw_chance = throw_next
	if o.health <= Fx.div_trunc(o.health_max, 10):
		for w: int in [AiRecord.Param.FILTER_POSTURE, AiRecord.Param.FILTER_FAST, AiRecord.Param.PUNISH,
				AiRecord.Param.PUNISH_CAP]:
			rec.params[w] = 0
	var x := ai.lcg_next()
	if rec.word(AiRecord.Param.FOCUS) <= x & 0xFFF and rec.angle > 0x1FFF and Fx.s16(f.opp_rel_angle) < 0x6001 \
			and rec.reach_band < 3:
		rec.punish = 1
	rec.move_changed = 1 if sm != rec.collected_move or my_frame < rec.move_frame_seen else 0
	# +0x204 compares with the words +0x1D8 / +0x206, which nothing writes: always changed.
	rec.opp_move_changed = 1
	rec.move_frames = Fx.s16(rec.move_frames + 1)
	if rec.collected_move != sm:
		rec.collected_move = sm
		rec.move_frames = 0
	rec.move_frame_seen = my_frame
	if rec.own_state & 0x400000:
		CpuOpponent.reset_approach(rec)
	if my_first == 0:
		if rec.own_word & HINT_MIDDLE == 0 and o.was_hit_this_move == 0:
			rec.attacks_in_row = 0
	elif my_first == my_frame:
		rec.attacks_in_row = Fx.s16(rec.attacks_in_row + 1)
	if op_first == 0:
		if rec.opp_word & HINT_MIDDLE == 0 and f.was_hit_this_move == 0:
			rec.opp_string = -1
	elif op_first == op_frame:
		rec.opp_string = Fx.s16(rec.opp_string + 1)
		if rec.opp_string > 10:
			rec.opp_string = 10
	_distance_bands()
	_opponent_attack()
	_guard_state()


func _distance_bands() -> void:
	var d := rec.distance
	if fight.mode == GameMode.BALL:
		var b := _ball_distance()
		if b < d:
			d = b
	var prev := rec.prev_distance
	rec.prev_distance = d
	var e := d - rec.opp_bands[5] - 0x80
	rec.distance_change = Fx.w32(d - prev)
	if e < rec.own_bands[0]:
		var pushed := false
		for fighter: FighterState in [f, o]:
			if fighter.body_push_x != 0 or fighter.body_push_y != 0 or fighter.body_push_z != 0:
				pushed = true
		if not pushed:
			rec.band = 1
			if rec.attacking == 0:
				rec.wait = Fx.s16(rec.wait - 1)
		else:
			rec.band = 0
			if rec.attacking == 0:
				rec.wait = Fx.s16(rec.wait - 2)
		rec.far_count = 0
	elif e < rec.own_bands[1]:
		rec.band = 2
		rec.far_count = 0
	elif e < rec.own_bands[2]:
		rec.band = 3
		rec.far_count = 0
	else:
		var band := 4 if e < rec.own_bands[3] else 5
		var extra := 2 if band == 4 else 3
		rec.band = band
		var r := fight.rng.next()
		var v := ((r + fight.ai_rng) & 0x7FFF) * extra
		ai.lcg_next()
		rec.far_count = Fx.s16(rec.far_count + band + (v >> 15))
	if rec.attacking == 0 or o.in_air != 0:
		rec.wait = Fx.s16(rec.wait - 1)
	var g := Fx.w32(rec.distance - rec.own_bands[5])
	if rec.distance_change < 0:
		g = Fx.w32(g + rec.distance_change)
	var reach := 1
	var margins := PackedInt32Array([0x80, 0x100, 0x200, 0x280])
	for k in 4:
		if g < rec.opp_bands[k] + margins[k]:
			break
		reach += 1
	rec.reach_band = reach


## How long until the opponent's attack is active (+0x20A) and whether it is coming (+0x20C).
func _opponent_attack() -> void:
	if op_first != 0 or rec.opp_state & 0x80000 == 0:
		rec.opp_unblockable = 0
	else:
		rec.opp_unblockable = Fx.s16(rec.opp_unblockable + 1)
		if om.stance_slot == Fx.s16(o.cur_slot):
			rec.opp_unblockable = 0
	var coming := 1 if rec.opp_unblockable > 0 or (op_first != 0 and op_frame <= op_last + 1) else 0
	rec.opp_coming = coming
	if coming == 0 or op_first - 3 <= op_frame:
		rec.announced_frames = 0
	else:
		rec.announced_frames = Fx.w32(rec.announced_frames + 1)
	if my_first == 0 or op_frame <= op_last + 1:
		rec.passed_frames = 0
	else:
		rec.passed_frames = Fx.w32(rec.passed_frames + 1)
	if rec.opp_coming == 0:
		rec.guard_delay = -1
	elif rec.guard_delay > 0:
		rec.guard_delay -= 1
	if rec.opp_coming == 0 and rec.opp_state & 0x200000:
		rec.opp_coming = 1
	if rec.opp_state & 0x80000:
		rec.opp_charging = Fx.s16(rec.opp_charging + 1)
	else:
		rec.opp_charging = 0
	var grab := 1 if rec.opp_word & GRAB and (op_first == 0 or op_frame <= op_last) else 0
	rec.opp_grabs = grab
	if rec.opp_coming == 0 and grab == 0:
		rec.opp_until = 999
		rec.evade_reason = 0
	elif op_first == 0:
		var first_row := om.bank.branches[om.branches]
		rec.opp_until = Fx.s16(first_row[ROW_LAST] - op_frame + 1)
	else:
		var value := 0x3E5
		if op_frame <= op_last:
			rec.opp_until = Fx.s16(op_first - op_frame)
			value = -1 if Fx.s16(op_first - op_frame) < 0x65 else 0x3E6
		if value >= 0:
			rec.opp_grabs = 0
			rec.opp_coming = 0
			rec.opp_until = value


## +0x6A: the CPU already holds the guard that stops the opponent's attack level.
func _needs_guard() -> int:
	var posture := rec.own_state & 0xFFFF
	if rec.distance >= 0xB87 or rec.vs_stance != 0:
		return 0
	var attack := rec.opp_attack
	if rec.opp_grabs != 0:
		return 0 if attack == AttackWord.MID else (1 if posture == StateWord.CROUCH or posture == StateWord.GUARD_LOW else 0)
	if rec.opp_coming == 0 or rec.angle > 0x3000:
		return 0
	var accepted: Array = []
	match attack:
		AttackWord.HIGH:
			accepted = [StateWord.CROUCH, StateWord.GUARD_LOW, StateWord.GUARD_HIGH]
		AttackWord.MID:
			accepted = [StateWord.GUARD_HIGH]
		AttackWord.LOW:
			accepted = [StateWord.GUARD_LOW]
		AttackWord.MID_2:
			accepted = [StateWord.GUARD_LOW, StateWord.GUARD_HIGH]
		AttackWord.UNBLOCKABLE_2:
			accepted = [StateWord.GUARD_LOW, StateWord.CROUCH]
	return 1 if posture in accepted else 0


func _guard_state() -> void:
	rec.opp_high = 1 if o.body.joints[2].t[1] < -0xC1B else 0
	if Fx.s16(f.opp_rel_angle) > 0x3000 \
			or (rec.opp_state & 0x200000 == 0 and rec.opp_attack != AttackWord.UNBLOCKABLE and rec.opp_attack != AttackWord.UNBLOCKABLE_2):
		rec.evasion = 0
	if rec.whiff_timer >= 0 and rec.reach_band < 2 and rec.word(AiRecord.Param.FOCUS) <= ai.lcg_next() & 0xFFF:
		rec.evade_reason = 1
	var down := 0
	if rec.opp_state & (StateBit.DOWN_REVERSED | StateBit.DOWN) and rec.opp_state & 0xFFFF != StateWord.LAUNCHED:
		down = 1 if o.in_air == 0 else 0
	rec.opp_down = down
	rec.vs_stance = 1 if o.bank_type == BankType.YOSHIMITSU and Fx.s16(o.cur_slot) == CpuOpponent.YOSHIMITSU_STANCE else 0
	if rec.vs_stance != 0:
		rec.opp_string = -1
	rec.guard_holds = _needs_guard()
	if rec.own_state & StateBit.CROUCHING == 0:
		rec.crouch_timer = -1
	elif rec.crouching > 0:
		rec.crouch_timer = Fx.s16(rec.crouch_timer - 1)
	elif sm.flags & MoveFlag.LAUNCH_ANGLE == 0:
		var x0 := ai.lcg_next()
		var x1 := ai.lcg_next()
		var x2 := ai.lcg_next()
		rec.crouch_timer = (x0 & 7) + (x1 & 0xF) + 0x14 + (x2 & 7)
	rec.attacking = 1 if my_first != 0 else 0
	var open := 0
	if sm.state & 0x200000 and sm.attack_word & HINT_SPECIAL:
		open = 1 if my_frame <= my_last else 0
	rec.special_open = open


# ---- throws and stances -----------------------------------------------------------------------

## Throw escapes (the CPU is thrown, throwState < 0) and throw follow-ups (it throws).
func _throws() -> bool:
	var state := Fx.s16(f.throw_state)
	if state == 0:
		rec.throw_move = null
		rec.throw_steps = 0
		rec.throw_press_frame = -1
		rec.throw_row = PackedInt32Array()
		return false
	CpuOpponent.reset_approach(rec)
	var move := f.pose_move
	if state < 1:
		if move == rec.throw_move:
			rec.pad = 0
			return true
		rec.throw_steps = Fx.s16(rec.throw_steps - 1)
		rec.throw_move = move
		var slot := Fx.s16(o.cur_slot)
		var bank := o.bank_type
		var forced := slot in FORCED_ESCAPES or (slot == 0x172 and (bank == BankType.JIN or bank == BankType.PAUL)) \
			or (bank == BankType.KING and slot == 0x152)
		if not forced and ai.lcg_next() & 0xFFF >= rec.word(AiRecord.Param.THROW_ESCAPE):
			return true
		var rows := ai.list_rows(move).slice(0, THROW_ROWS)
		var press := 0
		if not rows.is_empty():
			var row: PackedInt32Array = rows[ai.random_below(rows.size())]
			press = _escape_press(row)
		if press != 0:
			ai.press_command(rec, press, null)
		else:
			rec.pad = 0
		return true
	if move != rec.throw_move and rec.throw_steps >= 0 and rec.throw_steps < rec.word(AiRecord.Param.THROW_STEPS) - 1 \
			and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.THROW_CONTINUE):
		var follow := _throw_follow_ups(move)
		if follow.is_empty():
			rec.throw_steps = -1
			rec.throw_press_frame = -1
			rec.throw_row = PackedInt32Array()
		else:
			rec.throw_steps = Fx.s16(rec.throw_steps + 1)
			rec.throw_move = f.pose_move
			var chosen: PackedInt32Array = follow[ai.random_below(follow.size())]
			rec.throw_press_frame = chosen[ROW_FIRST] + 1
			rec.throw_row = chosen
	if my_frame != rec.throw_press_frame or rec.throw_row.is_empty():
		rec.pad = 0
		return true
	ai.press_command(rec, rec.throw_row[ROW_COMMAND], ai.slot_move(f.ai_slot, rec.throw_row))
	return true


## The command pressed to escape with a row: 1 or 2 for the latched tap conditions, else the
## row's command.
static func _escape_press(row: PackedInt32Array) -> int:
	match row[ROW_CONDITION]:
		BranchCondition.TAP_LP, BranchCondition.TAP_BOTH:
			return 1
		BranchCondition.TAP_RP:
			return 2
	return Fx.s16(row[ROW_COMMAND])


## Up to six rows of the running throw the CPU may continue with; a few slots are tied to banks.
func _throw_follow_ups(move: MoveRow) -> Array[PackedInt32Array]:
	var bank := f.bank_type
	var found: Array[PackedInt32Array] = []
	for row in ai.list_rows(move):
		if not CpuOpponent.restriction_ok(f, o, row[ROW_RESTRICTION]):
			continue
		var u := ai.lcg_next() & 0x70
		var slot := Fx.s16(row[ROW_TARGET])
		var ok := true
		if slot == 0x3A7:
			ok = false
		elif slot == 0xD41:
			ok = bank != BankType.YOSHIMITSU or u != 0
		elif slot == 0xD24 or slot == 0xD32:
			ok = u == 0 if bank == BankType.PAUL or bank == BankType.HEIHACHI else true
		elif slot == 0xDE2:
			ok = not (bank == BankType.PAUL and u != 0)
		elif slot == 0xD25 or slot == 0xD34:
			ok = bank != BankType.PAUL and bank != BankType.HEIHACHI
		if ok and (row[ROW_CONDITION] == 0 or ai.moves.condition(row, f, o)):
			found.append(row)
			if found.size() > 5:
				return found
	return found


func _collect(current_only: bool) -> int:
	rec.marked_count = 0
	rec.collected_move = f.pose_move
	var n := ai.collect_candidates(rec, current_only)
	rec.candidate_count = Fx.s16(n)
	return Fx.s16(n)


## Stance moves (state 0x4C02, no active window): with probability word 49 execute a candidate
## whose branch row flags are 0x1C or 0x1D.
func _stance() -> bool:
	if rec.own_state & 0xFFFF != StateWord.LAUNCHED or f.pose_move.active_first != 0:
		return false
	CpuOpponent.reset_approach(rec)
	if _collect(true) > 0 and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.STANCE):
		var marked := ai.mark_candidates(rec, func(_m: MoveRow, br: PackedInt32Array) -> bool:
			return ((br[ROW_FLAGS] - 0x1C) & 0xFFFFFFFF) < 2)
		if marked > 0:
			ai.execute_candidate(rec)
			return true
	rec.pad = 0
	return true


# ---- neutral actions ------------------------------------------------------------------------

## A grounded CPU in a neutral state (+0x224 bits 2 or 10): crouch-cancel rows (RECOVERED)
## or a random action from a mask chosen by the opponent's attack timing.
func _crouch_and_actions() -> bool:
	if f.in_air != 0 or rec.own_state & (StateBit.AIRBORNE | StateBit.DOWN) == 0:
		rec.neutral_action = 0
		return false
	var cancel := false
	for row in ai.list_rows(f.pose_move):
		if row[ROW_CONDITION] == BranchCondition.RECOVERED:
			cancel = true
			break
	if cancel:
		var v := Fx.s16(rec.cancel_wait - 1)
		rec.neutral_action = 1
		rec.cancel_wait = v
		if v >= 0:
			rec.pad = 0
			return true
		var wait := rec.param_byte(fight.ai_rng & 3)
		ai.lcg_next()
		rec.pad = 0x10
		rec.cancel_wait = wait
		return true
	if _collect(true) < 1:
		rec.pad = 0
		return true
	rec.neutral_action = 1
	rec.approach_hold = 0x28
	rec.direction_hold = -1
	rec.approach_kind = 0
	rec.approach = 0
	rec.move_block = 0x10
	if rec.opp_gon_special != 0 and f.state & StateBit.DOWN_REVERSED:
		rec.pad = PAD_BACK
		return true
	if ((rec.opp_state & 0x200000 and op_first == 0) \
			or (rec.opp_attack == AttackWord.UNBLOCKABLE and rec.opp_word & HINT_SAFE == 0 and rec.opp_until < 0x1D)) \
			and op_frame < op_last:
		rec.pad = 0
		return true
	var mask := _action_mask()
	if mask == 0:
		rec.pad = 0
		return true
	var action := 0
	while true:
		var r := fight.rng.next()
		var u := (r + ai.lcg_next()) & 0x7FFF
		action = t.actions[(u * 6) >> 15]
		if mask & action:
			break
	match action:
		1:
			rec.pad = PAD_UP
			return true
		2:
			rec.pad = 0x80 if rec.frame_count & 7 else 0x4080
			return true
		4:
			rec.pad = PAD_FORWARD if f.bank_type == BankType.DOCTOR_B else PAD_BACK
			return true
		8:
			ai.filter_attacks(rec)
		0x10:
			ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
				return m.attack_word & HINT_SAFE != 0 or m.attack_word & 0xFFFF == AttackWord.LOW)
		0x20:
			ai.mark_candidates(rec, _side_step_or_special)
	if rec.marked_count > 0:
		ai.execute_candidate(rec)
	return true


func _action_mask() -> int:
	var band := rec.band
	var closing := rec.reach_band
	if op_first == 0:
		if band > 2:
			rec.neutral_action = 0
			return 7 if closing >= 4 else 0x3F
		if rec.frame_count & 1 == 0:
			return 0
		rec.neutral_action = 0
		if rec.wait < 0 and ai.lcg_next() & 0x3F == 0:
			return 0x38
		return 7
	if rec.opp_until < 0xC and op_frame <= op_last:
		if rec.opp_attack == AttackWord.LOW or rec.opp_word & HINT_SAFE:
			if rec.frame_count & 1 == 0:
				return 0
			rec.neutral_action = 0
			var x := fight.ai_rng
			var x1 := (5 * x + 3) & 0xFFFFFFFF
			if x & 2:
				fight.ai_rng = x1
				return 0x38
			if om.air_first == 0 and rec.angle <= FightMath.QUARTER_TURN and rec.opp_state & 0x200000 == 0:
				fight.ai_rng = x1
				return 4
			fight.ai_rng = (5 * x1 + 3) & 0xFFFFFFFF
			return 4 if x1 & 0x3F == 0 else 2
		var mask := 1
		if closing < 3 and (closing < 2 or rec.distance_change < 0xB):
			mask = 0x3F if ai.lcg_next() & 0xF else 0
		rec.neutral_action = 0
		return mask
	if band < 2:
		rec.neutral_action = 0
		return 0x38 if rec.opp_state & StateBit.STANDING else 0x28
	return 0


static func _side_step_or_special(m: MoveRow, br: PackedInt32Array) -> bool:
	return br[ROW_COMMAND] == CpuOpponent.SIDE_STEP \
		or (m.state & 0xA0000 == 0x80000 and m.state & 0x600000 == 0)


# ---- guard, new moves, follow-through -----------------------------------------------------

## After the opponent whiffs, a draw marks a punish chance (+0x8F); otherwise the direction is
## held while the guard state (+0x6A) says so.
func _hold_guard() -> bool:
	if o.whiffed != 0:
		var threshold := rec.word(AiRecord.Param.PUNISH) + Fx.w32(rec.opp_string * (fight.ai_difficulty & 0xFFFF) * 30)
		if ai.lcg_next() & 0xFFF < threshold:
			rec.punish = 1
			return false
	if (rec.guard_delay >= 0 or op_first == 0 or op_first - 0x1E < op_frame) and rec.guard_holds != 0:
		rec.pad = rec.prev_pad & PadState.DIRECTIONS
		return true
	return false


## The move a row leads to, or null when its slot is empty in both fighters' banks (bug #61: the
## original reads a garbage row there; the remake treats the row as leading nowhere).
func _self_target(row: PackedInt32Array) -> MoveRow:
	return ai.slot_move(f.ai_slot, row)


## Rows of a move's branch list that pass the restriction and `accept` (called with the row and
## the move it leads to), up to `limit`.
func _gather(move: MoveRow, limit: int, accept: Callable) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	for row in ai.list_rows(move):
		var target := _self_target(row)
		if target != null and CpuOpponent.restriction_ok(f, o, row[ROW_RESTRICTION]) \
				and accept.call(row, target):
			found.append(row)
			if found.size() >= limit:
				return found
	return found


## As _gather, with the restriction tested after `pre` (the game's order of tests).
func _gather_ordered(move: MoveRow, limit: int, pre: Callable, accept: Callable) -> Array[PackedInt32Array]:
	var found: Array[PackedInt32Array] = []
	for row in ai.list_rows(move):
		var target := _self_target(row)
		if target != null and pre.call(row) \
				and CpuOpponent.restriction_ok(f, o, row[ROW_RESTRICTION]) and accept.call(row, target):
			found.append(row)
			if found.size() >= limit:
				return found
	return found


## When the CPU's move changed (+0x28), the follow-up lists: string continuations, planned
## follow-ups in reach, or rows that open on frame 1 of an attack; the direction is held while a
## list is ready. Otherwise the candidates are collected, and after 220 frames in one move any
## of them is executed.
func _new_move() -> bool:
	rec.marked_count = 0
	rec.candidate_count = 0
	var done := false
	if rec.move_changed != 0:
		rec.collected_move = f.pose_move
		rec.move_frame_seen = Fx.s16(f.pose_frame)
		var move := rec.collected_move
		if rec.strings_on >= 1:
			var found := _gather(move, 4, func(_row: PackedInt32Array, target: MoveRow) -> bool:
				return target.flags & MoveFlag.BUFFER_INPUT != 0)
			rec.strings = found
			rec.strings_count = found.size()
			done = true
			if not found.is_empty():
				rec.pad = rec.prev_pad & PadState.DIRECTIONS
			else:
				rec.strings_count = 0
				rec.strings_on = 0
		elif rec.planned_on >= 1:
			var found := _planned_follow_ups(move)
			rec.planned = found
			rec.planned_count = found.size()
			done = true
			if not found.is_empty():
				rec.pad = rec.prev_pad & PadState.DIRECTIONS
			else:
				rec.planned_count = 0
				rec.planned_on = 0
		elif rec.special_open == 0:
			if f.pose_move.active_first == 0:
				rec.links_count = 0
				rec.planned_count = 0
				rec.strings_count = 0
				rec.links_on = 0
				rec.planned_on = 0
				rec.strings_on = 0
				rec.throw_list = 0
			else:
				var found: Array[PackedInt32Array] = []
				if rec.link_skip == 0:
					rec.link_last = 0
					var focus := rec.word(AiRecord.Param.FOCUS)
					found = _gather_ordered(move, 10, func(row: PackedInt32Array) -> bool:
						return row[ROW_FIRST] == 1 and row[ROW_LAST] == row[ROW_ENTRY],
						func(_row: PackedInt32Array, target: MoveRow) -> bool:
							return not (target.flags & MoveFlag.BUFFER_INPUT and ai.lcg_next() & 0xFFF < focus))
					rec.links = found
					for row in found:
						var last := row[ROW_LAST]
						if last < 0x3C and rec.link_last < last:
							rec.link_last = last
					rec.links_count = found.size()
				else:
					rec.link_skip = 0
				done = true
				if found.is_empty():
					rec.links_count = 0
					rec.links_on = 0
				else:
					rec.pad = rec.prev_pad & PadState.DIRECTIONS
					rec.links_on = Fx.s16(rec.links_on + 1)
	rec.move_frame_seen = Fx.s16(f.pose_frame)
	if not done:
		var n := Fx.s16(ai.collect_candidates(rec, false))
		rec.candidate_count = n
		if rec.move_frames > 0xDC:
			var marked := 0
			for k in n:
				if ai.cand_mark[k] == 0:
					ai.cand_mark[k] = 1
					marked += 1
			rec.marked_count = Fx.s16(rec.marked_count + marked)
			if marked > 0:
				ai.execute_candidate(rec)
				done = true
	if not done and fight.mode == GameMode.BALL and _ball_behind():
		done = true
	return done


## The +0xDC list: rows in reach whose target is usable; AI-excluded targets pass only while
## +0x208 is clear, and plain ground moves with the hint only after a draw above word 11.
func _planned_follow_ups(move: MoveRow) -> Array[PackedInt32Array]:
	var down := rec.opp_down
	var threshold := rec.word(AiRecord.Param.THROW_LIST)
	ai.lcg_next()
	var reach_mask := t.band_reach[rec.band]
	return _gather(move, 48, func(_row: PackedInt32Array, m: MoveRow) -> bool:
		if not ((down == 0 or m.attack_word & HINT_NEVER == 0) and m.state & StateBit.NOT_AI_ATTACK == 0):
			return false
		var w := m.attack_word
		if w & HINT_SPECIAL == 0 and m.state & 0x80000 == 0:
			if w & HINT_NEVER == 0:
				return false
			if ai.lcg_next() & 0x7FFF <= threshold:
				return false
		var r := w & 0xFFFF0000
		if w & HINT_REACH == 0:
			r |= HINT_CLOSE | HINT_MIDDLE
		return r & reach_mask != 0)


## During a move usable in the air or as a special (+0x52), any open candidate is executed when
## the opponent's attack comes later than this move's, the band is above 2 or the CPU faces
## away; this ends the decision either way.
func _follow_through() -> bool:
	if not (rec.special_open != 0 and rec.candidate_count != 0 and rec.opp_breath == 0):
		return false
	if rec.opp_until < f.pose_move.active_first - Fx.s16(f.pose_frame) or rec.band > 2 \
			or Fx.s16(f.facing_quadrant) == 2:
		if ai.mark_candidates(rec, func(_m: MoveRow, _br: PackedInt32Array) -> bool: return true) > 0 \
				and ai.execute_candidate(rec) >= 0:
			rec.wait = -1
	return true


## The opponent's attack is coming: attack first (word 19), duck or step back (word 21) or
## side-step (word 18).
func _counter() -> bool:
	if not (rec.opp_coming != 0 and rec.opp_string >= 0 and rec.reach_band < 4):
		return false
	if rec.punish != 0 or ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.COUNTER):
		var v := rec.opp_until
		if 1 < v and v < 0x1E:
			var k := ai.filter_quick_attacks(rec)
			if k > 0 and ai.execute_candidate(rec) >= 0:
				return true
	if rec.attacking == 0:
		var attack := Fx.s16(rec.opp_word)
		if ((attack != 0 and attack != AttackWord.UNBLOCKABLE) or rec.opp_unblockable > 0) \
				and (rec.evade_reason != 0 or ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.DUCK)):
			rec.pad = _duck_or_back()
			return true
	if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.SIDE_STEP):
		var ok := false
		if (((rec.opp_until & 0xFFFF) - 9) & 0xFFFFFFFF) < 3 and rec.angle < FightMath.QUARTER_TURN:
			ok = rec.own_state & 0x400000 == 0
		if ok and rec.reach_band > 1:
			ai.side_step(rec, -1)
			rec.wait = Fx.s16(rec.wait - 10)
			return true
	return false


# ---- reactions ------------------------------------------------------------------------------

## The opponent's move reach bits against the band mask of `band`.
func _reach_ok(band: int) -> bool:
	var w := om.attack_word
	var r := w & 0xFFFF0000
	if w & HINT_REACH == 0:
		r |= HINT_CLOSE | HINT_MIDDLE
	return r & t.band_reach[band] != 0


func _can_counter() -> bool:
	return rec.opp_coming != 0 and rec.guard_holds == 0 and Fx.s16(f.opp_rel_angle) < 0x5000 \
		and rec.distance < 0xB87 and _reach_ok(rec.reach_band)


## The reaction to the opponent's attack (jump table 0x8002317C): 0 none, 1 escape attempt,
## 2 guard or evade, 3 evasion, 4 side step, 5–8 bank-specific counters, 9 a neutral move.
func _reaction_kind() -> int:
	if rec.opp_string >= 0 or rec.vs_stance != 0:
		return 0
	if rec.guard_delay == 0 and rec.attacking == 0:
		return 2
	if rec.evasion == 0 and not (rec.opp_coming != 0 and rec.reach_band < 4):
		return 0
	if (om.active_first != 0 and om.active_last < op_frame) or Fx.s16(f.opp_quadrant) == 2:
		rec.evasion = 2
	if rec.evasion == 0 and (rec.opp_attack == AttackWord.UNBLOCKABLE or rec.opp_attack == AttackWord.UNBLOCKABLE_2 or rec.opp_state & 0x200000) \
			and _draw(AiRecord.Param.HOOKS):
		rec.evasion = 1
	if rec.guard_suspend < 0 and rec.evasion != 2:
		if rec.evasion != 0:
			return 3
	var bank := f.bank_type
	var grounded := rec.own_attack == 0 and f.in_air == 0
	var until := rec.opp_until & 0xFFFF
	var bank_record := t.bank(bank)
	if ((until - 8) & 0xFFFFFFFF) < 2 and grounded and bank_record.counter != 0 \
			and om.flags & MoveFlag.ALERT == 0 and o.in_air == 0:
		if _can_counter() and _draw(AiRecord.Param.BANK_COUNTER):
			return 5
	if bank == BankType.JIN and 0x15 < rec.opp_until and rec.opp_until < 0x1B and grounded:
		if _can_counter() and _draw(AiRecord.Param.BANK_COUNTER):
			return 6
	if ((until - 4) & 0xFFFFFFFF) < 7 and grounded and o.in_air == 0:
		if _can_counter() and _draw(AiRecord.Param.BANK_COUNTER):
			var attack := rec.opp_attack
			if attack == AttackWord.HIGH or attack == AttackWord.MID or attack == AttackWord.UNBLOCKABLE or attack == AttackWord.UNBLOCKABLE_2:
				if not bank_record.parry_high.is_empty():
					return 7
			if attack == AttackWord.LOW:
				if not bank_record.parry_low.is_empty():
					return 8
	if rec.opp_word & GRAB:
		var slot := Fx.s16(o.cur_slot)
		var obank := o.bank_type
		if slot in FORCED_ESCAPES or (slot == 0x172 and (obank == BankType.JIN or obank == BankType.PAUL)) or (obank == BankType.KING and slot == 0x152):
			if _draw(AiRecord.Param.HOOKS):
				return 1
		if rec.opp_until <= 0x1D and _draw(AiRecord.Param.GRAB_GUARD):
			rec.evade_reason = 2
			return 2
	var attack_word := Fx.s16(rec.opp_word)
	if (attack_word != 0 and attack_word != AttackWord.UNBLOCKABLE) or rec.opp_unblockable > 0:
		if rec.guard_holds != 0:
			return 0
		if rec.attacking != 0:
			return 0
		if rec.evade_reason != 0:
			return 2
		var x := ai.lcg_next()
		if x & 0xFFF < rec.word(AiRecord.Param.GUARD) or (rec.opp_unblockable > 0x1E and _draw(AiRecord.Param.GUARD_CAP)):
			rec.evade_reason = 5
			return 2
	if rec.guard_delay > 8 and ai.lcg_next() & 0x1F == 0:
		return 1
	if rec.adaptive != 0 and ai.lcg_next() & 0xF == 0:
		return 1
	if learned(rec.history, o.pose_move, ai.fight.rules.fix_ai_damage_history) and rec.vs_stance == 0 and _draw(AiRecord.Param.PUNISH_CAP):
		return 1
	if rec.vs_stance == 0 and _draw(AiRecord.Param.PUNISH):
		return _low_parry_or_escape()
	if rec.opp_unblockable >= 0x1F and _draw(AiRecord.Param.PUNISH_CAP):
		return _low_parry_or_escape()
	var ok := false
	if (((rec.opp_until & 0xFFFF) - 9) & 0xFFFFFFFF) < 3 and rec.angle < FightMath.QUARTER_TURN:
		ok = rec.own_state & 0x400000 == 0
	if not ok or rec.reach_band != 2:
		return 0
	if rec.own_state & StateBit.CROUCHING or f.in_air != 0 or rec.attacking != 0 or rec.opp_attack != AttackWord.HIGH:
		return 0
	return 4 if _draw(AiRecord.Param.SIDE_STEP) else 0


## Kind 1, or kind 9 on a 1-in-64 draw against the attack word 0x412.
func _low_parry_or_escape() -> int:
	if rec.opp_attack != AttackWord.HIGH:
		return 1
	return 9 if ai.lcg_next() & 0x3F == 0 else 1


## LAB_8005D7A4: with `execute`, runs a marked candidate (and restarts the approach timers when
## one was pressed); the reaction then ends the decision.
func _execute_marked(count: int, execute: bool) -> bool:
	if not execute:
		return false
	if count > 0 and ai.execute_candidate(rec) >= 0:
		rec.approach_hold = 0x28
		rec.approach_kind = 0
		rec.approach = 0
		rec.direction_hold = -1
	return true


func _react(kind: int) -> bool:
	match kind:
		0:
			return false
		9:
			var n := ai.mark_neutral(rec)
			if n > 0:
				rec.parried = 1
				rec.wait = -1
			return _execute_marked(n, n > 0)
		1:
			var attack := rec.opp_attack
			var n := 0
			if rec.opp_coming == 0:
				n = ai.filter_fast_attacks(rec)
			elif attack == AttackWord.UNBLOCKABLE or attack == AttackWord.UNBLOCKABLE_2 or rec.opp_state & 0x200001:
				n = ai.filter_quick_attacks_no_high(rec)
			else:
				n = ai.filter_quick_attacks(rec)
			if attack == AttackWord.HIGH:
				n += ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
					return m.active_first != 0 and m.state & (StateBit.NOT_AI_ATTACK | StateBit.CROUCHING) == StateBit.CROUCHING and ai.reach_ok(rec, m))
			return _execute_marked(n, n > 0)
		2:
			var n := ai.filter_defence(rec)
			if n > 0:
				return _execute_marked(n, true)
			var pad := 0
			if Fx.s16(f.facing_quadrant) == 0:
				pad = PAD_BACK if rec.opp_attack == AttackWord.MID else PAD_DOWN_BACK
				CpuOpponent.reset_approach(rec)
			rec.pad = pad
			return true
		3:
			return _evade()
		4:
			ai.side_step(rec, -1)
			rec.wait = Fx.s16(rec.wait - 10)
			return true
		5:
			var n := ai.mark_candidates(rec, func(_m: MoveRow, br: PackedInt32Array) -> bool:
				var slot := br[ROW_TARGET] & 0xFFFF
				return slot == 0x1EE or slot == 0x6A3)
			return _execute_marked(n, n > 0)
		6:
			var n := ai.mark_candidates(rec, func(_m: MoveRow, br: PackedInt32Array) -> bool:
				return br[ROW_TARGET] & 0xFFFF == 0x22C)
			return _execute_marked(n, n > 0)
	var bank_record := t.bank(f.bank_type)
	ai.start_script(rec, bank_record.parry_high if kind == 7 else bank_record.parry_low)
	return true


## FUN_800595E4: restarts the approach timers; forward on frames with +0x02 bit 0 clear.
func _pad_back_on_even() -> int:
	CpuOpponent.reset_approach(rec)
	return PAD_FORWARD if rec.frame_count & 1 == 0 else 0


## The evasion states in +0x94: 1 pick, 3 retreat, 4 back off, 5 side step, 6 keep out (no path
## sets 6, bug #22).
func _evade() -> bool:
	if rec.opp_high != 0:
		return false
	var dist := rec.distance
	var band := rec.band
	if rec.evasion == 1:
		if band < 3 and ai.lcg_next() & 0xFFF >= rec.word(AiRecord.Param.FOCUS):
			rec.evasion = 3
		else:
			rec.evasion = t.evasion_states[ai.random_below(7)]
	if o.bank_type == BankType.YOSHIMITSU:
		dist -= 0x12C
	var state := rec.evasion
	if state != 1 and state != 2 and dist >= 0xB87:
		rec.evasion = 0
		rec.pad = 0
		return true
	var until := rec.opp_until
	var facing := Fx.s16(f.opp_rel_angle)
	match state:
		3:
			CpuOpponent.reset_approach(rec)
			if o.pose_move.active_first != 0 and o.pose_move.active_last < Fx.s16(o.pose_frame):
				return false
			if until >= 0x1D:
				if band >= 3:
					rec.pad = _pad_back_on_even()
					rec.wait = ai.lcg_next() & 0xF
					return true
				return ai.filter_attacks_no_special(rec) <= 0
			if until < 9:
				rec.pad = PAD_BACK if facing < FightMath.QUARTER_TURN else 0
				return true
			if band < 3:
				if ai.filter_attacks_no_special(rec) <= 0:
					return true
				rec.wait = -1
				return false
			if facing < FightMath.QUARTER_TURN:
				rec.evasion = 4
				rec.pad = PAD_BACK
				return true
			return false
		4:
			CpuOpponent.reset_approach(rec)
			if facing > FightMath.QUARTER_TURN and rec.reach_band >= 2:
				rec.pad = PAD_FORWARD
				return true
			if until >= 9 and band < 2:
				if ai.filter_attacks_no_special(rec) <= 0:
					return true
				rec.wait = -1
				return false
			ai.start_script(rec, t.back_dash)
			return true
		5:
			if rec.own_state & 0x400000 or ai.lcg_next() & 7 or until < 7:
				rec.pad = PAD_FORWARD
				return false
			if facing >= FightMath.QUARTER_TURN:
				rec.evasion = 3
			ai.side_step(rec, -1)
			return true
		6:
			CpuOpponent.reset_approach(rec)
			if until >= 0x1D:
				rec.pad = PAD_BACK if rec.reach_band > 0 else 0
				return true
			if rec.reach_band >= 2 or until < 8:
				ai.start_script(rec, t.back_dash)
				return true
			rec.pad = 0x3000
			rec.direction_hold = 0x14
			return true
	return false


func _open_now(row: PackedInt32Array) -> bool:
	return row[ROW_FIRST] <= Fx.s16(f.pose_frame) and Fx.s16(f.pose_frame) <= row[ROW_LAST] \
		and CpuOpponent.restriction_ok(f, o, row[ROW_RESTRICTION]) and ai.cond_ok(row, f, o, rec.situation)


## The follow-up lists are tested for their open rows and dropped: the code that would press
## one counts them in a register that is never incremented (bug #10). The tests still run, with
## the side effects of their branch conditions.
func _expire_lists() -> void:
	if rec.strings_on > 0:
		for i in rec.strings_count:
			_open_now(rec.strings[i])
		rec.strings_on = 0
		rec.strings_count = 0
		rec.no_strings = 1
	if rec.planned_on > 0:
		for i in rec.planned_count:
			_open_now(rec.planned[i])
		rec.planned_on = 0
		rec.planned_count = 0
	if rec.links_on >= 0:
		for i in rec.links_count:
			_open_now(rec.links[i])
		rec.links_on = 0
		rec.links_count = 0


## Crouch-back (back against mids) when facing the opponent, else nothing;
## restarts the approach timers.
func _duck_or_back() -> int:
	if Fx.s16(f.facing_quadrant) != 0:
		return 0
	rec.approach_hold = 0x28
	rec.direction_hold = -1
	rec.approach_kind = 0
	rec.approach = 0
	return PAD_BACK if rec.opp_attack == AttackWord.MID else PAD_DOWN_BACK


## Outside its own attack the CPU backs off from airborne attacks at close range, turns towards
## the opponent, or walks in (bank 7 moves differently).
func _avoid_air_attack() -> bool:
	if rec.attacking != 0:
		return false
	var omv := o.pose_move
	var angle := rec.angle
	var closing := rec.reach_band
	var a := omv.air_first == 0 or closing > 1 or rec.word(AiRecord.Param.AIR_RETREAT) <= ai.lcg_next() & 0xFFF
	if not a:
		var b := false
		var pad := 0
		if angle >= FightMath.QUARTER_TURN or rec.distance_change > -0xB:
			if omv.air_last - Fx.s16(o.pose_frame) < 0x15 or angle <= FightMath.QUARTER_TURN:
				b = true
			else:
				pad = PAD_FORWARD
		else:
			pad = PAD_DOWN_FORWARD
		if not b:
			rec.pad = pad
			return true
	if angle < 0x6001 or closing > 1:
		if angle <= 0x1000:
			return false
		if ai.lcg_next() & 0x7FFF >= angle:
			return false
		if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.FOCUS):
			return false
		rec.approach = 8
		rec.approach_kind = 0
		rec.approach_hold = 0x30
		if f.bank_type == BankType.XIAOYU:
			rec.pad = PAD_BACK if angle >= FightMath.QUARTER_TURN else PAD_FORWARD
			return true
		var pad2 := 0
		if rec.opp_coming == 0 or ai.lcg_next() & 7:
			pad2 = PAD_FORWARD
			if closing < 3:
				pad2 = PAD_BACK if rec.frame_count & 1 else PAD_FORWARD
		else:
			pad2 = _duck_or_back()
		rec.pad = pad2
		return true
	if o.in_air != 0:
		rec.pad = 0
	elif rec.opp_down != 0:
		rec.pad = (PAD_DOWN | PadState.CROSS) if rec.frame_count & 1 else (PAD_DOWN | PadState.CIRCLE)
	else:
		if ai.lcg_next() & 0xFFF >= rec.word(AiRecord.Param.FOCUS):
			rec.wait = -2
			return false
		if f.bank_type == BankType.XIAOYU:
			rec.pad = PAD_BACK if angle >= FightMath.QUARTER_TURN else PAD_FORWARD
		else:
			rec.pad = PAD_FORWARD
	return true


# ---- attacks ------------------------------------------------------------------------------

## Picks and executes an attack; true ends the decision.
func _attack() -> bool:
	if fight.mode == GameMode.FORCE:
		# Tekken Force: no attack while held off, and one not facing the player attacks only
		# by chance.
		var slot := rec.slot & 0xFFFF
		if ai.force_timers[slot] >= 1:
			return false
		if fight.force.player().cur_opp_index != f.index:
			if ai.lcg_next() & 0xFFF < t.force_words[rec.force_words + 2]:
				return false
	if rec.crouch_attack_hold >= 1:
		rec.crouch_attack_hold -= 1
		rec.pad = rec.prev_pad & PadState.DIRECTIONS
		return true
	if rec.neutral_cooldown >= 5:
		rec.pad = rec.prev_pad & PadState.DIRECTIONS
		return true
	var band := rec.band
	if not (band < 4 and rec.opp_high == 0 and rec.attacks_in_row < rec.attack_limit):
		return false
	if band > 2 and ai.random_below(12) != 0:
		return false
	if band > 1 and ai.random_below(8) == 0:
		return false
	if rec.approach_kind != 0:
		if rec.guard_delay < 1 and (rec.opp_coming == 0 or rec.reach_band > 3):
			if rec.opp_state & StateBit.DOWN and ai.random_below(0x1000) < 0x100:
				return false
		else:
			rec.pad = PAD_BACK
			return true
	var n := _choose()
	if n != DIRECT:
		n = _last_resort(n)
		if n < 0:
			CpuOpponent.reset_approach(rec)
			return true
	var pick := ai.execute_candidate(rec)
	if pick < 0:
		return false
	rec.approach_hold = 0x28
	rec.direction_hold = -1
	rec.approach_kind = 0
	rec.approach = 0
	var target := ai.cand_target[pick]
	if Fx.s16(fight.attract) == 0 and target.flags & MoveFlag.BUFFER_INPUT:
		rec.strings_on = 1
	elif (rec.own_state & 0x80000 and ai.lcg_next() & 0x3F < 0x20) \
			or (target.state & 0x80000 and ai.lcg_next() & 0x3F < 0x30):
		rec.planned_on = 1
	var pressed := rec.pressed_move
	var state := Fx.s16(pressed.state) if pressed != null else 0
	if state == StateWord.CROUCH or state == 0x2829:
		rec.crouch_attack_hold = 0xC
	if target.active_first == 0 and target.state & 0x80000 == 0:
		return true
	rec.last_attack = target
	return true


## With nothing marked, far away and at 10 % health, a 1-in-4 draw and word 16 mark the
## desperation moves (move +0x24 bit 16).
func _last_resort(n: int) -> int:
	if n == 0 and rec.reach_band > 2 and Fx.s16(f.power_timer) == 0 \
			and f.health <= Fx.div_trunc(f.health_max, 10) \
			and ai.lcg_next() & 3 == 0 and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.PUNISH):
		n = ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.flags & MoveFlag.POWER != 0)
	return n


## Marks the candidates to execute: their count (−1: input already set), or DIRECT.
func _choose() -> int:
	var wait := rec.wait
	var threshold := rec.word(AiRecord.Param.THROW_TRY)
	if rec.no_strings != 0:
		var removed := 0
		for k in rec.candidate_count:
			var mark := ai.cand_mark[k]
			if mark >= 0 and ai.cand_target[k].flags & MoveFlag.BUFFER_INPUT:
				if mark > 0:
					removed += 1
				ai.cand_mark[k] = -1
		rec.marked_count = Fx.s16(rec.marked_count - removed)
	if rec.announced_frames >= 0x1A and rec.guard_delay < 0 and rec.guard_holds == 0:
		var delay := rec.opp_until - ((fight.ai_rng & 7) + 4)
		ai.lcg_next()
		rec.guard_delay = maxi(delay, 3)
	if rec.guard_delay >= 1:
		return 0
	var focus := rec.word(AiRecord.Param.FOCUS)
	if rec.punish != 0 or rec.throw_chance != 0 \
			or (rec.announced_frames > 0x19 and Fx.div_trunc(focus, 2) <= ai.lcg_next() & 0xFFF) \
			or (((rec.passed_frames - 1) & 0xFFFFFFFF) < 0x13 and focus <= ai.lcg_next() & 0xFFF):
		wait = -1
	var omv := o.pose_move
	var band := rec.band
	if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.AIR_RETREAT) and o.in_air != 0 and Fx.s16(rec.opp_state) != StateWord.LAUNCHED:
		var last := omv.air_last
		var first := omv.air_first
		var frame := Fx.s16(o.pose_frame)
		if first + Fx.div_trunc(last - first, 2) <= frame and frame <= last and rec.angle <= FightMath.QUARTER_TURN and band == 2:
			rec.wait = -1
	if Fx.s16(o.cur_slot) == 6 and band < 3 and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.PUNISH):
		rec.wait = Fx.s16(rec.wait - 2)
	if rec.opp_state & (StateBit.AIRBORNE | StateBit.DOWN_REVERSED | StateBit.DOWN | StateBit.CROUCHING) or o.in_air != 0 or o.about_to_hit != 0 or o.bank_type == BankType.GON or rec.opp_until < 10:
		threshold = 0
		rec.throw_chance = 0
	if fight.mode == GameMode.BALL and _ball_ahead():
		return ai.filter_attacks(rec)
	if rec.opp_down != 0 and rec.vs_stance == 0:
		return _vs_grounded(wait)
	if Fx.s16(rec.opp_state) == StateWord.LAUNCHED and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.VS_LAUNCHED):
		return _vs_stance()
	if rec.air_cooldown >= 0:
		var n := ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.active_first != 0 and (m.state & 0x80000 != 0 or m.attack_word & HINT_SPECIAL != 0) \
				and m.state & StateBit.NOT_AI_ATTACK == 0)
		if n > 0:
			rec.air_cooldown = -1
		return n
	if rec.opp_unblockable != 0:
		if rec.punish == 0 and rec.word(AiRecord.Param.PUNISH) <= ai.lcg_next() & 0xFFF:
			if wait < 1:
				return ai.filter_attacks_no_special(rec) if rec.opp_state & StateBit.CROUCHING else ai.filter_attacks(rec)
			return 0
		return ai.filter_side_steps_then_quick(rec)
	if (rec.opp_coming != 0 or rec.opp_grabs != 0) and rec.vs_stance == 0:
		if rec.punish != 0 or ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.PUNISH):
			return ai.filter_side_steps_then_quick(rec)
		if wait < 1:
			return ai.filter_attacks_no_special(rec) if rec.opp_state & StateBit.CROUCHING else ai.filter_attacks(rec)
		return 0
	if wait < 1:
		if rec.neutral_cooldown < 0:
			return _approach_attack(threshold)
		var n2 := ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.state & 0xA0000 == 0x80000 and m.air_first == 0)
		rec.neutral_cooldown = -1
		return n2
	if band > 2 or rec.own_state & StateBit.CROUCHING or ai.lcg_next() & 0xFFF > 3:
		return 0
	if ai.mark_neutral(rec) < 1:
		return 0
	return DIRECT


static func _low_or_hint(m: MoveRow, extra: Array) -> bool:
	var w := m.attack_word
	return m.active_first < 0x51 and (w & HINT_SAFE != 0 or (w & 0xFFFF) in extra) and w & HINT_NEVER == 0


## The opponent is down (+0x208).
func _vs_grounded(wait: int) -> int:
	if rec.attacking != 0:
		return 0
	var x := ai.lcg_next()
	if rec.word(AiRecord.Param.FOCUS) <= x & 0xFFF:
		wait = -1
	if not (rec.angle <= FightMath.QUARTER_TURN or ai.lcg_next() & 0xF != 0):
		return ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.state & StateBit.NOT_AI_ATTACK != 0)
	if wait >= 0:
		return 0
	x = ai.lcg_next()
	var u := x & 0xFFF
	if u < 0x334:
		return ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.bank.branches[m.branches][ROW_CONDITION] == BranchCondition.OPP_DOWN and m.attack_word & HINT_NEVER == 0)
	if u < 0x3AF:
		ai.side_step(rec, x & 1)
		return -1
	if u < 0x6E2:
		return ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return _low_or_hint(m, [AttackWord.LOW_2]))
	if u < 0x75D and rec.own_state & StateBit.CROUCHING == 0:
		return ai.mark_neutral(rec)
	if u < 0x829:
		return ai.mark_command(rec, CpuOpponent.CROUCH_DASH)
	if ((rec.band - 2) & 0xFFFFFFFF) < 2 and u < 0x9C3:
		ai.start_script(rec, t.wake_up)
		return -1
	return ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
		return _low_or_hint(m, [AttackWord.LOW_2, AttackWord.LOW]))


static func _hint_ground(m: MoveRow, _br: PackedInt32Array) -> bool:
	return m.attack_word & HINT_SAFE != 0 and m.active_first == 0 and m.air_first == 0


## The opponent is in a stance (state 0x4C02), after a draw against word 30.
func _vs_stance() -> int:
	var band := rec.band
	var n := 0
	if band < 3:
		if band > 1:
			var x := ai.lcg_next()
			if x & 0xF == 0:
				n = ai.mark_command(rec, CpuOpponent.SIDE_STEP)
			else:
				n = ai.mark_candidates(rec, _hint_ground)
	else:
		var side := true
		if rec.distance_change < 0x33:
			var x2 := ai.lcg_next()
			if x2 & 7 == 0:
				n = ai.mark_candidates(rec, _hint_ground)
				side = false
		if side:
			n = ai.mark_command(rec, CpuOpponent.SIDE_STEP)
			if n > 0:
				rec.approach_kind = 2
				rec.approach = 0xFA
				rec.approach_hold = 0x136
	if band < 4 and rec.opp_high == 0 and rec.word(AiRecord.Param.FOCUS) <= ai.lcg_next() & 0xFFF:
		rec.wait = -1
		if o.in_air == 0 and ai.lcg_next() & 0x3F < 0x20 and not rec.filter_no_lows:
			n += ai.filter_punish_level_no_high(rec)
		else:
			n += ai.filter_punish_level(rec)
	return n


## Waiting is over and nothing urgent: throws, bank setups, neutral moves, side steps or the
## regular attack filters.
func _approach_attack(threshold: int) -> int:
	var band := rec.band
	if (rec.throw_chance != 0 or ai.lcg_next() & 0xFFF < threshold) and band < 2 and o.bank_type != BankType.GON:
		var x := ai.lcg_next()
		var n := 0
		var throw_rows := func(m: MoveRow, br: PackedInt32Array) -> bool:
			return m.attack_word & HINT_NEVER != 0 and br[ROW_COMMAND] & 0xC200 != 0x200
		var plain_throws := func(m: MoveRow, br: PackedInt32Array) -> bool:
			return m.attack_word & HINT_NEVER != 0 and br[ROW_COMMAND] & 0xFFE0 == 0
		if x & 0xFFF < rec.word(AiRecord.Param.THROW_LIST):
			n = ai.mark_candidates(rec, throw_rows)
			if n < 1:
				n = ai.mark_candidates(rec, plain_throws)
			else:
				rec.throw_list = 1
		else:
			n = ai.mark_candidates(rec, plain_throws)
		if n > 0:
			return n
	var setups := t.bank(f.bank_type).setups
	if rec.setup_cooldown < 0 and not setups.is_empty() and rec.attacking == 0 and rec.own_state & StateBit.CROUCHING == 0 \
			and Fx.s16(f.cur_slot) != setups[0].slot and rec.angle < 0x2001 and f.in_air == 0 and band < 3 \
			and rec.opp_down == 0:
		var u := ai.lcg_next() & 0xFFF
		for setup in setups:
			if u <= setup.chance:
				if ai.branch_open_to(rec, setup.slot):
					ai.start_script(rec, setup.steps)
					rec.planned_on = 1
					rec.setup_cooldown = (ai.lcg_next() & 0xF) + 0x1C
					return -1
				break
	if band < 3 and f.in_air == 0 and rec.own_state & StateBit.CROUCHING == 0 and ai.lcg_next() & 0x3F < 0xE:
		return ai.mark_neutral(rec)
	var x3 := ai.lcg_next()
	if x3 & 0x3F < 0x20:
		if ai.lcg_next() & 1:
			return ai.mark_candidates(rec, _side_step_or_special)
		return ai.filter_punish_level(rec)
	if rec.neutral_cooldown < 0 and rec.air_cooldown < 0 and rec.own_state & StateBit.CROUCHING == 0 and f.in_air == 0 \
			and ai.lcg_next() & 0xFFF < 0x200:
		var neutral := ai.mark_neutral(rec)
		if neutral > 0:
			rec.neutral_cooldown = 0x12
			rec.wait = -1
			return neutral
	var n2 := ai.mark_candidates(rec, _side_step_or_special)
	if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.FILTER_POSTURE):
		return n2 + ai.filter_vs_posture(rec)
	if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.FILTER_FAST):
		return n2 + ai.filter_fast_attacks(rec)
	if rec.opp_state & StateBit.CROUCHING and ai.lcg_next() & 0xFFF >= rec.word(AiRecord.Param.FOCUS):
		return n2 + ai.filter_attacks_no_special(rec)
	if ai.lcg_next() & 0x3F < 10:
		return n2 + ai.filter_plain_attacks(rec)
	if f.in_air == 0 and rec.air_cooldown < 0 and ai.random_below(0x1000) < 0x200:
		var air := ai.mark_candidates(rec, func(m: MoveRow, _br: PackedInt32Array) -> bool:
			return m.air_first != 0 and m.state & StateBit.NOT_AI_ATTACK == 0 \
				and (m.state & 0x80000 != 0 or m.attack_word & HINT_SPECIAL != 0))
		if air > 0:
			rec.air_cooldown = 4
			var a := ai.random_below(4)
			var b := ai.random_below(4)
			var d := ai.random_below(4)
			rec.air_cooldown = a + b + d + 1
			return air
	if ai.random_below(0x1000) < 10:
		return n2 + ai.mark_candidates(rec, func(m: MoveRow, br: PackedInt32Array) -> bool:
			var slot := br[ROW_TARGET] & 0xFFFF
			return m.active_first == 0 and m.air_first == 0 and m.state & StateBit.NOT_AI_ATTACK == 0 \
				and slot != 0x1EE and slot != 0x6A3)
	return n2 + ai.filter_attacks(rec)


# ---- movement -------------------------------------------------------------------------------

func _move() -> void:
	if _movement() == 0:
		if rec.crouch_timer >= 0:
			rec.pad = PAD_DOWN
		elif rec.direction_hold >= 0:
			rec.pad = rec.prev_pad & PadState.DIRECTIONS
		else:
			rec.pad = 0


func _movement() -> int:
	if rec.move_block >= 0:
		return 0
	if rec.approach < 0:
		if rec.attacking == 0 and rec.crouch_timer < 0 and rec.direction_hold < 0 and rec.air_cooldown < 0:
			return _pick_movement()
		return 0
	if (rec.opp_breath == 0 or rec.distance > 7000) and rec.band > 0:
		var x := fight.ai_rng
		var x1 := (5 * x + 3) & 0xFFFFFFFF
		if rec.word(AiRecord.Param.FOCUS) <= x & 0xFFF:
			var unsafe := false
			if rec.opp_coming != 0 and rec.guard_holds == 0 and Fx.s16(f.opp_rel_angle) < 0x5000:
				if rec.distance < 0xB87:
					var w := o.pose_move.attack_word
					var r := w & 0xFFFF0000
					if w & HINT_REACH == 0:
						r |= HINT_CLOSE | HINT_MIDDLE
					unsafe = r & t.approach_reach[rec.reach_band] != 0
			fight.ai_rng = x1
			if unsafe:
				CpuOpponent.reset_approach(rec)
				return _pick_movement()
		fight.ai_rng = x1
		if rec.approach_kind == 2:
			var pad := PAD_FORWARD
			if rec.reach_band < 3 and ai.lcg_next() & 0xFFF < 0x20:
				CpuOpponent.reset_approach(rec)
				pad = PAD_BACK
			rec.pad = pad
			return 1
		if rec.wait < 0x24 and rec.reach_band == 2 and ai.lcg_next() & 0xF == 0:
			if ai.mark_command(rec, CpuOpponent.SIDE_STEP) > 0 and ai.execute_candidate(rec) >= 0:
				rec.approach_kind = 0
				rec.approach = 0
				rec.approach_hold = 0x28
				return 1
		rec.pad = rec.prev_pad & PadState.DIRECTIONS
		return 1
	CpuOpponent.reset_approach(rec)
	return _pick_movement()


## A random movement by distance band (or, while waiting long, by reach band).
func _pick_movement() -> int:
	if rec.approach_hold >= 0 or rec.direction_hold >= 0:
		return 0
	var v := ai.random_below(0x1000)
	var choice := 0
	if rec.opp_breath == 0:
		if rec.wait < 0x24:
			choice = _by_distance(v)
		else:
			choice = _by_closing(v)
			if (choice == 3 or choice == 6) and rec.word(AiRecord.Param.KEEP_RETREAT) <= ai.lcg_next() & 0xFFF:
				choice = 0
		if (choice == 3 or choice == 6) and (rec.opp_state & 0x80000 or rec.opp_attack != 0) \
				and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.FOCUS):
			choice = 0
	return _do_movement(choice)


func _by_distance(v: int) -> int:
	match rec.band:
		0, 1:
			return 3 if v < 0x14 else 0
		2:
			if v < 0x7A:
				return 5
			if v < 0x1EB:
				return 1
			if v < 0x214:
				return 3
			return 8 if v < Fx.div_trunc(rec.word(AiRecord.Param.SIDE_STEP) << 12, 1000) else 0
		3:
			return 2 if v < 0x666 else (1 if v < 0xB33 else 0)
		4:
			return 2 if v < 0xCC else (4 if v < 0x599 else 1)
		5:
			if rec.far_count < 0x2D1 and rec.opp_down == 0 and v > 0x11D:
				return 1
			return 4
	return 0


func _by_closing(v: int) -> int:
	match rec.reach_band:
		0, 1:
			return 6 if v < 0x199 else (3 if v < 0x333 else 0)
		2:
			if v <= 0x27:
				return 2
			return 3 if v < 0x170 else 0
		3:
			if v < 0x1EB:
				return 2
			if v < 0x214:
				return 5
			if v < 0x218:
				return 3
			if v < 0x22D:
				return 1
			return 8 if v < 0x241 and rec.own_state & StateBit.STANDING else 0
		4:
			if v < 0x80:
				return 2
			if v < 0x90:
				return 5
			if v < 0xC0:
				return 8
			return 1 if v < 0x3C0 else 0
		5:
			if rec.far_count < 0x2D1 and rec.opp_down == 0 and v > 0x50:
				if v < 0xCC:
					return 2
				if v < 0x400:
					return 1
				return 5 if v < 0x5EB else 0
			return 4
	return 0


## The movements: 1 side step or walk in, 2 walk in, 3 step back, 4 side step with a long
## approach or dash in, 5 dash in, 6 crouch dash or step back, 8 side step then a candidate.
func _do_movement(choice: int) -> int:
	if choice == 0:
		return 0
	if choice == 1:
		if ai.mark_command(rec, CpuOpponent.SIDE_STEP) >= 1:
			rec.approach_kind = 0
			rec.approach = 0
			rec.approach_hold = 0x28
			return 1 if ai.execute_candidate(rec) >= 0 else 0
		choice = 2
	if choice == 4:
		if ai.mark_command(rec, CpuOpponent.SIDE_STEP) >= 1:
			rec.approach_kind = 2
			rec.approach = 0xFA
			rec.approach_hold = 0x136
			return 1 if ai.execute_candidate(rec) >= 0 else 0
		choice = 5
	if choice == 6:
		if ai.mark_command(rec, CpuOpponent.CROUCH_DASH) >= 1:
			rec.approach_hold = 0x3C
			return 1 if ai.execute_candidate(rec) >= 0 else 0
		choice = 3
	if choice == 2:
		var q := 0
		var short := 0
		var long := 0
		if rec.band >= 0 and rec.band < 3:
			q = ai.random_below(8)
			short = q + 4
			long = q + 0x2C
		elif rec.band == 3:
			q = ai.random_below(10)
			short = q + 10
			long = q + 0x32
		else:
			q = ai.random_below(0xF)
			short = q + 0xF
			long = q + 0x37
		rec.approach_kind = 0
		rec.approach = short
		rec.approach_hold = long
		rec.pad = PAD_DOWN_FORWARD if rec.crouching > 0 else PAD_FORWARD
		return 1
	if choice == 3:
		var q := ai.random_below(5)
		rec.approach = q + 0x14
		rec.approach_kind = 0
		rec.approach_hold = q + 0x3C
		rec.pad = PAD_DOWN_BACK if rec.crouching > 0 else PAD_BACK
		return 1
	if choice == 5:
		var q := ai.random_below(0x14)
		rec.approach = q + 0x28
		rec.approach_kind = 0
		rec.approach_hold = q + 0x50
		rec.pad = PAD_DOWN_FORWARD if rec.crouching > 0 else PAD_FORWARD
		return 1
	if choice == 8 and (rec.reach_band > 2 or rec.opp_until > 10):
		ai.side_step(rec, -1)
	return 1 if ai.execute_candidate(rec) >= 0 else 0


# ---- the end of the frame --------------------------------------------------------------------

static func _dec(v: int) -> int:
	return v - 1 if v >= 0 else v


## Timers, adaptive difficulty, guard memory and the pad output.
func _finish() -> PackedInt32Array:
	var state := rec.own_state
	var target := rec.pressed_move
	rec.crouching = 1 if state & (StateBit.DOWN_REVERSED | StateBit.DOWN | StateBit.CROUCHING) == StateBit.CROUCHING else 0
	if target != null and rec.direction_hold < 0 and target.air_first != 0:
		rec.direction_hold = target.air_first
	rec.direction_hold = _dec(rec.direction_hold)
	rec.approach = _dec(rec.approach)
	rec.approach_hold = _dec(rec.approach_hold)
	rec.whiff_timer = _dec(rec.whiff_timer)
	rec.air_cooldown = _dec(rec.air_cooldown)
	rec.neutral_cooldown = _dec(rec.neutral_cooldown)
	rec.setup_cooldown = _dec(rec.setup_cooldown)
	rec.move_block = _dec(rec.move_block)
	rec.guard_suspend = _dec(rec.guard_suspend)
	if rec.reload_timer == 0:
		ai.load_params(rec, -1, -1, -1)
	rec.reload_timer = _dec(rec.reload_timer)
	if fight.mode == GameMode.FORCE:
		var slot := rec.slot & 0xFFFF
		for base: int in [0, 2]:
			if ai.force_timers[base + slot] >= 0:
				ai.force_timers[base + slot] -= 1
	var posture := state & 0xFFFF
	rec.coming_seen = rec.opp_coming
	var guarding := posture == StateWord.GUARD_HIGH or posture == StateWord.GUARD_LOW
	if rec.guarding == 0:
		rec.guarding = 1 if guarding else 0
		rec.guard_memory = 0
	else:
		rec.guarding = 1 if guarding else 0
		if not guarding and rec.guard_memory != 0:
			rec.guard_memory = 0
	if f.got_hit != 0:
		CpuOpponent.reset_approach(rec)
		rec.planned_on = 0
		rec.strings_on = 0
		rec.links_on = 0
		rec.throw_list = 0
	if f.whiffed != 0 and rec.reach_band < 3:
		rec.whiff_timer = 0x1E
	if o.whiffed != 0 and rec.band < 2 and ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.PUNISH):
		rec.wait = Fx.s16(rec.wait - 3)
	if f.health < rec.health_seen:
		_learn_from_damage()
	rec.health_seen = f.health
	if f.got_hit != 0 and fight.attract == 0:
		rec.approach_hold = 0x28
		rec.direction_hold = -1
		rec.approach_kind = 0
		rec.approach = 0
		_raise_capped(AiRecord.Param.GUARD, 10, AiRecord.Param.GUARD_CAP)
		_raise_capped(AiRecord.Param.PUNISH, 10, AiRecord.Param.PUNISH_CAP)
		if rec.opp_string > 0:
			_raise_capped(AiRecord.Param.DUCK, 0x28, AiRecord.Param.DUCK_CAP)
			_raise_capped(AiRecord.Param.COUNTER, 0x14, AiRecord.Param.COUNTER_CAP)
	var pad := rec.pad & 0xFFFF
	var pressed := pad & (pad ^ rec.prev_pad)
	rec.prev_pad = pad
	return PackedInt32Array([pad, pressed])


func _raise_capped(word_index: int, step: int, cap: int) -> void:
	rec.params[word_index] = Fx.s16(rec.params[word_index] + step)
	if rec.params[cap] < rec.params[word_index]:
		rec.params[word_index] = rec.params[cap]


## Whether the opponent's move is one that hurt the CPU before: the game compares only history slot
## 0 (bug #23); `every_entry` (RuleSet.fix_ai_damage_history) compares the whole history.
static func learned(history: Array[MoveRow], move: MoveRow, every_entry: bool) -> bool:
	return move in history if every_entry else move == history[0]


## The CPU lost health: after a draw against word 35 the wait shortens and, in one-on-one play,
## the opponent's move goes into an 8-entry history; a move already there twice switches to
## level 9 for 600 frames (the adaptive mode).
func _learn_from_damage() -> void:
	if ai.lcg_next() & 0xFFF < rec.word(AiRecord.Param.FOCUS):
		return
	rec.wait = Fx.s16(rec.wait - 3)
	var move := o.pose_move
	if ai.multi != 0:
		return
	rec.adaptive = 0
	var seen := 0
	for k in AiRecord.HISTORY:
		if rec.history[k] == move:
			seen += 1
	if seen > 1:
		if rec.reload_timer < 1:
			ai.load_params(rec, 0, 9, -1)
		rec.reload_timer = 600
		rec.adaptive = 1
	var k2 := rec.history_at
	rec.history[k2] = move
	rec.history_at = (k2 + 1) & 7


# ---- Tekken Ball (volley.ovl) ----------------------------------------------------------------------

const BALL_LINE := 0x800B6AF0          ## s32: player 1, player 2 and the ball along the line, its height, its lateral offset
const BALL_AHEAD := 0x7D0


## FUN_800B4958: both fighters and the ball projected onto the line through the fighters. The
## line's z intercept divides by the fighters' x difference unchecked (bug #24: with equal x the
## R3000's quotient ±1 gives one frame of wrong positions; with the fix the line keeps its values).
func _ball_project() -> void:
	var tb := fight.ball
	var p := tb.position()
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var dx := Fx.w32(f1.root_x - f0.root_x)
	var dz := Fx.w32(f1.root_z - f0.root_z)
	if dx == 0 and fight.rules.fix_ball_cpu:
		return
	var angle := CameraMath.atan2_units4096(dx, dz, fight.tables.camera)
	var c := FightMath.cos12(-angle, fight.tables)
	var s := FightMath.sin12(-angle, fight.tables)
	var k := Fx.w32(f0.root_z - TekkenBall._div(Fx.w32(dz * f0.root_x), dx))
	var line := PackedInt32Array([Fx.trunc12(Fx.w32(f0.root_x * c - Fx.w32(f0.root_z - k) * s)),
		Fx.trunc12(Fx.w32(f1.root_x * c - Fx.w32(f1.root_z - k) * s)),
		Fx.trunc12(Fx.w32(p[0] * c - Fx.w32(p[2] - k) * s)), p[1],
		Fx.trunc12(Fx.w32(p[0] * s + Fx.w32(p[2] - k) * c))])
	for i in 5:
		tb.v.put32(BALL_LINE + 4 * i - TekkenBall.BASE, line[i])


func _ball_line(i: int) -> int:
	return fight.ball.v.s32(BALL_LINE + 4 * i - TekkenBall.BASE)


## FUN_800B4B08: the CPU's distance to the ball on the line.
func _ball_distance() -> int:
	var d := Fx.w32(_ball_line(f.player_index) - _ball_line(2))
	var lateral := _ball_line(4)
	return CameraMath.isqrt(Fx.w32(d * d + lateral * lateral) & 0xFFFFFFFF)


## FUN_800B4B64: the ball is behind the CPU on the line: it back-dashes to get under it.
func _ball_behind() -> bool:
	var ball := _ball_line(2)
	var behind := ball < _ball_line(0) if rec.slot == 0 else _ball_line(1) < ball
	if behind:
		ai.start_script(rec, t.back_dash)
	return behind


## FUN_800B4BE4: the ball is ahead of the CPU: for player 1 more than 2,000 units ahead, for
## player 2 ahead but closer than 2,000 units (bug #3; the fix mirrors player 1's test).
func _ball_ahead() -> bool:
	var ball := _ball_line(2)
	if rec.slot == 0:
		var p := _ball_line(0)
		return p < ball and p + BALL_AHEAD < ball
	var q := _ball_line(1)
	if fight.rules.fix_ball_cpu:
		return ball < q and ball < q - BALL_AHEAD
	return ball < q and q - BALL_AHEAD < ball
