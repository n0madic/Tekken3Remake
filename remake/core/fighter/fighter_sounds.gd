class_name FighterSounds
## FighterSounds (0x80041138, sound.md#fighter-sound-logic): the fighter's voices and sounds of
## the frame, the sound scripts, and the voice cooldowns. The simulation only decides what plays
## (SimEvents SOUND / SOUND_STOP / SYSTEM_SOUND with the game's 16-bit sound codes); every sound
## is also written to the replay. `rand()` is drawn exactly where the game draws it.

const VOICE_FIRST := 2               ## voice ids 0x2nnn–0x5nnn: category nibble − 2
const VOICE_CATEGORIES := 4
const SHOUT_CATEGORY := 2             ## category nibble of the attack shouts (SimEvents SHOUT)
const THROW_VOICE := 4               ## category nibble not written to the replay during a throw
const KO_VOICE := 0x4000
const KO_IMPACT_LIGHT := 0x7044
const KO_IMPACT_HEAVY := 0x7048
const HEAVY_JOINT := 0xB             ## first descriptor joint from which impacts are heavy
const GUARD_JOINT := 0xC
const GUARD_LIGHT := 0x704D
const GUARD_HEAVY := 0x704E
const WOOD_GUARD_LIGHT := 0x707B
const WOOD_GUARD_HEAVY := 0x707A
const STRIKE_CODES := [0x7000, 0x7041, 0x7042, 0x7045]
const JUMP := 0x1053
const LAND_A := 0x1054
const LAND_B := 0x104F
const SWING := 0x604A
const DAMAGE_VOICE_HOLD := 0x28
const HEAVY_DAMAGE := 0x14
const GUN_JACK_LIGHT := 0x705D
const GUN_JACK_HEAVY_A := 0x7099
const GUN_JACK_HEAVY_B := 0x7098
const REPLAY_SYSTEM := 1
const REPLAY_VOICE := 2
const REPLAY_SOUND := 3


## FighterSounds for fighter `f` against `opp` (the fight calls it for each active fighter).
static func run(fight: FightState, f: FighterState, opp: FighterState, events: SimEvents) -> void:
	var t := fight.tables
	var p := f.player_index
	var q := opp.player_index
	var voices := t.voices[f.voice_set]
	fight.sound_hold[p] = 0
	# FUN_8004B9B8: a clean hit, or the first frame of a throw victim's move, keys off voice 0.
	if f.hit_clean != 0 or (f.throw_state < 0 and f.move_frame == 1):
		events.add(SimEvents.Kind.VOICE_OFF, f.index, 0)
	var voiced := false
	var impacted := false
	if f.ko != 0:
		var id := (((fight.rng.next() & 0xFF) * voices.counts[2]) >> 8) | KO_VOICE
		_voice(fight, p, f.voice_set, id, events)
		voiced = true
	if opp.health == 0 and opp.hit_clean != 0:
		var code := KO_IMPACT_LIGHT if AttackRecords.first_joint(f.pose_move, t) < HEAVY_JOINT else KO_IMPACT_HEAVY
		_sound(fight, p, code, events)
		impacted = true
	var move := f.pose_move
	if move.sounds >= 0:
		var list := move.bank.sounds
		for k in 3:
			var code: int = list[move.sounds + k]
			if code == 0xFFFF:
				break
			match code >> 12:
				1, 7:
					if f.contact != 0 and not impacted:
						_impact(fight, f, opp, code, events)
				2:
					if f.pose_frame == 1 and f.health != 0 and fight.voice_cooldown[p] == 0 and not voiced:
						_voice(fight, p, f.voice_set, code, events)
						fight.voice_cooldown[p] = voices.cooldown
				3:
					if f.pose_frame == 1 and f.health != 0 and fight.voice_cooldown[p] == 0 and not voiced:
						_voice(fight, p, f.voice_set, code, events)
						voiced = true
				4, 5:
					_sound(fight, p, code, events)
				8:
					var script := code & 0xFFF
					if script != 0 and f.sound_script_last != script:
						f.sound_script = script
						f.sound_script_last = script
						f.sound_script_pos = 0
						f.sound_script_frame = Fx.s16(f.pose_frame - 1)
				9:
					_special(fight, f, opp, code & 0xFFF, events)
	if f.got_hit != 0:
		script_stop(f)
	if f.sound_script != -1 and fight.camera_phase in [CameraPhase.RESET, CameraPhase.INTRO, CameraPhase.FIGHT,
			CameraPhase.WINNER]:
		_run_script(fight, f, opp, events)
	else:
		_ambient(fight, f, opp, voices, voiced, events)
	if fight.voice_cooldown[p] > 0:
		fight.voice_cooldown[p] -= 1
	if fight.damage_voice_timer[p] > 0:
		fight.damage_voice_timer[p] -= 1


## SoundScriptStop (0x80041C30).
static func script_stop(f: FighterState) -> void:
	f.sound_script = -1
	f.sound_script_last = 0
	f.sound_script_pos = 0
	f.sound_script_frame = 0


## Steps 5–8 when no sound script runs: the damage voice, the attack shout, jump and landing
## sounds and the swing one frame before the active window.
static func _ambient(fight: FightState, f: FighterState, opp: FighterState, voices: FightTables.VoiceSet,
		voiced: bool, events: SimEvents) -> void:
	var p := f.player_index
	if not voiced and f.health != 0 and f.hit_clean != 0 and fight.damage_voice_timer[p] == 0 \
			and fight.frame_counter & 1:
		var n := voices.damage_counts[0]
		var first := 0
		if opp.damage >= HEAVY_DAMAGE:
			n = voices.damage_counts[1]
			first = voices.damage_counts[0]
		voiced = true
		if n != 0:
			var id := voices.damage[first + (((fight.rng.next() & 0xFF) * n) >> 8)]
			_voice(fight, p, f.voice_set, id, events)
			fight.damage_voice_timer[p] = DAMAGE_VOICE_HOLD
	if fight.voice_cooldown[p] == 0 and not voiced:
		if f.damage != 0 and f.throw_state == 0 and f.move_changed != 0 and fight.rng.next() & 3 == 0:
			var id := voices.shouts[(voices.shouts.size() * (fight.rng.next() & 0xFF)) >> 8]
			_voice(fight, p, f.voice_set, id, events)
			fight.voice_cooldown[p] = voices.cooldown
	if fight.sound_hold[p] == 0:
		if f.pose_frame == f.pose_move.air_first and f.pose_frame != 1:
			_sound(fight, p, JUMP, events)
		if f.landed_a != 0 and fight.sound_hold[p] == 0:
			_sound(fight, p, LAND_A, events)
		if f.landed_b != 0 and fight.sound_hold[p] == 0:
			_sound(fight, p, LAND_B, events)
	if f.pose_frame == f.pose_move.active_first - 1:
		_sound(fight, p, SWING, events)


## The running sound script: every entry of the script's frame counter.
static func _run_script(fight: FightState, f: FighterState, opp: FighterState, events: SimEvents) -> void:
	var script: PackedInt32Array = fight.tables.sound_scripts[f.sound_script]
	var p := f.player_index
	var q := opp.player_index
	f.sound_script_frame = Fx.s16(f.sound_script_frame + 1)
	while true:
		var entry := script[f.sound_script_pos]
		var frame := entry & 0xFFF
		if frame == 0:
			break
		if f.sound_script_frame < frame:
			return
		if f.sound_script_frame == frame:
			var code := (entry >> 16) & 0xFFFF
			match (entry >> 12) & 0xF:
				0:
					fight.replay.record_sound(REPLAY_SYSTEM, 0, Fx.s16(code))
					events.add(SimEvents.Kind.SYSTEM_SOUND, f.index, code & 0xFFF)
				1:
					if _is_voice(code):
						_voice(fight, p, f.voice_set, code, events)
					else:
						_sound(fight, p, code, events)
				2:
					if _is_voice(code):
						_voice(fight, q, opp.voice_set, code, events)
					else:
						_sound(fight, q, code, events)
				3:
					_special(fight, f, opp, code & 0xFFF, events)
		f.sound_script_pos += 1
	script_stop(f)


## Sound list nibbles 1 and 7 on contact: the impact sound of a hit or a guard.
static func _impact(fight: FightState, f: FighterState, opp: FighterState, code: int, events: SimEvents) -> void:
	var t := fight.tables
	var q := opp.player_index
	var joint := AttackRecords.first_joint(f.pose_move, t)
	var wooden := opp.char_id == Character.MOKUJIN and fight.wooden_sounds[q] != 0
	if opp.guarded == 0:
		script_stop(opp)
		if opp.char_id == Character.GUN_JACK:
			_gun_jack_hit(fight, f, opp, events)
		elif wooden:
			var impacts := t.impact_voices
			_sound(fight, q, impacts[((fight.rng.next() & 0xFF) * impacts.size()) >> 8], events)
		elif code in STRIKE_CODES:
			_strike(fight, f, events)
		else:
			_sound(fight, f.player_index, code, events)
	elif wooden:
		_sound(fight, q, WOOD_GUARD_LIGHT if joint < GUARD_JOINT else WOOD_GUARD_HEAVY, events)
	else:
		_sound(fight, q, GUARD_LIGHT if joint < GUARD_JOINT else GUARD_HEAVY, events)


## FUN_80041E08: Gun Jack's hit sounds (the game tests charId 0x10). The game alternates the heavy ones by the VSync counter
## (0x800AE6E0); the remake counts one VSync per frame.
static func _gun_jack_hit(fight: FightState, f: FighterState, opp: FighterState, events: SimEvents) -> void:
	var code := GUN_JACK_LIGHT
	if f.damage >= 7 and opp.damage >= 0x10:
		code = GUN_JACK_HEAVY_A if fight.vblank & 3 == 0 else GUN_JACK_HEAVY_B
	_sound(fight, opp.player_index, code, events)


## FUN_80041F4C: the strike sound by the attacker's damage and descriptor.
static func _strike(fight: FightState, f: FighterState, events: SimEvents) -> void:
	var code := 0
	if AttackRecords.first_joint(f.pose_move, fight.tables) < GUARD_JOINT:
		var r := fight.rng.next()
		if f.damage < 0xD:
			code = fight.tables.strike_sounds[(r >> 7) & 1]
		elif f.damage < 0x17:
			code = 0x7042
		elif f.damage < 0x21:
			code = 0x7043
		else:
			code = 0x7044
	elif f.damage < 0xD:
		code = 0x7045
	elif f.damage < 0x17:
		code = 0x7046
	elif f.damage < 0x21:
		code = 0x7047
	else:
		code = 0x7048
	_sound(fight, f.player_index, code, events)


## FUN_80041C48: 0 holds the jump and landing sounds this frame, 1 answers the opponent's sound
## script with the special voice and stops it, 2 starts a one-frame voice cooldown, 3 plays one
## of three special sounds for the opponent.
static func _special(fight: FightState, f: FighterState, opp: FighterState, n: int, events: SimEvents) -> void:
	var p := f.player_index
	match n:
		0:
			fight.sound_hold[p] = 1
		1:
			if opp.sound_script != -1:
				_voice(fight, p, f.voice_set, fight.tables.voices[f.voice_set].ids[2], events)
				script_stop(opp)
		2:
			fight.voice_cooldown[p] = 1
		3:
			var sounds := fight.tables.special_sounds
			_sound(fight, opp.player_index, sounds[((fight.rng.next() & 0xFF) * sounds.size()) >> 8], events)


## FUN_80040EB8 / FUN_80041038: a voice or sound the replay plays back (not recorded again).
static func replay_voice(fight: FightState, player: int, voice_set: int, code: int, events: SimEvents) -> void:
	_voice(fight, player, voice_set, code, events)


static func replay_sound(fight: FightState, player: int, code: int, events: SimEvents) -> void:
	_sound(fight, player, code, events)


static func _is_voice(code: int) -> bool:
	var c := (code >> 12) - VOICE_FIRST
	return c >= 0 and c < VOICE_CATEGORIES


## A voice id (0x2nnn–0x5nnn) of `player` with voice set `voice_set`: written to the replay
## unless it is a throw voice during a throw (FUN_80075BFC), then FighterVoice (0x80040F28).
static func _voice(fight: FightState, player: int, voice_set: int, id: int, events: SimEvents) -> void:
	id = Fx.s16(id)
	var nibble := id >> 12
	if not (fight.fighters[player].in_throw != 0 and nibble == THROW_VOICE):
		fight.replay.record_sound(REPLAY_VOICE, player, id)
	var c := ((id & 0xFFFF) >> 12) - VOICE_FIRST
	if c < 0 or c >= VOICE_CATEGORIES:
		return
	var voices := fight.tables.voices[voice_set]
	var index := id & 0xFFF
	if index > voices.counts[c] - 1:
		return
	for k in c:
		index += voices.counts[k]
	var code := voices.voices[index]
	events.add(SimEvents.Kind.SOUND, player, code, player)
	if c + VOICE_FIRST == SHOUT_CATEGORY:
		events.add(SimEvents.Kind.SHOUT, player, id, player)
	if c + VOICE_FIRST == THROW_VOICE:
		EffectObjects.voice_echo(fight, player, code, false)
		events.add(SimEvents.Kind.VOICE_OFF, player, 0)
	elif fight.replay_playing != 0:
		EffectObjects.voice_echo(fight, player, code, true)


## A sound id of `player`, written to the replay (FighterSoundById 0x8004108C): a zero top
## nibble stops the sound's voice.
static func _sound(fight: FightState, player: int, id: int, events: SimEvents) -> void:
	id = Fx.s16(id)
	fight.replay.record_sound(REPLAY_SOUND, player, id)
	var index := id & 0xFFF
	if index == 0:
		return
	var code := fight.tables.sound_codes[index]
	if id >> 12 == 0:
		events.add(SimEvents.Kind.SOUND_STOP, player, code, player)
	else:
		events.add(SimEvents.Kind.SOUND, player, code, player)
		if fight.replay_playing != 0:
			EffectObjects.voice_echo(fight, player, code, true)
