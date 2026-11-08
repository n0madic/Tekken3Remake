class_name ArcadeWind
extends RefCounted
## The arcade's wind on the helicopter stage (stage 11), which blows the arcade models' swinging
## attachments (ArcadeAttachments.wind): FUN_801E6ACC picks one of eight directions when a fight loads,
## and FUN_8019C738 gusts it every frame, before the fighters' skeletons. A round starts its gust again.

const STAGE := 11
const DIRECTIONS := 0xE00         ## rand() & 0xE00: eight directions of the 4096-unit turn
const PHASE_STEP := 0x20
const GUST_FLIP := 0x100          ## the gust turns back when its phase reaches this bit
const LIFT := 0x100

var vector := PackedInt32Array([0, 0, 0])   ## the wind this step, normalised to 4096. In still air it points up; only x and z are read
var _sign_x := 0
var _sign_z := 0
var phase := 0                    ## 0x8021F698
var tables: ArcadeAttachmentTables


## FUN_8019C72C.
func round_start() -> void:
	phase = 0


## Still air.
func calm() -> void:
	vector = PackedInt32Array([0, 0, 0])
	_sign_x = 0
	_sign_z = 0


## One of the directions, by the random number `draw`.
func blow(draw: int) -> void:
	var angle := draw & DIRECTIONS
	_sign_x = signi(tables.solver.tables.sin16(angle << 4))
	_sign_z = signi(tables.solver.tables.cos16(angle << 4))


## FUN_8019C738: the next gust, (±g, LIFT − g, ±g) normalised, g the low byte of a triangle wave
## of the phase.
func step() -> void:
	var v := phase + PHASE_STEP
	if v & GUST_FLIP:
		v = -(phase + PHASE_STEP + 1)
	phase += PHASE_STEP
	var u := v & 0xFF                    # the gust's low byte (lbu)
	var raw := PackedInt32Array([Fx.s16(_sign_x * u), Fx.s16(LIFT - u), Fx.s16(_sign_z * u)])
	vector = Gte.vector_normal(raw, tables.fighter.rsqrt)
