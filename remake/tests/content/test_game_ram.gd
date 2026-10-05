extends TestSuite
## The game's memory the screens read (GameRam): a text another release keeps longer than Japan
## Rev.1's place for it is read aside by address, the rest from the block's bytes.

const BASE := 0x800B9378


func test_texts_kept_aside() -> void:
	var ram := GameRam.new()
	var b := GameRam.Block.new()
	b.name = "title"
	b.base = BASE
	b.bytes = "SHORT".to_ascii_buffer() + PackedByteArray([0]) + "NEXT".to_ascii_buffer() + PackedByteArray([0])
	b.strings[BASE] = "A LONGER TEXT"
	ram.blocks.append(b)
	expect_equal(ram.string(BASE), "A LONGER TEXT", "the text kept aside")
	expect_equal(ram.string(BASE + 6), "NEXT", "the block's own text")
	expect_equal(ram.u8(BASE), 0x53, "the bytes stay the block's")
