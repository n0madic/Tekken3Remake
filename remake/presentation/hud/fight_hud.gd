class_name FightHud
extends Control
## The fight HUD (hud.md) with the game's own sprites: health bars with their animation, the
## timer, the round marks, the name plates, the round messages and the replay caption, laid out
## in the game's 384 × 480 frame-buffer units inside the scene's 4:3 frame.

const BAR_Y := 40.0
const BAR_X := [10.0, 202.0]
const BAR_LENGTH := 152.0
const BAR_HEIGHT := 24.0
const BAR_CAP := Vector2(6, 24)
const BAR_RIGHT_CAP := 150.0         ## the second cap at x + 0x96
const BAR_FILL_SOURCE := Rect2(0, 0, 1, 24)   ## one texel column, stretched
const TIMER_UNITS_X := 184.0
const TIMER_STEP := 15.0
const TIMER_Y := 22.0
const DIGIT := Vector2(16, 46)
const INFINITE := [11, 10]           ## the halves of ∞ (units, tens)
const MARK_Y := 70.0
const MARK_X := [151.0, 202.0]
const MARK_STEP := [-14.0, 14.0]
const MARK := Vector2(15, 18)
const NAME_POS := [Vector2(14, 66), Vector2(354, 66)]   ## player 2: the right end
const NAME_HEIGHT := 16.0
const PLATE_TOP := 9.0
const PLATE_BOTTOM := 19.0
const PLATE_MARGIN := 4.0
const PLATE_SOURCE := Rect2(0, 0, 2, 10)
const REPLAY_POS := Vector2(244, 30)
const REPLAY_COLOUR := 7
const REPLAY_FONT := 1

var data: HudData
var box := Rect2()                   ## the scene's 4:3 frame in the window
var _fight: FightState
var _slots := PackedInt32Array([0, 0])
var _replay := false
## The flow's own texts over the fight (CONTINUE?, GAME OVER, A NEW CHALLENGER).
var flow_texts: Array[RoundHud.Message] = []


func setup(hud_data: HudData, costume_slots: PackedInt32Array) -> void:
	data = hud_data
	_slots = costume_slots.duplicate()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## A record's costume swapped in during the fight (its name plate).
func set_slot(record: int, costume_slot: int) -> void:
	if record < _slots.size():
		_slots[record] = costume_slot


## After a simulation step.
func show_state(sim: FightSimulation) -> void:
	_fight = sim.fight
	_replay = sim.events.has(SimEvents.Kind.REPLAY_TEXT)
	queue_redraw()


## The original 4:3 frame in the window (CameraRig.frame_rect, normalised).
func place(frame_rect: Rect2) -> void:
	var window := size
	var frame := Rect2(frame_rect.position * window, frame_rect.size * window)
	if frame != box:
		box = frame
		queue_redraw()


func point(x: float, y: float) -> Vector2:
	return HudFrame.point(box, x, y)


func unit_scale() -> Vector2:
	return HudFrame.unit_scale(box)


## A rectangle in HUD units.
func rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(point(x, y), Vector2(w, h) * unit_scale())


func _draw() -> void:
	if _fight == null or data == null or box.size.x <= 0:
		return
	if _fight.hud_shown != 0 and _fight.replay_playing == 0:
		# Tekken Force draws its own bars and names (ModeHudView) and no round marks.
		if _fight.mode != GameMode.FORCE:
			for p in 2:
				_draw_bar(p)
				_draw_marks(p)
				_draw_name(p)
		_draw_timer()
	if _fight.replay_playing == 0:
		for m in RoundHud.messages(_fight):
			draw_text_at(self, m.text, m.font, m.palette, m.x, m.y)
	if _replay:
		draw_text_at(self, "REPLAY", REPLAY_FONT, REPLAY_COLOUR, REPLAY_POS.x, REPLAY_POS.y)
	for m in flow_texts:
		draw_text_at(self, m.text, m.font, m.palette, m.x, m.y)


## FUN_8004E55C: the fills (health innermost, recent damage, empty) under the two end caps.
func _draw_bar(p: int) -> void:
	var bar := _fight.hud_bars[p]
	var x: float = BAR_X[p]
	var drawn := float(bar[2])
	var recent := float(maxi(bar[3], bar[2]))
	var parts := [["bar_health.png", drawn], ["bar_damage.png", recent - drawn], ["bar_empty.png", BAR_LENGTH - recent]]
	var pen := x + 2.0 if p == 1 else x + 2.0 + BAR_LENGTH
	for part: Array in parts:
		var length: float = part[1]
		if length <= 0:
			continue
		var from := pen if p == 1 else pen - length
		draw_texture_rect_region(data.texture(str(part[0])), rect(from, BAR_Y, length, BAR_HEIGHT), BAR_FILL_SOURCE)
		pen = pen + length if p == 1 else pen - length
	draw_texture_rect(data.texture("bar_cap_left.png"), rect(x, BAR_Y, BAR_CAP.x, BAR_CAP.y), false)
	draw_texture_rect(data.texture("bar_cap_right.png"), rect(x + BAR_RIGHT_CAP, BAR_Y, BAR_CAP.x, BAR_CAP.y), false)


## FUN_8004E410: the seconds left, (frames + 59) / 60, or ∞; units first, tens 15 to the left.
func _draw_timer() -> void:
	var digits := PackedInt32Array(INFINITE)
	if _fight.timer_stopped == 0:
		var seconds := clampi((_fight.timer + 59) / 60, 0, 99)
		digits = PackedInt32Array([seconds % 10, seconds / 10])
	for i in 2:
		var tex := data.texture("digit_%d.png" % digits[i])
		draw_texture_rect(tex, rect(TIMER_UNITS_X - i * TIMER_STEP, TIMER_Y, DIGIT.x, DIGIT.y), false)


## FUN_8004E87C: one mark per round to win; the newest won mark blinks.
func _draw_marks(p: int) -> void:
	var wins := _fight.fighters[p].round_wins
	var x: float = MARK_X[p]
	for i in _fight.rounds_to_win:
		var empty := i >= wins
		if i == wins - 1 and _fight.hud_wins_seen[p] != wins:
			empty = _fight.vblank & 0x10 != 0
		var tex := data.texture("mark_empty.png" if empty else "mark_won.png")
		draw_texture_rect(tex, rect(x, MARK_Y, MARK.x, MARK.y), false)
		x += MARK_STEP[p]


## FUN_8004EB9C: the name sprite on its backing quad.
func _draw_name(p: int) -> void:
	var slot := _slots[p]
	var tex := data.name_texture(slot)
	if tex == null:
		return
	var width := float(data.name_width(slot))
	var at: Vector2 = NAME_POS[p]
	var x := at.x if p == 0 else at.x - width
	var plate := rect(x - PLATE_MARGIN, at.y + PLATE_TOP, width + 2.0 * PLATE_MARGIN, PLATE_BOTTOM - PLATE_TOP)
	draw_texture_rect_region(data.plate_texture(slot), plate, PLATE_SOURCE)
	draw_texture_rect(tex, rect(x, at.y, width, NAME_HEIGHT), false)


## FUN_8004D15C: glyphs of a font and colour from (x, y), one advance per character.
func draw_text_at(item: CanvasItem, text: String, font_index: int, colour: int, x: float, y: float) -> void:
	HudText.draw(item, data, text, font_index, colour, x, y, HudText.layout(point(0, 0), point(1, 1)))
