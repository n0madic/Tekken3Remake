class_name AudioDirector
extends Node
## Plays the simulation's and the screens' sound requests on separate buses (remake-plan.md#audio):
## music tracks (from `imported/music/music.json`, ARRANGE or ARCADE, with the track's volume;
## silent in a build without music) and the game's 16-bit sound codes (sound.md#sound-code) on
## emulated SPU voices, so that a sound replaces the one playing on its voice as in the game.
## SPEAKER OUT's MONO (the options) folds the whole mix down to mono on the master bus.

const BUSES: Array[StringName] = [&"Music", &"SFX", &"Voices", &"System"]
const SPU_VOICES := 24               ## SsUtKeyOnV ignores voices from 24 on
const ECHO_VOICES_FROM := 16         ## attenuation bit 0x80 moves a sound 16 voices up
const PLAYER_VOICES_FROM := 6        ## voices above 5 are offset by the player number
const VOLUME_MAX := 127.0
const BANK_COMBAT := 1
const BANK_SYSTEM := 2
const BANK_FIGHTER := 3
const BANK_NAMES := {BANK_COMBAT: "combat", BANK_SYSTEM: "system"}
const BANK_BUSES := {BANK_COMBAT: &"SFX", BANK_SYSTEM: &"System", BANK_FIGHTER: &"Voices"}
## FUN_8004B920: voices it leaves on (the announcer's), and with `keep_music` these as well.
const VOICES_KEPT := [2, 3]
const VOICES_KEPT_MUSIC := [1, 6, 7]

var music := AudioStreamPlayer.new()
var voices: Array[AudioStreamPlayer] = []
var tracks: Dictionary = {}
var banks: Dictionary = {}           ## bank name → tones ("<program>_<tone>" → file, gain)
var volumes := PackedInt32Array()    ## key-on volume by code bits 6–9
var voice_banks: Dictionary = {}     ## costume slot → voice bank name
var sound_codes := PackedInt32Array()   ## g_soundTable (SoundPlaySystem, the Mokujin remap)
var mokujin_sounds: Array[PackedInt32Array] = []
var fighter_banks := PackedStringArray(["", ""])
var fighter_chars := PackedInt32Array([-1, -1])
var soundtrack := 0                  ## 0 ARRANGE, 1 ARCADE (the BGM option)
var music_available := false
var _music_volume := 1.0             ## the track's own volume
var _music_level := 1.0              ## the fade level (MusicSetVolume)
var _prepared := -1                  ## the track MusicPlay(track, 1) loaded, silent until the volume call
var _fade: Tween
var _streams: Dictionary = {}       ## tone file → stream
var _requested: Dictionary = {}     ## tone file → true: a background load is under way (_preload_bank)
## Background loads of tones no fighter needs any more: taken (and thrown away) once finished, so
## that dropping them never waits for the decoder.
var _dropped: Dictionary = {}
var mono := false                    ## SPEAKER OUT: MONO
var _downmix := AudioEffectStereoEnhance.new()


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	# A pan pull-out of 0 folds both sides into one (SPEAKER OUT: MONO).
	_downmix.pan_pullout = 0.0
	AudioServer.add_bus_effect(0, _downmix)
	AudioServer.set_bus_effect_enabled(0, AudioServer.get_bus_effect_count(0) - 1, false)
	music.bus = &"Music"
	add_child(music)
	for i in SPU_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		voices.append(p)
	music_available = Assets.has_group("music")
	if music_available:
		var data: Dictionary = JsonFile.read(Assets.path("music/music.json"))
		tracks = data.get("tracks", {})
	if FileAccess.file_exists(_sound_path("sounds.json")):
		var data: Dictionary = JsonFile.read(_sound_path("sounds.json"))
		banks = data.get("banks", {})
		volumes = JsonFile.ints(data.get("volumes", []))
		voice_banks = data.get("voice_banks", {})
		for bank: String in BANK_NAMES.values():
			_preload_bank(bank)


## The fight tables' sound codes and Mokujin remap (loaded once by FightContent).
func use_tables(tables: FightTables) -> void:
	sound_codes = tables.sound_codes
	mokujin_sounds = tables.effects.mokujin_sounds


## SPEAKER OUT: MONO folds the mix to mono, STEREO leaves it.
func set_mono(on: bool) -> void:
	if on == mono:
		return
	mono = on
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _downmix:
			AudioServer.set_bus_effect_enabled(0, i, on)


func _exit_tree() -> void:
	for file: String in _requested.keys():
		_take_requested(file)
	for file: String in _dropped.keys():
		_take_dropped(file)
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _downmix:
			AudioServer.remove_bus_effect(0, i)
			return


## The voice banks and characters of the fight's fighters (SoundSelectBanks; players 1 and 2,
## the first entries of the arrays). The voice banks no fighter uses any more are dropped once both
## are known, so a bank that changes sides between two fights stays loaded.
func set_fighters(costume_slots: PackedInt32Array, char_ids: PackedInt32Array) -> void:
	for player in mini(costume_slots.size(), fighter_banks.size()):
		fighter_banks[player] = str(voice_banks.get(str(costume_slots[player]), ""))
		fighter_chars[player] = char_ids[player]
	_evict_unused_voices()
	for bank in fighter_banks:
		_preload_bank(bank)


## MusicPlay(track): starts a track, −1 stops the music.
func play_music(track: int) -> void:
	play_track(track, soundtrack)


## A track in a given version (0 ARRANGE, 1 ARCADE): the Theater's sound player picks it.
func play_track(track: int, version: int) -> void:
	_prepared = -1
	if _fade != null:
		_fade.kill()
		_fade = null
	music.stop()
	_music_level = 1.0
	if track < 0 or not music_available:
		return
	var variants: Array = tracks.get(str(track), [])
	if variants.is_empty():
		return
	var v: Dictionary = variants[clampi(version, 0, variants.size() - 1)]
	var stream := load(Assets.path("music/" + str(v["file"]))) as AudioStream
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		var loop: bool = v["loop"]
		ogg.loop = loop                    # the whole stream; a WAV carries its loop itself
	music.stream = stream
	var volume: float = v["volume"]
	_music_volume = volume / VOLUME_MAX
	_apply_music_volume()
	music.play()


## MusicSetVolume(volume 0–127, frames): fades the music to `volume` over `frames`.
func fade_music(volume: int, frames: int) -> void:
	if _fade != null:
		_fade.kill()
	var target := clampf(volume / VOLUME_MAX, 0.0, 1.0)
	if frames <= 0:
		_music_level = target
		_apply_music_volume()
		return
	_fade = create_tween()
	_fade.tween_method(_set_music_level, _music_level, target, frames / 60.0)


func _set_music_level(level: float) -> void:
	_music_level = level
	_apply_music_volume()


func _apply_music_volume() -> void:
	music.volume_db = linear_to_db(maxf(_music_volume * _music_level, 0.0001))


## Stops the music and every sound (before quitting: the audio server releases a playback on
## its next mix, so a stream still playing at exit is reported as leaked).
func stop_all() -> void:
	music.stop()
	for p in voices:
		p.stop()


## SoundPlayFighter(player, code, attenuation).
func play_code(code: int, player: int, attenuation: int) -> void:
	player = clampi(player, 0, 1)
	code &= 0xFFFF
	if fighter_chars[player] == Character.MOKUJIN:
		code = _mokujin(code)
	var bank := code >> 14
	if bank == 0:
		return
	var voice := (code >> 10) & 0xF
	if attenuation & 0x80 != 0:
		voice += ECHO_VOICES_FROM
	elif voice >= PLAYER_VOICES_FROM:
		voice += player
	var level := volumes[(code >> 6) & 0xF] >> (attenuation & 0x1F) if not volumes.is_empty() else 127
	_key_on(voice, bank, fighter_banks[player], code, level)


## SoundPlaySystem(id): entry `id` of the sound table on its own voice and bank.
func play_system(id: int) -> void:
	if id < 0 or id >= sound_codes.size():
		return
	var code := sound_codes[id]
	var bank := code >> 14
	if bank == 0:
		return
	var level := volumes[(code >> 6) & 0xF] if not volumes.is_empty() else 127
	# Bank 3 would be VAB 2, the voice cache's first slot; the game never reaches it here: every
	# SoundPlaySystem id (FUN_80040E98: the announcer, the continue, the sound scripts' 5–9) is
	# in VAB 1 (sound.md).
	_key_on((code >> 10) & 0xF, bank, fighter_banks[0], code, level)


## SoundStopFighter(player, code): keys off the code's voice.
func stop_code(code: int, player: int) -> void:
	if code & 0xC000 == 0:
		return
	var voice := (code & 0x3C00) >> 10
	if voice > 5:
		voice += clampi(player, 0, 1)
	key_off(voice)


func key_off(voice: int) -> void:
	if voice >= 0 and voice < voices.size():
		voices[voice].stop()


## FUN_8004B920: every voice off but the announcer's (and the music ones with `keep_music`).
func voices_off(keep_music: bool) -> void:
	for v in SPU_VOICES:
		if v in VOICES_KEPT or (keep_music and v in VOICES_KEPT_MUSIC):
			continue
		key_off(v)


## The sound and music requests of a simulation step (from its `from`-th event: a frame
## finished after a movie handles only what came after the movie).
func handle(events: SimEvents, from := 0) -> void:
	_collect_dropped()
	for i in range(from, events.items.size()):
		var e := events.items[i]
		match e.kind:
			SimEvents.Kind.SOUND:
				play_code(e.a, e.b, e.c)
			SimEvents.Kind.SOUND_STOP:
				stop_code(e.a, e.b)
			SimEvents.Kind.SYSTEM_SOUND:
				play_system(e.a)
			SimEvents.Kind.VOICE_OFF:
				key_off(e.a)
			SimEvents.Kind.VOICES_OFF:
				voices_off(e.a != 0)
			SimEvents.Kind.MUSIC:
				play_music(e.a)
			SimEvents.Kind.MUSIC_PREPARE:
				# MusicPlay(track, 1) only loads the stream: it is heard from the volume call
				# that FUN_8006BCC8 makes (a disc read or a MusicPlay in between drops it).
				play_music(-1)
				_prepared = e.a
			SimEvents.Kind.MUSIC_TRACK:
				play_track(e.a, e.b)
			SimEvents.Kind.MUSIC_STOP:
				play_music(-1)
			SimEvents.Kind.MUSIC_VOLUME:
				if _prepared >= 0:
					play_music(_prepared)
				fade_music(e.a, e.b)


## FUN_80075830: Mokujin's replacement for the codes of some sound ids.
func _mokujin(code: int) -> int:
	for pair in mokujin_sounds:
		if pair[0] < sound_codes.size() and sound_codes[pair[0]] == code:
			return pair[1] & 0xFFFF
	return code


## SsUtKeyOffV, then SsUtKeyOnV: the voice stops even when nothing plays on it (no bank or
## tone); voices from 24 on do not exist.
func _key_on(voice: int, bank: int, fighter_bank: String, code: int, level: int) -> void:
	if voice >= voices.size():
		return
	var p := voices[voice]
	p.stop()
	var name: String = fighter_bank if bank == BANK_FIGHTER else str(BANK_NAMES.get(bank, ""))
	if name.is_empty() or not banks.has(name):
		return
	var tones: Dictionary = (banks[name] as Dictionary).get("tones", {})
	var key := "%d_%d" % [(code >> 4) & 3, code & 0xF]
	if not tones.has(key):
		return
	var tone: Dictionary = tones[key]
	p.stream = _stream(str(tone["file"]))
	p.bus = BANK_BUSES.get(bank, &"SFX")
	var gain: float = tone["gain"]
	p.volume_db = linear_to_db(maxf(gain * level / VOLUME_MAX, 0.0001))
	p.play()


## A tone's stream: the one requested ahead (`_preload_bank`) or loaded now.
func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		_revive(file)
		var stream: AudioStream = _take_requested(file) if _requested.has(file) else null
		_streams[file] = stream if stream != null else load(_sound_path(file)) as AudioStream
	return _streams[file] as AudioStream


## The result of a background load (`_preload_bank`), waiting for it if need be. Every request is
## taken: the loader keeps a request nobody takes until the end, and it leaks at exit.
func _take_requested(file: String) -> AudioStream:
	_requested.erase(file)
	return ResourceLoader.load_threaded_get(_sound_path(file)) as AudioStream


func _take_dropped(file: String) -> void:
	_dropped.erase(file)
	ResourceLoader.load_threaded_get(_sound_path(file))


func _sound_path(file: String) -> String:
	return Assets.path("sounds/" + file)


## A dropped load wanted again becomes a request.
func _revive(file: String) -> void:
	if _dropped.has(file):
		_dropped.erase(file)
		_requested[file] = true


## Takes the dropped loads that have finished.
func _collect_dropped() -> void:
	if _dropped.is_empty():
		return
	for file: String in _dropped.keys():
		if ResourceLoader.load_threaded_get_status(_sound_path(file)) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_take_dropped(file)


## The sound files of a bank's tones.
func _bank_files(bank: String) -> PackedStringArray:
	var files := PackedStringArray()
	if banks.has(bank):
		var tones: Dictionary = (banks[bank] as Dictionary).get("tones", {})
		for tone: Dictionary in tones.values():
			files.append(str(tone["file"]))
	return files


## Loads a bank's tones ahead of their first key-on, which would otherwise load and decode them
## in the middle of a simulation step: in the background, except on the web, where threads are not
## a given and the bank is loaded now.
func _preload_bank(bank: String) -> void:
	for file in _bank_files(bank):
		_revive(file)
		if _streams.has(file) or _requested.has(file):
			continue
		if OS.has_feature("web"):
			_stream(file)
		elif ResourceLoader.load_threaded_request(_sound_path(file)) == OK:
			_requested[file] = true


## Drops the tones of the voice banks that no fighter of the fight uses any more: the common banks
## and the two fighters' voice banks stay.
func _evict_unused_voices() -> void:
	var keep := {}
	var kept: Array[String] = [fighter_banks[0], fighter_banks[1]]
	kept.append_array(BANK_NAMES.values())
	for bank in kept:
		for file in _bank_files(bank):
			keep[file] = true
	for file: String in _streams.keys():
		if not keep.has(file):
			_streams.erase(file)
	for file: String in _requested.keys():
		if not keep.has(file):
			_requested.erase(file)
			_dropped[file] = true
