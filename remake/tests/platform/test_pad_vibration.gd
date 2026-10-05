extends TestSuite
## PadVibration against the game's own VibrationUpdate (`work/traces/vibration.bin`,
## tools/research/vibration_trace.py): every pattern and some pairs, frame by frame.

const TRACE := "vibration.bin"
const TABLES := AssetCatalog.ROOT + "tables"


func test_scripts_match_the_game() -> void:
	if not require(TraceFiles.path(TRACE), "run tools/research/export_traces.py first"):
		return
	if not require(TABLES.path_join("fight.json")):
		return
	var tables := FightTables.load_from(TABLES)
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(TRACE))
	expect_equal(data.slice(0, 4).get_string_from_ascii(), "T3VB", "trace magic")
	var cases := data.decode_u32(8)
	var pos := 12
	for c in cases:
		var count := data.decode_u8(pos)
		var patterns := data.slice(pos + 1, pos + 1 + count)
		pos += 1 + count
		var frames := data.decode_u16(pos)
		pos += 2
		var pad := PadVibration.new(tables.vibration)
		for p in patterns:
			pad.vibrate(0, p)
		for frame in frames:
			pad.update()
			var small := data.decode_u8(pos)
			var large := data.decode_u8(pos + 1)
			pos += 2
			if (1 if pad.small_on[0] else 0) != small or pad.large_level[0] != large:
				expect(false, "patterns %s frame %d: small %s large %d ≠ %d %d" % [patterns, frame,
					pad.small_on[0], pad.large_level[0], small, large])
				return
