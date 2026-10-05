class_name FighterInput
## A fighter's input state (moves.md#input-state): the pads' mapped words, InputSource and
## InputUpdate with the 60-frame history and the command buffer, the STEP key helper of
## CpuOrPadInput, InputClear and LatchButtonTaps.

const HISTORY := 60
const NEUTRAL := 5
const STEP_UP := 0x1                 ## mapped bits of the STEP key actions (key configuration)
const STEP_DOWN := 0x4
const STEP_HOLD := 0x23
const DIRECTIONS := PadState.DIRECTIONS
const OPPOSITE_VERTICAL := PadState.VERTICAL
const OPPOSITE_HORIZONTAL := PadState.HORIZONTAL
## The attack buttons of the mapped pad word (the key configuration's layout).
const PAD_LP := PadState.SQUARE
const PAD_RP := PadState.TRIANGLE
const PAD_LK := PadState.CROSS
const PAD_RK := PadState.CIRCLE
## A history entry: the newly pressed attack buttons in bits 4–7, the numpad direction in 0–3.
const HIST_LP := 0x10
const HIST_RP := 0x20
const HIST_LK := 0x40
const HIST_RK := 0x80
const HIST_BUTTONS := 0xF0
const HIST_DIRECTION := 0xF


## The pads of one frame as FUN_8002A014 reads them: per player the physical buttons and the
## words mapped by the key configuration, each with its newly pressed bits.
class PadWords:
	const REPEAT_DELAY := 0x13          ## frames a button is held before it repeats
	const REPEAT_STEP := 4

	var physical := PackedInt32Array([0, 0])            ## 0x800AE230
	var physical_pressed := PackedInt32Array([0, 0])    ## 0x800AE3D0
	var repeat := PackedInt32Array([0, 0])              ## 0x800AE3C8: pressed, then repeating
	var held := PackedInt32Array([0, 0])                ## 0x800A9110 (mapped)
	var pressed := PackedInt32Array([0, 0])             ## 0x800AE140 (mapped)
	var connected := 3                                  ## 0x800A964C: a bit per connected pad
	var _counters: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]   ## 0x8009C010

	func _init() -> void:
		for p in 2:
			_counters[p].resize(16)

	## FUN_8002A014 for one frame: `buttons` are the pads' physical words, `tables` per player the
	## mapped word of each physical bit. Opposite directions cancel in the mapped word.
	func read(buttons: PackedInt32Array, tables: Array[PackedInt32Array]) -> void:
		for p in 2:
			var raw := buttons[p] & 0xFFFF
			physical_pressed[p] = (raw ^ physical[p]) & raw
			physical[p] = raw
			var mapped := 0
			for bit in 16:
				if raw & (1 << bit):
					mapped |= tables[p][bit]
			var word := mapped
			if mapped & OPPOSITE_VERTICAL == OPPOSITE_VERTICAL:
				word = mapped & 0xAFFF
			if mapped & OPPOSITE_HORIZONTAL == OPPOSITE_HORIZONTAL:
				word &= 0x5FFF
			pressed[p] = (word ^ held[p]) & word
			held[p] = word
			repeat[p] = _repeat(p)

	## The repeating buttons: a new press, then every 4th frame after the button has been held
	## for 20 frames (bits from 15 down, as the game walks them).
	func _repeat(p: int) -> int:
		var word := 0
		var counters := _counters[p]
		for k in 16:
			var bit := 15 - k
			word <<= 1
			if physical[p] & (1 << bit) == 0:
				counters[bit] = 0
			elif physical_pressed[p] & (1 << bit) == 0:
				var c := counters[bit] + 1
				counters[bit] = c & 0xFF
				if c > REPEAT_DELAY:
					word |= 1 if c & 3 == 0 else 0
					counters[bit] = (c - REPEAT_STEP) & 0xFF
			else:
				counters[bit] = 1
				word |= 1
		return word


## InputSource (0x8002BF3C): nothing (mode 0), the pad or the CPU (1), the scripted word (2,
## InputScripted 0x8002C778: the round end's hold or crouch, the practice dummy).
static func source(fight: FightState, f: FighterState, pads: PadWords, cpu: AiDecision = null) -> void:
	match fight.input_mode[f.index]:
		0:
			clear(fight, f)
		1:
			if f.is_cpu != 0:
				_cpu_input(fight, f, cpu)
			else:
				_pad_input(fight, f, pads)
		2:
			var word := f.script_input & 0xFFFF
			update(fight, f, 0, word, word & (word ^ fight.script_previous[f.index]))
			fight.script_previous[f.index] = word


## CpuOrPadInput (0x8002C4CC) for a CPU fighter: AiUpdate's pad words in the fighter's own frame
## (side 0). A CPU without health skips AiUpdate and gets no input (the game passes stack
## garbage, bug #59).
static func _cpu_input(fight: FightState, f: FighterState, cpu: AiDecision) -> void:
	var words := PackedInt32Array([0, 0])
	if f.health != 0:
		words = cpu.update(f)
	if fight.mode == GameMode.PRACTICE and fight.practice_pads != null:
		fight.practice_pads.call(f.index, words[0])
	update(fight, f, 0, words[0], words[1] & 0xFFFF)


## CpuOrPadInput (0x8002C4CC) for a human: the side from the screen positions, the STEP key
## helper, then InputUpdate. Tekken Force's player faces its current opponent and reads the
## human's pad (0x800B70D8).
static func _pad_input(fight: FightState, f: FighterState, pads: PadWords) -> void:
	var p := f.index
	if fight.mode == GameMode.FORCE:
		update_side(f, fight.fighters[f.cur_opp_index])
		p = fight.force.human()
	else:
		update_side(f, fight.fighters[(f.player_index + 1) & 1])
	# Practice's dummy on CONTROLLER takes the other pad (FUN_800B4800).
	if fight.mode == GameMode.PRACTICE and fight.practice_swap:
		p = (p + 1) & 1
	var held := pads.held[p]
	var pressed := pads.pressed[p]
	var step_dir := 0
	var step_press := 0
	if pressed & STEP_UP:
		step_press = PadState.UP
		fight.step_helper_side[p] = 0
		fight.step_helper_timer[p] = STEP_HOLD
	elif pressed & STEP_DOWN:
		step_press = PadState.DOWN
		fight.step_helper_side[p] = 1
		fight.step_helper_timer[p] = STEP_HOLD
	if fight.step_helper_timer[p] > 0:
		fight.step_helper_timer[p] -= 1
		var left := fight.step_helper_timer[p]
		if left > 0x21:
			step_dir = PadState.UP if fight.step_helper_side[p] == 0 else PadState.DOWN
		var holding := (fight.step_helper_side[p] == 0 and pads.held[p] & STEP_UP) \
			or (fight.step_helper_side[p] == 1 and pads.held[p] & STEP_DOWN)
		if holding and held & PadState.FACE_BUTTONS == 0:
			held &= 0xFFFF0FFF
			pressed &= 0xFFFF0FFF
	if fight.mode == GameMode.PRACTICE and fight.practice_pads != null:
		fight.practice_pads.call(f.index, held | step_dir)
	update(fight, f, f.side_flag, held | step_dir, (pressed | step_press) & 0xFFFF)


## FighterUpdateSide (0x800464CC): the side from the screen positions (mirrors the stick).
static func update_side(f: FighterState, opp: FighterState) -> void:
	if f.fixed_facing == 0:
		f.side_flag = 1 if opp.screen_x <= f.screen_x else 0
	else:
		f.side_flag = f.fixed_facing_side


## InputUpdate (0x8002C7D4): direction, buttons, the history rings and the command buffer. It
## leaves the pressed bits (LP 0x10, RP 0x20, LK 0x40, RK 0x80) in $a2, which LatchButtonTaps
## may find there (bug #52).
static func update(fight: FightState, f: FighterState, side: int, held: int, pressed: int) -> void:
	f.in_hist_index = f.in_hist_index + 1 if (f.in_hist_index & 0xFFFFFFFF) < 0x3B else 0
	var direction := NEUTRAL
	if side < 2:
		var table := fight.tables.directions[side]
		for d in 9:
			if table[d] == held & DIRECTIONS:
				direction = d + 1
				break
	var held_bits := HIST_LP if held & PAD_LP else 0
	if held & PAD_RP:
		held_bits |= HIST_RP
	if held & PAD_LK:
		held_bits |= HIST_LK
	if held & PAD_RK:
		held_bits |= HIST_RK
	f.in_held = held_bits >> 4
	var bits := 0
	if pressed & PAD_LP:
		bits = HIST_LP
		f.press_count[0] += 1
	if pressed & PAD_RP:
		bits |= HIST_RP
		f.press_count[1] += 1
	if pressed & PAD_LK:
		bits |= HIST_LK
		f.press_count[2] += 1
	if pressed & PAD_RK:
		bits |= HIST_RK
		f.press_count[3] += 1
	fight.latch_register = bits
	f.in_history[f.in_hist_index] = (bits | direction) & 0xFF
	f.in_pressed = bits >> 4
	f.in_dir = 1 << ((direction & 0xF) + 4)
	var old := f.in_pressed_hist[f.in_hist_index]
	if old & 0x80:
		f.press_count[0] -= 1
	if old & 0x10:
		f.press_count[1] -= 1
	if old & 0x40:
		f.press_count[2] -= 1
	if old & 0x20:
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
		if f.cmd_count > 8:
			return
		f.cmd_count += 1
		f.cmd_buffer[f.cmd_count] = (held_bits + direction) & 0xFF
	f.cmd_merge_timer = 3


## InputClear (0x8002C2A4): a neutral history. It leaves 5 in $a2.
static func clear(fight: FightState, f: FighterState) -> void:
	for i in HISTORY:
		f.in_history[i] = NEUTRAL
		f.in_pressed_hist[i] = 0
	f.in_dir = NEUTRAL
	f.cmd_count = -1
	f.cmd_read = -1
	f.in_hist_index = 0
	f.in_held = 0
	f.in_pressed = 0
	for i in 4:
		f.press_count[i] = 0
	f.script_input = 0
	fight.script_previous[f.index] = 0
	fight.tap_previous[f.index] = 0
	fight.latch_register = NEUTRAL


## FUN_8002C33C / FUN_8002C360: opens (counters 0) or closes (−1) the command buffer.
static func buffer_enable(f: FighterState, on: bool) -> void:
	if on and f.cmd_count < 0:
		f.cmd_count = 0
		f.cmd_read = 0
		f.cmd_merge_timer = 0
	elif not on and f.cmd_count >= 0:
		f.cmd_count = -1
		f.cmd_read = -1
		f.cmd_merge_timer = -1


## LatchButtonTaps (0x80040D68), once per new input frame: a new LP, RP or LP+RP press of the
## newest history entry. While a tap is pending and a branch condition has read it
## (condFlagUsed) the taps stay frozen, and the game then stores whatever $a2 holds as the
## entry to compare with next time (bug #52; with the Gameplay fix, the newest entry).
static func latch_taps(fight: FightState, f: FighterState) -> void:
	if fight.round_frame_seen == fight.round_frame:
		return
	var frozen := f.cond_flag_used == 1 and (f.tap_lp != 0 or f.tap_rp != 0 or f.tap_both != 0)
	if not frozen:
		var entry := f.in_history[f.in_hist_index]
		fight.latch_register = entry
		var fresh := entry & (entry ^ fight.tap_previous[f.index])
		var lp := fresh & HIST_LP
		var rp := fresh & HIST_RP
		if entry & (HIST_LP | HIST_RP) == HIST_LP | HIST_RP and (lp != 0 or rp != 0):
			f.tap_both = 1
		elif lp != 0:
			f.tap_lp = 1
		elif rp != 0:
			f.tap_rp = 1
		else:
			f.tap_both = 0
			f.tap_lp = 0
			f.tap_rp = 0
	elif fight.rules.fix_tap_latch_register:
		fight.latch_register = f.in_history[f.in_hist_index]
	fight.tap_previous[f.index] = fight.latch_register & 0xFFFF
