extends TestSuite
## Yoshimitsu's sword glow on the arcade's models (ArcadeSwordGlow) against the arcade's FUN_80192ecc
## run in the CPU harness on random fighters, views and sword joints (`work/traces/arcade_sword_glow.bin`,
## tools/research/arcade_sword_glow_cases.py): every corner of the ten quads, the ordering-table entry
## each is filed in and the colour.

const FILE := "arcade_sword_glow.bin"
const MAGIC := "T3AG"
const QUAD_BYTES := 8 * 2 + 2 + 3


func test_matches_the_game() -> void:
	if not require(TraceFiles.path(FILE), "run tools/research/arcade_sword_glow_cases.py first"):
		return
	if not require(AssetCatalog.ROOT + "tables/fight.json"):
		return
	var tables := FightTables.load_from(AssetCatalog.ROOT + "tables")
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(FILE))
	expect_equal(data.slice(0, 4).get_string_from_ascii(), MAGIC, "the trace file")
	var count := data.decode_u32(8)
	var pos := 12
	var failed := 0
	var drawn := 0
	for n in count:
		var slot := data.decode_s16(pos)
		var char_id := data.decode_s16(pos + 2)
		var bank := data.decode_s16(pos + 4)
		var parity := data.decode_s16(pos + 6)
		pos += 8
		var view := ViewMatrix.new()
		view.rot = Traces.s16s(data, pos, 9)
		view.t = PackedInt32Array([data.decode_s32(pos + 18), data.decode_s32(pos + 22), data.decode_s32(pos + 26)])
		view.h = data.decode_s16(pos + 30)
		pos += 34
		var block := JointFrame.new(Traces.s16s(data, pos, 9),
				PackedInt32Array([data.decode_s32(pos + 18), data.decode_s32(pos + 22), data.decode_s32(pos + 26)]))
		pos += 30
		var has_glow := data.decode_u8(pos) != 0
		pos += 4
		expect_equal(has_glow, slot in [SwordGlow.SLOT_GREEN, SwordGlow.SLOT_RED] \
				or (char_id == SwordGlow.MOKUJIN and bank == SwordGlow.YOSHIMITSU_BANK), "case %d: who has a glow" % n)
		if not has_glow:
			continue
		drawn += 1
		var glow := ArcadeSwordGlow.build(block, view, tables, slot, parity)
		var bad := ""
		for q in SwordGlow.QUADS:
			var o := pos + QUAD_BYTES * q
			for v in 4:
				var p := SwordGlow.corner(q, v)
				var want := Vector2i(data.decode_s16(o + 4 * v), data.decode_s16(o + 4 * v + 2))
				if Vector2i(glow.points[2 * p], glow.points[2 * p + 1]) != want:
					bad = "quad %d corner %d at %s, the game's %s" % [q, v, Vector2i(glow.points[2 * p], glow.points[2 * p + 1]), want]
			if SwordGlow.entry(glow, q) != data.decode_u16(o + 16):
				bad = "quad %d filed in entry %d, the game's %d" % [q, SwordGlow.entry(glow, q), data.decode_u16(o + 16)]
			var want_rgb := Vector3i(data.decode_u8(o + 18), data.decode_u8(o + 19), data.decode_u8(o + 20))
			if glow.colour != want_rgb:
				bad = "quad %d colour %s, the game's %s" % [q, glow.colour, want_rgb]
		pos += QUAD_BYTES * SwordGlow.QUADS
		if bad != "":
			failed += 1
			if failed <= 5:
				expect(false, "case %d (slot %d, parity %d): %s" % [n, slot, parity, bad])
	expect(drawn > count / 2, "most cases draw the glow (%d of %d)" % [drawn, count])
	expect_equal(failed, 0, "cases that differ from the game")


func test_costumes_have_their_colours_and_odd_frames_are_brighter() -> void:
	expect_equal(ArcadeSwordGlow.colour_of(8, 0), Vector3i(0x10, 0x28, 0), "slot 8, even frame: green")
	expect_equal(ArcadeSwordGlow.colour_of(8, 1), Vector3i(0x20, 0x40, 0), "slot 8, odd frame")
	expect_equal(ArcadeSwordGlow.colour_of(9, 0), Vector3i(0x40, 0x20, 0), "slot 9, even frame: red")
	expect_equal(ArcadeSwordGlow.colour_of(9, 3), Vector3i(0x60, 0x28, 0), "slot 9, odd counter")
	expect_equal(ArcadeSwordGlow.colour_of(30, 0), Vector3i(0x28, 0x18, 0), "any other slot: orange")
	expect_equal(ArcadeSwordGlow.colour_of(30, 1), Vector3i(0x50, 0x28, 0), "any other slot, odd frame")
	for slot: int in [8, 9, 30]:
		var even := ArcadeSwordGlow.colour_of(slot, 0)
		var odd := ArcadeSwordGlow.colour_of(slot, 1)
		expect(odd.x >= even.x and odd.y >= even.y and odd.z >= even.z, "slot %d: odd frames are no dimmer" % slot)
		expect(odd.x + odd.y + odd.z > even.x + even.y + even.z, "slot %d: odd frames are brighter" % slot)


func test_the_texture_ramps_across_each_quad() -> void:
	expect_equal(ArcadeSwordGlow.UV.size(), SwordGlow.QUADS * 8, "four texels a quad")
	for q in SwordGlow.QUADS:
		# Corners 0 and 1 are on the centre line (u = 15, white), corners 2 and 3 on an edge (u = 0, black).
		for v in 2:
			expect_equal(ArcadeSwordGlow.uv(q, v).x, ArcadeSwordGlow.PICTURE - 1, "quad %d corner %d: centre" % [q, v])
		for v in range(2, 4):
			expect_equal(ArcadeSwordGlow.uv(q, v).x, 0, "quad %d corner %d: edge" % [q, v])
		for v in 4:
			expect(ArcadeSwordGlow.uv(q, v).y < ArcadeSwordGlow.PICTURE, "quad %d corner %d: inside the picture" % [q, v])
	# Only the quads at the ribbon's two ends start inside the picture (its top rows are black).
	expect_equal(ArcadeSwordGlow.uv(0, 0).y, 0, "the first quad starts at the dark top")
	expect_equal(ArcadeSwordGlow.uv(4, 0).y, 0, "the last quad starts at the dark top")
	expect_equal(ArcadeSwordGlow.uv(3, 3).y, 7, "the fourth quad ends half way down")
