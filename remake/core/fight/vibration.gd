class_name Vibration
extends RefCounted
## Pad vibration requests (PadVibrate patterns, SimEvents VIBRATE a = pad (2 both), b = pattern):
## HitVibration (0x80075CBC) for the frame's hits, FighterVibrate (0x800760D4) for the move and
## effect events and VibrateAll (0x80076078) for camera shakes. Nothing vibrates during a replay.

const BOTH_PADS := 2

## HitVibration patterns: on the fighter's own pad, then the pads flagged per player.
const GUARDED := 0x10
const HIT_LIGHT := 0x11
const HIT_HEAVY := 0x12           ## damage from 21 on
const HEAVY_DAMAGE := 0x15
const HIT_CLOSE := 0x14
const HIT_COUNTER := 0x15
const EXTRA_DAMAGE := 0x13
const LANDED := 0x18
const KNOCKED_OUT := 0x16
const POWER_MOVE := 0xE
const FLAGGED := [[0x40, 0x1A], [1, 4], [2, 5], [4, 6], [8, 8], [0x10, 9], [0x20, 7], [0x80, 0xB]]

## FighterVibrate kinds: (own pad pattern or −1, other pad pattern or −1); kinds 2–5 vibrate
## the fighter's own pad only.
const FIGHTER_KINDS := [[0x17, 10], [0xF, 0x1B], [0x19, -1], [0xC, -1], [0xD, -1], [5, -1]]


static func _allowed(fight: FightState) -> bool:
	return fight.replay_playing == 0 \
		and (fight.mode != GameMode.BALL or fight.region.ctx_s32(TekkenBall.LAST_POINT) == 0)


## FUN_800761D8: the pad of a fighter (Tekken Force: the human's pad for the first record, the
## other pad for the enemies).
static func _pad(fight: FightState, f: FighterState) -> int:
	if fight.mode == GameMode.FORCE:
		var human := fight.force.human()
		return human if f.index == 0 else (human + 1) & 1
	return f.player_index


## HitVibration: the outcome of every fighter's last applied hit on its pad, then the attacker's
## and thrower's pads.
static func hits(fight: FightState, events: SimEvents) -> void:
	if not _allowed(fight):
		return
	var flagged := PackedInt32Array([0, 0, 0])   # by attacker record (the third: the ball, a Force enemy)
	for f in fight.active():
		var pad := _pad(fight, f)
		var attacker := f.last_attacker
		if f.guarded != 0:
			events.add(SimEvents.Kind.VIBRATE, f.index, pad, GUARDED)
			flagged[attacker] |= 1
		# The KO flag goes to the pad of the hit's attacker (or the thrower). The game starts the
		# index at −1, so a KO without either this frame (guard damage) flags a stack word and no
		# pad gets pattern 0x0B (game-bugs.md #58, not reproduced): here the last attacker's does.
		var ko_pad := attacker
		if f.hit_clean != 0:
			if f.last_damage < HEAVY_DAMAGE:
				events.add(SimEvents.Kind.VIBRATE, f.index, pad, HIT_LIGHT)
				flagged[attacker] |= 2
			else:
				events.add(SimEvents.Kind.VIBRATE, f.index, pad, HIT_HEAVY)
				flagged[attacker] |= 4
			if f.close_hit != 0:
				events.add(SimEvents.Kind.VIBRATE, f.index, pad, HIT_CLOSE)
				flagged[attacker] |= 8
			if f.counter_hit != 0:
				events.add(SimEvents.Kind.VIBRATE, f.index, pad, HIT_COUNTER)
				flagged[attacker] |= 0x10
		if f.last_extra_damage > 0:
			events.add(SimEvents.Kind.VIBRATE, f.index, pad, EXTRA_DAMAGE)
			ko_pad = f.throw_partner
			flagged[ko_pad] |= 0x20
		if f.landed_b != 0:
			events.add(SimEvents.Kind.VIBRATE, f.index, pad, LANDED)
		if f.ko != 0:
			events.add(SimEvents.Kind.VIBRATE, f.index, pad, KNOCKED_OUT)
			flagged[ko_pad] |= 0x80
		if f.pose_move.flags & MoveFlag.POWER != 0 and f.move_changed != 0:
			events.add(SimEvents.Kind.VIBRATE, f.index, pad, POWER_MOVE)
			flagged[(f.player_index + 1) & 1] |= 0x40
	for p in 2:
		var pad := _pad(fight, fight.fighters[p])
		for entry: Array in FLAGGED:
			var bit: int = entry[0]
			if flagged[p] & bit != 0:
				events.add(SimEvents.Kind.VIBRATE, p, pad, entry[1] as int)


## FighterVibrate: kind 0 burning, 1 move effect, 2 ground impact, 3 fire breath, 4 Gon's flame,
## 5 unused here.
static func fighter(fight: FightState, index: int, kind: int, events: SimEvents) -> void:
	if not _allowed(fight):
		return
	var pad := _pad(fight, fight.fighters[index])
	var patterns: Array = FIGHTER_KINDS[kind]
	var own: int = patterns[0]
	var other: int = patterns[1]
	events.add(SimEvents.Kind.VIBRATE, index, pad, own)
	if other >= 0:
		events.add(SimEvents.Kind.VIBRATE, index, (pad + 1) & 1, other)


## VibrateAll: a camera shake's pulse on both pads.
static func all(fight: FightState, script: int, events: SimEvents) -> void:
	if _allowed(fight):
		events.add(SimEvents.Kind.VIBRATE, -1, BOTH_PADS, script + 1)
