class_name FightCalls
extends RefCounted
## The engine calls of one frame in a comparable form: the fight trace's logged calls
## (tools/research/fight_harness.py LOGGED_CALLS / LOGGED_STUBS) and the SimEvents that stand for them.
## Each call is a string "kind arg arg …" with the arguments masked to the width the game uses.

## Call kinds compared; the flipbook and dust spawns are checked through the effect state.
const KINDS := ["music", "music_volume", "sound", "sound_stop", "system_sound", "vibrate", "shake"]


## The trace's calls of `frame`.
static func of_trace(trace: FightTrace, frame: int) -> PackedStringArray:
	return of_list(trace.calls(frame))


## Logged calls as (kind name, arguments…) arrays.
static func of_list(calls: Array[Array]) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Array in calls:
		var kind: String = c[0]
		if kind not in KINDS:
			continue
		match kind:
			"sound":
				out.append("sound %d %04x %d" % [c[1], c[2] & 0xFFFF, c[3]])
			"sound_stop":
				out.append("sound_stop %d %04x" % [c[1], c[2] & 0xFFFF])
			"system_sound":
				out.append("system_sound %d" % (c[1] & 0xFFFF))
			"vibrate":
				out.append("vibrate %d %d" % [c[1], c[2]])
			"shake":
				out.append("shake %d" % c[1])
			"music":
				out.append("music %d" % c[1])
			"music_volume":
				out.append("music_volume %d %d" % [c[1], c[2]])
	return out


## The simulation's events of the last step.
static func of_events(events: SimEvents) -> PackedStringArray:
	var out := PackedStringArray()
	for e in events.items:
		match e.kind:
			SimEvents.Kind.SOUND:
				out.append("sound %d %04x %d" % [e.b, e.a & 0xFFFF, e.c])
			SimEvents.Kind.SOUND_STOP:
				out.append("sound_stop %d %04x" % [e.b, e.a & 0xFFFF])
			SimEvents.Kind.SYSTEM_SOUND:
				out.append("system_sound %d" % (e.a & 0xFFFF))
			SimEvents.Kind.VIBRATE:
				out.append("vibrate %d %d" % [e.a, e.b])
			SimEvents.Kind.SHAKE:
				out.append("shake %d" % e.a)
			SimEvents.Kind.MUSIC, SimEvents.Kind.MUSIC_PREPARE:
				out.append("music %d" % e.a)
			SimEvents.Kind.MUSIC_VOLUME:
				out.append("music_volume %d %d" % [e.a, e.b])
	return out
