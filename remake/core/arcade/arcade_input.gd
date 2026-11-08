class_name ArcadeInput
## The arcade's panels and a fighter's input state: FUN_8018CD30 (the panels), FUN_8018E0DC /
## FUN_8018B61C (the source of a fighter's input), FUN_8018E220 (the history and the command buffer),
## FUN_8018E000 (the clear) and FUN_8018B710 (the taps).

const NEUTRAL := 5
const DIRECTIONS := 0x3C00          ## panel bits, mapped by the table at 0x8001095C
const LP := 0x200
const RP := 0x100
const LK := 0x40
const RK := 0x20
const STICK_SIDES := 2
const NO_CONTROL := -1              ## fighter +0x34A
const HISTORY := 60
const MERGE_FRAMES := 3
const MAX_COMMANDS := 9
const BOTH_PUNCHES := FighterInput.HIST_LP | FighterInput.HIST_RP
## The low half of each fighter record's address, which FUN_8018E220 leaves in $t0 (see `latch_taps`).
const RECORD_ADDRESS_LOW: Array[int] = [0xE154, 0xFC38]


const PANEL_START := 0x8000
const PANEL_UP := 0x2000
const PANEL_DOWN := 0x1000
const PANEL_LEFT := 0x800
const PANEL_RIGHT := 0x400
## The panel's bit of a pad's button: the PlayStation version's layout of the same four buttons.
const PANEL_OF_PAD := {
	PadState.START: PANEL_START,
	PadState.UP: PANEL_UP,
	PadState.DOWN: PANEL_DOWN,
	PadState.LEFT: PANEL_LEFT,
	PadState.RIGHT: PANEL_RIGHT,
	PadState.SQUARE: LP,
	PadState.TRIANGLE: RP,
	PadState.CROSS: LK,
	PadState.CIRCLE: RK,
}


## The panel word (FUN_8018CD30, 1 = pressed) of a pad's physical word.
static func panel_word(pad: int) -> int:
	var word := 0
	for bit: int in PANEL_OF_PAD:
		if pad & bit != 0:
			word |= PANEL_OF_PAD[bit] as int
	return word


## The panels of one frame: per player the held word and its new presses.
class Panels:
	const REPEAT_BITS := 16
	const REPEAT_FROM := 0x14

	var held := PackedInt32Array([0, 0])       ## 0x8021FBF4, 0x8021FBF8
	var pressed := PackedInt32Array([0, 0])    ## 0x8021FC90
	var previous := PackedInt32Array([0, 0])   ## 0x8021F058: the word a fighter's input last saw
	var fresh := PackedInt32Array([1, 1])      ## 0x8021F618: the next input frame has no new press
	var repeat := PackedInt32Array([0, 0])     ## 0x8021FC88
	var counters := PackedInt32Array()         ## 0x8021FE20: 16 per player

	func _init() -> void:
		counters.resize(2 * REPEAT_BITS)

	func read(words: PackedInt32Array) -> void:
		for p in 2:
			pressed[p] = (words[p] ^ held[p]) & words[p]
			held[p] = words[p]
			repeat[p] = _repeat_word(p)

	## FUN_8018CD30's auto-repeat: a new press, then from REPEAT_FROM frames on every fourth frame.
	func _repeat_word(p: int) -> int:
		var word := 0
		for bit in REPEAT_BITS:
			var at := p * REPEAT_BITS + bit
			var mask := 1 << bit
			if held[p] & mask == 0:
				counters[at] = 0
			elif pressed[p] & mask != 0:
				counters[at] = 1
				word |= mask
			else:
				counters[at] = (counters[at] + 1) & 0xFFFF
				if counters[at] >= REPEAT_FROM and counters[at] & 3 == 0:
					word |= mask
		return word


## FUN_801A2D9C: which way a player's stick reads, from the screen positions.
static func update_sides(f0: FighterState, f1: FighterState) -> void:
	f0.side_flag = 0 if f0.screen_x < f1.screen_x else 1
	f1.side_flag = 0 if f1.screen_x < f0.screen_x else 1


## FUN_8018B61C for one fighter: `mode` is the fighter's input mode.
static func source(fight: FightState, f: FighterState, panels: Panels, mode: int, cpu: AiDecision) -> void:
	match mode:
		1:
			if f.health == 0 or (f.is_cpu != 0 and fight.no_damage != 0):
				clear(f, panels)
			else:
				_read(fight, f, panels, cpu)
		0:
			clear(f, panels)


## FUN_8018E0DC. Control −1 reads nothing; the program has no writer of that value (FUN_8018A44C
## writes positive ones only).
static func _read(fight: FightState, f: FighterState, panels: Panels, cpu: AiDecision) -> void:
	var p := f.index
	if f.is_cpu == NO_CONTROL:
		update(fight, f, -1, 0, 0)
		return
	if f.is_cpu != 0:
		var words := cpu.update(f)
		update(fight, f, 0, words[0], words[1])
		return
	if panels.fresh[p] != 0:
		panels.fresh[p] = 0
		panels.previous[p] = panels.held[p]
	var held := panels.held[p]
	var pressed := held & (held ^ panels.previous[p])
	panels.previous[p] = held
	update(fight, f, f.side_flag, held, pressed)


## FUN_8018E220.
static func update(fight: FightState, f: FighterState, side: int, held: int, pressed: int) -> void:
	fight.latch_register = RECORD_ADDRESS_LOW[f.index]
	f.in_hist_index = f.in_hist_index + 1 if (f.in_hist_index & 0xFFFFFFFF) < 0x3B else 0
	var direction := NEUTRAL
	if side >= 0 and side < STICK_SIDES:
		var table := fight.tables.directions[side]
		for d in 9:
			if table[d] == held & DIRECTIONS:
				direction = d + 1
				break
	var held_bits := _history_bits(held)
	f.in_held = held_bits >> 4
	var bits := _history_bits(pressed)
	if pressed & LP:
		f.press_count[0] += 1
	if pressed & RP:
		f.press_count[1] += 1
	if pressed & LK:
		f.press_count[2] += 1
	if pressed & RK:
		f.press_count[3] += 1
	f.in_history[f.in_hist_index] = (bits | direction) & 0xFF
	f.in_pressed = bits >> 4
	f.in_dir = direction_bit(direction)
	var old := f.in_pressed_hist[f.in_hist_index]
	if old & LP:
		f.press_count[0] -= 1
	if old & RP:
		f.press_count[1] -= 1
	if old & LK:
		f.press_count[2] -= 1
	if old & RK:
		f.press_count[3] -= 1
	f.in_pressed_hist[f.in_hist_index] = pressed & 0xFFFF
	if (f.cmd_count & 0xFFFFFFFF) > 9:
		return
	if f.cmd_merge_timer > 0:
		f.cmd_merge_timer -= 1
	if bits == 0:
		return
	if f.cmd_merge_timer > 0 and (held_bits & ~bits) == (f.cmd_buffer[f.cmd_count] & 0xF0):
		f.cmd_buffer[f.cmd_count] = (held_bits + direction) & 0xFF
	else:
		if f.cmd_count > MAX_COMMANDS - 1:
			return
		f.cmd_count += 1
		f.cmd_buffer[f.cmd_count] = (held_bits + direction) & 0xFF
	f.cmd_merge_timer = MERGE_FRAMES


## A direction as the commands' mask has it. FUN_8018E8D8 reads it from the newest history entry:
## whatever writes that entry keeps `in_dir` in step.
static func direction_bit(direction: int) -> int:
	return 1 << ((direction & 0xF) + 4)


static func _history_bits(word: int) -> int:
	var bits := 0
	if word & LP:
		bits |= FighterInput.HIST_LP
	if word & RP:
		bits |= FighterInput.HIST_RP
	if word & LK:
		bits |= FighterInput.HIST_LK
	if word & RK:
		bits |= FighterInput.HIST_RK
	return bits


## FUN_8018E000. The held bits stay as they were.
static func clear(f: FighterState, panels: Panels) -> void:
	for i in HISTORY:
		f.in_history[i] = NEUTRAL
		f.in_pressed_hist[i] = 0
	f.cmd_count = -1
	f.cmd_read = -1
	f.in_hist_index = 0
	for i in 4:
		f.press_count[i] = 0
	f.in_dir = direction_bit(NEUTRAL)
	f.in_pressed = 0
	panels.fresh[f.index] = 1


## FUN_8018B710: a new LP, RP or LP + RP press of each fighter's newest entry, once per input frame.
## A fighter holding a used tap leaves $t0 as it was, and that is what its "previous" becomes
## (`fight.latch_register`): for the first fighter the address FUN_8018E220 worked on last, for the
## second also the first fighter's entry. The address's low byte has both punch bits set, so a press
## on the frame after a held tap is not new.
static func latch_taps(fight: FightState) -> void:
	if fight.round_frame == 1:
		fight.tap_previous[0] = 0
		fight.tap_previous[1] = 0
	if fight.round_frame_seen == fight.round_frame:
		return
	for i in 2:
		var f := fight.fighters[i]
		if f.cond_flag_used != 1 or (f.tap_lp == 0 and f.tap_rp == 0 and f.tap_both == 0):
			var entry := f.in_history[f.in_hist_index]
			var fresh := entry & (entry ^ fight.tap_previous[i])
			var lp := fresh & FighterInput.HIST_LP
			var rp := fresh & FighterInput.HIST_RP
			if entry & BOTH_PUNCHES == BOTH_PUNCHES and (lp != 0 or rp != 0):
				f.tap_both = 1
			elif lp != 0:
				f.tap_lp = 1
			elif rp != 0:
				f.tap_rp = 1
			else:
				f.tap_both = 0
				f.tap_lp = 0
				f.tap_rp = 0
			fight.latch_register = entry
		fight.tap_previous[i] = fight.latch_register
