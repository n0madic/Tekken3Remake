class_name OptionsView
extends PsxCanvas
## The options (title.ovl FUN_800DE480's drawing, menu_sim.option_list_draw, records and key
## configuration): the options backdrop, the page title in font 1, items in font 0 (the cursor's
## item in colour 5 on a pulsing bar, the others 10; a value equal to its default in colour 1,
## else 6, right-aligned in the value column), the records tables, the memory card's messages and
## both players' key configuration.

const BAR := 0xFF4020                ## FUN_800DC838's cursor bar (a GPU colour word)
const MODE_ICONS := 0x800EB45C       ## title.ovl: per mode (u32 mode, u32 uv|clut)
const MODE_ICON_GREY := 0x7E5E
const RECORD_ROW_Y := 0x92
const RECORD_ROW := 0x14
const ORDINALS := ["ST", "ND", "RD", "TH"]
const CARD_MESSAGES := {1: ["SAVE OK!", 1], 6: ["NO TEKKEN3 FILE!", 5], 2: ["SAVE ERROR!", 2]}
const LOAD_MESSAGES := {1: ["LOAD OK!", 1], 6: ["NO TEKKEN3 FILE!", 5], 2: ["LOAD ERROR!", 2]}

var picture_texture: Texture2D
var pads: Array[Texture2D] = []
var options: OptionsScreen
var flow: GameFlow
var frame_count := 0


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	pictures_dir = screens_dir
	reload_pictures()


## The options backdrop and the pad pictures, from the texture pack in use.
func reload_pictures() -> void:
	picture_texture = TexturePacks.texture(pictures_dir.path_join("options.png"))
	pads.clear()
	for i in 2:
		pads.append(TexturePacks.texture(pictures_dir.path_join("pad_%d.png" % i)))


func show_state(game: GameFlow) -> void:
	flow = game
	options = game.options
	frame_count = game.fight.vblank
	queue_redraw()


func _title_colour() -> int:
	return 1 if flow.progress.options_colour != 0 else 6




func _draw() -> void:
	begin()
	black()
	image(picture_texture, 0, 0, SCREEN.x, SCREEN.y)
	if options == null or flow.sub != 1:
		return
	match options.page:
		0, 1:
			_list(options.page)
		OptionsScreen.PAGE_RECORDS:
			_records()
		OptionsScreen.PAGE_CARD:
			_list(OptionsScreen.PAGE_CARD)
			_card_message()
		OptionsScreen.PAGE_KEYS:
			_keys()


## FUN_800DC838: the cursor bar behind an option (pulsing).
func _glow(x: float, y: float, w: float, pulse := true) -> void:
	var c := BAR
	if pulse:
		c = scale_colour(BAR, (triangle(frame_count << 4) >> 1) + 0x80)
	fill(x - 3, y - 3, w + 6, 0x16, psx(c))


func _list(p: int) -> void:
	var page: Dictionary = flow.data.option_pages[p]
	var title := str(page["title"])
	if not title.is_empty():
		text(title, 1, _title_colour(), JsonFile.number(page["x"]), JsonFile.number(page["y"]))
	var x := JsonFile.number(page["list_x"])
	var y := JsonFile.number(page["list_y"])
	var spacing := JsonFile.number(page["spacing"])
	var width := JsonFile.number(page["value_width"])
	var items: Array = page["items"]
	for i in items.size():
		if options.item_hidden(p, i):
			continue
		var e: Dictionary = items[i]
		var label := str(e["label"])
		var colour := 10
		var layout := JsonFile.number(e["layout"])
		if i == options.cursors[p]:
			colour = 5
			_glow(x, y, text_width(label, 0) if layout == 1 else width)
		text(label, 0, colour, x, y)
		var values: Array = e["values"]
		if layout == 2 and not values.is_empty():
			var v := options.item_value(p, i)
			var shown := str(values[clampi(v, 0, values.size() - 1)])
			var default_value := JsonFile.number(e["kind"]) != 0 and JsonFile.number(e["value"]) == v
			text(shown, 0, 1 if default_value else 6, x + width - text_width(shown, 0), y)
		y += spacing
	if p == 1:
		_mode_boxes(items[options.cursors[1]] as Dictionary)


## FUN_800DC914: the pictures of the modes the item applies to (greyed without the mode's bit).
func _mode_boxes(item: Dictionary) -> void:
	var mask := JsonFile.number(item["modes"])
	var n := options.modes.size()
	fill(0xF6, 0x28, 0x62, n * 0xE + 4, psx(0xC0C0C0))
	fill(0xF7, 0x2A, 0x60, n * 0xE, Color.BLACK)
	for i in n:
		var m := options.modes[i]
		var uv := 0
		for k in flow.data.option_modes.size():
			if ram.u32(MODE_ICONS + 8 * k) == m:
				uv = ram.u32(MODE_ICONS + 8 * k + 4)
		if not (mask >> (m & 31)) & 1:
			uv = (uv & 0xFFFF) | (MODE_ICON_GREY << 16)
		sprt(0xF7, 0x2A + 0xE * i, 0x60, 0xE, uv, 0xB)


func _records() -> void:
	text("RECORDS", 1, 6, 0x8B, 0x28)
	var sub := options.record_page
	centred(flow.data.record_titles[sub], 0, 6, 0xB8, 0x5A)
	text("PAGE:%d" % (sub + 1), 0, 6, 0xE, 2)
	var ids := options.record_lists[sub]
	var top := options.record_tops[sub]
	var progress := flow.progress
	for i in mini(ids.size() - top, 10):
		var row := top + i
		var y := RECORD_ROW_Y + RECORD_ROW * i
		var id := ids[row]
		var ordinal: String = ORDINALS[row % 10 if row < 4 else 3]
		text(_rank_format() % [mini(row + 1, 99), ordinal], 0, 6, 0x12, y)
		match sub:
			0:
				_name(id, y)
				var t := mini(progress.time_record(id), 359_999)
				var sec := t / 60
				text("%02d'%02d\"%02d" % [sec / 60, sec % 60, (t % 60) * 100 / 60], 0, 6, 0xC6, y)
				text(progress.time_record_name(id), 0, 6, 0x132, y)
			1:
				var s := progress.survivor(id)
				_name(s.x >> 2, y)
				text("%3d %s" % [s.y, "WIN" if s.y == 1 else "WINS"], 0, 6, 0xC6, y)
				text(progress.survivor_name(id), 0, 6, 0x132, y)
			2:
				_name(id, y)
				var share := RankingScreen.permille(progress.usage(id), options.record_total)
				text("%d.%d%%" % [share / 10, share % 10], 0, 1 if share >= 1000 else 6, 0xE1, y)
				text("%d" % progress.usage(id), 0, 6, 0x120, y)
			3:
				_name(id, y)
				var w := progress.stat(id, 1)
				var l := progress.stat(id, 2)
				var rate := RankingScreen.permille(w, w + l)
				text("%d.%d%%" % [rate / 10, rate % 10], 0, 6, 0xAB, y)
				text("%d" % w, 0, 6, 0xEA, y)
				text("%d" % l, 0, 6, 0x120, y)


## The records' rank: the USA release pads it to two digits.
func _rank_format() -> String:
	return ram.locale.record_rank if ram.locale != null and ram.locale.english else "%d%s"


func _name(character: int, y: float) -> void:
	var record := flow.fight.tables.character(character * 4)
	centred(str(record["name"]), 0, 6, 0x7E, y)


func _card_message() -> void:
	var sub := options.subs[OptionsScreen.PAGE_CARD]
	if sub == 0:
		return
	var state := options.card_state
	if state == 0:
		text("PUSH START BUTTON", 0, 4, 0x15, 0x168)
		return
	var table := LOAD_MESSAGES if sub == 2 else CARD_MESSAGES
	var e: Array = table.get(state, ["SOMETHING MESSAGE", 3])
	var colour: int = e[1]
	centred(str(e[0]), 0, colour, 0xB8, 0x168)


## FUN_800DF630: both players' pad pictures, button actions, VIBRATION, DEFAULT and EXIT.
func _keys() -> void:
	text("KEY CONFIGURATION", 1, _title_colour(), 0x4A, 0x28)
	for rec in options.keys:
		var x := rec.x + 0x14
		var y := rec.y
		image(pads[0], x, y + 0x88)
		for i in 8:
			var row := rec.rows[i]
			var action := flow.progress.button_action(rec.player, row.button)
			var open := row.open / 8.0
			var at := Vector2(rec.x + lerpf(row.layout[0], row.layout[2], open), rec.y + lerpf(row.layout[1], row.layout[3], open))
			var selected := rec.selected == 0 and row.state != 0
			fill(at.x, at.y, 0x40, 0x16, psx(row.colour))
			fill(at.x + 1, at.y + 2, 0x3E, 0x12, Color.BLACK)
			text(flow.data.key_names[action], 0, 5 if selected else 6, at.x + 4, at.y + 3)
		_item("SETTING", rec.selected == 0, x, y + 0x154)
		var vib := flow.progress.u8(0x1C + rec.player)
		_item("VIBRATION    " + ("YES" if vib != 0 else " NO"), rec.selected == 1, x, y + 0x16E)
		_item("DEFAULT", rec.selected == 2, x, y + 0x188)
		_item("EXIT", rec.selected == 3, x, y + 0x1A2)


func _item(label: String, selected: bool, x: float, y: float) -> void:
	if selected:
		_glow(x, y, text_width(label, 0))
	text(label, 0, 5 if selected else 10, x, y)
