extends TestSuite
## VramImage's texels through a CLUT or direct: colour 0x0000 is transparent, and each 5-bit
## channel fills 8 bits with its top bits repeated below (31 → 255), as the converter's pictures
## (tools/remake_import/vram.py rgba), so the screens' sprites and pictures match.

const CLUT := Vector2i(0, 480)
const PAGE := Vector2i(64, 0)            ## tpage 1, 4-bit


func test_indexed_sprite_colours() -> void:
	var v := _vram()
	_put(v, CLUT.x, CLUT.y, 0x0000)
	_put(v, CLUT.x + 1, CLUT.y, 0x7FFF)
	_put(v, CLUT.x + 2, CLUT.y, 0x0001)
	_put(v, CLUT.x + 3, CLUT.y, 0x7C00)
	_put(v, PAGE.x, PAGE.y, 0x3210)       # texels 0, 1, 2, 3 (low nibble first)
	var clut := (CLUT.y << 6) | (CLUT.x / 16)
	var image := v.sprite(0, 0, 4, 1, clut, PAGE.x / 64).get_image()
	expect_equal(image.get_pixel(0, 0), Color(0, 0, 0, 0), "colour 0 is transparent")
	expect_equal(image.get_pixel(1, 0), Color8(255, 255, 255), "31 fills 255")
	expect_equal(image.get_pixel(2, 0), Color8(8, 0, 0), "1 is 8")
	expect_equal(image.get_pixel(3, 0), Color8(0, 0, 255), "blue")


func test_direct_picture_colours() -> void:
	var v := _vram()
	_put(v, 200, 100, 0x0010 | 0x0200 | 0x4000)   # r 16, g 16, b 16
	var image := v.picture(200, 100, 1, 1, 0, 2).get_image()
	expect_equal(image.get_pixel(0, 0), Color8(132, 132, 132), "16 is 132")


static func _vram() -> VramImage:
	var v := VramImage.new()
	v.words.resize(VramImage.WIDTH * VramImage.HEIGHT * 2)
	return v


static func _put(v: VramImage, x: int, y: int, word: int) -> void:
	v.words.encode_u16(2 * (y * VramImage.WIDTH + x), word)


## LoadImage wraps at the VRAM's edges as the GPU's transfer does.
func test_upload_wraps_at_the_edges() -> void:
	var v := _vram()
	var tim := PackedByteArray()
	tim.resize(8 + 12 + 8)
	tim.encode_u32(0, 0x10)
	tim.encode_u32(4, 2)
	tim.encode_u32(8, 12 + 8)
	tim.encode_u16(12, VramImage.WIDTH - 1)
	tim.encode_u16(14, VramImage.HEIGHT - 1)
	tim.encode_u16(16, 2)
	tim.encode_u16(18, 2)
	for i in 4:
		tim.encode_u16(20 + 2 * i, 0x100 + i)
	v.upload_tim(tim)
	expect_equal(v.word(VramImage.WIDTH - 1, VramImage.HEIGHT - 1), 0x100, "the corner")
	expect_equal(v.word(0, VramImage.HEIGHT - 1), 0x101, "the row continues at x 0")
	expect_equal(v.word(VramImage.WIDTH - 1, 0), 0x102, "the next row is line 0")
	expect_equal(v.word(0, 0), 0x103)
	expect_equal(v.words.size(), VramImage.WIDTH * VramImage.HEIGHT * 2, "nothing written past the end")
