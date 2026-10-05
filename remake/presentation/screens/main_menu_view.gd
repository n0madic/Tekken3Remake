class_name MainMenuView
extends ScreenCanvas
## The main menu (title.ovl FUN_800DBBD0's drawing, menu_sim._main_menu_draw): the title picture,
## the cursor's bars once the list rests, and in the band y 316–431 (a draw area) seven entries of
## the list in font 1 around the cursor (28 pixels apart, sliding), darkened at the band's edges
## by two subtracted gradients. A NEW entry blinks in colour 14.

const LIST_Y := 0x116
const LINE := 0x1C
const CENTRE := 0xB8
const BAND := Rect2(0x30, 0x13C, 0x140, 0x74)
const NEW_COLOUR := 14

var title: Texture2D
var menu: MainMenu
var frame_count := 0


func setup(hud_data: HudData, title_picture: Texture2D) -> void:
	setup_canvas(hud_data)
	title = title_picture
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _list, BAND)
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, _fades, BAND)


func show_state(main_menu: MainMenu, frames: int) -> void:
	menu = main_menu
	frame_count = frames
	redraw()


func _draw() -> void:
	begin()
	black()
	image(title, 0, 0, SCREEN.x, SCREEN.y)
	if menu != null and menu.scroll == 0:
		_bars(menu.glow)


## The seven entries around the cursor.
func _list() -> void:
	if menu == null or menu.entries.is_empty():
		return
	var count := menu.entries.size()
	var cur := menu.cursor()
	var index := (cur - 3 + count) if cur < 3 else cur - 3
	var y := menu.scroll + LIST_Y
	for i in 7:
		index %= count
		var e := menu.entries[index]
		var colour := e.entry.index
		if menu.chosen == 0 and e.new and frame_count & 3 == 0:
			colour = NEW_COLOUR
		centred(e.entry.text, 1, colour, CENTRE, y)
		index += 1
		y += LINE


## The band's edges darkened (subtracted gradients).
func _fades() -> void:
	if menu == null:
		return
	gradient(0x44, 0x13C, 0xE8, 0x1C, psx(0xE0E0E0), psx(0xE0E0E0), Color.BLACK, Color.BLACK)
	gradient(0x44, 0x194, 0xE8, 0x1C, Color.BLACK, Color.BLACK, psx(0xF8F8F8), psx(0xF8F8F8))


## The cursor's bars (opaque Gouraud quads, brightening in): a band and two lines, brightest in
## the middle.
func _bars(glow: int) -> void:
	var g := mini(glow, 0x100)
	var c := psx(PsxCanvas.scale_colour(0xC0C0C0, g))
	var f := psx(PsxCanvas.scale_colour(0xF8F8F8, g))
	var none := Color.BLACK
	gradient(8, 0x168, CENTRE - 8, 0x1C, none, c, none, c)
	gradient(CENTRE, 0x168, 0x168 - CENTRE, 0x1C, c, none, c, none)
	for y: int in [0x182, 0x168]:
		gradient(0, y, CENTRE, 2, none, f, none, f)
		gradient(CENTRE, y, SCREEN.x - CENTRE, 2, f, none, f, none)
