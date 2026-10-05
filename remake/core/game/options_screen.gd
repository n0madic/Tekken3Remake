class_name OptionsScreen
extends FlowPart
## The options (title.ovl FUN_800DE480, game state 5; modes.md#options), written from the
## verified port `tools/research/menu_sim.py` and the decompiled overlay (its sounds). Pages: 0 OPTION
## MODE, 1 GAME OPTION, 2 RECORDS, 3 MEMORY CARD, 4 KEY CONFIGURATION, 5 DISPLAY ADJUST (hidden in
## the remake: its item is skipped), 6 leaves. MEMORY CARD saves and loads the save file through
## the owner's `save_writer` and `card_loader` with the memory card's results.

const PAGE_LEAVE := 6
const PAGE_DISPLAY_ADJUST := 5
const PAGE_RECORDS := 2
const PAGE_CARD := 3
const PAGE_KEYS := 4
const SOUND_MOVE := 0x546C
const SOUND_OK := 0x4CEB
const SOUND_DONE := 0x4D87
const SOUND_KEY_OPEN := 0x45CA
const CHOOSE := PadState.CONFIRM
const COLOUR_TOGGLE_HELD := 0x103
const TIME_LIMIT := 359_998
const HIDDEN_ITEMS := ["DISPLAY ADJUST"]
## Memory card results (the card calls' codes).
const CARD_DONE := 0
const CARD_NO_CARD := 2
const CARD_UNFORMATTED := 3
const CARD_FULL := 4
const CARD_NO_FILE := 5
const KEY_ROWS := 8
const KEY_ITEMS := 4
const KEY_OPEN_FRAMES := 8
const KEY_ACTIONS := 13
const VIBRATION_PATTERN := 0xD

## A key configuration button row (0x38 bytes in the game).
class KeyRow:
	extends RefCounted
	var state := 0                   ## 0 closed, 1 opening, 2 open, 3 closing
	var button := 0                  ## the button index (0x80098308 + 8·player + button)
	var mask := 0                    ## the button's pad bit
	var open := 0                    ## frames open (0–8)
	var layer := 0
	var layout := PackedInt32Array()
	var colour := 0


## A player's key configuration (0x1E8 bytes in the game).
class KeyRecord:
	extends RefCounted
	var player := 0
	var selected := 0                ## 0 the buttons, 1 VIBRATION, 2 DEFAULT, 3 EXIT
	var armed := 0                   ## a button was pressed on this page
	var busy := 0                    ## a row is open or a setting changed this frame
	var pad_kind := 0                ## 9 analog
	var x := 0
	var y := 0
	var held := 0
	var repeat := 0
	var used := 0                    ## the actions in use (bit per action)
	var rows: Array[KeyRow] = []


var page := 0                        ## 0x800EC5E8
var cursors := PackedInt32Array([0, 0, 0, 0, 0, 0])   ## per page (+0)
var subs := PackedInt32Array([0, 0, 0, 0, 0, 0])      ## per page (+4)
var card_state := 0                  ## 0x800EC63C: 0 the prompt, else the result + 1
var keys: Array[KeyRecord] = []
var record_page := 0                 ## 0x800ECA10
var record_tops := PackedInt32Array([0, 0, 0, 0])
var record_lists: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
var record_total := 0                ## 0x800ECA18: fights of every character
var modes := PackedInt32Array()      ## GAME OPTION's mode pictures shown (Tekken Ball once unlocked)
## Writes the save file: returns a memory card result (0 done, 5 error).
var save_writer: Callable


func _init(flow: GameFlow) -> void:
	super(flow)
	for p in 2:
		var rec := KeyRecord.new()
		for i in KEY_ROWS:
			rec.rows.append(KeyRow.new())
		keys.append(rec)


func items(p: int) -> Array:
	return g.data.option_pages[p]["items"]


func _item(p: int, i: int) -> Dictionary:
	return items(p)[i]


func item_hidden(p: int, i: int) -> bool:
	return str(_item(p, i)["label"]) in HIDDEN_ITEMS


## The value byte of an item (a progress byte, or the page byte).
func item_value(p: int, i: int) -> int:
	var v: Dictionary = _item(p, i)["variable"]
	if v.has("page"):
		return page
	if v.has("progress"):
		return g.progress.u8(JsonFile.number(v["progress"]))
	return 0


func _set_item_value(p: int, i: int, value: int) -> void:
	var v: Dictionary = _item(p, i)["variable"]
	if v.has("page"):
		page = value & 0xFF
	elif v.has("progress"):
		g.progress.put8(JsonFile.number(v["progress"]), value)


func step() -> void:
	if _exit_allowed():
		# Select + Start as outside the demonstration fight.
		var mode := g.region.mode
		g.region.mode = 0
		var left := g.menu_exit()
		g.region.mode = mode
		if left:
			return
	match g.sub:
		2:
			g.goto_transition(GameFlow.State.MENU)
			return
		0:
			g.progress.menu_to_options = 1
			_option_modes()
			key_config_init()
			for i in 6:
				cursors[i] = 0
				subs[i] = 0
			page = 0
			g.sub = 1
	if g.sub != 1:
		return
	match page:
		0, 1:
			_list_input(page)
		PAGE_RECORDS:
			if subs[page] == 0:
				records_init()
				subs[page] += 1
			if records_step():
				subs[page] = 0
				page = JsonFile.number(g.data.option_pages[PAGE_RECORDS]["back_value"])
		PAGE_CARD:
			_card_page()
		PAGE_KEYS:
			if key_config_step():
				page = 0
		PAGE_DISPLAY_ADJUST:
			page = 0
		_:
			g.sub = 2


## Select + Start is ignored while a memory card screen is up.
func _exit_allowed() -> bool:
	return page != PAGE_CARD or subs[PAGE_CARD] in [0, 3]


## The mode pictures of GAME OPTION; Tekken Ball's only once it is unlocked.
func _option_modes() -> void:
	modes = PackedInt32Array()
	for m in g.data.option_modes:
		if m != GameMode.BALL or g.progress.ball_new != 0:
			modes.append(m)


# ---- list pages (FUN_800DCE20) ------------------------------------------------------------

static func _cycle(v: int, step: int, n: int) -> int:
	var t := (v + step) & 0xFFFFFFFF
	return t if t < n else (n - (v + 1)) & 0xFFFFFFFF


func _list_input(p: int) -> void:
	var rep := g.repeat(0) | g.repeat(1)
	var pressed := g.pressed_any()
	var step := ((rep >> 14) & 1) - ((rep >> 12) & 1)
	var lr := ((rep >> 13) & 1) - (rep >> 15)
	var count := items(p).size()
	var cur := _cycle(cursors[p], step, count)
	# The remake's hidden items are passed over.
	while step != 0 and item_hidden(p, cur):
		cur = _cycle(cur, step, count)
	if step != 0:
		g.sound(SOUND_MOVE)
	cursors[p] = cur
	var e := _item(p, cur)
	var kind := JsonFile.number(e["kind"])
	if kind == 1 or kind == 2:
		var v := _cycle(item_value(p, cur), lr, JsonFile.number(e["count"]))
		if lr != 0:
			g.sound(SOUND_MOVE)
		if kind == 2 and lr != 0 and v & 0xFF != 0:
			subs[p] = 3                  # auto save on: the save test first
		else:
			_set_item_value(p, cur, v)
	e = _item(p, cursors[p])
	match JsonFile.number(e["action"]):
		1:
			if pressed & CHOOSE:
				_set_item_value(p, cursors[p], JsonFile.number(e["value"]))
				g.sound(SOUND_OK)
		2:
			if pressed & CHOOSE:
				_set_item_value(p, cursors[p], JsonFile.number(e["value"]))
				g.sound(SOUND_OK)
			if g.held(0) | g.held(1) == COLOUR_TOGGLE_HELD and pressed == PadState.SELECT:
				g.progress.options_colour = (g.progress.options_colour + 1) & 1
		3:
			if pressed & CHOOSE:
				subs[p] = cursors[p] + 1
				g.sound(SOUND_MOVE)
	var pg: Dictionary = g.data.option_pages[p]
	if JsonFile.number(pg["back"]) == 1 and pressed & PadState.SELECT:
		page = JsonFile.number(pg["back_value"])
		g.sound(SOUND_OK)


# ---- records (FUN_800E0E2C, FUN_800E10E8) -------------------------------------------------

func records_init() -> void:
	var progress := g.progress
	var mask := progress.unlocked & 0xFFDFFFFF
	record_total = 0
	for c in Opponents.CHARACTERS:
		record_total += progress.usage(c)
	for i in 4:
		record_tops[i] = 0
		var pairs: Array[Vector2i] = []
		var ascending := false
		match i:
			0:
				var m := 0x3FF
				for c in Opponents.CHARACTERS:
					if progress.time_record(c) <= TIME_LIMIT:
						m |= 1 << c
				m &= 0xFFDFFFFF
				for c in Opponents.CHARACTERS:
					if (m >> c) & 1:
						pairs.append(Vector2i(c, progress.time_record(c)))
				ascending = true
			1:
				record_lists[i] = PackedInt32Array(range(10))
				continue
			2:
				for c in Opponents.CHARACTERS:
					if (mask >> c) & 1:
						pairs.append(Vector2i(c, progress.usage(c)))
			3:
				for c in Opponents.CHARACTERS:
					if (mask >> c) & 1:
						var w := progress.stat(c, 1)
						var l := progress.stat(c, 2)
						pairs.append(Vector2i(c, (RankingScreen.permille(w, w + l) * 0x100000 + w + l) & 0xFFFFFFFF))
		Opponents.sort_pairs(pairs, ascending)
		var ids := PackedInt32Array()
		for pr in pairs:
			ids.append(pr.x)
		record_lists[i] = ids
	record_page = 0


## The records: left/right the sub-page, up/down scroll; true when left (any face button or Select).
func records_step() -> bool:
	var pressed := g.pressed_any()
	if pressed & (PadState.SELECT | PadState.FACE_BUTTONS):
		g.sound(SOUND_OK)
		return true
	var rep := g.repeat(0) | g.repeat(1)
	var lr := ((rep >> 13) & 1) - (rep >> 15)
	if lr != 0:
		g.sound(SOUND_MOVE)
	var sub := record_page + lr
	if sub < 0:
		sub = 3
	elif sub > 3:
		sub = 0
	record_page = sub
	var n := record_lists[sub].size()
	var top := record_tops[sub]
	if n < 11:
		top = 0
	else:
		var t := (top + ((rep >> 14) & 1) - ((rep >> 12) & 1)) & 0xFFFFFFFF
		if t < ((n - 9) & 0xFFFFFFFF):
			if t != top:
				g.sound(SOUND_MOVE)
			top = t
	record_tops[sub] = top
	return false


# ---- memory card (FUN_800DDED0 and its screens) --------------------------------------------

func _card_page() -> void:
	match subs[PAGE_CARD]:
		0:
			card_state = 0
			_list_input(PAGE_CARD)
		1:
			if _card_save_screen():
				subs[PAGE_CARD] = 0
		2:
			if _card_load_screen():
				subs[PAGE_CARD] = 0
		3:
			g.progress.auto_save = 1
			var r := _card_auto_save_screen()
			g.progress.auto_save = 0
			if r == 2:
				g.progress.auto_save = 1
			if r == 1 or r == 2:
				subs[PAGE_CARD] = 0
	_option_modes()


func _card_gate(quiet: Array) -> bool:
	var pressed := g.pressed_any()
	return pressed & (0xF0 if card_state in quiet else 0x58F0) != 0


func _save() -> int:
	if save_writer.is_valid():
		return save_writer.call(g.progress.save_data()) as int
	return CARD_DONE


func _load() -> int:
	if not g.card_loader.is_valid():
		return CARD_NO_FILE
	var saved: PackedByteArray = g.card_loader.call()
	if saved.is_empty():
		return CARD_NO_FILE
	g.progress.load_save_data(saved)
	return CARD_DONE


## FUN_800DD198: Start loads; any other button (with a message showing, also Start, up, down) leaves.
func _card_load_screen() -> bool:
	if _card_gate([0]):
		g.sound(SOUND_MOVE)
		return true
	if card_state == 0 and g.pressed_any() & PadState.START:
		card_state = (_load() + 1) & 0xFF
		g.sound(SOUND_DONE)
	return false


## FUN_800DD544: Start saves.
func _card_save_screen() -> bool:
	if _card_gate([0, 4]):
		g.sound(SOUND_MOVE)
		return true
	if (card_state == 0 or card_state == 4) and g.pressed_any() & PadState.START:
		card_state = (_save() + 1) & 0xFF
		g.sound(SOUND_DONE)
	return false


## FUN_800DD9E4: turning AUTO SAVE on saves first; 2 when that worked, 1 when left.
func _card_auto_save_screen() -> int:
	if _card_gate([0, 4, 6]):
		g.sound(SOUND_MOVE)
		return 1
	match card_state:
		0:
			card_state = (_save() + 1) & 0xFF
		1:
			return 2
		4, 6:
			if g.pressed_any() & PadState.START:
				card_state = (_save() + 1) & 0xFF
	return 0


# ---- key configuration (FUN_800DF9EC, FUN_800DF630) ----------------------------------------

func key_config_init() -> void:
	for p in 2:
		var rec := keys[p]
		rec.player = p
		rec.selected = 0
		rec.armed = 0
		rec.x = p * 0xB8
		rec.y = 0
		rec.busy = 0
		rec.pad_kind = 0
		for i in KEY_ROWS:
			var src: Dictionary = g.data.key_rows[i]
			var row := rec.rows[i]
			row.state = 0
			row.open = 0
			row.mask = JsonFile.number(src["mask"])
			row.button = JsonFile.number(src["index"])
			row.layer = JsonFile.number(src["layer"])
			row.layout = JsonFile.ints(src["layout"])
			row.colour = JsonFile.number(src["colour"])
		g.menu.button_map(p)


## Both players' key configuration; true when left (Select, or EXIT with no row busy).
func key_config_step() -> bool:
	var leave := false
	for p in 2:
		var rec := keys[p]
		if rec.armed == 0 and g.pressed(p) != 0:
			rec.armed = 1
		rec.busy = 0
		for item in KEY_ITEMS:
			var selected := item == rec.selected
			match item:
				0:
					_key_setting(rec, selected)
				1:
					_key_vibration(rec, selected)
				2:
					if selected and g.pressed(p) & CHOOSE:
						g.progress.put8(0x1C + p, 0)
						for k in 8:
							g.progress.set_button_action(p, k, g.data.key_default[k])
						rec.busy = 1
						g.sound(SOUND_DONE)
				3:
					if selected and g.pressed(p) & CHOOSE:
						leave = true
		if rec.busy == 0:
			var rep := g.repeat(p)
			var step := ((rep >> 14) & 1) - ((rep >> 12) & 1)
			if step != 0:
				g.sound(SOUND_MOVE)
			var v := step + rec.selected
			rec.selected = 3 if v < 0 else (0 if v > 3 else v)
	if g.pressed_any() & PadState.SELECT:
		leave = true
	if leave and keys[0].busy == 0 and keys[1].busy == 0:
		key_config_init()
		g.sound(SOUND_OK)
		return true
	return false


## FUN_800DF14C: the eight button rows (the pad picture).
func _key_setting(rec: KeyRecord, selected: bool) -> void:
	rec.pad_kind = 0
	rec.used = 0
	if not selected:
		return
	rec.held = g.held(rec.player)
	rec.repeat = g.repeat(rec.player)
	if rec.armed == 0:
		rec.held = 0
	if rec.held & 0xFF:
		rec.busy = 1
	if ProgressRules.popcount(rec.held & 0xFF) != 1:
		rec.held = 0
	for row in rec.rows:
		_key_row_input(rec, row)


## FUN_800DEF98: holding a row's button opens its list over 8 frames; up/down picks the action.
func _key_row_input(rec: KeyRecord, row: KeyRow) -> void:
	var before := row.state
	if rec.held & row.mask:
		row.open += 1
		if row.open < KEY_OPEN_FRAMES + 1:
			row.state = 1
		else:
			row.open = KEY_OPEN_FRAMES
			row.state = 2
	else:
		row.open -= 1
		if row.open < 1:
			row.open = 0
			row.state = 0
		else:
			row.state = 3
	if row.open != 0:
		rec.busy = 1
	if before == 0 and row.state == 1:
		g.sound(SOUND_KEY_OPEN)
	if row.state == 2:
		var step := ((rec.repeat >> 14) & 1) - ((rec.repeat >> 12) & 1)
		if step != 0:
			g.sound(SOUND_MOVE)
		var v := step + g.progress.button_action(rec.player, row.button)
		g.progress.set_button_action(rec.player, row.button, KEY_ACTIONS - 1 if v < 0 else (0 if v > KEY_ACTIONS - 1 else v))
	rec.used |= 1 << (g.progress.button_action(rec.player, row.button) & 31)


## FUN_800DF324: VIBRATION (left/right toggles it, with a short buzz).
func _key_vibration(rec: KeyRecord, selected: bool) -> void:
	var p := rec.player
	if selected and g.pressed(p) & PadState.HORIZONTAL:
		var v := (g.progress.u8(0x1C + p) + 1) & 1
		g.progress.put8(0x1C + p, v)
		rec.busy = 1
		g.globals.player_active[p] = 1
		g.globals.controller[p] = v
		g.sim.events.add(SimEvents.Kind.VIBRATE, -1, p, VIBRATION_PATTERN)
		g.sound(SOUND_MOVE)
