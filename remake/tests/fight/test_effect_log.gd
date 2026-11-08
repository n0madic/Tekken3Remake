extends TestSuite
## The replay's effect logs: a frame plays what it logged, the limit holds per cycle of the frame ring,
## a kept copy ends at the frame being written; the arcade keeps flipbooks and dust apart.

const ENTRIES := 4
const LIMIT := 6

var _no_direction := PackedInt32Array([0, 0, 0])


func _log() -> EffectLog:
	var effects := EffectLog.new(ENTRIES, LIMIT)
	effects.reset()
	return effects


func _add(effects: EffectLog, index: int) -> void:
	effects.add(0, index, PackedInt32Array([index, 0, 0]), _no_direction, EffectLog.FLIPBOOK)


func _indices(entries: Array[EffectLog.Entry]) -> Array[int]:
	var out: Array[int] = []
	for e: EffectLog.Entry in entries:
		out.append(e.index)
	return out


func test_a_frame_plays_what_it_logged() -> void:
	var effects := _log()
	_add(effects, 1)
	effects.advance()
	effects.advance()
	_add(effects, 2)
	_add(effects, 3)
	effects.advance()
	effects.rewind(3)
	expect_equal(_indices(effects.take()), [1] as Array[int], "the first frame")
	expect_equal(_indices(effects.take()), [] as Array[int], "a frame without effects")
	expect_equal(_indices(effects.take()), [2, 3] as Array[int], "the third frame")


func test_the_entries_are_a_ring() -> void:
	var effects := _log()
	for i in ENTRIES - 1:
		_add(effects, i)
	effects.advance()
	_add(effects, 10)
	_add(effects, 11)
	effects.advance()
	effects.rewind(1)
	expect_equal(_indices(effects.take()), [10, 11] as Array[int], "wraps past the last entry")


func test_the_limit_holds_until_the_frames_wrap() -> void:
	var effects := _log()
	for i in LIMIT:
		_add(effects, i)
	expect_equal(effects.slots[0] >> 16, LIMIT - 1, "the entry that reaches the limit is not logged")
	for i in EffectLog.FRAMES:
		effects.advance()
	_add(effects, 7)
	expect_equal(effects.slots[0] >> 16, 1, "the wrap of the frames starts a new cycle")


func test_a_stopped_log_keeps_its_place() -> void:
	var effects := _log()
	_add(effects, 1)
	effects.on = 0
	_add(effects, 2)
	effects.advance()
	expect_equal(effects.frame, 0, "no frame slot follows")
	expect_equal(effects.slots[0] >> 16, 1, "no entry either")


func test_a_kept_copy_ends_at_the_frame_being_written() -> void:
	var effects := _log()
	effects.advance()
	_add(effects, 5)
	var kept := effects.kept()
	expect_equal(kept.slots[EffectLog.FRAMES - 1] >> 16, 1, "the last slot is the one being written")
	_add(effects, 6)
	expect_equal(kept.entries[0].index, 5, "the copy has entries of its own")
	var other := _log()
	other.restore(kept, EffectLog.FRAMES - 1)
	expect_equal(_indices(other.take()), [5] as Array[int], "played from the slot given")
	expect_equal(other.read, 0, "then the ring wraps")


func test_the_arcade_logs_flipbooks_and_dust_apart() -> void:
	var replay := ArcadeReplay.new()
	replay.log_reset()
	replay.log_effect(0, 9, PackedInt32Array([9, 0, 0]), _no_direction, EffectLog.FLIPBOOK)
	replay.log_effect(0, 0, PackedInt32Array([8, 0, 0]), _no_direction, EffectLog.DUST)
	replay.log_advance()
	replay.log_rewind(1)
	var entries := replay.log_take()
	expect_equal(entries.size(), 2, "one of each")
	expect_equal(entries[0].mode, EffectLog.DUST, "the dust rings come first")
	expect_equal(entries[0].point[0], 8, "the dust's point")
	expect_equal(entries[1].index, 9, "then the flipbooks")
	expect_equal(replay.effect_log.entries.size(), ArcadeReplay.FLIPBOOK_ENTRIES, "the arcade's size")


func test_the_arcade_limits_each_log_on_its_own() -> void:
	var replay := ArcadeReplay.new()
	replay.log_reset()
	for i in ArcadeReplay.DUST_LIMIT:
		replay.log_effect(0, 0, _no_direction, _no_direction, EffectLog.DUST)
	expect_equal(replay.dust_log.cycle, ArcadeReplay.DUST_LIMIT, "the dust's count")
	expect_equal(replay.effect_log.cycle, 0, "the flipbooks' stays")


func test_a_kept_fights_logs_start_two_frames_after_its_poses() -> void:
	var replay := ArcadeReplay.new()
	var kept := replay.kept[3]
	kept.count = 99
	kept.flipbook_log = EffectLog.new(ArcadeReplay.FLIPBOOK_ENTRIES, ArcadeReplay.FLIPBOOK_LIMIT)
	kept.dust_log = EffectLog.new(ArcadeReplay.DUST_ENTRIES, ArcadeReplay.DUST_LIMIT)
	replay.restore_logs(3)
	expect_equal(replay.effect_log.read, EffectLog.FRAMES - 1 - 97, "FUN_801ADF88: the last slot less the frames")
	expect_equal(replay.dust_log.read, replay.effect_log.read, "FUN_801AE888: the same")
