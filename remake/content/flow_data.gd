class_name FlowData
extends RefCounted
## The game flow's converted data (`imported/tables/flow.json`, tools/remake_import/flow.py):
## the initial image of the progress block, the default key tables, the main menu's entries and
## the tables of the screens.


class MenuEntry:
	var text: String
	var mode: int
	var two_players: int
	var index: int


var progress := PackedByteArray()          ## GameProgress's image in the executable
var key_tables: Array[PackedInt32Array] = []   ## per player the mapped word of each physical bit
var quick_grid := PackedByteArray()        ## quick select cells: s16 x, s16 y, u8 key, pad
var quick_prefs := PackedByteArray()       ## per player 0x34 bytes of the record's layout values
var quick_state_anim := PackedByteArray()  ## per quick select state: three animation bytes
var quick_decided := PackedByteArray()     ## per state: the two costume-clash flags
var menu_entries: Array[MenuEntry] = []
var button_actions := PackedInt32Array()   ## the pad word of each key configuration action
var button_tail := PackedInt32Array()      ## the fixed words of the other eight pad bits
var unlock_schedule := PackedInt32Array()  ## ArcadeUnlocks' steps as (kind, value) pairs
var demo_characters := PackedInt32Array()  ## the demonstration fight's character list
var attributes := PackedInt64Array()       ## per costume key: portrait (bits 0–4), facing (5), layout (6–7), colour (8–31)
var vs_backgrounds := PackedInt32Array()   ## the VS screen: background id per kind
var vs_caption_colours := PackedInt32Array()   ## caption bar colour (RGB) per kind
var vs_caption_widths := PackedInt32Array()
var vs_player_pos := PackedInt32Array()    ## per side: portrait x, y, slide x, slide y
var vs_player_names := PackedInt32Array()  ## per side: name x, y, slide x, slide y
var vs_team_pos := PackedInt32Array()
var vs_team_names := PackedInt32Array()
var vs_team_icons := PackedInt32Array()    ## per side: x, y, step, x with eight members
var ranking_alphabet := ""                     ## the name entry's 40 symbols ("<" back, "=" end)
var ranking_rejected := PackedStringArray()    ## names replaced by the character's own
var ranking_skipped := PackedInt32Array()      ## stages the ranking backdrop never shows
var ranking_gon := ""                          ## the name that unlocks Gon
var ending_movies := PackedInt32Array()        ## per costume key (21 characters × 4) the ending movie
var staff_titles := PackedStringArray()        ## the staff roll's title block
var staff_rows := PackedStringArray()          ## the rows: a kind digit, then the text
var staff_font_wide := PackedInt32Array()      ## glyph widths from '!' (headings)
var staff_font_narrow := PackedInt32Array()    ## glyph widths from '!' (names)
var theater_movies: Array[Dictionary] = []     ## Tekken 3 movies: movie, alternative, picture, mask, rule, name, lines
var theater_tracks: Array[Dictionary] = []     ## Tekken 3 sound list: track, name
var theater_names: Dictionary = {}             ## "0"–"3": the names of shared ending slots by the clears
var theater_texts: Dictionary = {}             ## the buttons and captions
var ogre_scripts: Array[Array] = []            ## the Ogre scene's events (frame, kind, a, b, c) by the human's side
var vs_practice_pos := PackedInt32Array()     ## practice.ovl's VS screen: portraits, names, captions
var vs_practice_names := PackedInt32Array()
var vs_practice_texts: Dictionary = {}
var practice_rows: Array[PackedInt32Array] = []   ## per page (FREE, VS CPU, COMBO TRAINING) the item id of each row
var practice_combos: Array[Array] = []         ## per bank type: combos {steps: key-ring words, moves: move slots}
var practice_texts: Dictionary = {}            ## the menus' titles and labels
var option_pages: Array[Dictionary] = []       ## the options' pages: layout, title, items, the Select byte
var option_modes := PackedInt32Array()         ## GAME OPTION's mode pictures, in order
var key_rows: Array[Dictionary] = []           ## key configuration: per row the button mask, index, layer, layout, colour
var key_default := PackedInt32Array()          ## the default action per button
var key_names := PackedStringArray()           ## the 13 actions
var record_titles := PackedStringArray()       ## the records sub-pages
var select_grid_keys := PackedInt32Array()     ## select.ovl: the character of each of the 22 cells
var select_player_layout := PackedByteArray()  ## per player 0x28 bytes copied to the record at +0x54
var select_state_anim := PackedInt32Array()    ## per state the two bytes kept at +0x08/+0x0C
var select_decided := PackedInt32Array()       ## per state the costume-clash flags
var select_layouts := PackedByteArray()        ## the one-row and two-row layouts (0x30 bytes each)
var select_context := PackedByteArray()        ## the screen context's initial image
var vs_text := ""                          ## "VS"
var vs_stage := ""                         ## the arcade and time attack caption: "STAGE %d"
var vs_round := ""                         ## VS, team battle and survival: "FIGHT %d"
var vs_demo := ""                          ## the demonstration: "STAGE 1"


## The text fields by the game memory block they come from, as converted (Japanese release).
const TEXT_FIELDS := {
	"theater_names": "ending", "theater_texts": "ending", "vs_practice_texts": "practice",
	"practice_texts": "practice", "key_names": "title", "record_titles": "title",
}

var _texts: Dictionary = {}                   ## the text fields as converted


static func load_from(path: String) -> FlowData:
	var d: Dictionary = JsonFile.read(path)
	var f := FlowData.new()
	f.progress = _bytes(d["progress"])
	var tables := _bytes(d["key_tables"])
	for p in 2:
		var words := PackedInt32Array()
		for bit in 16:
			words.append(tables.decode_u16(0x20 * p + 2 * bit))
		f.key_tables.append(words)
	f.quick_grid = _bytes(d["quick_grid"])
	f.quick_prefs = _bytes(d["quick_prefs"])
	f.quick_state_anim = _bytes(d["quick_state_anim"])
	f.quick_decided = _bytes(d["quick_decided"])
	for e: Dictionary in d["menu_entries"]:
		var m := MenuEntry.new()
		m.text = str(e["text"])
		m.mode = JsonFile.number(e["mode"])
		m.two_players = JsonFile.number(e["two_players"])
		m.index = JsonFile.number(e["index"])
		f.menu_entries.append(m)
	f.button_actions = _u16s(d["button_actions"])
	f.button_tail = _u16s(d["button_tail"])
	f.unlock_schedule = JsonFile.ints(d["unlock_schedule"])
	f.demo_characters = JsonFile.ints(d["demo_characters"])
	f.attributes = PackedInt64Array(d["attributes"] as Array)
	f.vs_backgrounds = _u16s(d["vs_backgrounds"])
	var colours := _bytes(d["vs_caption_colours"])
	for i in colours.size() / 4:
		f.vs_caption_colours.append(colours.decode_u32(4 * i))
	f.vs_caption_widths = _u16s(d["vs_caption_widths"])
	f.vs_player_pos = JsonFile.ints(d["vs_player_pos"])
	f.vs_player_names = JsonFile.ints(d["vs_player_names"])
	f.vs_team_pos = JsonFile.ints(d["vs_team_pos"])
	f.vs_team_names = JsonFile.ints(d["vs_team_names"])
	f.vs_team_icons = JsonFile.ints(d["vs_team_icons"])
	f.ranking_alphabet = str(d["ranking_alphabet"])
	f.ranking_rejected = PackedStringArray(d["ranking_rejected"] as Array)
	f.ranking_skipped = JsonFile.ints(d["ranking_skipped"])
	f.ranking_gon = str(d["ranking_gon"])
	f.ending_movies = JsonFile.ints(d["ending_movies"])
	f.staff_titles = PackedStringArray(d["staff_titles"] as Array)
	f.staff_rows = PackedStringArray(d["staff_rows"] as Array)
	f.staff_font_wide = JsonFile.ints(d["staff_font_wide"])
	f.staff_font_narrow = JsonFile.ints(d["staff_font_narrow"])
	f.theater_movies.assign(d["theater_movies"] as Array)
	f.theater_tracks.assign(d["theater_tracks"] as Array)
	f.theater_names = d["theater_names"]
	f.theater_texts = d["theater_texts"]
	for script: Array in d["ogre_scripts"]:
		var events: Array[PackedInt32Array] = []
		for e: Array in script:
			events.append(JsonFile.ints(e))
		f.ogre_scripts.append(events)
	f.vs_practice_pos = JsonFile.ints(d["vs_practice_pos"])
	f.vs_practice_names = JsonFile.ints(d["vs_practice_names"])
	f.vs_practice_texts = d["vs_practice_texts"]
	for row: Array in d["practice_rows"]:
		f.practice_rows.append(JsonFile.ints(row))
	for kind: Array in d["practice_combos"]:
		var list: Array[Dictionary] = []
		for c: Dictionary in kind:
			list.append({"steps": JsonFile.ints(c["steps"]), "moves": JsonFile.ints(c["moves"])})
		f.practice_combos.append(list)
	f.practice_texts = d["practice_texts"]
	f.option_pages.assign(d["option_pages"] as Array)
	f.option_modes = JsonFile.ints(d["option_modes"])
	f.key_rows.assign(d["key_rows"] as Array)
	f.key_default = JsonFile.ints(d["key_default"])
	f.key_names = PackedStringArray(d["key_names"] as Array)
	f.record_titles = PackedStringArray(d["record_titles"] as Array)
	f.select_grid_keys = JsonFile.ints(d["select_grid_keys"])
	f.select_player_layout = _bytes(d["select_player_layout"])
	f.select_state_anim = JsonFile.ints(d["select_state_anim"])
	f.select_decided = JsonFile.ints(d["select_decided"])
	f.select_layouts = _bytes(d["select_layouts"])
	f.select_context = _bytes(d["select_context"])
	var texts: Dictionary = d["vs_texts"]
	f.vs_text = str(texts["vs"])
	f.vs_stage = str(texts["stage"])
	f.vs_round = str(texts["round"])
	f.vs_demo = str(texts["demo"])
	for field: String in TEXT_FIELDS:
		f._texts[field] = f.get(field)
	f._texts["staff_titles"] = f.staff_titles
	f._texts["staff_rows"] = f.staff_rows
	return f


## The text fields in the locale's language (null: as converted): the strings through their
## blocks, the staff roll the USA one when it was converted.
func localize(locale: TextLocale) -> void:
	for field: String in TEXT_FIELDS:
		var v: Variant = _texts[field]
		set(field, locale.texts(str(TEXT_FIELDS[field]), v) if locale != null else v)
	var english := locale != null and locale.english and not locale.staff_rows.is_empty()
	staff_titles = locale.staff_titles if english else _texts["staff_titles"]
	staff_rows = locale.staff_rows if english else _texts["staff_rows"]


## FUN_8004BA28: the attribute word of a character's costume (an out-of-range one: the empty key).
func attribute(character: int, costume: int) -> int:
	if character > 0x15 or costume > 3:
		character = 0x16
		costume = 0
	return attributes[character * 4 + costume]


static func _bytes(value: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	for v in JsonFile.ints(value):
		out.append(v)
	return out


static func _u16s(value: Variant) -> PackedInt32Array:
	var b := _bytes(value)
	var out := PackedInt32Array()
	for i in b.size() / 2:
		out.append(b.decode_u16(2 * i))
	return out
