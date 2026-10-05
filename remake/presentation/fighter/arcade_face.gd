class_name ArcadeFace
extends RefCounted
## The face of an arcade costume (FUN_80193F90 and FUN_80193EA4, arcade/README.md#eye-shapes), as a
## presentation effect: the eye shape shown, one step per simulation step.
##
## The game keeps the shape and a hold counter. A move with the closed-eyes field shows the "held"
## shape for 2 frames, a lying fighter the "down" one; when the counter runs out, open eyes (shape
## 0) turn to the costume's blink shape for 3 frames and any other shape back to open eyes for a
## random odd 1–255. An attack shout (SimEvents SHOUT) shows the character's shout shape for as many
## frames as its voice lasts (FUN_801A1C74); a costume lacking a shape keeps its face for that
## change. The blink and its random open times are this view's own (`rand`), not the simulation's.

const SHAPES := 6
const OPEN := 0
const BLINK_FRAMES := 3
const HELD_FRAMES := 2
const DOWN_FRAMES := 2
const SHOUT_FIRST := 0x2000            ## the first voice id with a shout face
const OPEN_MASK := 0xFE                ## the open time is `(rand & 0xFE) | 1` frames
const SEED_STEP := 7919                ## between the seeds of two faces (a prime)

static var _created := 0               ## the faces made so far in this session (`next_seed`)

var shape := OPEN                      ## the shape shown
var rand := Callable(self, "_random")  ## the random numbers of the open times
var _eyes: CharacterModel.ArcadeEyes
var _hold := 0
var _rng := RandomNumberGenerator.new()


## A seed that differs for every face of the session (so two fighters of one costume, or two fights,
## do not blink alike) and is the same in every run of the program (screenshots repeat).
static func next_seed() -> int:
	_created += 1
	return _created * SEED_STEP


func _init(eyes: CharacterModel.ArcadeEyes, seed_value: int = 0) -> void:
	_eyes = eyes
	_rng.seed = seed_value


## One frame: `held` while the running move keeps the eyes closed (Blinker.held), `down` while it
## is a lying one (Blinker.lying). Returns the shape shown.
func step(held: bool, down: bool) -> int:
	if held:
		_show(_eyes.held, HELD_FRAMES)
	elif down:
		_show(_eyes.down, DOWN_FRAMES)
	if _hold == 0:
		if shape == OPEN:
			_show(_eyes.blink, BLINK_FRAMES)
		else:
			_show(OPEN, ((rand.call() as int) & OPEN_MASK) | 1)
	_hold -= 1
	return shape


## An attack shout of voice id `code` (0x2000 on) starts: the character's shout face for its frames.
func shout(code: int) -> void:
	var index := code - SHOUT_FIRST
	if index < 0 or index >= _eyes.shout_frames.size():
		return
	_show(_eyes.shout, _eyes.shout_frames[index])


## FUN_80193EA4: the hold counter, and the shape when the costume has it.
func _show(new_shape: int, frames: int) -> void:
	_hold = frames
	if new_shape != CharacterModel.ArcadeEyes.NO_SHAPE and new_shape != shape:
		shape = new_shape


func _random() -> int:
	return _rng.randi()
