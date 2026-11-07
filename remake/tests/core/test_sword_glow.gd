extends TestSuite
## Yoshimitsu's sword glow (SwordGlow) against the game's FUN_8003161C and FUN_80031980 run in the
## CPU harness on random fighters, views and sword joints (`work/traces/sword_glow.bin`,
## tools/research/sword_glow_cases.py): every corner of the ten quads, the ordering-table entry each
## is filed in and the colours of the first two corners.

const FILE := "sword_glow.bin"
const MAGIC := "T3SG"
const QUAD_BYTES := 8 * 2 + 2 + 6


func test_matches_the_game() -> void:
	if not require(TraceFiles.path(FILE), "run tools/research/export_traces.py first"):
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
		var char_id := data.decode_s16(pos)
		var bank := data.decode_s16(pos + 2)
		var slot := data.decode_s16(pos + 4)
		var buffer := data.decode_s16(pos + 6)
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
		var f := FighterState.new()
		f.char_id = char_id
		f.bank_type = bank
		expect_equal(SwordGlow.shown(f), has_glow, "case %d: who has a glow" % n)
		if not has_glow:
			continue
		drawn += 1
		var glow := SwordGlow.build(block, view, tables, slot, buffer)
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
			for v in 2:
				var got := Vector3i.ZERO
				if SwordGlow.lit(q, v):
					got = glow.colour
				var want_rgb := Vector3i(data.decode_u8(o + 18 + 3 * v), data.decode_u8(o + 19 + 3 * v), data.decode_u8(o + 20 + 3 * v))
				if got != want_rgb:
					bad = "quad %d corner %d colour %s, the game's %s" % [q, v, got, want_rgb]
		pos += QUAD_BYTES * SwordGlow.QUADS
		if bad != "":
			failed += 1
			if failed <= 5:
				expect(false, "case %d (character %d, bank %d, slot %d, buffer %d): %s" % [n, char_id, bank, slot, buffer, bad])
	expect(drawn > count / 2, "most cases draw the glow (%d of %d)" % [drawn, count])
	expect_equal(failed, 0, "cases that differ from the game")


func test_only_yoshimitsu_and_mokujin_with_his_moves_glow() -> void:
	var f := FighterState.new()
	for char_id in 23:
		f.char_id = char_id
		f.bank_type = 4
		var expected := char_id == SwordGlow.YOSHIMITSU or char_id == SwordGlow.MOKUJIN
		expect_equal(SwordGlow.shown(f), expected, "character %d with bank 4" % char_id)
		f.bank_type = 1
		expect_equal(SwordGlow.shown(f), char_id == SwordGlow.YOSHIMITSU, "character %d with another bank" % char_id)


func test_costumes_have_their_colours_and_the_second_buffer_is_dimmer() -> void:
	expect_equal(SwordGlow.colour_of(8, 0), Vector3i(0x18, 0x30, 0x18), "slot 8, buffer 0: green")
	expect_equal(SwordGlow.colour_of(8, 1), Vector3i(0x0C, 0x1E, 0x0C), "slot 8, buffer 1")
	expect_equal(SwordGlow.colour_of(9, 0), Vector3i(0x48, 0x1E, 0x1E), "slot 9: red")
	expect_equal(SwordGlow.colour_of(9, 1), Vector3i(0x30, 0x18, 0x18), "slot 9, buffer 1")
	expect_equal(SwordGlow.colour_of(30, 0), Vector3i(0x3C, 0x1E, 0x0C), "any other slot: orange")
	expect_equal(SwordGlow.colour_of(30, 1), Vector3i(0x1E, 0x12, 0x0C), "any other slot, buffer 1")
	for slot: int in [8, 9, 30]:
		var bright := SwordGlow.colour_of(slot, 0)
		var dim := SwordGlow.colour_of(slot, 1)
		expect(dim.x <= bright.x and dim.y <= bright.y and dim.z <= bright.z, "slot %d: buffer 1 is no brighter" % slot)
		expect(dim.x + dim.y + dim.z < bright.x + bright.y + bright.z, "slot %d: buffer 1 is dimmer" % slot)


func test_the_quad_table_is_a_ribbon_with_black_edges() -> void:
	expect_equal(SwordGlow.QUAD_POINTS.size(), SwordGlow.QUADS * SwordGlow.QUAD_STRIDE, "ten quads of five bytes")
	expect_equal(SwordGlow.LIT.size(), SwordGlow.QUADS, "a lit mask per quad")
	for q in SwordGlow.QUADS:
		# Corners 2 and 3 are on an edge (points 6 and up), never coloured.
		expect(SwordGlow.corner(q, 2) >= 6 and SwordGlow.corner(q, 3) >= 6, "quad %d: edge corners" % q)
		expect(SwordGlow.corner(q, 0) < 6 and SwordGlow.corner(q, 1) < 6, "quad %d: centre corners" % q)
		expect(not SwordGlow.lit(q, 2) and not SwordGlow.lit(q, 3), "quad %d: edge corners are black" % q)
	# The first and last point of the centre line fade out.
	expect(not SwordGlow.lit(0, 0) and SwordGlow.lit(0, 1), "the first quad starts black")
	expect(not SwordGlow.lit(4, 0) and SwordGlow.lit(4, 1), "the last quad ends black")
