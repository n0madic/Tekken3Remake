class_name VramImage
extends RefCounted
## The PlayStation's VRAM (1024 × 512 words) for the 2D screens: the resident system textures,
## then the screen's own pictures uploaded in the game's order (LoadImage of TIM blocks). Sprites
## are cut out by texture page, CLUT and texel rectangle, as the GPU reads them: 4- and 8-bit
## texels through a CLUT, 15-bit direct; the colour 0x0000 is transparent. Pictures are cached.

const WIDTH := 1024
const HEIGHT := 512
const MAX_SIZE := Vector2i(1024, 512)   ## the largest rectangle the GPU draws
const OPAQUE := -0x1000000            ## alpha 0xFF of an RGBA8 texel as a signed 32-bit int
const PICTURE_KEY := 1 << 62          ## the picture cache keys' flag

var words := PackedByteArray()        ## little-endian u16 per VRAM word
var _cache: Dictionary = {}          ## packed sprite / picture key → Texture2D
var _checks: Dictionary = {}          ## TexturePacks.vram_sprite's checks of this VRAM's words
var _generation := -1                 ## the TexturePacks generation the caches belong to


static func load_system(path: String) -> VramImage:
	var v := VramImage.new()
	v.words = FileAccess.get_file_as_bytes(path)
	if v.words.size() != WIDTH * HEIGHT * 2:
		Log.error("VramImage: %s is not a VRAM image" % path)
		v.words.resize(WIDTH * HEIGHT * 2)
	return v


func duplicate_image() -> VramImage:
	var v := VramImage.new()
	v.words = words.duplicate()
	return v


func word(x: int, y: int) -> int:
	return words.decode_u16(2 * ((y & 511) * WIDTH + (x & 1023)))


## LoadImage of a TIM's CLUT and pixel blocks; a rectangle past the VRAM's edges wraps around, as
## the GPU's transfer does.
func upload_tim(tim: PackedByteArray) -> void:
	var flags := tim.decode_u32(4)
	var at := 8
	var blocks := 2 if flags & 8 else 1
	for i in blocks:
		var length := tim.decode_u32(at)
		if length >= 12:
			var x := tim.decode_u16(at + 4)
			var y := tim.decode_u16(at + 6)
			var w := tim.decode_u16(at + 8)
			var h := tim.decode_u16(at + 10)
			var wraps := (x & (WIDTH - 1)) + w > WIDTH
			for row in h:
				var src := at + 12 + row * w * 2
				var line := ((y + row) & (HEIGHT - 1)) * WIDTH
				var n := clampi(tim.size() - src, 0, w * 2)
				if not wraps:
					var dst := 2 * (line + (x & (WIDTH - 1)))
					for k in n:
						words[dst + k] = tim[src + k]
				else:
					for k in n:
						words[2 * (line + ((x + (k >> 1)) & (WIDTH - 1))) + (k & 1)] = tim[src + k]
		at += length
	_clear()


func _clear() -> void:
	_cache.clear()
	_checks.clear()
	_generation = TexturePacks.generation


## A cached sprite, after dropping the caches of another texture pack.
func _cached(key: int) -> Texture2D:
	if _generation != TexturePacks.generation:
		_clear()
	return _cache.get(key) as Texture2D


## The texture pack's replacement of an indexed sprite (depth 0 or 1), cached under `key` (not
## when negative), or null.
func _replacement(key: int, page_x: int, page_y: int, depth: int, u: int, v: int, w: int, h: int,
		clut_x: int, clut_y: int) -> Texture2D:
	if depth >= 2:
		return null
	var hd := TexturePacks.vram_sprite(self, _checks, page_x, page_y, 4 << depth, u, v, w, h, clut_x, clut_y)
	if hd != null and key >= 0:
		_cache[key] = hd
	return hd


## Every TIM of a `.tims` file (u32 count, then u32 length and bytes per TIM), in order.
func upload_file(path: String) -> void:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return
	var count := data.decode_u32(0)
	var at := 4
	for i in count:
		var n := data.decode_u32(at)
		upload_tim(data.slice(at + 4, at + 4 + n))
		at += 4 + n


## A 15-bit colour as RGBA8 bytes in a little-endian int (0x0000 transparent). Each 5-bit
## channel fills 8 bits with its top bits repeated below (31 → 255), as the converter's pictures
## (tools/remake_import/vram.py rgba), so sprites cut here match them.
static func _rgba(c: int) -> int:
	if c == 0:
		return 0
	return OPAQUE | _channel(c & 31) | _channel((c >> 5) & 31) << 8 | _channel((c >> 10) & 31) << 16


static func _channel(v: int) -> int:
	return (v << 3) | (v >> 2)


## w × h texels from texel (u, v) (wrapped by `mask`) of the page at VRAM word (page_x, page_y),
## at depth 0 (4-bit), 1 (8-bit) or other (15-bit direct), through the CLUT at (clut_x, clut_y).
func _texels(page_x: int, page_y: int, u: int, v: int, w: int, h: int, mask: int, depth: int,
		clut_x: int, clut_y: int) -> ImageTexture:
	var pixels := PackedInt32Array()
	pixels.resize(w * h)
	var palette := PackedInt32Array()
	if depth == 0 or depth == 1:
		palette.resize(16 << (depth * 4))
		for k in palette.size():
			palette[k] = _rgba(word(clut_x + k, clut_y))
	var i := 0
	for y in h:
		var row := ((page_y + ((v + y) & mask)) & 511) * WIDTH
		match depth:
			0:
				for x in w:
					var tx := (u + x) & mask
					var wd := words.decode_u16(2 * (row + ((page_x + (tx >> 2)) & 1023)))
					pixels[i] = palette[(wd >> ((tx & 3) * 4)) & 0xF]
					i += 1
			1:
				for x in w:
					var tx := (u + x) & mask
					var wd := words.decode_u16(2 * (row + ((page_x + (tx >> 1)) & 1023)))
					pixels[i] = palette[(wd >> ((tx & 1) * 8)) & 0xFF]
					i += 1
			_:
				for x in w:
					pixels[i] = _rgba(words.decode_u16(2 * (row + ((page_x + ((u + x) & mask)) & 1023))))
					i += 1
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels.to_byte_array())
	return ImageTexture.create_from_image(image)


## A w × h sprite from texel (u, v) of texture page `tpage` through CLUT `clut` (the GPU's
## packet words: tpage bits 0–4 page x/y, 7–8 depth; clut bits 0–5 x/16, 6–14 y).
func sprite(u: int, v: int, w: int, h: int, clut: int, tpage: int) -> Texture2D:
	if w <= 0 or h <= 0 or w > MAX_SIZE.x or h > MAX_SIZE.y:
		# The GPU draws nothing for such a rectangle.
		return null
	# Every input bit the sprite depends on: u, v 8 bits, w - 1 10, h - 1 9, clut 15, tpage 7.
	var key := (u & 0xFF) | (v & 0xFF) << 8 | (w - 1) << 16 | (h - 1) << 26 | (clut & 0x7FFF) << 35 \
			| (tpage & 0x1F) << 50 | ((tpage >> 7) & 3) << 55
	var cached := _cached(key)
	if cached != null:
		return cached
	var page_x := (tpage & 0xF) * 64
	var page_y := ((tpage >> 4) & 1) * 256
	var depth := (tpage >> 7) & 3
	var clut_x := (clut & 0x3F) * 16
	var clut_y := (clut >> 6) & 0x1FF
	var hd := _replacement(key, page_x, page_y, depth, u & 0xFF, v & 0xFF, w, h, clut_x, clut_y)
	if hd != null:
		return hd
	var tex := _texels(page_x, page_y, u, v, w, h, 0xFF, depth, clut_x, clut_y)
	_cache[key] = tex
	return tex


## FUN_8004DE84's picture: w × h texels from VRAM word (vx, vy) at depth 0 (4-bit), 1 (8-bit)
## or 2 (15-bit), through CLUT `clut` for the indexed depths.
func picture(vx: int, vy: int, w: int, h: int, clut: int, depth: int) -> Texture2D:
	if w <= 0 or h <= 0 or w > MAX_SIZE.x or h > MAX_SIZE.y:
		return null
	# Keyed apart from the sprites (bit 62) while every input fits its field, else not cached.
	var key := -1
	if vx >= 0 and vx < 0x1000 and vy >= 0 and vy < 0x1000 and depth >= 0 and depth < 4:
		key = PICTURE_KEY | vx | vy << 12 | (w - 1) << 24 | (h - 1) << 34 | (clut & 0x7FFF) << 43 | depth << 58
	var cached := _cached(key)
	if cached != null:
		return cached
	var clut_x := (clut & 0x3F) * 16
	var clut_y := (clut >> 6) & 0x1FF
	var page_x := vx & ~63
	var page_y := vy & ~255
	var hd := _replacement(key, page_x, page_y, depth, (vx - page_x) * (4 >> depth), vy - page_y, w, h, clut_x, clut_y)
	if hd != null:
		return hd
	var tex := _texels(vx, vy, 0, 0, w, h, -1, depth, clut_x, clut_y)
	if key >= 0:
		_cache[key] = tex
	return tex
