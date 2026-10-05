class_name FighterState
extends RefCounted
## The simulation's record of one fighter (fighter.md). Field names are fighter.md's in
## snake_case; the comment gives the record offset. Values keep the widths of the original
## fields: code that stores into an s16 or u8 field wraps the value (Fx.s16, & 0xFF) where the
## game's arithmetic can leave the range. Move rows are MoveRow references (null for none).
##
## A fighter record persists for the whole match: round starts reset only what the game
## resets (FUN_8002BFCC), so everything else carries over as in the original.

const RECORDS := 0x800A96F0      ## the fighter records in the game's RAM
const RECORD_SIZE := 0x188C
## The properties copy_from leaves out: the skeleton (the copy is never animated or drawn) and the
## views of other fields (`move` would set root_move to the pose move, `anchor` is pos_x … pos_z).
const NOT_COPIED: Array[String] = ["body", "move", "anchor"]


## A fighter record's address in the game (the pointers the game keeps in its globals).
static func address(fighter_index: int) -> int:
	return RECORDS + RECORD_SIZE * fighter_index


## The fighter index of a record address (the inverse of `address`).
static func index_at(record_address: int) -> int:
	return (record_address - RECORDS) / RECORD_SIZE


# ---- identity (+0x12 … +0x23)
var player_index := 0           ## +0x12 0/1: VRAM and pad slot
var costume_key := 0            ## +0x14 charId · 4 + costume
var bank_type := 0              ## +0x16 motion bank type (character record +9)
var char_id := 0                ## +0x18
var voice_set := 0              ## +0x1A character record +8
var costume_slot := 0           ## +0x1C
## The costume's move list (FighterCopyMoveText: ARC member 4 at 0x800A39D0 + 0x232·player; a
## count, then name / command strings).
var move_text := PackedByteArray()
var index := 0                  ## +0x1E fighter index
var cur_opp_index := 1          ## +0x1F
var opp_index := 1              ## +0x20 default opponent
var throw_partner := 0          ## +0x21
var last_attacker := 0          ## +0x22
var last_hit_target := 0        ## +0x23

# ---- placement and angles
var pos_x := 0                  ## +0x00 anchor of the running move
var pos_y := 0                  ## +0x04
var pos_z := 0                  ## +0x08
var tilt_x := 0                 ## +0x0C
var facing := 0                 ## +0x0E
var tilt_z := 0                 ## +0x10
var root_dx := 0                ## +0x24 root displacement of the animation
var root_dy := 0                ## +0x26
var root_dz := 0                ## +0x28
var target_dir := 0             ## +0x2A (u16 angle)
var heading := 0                ## +0x2C
var heading_delta := 0          ## +0x2E (u16)
var rel_angle := 0              ## +0x30 (u16 folded)
var facing_quadrant := 0        ## +0x32
var aim_dir := 0                ## +0x34 (u16)
var track_accum := 0            ## +0x36
var opp_to_self_dir := 0        ## +0x38 (u16)
var opp_heading := 0            ## +0x3A (u16)
var opp_heading_delta := 0      ## +0x3C (u16)
var opp_rel_angle := 0          ## +0x3E (u16)
var opp_quadrant := 0           ## +0x40
var opp_aim_dir := 0            ## +0x42 (u16)

# ---- match
var round_wins := 0             ## +0x44
var round_won := 0              ## +0x46
var win_pose := 0               ## +0x48

# ---- running move
var root_move: MoveRow          ## +0x4C
var root_frame := 0             ## +0x50
var pose_move: MoveRow          ## +0x54
var pose_frame := 0             ## +0x58
var event_frame := 0            ## +0x5A (s16): the pose frame when the last frame's events ran
var move_frame := 0             ## +0x5C
var damage := 0                 ## +0x5E
var state := 0                  ## +0x60 (u32)
var attack := 0                 ## +0x64 (u16)
var guard := 0                  ## +0x66 (u16)
var attack_hi := 0              ## +0x68
var state_class := 0            ## +0x69
var hold_frames := 0            ## +0x6A
var branch_window := 0          ## +0x6C
var frame_step := 0             ## +0x6E
var sound_script := -1          ## +0x70: running sound script id, −1 none
var sound_script_last := 0      ## +0x72: the last script started by the move's sound list
var throw_state := 0            ## +0x74
var hit_freeze := 0             ## +0x76
var slide_step_x := 0           ## +0x78
var slide_step_z := 0           ## +0x7C
var react_chain := 0            ## +0x80
var slide_state := 0            ## +0x82
var hit_done := PackedInt32Array([0, 0, 0, 0])   ## +0x83 … +0x86 (+0x86 also set at a throw start)
var was_hit_this_move := 0      ## +0x87
var contact_this_move := 0      ## +0x88
var guarded_prev := 0           ## +0x89
var in_reaction := 0            ## +0x8A
var branch_kind := 0            ## +0x8B
var cond_flag_used := 0         ## +0x8C
var launch_armed := 0           ## +0x8E
var air_kind := 0               ## +0x90
var ballistic := 0              ## +0x92
var juggle_count := 0           ## +0x94
var ground_offset := 0          ## +0x96
var air_speed := 0              ## +0x98
var air_vel_x := 0              ## +0x9A
var air_vel_y := 0              ## +0x9C
var air_vel_z := 0              ## +0x9E
var cur_slot := 0               ## +0xA0
var cur_transition := 0         ## +0xA2
var slide_target_x := 0         ## +0xA4
var slide_target_z := 0         ## +0xA8
var opp_start_x := 0            ## +0xAC
var opp_start_z := 0            ## +0xB0
var attack_seg_count := 0       ## +0xB4
var crouch_move := 0            ## +0xB5
var step_kind := 0              ## +0xB6
var attack_class := 0           ## +0xB7
var air_phase := 0              ## +0xB8
var track_mode := 0             ## +0xB9
var move_flag_ba := 0           ## +0xBA
var move_flag_bb := 0           ## +0xBB
var skip_step_physics := 0      ## +0xBC
var attack_pending := 0         ## +0xBD
var anchor_dirty := 0           ## +0xBE
var slide_to_point := 0         ## +0xBF
var reset_flag_c0 := 0          ## +0xC0
var apply_end_turn := 0         ## +0xC1
var invulnerable := 0           ## +0xC2
var active := 0                 ## +0xC3
var in_throw := 0               ## +0xC4
var is_cpu := 0                 ## +0xC5
var side_flag := 0              ## +0xC6
var fixed_facing := 0           ## +0xC7
var fixed_facing_side := 0      ## +0xC8
var no_look_at := 0             ## +0xC9
var human_guard := 0            ## +0xCA
var last_extra_damage := 0      ## +0xCC
var got_hit := 0                ## +0xCE
var guarded := 0                ## +0xCF
var hit_clean := 0              ## +0xD0
var contact := 0                ## +0xD1
var whiffed := 0                ## +0xD2
var counter_hit := 0            ## +0xD3
var close_hit := 0              ## +0xD4
var body_contact := 0           ## +0xD5
var body_contact_with := PackedInt32Array([0, 0, 0])   ## +0xD6
var no_body_push := 0           ## +0xD9
var move_changed := 0           ## +0xDA
var in_air := 0                 ## +0xDB
var landed_a := 0               ## +0xDC
var landed_b := 0               ## +0xDD
var ko := 0                     ## +0xDE
var about_to_hit := 0           ## +0xDF
var tap_lp := 0                 ## +0xE0
var tap_rp := 0                 ## +0xE1
var tap_both := 0               ## +0xE2
var active_segs := 0            ## +0xE3
var extra_kind := 0             ## +0xE4
var blend_active := 0           ## +0xE5
var forced_hit := 0             ## +0xE6
var forced_hit_in := 0          ## +0xE7
var last_damage := 0            ## +0xE8
var damage_override := 0        ## +0xEA
var extra_damage := 0           ## +0xEC
var hit_freeze_in := 0          ## +0xEE
var dist_adj := 0               ## +0xF4 (u32)
var dist := 0                   ## +0xF8 (u32)
var dir_x := 0                  ## +0xFC: x offset to the opponent (PairwiseDistances)
var dir_z := 0                  ## +0x100
var hit_cooldown := 0           ## +0x104
var push_frames := 0            ## +0x106
var push_speed := 0             ## +0x108
var push_table_frames := 0      ## +0x10A
var push_dir := 0               ## +0x10C
var push_table := PackedInt32Array()   ## +0x110: the push values still to come
var push_table_pos := 0
var turn_frames := 0            ## +0x114
var turn_step := 0              ## +0x116
var recover_mash := 0           ## +0x118
var recover_frames := 0         ## +0x11A
var attack_alert := 0           ## +0x11C
var sound_script_pos := 0       ## +0x11E: the running script's next entry
var sound_script_frame := 0     ## +0x120: the running script's frame counter
var power_timer := 0            ## +0x122
var push_repeat := 0            ## +0x124
var push_repeat_timer := 0      ## +0x126
var step_cooldown := 0          ## +0x128
var placed_x := 0               ## +0x12C
var placed_z := 0               ## +0x130
var prev_pose_frame := 0        ## +0x134
var prev_slot := 0              ## +0x136
var prev_move_unk10 := 0        ## +0x138
var push_repeat_trans := 0      ## +0x13A
var hit_slots: Array[HitSlot] = [HitSlot.new(), HitSlot.new()]   ## +0x13C
var best_hit_slot := 0          ## +0x194: index into hit_slots
var entry_frame := 0            ## +0x198
var transition := 0             ## +0x19A
var trans_bit7 := 0             ## +0x19C
var trans_bit6 := 0             ## +0x19E
var move_slot := 0              ## +0x1A0
var move_row: MoveRow           ## +0x1A4 pending move
var reaction := PackedInt32Array()   ## +0x1A8 the reaction record (21 s16), or a throw-victim entry
var reaction_throw_slot := -1   ## +0x1A8 for 0x1xxx reactions: the throw victim's move slot

# ---- shapes, velocities, health
var attack_segs: Array[PackedInt32Array] = []    ## +0x1AC 4 × (start xyz, end xyz)
var hurt_zones: Array[PackedInt32Array] = []     ## +0x20C 14 × (x, y, z, radius, radius²)
var body_points: Array[PackedInt32Array] = []    ## +0x324 8 × (x, y, z, radius)
var prev_hurt_zone := PackedInt32Array([0, 0, 0])   ## +0x3A4
var prev_root_x := 0            ## +0x3B8
var prev_root_y := 0            ## +0x3BC
var prev_root_z := 0            ## +0x3C0
var vel_x := 0                  ## +0x3C4
var vel_y := 0                  ## +0x3C8
var vel_z := 0                  ## +0x3CC
var atk_dir_x := 0              ## +0x3D0
var atk_dir_y := 0              ## +0x3D4
var atk_dir_z := 0              ## +0x3D8
var hit_dir_x := 0              ## +0x3DC
var hit_dir_y := 0              ## +0x3E0
var hit_dir_z := 0              ## +0x3E4
var body_push_x := 0            ## +0x3E8
var body_push_y := 0            ## +0x3EC
var body_push_z := 0            ## +0x3F0
var health := 0                 ## +0x3F4 (16.16)
var health_max := 0             ## +0x3F8
var carried_health := 0         ## +0x3FC
var health_left := 0            ## +0x400 (s16): health in 1/4096 of the maximum at the round result (FUN_8003E6D0)

# ---- input (+0x402 … +0x4E8)
var in_dir := 5                 ## +0x402
var in_pressed := 0             ## +0x404
var in_held := 0                ## +0x406
var script_input := 0           ## +0x408
var in_hist_index := 0          ## +0x40C
var cmd_count := -1             ## +0x410
var cmd_read := -1              ## +0x414
var cmd_merge_timer := 0        ## +0x418
var in_history := PackedInt32Array()      ## +0x41C 60 × (pressed << 4 | direction)
var cmd_buffer := PackedInt32Array()      ## +0x458 10 entries
var in_pressed_hist := PackedInt32Array() ## +0x462 60 raw pressed words
var press_count := PackedInt32Array([0, 0, 0, 0])   ## +0x4DC

# ---- model and pose
var bank: MotionBank            ## the player's motion bank (g_fighterDivmot 0x800AE0E8)
var body: FighterBody           ## joints, local matrices and the model (+0x8B0 …)
var scale_base := 0             ## +0x4EC
var scale := 0                  ## +0x4EE
var root_x := 0                 ## +0xF68
var root_y := 0                 ## +0xF6C
var root_z := 0                 ## +0xF70
var screen_x := 0               ## +0x1278
var hands := FighterHands.new() ## +0x127C … +0x1298
var air_free := 0               ## +0x128A
var ogre_freeze := 0            ## +0x12D0
var ai_slot := -1               ## +0x1886
var ai_target := -1             ## +0x1887
var keep_light := 0             ## +0x1888

# ---- motion blending (+0x1810 …)
var prev_root_dx := 0           ## +0x1810
var root_dy_blended := 0        ## +0x1812
var blend_mode := 0             ## +0x181C
var blend_mode_b := 0           ## +0x1820: cleared with the blend mode (FUN_8003C4AC)
var last_pose_move: MoveRow     ## +0x1824
var last_pose_frame := 0        ## +0x182C
var blend_root_delta := PackedInt32Array([0, 0, 0])   ## +0x1868
var blend_weight := 0           ## +0x186E
var blend_frames := 0           ## +0x1870
var blend_counter := 0          ## +0x1878
var blend_src_move: MoveRow     ## +0x187C
var blend_dst_move: MoveRow     ## +0x1880
var blend_src_frame := 0        ## +0x1884
var blend_dst_frame := 0        ## +0x1885

## Scripted scenes (the attract demonstration): the running move as one row for root and pose.
var move: MoveRow:
	get:
		return pose_move
	set(value):
		pose_move = value
		root_move = value
## Enbu's anchor as one vector.
var anchor: PackedInt32Array:
	get:
		return PackedInt32Array([pos_x, pos_y, pos_z])
	set(value):
		pos_x = value[0]
		pos_y = value[1]
		pos_z = value[2]


func _init() -> void:
	for i in 4:
		attack_segs.append(PackedInt32Array([0, 0, 0, 0, 0, 0]))
	for i in 14:
		hurt_zones.append(PackedInt32Array([0, 0, 0, 0, 0]))
	for i in 8:
		body_points.append(PackedInt32Array([0, 0, 0, 0]))
	in_history.resize(60)
	in_pressed_hist.resize(60)
	cmd_buffer.resize(10)


## FUN_80036440: selects a costume slot (and the costume key and character it belongs to).
func set_costume(slot: int, tables: FighterTables) -> void:
	costume_key = tables.key_of_slot(slot)
	costume_slot = tables.costume_keys[costume_key]
	char_id = costume_key >> 2


## The whole record copied from `other` (Tekken Ball copies the hitter's record into the third
## record, the ball's attacker). Move rows, banks and texts are shared data; everything the
## record owns is copied.
func copy_from(other: FighterState) -> void:
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name: String = p["name"]
		if name in NOT_COPIED:
			continue
		set(name, _copied(other.get(name)))


static func _copied(v: Variant) -> Variant:
	match typeof(v):
		TYPE_PACKED_INT32_ARRAY:
			return (v as PackedInt32Array).duplicate()
		TYPE_PACKED_BYTE_ARRAY:
			return (v as PackedByteArray).duplicate()
		TYPE_PACKED_INT64_ARRAY:
			return (v as PackedInt64Array).duplicate()
		TYPE_ARRAY:
			var a: Array = v
			var out := a.duplicate()
			for i in out.size():
				out[i] = _copied(a[i])
			return out
		TYPE_OBJECT:
			if v is HitSlot or v is FighterHands:
				var src := v as RefCounted
				var copy := (src.get_script() as GDScript).new() as RefCounted
				for p in src.get_property_list():
					var name: String = p["name"]
					if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
						copy.set(name, _copied(src.get(name)))
				return copy
	return v
