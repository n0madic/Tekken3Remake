class_name PadState
## Button bits of the game's pad word (PsyQ libetc layout, as in 0x800AE230).
## Directions are screen directions; the fight code turns them into forward/back.
## Names are plain text: the default font of web builds has no PlayStation symbols.

const L2 := 0x0001
const R2 := 0x0002
const L1 := 0x0004
const R1 := 0x0008
const TRIANGLE := 0x0010
const CIRCLE := 0x0020
const CROSS := 0x0040
const SQUARE := 0x0080
const SELECT := 0x0100
const START := 0x0800
const UP := 0x1000
const RIGHT := 0x2000
const DOWN := 0x4000
const LEFT := 0x8000
const FACE_BUTTONS := TRIANGLE | CIRCLE | CROSS | SQUARE
const CONFIRM := START | FACE_BUTTONS        ## Start or any face button
const HORIZONTAL := LEFT | RIGHT
const VERTICAL := UP | DOWN
const DIRECTIONS := HORIZONTAL | VERTICAL

const NAMES := {
	L2: "L2", R2: "R2", L1: "L1", R1: "R1",
	TRIANGLE: "Triangle", CIRCLE: "Circle", CROSS: "Cross", SQUARE: "Square",
	SELECT: "Select", START: "Start", UP: "Up", RIGHT: "Right", DOWN: "Down", LEFT: "Left",
}


static func describe(bits: int) -> String:
	var parts := PackedStringArray()
	for bit: int in NAMES:
		if bits & bit:
			parts.append(str(NAMES[bit]))
	return " ".join(parts) if not parts.is_empty() else "—"
