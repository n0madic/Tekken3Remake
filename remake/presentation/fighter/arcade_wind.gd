class_name ArcadeWind
extends RefCounted
## The arcade's wind on the helicopter stage (stage 11), which blows the arcade models' swinging
## attachments (ArcadeAttachments.wind): FUN_801e6acc picks one of eight directions when a fight
## starts, and FUN_8019c738 gusts it every step, after the fighters (they feel the last step's).
## The direction comes from the presentation's random numbers, not the fight's.

const STAGE := 11
const DIRECTIONS := 0xE00         ## rand() & 0xE00: eight directions of the 4096-unit turn
const PHASE_STEP := 0x20
const GUST_FLIP := 0x100          ## the gust turns back when its phase reaches this bit
const LIFT := 0x100

var vector := PackedInt32Array([0, 0, 0])   ## the wind this step (normalised to 4096, or zero)
var _sign_x := 0
var _sign_z := 0
var _phase := 0


## Starts a fight on `stage`: still air unless it is the helicopter stage.
func start(stage: int, rng: RandomNumberGenerator) -> void:
	_phase = 0
	vector = PackedInt32Array([0, 0, 0])
	_sign_x = 0
	_sign_z = 0
	if stage != STAGE:
		return
	var angle := rng.randi() & DIRECTIONS
	_sign_x = signi(ArcadeAttachments.solver().tables.sin16(angle << 4))
	_sign_z = signi(ArcadeAttachments.solver().tables.cos16(angle << 4))


## FUN_8019c738: the next gust, (±g, LIFT − g, ±g) normalised, g the low byte of a triangle wave
## of the phase.
func step() -> void:
	var v := _phase + PHASE_STEP
	if v & GUST_FLIP:
		v = -(_phase + PHASE_STEP + 1)
	_phase += PHASE_STEP
	if _sign_x == 0 and _sign_z == 0:
		vector = PackedInt32Array([0, 0, 0])
		return
	var u := v & 0xFF                    # the gust's low byte (lbu)
	var raw := PackedInt32Array([Fx.s16(_sign_x * u), Fx.s16(LIFT - u), Fx.s16(_sign_z * u)])
	vector = Gte.vector_normal(raw, ArcadeAttachments.fighter_tables().rsqrt)
