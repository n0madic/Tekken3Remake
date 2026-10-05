class_name MoveRow
extends RefCounted
## One 56-byte move row of a motion bank, decoded and linked as `DivmotLinkBank` (0x8002D068)
## links it: the animation (own or common bank), its length byte, the damage with the throw
## damage of its `0x0B` events, and the event, sound and branch lists and attack record of the
## row's own bank. Field meanings: moves.md#move-row-fields-used-at-run-time.

const COMMON_FLAG := 0x40000000
const NO_LIST := 0xFFFFFFFF
const THROW_DAMAGE_EVENT := 0x0B
const DAMAGE_MASK := 0x3FFF

var bank: MotionBank              ## the bank the row belongs to
var index := 0                    ## row number in its bank
var anim_bank: MotionBank         ## the bank of the animation stream (own or common)
var anim := 0                     ## stream offset in section 6 of `anim_bank`
var state := 0                    ## +0x04
var attack := 0                   ## +0x08
var ai_hints := 0                 ## +0x0A
var attack_word := 0              ## +0x08 as a u32: the attack, the AI hints (bits 16–23) and byte +0x0B
var branches := -1                ## +0x0C: first branch row in `bank.branches`
var stance_slot := 0              ## +0x10
var end_turn := 0                 ## +0x12 (s16)
var damage_word := 0              ## +0x14: damage (bits 0–13, throw damage added) and class (14–15)
var step := 0                     ## +0x16 (s16)
var length := 0                   ## +0x18: the stream's first byte
var air_first := 0                ## +0x19
var air_last := 0                 ## +0x1A
var hold_frame := 0               ## +0x1B
var sounds := -1                  ## +0x1C: first word in `bank.sounds`, −1 none
var events := -1                  ## +0x20: first word in `bank.events`, −1 none
var flags := 0                    ## +0x24
var attack_record := -1           ## +0x28: byte offset in `bank.attacks`, −1 none or built in
var builtin_attack := -1          ## +0x28: index of a built-in descriptor (fight tables), −1 none
var hit_freeze := 0               ## +0x2C
var active_first := 0             ## +0x2D
var active_last := 0              ## +0x2E
var body_profile := 0             ## +0x30
var reaction := 0                 ## +0x32
var close_reaction := 0           ## +0x34


## Decodes row `row_index` of `owner` (words as converted) and links it; `common` is the common
## bank (the owner itself for the common bank), `builtins` the built-in descriptor ids.
static func link(owner: MotionBank, row_index: int, common: MotionBank, builtins: PackedInt32Array) -> MoveRow:
	var w := owner.moves[row_index]
	var r := MoveRow.new()
	r.bank = owner
	r.index = row_index
	var anim_word := w[0]
	if anim_word >= COMMON_FLAG:
		r.anim_bank = common
		r.anim = anim_word - COMMON_FLAG
	else:
		r.anim_bank = owner
		r.anim = anim_word
	r.length = r.anim_bank.anim_first_byte(r.anim)
	r.state = w[1]
	r.attack = w[2] & 0xFFFF
	r.attack_word = w[2] & 0xFFFFFFFF
	r.ai_hints = (w[2] >> 16) & 0xFF
	r.branches = w[3]
	r.stance_slot = w[4] & 0xFFFF
	r.end_turn = Fx.s16(w[4] >> 16)
	r.step = Fx.s16(w[5] >> 16)
	r.air_first = (w[6] >> 8) & 0xFF
	r.air_last = (w[6] >> 16) & 0xFF
	r.hold_frame = (w[6] >> 24) & 0xFF
	r.sounds = -1 if w[7] == NO_LIST else w[7]
	r.events = -1 if w[8] == NO_LIST else 2 * w[8]
	r.flags = w[9]
	var descriptor := Fx.w32(w[10])
	if descriptor >= 0:
		r.builtin_attack = builtins.find(descriptor)
		if r.builtin_attack < 0:
			r.attack_record = descriptor - 4
	r.hit_freeze = w[11] & 0xFF
	r.active_first = (w[11] >> 8) & 0xFF
	r.active_last = (w[11] >> 16) & 0xFF
	r.body_profile = w[12] & 0xFFFF
	r.reaction = (w[12] >> 16) & 0xFFFF
	r.close_reaction = w[13] & 0xFFFF
	# MoveTotalDamage: the u16 damage word plus the arguments of the 0x0Bxx events.
	var damage := w[5] & 0xFFFF
	if r.events >= 0:
		var i := r.events
		while owner.events[i] != 0:
			var command := owner.events[i + 1]
			if command >> 8 == THROW_DAMAGE_EVENT:
				damage += command & 0xFF
			i += 2
	r.damage_word = damage & 0xFFFF
	return r


func damage() -> int:
	return damage_word & DAMAGE_MASK


func attack_class() -> int:
	return damage_word >> 14


func _to_string() -> String:
	return "%s:%d" % [bank.name, index]
