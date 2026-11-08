extends TestSuite
## PadVibration against the game's own VibrationUpdate (`work/traces/vibration.bin`,
## tools/research/vibration_trace.py): every pattern and some pairs, frame by frame.

const DISC_DATA := [
	"test_scripts_match_the_game",
]
const TRACE := "vibration.bin"
const TABLES := AssetCatalog.ROOT + "tables"


## The game's OPTIONS setting holds a pad's motors still while its scripts run on (FUN_8002A37C).
func test_only_the_enabled_pad_moves_its_motors() -> void:
	var tables := FightTables.VibrationTables.new()
	tables.slots = PackedInt32Array([0, 0])
	tables.pulses = PackedInt32Array([0, 0xFF])
	tables.small = [PackedInt32Array(), PackedInt32Array([0x1100 | 2, 0x2100 | 2])]
	tables.large = [PackedInt32Array(), PackedInt32Array([0x2F00 | 4])]
	var devices := Pads.devices.duplicate()
	Pads.devices[0] = 100
	Pads.devices[1] = 101
	var pad := PadVibration.new(tables)
	pad.vibrate(2, 1)
	pad.drive(PackedInt32Array([1, 0]))
	var levels: Dictionary = Pads.rumble._levels
	var on: Vector2 = levels[100]
	var off: Vector2 = levels[101]
	expect(on.x > 0.0 and on.y > 0.0, "the enabled pad vibrates")
	expect_equal(off, Vector2.ZERO, "the other one stays still")
	expect(pad.small_on[1] and pad.large_level[1] > 0, "its scripts run on")
	levels.clear()
	Pads.devices = devices


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
