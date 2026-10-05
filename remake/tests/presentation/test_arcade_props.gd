extends TestSuite
## ArcadeProps against the arcade's own prop routines: tools/research/verify_arcade_props.py ran stage 3's
## carousel and stage 11's helicopter (every mode, two rounds) in the CPU harness under random
## camera turns and recorded every frame's state (work/traces/arcade_props.json and .bin).

const TRACE := "arcade_props.json"
const FRAMES := "arcade_props.bin"


func test_props_follow_the_arcade_frame_for_frame() -> void:
	if not require(TraceFiles.path(TRACE), "run tools/research/verify_arcade_props.py --export first"):
		return
	var trace: Dictionary = JsonFile.read(TraceFiles.path(TRACE))
	var words := JsonFile.number(trace.get("frame_words", 0))
	var frames := FileAccess.get_file_as_bytes(TraceFiles.path(FRAMES)).to_int32_array()
	var states := PackedInt32Array()
	# The .bin holds s16 words: unpack them from the 32-bit view.
	for w in frames:
		states.append(ArcadeProps.s16(w & 0xFFFF))
		states.append(ArcadeProps.s16((w >> 16) & 0xFFFF))
	var sine := JsonFile.ints(trace.get("sine", []))
	var at := 0
	for case_data: Dictionary in trace.get("cases", []):
		var stage := JsonFile.number(case_data.get("stage", 0))
		var props := ArcadeProps.new(ArcadeProps.CAROUSEL if stage == 3 else ArcadeProps.HELICOPTER, sine)
		var first_difference := -1
		var frame := 0
		for round_data: Dictionary in case_data.get("rounds", []):
			props.start(JsonFile.number(round_data.get("buttons", 0)), JsonFile.number(round_data.get("counter", 0)))
			for yaw: int in JsonFile.ints(round_data.get("yaws", [])):
				props.step(yaw)
				if first_difference < 0 and props.words() != states.slice(at, at + words):
					first_difference = frame
				at += words
				frame += 1
		expect(first_difference < 0, "%s: equal on all %d frames (first difference at %d)" % [
			case_data.get("name", ""), frame, first_difference])
	expect_equal(at, states.size(), "every recorded frame compared")


## FUN_801E3DE0's mode buttons are the attack buttons in pose order: LP □ 0, RP △ 1, LK ✕ 2, RK ○ 3;
## none: the counter's low bits.
func test_helicopter_mode_from_held_buttons() -> void:
	var expected := {PadState.SQUARE: 0, PadState.TRIANGLE: 1, PadState.CROSS: 2, PadState.CIRCLE: 3}
	for button: int in expected:
		var props := ArcadeProps.new(ArcadeProps.HELICOPTER)
		props.start(ArcadeProps.arcade_buttons(button), 1)
		expect_equal(props.mode, expected[button], "button 0x%x" % button)
	var plain := ArcadeProps.new(ArcadeProps.HELICOPTER)
	plain.start(ArcadeProps.arcade_buttons(PadState.START), 6)
	expect_equal(plain.mode, 2, "no attack button: the counter's low bits")
