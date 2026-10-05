class_name VsView
extends PsxCanvas
## The pre-fight VS screen (FUN_80052808's drawing loop, draw_sim.vs_draw): the tiled
## `makuma` background, the caption bar, the portraits (`face_b` pictures) with their frame and
## coloured glow, the names sliding in, team battle's member icons and bars, and the texts.
##
## The game links every object into the same ordering-table slot, so the last object is drawn
## first (the background) and the first ones on top; the texts are in the front slot. The glow and
## the caption bar's tail blend with the background: they are passes in their blend modes.

const COL_EDGES := 0x800228C6
const ROW_EDGES := 0x800228D8
const FRAME_RECTS := 0x8002292C
const BACKGROUND_BASE := 10          ## logical id of makuma00.tia
const PORTRAIT_W := 0x7E
const PORTRAIT_H := 0xD4
const PORTRAIT_TOP := 0x14
const FRAME_COLOUR := 0xE8E8E8

var vs: VsScreen
var backgrounds: Array[VramImage] = []
var portraits: Array[Texture2D] = []
var frame_count := 0
var _system: VramImage


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	_system = image
	for i in 2:
		var v := image.duplicate_image()
		v.upload_file(screens_dir.path_join("makuma_%d.tims" % i))
		backgrounds.append(v)
	pictures_dir = screens_dir
	reload_pictures()
	# The caption bar's tail: subtracted, then added (VS_BAR_MODES 0x40, 0x20).
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, _caption_tail)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _caption_tail)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _glows)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


## The portraits, from the texture pack in use.
func reload_pictures() -> void:
	portraits = character_pictures(pictures_dir, "vs_portraits")


func show_state(game: GameFlow) -> void:
	vs = game.vs_screen
	frame_count = game.fight.vblank
	var b := vs.background - BACKGROUND_BASE
	vram = backgrounds[b] if b >= 0 and b < backgrounds.size() else _system
	redraw()


func _objects(kind: VsScreen.Kind) -> Array[VsScreen.VsObject]:
	var out: Array[VsScreen.VsObject] = []
	if vs == null:
		return out
	for o in vs.objects:
		if o.kind == kind:
			out.append(o)
	return out


func _draw() -> void:
	begin()
	black()
	if vs == null or vs.objects.is_empty():
		return
	if not _objects(VsScreen.Kind.BACKGROUND).is_empty():
		_background()
	if vs.slide == 0:
		for o in _objects(VsScreen.Kind.CAPTION_BAR):
			fill(o.x, o.y, o.dx - 0x6E, 0x24, psx(o.colour))


## FUN_80051C9C: the 7 × 6 grid of background cells (a black tile while sliding).
func _background() -> void:
	if vs.slide != 0:
		return
	var cell := 0
	var v_last := -1
	var y_top := 0x14
	for row in 7:
		var va := (v_last + 1) & 0xFF
		v_last += 0x20
		var vb := v_last & 0xFF
		var y_bot := ram.u32(ROW_EDGES + 4 * row) >> 16
		var x_left := 0
		var u_left := 0
		var u_last := -1
		for col in 6:
			var clut := 0x7D00 | ((cell & 0x30) << 2) | (cell & 0xF)
			cell += 1
			var x_right := ram.u16(COL_EDGES + 2 * col)
			var u_right := (u_last + 0x20) & 0xFF
			ft4(x_left, y_top, x_right - x_left, y_bot - y_top, u_left & 0xFF, va, u_right - (u_left & 0xFF) + 1,
				vb - va + 1, clut, 0xD)
			u_left = u_last + 0x21
			x_left = x_right
			u_last += 0x20
		y_top = y_bot


## FUN_80051E74: the caption bar's gradient tail (drawn at rest).
func _caption_tail() -> void:
	if vs == null or vs.slide != 0:
		return
	for o in _objects(VsScreen.Kind.CAPTION_BAR):
		var c := psx(o.colour)
		gradient(o.x + o.dx - 0x6E, o.y, 0x6E, 0x24, c, Color.BLACK, c, Color.BLACK)


## The additive glows: team battle's bars (arcade.ovl FUN_800B3708) and each portrait's tint.
func _glows() -> void:
	if vs == null:
		return
	if vs.slide == 0 and not _objects(VsScreen.Kind.TEAM_BARS).is_empty():
		gradient(0x8E, 0x60, 0xE2, 0x58, psx(0xE0E0E0), Color.BLACK, psx(0x707070), Color.BLACK)
		gradient(0, 0x15E, 0xE2, 0x58, Color.BLACK, psx(0x707070), Color.BLACK, psx(0xE0E0E0))
	for o in _objects(VsScreen.Kind.PORTRAIT):
		var at := o.at(vs.slide)
		var c := psx(o.colour)
		gradient(at.x + 2, at.y + 6, 0x7E, 0x6A, Color.BLACK, Color.BLACK, c, c)
		gradient(at.x + 2, at.y + 0x70, 0x7E, 0x6A, c, c, psx(0xC0C0C0), psx(0xC0C0C0))


## The portraits, icons, frames and texts, the last objects first.
func _front() -> void:
	if vs == null:
		return
	var objects := vs.objects.duplicate()
	objects.reverse()
	for o: VsScreen.VsObject in objects:
		var at := o.at(vs.slide)
		match o.kind:
			VsScreen.Kind.PORTRAIT:
				_portrait(o, at)
			VsScreen.Kind.ICON:
				portrait(at.x, at.y, o.arg, o.flags, frame_count)
			VsScreen.Kind.FRAME:
				if vs.slide == 0:
					fill(at.x, at.y, o.dx, o.dy, psx(0xE0E0E0))
	for o: VsScreen.VsObject in objects:
		if o.kind == VsScreen.Kind.NAME or (o.kind == VsScreen.Kind.TEXT and vs.slide == 0):
			var at := o.at(vs.slide) if o.kind == VsScreen.Kind.NAME else Vector2i(o.x, o.y)
			var s := o.text.replace("%d", str(o.arg))
			text(s, o.font, o.colour, at.x, at.y)


## FUN_800520A0: a 126 × 212 portrait, mirrored to face the middle, in its frame.
func _portrait(o: VsScreen.VsObject, at: Vector2i) -> void:
	for i in 4:
		var e := FRAME_RECTS + 8 * i
		var wh := ram.u32(e + 4)
		fill(at.x + ram.s16(e), at.y + ram.s16(e + 2), wh & 0xFFFF, wh >> 16, psx(FRAME_COLOUR))
	if o.picture >= portraits.size():
		return
	var dest := r(at.x + 2, at.y + 6, PORTRAIT_W, PORTRAIT_H)
	if o.facing != 0:
		# A negative size flips the texture in place.
		dest.size.x = -dest.size.x
	target.draw_texture_rect_region(portraits[o.picture], dest, Rect2(0, PORTRAIT_TOP, PORTRAIT_W, PORTRAIT_H))
