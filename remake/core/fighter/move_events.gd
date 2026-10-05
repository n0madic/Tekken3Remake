class_name MoveEvents
## MoveEvents (0x80045B60, moves.md#frame-events): fires the running move's frame events whose
## frame the pose passed this frame (`eventFrame < frame ≤ poseFrame`).
##
## Throw damage and damage exchanges (11–13) only record `extra_kind`; hand commands (14–61)
## go to the fighter's hands; camera shakes (1–3), flipbooks, sparks, dust and vibration become
## SimEvents (the fight runs the SHAKE_REQUEST and FIGHTER_VIBRATE calls in place after both
## fighters' events).

const SHAKE_LAST := 3
const GROUND_IMPACT := 4
const EFFECT_OWN := 6
const EFFECT_OPPONENT := 7
const SPARK_FIRST := 8
const SPARK_INDEX := [0, 1, 3]         ## events 8–10 → system flipbook index
const EXTRA_FIRST := 11
const EXTRA_LAST := 13
const HAND_FIRST := 14
const HAND_LAST := 61
const HAND_RESET := 20                 ## both hands open
const HAND_COSTUME := 21               ## both hands to the costume's own shape
const VIBRATE_EFFECT := 1           ## FighterVibrate kinds
const VIBRATE_IMPACT := 2


static func run(f: FighterState, tables: FighterTables, out: SimEvents) -> void:
	f.extra_kind = 0
	var move := f.pose_move
	if f.active == 0 or move == null or move.events < 0:
		return
	var events := move.bank.events
	var i := move.events
	while events[i] != 0:
		var frame := events[i]
		var command := events[i + 1]
		i += 2
		if frame > f.pose_frame or frame <= f.event_frame:
			continue
		var hi := command >> 8
		var lo := command & 0xFF
		if hi >= EFFECT_OWN and hi < SPARK_FIRST + SPARK_INDEX.size():
			var point := _joint_point(f, lo)
			if hi == EFFECT_OWN:
				out.add_at(SimEvents.Kind.EFFECT, f.index, point, f.index, lo)
				out.add(SimEvents.Kind.FIGHTER_VIBRATE, f.index, VIBRATE_EFFECT)
			elif hi == EFFECT_OPPONENT:
				out.add_at(SimEvents.Kind.EFFECT, f.index, point, f.cur_opp_index, lo)
			else:
				var index: int = SPARK_INDEX[hi - SPARK_FIRST]
				out.add_at(SimEvents.Kind.SPARK, f.index, point, index, lo)
		elif hi >= HAND_FIRST and hi <= HAND_LAST:
			f.skip_step_physics = 1
			var cmd := hi - HAND_FIRST
			var hands := cmd >> 4
			if hands == 0:
				hands = 3
			var shape := cmd & 7
			var speed := Fx.s8(lo)
			if hi == HAND_RESET:
				shape = 0
				speed = lo
			elif hi == HAND_COSTUME:
				shape = tables.hand_shape(f.costume_slot)
				speed = lo
			f.hands.command(hands, shape, speed, f.char_id)
			out.add(SimEvents.Kind.HAND, f.index, hands, shape).c = speed
		elif hi >= 1 and hi <= SHAKE_LAST:
			out.add(SimEvents.Kind.SHAKE_REQUEST, f.index, hi - 1)
		elif hi == GROUND_IMPACT:
			out.add_at(SimEvents.Kind.DUST, f.index, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
			# Bug #16: the game passes the player slot, not the fighter index (the same in
			# two-fighter modes).
			out.add(SimEvents.Kind.FIGHTER_VIBRATE, f.index, VIBRATE_IMPACT)
		elif hi >= EXTRA_FIRST and hi <= EXTRA_LAST:
			f.extra_kind = hi - EXTRA_FIRST + 1
			f.extra_damage = lo


## The world position of the joint block an event names (the scripted scenes have no body:
## their presentation resolves the joint itself).
static func _joint_point(f: FighterState, joint: int) -> PackedInt32Array:
	if f.body == null:
		return PackedInt32Array()
	return f.body.joints[joint].t.duplicate()
