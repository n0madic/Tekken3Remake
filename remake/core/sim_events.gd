class_name SimEvents
extends RefCounted
## What one simulation step asks the presentation to do (remake-plan.md#one-step): effect
## spawns, sounds, music, vibration and the like. The simulation never plays anything itself.

enum Kind {
	EFFECT,       ## a: flipbook set (the owner's fighter index), b: joint
	SPARK,        ## a: system flipbook index (set 3), b: joint
	DUST,         ## landing dust at the fighter's root (move event 4)
	SHAKE,        ## a: camera shake script (CameraShakeStart)
	VIBRATE,      ## a: pad (2 both), b: pattern (PadVibrate)
	HAND,         ## a: hands (bit per channel), b: shape, c: speed; applied to the fighter's hands
	LANDING_DUST, ## a knock-down landing: dust ring and floor mark at `point` (FUN_8004AC28)
	SOUND,        ## a: sound code, b: player (voice channel), c: attenuation (SoundPlayFighter)
	SOUND_STOP,   ## a: sound code whose voice stops, b: player (SoundStopFighter)
	SYSTEM_SOUND, ## a: system sound id (SoundPlaySystem)
	HIT_SPARK,    ## a: 0 hit, 1 guard, b: damage of the hit; `point` the contact (HitSpawnEffect)
	MUSIC,        ## a: track, −1 stops the music
	MUSIC_VOLUME, ## a: volume 0–127, b: frames of the fade
	VOICE_OFF,    ## a: SPU voice keyed off (SsUtKeyOffV)
	VOICES_OFF,   ## the fighters' voices keyed off (FUN_8004B920); a: 1 keeps the music voices
	EFFECTS_CLEAR, ## every running effect ends (round start, replay start and end)
	EFFECTS_DRAW, ## a: how the flipbooks and dust rings are drawn this frame (EFFECTS_HOLD, EFFECTS_ADVANCE)
	PAUSE_MENU,   ## the pause menu of player `a` (1/2) is shown this frame (FUN_80078498)
	REPLAY_TEXT,  ## the blinking REPLAY caption is shown this frame
	SHAKE_REQUEST, ## a: camera shake script of a move event (the fight starts it: SHAKE)
	FIGHTER_VIBRATE, ## a: FighterVibrate kind of a move event (the fight turns it into VIBRATE)
	MUSIC_STOP,   ## the music stops (FUN_8006C870; not a MusicPlay call)
	MUSIC_TRACK,  ## a: the sound player's track, b: 1 the arcade version (Theater, FUN_8006B47C)
	MUSIC_PREPARE, ## a: the track to start later (MusicPlay(track, 1))
	MOVE_LIST,    ## the move lists are shown: a: the sides' mask, b: the side of the exit prompt (MoveListScreen)
	FORCE_NAMES,  ## Tekken Force: fighter `a`'s name plate changes to character `b` (FUN_800B362C)
	SHOUT,        ## a: the voice id (0x2nnn) of an attack shout that plays, b: player (the arcade models' face: ArcadeFace)
}

## EFFECTS_DRAW modes: the game's flipbook and dust ring draw calls (FUN_80077744,
## FUN_8004AEBC) with their advance flag clear (paused frames, the replay's still frames) or set
## (FUN_8007780C and FUN_8004AF4C in the fight frame, FUN_8004A954 in the replay). A step
## without EFFECTS_DRAW does not draw them (the loser camera, FUN_8002BDAC; between rounds).
const EFFECTS_HOLD := 0
const EFFECTS_ADVANCE := 1


class Event:
	var kind: int
	var fighter: int     ## the fighter whose data produced the event
	var a: int
	var b: int
	var c := 0
	var point := PackedInt32Array()   ## world position (game units) where the event happens
	var vector := PackedInt32Array()  ## HIT_SPARK: the hit direction (the hit slot's), for the drift

	func _init(event_kind: int, owner: int, first: int, second: int) -> void:
		kind = event_kind
		fighter = owner
		a = first
		b = second

	func _to_string() -> String:
		return "%s(f%d, %d, %d, %d)" % [Kind.keys()[kind], fighter, a, b, c]


var items: Array[Event] = []


func add(kind: int, fighter: int, a: int = 0, b: int = 0) -> Event:
	var e := Event.new(kind, fighter, a, b)
	items.append(e)
	return e


func add_at(kind: int, fighter: int, point: PackedInt32Array, a: int = 0, b: int = 0) -> Event:
	var e := add(kind, fighter, a, b)
	e.point = point
	return e


## The step's first event of this kind, or null.
func first(kind: int) -> Event:
	for e in items:
		if e.kind == kind:
			return e
	return null


## Whether the step raised an event of this kind.
func has(kind: int) -> bool:
	return first(kind) != null


func clear() -> void:
	items.clear()
