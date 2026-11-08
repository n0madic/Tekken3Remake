extends TestSuite
## The rules the PlayStation's CPU and the arcade's share through `CpuMachinery`: the side step's choice
## from the heading, the hooks against Paul and as Hwoarang, the side steps against Ogre, a script's and
## a command's pad words and the approach reset. The CPU traces leave several edges of them open (a
## mutation of Hwoarang's window, of the heading ranges or of the sweep's side passes them), and an edge
## is where a rewrite would move.

const NO_SIDE := CpuMachinery.NO_SIDE
const NOTHING := CpuMachinery.HOOK_NOTHING
const PAD := 0x1234                     ## a build's pad word, as the hooks are given it


func _cpu() -> CpuOpponent:
	var fight := FightState.new(FightTables.new(), RuleSet.original())
	fight.tables.ai = AiTables.new()
	return CpuOpponent.new(fight, MoveSystem.new(fight))


## A generator state whose next draw has a low nibble of 0 (`nibble_zero`) or not.
func _draw_state(cpu: CpuMachinery, nibble_zero: bool) -> int:
	for s in range(1, 400):
		cpu.fight.rng.state = s
		if (cpu.fight.rng.next() & 0xF == 0) == nibble_zero:
			return s
	return 0


func test_the_heading_gives_the_side_by_half_turns() -> void:
	expect_equal(CpuMachinery.heading_side(0x100), NO_SIDE, "just before side 0")
	expect_equal(CpuMachinery.heading_side(0x101), 0, "side 0 starts at 0x101")
	expect_equal(CpuMachinery.heading_side(0x7FFF), 0, "and ends at 0x7FFF")
	expect_equal(CpuMachinery.heading_side(0x8000), NO_SIDE, "the half turn itself is ambiguous")
	expect_equal(CpuMachinery.heading_side(0x8001), 1, "side 1 starts just past it")
	expect_equal(CpuMachinery.heading_side(0xFEFE), 1, "and ends at 0xFEFE")
	expect_equal(CpuMachinery.heading_side(0xFEFF), NO_SIDE, "nearly straight ahead is ambiguous too")
	expect_equal(CpuMachinery.heading_side(0), NO_SIDE, "straight ahead")
	expect_equal(CpuMachinery.heading_side(0x10000 + 0x101), 0, "only 16 bits count")


func test_a_side_is_mirrored_when_the_opponent_stands_to_the_left() -> void:
	expect_equal(CpuMachinery.side_toward(0, -5, 5), 1, "to the left: mirrored")
	expect_equal(CpuMachinery.side_toward(1, -5, 5), 0)
	expect_equal(CpuMachinery.side_toward(0, 5, -5), 0, "to the right: as it is")
	expect_equal(CpuMachinery.side_toward(0, 7, 7), 0, "level: as it is")
	expect_equal(CpuMachinery.side_toward(1, 0xFFFB, 5), 0, "screen x is an s16: 0xFFFB is −5")


func test_a_side_step_told_to_pick_draws_only_when_the_heading_is_ambiguous() -> void:
	var cpu := _cpu()
	cpu.fight.rng.state = 77
	var before := cpu.fight.rng.state
	expect_equal(cpu.auto_side(0x200, 0, 0), 0, "a clear heading")
	expect_equal(cpu.fight.rng.state, before, "takes no draw")
	var draw := cpu.fight.rng.next()
	cpu.fight.rng.state = 77
	expect_equal(cpu.auto_side(0, 0, 0), (draw >> 4) & 1, "an ambiguous one takes bit 4 of a draw")
	expect(cpu.fight.rng.state != before, "and advances the generator")
	cpu.fight.rng.state = 77
	expect_equal(cpu.auto_side(0x200, -5, 5), 1, "a clear heading is mirrored by the screen order")


func test_the_hook_against_paul_backs_away_from_the_frame_on() -> void:
	var cpu := _cpu()
	var rec := CpuRecord.new()
	var opp := FighterState.new()
	opp.cur_slot = 0x2C7
	rec.reach_band = 2
	rec.wait = 7
	opp.pose_frame = CpuMachinery.PAUL_BACK_FRAME - 1
	expect_equal(cpu.vs_paul(rec, opp, 0x2C7, PAD), NOTHING, "before the frame: nothing")
	expect_equal(rec.wait, -1, "but the CPU attacks at once")
	rec.wait = 7
	opp.pose_frame = CpuMachinery.PAUL_BACK_FRAME
	expect_equal(cpu.vs_paul(rec, opp, 0x2C7, PAD), PAD, "from the frame: back")
	expect_equal(rec.wait, 7, "the wait is left alone")
	rec.reach_band = 3
	expect_equal(cpu.vs_paul(rec, opp, 0x2C7, PAD), NOTHING, "out of close reach: nothing")
	rec.reach_band = 2
	expect_equal(cpu.vs_paul(rec, opp, 0x2C8, PAD), NOTHING, "another slot: nothing")
	expect_equal(rec.wait, 7)


func test_hwoarangs_hook_leaves_the_window_alone_only_with_the_attack_close() -> void:
	var cpu := _cpu()
	var rec := CpuRecord.new()
	var own := FighterState.new()
	own.cur_slot = 0x827
	var forward := _draw_state(cpu, false)
	var stay := _draw_state(cpu, true)
	expect(forward != 0 and stay != 0, "both kinds of draw exist")
	for frame: int in [0xD, 0xF, 0x11]:
		own.pose_frame = frame
		rec.opp_until = 9
		cpu.fight.rng.state = forward
		expect_equal(cpu.as_hwoarang(rec, own, 0x827, PAD), NOTHING, "frame %x with the attack close: nothing" % frame)
		expect_equal(cpu.fight.rng.state, forward, "frame %x takes no draw" % frame)
	for frame: int in [0xC, 0x12]:
		own.pose_frame = frame
		cpu.fight.rng.state = forward
		expect_equal(cpu.as_hwoarang(rec, own, 0x827, PAD), PAD, "frame %x is out of the window: forward" % frame)
	own.pose_frame = 0xD
	rec.opp_until = 10
	cpu.fight.rng.state = forward
	expect_equal(cpu.as_hwoarang(rec, own, 0x827, PAD), PAD, "inside it with the attack 10 frames off: forward")
	cpu.fight.rng.state = stay
	expect_equal(cpu.as_hwoarang(rec, own, 0x827, PAD), NOTHING, "unless the draw's low nibble is 0")
	own.cur_slot = 0x828
	cpu.fight.rng.state = forward
	expect_equal(cpu.as_hwoarang(rec, own, 0x827, PAD), NOTHING, "another slot: nothing")
	expect_equal(cpu.fight.rng.state, forward, "and no draw")


func _ogre_fighters(state: int, heading: int, x: int, opp_x: int) -> Array[FighterState]:
	var own := FighterState.new()
	own.pose_move = MoveRow.new()
	own.pose_move.state = state
	own.heading_delta = heading
	own.screen_x = x
	var opp := FighterState.new()
	opp.screen_x = opp_x
	return [own, opp] as Array[FighterState]


func test_the_breath_side_needs_a_clear_heading_a_free_move_and_a_short_distance() -> void:
	var fs := _ogre_fighters(0, 0, 0, 0)
	var own := fs[0]
	var opp := fs[1]
	var near := CpuMachinery.OGRE_NEAR
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x200, near - 1), 0, "side 0 to the right of Ogre")
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x9000, near - 1), 1, "side 1")
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x200, near), NO_SIDE, "from 7,001 on: none")
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x8000, near - 1), NO_SIDE, "an ambiguous heading: none")
	own.pose_move.state = CpuMachinery.STATE_BIT22
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x200, near - 1), NO_SIDE, "a move with state bit 22: none")
	own.pose_move.state = 0
	opp.screen_x = -50
	expect_equal(CpuMachinery.ogre_breath_side(own, opp, 0x200, near - 1), 1, "mirrored with Ogre on the left")


func test_the_sweep_side_is_toward_the_opponent_within_a_quarter_turn_of_straight() -> void:
	var fs := _ogre_fighters(0, 0xE000, 10, 50)
	var own := fs[0]
	var opp := fs[1]
	var near := CpuMachinery.OGRE_NEAR
	expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near - 1), 1, "the opponent on the right: 1")
	opp.screen_x = -50
	expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near - 1), 0, "on the left: 0")
	opp.screen_x = 50
	for heading: int in [0xE000, 0x0, 0x2000]:
		own.heading_delta = heading
		expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near - 1), 1, "heading %x is within the quarter turn" % heading)
	for heading: int in [0xDFFF, 0x2001, 0x8000]:
		own.heading_delta = heading
		expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near - 1), NO_SIDE, "heading %x is not" % heading)
	own.heading_delta = 0
	expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near), NO_SIDE, "7,001 apart: none")
	own.pose_move.state = CpuMachinery.STATE_BIT22
	expect_equal(CpuMachinery.ogre_sweep_side(own, opp, near - 1), NO_SIDE, "state bit 22: none")


## The tables of a CPU's pads: numpad directions 0–9 (bit d − 1 of a mask, pad 0x40 << d), buttons by bit.
func _pad_tables(t: AiTables) -> void:
	t.numpad_pads = PackedInt32Array()
	t.direction_masks = PackedInt32Array([0])
	t.direction_pads = PackedInt32Array()
	for d in 10:
		t.numpad_pads.append(0x1000 << d)
		t.direction_pads.append(0x40 << d)
		if d > 0:
			t.direction_masks.append(1 << (d - 1))
	t.button_pads = PackedInt32Array([1, 2, 4, 8])


func test_a_command_is_the_highest_direction_it_reaches_with_its_buttons() -> void:
	var cpu := _cpu()
	_pad_tables(cpu.t)
	expect_equal(cpu.command_pad(0), cpu.t.direction_pads[0], "no direction bit: numpad 0")
	expect_equal(cpu.command_pad(1 << 5), cpu.t.direction_pads[1], "the first direction bit: numpad 1")
	expect_equal(cpu.command_pad((1 << 5) | (1 << 7)), cpu.t.direction_pads[3], "two bits: the higher numpad")
	expect_equal(cpu.command_pad((1 << 13)), cpu.t.direction_pads[9], "the last bit: numpad 9")
	expect_equal(cpu.command_pad((1 << 5) | 0b101), cpu.t.direction_pads[1] | 5, "buttons by bits 0–3")


func test_a_script_presses_its_first_step_and_keeps_the_rest_by_the_builds_buttons() -> void:
	var ps1 := _cpu()
	_pad_tables(ps1.t)
	var steps := PackedInt32Array([0x100 | 0x800 | 3, 0x200, 0x400 | 5])
	ps1.start_script(ps1.records[0], steps)
	expect_equal(ps1.records[0].pad, PadState.SQUARE | PadState.CIRCLE | ps1.t.numpad_pads[3], "the PlayStation's buttons")
	expect_equal(ps1.records[0].script_at, 1, "the rest is pending")
	expect_equal(ps1.pad_from_step(0x200 | 0x400), PadState.TRIANGLE | PadState.CROSS | ps1.t.numpad_pads[0])
	ps1.start_script(ps1.records[1], PackedInt32Array([0x100 | 2, 0x400]))
	expect_equal(ps1.records[1].script_at, 1, "two steps leave the second pending")
	ps1.start_script(ps1.records[1], PackedInt32Array([0x100 | 2]))
	expect_equal(ps1.records[1].script_at, -1, "one step leaves nothing pending")
	ps1.start_script(ps1.records[2], PackedInt32Array())
	expect_equal(ps1.records[2].pad, ps1.t.numpad_pads[0], "an empty script presses nothing")
	expect(not ps1.records[2].script_pending())
	var fight := FightState.new(FightTables.new(), RuleSet.original())
	fight.tables.ai = AiTables.new()
	var arcade := ArcadeCpu.new(fight, ArcadeMoveSystem.new(fight))
	_pad_tables(arcade.t)
	arcade.start_script(arcade.arcade_records[0], steps)
	expect_equal(arcade.arcade_records[0].pad, ArcadeCpu.LP | ArcadeCpu.RK | arcade.t.numpad_pads[3], "the arcade's buttons")
	expect_equal(arcade.pad_from_step(0x200 | 0x400), ArcadeCpu.RP | ArcadeCpu.LK | arcade.t.numpad_pads[0])


func test_the_approach_reset_restarts_all_four_timers() -> void:
	var rec := CpuRecord.new()
	rec.approach_hold = 5
	rec.approach_kind = 2
	rec.approach = 9
	rec.direction_hold = 3
	CpuMachinery.reset_approach(rec)
	expect_equal(rec.approach_hold, 0x28, "the hold")
	expect_equal(rec.approach_kind, 0, "the kind")
	expect_equal(rec.approach, 0, "the length")
	expect_equal(rec.direction_hold, -1, "the direction hold")
