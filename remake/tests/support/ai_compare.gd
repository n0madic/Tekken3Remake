class_name AiCompare
extends RefCounted
## Compares the AI records of a fight simulation with the game's (0x8009F6C0 + 0x330 · slot in a
## fight trace with CPU fighters, ai.md#entry-and-state): every modelled scalar field, the move
## rows the record points to, the difficulty words and band thresholds, and whether an input
## script is pending.

const RECORDS := 0x8009F6C0
const RECORD_SIZE := 0x330
const MULTI := 0x8009F6A4
## (offset, size (negative: signed), AiRecord property)
const FIELDS := [
	[0x00, -2, "slot"], [0x02, -2, "frame_count"], [0x04, 2, "pad"], [0x06, 2, "prev_pad"],
	[0x14, -4, "band"], [0x18, -4, "reach_band"], [0x1C, -4, "distance"], [0x20, -4, "prev_distance"],
	[0x24, -4, "distance_change"], [0x28, -2, "move_changed"], [0x2A, -2, "far_count"],
	[0x2C, -2, "move_frames"], [0x2E, -2, "angle"], [0x30, -4, "health_seen"],
	[0x34, -2, "pose_frame_seen"], [0x36, -2, "neutral_action"], [0x38, -2, "approach"],
	[0x3A, -2, "approach_kind"], [0x3C, -2, "crouching"], [0x3E, -2, "guarding"],
	[0x40, -2, "approach_hold"], [0x42, -2, "setup_cooldown"], [0x44, -2, "neutral_cooldown"],
	[0x46, -2, "air_cooldown"], [0x48, -2, "direction_hold"], [0x4A, -2, "crouch_timer"],
	[0x4C, -2, "crouch_attack_hold"], [0x4E, -2, "move_frame_seen"], [0x50, -2, "attacking"],
	[0x52, -2, "special_open"], [0x54, -2, "whiff_timer"], [0x64, 4, "situation"], [0x68, -2, "wait"],
	[0x6A, -2, "guard_holds"], [0x6C, -2, "guard_delay"], [0x6E, -2, "cancel_wait"],
	[0x70, -2, "candidate_count"], [0x72, -2, "marked_count"], [0x80, -4, "announced_frames"],
	[0x84, -4, "passed_frames"], [0x88, -2, "vs_stance"], [0x8A, -2, "move_block"],
	[0x8C, -2, "guard_suspend"], [0x8E, 1, "parried"], [0x8F, 1, "punish"], [0x90, 1, "throw_next"],
	[0x91, 1, "throw_chance"], [0x92, 1, "evade_reason"], [0x93, 1, "guard_memory"], [0x94, 1, "evasion"],
	[0x96, -2, "throw_steps"], [0x98, -2, "throw_list"], [0x9C, -2, "throw_press_frame"],
	[0xC0, -2, "strings_on"], [0xC2, -2, "strings_count"], [0xD4, -2, "no_strings"],
	[0xD8, -2, "planned_on"], [0xDA, -2, "planned_count"], [0x1A0, -2, "links_on"],
	[0x1A2, -2, "links_count"], [0x1CC, -2, "link_skip"], [0x1D0, -2, "link_last"],
	[0x1D2, -2, "attacks_in_row"], [0x1D4, -2, "attack_limit"], [0x1FC, 2, "history_at"],
	[0x1FE, -2, "reload_timer"], [0x200, 1, "opp_breath"], [0x201, 1, "opp_gon_special"],
	[0x202, -2, "adaptive"], [0x204, -2, "opp_move_changed"], [0x208, -2, "opp_down"],
	[0x20A, -2, "opp_until"], [0x20C, -2, "opp_coming"], [0x20E, -2, "opp_unblockable"],
	[0x210, -2, "opp_charging"], [0x212, -2, "coming_seen"], [0x214, -2, "opp_grabs"],
	[0x216, -2, "opp_string"], [0x21A, 2, "opp_high"], [0x21E, 2, "input_mode"],
	[0x220, 4, "own_word"], [0x224, 4, "own_state"], [0x228, 4, "own_attack"], [0x22C, 4, "opp_word"],
	[0x230, 4, "opp_state"], [0x234, 4, "opp_attack"],
]
## (offset, AiRecord property) of the move-row pointers.
const ROWS := [[0x58, "collected_move"], [0x5C, "pressed_move"], [0x60, "last_attack"], [0xA0, "throw_move"]]

var trace: FightTrace


func _init(fight_trace: FightTrace) -> void:
	trace = fight_trace


static func applies(fight_trace: FightTrace) -> bool:
	return fight_trace.has_ram(RECORDS, 4)


## The differences of the AI record of slot `slot` at `frame` as "name: actual ≠ expected".
func differences(ai: CpuOpponent, slot: int, frame: int, banks: Array[MotionBank]) -> PackedStringArray:
	var out := PackedStringArray()
	var rec := ai.records[slot]
	var base := RECORDS + RECORD_SIZE * slot
	for d: Array in FIELDS:
		var offset: int = d[0]
		var size: int = d[1]
		var prop: String = d[2]
		var expected := trace.ram(frame, base + offset, size)
		var actual := RecordTrace.width(rec.get(prop) as int, size)
		if actual != expected:
			out.append("AI %d %s: %d ≠ %d" % [slot, prop, actual, expected])
	var pending := trace.ram(frame, base + 0x08, 4) != 0
	if rec.script_pending() != pending:
		out.append("AI %d script pending: %s ≠ %s" % [slot, rec.script_pending(), pending])
	for k in AiRecord.PARAM_WORDS:
		var expected := trace.ram(frame, base + 0x238 + 2 * k, -2)
		if rec.params[k] != expected:
			out.append("AI %d word %d: %d ≠ %d" % [slot, k, rec.params[k], expected])
	for k in 6:
		var own := trace.ram(frame, base + 0x314 + 2 * k, -2)
		var opp := trace.ram(frame, base + 0x320 + 2 * k, -2)
		if rec.own_bands[k] != own or rec.opp_bands[k] != opp:
			out.append("AI %d band threshold %d: %d/%d ≠ %d/%d" % [slot, k, rec.own_bands[k], rec.opp_bands[k], own, opp])
	for r: Array in ROWS:
		var offset: int = r[0]
		var prop: String = r[1]
		_row(out, rec.get(prop) as MoveRow, trace.ram(frame, base + offset, 4), frame, banks, "AI %d %s" % [slot, prop])
	for k in AiRecord.HISTORY:
		_row(out, rec.history[k], trace.ram(frame, base + 0x1DC + 4 * k, 4), frame, banks, "AI %d history %d" % [slot, k])
	if slot == 0 and ai.multi != trace.ram(frame, MULTI, 4):
		out.append("AI multi: %d ≠ %d" % [ai.multi, trace.ram(frame, MULTI, 4)])
	return out


func _row(out: PackedStringArray, row: MoveRow, pointer: int, frame: int, banks: Array[MotionBank], name: String) -> void:
	var actual := FighterCompare._row_key(row, banks)
	var expected := trace.row_of(frame, pointer)
	if actual.x == FighterCompare.STALE_BANK:
		if not pointer in trace.row_addresses(frame, row.bank.type_code, row.index):
			out.append("%s: stale row %d of %s ≠ 0x%08X" % [name, row.index, row.bank.name, pointer])
		return
	if actual != expected:
		out.append("%s: %s ≠ %s" % [name, actual, expected])

