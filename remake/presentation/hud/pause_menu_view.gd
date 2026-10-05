class_name PauseMenuView
extends Control
## Draws the pause menu (FUN_8007854C, modes.md#pause) over the frozen fight: a dark blue box
## on a light grey one behind CANCEL, COMMAND and RESET in font 0 (colour 2 for the chosen item,
## 6 for the others) centred at x = 184 from y = 104, 20 apart, and "nP PAUSE" blinking at 32
## from the left (player 1) or right (player 2) edge of the display (font 1, colour 5); Tekken
## Ball's HOW TO page shows the rules picture instead.
## Coordinates are the HUD's 384 × 480 units (FightHud).

const ITEM_Y := 0x68
const ITEM_STEP := 0x14
const ITEM_CENTRE := 0xB8
const ITEM_ADVANCE := 9
const BOX := Rect2(0x94, 0x64, 0x48, 0x41)            ## dark blue (0, 16, 48); 0x55 high in Tekken Ball
const BORDER := Rect2(0x93, 0x62, 0x4A, 0x41 + 4)     ## light grey (224, 224, 224) under it
const BALL_BOX_HEIGHT := 0x55
const BOX_COLOUR := Color8(0, 16, 48)
const BORDER_COLOUR := Color8(224, 224, 224)
const LABEL_Y := 0x78
const LABEL_LEFT := 0x20
## Player 2: the display's x + width − 0x88 (0x800AE6F8 holds (0, 20, 368, 448) in the fight).
const DISPLAY_X := 0
const DISPLAY_WIDTH := 368
const LABEL_RIGHT := DISPLAY_X + DISPLAY_WIDTH - 0x88
const SELECTED := 2
const OTHER := 6
const LABEL_COLOUR := 5
const HOW_TO_AT := Vector2(0x4C, 0x80)
const HOW_TO_SIZE := Vector2(0xD8, 0xCC)
## The USA release's wider RULES picture (volley.ovl FUN_800B3BC4): its card, shadow and place.
const RULES_CARD := Rect2(0x34, 0x78, 0x108, 0xDC)
const RULES_SHADOW := Rect2(0x3C, 0x84, 0x108, 0xDC)
const RULES_AT := Vector2(0x38, 0x80)
const RULES_WIDTH := 0x100
const HOW_TO_CARD := Rect2(0x40, 0x70, 0xF0, 0xEC)
const HOW_TO_SHADOW := Rect2(0x46, 0x78, 0xF0, 0xEC)

var hud: FightHud
var player := 0                      ## 1 or 2 while shown
var cursor := 0
var items := PauseMenu.ITEMS.size() - 1
var blink := false
var how_to := false                  ## Tekken Ball's HOW TO page is shown
var _how_to_picture: Texture2D
var locale: TextLocale                ## the texts' language: the items and the rules picture


func setup(fight_hud: FightHud) -> void:
	hud = fight_hud
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Drops the rules picture so the next HOW TO page loads it in the texts' language.
func reset_pictures() -> void:
	_how_to_picture = null


func show_state(sim: FightSimulation) -> void:
	var menu := sim.events.first(SimEvents.Kind.PAUSE_MENU)
	player = menu.a if menu != null else 0
	cursor = sim.fight.pause_cursor
	items = PauseMenu.item_count(sim.fight)
	blink = sim.fight.vblank & 0x20 != 0
	how_to = sim.fight.paused_player != 0 and sim.fight.pause_page == PauseMenu.PAGE_HOW_TO
	if how_to and _how_to_picture == null:
		var path := Assets.path("stages/v/how_to.png")
		_how_to_picture = TexturePacks.texture(locale.file_or("how_to.png", path) if locale != null else path)
	visible = player != 0 or how_to
	queue_redraw()


func _draw() -> void:
	if hud == null:
		return
	if how_to:
		_draw_how_to()
		return
	if player == 0:
		return
	var h: float = BOX.size.y if items < PauseMenu.ITEMS.size() else float(BALL_BOX_HEIGHT)
	draw_rect(hud.rect(BORDER.position.x, BORDER.position.y, BORDER.size.x, h + 4), BORDER_COLOUR)
	draw_rect(hud.rect(BOX.position.x, BOX.position.y, BOX.size.x, h), BOX_COLOUR)
	for i in items:
		var text: String = PauseMenu.ITEMS[i]
		if locale != null:
			text = locale.text("exe", text)
		var x := ITEM_CENTRE - (text.length() * ITEM_ADVANCE >> 1)
		hud.draw_text_at(self, text, 0, SELECTED if i == cursor else OTHER, x, ITEM_Y + i * ITEM_STEP)
	if blink:
		hud.draw_text_at(self, "%dP PAUSE" % player, 1, LABEL_COLOUR, LABEL_LEFT if player == 1 else LABEL_RIGHT, LABEL_Y)


## volley.ovl FUN_800B4088: the rules picture (216 × 204) on a white card with a black shadow.
func _draw_how_to() -> void:
	if _how_to_picture != null and _how_to_picture.get_width() == RULES_WIDTH:
		draw_rect(hud.rect(RULES_SHADOW.position.x, RULES_SHADOW.position.y, RULES_SHADOW.size.x, RULES_SHADOW.size.y), Color.BLACK)
		draw_rect(hud.rect(RULES_CARD.position.x, RULES_CARD.position.y, RULES_CARD.size.x, RULES_CARD.size.y), Color.WHITE)
		draw_texture_rect(_how_to_picture, hud.rect(RULES_AT.x, RULES_AT.y, RULES_WIDTH, HOW_TO_SIZE.y), false)
		return
	draw_rect(hud.rect(HOW_TO_SHADOW.position.x, HOW_TO_SHADOW.position.y, HOW_TO_SHADOW.size.x, HOW_TO_SHADOW.size.y), Color.BLACK)
	draw_rect(hud.rect(HOW_TO_CARD.position.x, HOW_TO_CARD.position.y, HOW_TO_CARD.size.x, HOW_TO_CARD.size.y), Color8(0xF0, 0xF0, 0xF0))
	if _how_to_picture != null:
		draw_texture_rect(_how_to_picture, hud.rect(HOW_TO_AT.x, HOW_TO_AT.y, HOW_TO_SIZE.x, HOW_TO_SIZE.y), false)
