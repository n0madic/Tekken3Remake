extends TestSuite
## ArcadeFace against the arcade's FUN_80193F90 / FUN_80193EA4 / FUN_801A1C74, run in the CPU
## harness by tools/research/verify_arcade_eyes.py: the shapes it printed for the costume slots below
## (their roles from the arcade's tables, the same inputs and random numbers), as (frame, shape)
## where the shown shape changes.

const FRAMES := 600
const SHOUT_AT := {20: 0x2005, 150: 0x2000, 300: 0x2008, 400: 0x2002, 520: 0x2006}
const HELD_SPANS := [[100, 110], [200, 215]]
const DOWN_SPANS := [[140, 170], [205, 220], [450, 470]]
const SLOT_0 := [[0, 2], [3, 0], [20, 3], [100, 1], [111, 0], [140, 2], [171, 0], [200, 1], [215, 2], [221, 0],
		[329, 2], [332, 0], [400, 3], [420, 0], [450, 2], [471, 0], [520, 3], [570, 0]]
const SLOT_12 := [[0, 2], [3, 0], [20, 5], [40, 0], [79, 2], [82, 0], [100, 1], [111, 0], [140, 2], [171, 0],
		[200, 1], [215, 2], [221, 0], [300, 5], [380, 0], [400, 5], [420, 0], [450, 2], [471, 0], [520, 5], [550, 0]]
const SLOT_10 := [[0, 4], [3, 0], [26, 4], [29, 0], [68, 4], [71, 0], [100, 1], [111, 0], [140, 2], [171, 0],
		[200, 1], [215, 2], [221, 0], [320, 4], [323, 0], [450, 2], [471, 0]]

var _random := 12345


## The harness's `rand` stand-in (verify_arcade_eyes.py rand_sequence).
func _next() -> int:
	_random = (_random * 1103515245 + 12345) & 0x7FFFFFFF
	return (_random >> 8) & 0x7FFF


func _eyes(blink: int, held: int, down: int, shout: int, frames: Array) -> CharacterModel.ArcadeEyes:
	var eyes := CharacterModel.ArcadeEyes.new()
	eyes.blink = blink
	eyes.held = held
	eyes.down = down
	eyes.shout = shout
	eyes.shout_frames = PackedInt32Array(frames)
	return eyes


func _in(spans: Array, frame: int) -> bool:
	for span: Array in spans:
		if frame >= (span[0] as int) and frame < (span[1] as int):
			return true
	return false


## The (frame, shape) pairs where the shape shown changes over the verifier's schedule.
func _run(eyes: CharacterModel.ArcadeEyes) -> Array:
	_random = 12345
	var face := ArcadeFace.new(eyes)
	face.rand = _next
	var changes := []
	var last := -1
	for n in FRAMES:
		if SHOUT_AT.has(n):
			face.shout(SHOUT_AT[n] as int)
		var shape := face.step(_in(HELD_SPANS, n), _in(DOWN_SPANS, n))
		if shape != last:
			changes.append([n, shape])
			last = shape
	return changes


func test_matches_the_arcade_for_a_shouting_costume() -> void:
	expect_equal(_run(_eyes(2, 1, 2, 3, [35, 90, 20, 40, 15, 120, 50, 60, 0])), SLOT_0)


func test_matches_the_arcade_for_the_fifth_shape() -> void:
	expect_equal(_run(_eyes(2, 1, 2, 5, [20, 20, 20, 20, 20, 20, 30, 40, 80])), SLOT_12)


func test_matches_the_arcade_for_a_costume_that_does_not_shout() -> void:
	expect_equal(_run(_eyes(4, 1, 2, 0, [])), SLOT_10)


func test_a_missing_shape_keeps_the_face() -> void:
	var face := ArcadeFace.new(_eyes(CharacterModel.ArcadeEyes.NO_SHAPE, 1, 2, 3, [10]))
	face.rand = _next
	for n in 30:
		expect_equal(face.step(false, false), ArcadeFace.OPEN, "the blink shape is missing: frame %d" % n)
	face.shout(0x2000)
	expect_equal(face.step(false, false), 3, "a shout shows its face")


## Two faces of one costume (a mirror match) or of two fights do not blink alike: every face made
## with `next_seed` draws its open times from a sequence of its own.
func test_faces_do_not_blink_alike() -> void:
	var first := ArcadeFace.new(_eyes(2, 1, 2, 3, [10]), ArcadeFace.next_seed())
	var second := ArcadeFace.new(_eyes(2, 1, 2, 3, [10]), ArcadeFace.next_seed())
	var draws: Array[Array] = [[], []]
	for n in 8:
		draws[0].append(first.rand.call())
		draws[1].append(second.rand.call())
	expect_equal(draws[0] == draws[1], false, "two faces, two sequences")
	var again := ArcadeFace.new(_eyes(2, 1, 2, 3, [10]), 0)
	var same := ArcadeFace.new(_eyes(2, 1, 2, 3, [10]), 0)
	expect_equal(again.rand.call(), same.rand.call(), "the same seed gives the same draws (screenshots repeat)")


func test_converted_model_loads_its_faces() -> void:
	var dir := "res://imported/characters/costume_00"
	if not require(dir + "/model.json", "convert with --arcade first"):
		return
	var model := CharacterModel.load_from(dir)
	if model.arcade_eyes == null:
		skip("converted before the arcade's eye shapes")
		return
	var eyes := model.arcade_eyes
	for shape: int in [eyes.blink, eyes.held, eyes.down, eyes.shout]:
		if shape > CharacterModel.OPEN_SHAPE:
			expect(model.eye_textures.has(shape), "an atlas for shape %d" % shape)
	expect_equal(eyes.shout_frames.size(), 9, "a shouting character has a frame count per voice")
