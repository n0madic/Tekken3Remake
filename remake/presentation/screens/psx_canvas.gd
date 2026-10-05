class_name PsxCanvas
extends ScreenCanvas
## A screen drawn the game's way: sprites cut from the VRAM image by texture page, CLUT and texel
## rectangle (SPRT, FUN_8004DE84's pictures, the HUD portraits and timer digits), with the game's
## tables read from its memory (GameRam) by address, as the verified Python ports do.

const PORTRAIT_UV := 0x8002152C              ## per character: u32 uv|clut, u16 tpage
const PORTRAIT_FRAME_COLOURS := 0x80021664
const PORTRAIT_FRAME_LINES := 0x800215EC
const TIMER_UV := 0x80022154
const COIN_TEXTS := 0x800223A0
const FREE_TEXTS := 0x800223D8
## FUN_80029860's display rectangle (0x800AE6F8): the part of the 368 × 480 screen drawn to.
const DISPLAY := Rect2i(0, 20, 368, 448)
const BACKDROPS: Array[int] = [0x80022CF8, 0x80022D78]   ## FUN_800551FC's gradient quads: 8 words each
const FRAME_COUNT_SHIFT := 4

var ram: GameRam
var vram: VramImage
var pictures_dir := ""                       ## the screens' directory the pictures come from


## The pictures the view takes from TexturePacks (a texture pack or filter changed): none here.
func reload_pictures() -> void:
	pass


func setup_psx(hud_data: HudData, game_ram: GameRam, image: VramImage) -> void:
	setup_canvas(hud_data)
	ram = game_ram
	vram = image


## SPRT: w × h texels from the packet's uv|clut word, in the texture page `tpage`.
## The pictures `<folder>/<n>.png` of the screens' directory, one per character (a texture pack may
## replace them). Not found by FileAccess.file_exists(): an export packs only the imported textures,
## not the .png files, so the count is the roster's.
static func character_pictures(screens_dir: String, folder: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in GameProgress.CHARACTERS:
		out.append(TexturePacks.texture(screens_dir.path_join("%s/%d.png" % [folder, i])))
	return out


func sprt(x: float, y: float, w: int, h: int, uv_clut: int, tpage: int, tint := Color.WHITE) -> void:
	var tex := vram.sprite(uv_clut & 0xFF, (uv_clut >> 8) & 0xFF, w, h, (uv_clut >> 16) & 0xFFFF, tpage)
	image(tex, x, y, w, h, tint)


## FUN_8004DE84: a VRAM picture drawn at (sx, sy).
func picture(sx: float, sy: float, w: int, h: int, vx: int, vy: int, clut: int, mode: int, tint := Color.WHITE) -> void:
	image(vram.picture(vx, vy, w, h, clut, (mode >> 7) & 3), sx, sy, w, h, tint)


## FUN_8004BA68: a portrait's frame, ten lines in the three colours of set `flags & 3`, pulsing
## with flag 0x10 (`frames`: the frame counter), clipped to a draw area when given.
func portrait_frame(x: int, y: int, flags: int, frames: int, clip := Rect2()) -> void:
	var k := triangle(frames << FRAME_COUNT_SHIFT) if flags & 0x10 else 0x80
	var colours: Array[Color] = []
	for i in 3:
		colours.append(psx(scale_colour(ram.u32(PORTRAIT_FRAME_COLOURS + (flags & 3) * 0x28 + 4 * i), k * 2)))
	var base := (x & 0xFFFF) | ((y << 16) & 0xFFFFFFFF)
	for i in 10:
		var e := PORTRAIT_FRAME_LINES + 12 * i
		var a := (base + ram.u32(e + 4)) & 0xFFFFFFFF
		var b := (base + ram.u32(e + 8)) & 0xFFFFFFFF
		line(Fx.s16(a & 0xFFFF), Fx.s16(a >> 16), Fx.s16(b & 0xFFFF), Fx.s16(b >> 16), colours[ram.s32(e)], clip)


## FUN_8004BBC0: a character's HUD portrait (flags 8: no frame, 0x20: dimmed, 0x40: the lock),
## the frame drawn over it (`frames`: the frame counter of a pulsing frame).
func portrait(x: float, y: float, key: int, flags: int, frames := 0) -> void:
	if not flags & 8:
		_portrait_face(x + 2, y + 3, key, flags)
		portrait_frame(int(x), int(y), flags, frames)
	else:
		_portrait_face(x, y, key, flags)


func _portrait_face(x: float, y: float, key: int, flags: int) -> void:
	if flags & 0x80:
		return
	var i := 0x17 if key == 0x59 else key >> 2
	var uvc := ram.u32(PORTRAIT_UV + 8 * i)
	var tp := ram.u16(PORTRAIT_UV + 8 * i + 4)
	if flags & 0x20:
		uvc = (uvc & 0xFFFF) | 0x7D500000
	if i == 0x14:
		sprt(x, y, 0x20, 0x18, uvc, tp)
		sprt(x, y + 0x18, 0x20, 0x18, uvc + 0x20, tp)
		sprt(x, y + 0x30, 0x20, 0x0A, uvc + 0x40, tp)
	elif i < 0x16:
		sprt(x, y, 0x20, 0x3A, uvc, tp)
	else:
		sprt(x, y, 0x20, 0x0A, uvc, tp)
		sprt(x, y + 10, 0x20, 0x18, (uvc & 0xFFFF00FF) + 0x20, tp)
		sprt(x, y + 0x22, 0x20, 0x18, (uvc & 0xFFFF00FF) + 0x40, tp)
	if flags & 0x40:
		sprt(x, y - 5, 0x20, 0x20, 0x7F1DE000, 0x1F)
		sprt(x, y + 0x1B, 0x20, 0x20, 0x7F1DE020, 0x1F)


## FUN_8004D15C with a format string of the game's memory.
func ptext(format_address: int, args: Array) -> void:
	print_fmt(ram.string(format_address), args)


## POLY_FT4 over an axis-aligned w × h rectangle: tw × th texels from (u, v) stretched over it.
func ft4(x: float, y: float, w: float, h: float, u: int, v: int, tw: int, th: int, clut: int, tpage: int,
		tint := Color.WHITE) -> void:
	if tw <= 0 or th <= 0:
		return
	image(vram.sprite(u, v, tw, th, clut, tpage), x, y, w, h, tint)


## FUN_800551FC: the menus' gradient backdrop (kind 0: four opaque quads, 1: two blended), the
## table's 0xFFFFFFFF corners in `colour`.
func backdrop(kind: int, colour: int) -> void:
	var table := BACKDROPS[kind]
	for q in 4 if kind == 0 else 2:
		var e := table + 32 * q
		var c: Array[Color] = []
		for i in 4:
			var w := ram.u32(e + 16 + 4 * i)
			c.append(psx(colour if w == 0xFFFFFFFF else w))
		var v: Array[Vector2] = []
		for i in 4:
			var xy := ram.u32(e + 4 * i)
			v.append(Vector2(Fx.s16(xy & 0xFFFF), Fx.s16(xy >> 16)))
		quad(v[0], v[1], v[2], v[3], c[0], c[1], c[2], c[3])


## FUN_8004E254: a colour word scaled by k / 256 per channel (saturating).
static func scale_colour(c: int, k: int) -> int:
	var out := 0
	for sh: int in [0, 8, 16]:
		out |= mini((((c >> sh) & 0xFF) * k) >> 8, 0xFF) << sh
	return out


## FUN_8004F1D0: the blinking coin prompt of a side that has not joined (PUSH Pn START, and
## every other 64 frames FREE PLAY; INSERT COIN without a controller in the port). Both ports
## count as plugged: the keyboard plays either side.
func coin(player: int, x: int, y: int, colour: int, frames: int) -> void:
	if not frames & 0x30:
		return
	var plugged := true
	var table := COIN_TEXTS
	var k := 0
	if not frames & 0x40:
		k = (1 if player == 0 else 2) if plugged else 0
	else:
		k = 0 if plugged else 1
		table = FREE_TEXTS
	text(ram.string(ram.u32(table + 8 * k)), 0, colour, x - ram.u32(table + 8 * k + 4), y)


## FUN_8004E410: two 16 × 46 digits (−1: the infinity sign).
func timer(value: int, x: float, y: float, clut: int) -> void:
	var digits := 0xAB if value == -1 else ((value / 10) % 10) << 4 | value % 10
	for i in 2:
		var d := digits & 0xF
		digits >>= 4
		sprt(x, y, 0x10, 0x2E, ram.u32(TIMER_UV + 4 * d) | (clut << 16), 0xE)
		x -= 0xF
