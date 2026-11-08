class_name ArcadeSounds
extends RefCounted
## FUN_801A104C: a fighter's voices and sounds of the frame, on the PlayStation's plan (FighterSounds)
## with its own tables and rules. A hit stops the sound script and silences the frame's ambient sounds,
## damage voices have no hold of their own, attack shouts change the speaker's face.

const ID_LAND_B := 0                  ## the voice set's ids
const ID_LAND_A := 1
const VOICE_DAMAGE_FRAMES := 3        ## the damage voice skips every fourth frame
const LAST_SOUND_LIST := 3
const LIST_END := 0xFFFF
const GUN_JACK_WEAK := 0x706D
const FAST_SWINGERS: Array[int] = [5, 7, 10, 0x12]
const FAST_SWING_FRAMES := 9
const VOICE_FIRST_ID := 0x2000
## FUN_801A1C74: per character, the mouth's face shape and how long it holds per attack shout.
const SPEAKING_FACE := {
	0: [0xD, [0x23, 0x5A, 0x14, 0x28, 0xF, 0x78, 0x32, 0x3C]],
	1: [0xD, [0xF, 0x28, 0xF, 0xF, 0xF, 0x46, 0x32, 0x3C]],
	6: [0xF, [0x14, 0x14, 0x14, 0x14, 0x14, 0x14, 0x1E, 0x28, 0x50]],
	7: [0xD, [0x14, 0x14, 0x32, 0x14, 0xF, 0xF, 0x32, 0x2D]],
}

var fight: FightState
var t: FightTables
var ko_voiced := PackedInt32Array([0, 0])   ## 0x8021FC30: the round's KO voice was played


func _init(fight_state: FightState) -> void:
	fight = fight_state
	t = fight_state.tables


func run(f: FighterState, opp: FighterState, events: SimEvents) -> void:
	var p := f.player_index
	var voices := t.voices[f.voice_set]
	fight.sound_hold[p] = 0
	var voiced := f.ko != 0
	if voiced:
		var id := (((fight.rng.next() & 0xFF) * voices.counts[2]) >> 8) | FighterSounds.KO_VOICE
		FighterSounds.replay_voice(fight, p, f.voice_set, id, events)
		ko_voiced[p] = 1
	var joint := f.pose_move.attack_joints & 0xFF
	var impacted := opp.health == 0 and opp.hit_clean != 0
	if impacted:
		FighterSounds.replay_sound(fight, p, FighterSounds.KO_IMPACT_LIGHT if joint < FighterSounds.HEAVY_JOINT else FighterSounds.KO_IMPACT_HEAVY, events)
	voiced = _list(f, opp, voices, voiced, impacted, events)
	if f.got_hit != 0:
		FighterSounds.script_stop(f)
	elif f.sound_script != -1 and fight.camera_phase in [CameraPhase.RESET, CameraPhase.INTRO, CameraPhase.FIGHT,
			CameraPhase.WINNER]:
		FighterSounds.run_script(fight, f, opp, events)
	else:
		_ambient(f, opp, voices, voiced, events)
	if fight.voice_cooldown[p] > 0:
		fight.voice_cooldown[p] -= 1


## The move's list of up to three sounds; returns whether a voice was started.
func _list(f: FighterState, opp: FighterState, voices: FightTables.VoiceSet, voiced_in: bool, impacted: bool,
		events: SimEvents) -> bool:
	var voiced := voiced_in
	var move := f.pose_move
	if move.sounds < 0:
		return voiced
	var p := f.player_index
	var list := move.bank.sounds
	for k in LAST_SOUND_LIST:
		var code: int = list[move.sounds + k]
		if code == LIST_END:
			break
		match code >> 12:
			1, 7:
				if f.contact != 0 and not impacted:
					_impact(f, opp, code, events)
			2:
				if _may_speak(f, voiced):
					FighterSounds.replay_voice(fight, p, f.voice_set, code, events)
					fight.voice_cooldown[p] = voices.cooldown
					_face(f, code)
			3:
				if _may_speak(f, voiced):
					FighterSounds.replay_voice(fight, p, f.voice_set, code, events)
					voiced = true
			4, 5:
				FighterSounds.replay_sound(fight, p, code, events)
			8:
				var script := code & 0xFFF
				if script != 0 and f.sound_script_last != script:
					f.sound_script = script
					f.sound_script_last = script
					f.sound_script_pos = 0
					f.sound_script_frame = Fx.s16(f.pose_frame - 1)
			9:
				FighterSounds.special(fight, f, opp, code & 0xFFF, events)
	return voiced


func _may_speak(f: FighterState, voiced: bool) -> bool:
	var p := f.player_index
	return f.pose_frame == 1 and f.health != 0 and fight.voice_cooldown[p] == 0 and not voiced and ko_voiced[p] == 0


## The damage voice, the attack shout, jump and landing sounds and the swing.
func _ambient(f: FighterState, opp: FighterState, voices: FightTables.VoiceSet, voiced_in: bool,
		events: SimEvents) -> void:
	var voiced := voiced_in
	var p := f.player_index
	if not voiced and ko_voiced[p] == 0 and f.hit_clean != 0 and fight.frame_counter & VOICE_DAMAGE_FRAMES != 0:
		var n := voices.damage_counts[0]
		var first := 0
		if opp.damage >= FighterSounds.HEAVY_DAMAGE:
			n = voices.damage_counts[1]
			first = voices.damage_counts[0]
		voiced = true
		if n != 0:
			var id := voices.damage[first + (((fight.rng.next() & 0xFF) * n) >> 8)]
			FighterSounds.replay_voice(fight, p, f.voice_set, id, events)
	if fight.voice_cooldown[p] == 0 and not voiced and f.damage != 0 and f.throw_state == 0 and f.move_changed != 0 \
			and fight.rng.next() & 1:
		var id := voices.shouts[(voices.shouts.size() * (fight.rng.next() & 0xFF)) >> 8]
		FighterSounds.replay_voice(fight, p, f.voice_set, id, events)
		fight.voice_cooldown[p] = voices.cooldown
		_face(f, id)
	if fight.sound_hold[p] == 0:
		var pose := f.pose_move
		if f.pose_frame == pose.air_first and f.pose_frame != 1:
			FighterSounds.replay_sound(fight, p, FighterSounds.JUMP, events)
		if f.landed_a != 0 and fight.sound_hold[p] == 0:
			FighterSounds.replay_sound(fight, p, voices.ids[ID_LAND_A], events)
		if f.landed_b != 0 and fight.sound_hold[p] == 0:
			FighterSounds.replay_sound(fight, p, voices.ids[ID_LAND_B], events)
	if f.pose_frame == f.pose_move.active_first - 1:
		_swing(f, events)


## FUN_801A1C74.
func _face(f: FighterState, id: int) -> void:
	if not SPEAKING_FACE.has(f.char_id):
		return
	var entry: Array = SPEAKING_FACE[f.char_id]
	var holds: Array = entry[1]
	var at := (id & 0xFFFF) - VOICE_FIRST_ID
	var hold: int = holds[at] if at >= 0 and at < holds.size() else 0
	f.hands.command(0, entry[0] as int, hold)


## FUN_801A1EAC.
func _swing(f: FighterState, events: SimEvents) -> void:
	var code := 0
	var r := fight.rng.next()
	if f.char_id in FAST_SWINGERS and f.pose_frame < FAST_SWING_FRAMES:
		code = t.swing_sounds[(r >> 6) & 3]
	else:
		code = t.swing_sounds_slow[((r & 0xFF) * 3) >> 8]
	FighterSounds.replay_sound(fight, f.player_index, code, events)


## The sounds of a contact: strike or guard by the first joint, Gun Jack's and the wooden Mokujin's.
func _impact(f: FighterState, opp: FighterState, code: int, events: SimEvents) -> void:
	var q := opp.player_index
	var joint := f.pose_move.attack_joints & 0xFF
	var wooden := opp.char_id == Character.MOKUJIN and fight.wooden_sounds[q] != 0
	if opp.guarded != 0:
		if wooden:
			FighterSounds.replay_sound(fight, q, FighterSounds.WOOD_GUARD_LIGHT if joint < FighterSounds.GUARD_JOINT else FighterSounds.WOOD_GUARD_HEAVY, events)
		else:
			FighterSounds.replay_sound(fight, q, FighterSounds.GUARD_LIGHT if joint < FighterSounds.GUARD_JOINT else FighterSounds.GUARD_HEAVY, events)
		return
	FighterSounds.script_stop(opp)
	if opp.char_id == Character.GUN_JACK:
		_gun_jack(f, opp, events)
	elif wooden:
		var impacts := t.impact_voices
		FighterSounds.replay_sound(fight, q, impacts[((fight.rng.next() & 0xFF) * impacts.size()) >> 8], events)
	elif code in FighterSounds.STRIKE_CODES:
		_strike(f, events)
	else:
		FighterSounds.replay_sound(fight, f.player_index, code, events)


## FUN_801A1F74.
func _gun_jack(f: FighterState, opp: FighterState, events: SimEvents) -> void:
	var code := FighterSounds.GUN_JACK_LIGHT
	if f.damage < 7:
		code = GUN_JACK_WEAK
	elif opp.damage >= 0x10:
		code = FighterSounds.GUN_JACK_HEAVY_A if fight.vblank & 3 == 0 else FighterSounds.GUN_JACK_HEAVY_B
	FighterSounds.replay_sound(fight, opp.player_index, code, events)


## FUN_801A2058.
func _strike(f: FighterState, events: SimEvents) -> void:
	var tier := 3
	if f.damage < 0xD:
		tier = 0
	elif f.damage < 0x17:
		tier = 1
	elif f.damage < 0x21:
		tier = 2
	var code := 0x7045 + tier
	if f.pose_move.attack_joints & 0xFF < FighterSounds.GUARD_JOINT:
		var r := fight.rng.next()
		code = t.strike_sounds[(r >> 7) & 1] if tier == 0 else 0x7041 + tier
	FighterSounds.replay_sound(fight, f.player_index, code, events)
