class_name RankingScreen
extends FlowPart
## The ranking (modes.md#ranking-screen): its loading (RankingLoad 0x800504A8, game state 16)
## and the pages (ranking.ovl FUN_800C2A24, game state 17), written from the verified port
## `tools/research/screens_sim.py` (ranking_frame, name_entry, the page tables, the backdrop camera).
## The pages cycle time attack, survivors and usage; after a new time attack or survival record
## the name is entered on its page. Behind the table a stage turns (a stage without fighters).
##
## The table (0x800CBE68): +0 mode (0 hidden, 1 fading in, 2 rows sliding, 3 name entry, 4 name
## entered), +2 y, +4 target y, +6 hold frames, +8 frames per group, +0xA alpha, +0xC rows,
## +0xE u16 per row the character, +0x50 s32 first row of the group, +0x54 rows shown, +0x58 u16
## per character the usage share (‰), +0x84 the top share, +0x86 the name's row on screen, +0x88
## the name's row (0xFFFF none). The name record (0x800D36F8): char[4], +4 u16 position, +6 u8
## pressed, +7 u8 moved, +8 u16 cursor, +0xA u16 character, +0xC u16 player.

const TABLE_BASE := 0x800CBE68
const TABLE_SIZE := 0x8C
const T_MODE := 0                    ## table fields (see above)
const T_Y := 2
const T_TARGET_Y := 4
const T_HOLD := 6
const T_GROUP_FRAMES := 8
const T_ALPHA := 0xA
const T_ROWS := 0xC
const T_CHARS := 0xE
const T_FIRST_ROW := 0x50
const T_SHOWN := 0x54
const T_USAGE := 0x58
const T_TOP_SHARE := 0x84
const T_NAME_SCREEN_ROW := 0x86
const T_NAME_ROW := 0x88
const NAME_BASE := 0x800D36F8
const NAME_SIZE := 0x10
const N_POS := 4                     ## name record fields (see above)
const N_PRESSED := 6
const N_MOVED := 7
const N_CURSOR := 8
const N_CHARACTER := 0xA
const N_PLAYER := 0xC
const BACKDROP_BASE := 0x800D3708
const BACKDROP_SIZE := 0x30
const TIME_CAP := 359_999
const ROW_HEIGHT := 0x48
const ROWS_TOP := 0xA8
const GROUP := 5
const GROUP_FRAMES := 150
const NAME_FRAMES := 3000
const SURVIVORS := 10
const NO_ROW := 0xFFFF
const STAGES := 13
const ORBIT_START := 0xC00
const ORBIT_RADIUS := 5000
const ORBIT_STEP := 3
const EYE_HEIGHT := -0x578


## The table's mode (+0).
enum TableMode { HIDDEN, FADING_IN, SLIDING, NAME_ENTRY, NAME_ENTERED }

## How `name_entry` runs a frame: from the pad, the time ran out, or skipped with Start.
enum NameInput { PAD, TIMEOUT, SKIP }

## The page sub-states of game state 17 (`g.sub`).
enum Sub {
	START = 0, SETUP = 1, FADE_IN_START = 2, FADE_IN = 3, GROUP_START = 4, SLIDE = 5, HOLD = 6,
	SHOW = 7, FADE_OUT_START = 8, FADE_OUT = 9, NAME_SCROLL_START = 0xA, NAME_SCROLL = 0xB,
	NAME_ENTRY = 0xC, NAME_ENTERED = 0xD, LEAVE = 0xE,
}

var table := ByteBlock.new(TABLE_SIZE)
var name := ByteBlock.new(NAME_SIZE)
var backdrop := ByteBlock.new(BACKDROP_SIZE)
var fade := -1                       ## the fade drawn this frame (FUN_8004E2E8 level), −1 none


# ---- loading (game state 16) ------------------------------------------------------------

func load_step() -> void:
	match g.sub:
		0:
			g.display(0)
			g.music_stop()
			g.sub = 1
		1:
			g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
			g.controllers_reset()
			if g.progress.name_entry == 0:
				g.auto_save()
			g.queue_overlay(GameFlow.SLOT_SCREEN, GameFlow.OVERLAY_RANKING)
			g.goto_loader(GameFlow.State.RANKING_LOAD, 2)
		2, 3:
			g.sub += 1
		4, 5:
			if g.sub == 4:
				_backdrop_setup()
				g.sub = 5
			if g.auto_save_error():
				return
			g.state = GameFlow.State.RANKING
			g.sub = 0


## FUN_800C390C: the stage behind the ranking (the next of the cycle, skipping four) and its camera.
func _backdrop_setup() -> void:
	var progress := g.progress
	var fight := g.fight
	g.region.mode = 6
	fight.true_ogre_mask = 0
	fight.attract = 1
	var stage := 0
	while true:
		stage = progress.ranking_stage % STAGES
		progress.ranking_stage = stage
		if stage not in g.data.ranking_skipped:
			break
		progress.ranking_stage = stage + 1
	progress.ranking_stage = stage + 1
	fight.stage = stage
	fight.stage_cached = stage        # FUN_80036BC8 empties the cache and reads the stage,
	fight.backdrop.setup(g.sim.camera.view)   # and sets its panorama up (FUN_8006CC44)
	backdrop.put16(0x28, ORBIT_START)
	var t := fight.tables
	backdrop.put16(0x24, _round12(FightMath.cos12(ORBIT_START, t) * ORBIT_RADIUS))
	backdrop.put16(0x26, _round12(FightMath.cos12(0x800, t) * ORBIT_RADIUS))
	fight.fighters[0].root_x = -1000
	fight.fighters[1].root_x = 1000
	fight.fighters[0].root_z = 0
	fight.fighters[1].root_z = 0
	backdrop.put32(0x14, backdrop.s16(0x24))
	backdrop.put32(0x18, EYE_HEIGHT)
	backdrop.put32(0x1C, backdrop.s16(0x26))
	for at: int in [0, 4, 8]:
		backdrop.put32(at, 0)


static func _round12(v: int) -> int:
	return (v + 0xFFF if v < 0 else v) >> 12


## FUN_800C3AAC: the camera turns around the stage (its eye at +0x14 … +0x1C); FUN_80046458 makes
## it the game's camera, and the background (FUN_8006DAB4) turns the panorama with it.
func _backdrop_camera() -> void:
	backdrop.put32(4, backdrop.s32(4) - ORBIT_STEP)
	var a := (backdrop.u16(0x28) - ORBIT_STEP) & 0xFFF
	backdrop.put16(0x28, a)
	var t := g.fight.tables
	backdrop.put16(0x24, _round12(FightMath.cos12(a, t) * ORBIT_RADIUS))
	backdrop.put16(0x26, _round12(FightMath.sin12(a, t) * ORBIT_RADIUS))
	backdrop.put32(0x14, backdrop.s16(0x24))
	backdrop.put32(0x1C, backdrop.s16(0x26))
	var view := g.sim.camera.view
	view.pitch = backdrop.s32(0)
	view.yaw = backdrop.s32(4)
	view.roll = backdrop.s32(8)
	view.x = backdrop.s32(0x14)
	view.y = backdrop.s32(0x18)
	view.z = backdrop.s32(0x1C)
	g.sim.background()


# ---- the pages (game state 17) ----------------------------------------------------------

func step() -> void:
	fade = -1
	var sub := g.sub
	if sub > Sub.SETUP and g.pressed_any() & PadState.START:
		_skip_to_menu()
		return
	if sub == Sub.START:
		_page_from_pad()
		sub = Sub.SETUP
		g.sub = Sub.SETUP
	if sub == Sub.SETUP:
		_set_up_page()
		_draw()
		return
	match sub:
		Sub.FADE_IN_START, Sub.FADE_IN:
			_fade_in(sub == Sub.FADE_IN_START)
		Sub.GROUP_START:
			_group_start()
		Sub.SLIDE:
			_slide()
		Sub.HOLD:
			_hold()
		Sub.SHOW:
			_wait(0x3B)
		Sub.FADE_OUT_START, Sub.FADE_OUT:
			_fade_out(sub == Sub.FADE_OUT_START)
		Sub.NAME_SCROLL_START:
			_name_scroll_start()
		Sub.NAME_SCROLL:
			_name_scroll()
		Sub.NAME_ENTRY:
			_name_entry_frame()
		Sub.NAME_ENTERED:
			_wait(0x77)
		Sub.LEAVE:
			table.put16(T_MODE, TableMode.HIDDEN)
			g.progress.ranking_page = (g.progress.ranking_page + 1) % 3
			g.goto_transition(GameFlow.State.TITLE)
			return
	_draw()


## Start leaves for the main menu, taking a pending name as it stands.
func _skip_to_menu() -> void:
	var progress := g.progress
	var pending := progress.name_entry
	if pending != 0:
		name_entry(NameInput.SKIP)
		_store_name(pending)
		progress.name_entry = 0
		g.rules.request_save()
	g.goto_transition(GameFlow.State.MENU)


## Without a pending name, player 2's stick picks the page: right time attack, left survivors,
## up usage.
func _page_from_pad() -> void:
	var progress := g.progress
	if progress.name_entry != 0:
		return
	var held := g.held(1)
	if held & PadState.RIGHT:
		progress.ranking_page = 0
	elif held & PadState.LEFT:
		progress.ranking_page = 1
	elif held & PadState.UP:
		progress.ranking_page = 2


## The page's table; a pending name (bit 0 time attack, bit 1 survival) opens its page with the
## name entry, a name for neither only shows the usage page.
func _set_up_page() -> void:
	var progress := g.progress
	var pending := progress.name_entry
	if pending != 0:
		if pending & 1 == 0:
			if pending & 2 == 0:
				progress.ranking_page = 2
				progress.name_entry = 0
				return
			progress.ranking_page = 1
			table.put16(T_NAME_ROW, _survivor_page())
		else:
			progress.ranking_page = 0
			table.put16(T_NAME_ROW, _time_page())
		_name_init(progress.entry_player, progress.entry_character)
	else:
		match progress.ranking_page:
			0: _time_page()
			1: _survivor_page()
			2: _usage_page()
		table.put16(T_NAME_ROW, NO_ROW)
	g.sub = Sub.FADE_IN_START
	table.put16(T_HOLD, 0)
	table.put16(T_MODE, TableMode.HIDDEN)


func _fade_in(first: bool) -> void:
	var timer := g.sim.state_timer
	if first:
		table.put16(T_MODE, TableMode.FADING_IN)
		timer = 0
		g.sub = Sub.FADE_IN
	fade = timer
	timer += 8
	g.sim.state_timer = timer
	if timer > 0xFF:
		g.sub = Sub.GROUP_START if g.progress.name_entry == 0 else Sub.NAME_SCROLL_START


func _fade_out(first: bool) -> void:
	var timer := g.sim.state_timer
	if first:
		timer = 0x100
		g.sub = Sub.FADE_OUT
	fade = timer
	timer -= 8
	g.sim.state_timer = timer
	if timer <= 0:
		g.sub = Sub.LEAVE
		table.put16(T_MODE, TableMode.HIDDEN)


## Holds the finished table for `frames` frames, then fades out.
func _wait(frames: int) -> void:
	var timer := g.sim.state_timer + 1
	g.sim.state_timer = timer
	if timer > frames:
		g.sub = Sub.FADE_OUT_START


## The rows slide in from below, the last group first.
func _group_start() -> void:
	var count := table.u16(T_ROWS)
	table.put32(T_SHOWN, count)
	var r := count % GROUP
	if r == 0:
		r = GROUP
	table.put32(T_FIRST_ROW, count - r)
	g.sub = Sub.SLIDE
	table.put16(T_MODE, TableMode.SLIDING)
	table.put16(T_Y, count * -ROW_HEIGHT + ROWS_TOP)


func _slide() -> void:
	var group := table.s32(T_FIRST_ROW)
	table.put16(T_TARGET_Y, group * -ROW_HEIGHT + ROWS_TOP)
	table.put16(T_Y, table.u16(T_Y) + 12)
	if table.s16(T_TARGET_Y) <= table.s16(T_Y):
		table.put16(T_HOLD, 0)
		table.put16(T_ALPHA, 0)
		g.sub = Sub.HOLD
		table.put32(T_SHOWN, group)
		table.put16(T_Y, table.u16(T_TARGET_Y))


## A group's rows fade in and hold, then the next group slides (or the table shows).
func _hold() -> void:
	var hold := table.u16(T_HOLD)
	table.put16(T_ALPHA, mini(hold, 0x40))
	table.put16(T_HOLD, hold + 1)
	if table.u16(T_GROUP_FRAMES) > table.u16(T_HOLD):
		return
	if table.s32(T_FIRST_ROW) < 1:
		g.sim.state_timer = 0
		g.sub = Sub.SHOW
	else:
		g.sub = Sub.SLIDE
		table.put32(T_FIRST_ROW, table.s32(T_FIRST_ROW) - GROUP)


## The table scrolls so the new record's row shows (as the third of five where it can).
func _name_scroll_start() -> void:
	var row := table.u16(T_NAME_ROW)
	var count := table.u16(T_ROWS)
	if row < 2:
		table.put32(T_FIRST_ROW, 0)
		table.put16(T_NAME_SCREEN_ROW, row)
	else:
		table.put32(T_FIRST_ROW, count - GROUP)
		if count - 3 < row:
			table.put16(T_NAME_SCREEN_ROW, GROUP - (count - row))
		else:
			table.put32(T_FIRST_ROW, row - 2)
			table.put16(T_NAME_SCREEN_ROW, 2)
	table.put16(T_ALPHA, 0x40)
	g.sub = Sub.NAME_SCROLL
	table.put32(T_SHOWN, 0)
	table.put16(T_MODE, TableMode.SLIDING)
	table.put16(T_Y, count * -ROW_HEIGHT + ROWS_TOP)


func _name_scroll() -> void:
	var target := (table.s32(T_FIRST_ROW) * -ROW_HEIGHT + ROWS_TOP) & 0xFFFF
	table.put16(T_TARGET_Y, target)
	var step := (Fx.s16(target) - table.s16(T_Y) + 0xF) >> 4
	step = 1 if step == 0 else mini(step, 0x10)
	var y := (table.u16(T_Y) + step) & 0xFFFF
	table.put16(T_Y, y)
	if table.s16(T_TARGET_Y) <= Fx.s16(y):
		table.put16(T_HOLD, NAME_FRAMES)
		table.put16(T_MODE, TableMode.NAME_ENTRY)
		g.sub = Sub.NAME_ENTRY
		table.put16(T_Y, table.u16(T_TARGET_Y))


## One frame of the name entry, which ends when the name is complete or the time runs out.
func _name_entry_frame() -> void:
	var progress := g.progress
	var left := (table.u16(T_HOLD) - 1) & 0xFFFF
	table.put16(T_HOLD, left)
	var done := name_entry(NameInput.TIMEOUT if left == 0 else NameInput.PAD)
	_store_name(progress.name_entry)
	if done:
		progress.name_entry = 0
		g.rules.request_save()
		table.put16(T_MODE, TableMode.NAME_ENTERED)
		g.sim.state_timer = 0
		g.sub = Sub.NAME_ENTERED


## The drawing half: the backdrop camera turns while the table shows.
func _draw() -> void:
	if table.u16(T_MODE) != TableMode.HIDDEN:
		_backdrop_camera()


## The entered name into the new records (time attack, survivors).
func _store_name(pending: int) -> void:
	var progress := g.progress
	var text := entered_name()
	if pending & 1:
		progress.put_name(progress.record_entry - GameProgress.BASE + 4, text)
	if pending & 2:
		progress.put_name(progress.survivor_entry - GameProgress.BASE + 4, text)


## The name so far (up to its terminator).
func entered_name() -> String:
	var s := ""
	for k in 4:
		var c := name.u8(k)
		if c == 0:
			break
		s += char(c)
	return s


# ---- the page tables ------------------------------------------------------------------------

## FUN_800C1D1C: time attack: the ten original characters and every other with a record, fastest
## first; the row of the record just set (−1 none).
func _time_page() -> int:
	var progress := g.progress
	table.put16(T_GROUP_FRAMES, GROUP_FRAMES)
	var mask := 0x3FF
	for c in Opponents.CHARACTERS:
		if progress.time_record(c) < TIME_CAP:
			mask |= 1 << c
	var n := ProgressRules.popcount(mask & 0x1FFFFF)
	table.put16(T_ROWS, n)
	var pairs: Array[Vector2i] = []
	for c in Opponents.CHARACTERS:
		if (mask >> c) & 1:
			pairs.append(Vector2i(c, progress.time_record(c)))
	Opponents.sort_pairs(pairs, true)
	for i in pairs.size():
		table.put16(T_CHARS + 2 * i, pairs[i].x)
	for i in n:
		var at := GameProgress.BASE + GameProgress.TIME_RECORDS + 8 * table.u16(T_CHARS + 2 * i)
		if at == progress.record_entry:
			return i
	return -1


## FUN_800C1E8C and the page set-up: the survivors re-sorted by wins; the row of the entry just
## made (−1 none).
func _survivor_page() -> int:
	var progress := g.progress
	var entry := progress.survivor_entry
	var rows: Array[PackedByteArray] = []
	var pairs: Array[Vector2i] = []
	var found := -1
	for i in SURVIVORS:
		var at := GameProgress.SURVIVORS + 8 * i
		rows.append(progress.bytes.slice(at, at + 8))
		pairs.append(Vector2i(i, progress.u16(at + 2)))
		if GameProgress.BASE + at == entry:
			found = i
	Opponents.sort_pairs(pairs, false)
	for k in SURVIVORS:
		var at := GameProgress.SURVIVORS + 8 * k
		var r := rows[pairs[k].x]
		progress.put16(at, r.decode_u16(0))
		progress.put16(at + 2, r.decode_u16(2))
		var end := 4
		while end < 8 and r[end] != 0:
			end += 1
		progress.put_name(at + 4, r.slice(4, end).get_string_from_ascii())
	if found != -1:
		progress.survivor_entry = GameProgress.BASE + GameProgress.SURVIVORS + 8 * found
	table.put16(T_ROWS, SURVIVORS)
	for k in SURVIVORS:
		table.put16(T_CHARS + 2 * k, k)
	table.put16(T_GROUP_FRAMES, GROUP_FRAMES)
	return found


## FUN_800C1FA8: usage: the ten original characters and every other played, most used first,
## with their shares.
func _usage_page() -> void:
	var progress := g.progress
	var mask := 0x3FF
	var total := 0
	for c in Opponents.CHARACTERS:
		var u := progress.usage(c)
		if u != 0:
			mask |= 1 << c
			total += u
	var n := ProgressRules.popcount(mask & 0x1FFFFF)
	table.put16(T_ROWS, n)
	var pairs: Array[Vector2i] = []
	for c in Opponents.CHARACTERS:
		if (mask >> c) & 1:
			var u := progress.usage(c)
			pairs.append(Vector2i(c, u))
			table.put16(T_USAGE + 2 * c, permille(u, total & 0xFFFFFFFF))
	Opponents.sort_pairs(pairs, false)
	for i in pairs.size():
		table.put16(T_CHARS + 2 * i, pairs[i].x)
	table.put16(T_GROUP_FRAMES, GROUP_FRAMES)
	table.put16(T_TOP_SHARE, table.u16(T_USAGE + 2 * pairs[0].x))


## FUN_8004D008: part · 1000 / total, scaled down to avoid overflow.
static func permille(part: int, total: int) -> int:
	if part > total:
		return 1000
	while total > 0x3FFFFF:
		total >>= 1
		part >>= 1
	return 0 if total == 0 else part * 1000 / total


# ---- the name entry (FUN_800C3438, FUN_800C3480) ------------------------------------------

func _name_init(player: int, character: int) -> void:
	name.put16(N_PLAYER, player)
	name.put16(N_CHARACTER, character)
	_put_text(g.data.ranking_rejected[0])
	name.put16(N_POS, 0)
	name.put16(N_CURSOR, 0)
	name.put8(N_PRESSED, 0)
	name.put8(N_MOVED, 0)


func _put_text(text: String) -> void:
	var raw := text.to_ascii_buffer()
	for k in raw.size():
		name.put8(k, raw[k])
	name.put8(raw.size(), 0)


## The character's name (its first three letters).
func _default_name() -> void:
	var record := g.fight.tables.character(name.u16(N_CHARACTER) * 4)
	var text := str(record["name"]).to_ascii_buffer()
	for i in 3:
		name.put8(i, text[i] if i < text.size() else 0)
	name.put8(3, 0)


func _finish_name() -> void:
	for i in range(name.u16(N_POS), 3):
		name.put8(i, 0x20)
	name.put8(3, 0)
	name.put16(N_POS, 3)
	if entered_name() in g.data.ranking_rejected:
		_default_name()


## FUN_800C3480: one frame of input, the time ran out, or take the character's name (NameInput);
## true when the name is complete.
func name_entry(mode: int) -> bool:
	name.put8(N_PRESSED, 0)
	name.put8(N_MOVED, 0)
	if mode == NameInput.TIMEOUT:
		_finish_name()
		return true
	if mode == NameInput.SKIP:
		_default_name()
		name.put16(N_POS, 3)
		return true
	var player := name.u16(N_PLAYER)
	var pressed := g.pressed(player)
	var rep := g.repeat(player)
	var step := ((rep >> 13) & 1) - (rep >> 15)
	if step != 0:
		name.put8(N_MOVED, 1)
	var symbols := g.data.ranking_alphabet.length()
	var cursor := name.u16(N_CURSOR) + step
	if cursor < 0:
		cursor = symbols - 1
	elif cursor > symbols - 1:
		cursor = 0
	name.put16(N_CURSOR, cursor)
	var pos := name.u16(N_POS)
	var ch := g.data.ranking_alphabet.unicode_at(cursor) if pos < 3 else 0
	name.put8(pos, ch)
	if pressed & GameFlow.FACE_BUTTONS == 0:
		return false
	name.put8(N_PRESSED, 1)
	if ch == ord("<"):
		if pos != 0:
			name.put8(pos, 0x20)
			name.put16(N_POS, pos - 1)
		return false
	if ch == ord("="):
		_finish_name()
		return true
	name.put8(pos, ch)
	pos = (pos + 1) & 0xFFFF
	name.put16(N_POS, pos)
	if pos < 3:
		return false
	if g.progress.unlocked & (1 << Character.GON) == 0:
		var typed := ""
		for i in 3:
			if name.u8(i) == 0:
				break
			typed += char(name.u8(i))
		if typed == g.data.ranking_gon:
			g.rules.unlock_character(Character.GON)
	_finish_name()
	return true
