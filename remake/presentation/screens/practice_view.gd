class_name PracticeView
extends FightCanvas
## PRACTICE MODE's drawing over the fight (practice_sim.py: pause_page, menu_backdrop,
## practice_hud): the pause menu's pages on their dark blue panel, the prompts, the attack data
## with the combo counters, the hit markers at their screen points, and the key display along the
## bottom.

const S := PracticeMode.BASE
const X0 := 0x48
const VALUE_COLUMNS := 0x19
const STR_MODE_SELECT := 0x800B0C1C
const STR_FREE := 0x800B0C30
const STR_VS_CPU := 0x800B0C40
const STR_COMBO := 0x800B0C50
const STR_PLAYER_SELECT := 0x800B0C68
const STR_RESET := 0x800B0C80
const STR_VS_CPU_TITLE := 0x800B0D20
const STR_COMMAND_LIST := 0x800B0C9C
const STR_TRAINING_DUMMY := 0x800B0CAC
const STR_COUNTER := 0x800B0CC0
const STR_ATTACK_DATA := 0x800B0CD0
const STR_FREEZE := 0x800B0CDC
const STR_REPLAY := 0x800B0CEC
const STR_KEY_DISPLAY := 0x800B0CFC
const STR_RETURN := 0x800B0D08
const STR_CPU_DIFFICULTY := 0x800B0D30
const STR_CPU_LEVEL := 0x800B0D40
const STR_COMBO_PLAYER := 0x800B0D4C
const STR_COMBO_TYPE := 0x800B0D68
const STR_NONE := 0x800B0D74
const OFF_ON := 0x800B9050
const OK_CANCEL := 0x800B9058
const DUMMY_NAMES := 0x800B9060
const REPLAY_NAMES := 0x800B9084
const DIFFICULTY_NAMES := 0x800B90A4
const LEVEL_NAMES := 0x800B90B0
const COMBO_NAMES := 0x800B90E4
const TECH_ROLL_LINES := 0x800B9160
const HUD_FMT_NUMBER := 0x800B0E8C
const HUD_FMT_COMBO := 0x800B0E98
const HUD_FMT_DAMAGE := 0x800B0EA8
const HUD_TOTAL := 0x800B0E18
const HUD_DMG := 0x800B0E2C
const HUD_COUNTER := 0x800B0E44
const HUD_CLEAN := 0x800B0E54
const HUD_REPLAY_SELECT := 0x800B0E00
const HUD_PLAY_SELECT := 0x800B0D7C
const HUD_PLAY_REC := 0x800B0D90
const HUD_PROMPTS := {PracticeMode.GuideState.RECORD_WAIT: [0x800B0DAC, 1], PracticeMode.GuideState.RECORDING: [0x800B0DC8, 2],
	PracticeMode.GuideState.GUIDE_PLAY: [0x800B0DE0, 5], PracticeMode.GuideState.GUIDE_MODE: [0x800B0DEC, 6]}
const MARKER_UV := 0x800B9154
const ARROWS := 0x800B0EDC
const MARKER_KINDS := {0x217: 1, 0x31F: 1, 0x51F: 1, 0x10F: 2, 0x607: 3, 0x706: 3, 0x800: 4}
const ARROW_INDEX := {0x1000: 1, 0x3000: 2, 0x2000: 3, 0x6000: 4, 0x4000: 5, 0xC000: 6, 0x8000: 7, 0x9000: 8}

var flow: GameFlow
var practice: PracticeMode
var camera: Camera3D                 ## the fight's camera: the hit markers' projection
var frame_count := 0
var _rows := PackedInt32Array()      ## per menu row its colour (the drawing's own table at S+0x8C)


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage) -> void:
	setup_psx(hud_data, game_ram, image)


func show_state(game: GameFlow) -> void:
	flow = game
	practice = game.practice
	frame_count = game.fight.vblank
	redraw()


func _b(at: int) -> int:
	return practice.s.u8(at)


func _sb(at: int) -> int:
	return practice.s.s8(at)


func _draw() -> void:
	begin()
	if flow == null or flow.region.mode != GameMode.PRACTICE:
		return
	if _b(PracticeMode.PAUSED) != 0:
		# While COMMAND LIST is on the move lists (MoveListView) take the screen.
		if _b(PracticeMode.COMMAND_LIST) == 0:
			_backdrop()
			_page()
	else:
		_hud()


# ---- the pause menu -------------------------------------------------------------------------

## FUN_800B6DA0: the dark blue panel in its light grey frame.
func _backdrop() -> void:
	if _b(PracticeMode.MODE_SELECT) != 0:
		fill(7, 0x26, 0xAE, 0xC4, psx(0xE0E0E0))
		fill(8, 0x28, 0xAC, 0xC0, psx(0x301000))
	elif _b(PracticeMode.SUB) < 3:
		fill(0x3F, 0x26, 0xF2, 0x140, psx(0xE0E0E0))
		fill(0x40, 0x28, 0xF0, 0x13C, psx(0x301000))


func _colours(cursor_field: int) -> void:
	_rows = PackedInt32Array()
	_rows.resize(0x11)
	_rows.fill(0xB)
	var c := _sb(cursor_field)
	if c >= 0 and c < _rows.size():
		_rows[c] = 0xA


func _label(row: int, y: int, label: String) -> void:
	text(label, 0, _rows[row], X0, y)


func _value(row: int, y: int, table: int, index: int) -> void:
	var v := ram.string(ram.u32(table + 4 * index))
	text(v, 0, _rows[row], X0 + (VALUE_COLUMNS - v.length()) * 9, y)


## FUN_800B57AC: the page of the sub-mode, or MODE SELECT.
func _page() -> void:
	if _b(PracticeMode.MODE_SELECT) != 0:
		ptext(STR_MODE_SELECT, [10, 1, 0x10, 0x38])
		_colours(PracticeMode.SUB)
		var items: Array[int] = [STR_FREE, STR_VS_CPU, STR_COMBO, STR_PLAYER_SELECT, STR_RESET]
		for k in items.size():
			ptext(items[k], [_rows[k], 0, 0x10, 0x6E + 0x16 * k])
		return
	match _b(PracticeMode.SUB):
		0: _page_free()
		1: _page_vs_cpu()
		2: _page_combo()


func _head(title: int, cursor_field: int) -> void:
	ptext(title, [10, 1, X0, 0x38])
	_colours(cursor_field)
	_label(0, 0x6E, ram.string(ram.u32(OK_CANCEL + 4 * _b(PracticeMode.CHANGED))))
	_label(1, 0x84, ram.string(STR_COMMAND_LIST))


## FUN_800B5978: the FREE page.
func _page_free() -> void:
	_head(STR_FREE, PracticeMode.CURSOR_FREE)
	var y := 0xA2
	_label(2, y, ram.string(STR_TRAINING_DUMMY))
	y += 0x16
	var dummy := _sb(PracticeMode.DUMMY)
	if dummy == 6 or dummy == 7:
		_tech_roll(dummy - 6, X0 + 0x7E, y, _rows[2])
	else:
		_value(2, y, DUMMY_NAMES, dummy)
	y += 0x16
	_label(3, y, ram.string(STR_COUNTER))
	_value(3, y, OFF_ON, _b(PracticeMode.COUNTER_ATTACKS))
	_tail(4, y + 0x16, true)


## FUN_800B5ED4: the VS CPU page.
func _page_vs_cpu() -> void:
	_head(STR_VS_CPU_TITLE, PracticeMode.CURSOR_VS)
	var y := 0xA2
	_label(2, y, ram.string(STR_CPU_DIFFICULTY))
	_value(2, y, DIFFICULTY_NAMES, _sb(PracticeMode.CPU_DIFFICULTY))
	y += 0x16
	_label(3, y, ram.string(STR_CPU_LEVEL))
	_value(3, y, LEVEL_NAMES, _sb(PracticeMode.CPU_LEVEL))
	_tail(4, y + 0x16, true)


## FUN_800B6368: the COMBO TRAINING page.
func _page_combo() -> void:
	_head(STR_COMBO, PracticeMode.CURSOR_COMBO)
	var y := 0xA2
	var pl := _sb(PracticeMode.COMBO_PLAYER)
	ptext(STR_COMBO_PLAYER, [_rows[2], 0, X0, y, pl + 1])
	var key := flow.fight.fighters[clampi(pl, 0, 1)].costume_key
	text(str(flow.fight.tables.character(0x58 if key > 0x5C else key)["name"]), 0, _rows[2], X0 | 0x87, y)
	y += 0x16
	_label(3, y, ram.string(STR_COMBO_TYPE))
	if _combo_count() != 0:
		_value(3, y, COMBO_NAMES, _sb(PracticeMode.COMBO_TYPE))
	else:
		text(ram.string(STR_NONE), 0, _rows[3], X0 + 0xBD, y)
	_tail(4, y + 0x16, false)


func _combo_count() -> int:
	return practice.combo_count()


## ATTACK DATA, FREEZE SIGNAL, REPLAY SETTINGS (and KEY DISPLAY), then RETURN TO MODE SELECT.
func _tail(row: int, y: int, key_display: bool) -> void:
	var rows: Array = [[STR_ATTACK_DATA, OFF_ON, PracticeMode.ATTACK_DATA, false],
		[STR_FREEZE, OFF_ON, PracticeMode.FREEZE_SIGNAL, true], [STR_REPLAY, REPLAY_NAMES, PracticeMode.REPLAY_SETTING, true]]
	if key_display:
		rows.append([STR_KEY_DISPLAY, OFF_ON, PracticeMode.KEY_DISPLAY, false])
	for i in rows.size():
		var e: Array = rows[i]
		_label(row, y, ram.string(e[0] as int))
		var field: int = e[2]
		_value(row, y, e[1] as int, _sb(field) if e[3] else _b(field))
		if i < rows.size() - 1:
			row += 1
		y += 0x16
	text(ram.string(STR_RETURN), 0, _rows[row + 1], X0, 0x148)


## FUN_800B7704: TECH ROLL with an up or down arrow for its 'u' / 'd' marks.
func _tech_roll(which: int, x: int, y: int, colour: int) -> void:
	_arrow_line(ram.string(ram.u32(TECH_ROLL_LINES + 4 * which)), x, y, colour)


## A line with an up or down arrow sprite in place of each 'u' / 'd'.
func _arrow_line(line: String, x: int, y: int, colour: int) -> void:
	var clut := ((((colour >> 4) + 0x18) & 0x1F) + 0x1E0) << 6 | (colour & 0xF) | 0x10
	var cx := x
	for i in line.length():
		var c := line.unicode_at(i)
		if c == 0x75 or c == 0x64:
			sprt(cx, y, 0xA, 0x10, (clut << 16) | (0xE078 if c == 0x75 else 0xE082), 6)
		cx += 9
	text(line.replace("u", " ").replace("d", " "), 0, colour, x, y)


# ---- the practice HUD -----------------------------------------------------------------------

## FUN_800B6898: the prompts, the attack data, the hit markers and the key display.
func _hud() -> void:
	if flow.fight.practice_intro != 0:
		return
	var sub := _sb(PracticeMode.SUB)
	var prompt: Array = []
	if _b(PracticeMode.GUIDE) != 0 and not (sub == 2 and _combo_count() == 0):
		var k := _sb(PracticeMode.GUIDE_STATE)
		if k == PracticeMode.GuideState.READY:
			prompt = [HUD_PLAY_SELECT, 1] if sub == 2 else [HUD_PLAY_REC, 7]
		elif HUD_PROMPTS.has(k):
			prompt = HUD_PROMPTS[k]
	elif _b(PracticeMode.PAUSED) == 0 and _sb(PracticeMode.REPLAY_SETTING) == 4 and sub == 0:
		prompt = [HUD_REPLAY_SELECT, 1]
	if _b(PracticeMode.KEY_DISPLAY) != 0:
		_key_display()
	if _b(PracticeMode.ATTACK_DATA) != 0 and _b(PracticeMode.PAUSED) == 0:
		_markers()
		_attack_data()
	if not prompt.is_empty():
		if prompt[0] == HUD_PLAY_REC and ram.locale != null and ram.locale.english:
			# The USA release (FUN_800B6248) writes the line with a down arrow through its
			# QUICK ROLL routine, then its first letter again in colour 5.
			_arrow_line(ram.locale.practice_prompt, 9, 0x17B, 7)
			print_fmt("%c%h%vP", [5, 1, 0x15])
		else:
			ptext(prompt[0] as int, [prompt[1], 1, 0x15])


func _attack_data() -> void:
	var me := practice.pd(_b(PracticeMode.PLAYER), 0)
	var d := practice.pd(_b(PracticeMode.OTHER), 0)
	var s := practice.s
	# The last hit's damage (+0xE) against the best of the move (+0xC).
	var dmg := s.s16(d + PracticeMode.D_HIT_SHARE)
	var top := s.s16(d + PracticeMode.D_HIT_DAMAGE)
	ptext(HUD_TOTAL, [1, 0x17, 3, s.u32(me + PracticeMode.D_TOTAL)])
	ptext(HUD_TOTAL, [1, 1, 3, s.u32(d + PracticeMode.D_TOTAL)])
	var hits := s.s8(d + PracticeMode.D_BEST)
	if hits >= 2 and s.s16(d + PracticeMode.D_MARKER) != 0 and s.s32(d + PracticeMode.D_SHOWN_DAMAGE) > 0:
		_combo_counter(hits, s.s32(d + PracticeMode.D_SHOWN_DAMAGE))
	elif s.s16(d + PracticeMode.D_HITS) >= 2:
		_combo_counter(0, s.s32(d + PracticeMode.D_SHOWN_DAMAGE))
	var col := 7 if top < dmg else (6 if top == dmg else 3)
	var pct := Fx.div_trunc(dmg * 100, top) if top != 0 and dmg != 0 else 0
	ptext(HUD_DMG, [col, 1, 4, dmg, pct])
	if s.u8(d + PracticeMode.D_COUNTER) != 0:
		ptext(HUD_COUNTER, [2, 1, 5])
	if s.u8(d + PracticeMode.D_CLEAN) != 0:
		ptext(HUD_CLEAN, [5, 1, 6])


## FUN_800B6F58: the big `n COMBO` and `n DAMAGE` counters.
func _combo_counter(count: int, damage: int) -> void:
	if count != 0:
		ptext(HUD_FMT_NUMBER, [0xC, 0x88, 1, 6, count])
		ptext(HUD_FMT_COMBO, [0x2A if count >= 10 else 0x20, 0x88, 1, 5])
	ptext(HUD_FMT_NUMBER, [0x16, 0xA6, 1, 6, damage])
	var a := absi(damage)
	var x := 0x40 if a >= 100 else (0x2A if a < 10 else 0x35)
	if damage < 0:
		x += 0xD
	ptext(HUD_FMT_DAMAGE, [x, 0xB0, 0, 7])


## FUN_800B75AC: the markers at the last four hit points (0 high, 1 mid, 2 low, 3 unblockable).
func _markers() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var idx := _b(PracticeMode.MARKER_INDEX)
	for n in 4:
		if idx < 0 or idx > 3:
			idx = 3
		var m := PracticeMode.MARKERS + 8 * idx
		if practice.s.s16(m + 2) != 0:
			var kind: int = MARKER_KINDS.get(practice.s.s16(m), 0)
			if kind != 4:
				var p := practice.marker_points[idx]
				var world := WorldSpace.point(p[0], p[1], p[2])
				if not camera.is_position_behind(world):
					var at := camera.unproject_position(world)
					var x := (at.x - box.position.x) / box.size.x * SCREEN.x + HudFrame.LEFT
					var y := (at.y - box.position.y) / box.size.y * SCREEN.y
					_hit_marker(int(x), int(y), kind)
		idx -= 1


func _hit_marker(x: int, y: int, kind: int) -> void:
	if kind == 3:
		sprt(x - 0x18, y - 0x18, 0x30, 0x30, 0x7FF7C0D0, 0x1F)
		sprt(x - 6, y - 0x18, 0xC, 0x30, 0x7FF6C090, 0x1F)
	else:
		sprt(x - 0x18, y - 0x18, 0x30, 0x30, 0x7FB7C0D0, 0x1F)
		sprt(x - 0x18, y - 8, 0x30, 0x10, ram.u32(MARKER_UV + 4 * kind), 0x1F)


## FUN_800B7C84: the last 15 inputs (directions and new buttons), oldest first.
func _key_display() -> void:
	var s := practice.s
	var head := s.s32(PracticeMode.HEADS + 4 * _sb(PracticeMode.COMBO_PLAYER))
	var guide_end := s.s32(PracticeMode.REPLAY)
	var mode := _b(PracticeMode.PROMPT)
	var dir_col := 0
	var btn_col := 1
	var dir_guide := 0
	var btn_guide := 1
	if mode == 2 or (mode == 3 and _b(PracticeMode.PROMPT_TIMER) & 0x10):
		dir_col = 3
		btn_col = 0
		dir_guide = 3
		btn_guide = 0
	elif mode == 4 or mode == 5:
		dir_guide = 3
		btn_guide = 0
	var i := _wrap(head + 1)
	var items: Array[Vector2i] = []
	var since := 0
	var prev_dir := 0
	var prev_btn := 0
	for n in PracticeMode.RING_WORDS:
		var e := PracticeMode.RING + 4 * i
		if i == 0:
			since = 0
		var d := s.u8(e + 1)
		if d != 0 and d != prev_dir:
			items.append(Vector2i((d << 12) & 0xFFFF, dir_guide if guide_end < i else dir_col))
			since += 1
		var bt := s.u8(e)
		if bt & (bt ^ prev_btn):
			items.append(Vector2i((bt << 4) & 0xFFFF, btn_guide if guide_end < i else btn_col))
			since += 1
		prev_dir = d
		prev_btn = bt
		i = _wrap(i + 1)
	var shown := mini(items.size(), 15)
	if _b(PracticeMode.GUIDE_PROMPT) != 0:
		shown = mini(mini(since, 15), items.size())
	var x := 0xC
	for k in range(items.size() - shown, items.size()):
		var item := items[k]
		if item.x & 0xF000:
			_key_arrow(x, 400, item.x, item.y)
			x += 0x17
		elif item.x & 0xF0:
			_key_button(x, 400, item.x, item.y)
			x += 0x17


static func _wrap(i: int) -> int:
	return 0x31 if i < 0 else (i if i < 0x32 else 0)


## FUN_800B721C: the pressed face buttons' icon.
func _key_button(x: int, y: int, pad: int, guide: int) -> void:
	var idx := (1 if pad & 0x80 else 0) | (2 if pad & 0x10 else 0) | (4 if pad & 0x40 else 0) | (8 if pad & 0x20 else 0)
	var back := ((((1 if guide != 0 else 0) * 0x10 + 0x300) >> 4) & 0x3F) | 0x7F80
	sprt(x, y, 0x14, 0x20, (back << 16) | 0xE014, 6)
	sprt(x, y, 0x14, 0x20, ((((idx & 0x18) << 3) | 0x7F00 | (idx & 7) | 0x30) << 16) | 0xE000, 6)


## FUN_800B7354: a direction arrow (a flipped 19 × 31 quad).
func _key_arrow(x: int, y: int, pad: int, colour: int) -> void:
	var idx: int = ARROW_INDEX.get(pad & 0xF000, 0)
	var base := ram.u16(ARROWS + 4 * idx)
	var flags := ram.u16(ARROWS + 4 * idx + 2)
	var clut: int = {1: 0x7FB3, 2: 0x7FB4, 3: 0x7FB5}.get(colour, 0x7FB2)
	var tex := vram.sprite(base & 0xFF, base >> 8, 0x13, 0x1F, clut, 6)
	var dest := r(x, y, 0x13, 0x1F)
	if flags & 1:
		dest.size.x = -dest.size.x
	if flags & 2:
		dest.size.y = -dest.size.y
	target.draw_texture_rect(tex, dest, false)
