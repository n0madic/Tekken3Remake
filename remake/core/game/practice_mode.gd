class_name PracticeMode
extends FlowPart
## PRACTICE MODE (practice.ovl, mode 5; modes.md#practice): the practice state S (0x800B9180,
## kept as bytes), its set-up at each round start (FUN_800B2D74), and the frame hook FightFrame
## calls last (FUN_800B3084): the pause menu (practice_sim.py's verified menu_cursor/menu_input),
## the training dummy's scripted input (FUN_800B4684, FUN_800B87C8), the attack data
## (FUN_800B3808), the freeze signal (FUN_800B4600, FUN_800B3520, FUN_800B6CF4), the key ring and
## the combo guide (FUN_800B7A88 … FUN_800B86F0), and the replay settings (FUN_800B8D50).
##
## The fight reads `pad_swap` (the dummy on CONTROLLER takes the other pad) and records each
## fighter's pad word through `record_pad` (FUN_800B4800, FUN_800B7AEC).
##
## The hit markers' screen points (FUN_80036D28) are left to the presentation (PracticeView),
## which projects the world point kept per marker with the fight camera.

const BASE := 0x800B9180
const SIZE := 0x1F8
const RING := 0xB0                   ## 0x800B9230: 50 key-ring words
const RING_WORDS := 0x32
const REPLAY := 0x178                ## 0x800B92F8: replay position, word, count
const MARKS := 0x184                 ## 0x800B9304: 50 u16 move slots of the replayed guide
const HEADS := 0x1E8                 ## 0x800B9368: per player the ring head
const CHECKED := 0x1F0               ## 0x800B9370: per player
const PLAYER_DATA := 0x14            ## per player 0x20 bytes of attack data
## S fields.
const HELD := 0x00
const PRESSED := 0x02
const REPEAT := 0x04
const MAPPED_HELD := 0x06
const MAPPED_PRESSED := 0x08
const SCRIPT_EDGE := 0x0C
const SCRIPT_PREVIOUS := 0x0E
const REPLAY_FRAMES := 0x10
const COMBO_FRAMES := 0x12
const MARKERS := 0x54
const MARKER_INDEX := 0x74
const MODE_SELECT := 0x75
const INTRO_DELAY := 0x76
const SUB := 0x77
const CURSOR_FREE := 0x78
const CURSOR_VS := 0x79
const CURSOR_COMBO := 0x7A
const COMBO_PLAYER := 0x7B
const COMBO_TYPE := 0x7C
const DUMMY := 0x7D
const CPU_DIFFICULTY := 0x7E
const CPU_LEVEL := 0x7F
const DUMMY_KIND := 0x80             ## 0 CONTROLLER, 1 scripted, 2 CPU
const REPLAY_SETTING := 0x81
const GUIDE_STATE := 0x82
const FREEZE_SIGNAL := 0x83
const PLAYER := 0x84
const OTHER := 0x85
const SWAP := 0x86
const GUIDE := 0x87
const CAN_ACT := 0x88                ## per player: the freeze signal's result
const PAUSED := 0x8A
const PAUSED_BEFORE := 0x8B
const ATTACK_DATA := 0x9D
const COUNTER_ATTACKS := 0x9E
const COMMAND_LIST := 0x9F
const KEY_DISPLAY := 0xA0
const GUIDE_LENGTH := 0xA1
const GUIDE_PROMPT := 0xA2
const PROMPT := 0xA3
const PROMPT_TIMER := 0xA4
const CHANGED := 0xA7
const RESUMED_INPUT := 0xA8
const MENU_DELAY := 0xA9
const ACTING := 0xAA                 ## per player (FUN_800B4818)
const RESUMING := 0xAC
## Per-player attack data (+0x14 + 0x20·player).
const D_TOTAL := 0x00
const D_COMBO_DAMAGE := 0x04
const D_SHOWN_DAMAGE := 0x08
const D_HIT_DAMAGE := 0x0C
const D_HIT_SHARE := 0x0E
const D_MARKER := 0x10
const D_HITS := 0x12
const D_COMBO := 0x14
const D_NEW_BEST := 0x15
const D_ENDED := 0x16
const D_PREVIOUS := 0x17
const D_LAST := 0x18
const D_DROPPED := 0x19
const D_COUNTER := 0x1A
const D_CLEAN := 0x1B
const D_HIT_ID := 0x1C
const D_BEST := 0x1D
const D_THROW := 0x1E
const D_THROW_BEFORE := 0x1F
## The input guide and recorder (GUIDE_STATE): the prompt, recording, the combo guide's play
## and the replay of a recording (the prompts of the practice HUD).
enum GuideState {
	IDLE = 0, READY = 1, RECORD_WAIT = 2, RECORDING = 3, GUIDE_STAND = 4, GUIDE_PLAY = 5, REPLAY = 6,
	REPLAY_END = 7, GUIDE_MODE = 8, MOVE_END = 9,
}
## The menu items (practice_rows' ids).
enum Item {
	RESUME = 0, ATTACK_DATA = 1, COUNTER_ATTACKS = 2, FREEZE_SIGNAL = 3, REPLAY = 4, KEY_DISPLAY = 5,
	GUIDE = 6, COMMAND_LIST = 7, CPU_DIFFICULTY = 9, CPU_LEVEL = 10, CHARACTER_SELECT = 11, EXIT = 12,
	DUMMY = 13, MODE_SELECT = 14, COMBO_PLAYER = 15, COMBO_TYPE = 16,
}
## Any of these starts a recording: the directions, face and shoulder buttons.
const RECORD_KEYS := PadState.DIRECTIONS | PadState.FACE_BUTTONS | PadState.L1 | PadState.R1 | PadState.L2 \
	| PadState.R2
const ITEM_ROW_CURSORS: Array[int] = [CURSOR_FREE, CURSOR_VS, CURSOR_COMBO]
const ITEM_ROW_LAST: Array[int] = [8, 8, 7]
const SOUND_MOVE := 0x546C
const SOUND_OK := 0x4CEB
const CHOOSE := 0x9F0
const REQUEST_SELECT := RoundState.END              ## back to character select
const REQUEST_LEAVE := RoundState.PRACTICE_EXIT    ## the main menu
const GUIDE_WAIT_FRAMES := 0x1E
const REPLAY_MIN := 0x5A
const REPLAY_MAX := 300
const MANUAL := 4
const PLAYER_SOUNDS: Array[int] = [0x80, 0x4C70, 0x10, 0x4C71, 0x40, 0x4C72, 0x20, 0x4C73]   ## button, sound

var s := ByteBlock.new(SIZE)
var guide_wait := PackedInt32Array([0, 0])   ## 0x800B916C: per player
var pads := PackedInt32Array([0, 0])         ## 0x800B9174: per fighter the pad word of the frame
var marker_points: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0]), PackedInt32Array([0, 0, 0]),
	PackedInt32Array([0, 0, 0]), PackedInt32Array([0, 0, 0])]   ## the hit markers' world points


## Several byte fields at once: offset, value, offset, value …
func _puts(pairs: Array[int]) -> void:
	for i in range(0, pairs.size(), 2):
		put(pairs[i], pairs[i + 1])


func b(at: int) -> int:
	return s.u8(at)


func sb(at: int) -> int:
	return s.s8(at)


func put(at: int, v: int) -> void:
	s.put8(at, v)


func pd(player: int, at: int) -> int:
	return PLAYER_DATA + 0x20 * player + at


# ---- the fight's hooks ------------------------------------------------------------------------

## FUN_800B4800: the dummy on CONTROLLER reads the other pad.
func pad_swap() -> bool:
	return b(SWAP) != 0


## FUN_800B7AEC: a fighter's pad word of the frame (the key display's source).
func record_pad(index: int, word: int) -> void:
	pads[index] = word & 0xFFFF


## FUN_800B2D74 (FUN_8002AB68 in mode 5): the settings of a new practice session's round.
func setup() -> void:
	var fight := g.fight
	put(PAUSED, 0)
	put(PAUSED_BEFORE, 0)
	put(MODE_SELECT, 1)
	put(SUB, 0)
	fight.practice_intro = 1
	put(INTRO_DELAY, 0x1E)
	for at: int in [CURSOR_FREE, CURSOR_VS, CURSOR_COMBO, FREEZE_SIGNAL, COUNTER_ATTACKS, REPLAY_SETTING, SWAP,
			GUIDE_PROMPT, DUMMY, COMBO_TYPE, RESUMING]:
		put(at, 0)
	put(ATTACK_DATA, 1)
	put(DUMMY_KIND, 1)
	put(CPU_DIFFICULTY, 1)
	put(CPU_LEVEL, 2)
	put(KEY_DISPLAY, 1)
	put(GUIDE_LENGTH, 0xF)
	put(GUIDE, 0)
	put(COMBO_PLAYER, fight.tie_choice)
	for p in 2:
		put(ACTING + p, 0)
		put(CAN_ACT + p, 0)
	key_ring_reset(0)
	key_ring_reset(1)
	put(MENU_DELAY, 0)
	put(COMMAND_LIST, 0)
	put(GUIDE_STATE, GuideState.IDLE)
	_guide_moves_reset()
	_input_modes(1)
	_signal_clear()
	put(MARKER_INDEX, 0)
	put(PROMPT_TIMER, 0)
	put(PROMPT, 0)
	put(CHANGED, 1)
	put(SWAP, 0)
	_ai_reset(fight.fighters[1])
	_input_modes(0)
	fight.counter_forced[0] = 0
	fight.counter_forced[1] = 0
	fight.counter_forced[2] = 0
	for p in 2:
		for at in range(0x20):
			put(pd(p, at), 0)


## AiReset (0x800596B0) of the dummy with the page's CPU DIFFICULTY and LEVEL.
func _ai_reset(f: FighterState) -> void:
	if f.ai_slot >= 0 and g.sim.ai.ai_self != null:
		g.sim.ai.reset(f, sb(CPU_DIFFICULTY), sb(CPU_LEVEL), -1)


## FUN_8002BE54: every fighter's input cleared and its input mode set.
func _input_modes(mode: int) -> void:
	for f in g.fight.fighters:
		FighterInput.clear(g.fight, f)
		g.fight.input_mode[f.index] = mode


func _signal_clear() -> void:
	for p in 2:
		g.fight.signal_colour[p] = Color8(0, 0, 0, 0)
	for i in 4:
		s.put16(MARKERS + 8 * i + 2, 0)


## FUN_800B3084 (FightFrame's last step in mode 5): returns the paused flag (0x800958DC).
func frame() -> int:
	var fight := g.fight
	var gl := g.globals
	fight.hud_shown = 0
	put(PLAYER, fight.tie_choice)
	put(OTHER, gl.other_player)
	var me := fight.fighters[fight.tie_choice]
	var dummy := fight.fighters[gl.other_player]
	var pads_now := g.sim.pads
	var p := fight.tie_choice
	s.put16(HELD, pads_now.physical[p])
	s.put16(PRESSED, pads_now.physical_pressed[p])
	s.put16(REPEAT, pads_now.repeat[p])
	s.put16(MAPPED_HELD, pads_now.held[p])
	s.put16(MAPPED_PRESSED, pads_now.pressed[p])
	if fight.replay_playing == 0:
		put(PAUSED, fight.pause_request)
		if fight.practice_intro != 0:
			s.put16(HELD, 0)
			s.put16(PRESSED, 0)
			s.put16(REPEAT, 0)
			if fight.pause_request != 0:
				put(INTRO_DELAY, sb(INTRO_DELAY) - 1)
				if sb(INTRO_DELAY) < 0:
					put(INTRO_DELAY, 0)
					fight.practice_intro = 0
					_input_modes(1)
					key_ring_reset(0)
					key_ring_reset(1)
		if b(PAUSED) != b(PAUSED_BEFORE):
			if b(PAUSED) == 0:
				_resume(me, dummy)
			else:
				put(COMMAND_LIST, 0)
				s.put16(PRESSED, s.u16(PRESSED) & 0xF7FF)
				put(GUIDE_STATE, GuideState.IDLE)
				_guide_moves_reset()
				_input_modes(1)
				_signal_clear()
				put(MARKER_INDEX, 0)
				put(PROMPT_TIMER, 0)
				put(PROMPT, 0)
				put(CHANGED, 1)
				put(SWAP, 0)
				put(MENU_DELAY, 3)
				if b(RESUMING) != 0:
					g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
		put(PAUSED_BEFORE, b(PAUSED))
		if b(MENU_DELAY) != 0:
			put(MENU_DELAY, b(MENU_DELAY) - 1)
		if b(PAUSED) == 0:
			_attack_data(me, dummy)
		elif b(MENU_DELAY) == 0:
			if b(COMMAND_LIST) == 0:
				_menu_cursor()
			_menu_input()
	_freeze_signal(me, dummy)
	_signal_colours()
	_replay_control(dummy, me)
	fight.practice_swap = b(SWAP) != 0
	return b(PAUSED)


## OK: the menu closes at the next pause check.
func resume() -> void:
	g.fight.pause_close = 1
	put(RESUMING, 1)


## The remake's Escape on the menu (not while COMMAND LIST is shown, which Escape's Start turns
## off): as OK. False when the menu is not taking input.
func escape() -> bool:
	if b(PAUSED) == 0 or b(COMMAND_LIST) != 0 or b(MENU_DELAY) != 0:
		return false
	resume()
	return true


## FUN_800B2BC4: leaving the pause menu applies the dummy and the page's settings.
func _resume(me: FighterState, dummy: FighterState) -> void:
	_dummy_control(me, dummy)
	if sb(DUMMY_KIND) == 2:
		_ai_reset(dummy)
	put(RESUMED_INPUT, 0)
	match sb(SUB):
		1:
			put(COUNTER_ATTACKS, 0)
			put(GUIDE, 0)
			key_ring_reset(b(PLAYER))
		0:
			put(GUIDE, 1 if s.u16(HELD) & 0x2F == 0x2F and sb(REPLAY_SETTING) != 4 else 0)
			key_ring_reset(b(PLAYER))
			replay_reset(b(PLAYER))
		2:
			put(COUNTER_ATTACKS, 0)
			put(GUIDE, 1)
			put(KEY_DISPLAY, 1)
			key_ring_reset(sb(COMBO_PLAYER))
			replay_reset(sb(COMBO_PLAYER))
			load_guide(sb(COMBO_PLAYER), 0)


# ---- the training dummy (FUN_800B4684, FUN_800B87C8 and its guards) --------------------------

func _dummy_control(me: FighterState, dummy: FighterState) -> void:
	var fight := g.fight
	me.human_guard = 1
	me.is_cpu = 0
	fight.input_mode[me.index] = 1
	match sb(SUB):
		1:
			put(DUMMY_KIND, 2)
		0:
			put(DUMMY_KIND, 0 if sb(DUMMY) == 8 else 1)
		2:
			put(DUMMY_KIND, 1)
			put(DUMMY, 0)
	match sb(DUMMY_KIND):
		1:
			dummy.human_guard = 0
			dummy.is_cpu = 0
			fight.input_mode[dummy.index] = 2
			dummy_input(dummy, me, sb(DUMMY))
		0:
			dummy.human_guard = 1
			dummy.is_cpu = 0
			fight.input_mode[dummy.index] = 1
		2:
			dummy.human_guard = 0
			dummy.is_cpu = 1
			fight.input_mode[dummy.index] = 1


## FUN_800B87C8: the dummy's scripted word for the TRAINING DUMMY setting.
func dummy_input(dummy: FighterState, me: FighterState, setting: int) -> void:
	if dummy.bank_type == BankType.DOCTOR_B:
		return
	if setting == 6 or setting == 7:
		dummy.human_guard = 0
		if dummy.in_reaction != 0:
			_tech_roll(dummy, setting == 6)
			return
		_standing_ok(dummy)
		return
	if not _standing_ok(dummy):
		return
	match setting:
		1:
			dummy.script_input = 0x4000
		2:
			if me.attack & 0x10 and me.pose_frame <= me.pose_move.active_last:
				dummy.script_input = 0x8000
		3:
			dummy.script_input = 0x4000
			if me.attack & 0x08 and me.pose_frame <= me.pose_move.active_last:
				dummy.script_input = 0xC000
		4:
			if me.attack & 0x18 and me.pose_frame <= me.pose_move.active_last:
				dummy.script_input = 0x8000 if me.attack & 0x10 else 0xC000
		5:
			dummy.human_guard = 1
			return
	dummy.human_guard = 0


## FUN_800B8904: lying down, the dummy holds up; true when it may act. A stance slot empty in
## both banks has no row (bug #61, not reproduced).
func _standing_ok(f: FighterState) -> bool:
	var row := f.move_row if f.move_row != null else g.fight.move_for_slot(f, f.pose_move.stance_slot)
	f.script_input = 0x1000 if row != null and row.state & (StateBit.DOWN_REVERSED | StateBit.DOWN) else 0
	return f.script_input == 0


## FUN_800B8AEC: UKEMI MAE (LK+RK) or OKU (LP+RP) on alternate frames, during a reaction with
## an air window and a tech-roll branch.
func _tech_roll(f: FighterState, forward: bool) -> void:
	if f.move_row != null or f.in_reaction == 0 or f.pose_move.air_first == 0 or not _has_tech_roll(f):
		return
	f.script_input = (0x60 if forward else 0x90) if g.region.frame_counter & 1 else 0


## FUN_800B8B94: a branch row of the move leads to the tech roll (transition 0x1C).
func _has_tech_roll(f: FighterState) -> bool:
	var rows := f.pose_move.bank.branches
	var i := f.pose_move.branches
	while i >= 0 and i < rows.size() and rows[i][MoveSystem.ROW_COMMAND] != MoveSystem.END:
		if rows[i][MoveSystem.ROW_FLAGS] == 0x1C:
			return true
		i += 1
	return false


## FUN_800B899C: the guide's replay may start once the fighter stands in its stance (a turned
## fighter first turns back).
func _ready_to_replay(f: FighterState) -> bool:
	if f.facing_quadrant != 0:
		f.script_input = 0x8000 if f.move_row == null else 0
		return false
	if f.cur_slot == 3 or f.cur_slot == 4 or f.cur_slot == 5 or f.cur_slot == f.pose_move.stance_slot:
		f.script_input = 0
		return true
	return false


# ---- the freeze signal (FUN_800B4600, FUN_800B3520, FUN_800B6CF4) -----------------------------

func _freeze_signal(me: FighterState, dummy: FighterState) -> void:
	if b(FREEZE_SIGNAL) == 0:
		return
	put(CAN_ACT + me.player_index, 1 if g.sim.moves.can_act(me, dummy) else 0)
	put(CAN_ACT + dummy.player_index, 1 if g.sim.moves.can_act(dummy, me) else 0)


## The back light colours: green while a fighter can act, red while it cannot.
func _signal_colours() -> void:
	var fight := g.fight
	if fight.practice_intro != 0 or b(PAUSED) != 0:
		return
	for p in 2:
		if b(FREEZE_SIGNAL) == 0:
			fight.signal_colour[p] = Color8(0, 0, 0, 0)
		elif b(CAN_ACT + p) == 0:
			fight.signal_colour[p] = Color8(250, 0, 0, 1)
		else:
			fight.signal_colour[p] = Color8(0, 250, 0, 1)


# ---- the key ring and the combo guide ---------------------------------------------------------

## FUN_800B7A88: the ring emptied (its flag bits kept).
func key_ring_reset(player: int) -> void:
	for i in RING_WORDS:
		s.put32(RING + 4 * i, s.u32(RING + 4 * i) & 0x80000000)
	s.put32(HEADS + 4 * player, 0)
	guide_wait[player] = GUIDE_WAIT_FRAMES


## FUN_800B8244: the ring's replay restarts at its first entry.
func replay_reset(player: int) -> void:
	_replay_rewind(player)


## FUN_800B82F4: the recording ends (its last entry counts once), and the replay rewinds.
func _recording_end(player: int) -> void:
	var at := RING + 4 * s.s32(HEADS + 4 * player)
	s.put32(at, (s.u32(at) & 0x8000FFFF) | 0x10000)
	_replay_rewind(player)


func _replay_rewind(player: int) -> void:
	if s.s32(HEADS + 4 * player) < 0:
		s.put32(REPLAY + 4, s.u32(REPLAY + 4) & 0x80000000)
	else:
		s.put32(REPLAY + 4, s.u32(RING))
	s.put32(REPLAY, 0)
	s.put32(REPLAY + 8, 0)
	for i in RING_WORDS:
		s.put16(MARKS + 2 * i, 0)


func _combos(player: int) -> Array:
	var kind := g.fight.fighters[player].bank_type
	return g.data.practice_combos[kind] if kind >= 0 and kind < g.data.practice_combos.size() else []


## FUN_800B8108: the combo count of the combo player's character.
func combo_count() -> int:
	return _combos(sb(COMBO_PLAYER)).size()


## FUN_800B7FB4: combo `combo` of the player's character into the ring as the guide.
func load_guide(player: int, combo: int) -> int:
	var list := _combos(player)
	if list.is_empty():
		return 0
	var steps: PackedInt32Array = (list[combo] as Dictionary)["steps"]
	if steps.is_empty():
		key_ring_reset(player)
		return 0
	s.put32(HEADS + 4 * player, steps.size() - 1)
	for i in steps.size():
		s.put32(RING + 4 * i, steps[i])
	return steps.size()


## FUN_800B85A0: the guide's move slots from MARKS, their count at REPLAY + 8.
func _guide_moves(player: int, combo: int) -> int:
	var list := _combos(player)
	if list.is_empty():
		return 0
	var moves: PackedInt32Array = (list[combo] as Dictionary)["moves"]
	if moves.is_empty():
		key_ring_reset(player)
		return 0
	s.put32(REPLAY + 8, moves.size())
	for i in moves.size():
		s.put16(MARKS + 2 * i, moves[i])
	return moves.size()


## FUN_800B8764.
func _guide_moves_reset() -> void:
	put(0xA6, 1)
	put(0xA5, 0)
	_guide_moves(sb(COMBO_PLAYER), sb(COMBO_TYPE))
	s.put32(CHECKED + 4 * sb(COMBO_PLAYER), 0)


## FUN_800B7B08: the fighter's pad word logged into the ring (a repeat counts on).
func _key_log(player: int) -> void:
	var head := s.s32(HEADS + 4 * player)
	var at := RING + 4 * head
	var word := pads[player]
	var buttons := word & 0xF0F0
	var entry := s.u32(at)
	if (((entry & 0xFF) << 4) | (((entry >> 8) & 0xF) << 12)) == buttons:
		var kept := entry & 0x8000FFFF
		var count := ((Fx.w32((entry << 1) & 0xFFFFFFFF) >> 17) + 1) & 0x7FFF
		var v := kept | (count << 16)
		if (Fx.w32((v << 1) & 0xFFFFFFFF) >> 17) > 0x3FFE:
			v = kept | 0x3FFF0000
		s.put32(at, v)
		return
	head += 1
	head = RING_WORDS - 1 if head < 0 else (0 if head >= RING_WORDS else head)
	at = RING + 4 * head
	var side := 0x80000000 if g.fight.fighters[player].side_flag != 0 else 0
	s.put32(at, ((buttons >> 4) & 0xFF) | (((word >> 12) & 0xFF) << 8) | 0x10000 | side)
	s.put32(HEADS + 4 * player, head)


## FUN_800B7968: true when a new input comes after the ring has been idle for 30 frames.
func _ring_idle(player: int) -> bool:
	var f := g.fight.fighters[player]
	var active := g.sim.pads.held[player] & 0xF0F0 != 0
	if f.cur_slot == f.pose_move.stance_slot:
		guide_wait[player] -= 1
	if not active and (f.move_row == null or f.transition == Transition.HOLD_TURN or f.cur_slot == f.move_slot):
		guide_wait[player] -= 1
	guide_wait[player] = maxi(guide_wait[player], 0)
	if active:
		var was := guide_wait[player]
		guide_wait[player] = GUIDE_WAIT_FRAMES
		return was == 0
	return false


## FUN_800B83A4: the guide's next scripted word for the player (false once the ring is played).
func _guide_play(player: int) -> bool:
	var f := g.fight.fighters[player]
	while true:
		var word := s.u32(REPLAY + 4)
		var kept := word & 0x8000FFFF
		var count := (Fx.w32((word << 1) & 0xFFFFFFFF) >> 17) - 1
		s.put32(REPLAY + 4, kept | ((count & 0x7FFF) << 16))
		if ((count << 17) & 0xFFFFFFFF) & 0x80000000 == 0:
			var direction := (s.u32(REPLAY + 4) >> 8) & 0xFF
			if kept & 0x80000000:
				if direction & 8:
					direction = (direction & 0xFFF7) | 2
				elif direction & 2:
					direction = (direction & 0xFFFD) | 8
			f.script_input = (((s.u32(REPLAY + 4) & 0xFF) << 4) | (direction << 12)) & 0xFFFF
			g.fight.input_mode[f.index] = 2
			return true
		var pos := s.s32(REPLAY) + 1
		s.put32(REPLAY, pos)
		var head := s.s32(HEADS + 4 * player)
		if head < pos or pos >= RING_WORDS:
			s.put32(REPLAY, 0)
			if head < 0:
				s.put32(REPLAY + 4, s.u32(REPLAY + 4) & 0x80000000)
			else:
				s.put32(REPLAY + 4, s.u32(RING))
			return false
		s.put32(REPLAY + 4, s.u32(RING + 4 * pos))
	return false


## FUN_800B8510: the move the player starts at its active frame, logged after the guide's moves.
func _guide_move_log(player: int) -> void:
	var f := g.fight.fighters[player]
	if f.pose_move.active_first == 0 or f.pose_frame != f.pose_move.active_first:
		return
	var n := s.s32(REPLAY + 8)
	s.put16(MARKS + 2 * n, f.cur_slot)
	n += 1
	s.put32(REPLAY + 8, 0 if n >= RING_WORDS else n)


## FUN_800B86F0: the combo player landed a clean hit, or is in a throw transition.
func _guide_hit() -> bool:
	var f := g.fight.fighters[sb(COMBO_PLAYER)]
	if f.hit_clean != 0:
		return true
	return f.move_row != null and f.transition == Transition.HOLD_TURN


# ---- the attack data (FUN_800B3808) -----------------------------------------------------------

func _attack_data(me: FighterState, dummy: FighterState) -> void:
	var fight := g.fight
	_dummy_control(me, dummy)
	var cp := sb(COMBO_PLAYER)
	if b(GUIDE) == 0:
		put(GUIDE_LENGTH, 0xF)
		put(GUIDE_PROMPT, 0)
		put(PROMPT, 1)
		put(PROMPT_TIMER, 0)
		if _ring_idle(cp):
			key_ring_reset(cp)
		_key_log(cp)
	else:
		_guide_step(me, cp)
	s.put16(SCRIPT_EDGE, me.script_input & (me.script_input ^ s.u16(SCRIPT_PREVIOUS)))
	s.put16(SCRIPT_PREVIOUS, me.script_input)
	if b(GUIDE_PROMPT) != 0 and (sb(SUB) != 0 or b(GUIDE) == 0):
		_button_sounds(me.player_index, s.u16(SCRIPT_EDGE))
	fight.counter_forced[dummy.player_index] = 1 if b(COUNTER_ATTACKS) != 0 else 0
	var acting := 1 if _acting(me, dummy) else 0
	put(ACTING + me.player_index, acting)
	put(ACTING + dummy.player_index, acting)
	_player_data(me, dummy)
	_player_data(dummy, me)
	for i in 4:
		var at := MARKERS + 8 * i + 2
		s.put16(at, maxi(s.s16(at) - 1, 0))
	if dummy.hit_clean != 0:
		var k := b(MARKER_INDEX) + 1
		if k > 3:
			k = 0
		put(MARKER_INDEX, k)
		marker_points[k] = dummy.hit_slots[dummy.best_hit_slot].point.duplicate()
		s.put16(MARKERS + 8 * k + 2, 0x3C)
		s.put16(MARKERS + 8 * k, me.attack)


## The COMBO TRAINING guide and the FREE page's recorded replay (FUN_800B3808's state machine).
func _guide_step(me: FighterState, cp: int) -> void:
	var fight := g.fight
	match b(GUIDE_STATE):
		GuideState.IDLE:
			if sb(SUB) == 2:
				put(GUIDE_PROMPT, 1)
				replay_reset(cp)
				_guide_moves_reset()
				put(GUIDE_LENGTH, load_guide(cp, sb(COMBO_TYPE)))
				if b(GUIDE_LENGTH) == 0:
					put(GUIDE_LENGTH, 0xF)
				put(GUIDE_STATE, GuideState.READY)
			elif sb(SUB) == 0 and b(GUIDE) != 0:
				put(GUIDE_STATE, GuideState.READY)
		GuideState.READY:
			_guide_ready(cp)
		GuideState.RECORD_WAIT, GuideState.RECORDING:
			if b(GUIDE_STATE) == GuideState.RECORD_WAIT:
				if s.u16(MAPPED_PRESSED) & RECORD_KEYS == 0:
					return
				put(GUIDE_STATE, GuideState.RECORDING)
			_key_log(cp)
			if s.u16(PRESSED) & PadState.SELECT == 0 and s.s32(HEADS + 4 * cp) != RING_WORDS - 1:
				return
			_recording_end(cp)
			put(GUIDE_STATE, GuideState.READY)
		GuideState.GUIDE_STAND:
			var f := fight.fighters[cp]
			if not _standing_ok(f):
				return
			if _ready_to_replay(f):
				put(GUIDE_STATE, GuideState.GUIDE_PLAY)
		GuideState.GUIDE_PLAY:
			if not _guide_play(cp):
				put(PROMPT_TIMER, 0x60)
				put(PROMPT, 3)
				put(GUIDE_STATE, GuideState.IDLE)
			elif _guide_hit():
				put(PROMPT, 2)
				put(GUIDE_STATE, GuideState.IDLE)
			else:
				_guide_move_log(cp)
		GuideState.REPLAY:
			if _guide_play(cp):
				_guide_move_log(cp)
			else:
				put(GUIDE_STATE, GuideState.REPLAY_END)
		GuideState.REPLAY_END:
			if me.cur_slot == 3 or me.cur_slot == me.pose_move.stance_slot:
				put(GUIDE_PROMPT, 1)
				put(GUIDE_STATE, GuideState.IDLE)
				if s.u16(HELD) & PadState.SELECT:
					put(RESUMED_INPUT, 0)
			else:
				_guide_move_log(cp)
		GuideState.MOVE_END:
			if me.pose_move.active_first == 0 or me.cur_transition == Transition.CONTINUE_FIXED:
				put(GUIDE_STATE, GuideState.IDLE)


## READY: the prompt; in combo training Select plays the guide, in FREE Select replays the
## recorded input and down + Select records a new one.
func _guide_ready(cp: int) -> void:
	var fight := g.fight
	var t := b(PROMPT_TIMER)
	put(PROMPT_TIMER, t - 1)
	if t == 0:
		put(PROMPT_TIMER, 0)
		put(PROMPT, 2)
	if sb(SUB) == 2 and combo_count() != 0:
		if s.u16(PRESSED) & PadState.SELECT:
			FighterInput.clear(fight, fight.fighters[cp])
			fight.input_mode[cp] = 2
			put(PROMPT, 4)
			put(GUIDE_PROMPT, 2)
			put(GUIDE_STATE, GuideState.GUIDE_STAND)
			return
		if b(PLAYER) == fight.tie_choice:
			_button_sounds(cp, s.u16(MAPPED_PRESSED))
	if sb(SUB) != 0 or b(GUIDE) == 0 \
			or (s.u16(PRESSED) & PadState.SELECT == 0 and b(RESUMED_INPUT) == 0):
		return
	if s.u16(HELD) & PadState.DOWN == 0:
		if s.u16(HELD) & PadState.HORIZONTAL:
			put(RESUMED_INPUT, 1)
		FighterInput.clear(fight, fight.fighters[cp])
		replay_reset(cp)
		fight.input_mode[cp] = 2
		put(GUIDE_PROMPT, 2)
		put(PROMPT, 1)
		put(GUIDE_STATE, GuideState.REPLAY)
	else:
		key_ring_reset(cp)
		put(GUIDE_PROMPT, 2)
		put(PROMPT, 1)
		put(GUIDE_STATE, GuideState.RECORD_WAIT)


## FUN_800B680C: the button sounds of the guide's replay.
func _button_sounds(player: int, word: int) -> void:
	for i in range(0, PLAYER_SOUNDS.size(), 2):
		if word & PLAYER_SOUNDS[i]:
			g.sim.events.add(SimEvents.Kind.SOUND, -1, PLAYER_SOUNDS[i + 1], player)


## FUN_800B4818: the player is in an attack, or the dummy left its stance after a hit.
func _acting(f: FighterState, o: FighterState) -> bool:
	var attacking := f.pose_move.active_first != 0 or (f.move_row != null and f.move_row.active_first != 0)
	var moved := o.cur_slot != o.pose_move.stance_slot and (o.was_hit_this_move != 0 or o.react_chain != 0)
	return attacking or moved


## A player's combo counter, damage and labels (the hits the player takes).
func _player_data(f: FighterState, o: FighterState) -> void:
	var p := f.player_index
	if f.last_extra_damage != 0:
		s.put16(pd(p, D_HITS), s.s16(pd(p, D_HITS)) + 1)
	if o.move_changed != 0:
		s.put16(pd(p, D_HITS), 0)
	if o.throw_state < 1:
		put(pd(p, D_HIT_ID), 0)
	_throw_flag(p, o)
	_count_combo(p, f, o)
	_combo_markers(p)
	if f.hit_clean != 0:
		put(pd(p, D_COUNTER), 1 if f.counter_hit != 0 else 0)
		put(pd(p, D_CLEAN), 1 if f.close_hit != 0 else 0)
	if f.throw_state < 0:
		put(pd(p, D_COUNTER), 0)
		put(pd(p, D_CLEAN), 0)
	_damage(p, f)


## Whether the opponent's move is a throw (move flag 13, or one of a few slots of banks 4, 7 and
## 0xC), and whether its previous one was.
func _throw_flag(p: int, o: FighterState) -> void:
	if o.move_changed == 0:
		return
	put(pd(p, D_THROW_BEFORE), b(pd(p, D_THROW)))
	var throw := 1 if o.pose_move.flags & MoveFlag.BUFFER_INPUT else 0      # the overlay tests bit 13
	var slot := o.cur_slot & 0xFFFF
	if o.bank_type == BankType.YOSHIMITSU and slot in [0x12D, 0x131, 0x136, 0x484]:
		throw = 1
	if o.bank_type == BankType.XIAOYU and slot - 0x5A1 >= 0 and slot - 0x5A1 < 3:
		throw = 1
	if o.bank_type == BankType.BRYAN and slot - 0x832 >= 0 and slot - 0x832 < 3:
		throw = 1
	put(pd(p, D_THROW), throw)


## The combo counter: kept while the opponent reacts, counting hits and throw steps, up to 99.
func _count_combo(p: int, f: FighterState, o: FighterState) -> void:
	var no_throw := b(pd(p, D_THROW)) == 0 or b(pd(p, D_THROW_BEFORE)) == 0
	if f.hit_clean == 0 and f.last_extra_damage == 0:
		if no_throw:
			if f.was_hit_this_move == 0 and f.react_chain == 0:
				put(pd(p, D_COMBO), 0)
		elif o.whiffed != 0:
			put(pd(p, D_COMBO), 0)
	elif f.throw_state < 0:
		if f.last_extra_damage == 0:
			put(pd(p, D_COMBO), b(pd(p, D_COMBO)) + 1)
		elif sb(pd(p, D_HIT_ID)) != o.throw_state:
			if not (o.bank_type == BankType.KING and o.cur_slot == 0xB82):
				put(pd(p, D_COMBO), b(pd(p, D_COMBO)) + 1)
			put(pd(p, D_HIT_ID), o.throw_state)
	elif f.react_chain == 0 and no_throw:
		put(pd(p, D_COMBO), 1)
	else:
		put(pd(p, D_COMBO), b(pd(p, D_COMBO)) + 1)
	if sb(pd(p, D_COMBO)) > 99:
		put(pd(p, D_COMBO), 0)
		s.put16(pd(p, D_MARKER), 0x5A)
	if sb(pd(p, D_COMBO)) > 98:
		put(pd(p, D_COMBO), 99)


## A new best or an ended combo, and the marker's frames (90 on a new best or a multi-hit move).
func _combo_markers(p: int) -> void:
	put(pd(p, D_NEW_BEST), 0)
	put(pd(p, D_ENDED), 0)
	var combo := sb(pd(p, D_COMBO))
	if combo != sb(pd(p, D_PREVIOUS)):
		if sb(pd(p, D_PREVIOUS)) < combo:
			put(pd(p, D_NEW_BEST), combo)
			put(pd(p, D_BEST), combo)
		if combo == 0:
			put(pd(p, D_ENDED), b(pd(p, D_PREVIOUS)))
	if combo >= 2 and b(pd(p, D_NEW_BEST)) != 0:
		s.put16(pd(p, D_MARKER), 0x5A)
	if combo < 2 and s.s16(pd(p, D_HITS)) > 1:
		s.put16(pd(p, D_MARKER), 0x5A)
	if s.s16(pd(p, D_MARKER)) > 0:
		s.put16(pd(p, D_MARKER), s.s16(pd(p, D_MARKER)) - 1)
	put(pd(p, D_PREVIOUS), b(pd(p, D_COMBO)))


## The hit's shown damage and share, the combo damage (capped at ±999) and the total.
func _damage(p: int, f: FighterState) -> void:
	var hs := f.hit_slots[f.best_hit_slot]
	var add := 0
	if f.got_hit == 0 and f.hit_clean == 0 and f.last_extra_damage == 0:
		add = Fx.s16(hs.damage)
	else:
		var shown := f.last_extra_damage
		var share := shown
		if share == 0:
			shown = 0
			if f.hit_clean != 0:
				shown = Fx.s16(hs.base_damage)
				share = Fx.s16(hs.damage)
		s.put16(pd(p, D_HIT_DAMAGE), shown)
		s.put16(pd(p, D_HIT_SHARE), share)
		if sb(pd(p, D_COMBO)) < 2 and s.s16(pd(p, D_HITS)) < 2:
			s.put32(pd(p, D_COMBO_DAMAGE), share)
		else:
			var v := s.s32(pd(p, D_COMBO_DAMAGE)) + share
			s.put32(pd(p, D_COMBO_DAMAGE), v)
			s.put32(pd(p, D_SHOWN_DAMAGE), v)
		if s.s32(pd(p, D_COMBO_DAMAGE)) > 999:
			s.put32(pd(p, D_COMBO_DAMAGE), 0)
			s.put32(pd(p, D_SHOWN_DAMAGE), 999)
		if s.s32(pd(p, D_COMBO_DAMAGE)) < -999:
			s.put32(pd(p, D_COMBO_DAMAGE), 0)
			s.put32(pd(p, D_SHOWN_DAMAGE), -999)
		add = f.last_extra_damage
		if add < 1:
			add = Fx.s16(hs.damage)
	s.put32(pd(p, D_TOTAL), s.s32(pd(p, D_TOTAL)) + add)


# ---- the replay settings (FUN_800B8D50) --------------------------------------------------------

func _replay_control(dummy: FighterState, me: FighterState) -> void:
	var fight := g.fight
	var d := PLAYER_DATA + 0x20 * dummy.player_index
	if b(d + D_COMBO) == 0 and b(d + D_LAST) != 0:
		put(d + D_DROPPED, b(d + D_LAST))
	else:
		put(d + D_DROPPED, 0)
	put(d + D_LAST, b(d + D_COMBO))
	if fight.replay.mode == ReplayState.DONE:
		fight.replay.reset()
		g.sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
		FighterSounds.script_stop(dummy)
		FighterSounds.script_stop(me)
		s.put16(REPLAY_FRAMES, 0)
		g.sim.camera.restart(dummy, me)
		s.put16(REPLAY_FRAMES, 0)
	if fight.replay_playing != 0:
		return
	if b(PAUSED) == 0:
		if sb(REPLAY_SETTING) == MANUAL:
			s.put16(COMBO_FRAMES, 0)
		elif b(d + D_DROPPED) == 0 and b(d + D_COMBO) == 0 and b(ACTING + me.player_index) != 0:
			s.put16(COMBO_FRAMES, me.pose_move.length)
		else:
			s.put16(COMBO_FRAMES, s.u16(COMBO_FRAMES) + 1)
		s.put16(REPLAY_FRAMES, mini(s.u16(REPLAY_FRAMES) + 1, REPLAY_MAX))
	else:
		s.put16(COMBO_FRAMES, 0)
	if s.u16(REPLAY_FRAMES) < REPLAY_MIN:
		return
	var start := false
	match sb(REPLAY_SETTING):
		1:
			start = sb(d + D_ENDED) >= 4
		2:
			start = sb(d + D_ENDED) >= 5
		3:
			start = sb(d + D_ENDED) >= 6
		MANUAL:
			if s.u16(PRESSED) & PadState.SELECT:
				s.put16(REPLAY_FRAMES, mini(s.u16(REPLAY_FRAMES), 0x118))
				start = s.u16(REPLAY_FRAMES) >= REPLAY_MIN
	if not start:
		return
	var frames := s.u16(REPLAY_FRAMES)
	if sb(REPLAY_SETTING) != MANUAL and s.u16(COMBO_FRAMES) != 0:
		frames = s.u16(COMBO_FRAMES) + 0x1E
	frames = mini(frames, s.u16(REPLAY_FRAMES))
	frames = clampi(frames, REPLAY_MIN, REPLAY_MAX)
	s.put16(REPLAY_FRAMES, 0)
	s.put16(COMBO_FRAMES, 0)
	s.put16(PRESSED, s.u16(PRESSED) & 0xFEFF)
	fight.replay.start(fight, frames - 2)
	g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
	g.sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	FighterSounds.script_stop(dummy)
	FighterSounds.script_stop(me)


# ---- the pause menu (practice_sim.menu_cursor, menu_input) ----------------------------------

## FUN_800B4BA8: up/down on the repeat pad, wrapping at 0 and `last`.
func _cursor_step(cur: int, last: int) -> int:
	var rep := s.u16(REPEAT)
	if rep & PadState.DOWN:
		cur += 1
		g.sound(SOUND_MOVE)
	elif rep & PadState.UP:
		cur -= 1
		g.sound(SOUND_MOVE)
	var v := Fx.s8(cur)
	return last if v < 0 else (0 if last < v else v)


## FUN_800B49C4.
func _menu_cursor() -> void:
	if b(MODE_SELECT) != 0:
		var old := sb(SUB)
		var new := _cursor_step(old, 4)
		put(SUB, new)
		if new == old:
			return
		var me := b(PLAYER)
		match new:
			0:
				_puts([ATTACK_DATA, 1, GUIDE, 0, COMMAND_LIST, 0, SWAP, 0, COMBO_TYPE, 0, COMBO_PLAYER, me])
				replay_reset(me)
				key_ring_reset(b(PLAYER))
				put(PROMPT, 1)
			1:
				for at: int in [COUNTER_ATTACKS, REPLAY_SETTING, GUIDE, COMMAND_LIST, SWAP, COMBO_TYPE]:
					put(at, 0)
				put(COMBO_PLAYER, me)
				replay_reset(me)
				key_ring_reset(b(PLAYER))
				put(PROMPT, 1)
			2:
				put(COMBO_PLAYER, me)
				_puts([COUNTER_ATTACKS, 0, REPLAY_SETTING, 0, KEY_DISPLAY, 1, GUIDE, 0, COMMAND_LIST, 0, SWAP, 0, DUMMY, 0, COMBO_TYPE, 0])
				replay_reset(sb(COMBO_PLAYER))
				key_ring_reset(sb(COMBO_PLAYER))
				put(PROMPT, 2)
		return
	var sub := sb(SUB)
	if sub >= 0 and sub < 3:
		var at: int = ITEM_ROW_CURSORS[sub]
		put(at, _cursor_step(sb(at), ITEM_ROW_LAST[sub]))


## FUN_800B4C44.
func _menu_input() -> void:
	if b(MODE_SELECT) != 0:
		_mode_select_confirm()
	else:
		_item_input()


## FUN_800B4C8C.
func _mode_select_confirm() -> void:
	var sub := sb(SUB)
	if s.u16(PRESSED) & CHOOSE == 0 or sub < 0 or sub > 4:
		return
	if sub == 3:
		g.fight.round_state = REQUEST_SELECT
		g.sound(SOUND_OK)
		return
	if sub == 4:
		g.fight.round_state = REQUEST_LEAVE
		return
	_puts([MODE_SELECT, 0, CURSOR_FREE, 0, CURSOR_VS, 0, CURSOR_COMBO, 0, CHANGED, 0, MENU_DELAY, 3])
	if sb(SUB) == 2:
		_puts([COMBO_PLAYER, b(PLAYER), COMBO_TYPE, 0, GUIDE, 1, KEY_DISPLAY, 1, PROMPT, 1])
		key_ring_reset(sb(COMBO_PLAYER))
		replay_reset(sb(COMBO_PLAYER))
		load_guide(sb(COMBO_PLAYER), sb(COMBO_TYPE))
	g.sound(SOUND_OK)


func _changed() -> void:
	put(CHANGED, 0)
	g.sound(SOUND_MOVE)


## Left or right flips a byte; true when a face button was pressed instead.
func _toggle(at: int) -> bool:
	var p := s.u16(PRESSED)
	if p & CHOOSE:
		return true
	if p & 0xA000:
		put(at, (b(at) + 1) & 1)
		_changed()
	return false


## Right adds one, left takes one (both may apply), wrapping at 0 and `last`.
func _cycle(at: int, last: int) -> bool:
	var p := s.u16(PRESSED)
	if p & CHOOSE:
		return true
	if p & 0x2000:
		put(at, b(at) + 1)
		_changed()
	if s.u16(PRESSED) & 0x8000:
		put(at, b(at) - 1)
		_changed()
	var v := sb(at)
	put(at, last if v < 0 else (0 if last < v else v))
	return false


func _guide_changed() -> void:
	key_ring_reset(sb(COMBO_PLAYER))
	replay_reset(sb(COMBO_PLAYER))
	load_guide(sb(COMBO_PLAYER), sb(COMBO_TYPE))
	_changed()


## The item under the cursor (FUN_800B4E4C, jump table 0x800B0A58).
func item_under_cursor() -> int:
	var sub := sb(SUB)
	if sub < 0 or sub >= 3:
		return 0
	return g.data.practice_rows[sub][sb(ITEM_ROW_CURSORS[sub])]


func _item_input() -> void:
	var item := item_under_cursor()
	var p := s.u16(PRESSED)
	var back := false
	match item:
		Item.RESUME:
			if p & CHOOSE:
				resume()
		Item.ATTACK_DATA, Item.COUNTER_ATTACKS, Item.FREEZE_SIGNAL:
			var fields: Array[int] = [0, ATTACK_DATA, COUNTER_ATTACKS, FREEZE_SIGNAL]
			back = _toggle(fields[item])
		Item.REPLAY:
			back = _cycle(REPLAY_SETTING, 3 if sb(SUB) == 2 else 4)
		Item.KEY_DISPLAY:
			if p & CHOOSE:
				back = true
			elif p & PadState.HORIZONTAL:
				put(KEY_DISPLAY, (b(KEY_DISPLAY) + 1) & 1)
				key_ring_reset(b(PLAYER))
				key_ring_reset(b(OTHER))
				_changed()
		Item.GUIDE:
			if p & CHOOSE:
				back = true
			elif p & PadState.HORIZONTAL:
				put(GUIDE, (b(GUIDE) + 1) & 1)
				_changed()
				key_ring_reset(0)
				key_ring_reset(1)
		Item.COMMAND_LIST:
			_command_list_item(p)
		Item.CPU_DIFFICULTY:
			back = _cycle(CPU_DIFFICULTY, 2)
		Item.CPU_LEVEL:
			back = _cycle(CPU_LEVEL, 9)
		Item.CHARACTER_SELECT:
			if p & CHOOSE:
				g.fight.round_state = REQUEST_SELECT
				g.sound(SOUND_MOVE)
		Item.EXIT:
			if p & CHOOSE:
				g.fight.round_state = REQUEST_LEAVE
		Item.DUMMY:
			back = _cycle(DUMMY, 8)
		Item.MODE_SELECT:
			if p & CHOOSE:
				put(MODE_SELECT, 1)
				put(MENU_DELAY, 3)
				if sb(SUB) == 2:
					key_ring_reset(sb(COMBO_PLAYER))
					replay_reset(sb(COMBO_PLAYER))
		Item.COMBO_PLAYER:
			if p & CHOOSE:
				back = true
			elif p & PadState.HORIZONTAL:
				put(COMBO_PLAYER, (b(COMBO_PLAYER) + 1) & 1)
				put(COMBO_TYPE, 0)
				_guide_changed()
		Item.COMBO_TYPE:
			back = _combo_type_item(p)
	if back and sb(SUB) >= 0 and sb(SUB) < 3:
		put(ITEM_ROW_CURSORS[sb(SUB)], 0)


## COMMAND LIST: a choice button opens or closes the move lists, which then take the input.
func _command_list_item(p: int) -> void:
	if p & CHOOSE:
		put(COMMAND_LIST, (b(COMMAND_LIST) + 1) & 1)
		put(MENU_DELAY, 3)
		# FUN_80048760's horizon band: covered by the remake's scene (MoveListScreen).
		if b(COMMAND_LIST) != 0:
			g.fight.pause_delay = 3
		else:
			for at: int in [CHANGED, CURSOR_FREE, CURSOR_VS, CURSOR_COMBO]:
				put(at, 0)
	if b(COMMAND_LIST) != 0:
		# The player's list, and the dummy's while it is on CONTROLLER.
		var mask := 1 << b(PLAYER)
		if sb(DUMMY_KIND) == 0:
			mask |= 1 << b(OTHER)
		MoveListScreen.practice_page(g.fight, mask, b(PLAYER), g.sim.pads, g.sim.events)


## The combo type: left / right cycle through the character's combos; true to go back.
func _combo_type_item(p: int) -> bool:
	if p & CHOOSE:
		return true
	var changed := false
	if p & PadState.RIGHT:
		changed = true
		put(COMBO_TYPE, b(COMBO_TYPE) + 1)
	if s.u16(PRESSED) & PadState.LEFT:
		changed = true
		put(COMBO_TYPE, b(COMBO_TYPE) - 1)
	var v := sb(COMBO_TYPE)
	if v < 0:
		put(COMBO_TYPE, combo_count() - 1)
	elif combo_count() - 1 < v:
		put(COMBO_TYPE, 0)
	if changed:
		_guide_changed()
	return false
