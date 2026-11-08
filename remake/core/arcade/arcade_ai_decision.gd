class_name ArcadeAiDecision
extends AiDecision
## The arcade CPU's decision for one frame (FUN_801C3634, FUN_801C3C74): the steps run in the game's
## order until one produces the frame's input; the bookkeeping at the end (FUN_801C3730) always runs.
## `f` and `o` are the CPU and its opponent, `sm` and `om` their running moves. Addresses are the
## arcade's; `ArcadeCpu` holds what the steps share.

# The difficulty words.
const WORD_HOLD: int = ArcadeAiRecord.Param.HOLD
const WORD_THROW_STEPS: int = ArcadeAiRecord.Param.THROW_STEPS
const WORD_THROW_TRY: int = ArcadeAiRecord.Param.THROW_TRY
const WORD_THROW_ESCAPE: int = ArcadeAiRecord.Param.THROW_ESCAPE
const WORD_THROW_LIST: int = ArcadeAiRecord.Param.THROW_LIST
const WORD_FILTER_POSTURE: int = ArcadeAiRecord.Param.FILTER_POSTURE
const WORD_FILTER_FAST: int = ArcadeAiRecord.Param.FILTER_FAST
const WORD_GUARD: int = ArcadeAiRecord.Param.GUARD
const WORD_GUARD_CAP: int = ArcadeAiRecord.Param.GUARD_CAP
const WORD_PUNISH: int = ArcadeAiRecord.Param.PUNISH
const WORD_PUNISH_CAP: int = ArcadeAiRecord.Param.PUNISH_CAP
const WORD_SIDE_STEP: int = ArcadeAiRecord.Param.SIDE_STEP
const WORD_COUNTER: int = ArcadeAiRecord.Param.COUNTER
const WORD_COUNTER_CAP: int = ArcadeAiRecord.Param.COUNTER_CAP
const WORD_DUCK: int = ArcadeAiRecord.Param.DUCK
const WORD_DUCK_CAP: int = ArcadeAiRecord.Param.DUCK_CAP
const WORD_STRINGS_MAX: int = ArcadeAiRecord.Param.STRINGS_MAX
const WORD_STRINGS_CHANCE: int = ArcadeAiRecord.Param.STRINGS_CHANCE
const WORD_ATTACKS_A: int = ArcadeAiRecord.Param.ATTACKS_A
const WORD_PLANNED_KEEP: int = ArcadeAiRecord.Param.PLANNED_KEEP
const WORD_ATTACKS_B: int = ArcadeAiRecord.Param.ATTACKS_B
const WORD_LINKS_CHANCE: int = ArcadeAiRecord.Param.LINKS_CHANCE
const WORD_HOOKS: int = ArcadeAiRecord.Param.HOOKS
const WORD_VS_LAUNCHED: int = ArcadeAiRecord.Param.VS_LAUNCHED
const WORD_FOCUS: int = ArcadeAiRecord.Param.FOCUS
const WORD_AIR_RETREAT: int = ArcadeAiRecord.Param.AIR_RETREAT
const WORD_KEEP_RETREAT: int = ArcadeAiRecord.Param.KEEP_RETREAT
const WORD_BANK_COUNTER: int = ArcadeAiRecord.Param.BANK_COUNTER
const WORD_GRAB_GUARD: int = ArcadeAiRecord.Param.GRAB_GUARD
const WORD_STANCE: int = ArcadeAiRecord.Param.STANCE
const WORD_STANCE_ESCAPE: int = ArcadeAiRecord.Param.STANCE_ESCAPE

# The chain's step numbers (0x8021F394).
const STEP_SCRIPT := 0
const STEP_THROW := 2
const STEP_LAUNCHED := 3
const STEP_NEUTRAL := 4
const STEP_PENDING_MOVE := 5
const STEP_HOOK_OPPONENT := 6
const STEP_HOOK_OWN := 7
const STEP_HOLD_GUARD := 8
const STEP_ATTRACT := 9
const STEP_COLLECT := 10
const STEP_SPECIAL := 11
const STEP_COUNTER := 12
const STEP_REACT := 13
const STEP_STRINGS := 14
const STEP_PLANNED := 15
const STEP_LINKS := 16
const STEP_FACING := 17
const STEP_ATTACK := 18
const STEP_APPROACH := 19
const STEP_IDLE := 99

const DIRECTIONS := ArcadeInput.DIRECTIONS
const UP := ArcadeCpu.UP
const DOWN := ArcadeCpu.DOWN
const BACK := ArcadeCpu.BACK
const FORWARD := ArcadeCpu.FORWARD
const DOWN_FORWARD := ArcadeCpu.DOWN_FORWARD
const DOWN_BACK := ArcadeCpu.DOWN_BACK
const LP := ArcadeCpu.LP
const RP := ArcadeCpu.RP
const LK := ArcadeCpu.LK
const RK := ArcadeCpu.RK

# Move state and word bits.
const CROUCHING := StateBit.CROUCHING
const STANDING := StateBit.STANDING
const DOWN_STATE := StateBit.DOWN
const AIRBORNE := StateBit.AIRBORNE
const STATE_CHARGING := ArcadeCpu.STATE_BIT19
const STATE_SPECIAL := ArcadeCpu.STATE_BIT21
const STATE_RECOVERS := ArcadeCpu.STATE_BIT22
const WORD_LINKED := 0x80000           ## the attack word's bit that keeps a string counted

# Fixed values of the distance and angle tests.
const NEAR := ArcadeCpu.FAR_DISTANCE   ## beyond it nothing that comes reaches the CPU
const BREATH_DISTANCE := 7000
const NEUTRAL_GRACE := 0xB4            ## frames on the ground before every action is allowed
const NEUTRAL_MOVE_BLOCK := 0x10
const NEUTRAL_ATTACK_BLOCK := 0x32
const ALL_ACTIONS := 0x3F
const ACTIONS_MOVING := 7
const ACTIONS_ATTACKING := 0x38
const ACTION_STEP := 1
const ACTION_RISE := 2
const ACTION_ROLL := 4
const ACTION_APPROACH := 8
const ACTION_LOW := 0x10
const ACTION_SIDE_STEP := 0x20
const STAND_UP_CONDITION := 0x31
const YOSHIMITSU_STANCE_SLOT := 0x470
const OGRE_BREATH_SLOT := ArcadeCpu.OGRE_SLOT_BREATH
const OGRE_SWEEP_SLOT := ArcadeCpu.OGRE_SLOT_SWEEP
const OGRE_BREATH_DISTANCE := 2000
const JOINT_HIGH := -0xC1B             ## the opponent's joint above this: leave it alone
const GROUND_JOINT := 2                ## fighter +0x800: this joint's height
const WOBBLE := 0xC0
const FIXED_ONE := 4096
const THROW_FOLLOW_CHANCE := 0xB33
const COMING_FOREVER := 999
const COMING_PAST := 0x3E5
const COMING_FAR := 0x3E6
const COMING_FAR_LIMIT := 0x65
const STRING_ROWS := 4
const PLANNED_ROWS := 0x30
const LINK_ROWS := 10
const LINK_WINDOW := 0x3C
const RARE_AIR_START := 0xD
const LONG_POSE := 0xDC
const LONG_APPROACH := 0xFA
const LONG_KIND := 2
const HOOK_APPROACH := 0x10
const SIDE_APPROACH := 8
const ATTACK_HOLD := 0xC
const HIT_LEARN_GUARD := 10
const HIT_LEARN_PUNISH := 10
const HIT_LEARN_DUCK := 0x28
const HIT_LEARN_COUNTER := 0x14
const WHIFF_FRAMES := 0x1E

# The reaction codes of FUN_801CC4B8 (FUN_801CCF24 acts on them).
enum Reaction {
	NONE = 0, COUNTER = 1, DUCK = 2, EVADE = 4, SIDE_STEP = 5, BANK_COUNTER_A = 6, BANK_COUNTER_B = 7,
	PARRY_HIGH = 8, PARRY_LOW = 9, CROUCH = 10,
}
const BANK_RAVEN := 9                  ## the bank whose counter comes earlier
const GRAB_SLOT_A := 0x170
const GRAB_SLOTS_B := 0x167
const GRAB_SLOT_BANK_A := 0x15A
const GRAB_SLOT_BANK_B := 0x13B
const BANK_WITH_GRAB_A := 9
const BANK_WITH_GRAB_B := 0
const BANK_WITH_GRAB_C := 3
const BANK_JACK := 7                   ## FUN_801CAF94's bank that turns differently
const EVADE_STEP_BACK := 3
const EVADE_BACK_DASH := 4
const EVADE_WALK := 5
const EVADE_MARKED := 1
const EVADE_PAST := 2
const YOSHIMITSU_BANK := 4
const YOSHIMITSU_REACH := 300
const LOW_PUNISH_SLOT := 6

# FUN_801CB2F0's kinds of movement.
const MOVE_NONE := 0
const MOVE_DASH := 1
const MOVE_WALK := 2
const MOVE_RETREAT := 3
const MOVE_LONG_DASH := 4
const MOVE_LONG_WALK := 5
const MOVE_BACK_DASH := 6
const MOVE_SIDE_STEP := 8
const WAIT_LONG := 0x23

var cpu: ArcadeCpu
var r: ArcadeAiRecord


func _init(opponent: CpuOpponent) -> void:
	super(opponent)
	cpu = opponent as ArcadeCpu


## FUN_801C3634: (held pad, newly pressed pad) of CPU fighter `fighter`.
func update(fighter: FighterState) -> PackedInt32Array:
	cpu.select(fighter.index)
	r = cpu.r
	f = cpu.me
	o = cpu.opp
	_begin_frame()
	var step := _first_step()
	if step >= 0:
		cpu.last_step = step
	_finish_frame()
	var pressed := r.pad & (r.pad ^ r.prev_pad)
	r.prev_pad = r.pad
	return PackedInt32Array([r.pad, pressed])


func _begin_frame() -> void:
	r.pressed_move = null
	sm = f.pose_move
	om = o.pose_move
	my_frame = f.pose_frame
	my_first = sm.active_first
	my_last = sm.active_last
	op_frame = o.pose_frame
	op_first = om.active_first
	op_last = om.active_last
	if my_frame != r.pose_frame_seen:
		r.frame_count = (r.frame_count + 1) & 0xFFFF
	r.pose_frame_seen = my_frame
	r.own_word = sm.attack_word
	r.own_state = sm.state
	r.own_attack = sm.attack
	r.opp_word = om.attack_word
	r.opp_state = om.state
	r.opp_attack = om.attack


## FUN_801C3C74's chain: the first step that takes the frame.
func _first_step() -> int:
	if _step_script():
		return STEP_SCRIPT
	_refresh()
	if _step_throw():
		return STEP_THROW
	if _step_launched():
		return STEP_LAUNCHED
	if f.move_row != null:
		return STEP_PENDING_MOVE
	if _step_neutral():
		return STEP_NEUTRAL
	if _step_hook(r.hook_opponent):
		return STEP_HOOK_OPPONENT
	if _step_hook(r.hook_own):
		return STEP_HOOK_OWN
	if _step_hold_guard():
		return STEP_HOLD_GUARD
	if fight.attract != 0 and fight.frame_counter & 1 == r.slot:
		_hold_direction()
		return STEP_ATTRACT
	if _step_collect():
		return STEP_COLLECT
	if _step_special():
		return STEP_SPECIAL
	if _step_counter():
		return STEP_COUNTER
	if _step_react():
		return STEP_REACT
	if _step_strings():
		return STEP_STRINGS
	if _step_planned():
		return STEP_PLANNED
	if _step_links():
		return STEP_LINKS
	if _step_facing():
		return STEP_FACING
	if _step_attack():
		return STEP_ATTACK
	if _step_approach():
		return STEP_APPROACH
	if r.crouch_timer >= 0:
		r.pad = DOWN
	elif r.direction_hold >= 0:
		_hold_direction()
	else:
		r.pad = 0
	return STEP_IDLE


# ---- small tests ------------------------------------------------------------------------------

## rand() & 0xFFF below difficulty word `i`.
func _below(i: int) -> bool:
	return cpu.draw() < r.word(i)


func _hold_direction() -> void:
	r.pad = r.prev_pad & DIRECTIONS


func _rel() -> int:
	return cpu.rel_of(f)


func _opp_rel() -> int:
	return cpu.rel_of(o)


static func _span(value: int, count: int) -> bool:
	return value >= 0 and value < count


# ---- FUN_801C4058 -----------------------------------------------------------------------------

func _step_script() -> bool:
	if not r.script_pending():
		return false
	var step := r.script_steps[r.script_at]
	r.script_at += 1
	if r.script_at >= r.script_steps.size():
		r.script_at = -1
	r.pad = cpu.step_pad(step)
	return true


# ---- FUN_801C4898: what the frame's choices read ------------------------------------------------

func _refresh() -> void:
	r.filter_no_lows = false
	r.continuation = null
	if sm.flags & MoveFlag.BUFFER_INPUT == 0:
		r.no_strings = 0
	r.punish = r.parried
	r.throw_chance = r.throw_next
	r.parried = 0
	r.throw_next = 0
	if o.health <= o.health_max / 10:
		for i: int in [WORD_FILTER_POSTURE, WORD_FILTER_FAST, WORD_PUNISH, WORD_PUNISH_CAP]:
			r.params[i] = 0
	var unfocused := cpu.draw() >= r.word(WORD_FOCUS)
	if unfocused and _rel() > 0x1FFF and _opp_rel() < 0x6001 and r.reach_band < 3:
		r.punish = 1
	r.move_changed = 1 if sm != r.collected_move or my_frame < r.move_frame_seen else 0
	# The game compares the opponent's move with +0x264, which nothing writes: always changed.
	r.opp_move_changed = 1
	r.move_frames = r.move_frames + 1 if r.collected_move == sm else 0
	r.collected_move = sm
	r.move_frame_seen = my_frame
	if r.own_state & STATE_RECOVERS != 0:
		cpu.stop_approach()
	_count_attacks()
	_distance_bands()
	_opponent_attack()
	_guard_and_crouch()
	r.attacking = 1 if my_first != 0 else 0
	r.special_open = 1 if sm.state & STATE_SPECIAL != 0 and sm.attack_word & ArcadeCpu.HINT_SPECIAL != 0 \
		and my_frame <= my_last else 0


func _count_attacks() -> void:
	if my_first == 0:
		if r.own_word & WORD_LINKED == 0 and o.was_hit_this_move == 0:
			r.attacks_in_row = 0
	elif my_first == my_frame:
		r.attacks_in_row += 1
	if op_first == 0:
		if r.opp_word & WORD_LINKED == 0 and f.was_hit_this_move == 0:
			r.opp_string = -1
	elif op_first == op_frame:
		r.opp_string += 1


func _distance_bands() -> void:
	r.wobble_phase += fight.rng.next() & 0x3F
	r.wobble = FightMath.sin12(r.wobble_phase, fight.tables) * WOBBLE / FIXED_ONE
	var distance := fight.fighter_distance
	var v := distance - r.opp_bands[5] + r.wobble - 0x80
	r.distance_change = distance - r.prev_distance
	r.prev_distance = distance
	if v < r.own_bands[0]:
		if _pushed():
			r.band = 0
			if r.attacking == 0:
				r.wait -= 2
		else:
			r.band = 1
			if r.attacking == 0:
				r.wait -= 1
		r.far_count = 0
	elif v < r.own_bands[1]:
		r.band = 2
		r.far_count = 0
	elif v < r.own_bands[2]:
		r.band = 3
		r.far_count = 0
	elif v < r.own_bands[3]:
		r.band = 4
		r.far_count += 4 + cpu.random_below(2)
	else:
		r.band = 5
		r.far_count += 5 + cpu.random_below(3)
	if r.attacking == 0 or o.in_air != 0:
		r.wait -= 1
	var x := distance - r.own_bands[5] + r.wobble
	if r.distance_change < 0:
		x += r.distance_change
	r.reach_band = 1
	if x >= r.opp_bands[0] + 0x80:
		r.reach_band = 2
		if x >= r.opp_bands[1] + 0x100:
			r.reach_band = 3
			if x >= r.opp_bands[2] + 0x200:
				r.reach_band = 4
				if x >= r.opp_bands[3] + 0x280:
					r.reach_band = 5


func _pushed() -> bool:
	for fighter: FighterState in [f, o]:
		if fighter.body_push_x != 0 or fighter.body_push_y != 0 or fighter.body_push_z != 0:
			return true
	return false


func _opponent_attack() -> void:
	r.opp_unblockable = r.opp_unblockable + 1 if op_first == 0 and r.opp_state & STATE_CHARGING != 0 else 0
	r.opp_coming = 1 if r.opp_unblockable > 0 or (op_first != 0 and op_frame <= op_last + 1) else 0
	r.announced_frames = 0 if r.opp_coming == 0 or op_first - 3 <= op_frame else r.announced_frames + 1
	r.passed_frames = 0 if my_first == 0 or op_frame <= op_last + 1 else r.passed_frames + 1
	if r.opp_coming == 0:
		r.guard_delay = -1
	elif r.guard_delay > 0:
		r.guard_delay -= 1
	if r.opp_coming == 0 and r.opp_state & STATE_SPECIAL != 0:
		r.opp_coming = 1
	r.opp_charging = r.opp_charging + 1 if r.opp_state & STATE_CHARGING != 0 else 0
	r.opp_grabs = 1 if r.opp_word & GRAB != 0 and (op_first == 0 or op_frame <= op_last) else 0
	_until_active()
	var joint_y: int = o.body.joints[GROUND_JOINT].t[1]
	r.opp_high = 1 if joint_y < JOINT_HIGH else 0
	r.opp_joint_y = joint_y
	if _opp_rel() > 0x3000 or (r.opp_state & STATE_SPECIAL == 0 and r.opp_attack != AttackWord.UNBLOCKABLE \
			and r.opp_attack != AttackWord.UNBLOCKABLE_2):
		r.evasion = 0
	if r.whiff_timer >= 0 and r.reach_band < 2 and cpu.draw() >= r.word(WORD_FOCUS):
		r.evade_reason = 1
	r.opp_down = 1 if r.opp_state & (DOWN_STATE | StateBit.DOWN_REVERSED) != 0 and r.opp_state & 0xFFFF != StateWord.LAUNCHED \
		and o.in_air == 0 else 0
	r.vs_stance = 1 if o.bank_type == YOSHIMITSU_BANK and o.cur_slot == YOSHIMITSU_STANCE_SLOT else 0
	if r.vs_stance != 0:
		r.opp_string = -1


func _until_active() -> void:
	if r.opp_coming == 0 and r.opp_grabs == 0:
		r.opp_until = COMING_FOREVER
		r.evade_reason = 0
	elif op_first == 0:
		r.opp_until = om.bank.branches[om.branches][ROW_LAST] - op_frame + 1
	else:
		var value := COMING_PAST
		if op_frame <= op_last:
			r.opp_until = op_first - op_frame
			value = COMING_FAR
			if r.opp_until < COMING_FAR_LIMIT:
				return
		r.opp_grabs = 0
		r.opp_coming = 0
		r.opp_until = value


func _guard_and_crouch() -> void:
	r.guard_holds = 1 if _holds_guard() else 0
	if r.own_state & CROUCHING != 0:
		if r.crouching >= 1:
			r.crouch_timer -= 1
		elif sm.flags & MoveFlag.LAUNCH_ANGLE == 0:
			var a := fight.rng.next() & 7
			var b := fight.rng.next() & 0xF
			var c := fight.rng.next() & 7
			r.crouch_timer = a + b + 0x14 + c
	else:
		r.crouch_timer = -1


func _holds_guard() -> bool:
	if fight.fighter_distance > NEAR or r.vs_stance != 0:
		return false
	var s := r.own_state & 0xFFFF
	if r.opp_grabs != 0:
		return r.opp_attack != AttackWord.MID and (s == StateWord.CROUCH or s == StateWord.GUARD_LOW)
	if r.opp_coming == 0 or _rel() > 0x3000:
		return false
	match r.opp_attack:
		AttackWord.HIGH:
			return s == StateWord.CROUCH or s == StateWord.GUARD_LOW or s == StateWord.GUARD_HIGH
		AttackWord.UNBLOCKABLE_2:
			return s == StateWord.GUARD_LOW or s == StateWord.CROUCH
		AttackWord.MID:
			return s == StateWord.GUARD_HIGH
		AttackWord.LOW:
			return s == StateWord.GUARD_LOW
		AttackWord.MID_2:
			return s == StateWord.GUARD_LOW or s == StateWord.GUARD_HIGH
	return false


# ---- FUN_801C473C: throws ---------------------------------------------------------------------

func _step_throw() -> bool:
	if f.throw_state == 0:
		r.throw_move = null
		r.throw_steps = 0
		r.throw_press_frame = -1
		r.throw_row = -1
		return false
	cpu.stop_approach()
	var changed := sm != r.throw_move
	if f.throw_state < 1:
		if changed:
			r.throw_move = sm
			r.throw_steps -= 1
			if cpu.draw() >= r.word(WORD_THROW_ESCAPE):
				return true
			var command := cpu.throw_escape_command()
			if command != 0:
				cpu.press(command, null)
				return true
		r.pad = 0
		return true
	if changed:
		_next_throw_step()
	if my_frame == r.throw_press_frame:
		var row := sm.bank.branches[r.throw_row]
		cpu.press(row[ROW_COMMAND], cpu.slot_row(row[ROW_TARGET]))
	else:
		r.pad = 0
	return true


## FUN_801C4628: picks the follow-up of a multi-part throw and the frame to press it on.
func _next_throw_step() -> void:
	if r.throw_steps < 0 or r.throw_steps >= r.word(WORD_THROW_STEPS) - 1 or cpu.draw() >= THROW_FOLLOW_CHANCE:
		return
	var rows := cpu.throw_step_rows()
	if rows.is_empty():
		r.throw_steps = -1
		r.throw_press_frame = -1
		r.throw_row = -1
		return
	r.throw_move = sm
	r.throw_steps += 1
	r.throw_row = rows[cpu.random_below(rows.size())]
	r.throw_press_frame = sm.bank.branches[r.throw_row][ROW_FIRST] + 1


# ---- FUN_801CBD84: launched -------------------------------------------------------------------

func _step_launched() -> bool:
	if r.own_state & 0xFFFF != StateWord.LAUNCHED or my_first != 0:
		return false
	cpu.stop_approach()
	r.marked_count = 0
	r.collected_move = sm
	r.candidate_count = cpu.collect_current()
	if r.candidate_count < 1:
		r.pad = 0
	elif _below(WORD_STANCE_ESCAPE) and cpu.mark(cpu.p_stance_escape) > 0:
		r.parried = 1
		r.punish = 1
		r.wait = -1
		cpu.execute()
	elif cpu.draw() >= r.word(WORD_STANCE) or cpu.mark(cpu.p_stance_row) < 1:
		r.pad = 0
	else:
		cpu.execute()
	return true


# ---- FUN_801CBEF8: on the ground --------------------------------------------------------------

func _step_neutral() -> bool:
	if f.in_air != 0 or r.own_state & (DOWN_STATE | AIRBORNE) == 0:
		r.neutral_action = 0
		r.neutral_actions = 0
		return false
	r.neutral_frames = 0 if r.neutral_block < 0 else r.neutral_frames + 1
	if cpu.pose_has_condition(STAND_UP_CONDITION):
		r.neutral_action = 1
		r.cancel_wait -= 1
		if r.cancel_wait < 0:
			r.cancel_wait = r.word(WORD_HOLD + (fight.rng.next() & 3))
			r.pad = RP
		else:
			r.pad = 0
		return true
	r.marked_count = 0
	r.collected_move = sm
	r.candidate_count = cpu.collect_current()
	if r.candidate_count < 1:
		r.pad = 0
		return true
	r.neutral_action = 1
	cpu.stop_approach()
	r.move_block = NEUTRAL_MOVE_BLOCK
	r.neutral_actions += 1
	if r.neutral_actions < NEUTRAL_GRACE and _breath_coming():
		r.pad = 0
		return true
	var mask := ALL_ACTIONS if r.neutral_actions >= NEUTRAL_GRACE else _neutral_mask()
	if mask == 0:
		r.pad = 0
		return true
	var action := t.actions[cpu.random_below(t.actions.size())]
	while mask & action == 0:
		action = t.actions[cpu.random_below(t.actions.size())]
	match action:
		ACTION_STEP:
			r.pad = UP
			return true
		ACTION_RISE:
			r.pad = DOWN | LP if r.frame_count & 7 == 0 else LP
			return true
		ACTION_ROLL:
			r.pad = BACK
			return true
		ACTION_APPROACH:
			cpu.mark(cpu.p_approach)
		ACTION_LOW:
			cpu.mark(cpu.p_low)
		ACTION_SIDE_STEP:
			cpu.mark(cpu.p_side_step)
	if r.marked_count > 0:
		if cpu.execute() >= 0:
			r.neutral_block = NEUTRAL_ATTACK_BLOCK
		return true
	r.pad = UP if r.neutral_actions > NEUTRAL_GRACE - 1 and (r.frame_count >> 1) & 7 == 0 else 0
	return true


func _breath_coming() -> bool:
	var attack := (r.opp_state & STATE_SPECIAL != 0 and op_first == 0) \
		or (r.opp_attack == AttackWord.UNBLOCKABLE and r.opp_word & ArcadeCpu.HINT_SAFE == 0)
	return attack and op_frame < op_last and o.bank_type == ArcadeCpu.BANK_OGRE \
		and o.cur_slot == OGRE_BREATH_SLOT and fight.fighter_distance < OGRE_BREATH_DISTANCE


func _neutral_mask() -> int:
	if op_first == 0:
		return _neutral_mask_no_attack()
	if r.opp_until < 0xC and op_frame <= op_last:
		return _neutral_mask_vs_attack()
	if r.band < 2:
		r.neutral_action = 0
		return ACTIONS_ATTACKING if r.opp_state & STANDING != 0 else 0x28
	return 0


func _neutral_mask_no_attack() -> int:
	if r.band < 3:
		if r.frame_count & 1 != r.slot:
			return 0
		r.neutral_action = 0
		if r.wait < 0 and fight.rng.next() & 0x3F == 0:
			return ACTIONS_ATTACKING
		return ACTIONS_MOVING
	r.neutral_action = 0
	return ALL_ACTIONS if r.reach_band < 4 else ACTIONS_MOVING


func _neutral_mask_vs_attack() -> int:
	if r.opp_attack == AttackWord.LOW or r.opp_word & ArcadeCpu.HINT_SAFE != 0:
		if r.frame_count & 1 != r.slot:
			return 0
		r.neutral_action = 0
		if fight.rng.next() & 2 != 0:
			return ACTIONS_ATTACKING
		if om.air_first != 0 or _rel() > 0x4000 or r.opp_state & STATE_SPECIAL != 0:
			return ACTION_ROLL if fight.rng.next() & 0x3F == 0 else ACTION_RISE
		return ACTION_ROLL
	var mask := ACTION_STEP
	if r.reach_band < 3 and (r.reach_band < 2 or r.distance_change < 0xB):
		mask = ALL_ACTIONS if fight.rng.next() & 0xF != 0 else 0
	r.neutral_action = 0
	return mask


# ---- FUN_801CD708, FUN_801CD828: the character hooks --------------------------------------------

func _step_hook(hook: AiTables.Hook) -> bool:
	if r.move_block >= 0 or hook == AiTables.Hook.NONE or not _below(WORD_HOOKS):
		return false
	var result := cpu.run_hook(hook)
	if result == ArcadeCpu.HOOK_ACTED:
		return true
	if result == ArcadeCpu.HOOK_NOTHING:
		return false
	r.pad = result
	if result == FORWARD or result == BACK:
		cpu.set_approach(HOOK_APPROACH)
	return true


# ---- FUN_801CAEB4 -----------------------------------------------------------------------------

func _step_hold_guard() -> bool:
	if r.guard_delay < 0 and op_first != 0 and op_frame <= op_first - 0x1E:
		return false
	if r.guard_holds == 0:
		return false
	_hold_direction()
	return true


# ---- FUN_801C8178: the frame's candidates and the follow-up lists -------------------------------

func _step_collect() -> bool:
	var result := false
	r.marked_count = 0
	r.candidate_count = 0
	if r.move_changed != 0:
		r.collected_move = sm
		r.move_frame_seen = my_frame
		result = _collect_follow_ups()
	r.move_frame_seen = my_frame
	r.candidate_count = cpu.collect_all()
	if r.move_frames > LONG_POSE and cpu.mark(cpu.p_any) > 0:
		cpu.execute()
		result = true
	return result


## The lists a new move can follow up with; true while the CPU waits for their window.
func _collect_follow_ups() -> bool:
	if r.strings_on >= 1:
		r.strings = _string_rows()
		if r.strings.is_empty():
			r.strings_on = 0
			return false
	elif r.planned_on >= 1:
		r.planned = _planned_rows()
		if r.planned.is_empty():
			r.planned_on = 0
			return false
	elif r.special_open != 0:
		return false
	elif my_first == 0:
		r.links.clear()
		r.planned.clear()
		r.strings.clear()
		r.links_on = 0
		r.planned_on = 0
		r.strings_on = 0
		r.throw_list = 0
		return false
	else:
		r.links = _link_rows()
		if r.links.is_empty():
			r.links_on = 0
			return false
		_hold_direction()
		r.links_on += 1
		return true
	_hold_direction()
	return true


## FUN_801C7C4C: the rows into a move that buffers further input.
func _string_rows() -> PackedInt32Array:
	var rows := sm.bank.branches
	var out := PackedInt32Array()
	var i := sm.branches
	while rows[i][ROW_COMMAND] != CpuOpponent.END and out.size() < STRING_ROWS:
		if cpu.restriction_passes(rows[i][ROW_RESTRICTION]) \
				and cpu.slot_row(rows[i][ROW_TARGET]).flags & MoveFlag.BUFFER_INPUT != 0:
			out.append(i)
		i += 1
	return out


## FUN_801C7D50: the rows into a follow-up attack of a plan.
func _planned_rows() -> PackedInt32Array:
	var chance := fight.rng.next()
	var rows := sm.bank.branches
	var out := PackedInt32Array()
	var i := sm.branches
	while rows[i][ROW_COMMAND] != CpuOpponent.END and out.size() < PLANNED_ROWS:
		if cpu.restriction_passes(rows[i][ROW_RESTRICTION]) and _plans(cpu.slot_row(rows[i][ROW_TARGET]), chance):
			out.append(i)
		i += 1
	return out


func _plans(target: MoveRow, chance: int) -> bool:
	if r.opp_down != 0 and target.attack_word & GRAB != 0:
		return false
	if target.attack_word & HINT_SPECIAL == 0 and target.state & STATE_CHARGING == 0 \
			and (target.attack_word & GRAB == 0 or not _below(WORD_THROW_LIST)):
		return false
	if target.state & StateBit.NOT_AI_ATTACK != 0:
		return false
	if target.air_first != 0 and f.bank_type == ArcadeCpu.BANK_PAUL and chance & ArcadeCpu.DRAW_MASK >= RARE_AIR_START:
		return false
	return cpu.in_band(target)


## FUN_801C7F6C: the rows that follow the move on its own timing.
func _link_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	if r.link_skip != 0:
		r.link_skip = 0
		return out
	r.link_last = 0
	var rows := sm.bank.branches
	var i := sm.branches
	while rows[i][ROW_COMMAND] != CpuOpponent.END and out.size() < LINK_ROWS:
		var row := rows[i]
		if row[ROW_FIRST] == 1 and row[ROW_LAST] == row[ROW_ENTRY] and cpu.restriction_passes(row[ROW_RESTRICTION]):
			var target := cpu.slot_row(row[ROW_TARGET])
			if target.flags & MoveFlag.BUFFER_INPUT == 0 or cpu.draw() >= r.word(WORD_FOCUS):
				out.append(i)
				var last := row[ROW_LAST]
				if last < LINK_WINDOW and r.link_last < last:
					r.link_last = last
		i += 1
	return out


# ---- FUN_801C894C -----------------------------------------------------------------------------

func _step_special() -> bool:
	if r.special_open == 0 or r.candidate_count == 0 or r.opp_breath != 0:
		return false
	if r.opp_until < my_first - my_frame or r.band > 2 or f.facing_quadrant == 2:
		if cpu.mark(cpu.p_any) > 0 and cpu.execute() >= 0:
			r.wait = -1
	return true


# ---- FUN_801CCD14: an attack is coming ----------------------------------------------------------

func _step_counter() -> bool:
	if r.opp_coming == 0 or r.opp_string < 0 or r.reach_band >= 4:
		return false
	if (r.punish != 0 or _below(WORD_COUNTER)) and _span(r.opp_until - 2, 0x1C) \
			and cpu.mark(cpu.p_counter) > 0 and cpu.execute() >= 0:
		return true
	if r.attacking == 0 and _attack_blockable() and (r.evade_reason != 0 or _below(WORD_DUCK)):
		var n := _duck_marks()
		if n < 1 or cpu.execute() < 0:
			r.pad = _guard_pad()
		return true
	if _below(WORD_SIDE_STEP) and _span(r.opp_until - 9, 3) and _rel() < 0x4000 \
			and r.own_state & STATE_RECOVERS == 0 and r.band > 1:
		cpu.step_aside(ArcadeCpu.SIDE_STEP_AUTO)
		r.wait -= 10
		return true
	return false


## FUN_801CBEB8.
func _attack_blockable() -> bool:
	var word := r.opp_word & 0xFFFF
	return (word != 0 and word != AttackWord.UNBLOCKABLE) or r.opp_unblockable > 0


## FUN_801C88F8.
func _guard_pad() -> int:
	if f.facing_quadrant != 0:
		return 0
	cpu.stop_approach()
	return BACK if r.opp_attack == AttackWord.MID else DOWN_BACK


## FUN_801CD948.
func _walk_pad() -> int:
	cpu.stop_approach()
	return FORWARD if r.frame_count & 1 != r.slot else 0


## FUN_801C757C.
func _duck_marks() -> int:
	if fight.fighter_distance > NEAR:
		return 0
	var n := 0
	if r.opp_grabs != 0:
		n = cpu.mark(cpu.p_crouch) if r.opp_attack != AttackWord.MID else 0
		return n + cpu.mark(cpu.p_tap_back) if r.reach_band > 2 else n
	if r.opp_coming != 0:
		match r.opp_attack:
			AttackWord.MID_2:
				n = cpu.mark(cpu.p_guard_high) + cpu.mark(cpu.p_guard_low)
			AttackWord.LOW:
				n = cpu.mark(cpu.p_guard_low)
				if r.reach_band >= 3:
					n += cpu.mark(cpu.p_tap_back)
			AttackWord.MID:
				n = cpu.mark(cpu.p_guard_high)
			AttackWord.UNBLOCKABLE_2:
				n = cpu.mark(cpu.p_crouch)
				if r.reach_band >= 3:
					n += cpu.mark(cpu.p_tap_back)
			AttackWord.HIGH:
				var s := f.pose_move.state & 0xFFFF
				if s == StateWord.CROUCH or s == StateWord.GUARD_LOW:
					n = cpu.mark(cpu.p_crouch)
				else:
					n = cpu.mark(cpu.p_guard_high)
					if cpu.draw() % 0x32 == 0:
						n += cpu.mark(cpu.p_crouch)
					if r.reach_band >= 3:
						n += cpu.mark(cpu.p_tap_back)
	if r.distance_change < -0x46 and r.reach_band < 3:
		n = cpu.mark(cpu.p_tap_back)
	return n


# ---- FUN_801CC4B8, FUN_801CCF24: the reactions --------------------------------------------------

func _reaction() -> Reaction:
	if r.opp_string >= 0 or r.vs_stance != 0:
		return Reaction.NONE
	if r.guard_delay == 0 and r.attacking == 0:
		return Reaction.DUCK
	if r.evasion == 0 and (r.opp_coming == 0 or r.reach_band > 3):
		return Reaction.NONE
	if (op_first != 0 and op_last < op_frame) or o.facing_quadrant == 2:
		r.evasion = EVADE_PAST
	if r.evasion == 0 and (r.opp_attack == AttackWord.UNBLOCKABLE or r.opp_attack == AttackWord.UNBLOCKABLE_2 \
			or r.opp_state & STATE_SPECIAL != 0) and _below(WORD_HOOKS):
		r.evasion = EVADE_MARKED
	if r.guard_suspend < 0 and r.evasion != EVADE_PAST and r.evasion != 0:
		return Reaction.EVADE
	var bank := t.bank(f.bank_type)
	if _span(r.opp_until - 8, 2) and r.own_attack == 0 and f.in_air == 0 and bank.counter != 0 \
			and om.flags & MoveFlag.ALERT == 0 and o.in_air == 0 and cpu.coming_reaches(false) \
			and _below(WORD_BANK_COUNTER):
		return Reaction.BANK_COUNTER_A
	if f.bank_type == BANK_RAVEN and _span(r.opp_until - 0x16, 5) and r.own_attack == 0 and f.in_air == 0 \
			and cpu.coming_reaches(false) and _below(WORD_BANK_COUNTER):
		return Reaction.BANK_COUNTER_B
	if _span(r.opp_until - 4, 7) and r.own_attack == 0 and f.in_air == 0 and o.in_air == 0 \
			and cpu.coming_reaches(false) and _below(WORD_BANK_COUNTER):
		if (r.opp_attack == AttackWord.HIGH or r.opp_attack == AttackWord.MID or r.opp_attack == AttackWord.UNBLOCKABLE \
				or r.opp_attack == AttackWord.UNBLOCKABLE_2) and not bank.parry_high.is_empty():
			return Reaction.PARRY_HIGH
		if r.opp_attack == AttackWord.LOW and not bank.parry_low.is_empty():
			return Reaction.PARRY_LOW
	if r.opp_word & GRAB != 0:
		if _special_grab() and _below(WORD_HOOKS):
			return Reaction.COUNTER
		if r.opp_until < 0x1E and _below(WORD_GRAB_GUARD):
			r.evade_reason = 2
			return Reaction.DUCK
	if _attack_blockable():
		if r.guard_holds != 0 or r.attacking != 0:
			return Reaction.NONE
		if r.evade_reason != 0:
			return Reaction.DUCK
		if _below(WORD_GUARD) or (r.opp_unblockable > 0x1E and _below(WORD_GUARD_CAP)):
			r.evade_reason = 5
			return Reaction.DUCK
	return _reaction_late()


func _special_grab() -> bool:
	var slot := o.cur_slot
	return slot == GRAB_SLOT_A or _span(slot - GRAB_SLOTS_B, 2) \
		or (slot == GRAB_SLOT_BANK_A and (o.bank_type == BANK_WITH_GRAB_A or o.bank_type == BANK_WITH_GRAB_B)) \
		or (slot == GRAB_SLOT_BANK_B and o.bank_type == BANK_WITH_GRAB_C)


func _reaction_late() -> Reaction:
	if r.guard_delay > 8 and fight.rng.next() & 0x1F == 0:
		return Reaction.COUNTER
	if r.history_same != 0 and fight.rng.next() & 0xF == 0:
		return Reaction.COUNTER
	if ArcadeCpu.row_address(om) == r.history[0] and r.vs_stance == 0 and _below(WORD_PUNISH_CAP):
		return Reaction.COUNTER
	if r.vs_stance == 0 and _below(WORD_PUNISH):
		if r.opp_attack != AttackWord.HIGH or fight.rng.next() & 0x3F != 0:
			return Reaction.COUNTER
		return Reaction.CROUCH
	if r.opp_unblockable > 0x1E and _below(WORD_PUNISH_CAP):
		if r.opp_attack != AttackWord.HIGH or fight.rng.next() & 0x3F != 0:
			return Reaction.COUNTER
		return Reaction.CROUCH
	if _span(r.opp_until - 9, 3) and _rel() < 0x4000 and r.own_state & STATE_RECOVERS == 0:
		if r.reach_band == 2 and r.own_state & CROUCHING == 0 and f.in_air == 0 and r.attacking == 0 \
				and r.opp_attack == AttackWord.HIGH and _below(WORD_SIDE_STEP):
			return Reaction.SIDE_STEP
	return Reaction.NONE


func _step_react() -> bool:
	var n := 0
	var result := false
	match _reaction():
		Reaction.NONE:
			return false
		Reaction.COUNTER:
			var pred: Callable = cpu.p_fast
			if r.opp_coming != 0:
				var at_range := r.opp_attack == AttackWord.UNBLOCKABLE or r.opp_attack == AttackWord.UNBLOCKABLE_2 \
					or r.opp_state & (STATE_SPECIAL | CROUCHING) != 0
				pred = cpu.p_counter_no_high if at_range else cpu.p_counter
			n = cpu.mark(pred)
			if r.opp_attack == AttackWord.HIGH:
				n += cpu.mark(cpu.p_crouching_attack)
			result = n > 0
		Reaction.DUCK:
			n = _duck_marks()
			result = true
			if n < 1:
				r.pad = _guard_pad()
				return true
		Reaction.EVADE:
			return _evade_step()
		Reaction.SIDE_STEP:
			cpu.step_aside(ArcadeCpu.SIDE_STEP_AUTO)
			r.wait -= 10
			return true
		Reaction.BANK_COUNTER_A:
			n = cpu.mark(cpu.p_counter_slot)
			result = n > 0
		Reaction.BANK_COUNTER_B:
			n = cpu.mark(cpu.p_counter_slot_b)
			result = n > 0
		Reaction.PARRY_HIGH:
			cpu.start_steps(t.bank(f.bank_type).parry_high)
			return true
		Reaction.PARRY_LOW:
			cpu.start_steps(t.bank(f.bank_type).parry_low)
			return true
		Reaction.CROUCH:
			n = cpu.mark(cpu.p_crouch)
			if n > 0:
				result = true
				r.parried = 1
				r.wait = -1
	if result and n > 0 and cpu.execute() >= 0:
		cpu.stop_approach()
	return result


## FUN_801CCF24's evasion, by the state of +0xFC.
func _evade_step() -> bool:
	if r.opp_high != 0:
		return false
	if r.evasion == EVADE_MARKED:
		if r.band < 3 and cpu.draw() >= r.word(WORD_FOCUS):
			r.evasion = EVADE_STEP_BACK
		else:
			r.evasion = t.evasion_states[cpu.random_below(t.evasion_states.size())]
	var distance := fight.fighter_distance
	if o.bank_type == YOSHIMITSU_BANK:
		distance -= YOSHIMITSU_REACH
	if r.evasion != EVADE_MARKED and r.evasion != EVADE_PAST and distance > NEAR:
		r.evasion = 0
		r.pad = 0
		return true
	match r.evasion:
		EVADE_STEP_BACK:
			return _evade_stepping_back(distance)
		EVADE_BACK_DASH:
			return _evade_back_dash(distance)
		EVADE_WALK:
			if r.own_state & STATE_RECOVERS == 0 and fight.rng.next() & 7 == 0 and r.opp_until > 6:
				if _opp_rel() > 0x3FFF:
					r.evasion = EVADE_STEP_BACK
				cpu.step_aside(ArcadeCpu.SIDE_STEP_AUTO)
				return true
			r.pad = FORWARD
	return false


func _evade_stepping_back(distance: int) -> bool:
	cpu.stop_approach()
	if op_first != 0 and op_last < op_frame:
		return false
	if r.opp_until < 0x1D:
		if r.opp_until < 9:
			r.pad = BACK if distance <= NEAR and _opp_rel() < 0x4000 else 0
			return true
		if distance <= NEAR:
			if r.band > 2:
				if _opp_rel() > 0x3FFF:
					return false
				r.evasion = EVADE_BACK_DASH
				r.pad = BACK
				return true
			if cpu.mark(cpu.p_attack_no_high) > 0:
				r.wait = -1
				return false
		r.pad = 0
		return true
	if r.band > 2:
		r.pad = _walk_pad()
		r.wait = fight.rng.next() & 0xF
		return true
	if cpu.mark(cpu.p_attack_no_high) > 0:
		return false
	return true


func _evade_back_dash(distance: int) -> bool:
	cpu.stop_approach()
	if _opp_rel() < 0x4001 or r.reach_band < 2:
		if distance <= NEAR:
			if r.opp_until < 9 or r.band > 1:
				cpu.start_steps(t.back_dash)
				return true
			if cpu.mark(cpu.p_attack_no_high) > 0:
				r.wait = -1
				return false
		r.pad = 0
	else:
		r.pad = FORWARD
	return true


# ---- FUN_801C9DAC, FUN_801CA204, FUN_801CA6A8: the follow-up lists ------------------------------

func _step_strings() -> bool:
	if r.strings_on < 1:
		return false
	var open := cpu.open_rows(r.strings)
	if not open.is_empty() and _rel() < 0x2000:
		if cpu.draw() >= r.word(WORD_STRINGS_CHANCE):
			_hold_direction()
			return true
		var row := sm.bank.branches[open[cpu.random_below(open.size())]]
		var target := cpu.slot_row(row[ROW_TARGET])
		if target.active_first == 0:
			_press_row(row, target)
			return true
		r.strings_on += 1
		if r.strings_on <= r.word(WORD_STRINGS_MAX) and target.active_first <= r.opp_until:
			_press_row(row, target)
			return true
	r.strings_on = 0
	r.strings.clear()
	r.no_strings = 1
	return false


func _press_row(row: PackedInt32Array, target: MoveRow) -> void:
	cpu.press(row[ROW_COMMAND], target)
	cpu.after_press(row)


func _step_planned() -> bool:
	if r.planned_on < 1:
		return false
	var open := cpu.open_rows(r.planned)
	if open.is_empty() or _rel() > 0x1FFF:
		r.planned_on = 0
		r.planned.clear()
		return false
	var row := sm.bank.branches[open[cpu.random_below(open.size())]]
	var target := cpu.slot_row(row[ROW_TARGET])
	if target.attack_word & HINT_SPECIAL != 0:
		r.planned_on += 1
	if target.active_first == 0 or (target.active_first <= r.opp_until and r.planned_on <= r.word(WORD_ATTACKS_A) \
			and r.attacks_in_row < r.attack_limit and not _distracted(target)):
		if target.state & STATE_CHARGING == 0 and cpu.draw() >= r.word(WORD_PLANNED_KEEP):
			r.planned_on = 0
			r.planned.clear()
		_press_row(row, target)
		return true
	r.planned_on = 0
	r.planned.clear()
	_hold_direction()
	return true


## FUN_801C9CB4: a follow-up the CPU gives up.
func _distracted(target: MoveRow) -> bool:
	if _below(WORD_FOCUS) or fight.rng.next() & 0x1F == 0:
		return false
	return (r.band < 2 and r.whiff_timer >= 0) or r.band > 3 \
		or (r.opp_state & DOWN_STATE != 0 and o.in_air == 0 and target.attack_word & HINT_SAFE == 0) \
		or _rel() > 0x3800


func _step_links() -> bool:
	if r.links_on < 0:
		return false
	var open := cpu.open_rows(r.links)
	if not open.is_empty() and _rel() < 0x2000:
		if cpu.draw() >= r.word(WORD_LINKS_CHANCE):
			_hold_direction()
			return true
		var row := sm.bank.branches[open[cpu.random_below(open.size())]]
		var target := cpu.slot_row(row[ROW_TARGET])
		if target.active_first == 0 or (r.links_on < r.word(WORD_ATTACKS_B) and r.attacks_in_row < r.attack_limit \
				and target.active_first <= r.opp_until and not _distracted(target)):
			_press_row(row, target)
			return true
	r.links_on = 0
	r.links.clear()
	return false


# ---- FUN_801CAF94: keep facing the opponent ------------------------------------------------------

func _step_facing() -> bool:
	if r.attacking != 0:
		return false
	if om.air_first != 0 and r.reach_band < 2 and _below(WORD_AIR_RETREAT):
		if _rel() < 0x4000 and r.distance_change < -10:
			r.pad = DOWN_FORWARD
			return true
		if om.air_last - op_frame > 0x14 and _rel() > 0x4000:
			r.pad = FORWARD
			return true
	if _rel() < 0x6001 or r.reach_band > 1:
		return _turn_towards()
	if o.in_air != 0:
		r.pad = 0
	elif r.opp_down != 0:
		r.pad = LK | DOWN if r.frame_count & 1 == r.slot else RK | DOWN
	else:
		if cpu.draw() >= r.word(WORD_FOCUS):
			r.wait = -2
			return false
		if f.bank_type == BANK_JACK:
			r.pad = BACK if _rel() > 0x3FFF else FORWARD
			return true
		r.pad = FORWARD
	return true


func _turn_towards() -> bool:
	if _rel() < 0x1001 or _rel() <= fight.rng.next() or _below(WORD_FOCUS):
		return false
	cpu.set_approach(SIDE_APPROACH)
	if f.bank_type == BANK_JACK:
		r.pad = BACK if _rel() > 0x3FFF else FORWARD
		return true
	if r.opp_coming == 0 or fight.rng.next() & 7 != 0:
		r.pad = BACK if r.reach_band < 3 and fight.rng.next() & 1 != 0 else FORWARD
	else:
		r.pad = _guard_pad()
	return true


# ---- FUN_801C9854, FUN_801C8A18: the attack -------------------------------------------------------

func _step_attack() -> bool:
	if r.crouch_attack_hold >= 1:
		r.crouch_attack_hold -= 1
		_hold_direction()
		return true
	if r.neutral_cooldown >= 5:
		_hold_direction()
		return true
	if r.band > 3 or r.opp_high != 0 or r.attacks_in_row >= r.attack_limit:
		return false
	if r.band > 2 and cpu.random_below(0xC) != 0:
		return false
	if r.band > 1 and cpu.random_below(8) == 0:
		return false
	if r.approach_kind != 0:
		if r.guard_delay > 0 or (r.opp_coming != 0 and r.reach_band < 4):
			r.pad = BACK
			return true
		if r.opp_state & DOWN_STATE != 0 and cpu.random_below(0x1000) < 0x100:
			return false
	var n := _choose_attack(r.wait)
	if n == 0 and r.reach_band > 2 and f.power_timer == 0 and f.health <= f.health_max / 10 \
			and fight.rng.next() & 3 == 0 and _below(WORD_PUNISH):
		n = cpu.mark(cpu.p_power)
	if n < 0:
		cpu.stop_approach()
		return true
	var i := cpu.execute()
	if i < 0:
		return false
	cpu.stop_approach()
	var target := cpu.cand_target[i]
	if fight.attract == 0 and target.flags & MoveFlag.BUFFER_INPUT != 0:
		r.strings_on = 1
	elif (r.own_state & STATE_CHARGING != 0 and fight.rng.next() & 0x3F < 0x20) \
			or (target.state & STATE_CHARGING != 0 and fight.rng.next() & 0x3F < 0x30):
		r.planned_on = 1
	var state := r.pressed_move.state & 0xFFFF if r.pressed_move != null else 0
	if state == StateWord.CROUCH or state == StateWord.GUARD_LOW:
		r.crouch_attack_hold = ATTACK_HOLD
	if target.active_first != 0 or target.state & STATE_CHARGING != 0:
		r.last_attack = target
	return true


func _choose_attack(wait: int) -> int:
	if r.no_strings != 0:
		cpu.unmark(cpu.p_string_start)
	if r.announced_frames >= 0x1A and r.guard_delay < 0 and r.guard_holds == 0:
		r.guard_delay = maxi(r.opp_until - ((fight.rng.next() & 7) + 4), 3)
	if r.guard_delay > 0:
		return 0
	if r.punish != 0 or r.throw_chance != 0 \
			or (r.announced_frames > 0x19 and cpu.draw() >= r.word(WORD_FOCUS) / 2) \
			or (_span(r.passed_frames - 1, 0x13) and cpu.draw() >= r.word(WORD_FOCUS)):
		wait = -1
	if _below(WORD_AIR_RETREAT) and o.in_air != 0 and r.opp_state & 0xFFFF != StateWord.LAUNCHED \
			and om.air_first + (om.air_last - om.air_first) / 2 <= op_frame and op_frame <= om.air_last \
			and _rel() < 0x4001 and r.band == 2:
		r.wait = -1
	if o.cur_slot == LOW_PUNISH_SLOT and r.band < 3 and _below(WORD_PUNISH):
		r.wait -= 2
	var tries := r.word(WORD_THROW_TRY)
	if r.opp_state & 0x605 != 0 or o.in_air != 0 or o.about_to_hit != 0 or r.opp_until < 10:
		tries = 0
		r.throw_chance = 0
	if r.opp_down != 0 and r.vs_stance == 0:
		return _choose_vs_down(wait)
	if r.opp_state & 0xFFFF == StateWord.LAUNCHED and _below(WORD_VS_LAUNCHED) and r.opp_state & STANDING == 0:
		return _choose_vs_launched()
	if r.air_cooldown >= 0:
		var n := cpu.mark(cpu.p_air_attack)
		if n >= 1:
			r.air_cooldown = -1
		return n
	if r.opp_unblockable != 0 or ((r.opp_coming != 0 or r.opp_grabs != 0) and r.vs_stance == 0):
		if r.punish != 0 or _below(WORD_PUNISH):
			return _counter_marks()
		if wait > 0:
			return 0
		return cpu.mark(cpu.p_attack_no_high if r.opp_state & CROUCHING != 0 else cpu.p_approach)
	return _choose_plain(wait, tries)


func _choose_vs_down(wait: int) -> int:
	if r.attacking != 0:
		return 0
	if cpu.draw() >= r.word(WORD_FOCUS):
		wait = -1
	if _rel() > 0x4000 and fight.rng.next() & 7 == 0:
		var n := cpu.mark(cpu.p_not_ai_attack)
		if n > 0:
			return n
	if wait >= 0:
		return 0
	var choice := cpu.draw()
	if choice < 0x334:
		return cpu.mark(cpu.p_stance)
	if choice < 0x3AF:
		cpu.step_aside(fight.rng.next() & 1)
		return -1
	if choice < 0x6E2:
		return cpu.mark(cpu.p_ground_low)
	if choice < 0x75D and r.own_state & CROUCHING == 0:
		return cpu.mark(cpu.p_crouch)
	if choice < 0x829:
		return cpu.mark(cpu.p_tap_back)
	if _span(r.band - 2, 2) and choice < 0x9C3:
		cpu.start_steps(t.wake_up)
		return -1
	return cpu.mark(cpu.p_ground_any_low)


func _choose_vs_launched() -> int:
	var n := 0
	if r.band < 3:
		if r.band > 1:
			n = cpu.mark(cpu.p_safe_still if fight.rng.next() & 0xF != 0 else cpu.p_tap_forward)
	elif r.distance_change < 0x33 and fight.rng.next() & 7 == 0:
		n = cpu.mark(cpu.p_safe_still)
	else:
		n = cpu.mark(cpu.p_tap_forward)
		if n > 0:
			cpu.set_long_approach(LONG_APPROACH, LONG_KIND)
	if r.band > 3 or r.opp_high != 0 or _below(WORD_FOCUS):
		return n
	r.wait = -1
	var no_high := o.in_air == 0 and fight.rng.next() & 0x3F < 0x20 and not r.filter_no_lows
	return n + cpu.mark(cpu.p_level_no_high if no_high else cpu.p_level)


func _choose_plain(wait: int, tries: int) -> int:
	if wait > 0:
		if r.band > 2 or cpu.draw() > 3 or r.own_state & CROUCHING != 0:
			return 0
		return maxi(cpu.mark(cpu.p_crouch), 0)
	if r.neutral_cooldown >= 0:
		var n := cpu.mark(cpu.p_neutral_follow)
		r.neutral_cooldown = -1
		return n
	if r.throw_chance != 0 or cpu.draw() < tries:
		var n := _throw_marks()
		if n != 0:
			return n
	if _start_setup():
		return -1
	if r.band < 3 and fight.rng.next() & 0x3F < 0xE and f.in_air == 0 and r.own_state & CROUCHING == 0:
		return cpu.mark(cpu.p_crouch)
	if fight.rng.next() & 0x3F <= 0x1F:
		return cpu.mark(cpu.p_side_step if fight.rng.next() & 1 != 0 else cpu.p_level)
	if r.neutral_cooldown < 0 and r.air_cooldown < 0 and r.own_state & CROUCHING == 0 and f.in_air == 0 \
			and cpu.draw() < 0x200:
		var n := cpu.mark(cpu.p_crouch)
		if n > 0:
			r.neutral_cooldown = 0x12
			r.wait = -1
			return n
	var filtered := _choose_filtered()
	return filtered + cpu.mark(cpu.p_side_step)


func _choose_filtered() -> int:
	if _below(WORD_FILTER_POSTURE):
		return cpu.mark(cpu.p_vs_posture)
	if _below(WORD_FILTER_FAST):
		return cpu.mark(cpu.p_fast)
	if r.opp_state & CROUCHING != 0 and cpu.draw() >= r.word(WORD_FOCUS):
		return cpu.mark(cpu.p_attack_no_high)
	if fight.rng.next() & 0x3F < 10:
		return cpu.mark(cpu.p_plain)
	if f.in_air == 0 and r.air_cooldown < 0 and cpu.random_below(0x1000) <= 0x1FF:
		var n := cpu.mark(cpu.p_air_start)
		if n >= 1:
			var a := cpu.random_below(4)
			var b := cpu.random_below(4)
			var c := cpu.random_below(4)
			r.air_cooldown = a + b + c + 1
			return n
	return cpu.mark(cpu.p_still if cpu.random_below(0x1000) < 10 else cpu.p_approach)


## The setups of the fighter's bank: a script when its draw passes and the branch is open.
func _start_setup() -> bool:
	var setups := t.bank(f.bank_type).setups
	if setups.is_empty() or r.setup_cooldown >= 0 or r.attacking != 0 or r.own_state & CROUCHING != 0 \
			or f.cur_slot == setups[0].slot or _rel() >= 0x2001 or f.in_air != 0 or r.band >= 3 or r.opp_down != 0:
		return false
	var chance := cpu.draw()
	for setup: AiTables.Setup in setups:
		if chance <= setup.chance:
			if not cpu.branch_open(setup.slot):
				return false
			cpu.start_steps(setup.steps)
			r.planned_on = 1
			r.setup_cooldown = (fight.rng.next() & 0xF) + 0x1C
			return true
	return false


## FUN_801C7810.
func _throw_marks() -> int:
	if r.band >= 2:
		return 0
	if _below(WORD_THROW_LIST):
		var n := cpu.mark(cpu.p_grab)
		if n > 0:
			r.throw_list = 1
		return n
	return cpu.mark(cpu.p_grab_plain)


## FUN_801C78E8.
func _counter_marks() -> int:
	var n := 0
	var chance := (fight.rng.next() >> 1) & ArcadeCpu.DRAW_MASK
	if (r.band == 2 and chance < 0x20) or (r.band == 3 and chance < 0x400):
		n = cpu.mark(cpu.p_tap_forward)
	return n + cpu.mark(cpu.p_counter_no_high if r.opp_state & CROUCHING != 0 else cpu.p_counter)


# ---- FUN_801CB698, FUN_801CB2F0: moving -----------------------------------------------------------

func _in_breath() -> bool:
	return r.opp_breath != 0 and fight.fighter_distance <= BREATH_DISTANCE


func _step_approach() -> bool:
	if r.move_block >= 0:
		return false
	if r.approach < 0:
		if r.attacking != 0 or r.crouch_timer >= 0 or r.direction_hold >= 0 or r.air_cooldown >= 0:
			return false
	elif not _in_breath():
		if r.band > 0 and (_below(WORD_FOCUS) or not cpu.coming_reaches(true)):
			return _keep_approaching()
		cpu.stop_approach()
	else:
		cpu.stop_approach()
	if r.approach_hold >= 0 or r.direction_hold >= 0:
		return false
	match _movement_kind():
		MOVE_DASH:
			if cpu.mark(cpu.p_tap_forward) > 0:
				cpu.set_approach(0)
				return cpu.execute() >= 0
			return _walk_forward(_walk_frames())
		MOVE_WALK:
			return _walk_forward(_walk_frames())
		MOVE_RETREAT:
			return _retreat()
		MOVE_LONG_DASH:
			if cpu.mark(cpu.p_tap_forward) > 0:
				cpu.set_long_approach(LONG_APPROACH, LONG_KIND)
				return cpu.execute() >= 0
			return _walk_forward(cpu.random_below(0x14) + 0x28)
		MOVE_LONG_WALK:
			return _walk_forward(cpu.random_below(0x14) + 0x28)
		MOVE_BACK_DASH:
			if cpu.mark(cpu.p_tap_back) > 0:
				r.approach_hold = ArcadeCpu.LONG_APPROACH_HOLD
				return cpu.execute() >= 0
			return _retreat()
		MOVE_SIDE_STEP:
			if r.reach_band > 2 or r.opp_until > 10:
				cpu.step_aside(ArcadeCpu.SIDE_STEP_AUTO)
			return cpu.execute() >= 0
	return false


func _keep_approaching() -> bool:
	if r.approach_kind == 2:
		if _in_breath():
			cpu.stop_approach()
			r.pad = BACK
		elif r.reach_band < 3 and cpu.draw() < 0x20:
			cpu.stop_approach()
			r.pad = BACK
		else:
			r.pad = FORWARD
		return true
	if r.wait < 0x24 and r.reach_band == 2 and fight.rng.next() & 0xF == 0 and cpu.mark(cpu.p_tap_forward) > 0 \
			and cpu.execute() >= 0:
		cpu.set_approach(0)
		return true
	_hold_direction()
	return true


func _walk_frames() -> int:
	if r.band < 0:
		return cpu.random_below(0xF) + 0xF
	if r.band < 3:
		return cpu.random_below(8) + 4
	if r.band == 3:
		return cpu.random_below(10) + 10
	return cpu.random_below(0xF) + 0xF


func _walk_forward(frames: int) -> bool:
	cpu.set_approach(frames)
	r.pad = DOWN_FORWARD if r.crouching > 0 else FORWARD
	return true


func _retreat() -> bool:
	cpu.set_approach(cpu.random_below(5) + 0x14)
	r.pad = DOWN_BACK if r.crouching > 0 else BACK
	return true


func _movement_kind() -> int:
	var u := cpu.random_below(0x1000)
	if r.opp_breath != 0:
		return MOVE_NONE
	var kind := MOVE_NONE
	if r.wait > WAIT_LONG:
		kind = _kind_by_reach(u)
		if (kind == MOVE_RETREAT or kind == MOVE_BACK_DASH) and cpu.draw() >= r.word(WORD_KEEP_RETREAT):
			kind = MOVE_NONE
	else:
		kind = _kind_by_band(u)
	if (kind == MOVE_RETREAT or kind == MOVE_BACK_DASH) \
			and (r.opp_state & STATE_CHARGING != 0 or r.opp_attack != 0) and _below(WORD_FOCUS):
		return MOVE_NONE
	return kind


func _kind_by_reach(u: int) -> int:
	match r.reach_band:
		0, 1:
			if u < 0x199:
				return MOVE_BACK_DASH
			return MOVE_RETREAT if u < 0x333 else MOVE_NONE
		2:
			if u <= 0x27:
				return MOVE_WALK
			return MOVE_RETREAT if u < 0x170 else MOVE_NONE
		3:
			if u < 0x1EB:
				return MOVE_WALK
			if u < 0x214:
				return MOVE_LONG_WALK
			if u < 0x218:
				return MOVE_RETREAT
			if u < 0x22D:
				return MOVE_DASH
			return MOVE_SIDE_STEP if u < 0x241 and r.own_state & STANDING != 0 else MOVE_NONE
		4:
			if u < 0x80:
				return MOVE_WALK
			if u < 0x90:
				return MOVE_LONG_WALK
			if u < 0xC0:
				return MOVE_SIDE_STEP
			return MOVE_DASH if u < 0x3C0 else MOVE_NONE
		5:
			if r.far_count >= 0x2D1 or r.opp_down != 0 or u <= 0x50:
				return MOVE_LONG_DASH
			if u < 0xCC:
				return MOVE_WALK
			if u < 0x400:
				return MOVE_DASH
			return MOVE_LONG_WALK if u < 0x5EB else MOVE_NONE
	return MOVE_NONE


func _kind_by_band(u: int) -> int:
	match r.band:
		0, 1:
			return MOVE_RETREAT if u <= 0x13 else MOVE_NONE
		2:
			if u < 0x7A:
				return MOVE_LONG_WALK
			if u < 0x1EB:
				return MOVE_DASH
			if u > 0x213:
				return MOVE_SIDE_STEP if u < (r.word(WORD_SIDE_STEP) << 12) / 1000 else MOVE_NONE
			return MOVE_RETREAT
		3:
			if u <= 0x665:
				return MOVE_WALK
			return MOVE_DASH if u < 0xB33 else MOVE_NONE
		4:
			if u <= 0xCB:
				return MOVE_WALK
			return MOVE_LONG_DASH if u < 0x599 else MOVE_DASH
		5:
			return MOVE_LONG_DASH if r.far_count > 0x2D0 or r.opp_down != 0 or u < 0x11E else MOVE_DASH
	return MOVE_NONE


# ---- FUN_801C3730: the frame's end --------------------------------------------------------------

func _finish_frame() -> void:
	r.crouching = 1 if r.own_state & CROUCHING != 0 and r.own_state & (DOWN_STATE | StateBit.DOWN_REVERSED) == 0 else 0
	if r.pressed_move != null and r.direction_hold < 0 and r.pressed_move.air_first != 0:
		r.direction_hold = r.pressed_move.air_first
	if r.direction_hold >= 0:
		r.direction_hold -= 1
	r.approach = _count_down(r.approach)
	r.approach_hold = _count_down(r.approach_hold)
	r.whiff_timer = _count_down(r.whiff_timer)
	r.air_cooldown = _count_down(r.air_cooldown)
	r.neutral_cooldown = _count_down(r.neutral_cooldown)
	r.setup_cooldown = _count_down(r.setup_cooldown)
	r.move_block = _count_down(r.move_block)
	r.guard_suspend = _count_down(r.guard_suspend)
	r.neutral_block = _count_down(r.neutral_block)
	r.coming_seen = r.opp_coming
	r.opp_breath = 1 if o.bank_type == ArcadeCpu.BANK_OGRE \
		and (o.cur_slot == OGRE_BREATH_SLOT or o.cur_slot == OGRE_SWEEP_SLOT) else 0
	_track_guard()
	if f.got_hit != 0:
		cpu.stop_approach()
		r.links_on = 0
		r.strings_on = 0
		r.planned_on = 0
		r.throw_list = 0
	if f.whiffed != 0 and r.reach_band < 3:
		r.whiff_timer = WHIFF_FRAMES
	if o.whiffed != 0 and r.band < 2 and _below(WORD_PUNISH):
		r.wait -= 3
	if cpu.draw() >= r.word(WORD_FOCUS) and f.health < r.health_seen:
		r.wait -= 3
		# The game shifts its hit history through +0x274, so the "in Ogre's breath" flag read by the
		# next frame's steps becomes a move's address here (docs: game-bugs, arcade AI).
		r.opp_breath = r.history[2]
		r.history[2] = r.history[1]
		r.history[1] = r.history[0]
		r.history[0] = ArcadeCpu.row_address(om)
		r.history_same = 1 if r.history[0] == r.history[1] and r.history[1] == r.history[2] else 0
	r.health_seen = f.health
	if f.got_hit != 0 and fight.attract == 0:
		cpu.stop_approach()
		r.raise_word(WORD_GUARD, HIT_LEARN_GUARD, WORD_GUARD_CAP)
		r.raise_word(WORD_PUNISH, HIT_LEARN_PUNISH, WORD_PUNISH_CAP)
		if r.opp_string > 0:
			r.raise_word(WORD_DUCK, HIT_LEARN_DUCK, WORD_DUCK_CAP)
			r.raise_word(WORD_COUNTER, HIT_LEARN_COUNTER, WORD_COUNTER_CAP)


static func _count_down(value: int) -> int:
	return value - 1 if value >= 0 else value


func _track_guard() -> void:
	var s := r.own_state & 0xFFFF
	var guarding := 1 if s == StateWord.GUARD_HIGH or s == StateWord.GUARD_LOW else 0
	if r.guarding == 0:
		r.guarding = guarding
		r.guard_memory = 0
	else:
		r.guarding = guarding
		if guarding == 0 and r.guard_memory != 0:
			r.guard_memory = 0
