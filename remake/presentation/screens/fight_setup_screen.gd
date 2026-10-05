class_name FightSetupScreen
extends Control
## A temporary set-up screen for VS fights until the game's own select screens arrive (M3):
## both players' characters and costumes, the stage, the rounds to win, the round time and the
## Gameplay fixes option. Either pad moves the cursor with up and down, changes a value with
## left and right, and starts the fight with Start or Cross on START.

signal start_requested

enum Row { P1_CHARACTER, P1_COSTUME, P2_CHARACTER, P2_COSTUME, STAGE, ROUNDS, TIME, FIXES, START }

const ROW_NAMES := ["1P CHARACTER", "1P COSTUME", "2P CHARACTER", "2P COSTUME", "STAGE",
	"ROUNDS TO WIN", "ROUND TIME", "GAMEPLAY FIXES", "START"]
const CHARACTERS := 21                  ## character ids 0–20 (True Ogre is 20)
const COSTUMES := 4
const STAGES := 15
const MAX_ROUNDS := 5
const ROUND_TIMES := ["20", "30", "40", "50", "60", "∞"]
const TITLE := "VS BATTLE (temporary set-up until M3)"
const HINT := "Up / Down: choose   Left / Right: change   Start or Cross: fight"

var tables: FightTables
var chars := PackedInt32Array([0, 1])
var costumes := PackedInt32Array([0, 0])
var stage := 0
var rounds := 2                         ## rounds to win
var round_time := 2                     ## option index: 40 s
var gameplay_fixes := false
var row := Row.START
var font: Font


func setup(fight_tables: FightTables) -> void:
	tables = fight_tables
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## One frame of input: `pressed` are the newly pressed physical buttons of both pads.
func input(pressed: int) -> void:
	if pressed & PadState.UP:
		row = posmod(row - 1, Row.size()) as Row
	if pressed & PadState.DOWN:
		row = posmod(row + 1, Row.size()) as Row
	var change := 0
	if pressed & PadState.LEFT:
		change = -1
	if pressed & PadState.RIGHT:
		change = 1
	if change != 0:
		_change(change)
	if row == Row.START and pressed & (PadState.START | PadState.CROSS):
		start_requested.emit()
	queue_redraw()


func _change(step: int) -> void:
	match row:
		Row.P1_CHARACTER, Row.P2_CHARACTER:
			var p := 0 if row == Row.P1_CHARACTER else 1
			chars[p] = posmod(chars[p] + step, CHARACTERS)
			costumes[p] = valid_costume(chars[p], costumes[p], 1)
		Row.P1_COSTUME, Row.P2_COSTUME:
			var p := 0 if row == Row.P1_COSTUME else 1
			costumes[p] = valid_costume(chars[p], posmod(costumes[p] + step, COSTUMES), step)
		Row.STAGE:
			stage = posmod(stage + step, STAGES)
		Row.ROUNDS:
			rounds = clampi(rounds + step, 1, MAX_ROUNDS)
		Row.TIME:
			round_time = posmod(round_time + step, ROUND_TIMES.size())
		Row.FIXES:
			gameplay_fixes = not gameplay_fixes


## The nearest costume the character has, searching in the direction of `step`.
func valid_costume(char_id: int, costume: int, step: int) -> int:
	for k in COSTUMES:
		var c := posmod(costume + k * step, COSTUMES)
		if tables.fighter.costume_keys[char_id * 4 + c] >= 0:
			return c
	return 0


func _value(r: Row) -> String:
	match r:
		Row.P1_CHARACTER, Row.P2_CHARACTER:
			var p := 0 if r == Row.P1_CHARACTER else 1
			return str(tables.character(chars[p] * 4)["name"])
		Row.P1_COSTUME, Row.P2_COSTUME:
			var p := 0 if r == Row.P1_COSTUME else 1
			return str(costumes[p] + 1)
		Row.STAGE:
			return str(stage + 1)
		Row.ROUNDS:
			return str(rounds)
		Row.TIME:
			return ROUND_TIMES[round_time]
		Row.FIXES:
			return "ON" if gameplay_fixes else "OFF"
	return ""


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06))
	var h := maxf(16.0, size.y / 26.0)
	var x := size.x * 0.2
	var y := size.y * 0.15
	draw_string(font, Vector2(x, y), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 1.3), Color(1, 0.85, 0.3))
	y += h * 2.5
	for r in Row.size():
		var selected := r == row
		var colour := Color(1, 1, 1) if selected else Color(0.6, 0.6, 0.7)
		if selected:
			draw_rect(Rect2(x - h * 0.5, y - h * 1.05, size.x * 0.6 + h, h * 1.4), Color(0.2, 0.25, 0.5))
		draw_string(font, Vector2(x, y), str(ROW_NAMES[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(h), colour)
		var value := _value(r as Row)
		if not value.is_empty():
			draw_string(font, Vector2(x + size.x * 0.32, y), "<  %s  >" % value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h), colour)
		y += h * 1.6
	draw_string(font, Vector2(x, y + h), HINT, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.75), Color(0.6, 0.6, 0.7))
	var devices := "1P: %s    2P: %s" % [Pads.device_name(0), Pads.device_name(1)]
	draw_string(font, Vector2(x, y + h * 2.2), devices, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.75), Color(0.6, 0.6, 0.7))
