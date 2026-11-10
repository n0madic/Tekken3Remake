extends TestSuite
## AudioDirector plays sound codes on emulated SPU voices as SoundPlayFighter does: the voice is
## keyed off before the key-on, so a code with no tone behind it still cuts the old sound.

const DISC_DATA := [
	"test_a_prepared_track_is_silent_until_the_volume_call",
	"test_the_current_track_is_not_restarted",
]
const COMBAT_TONE := 0x4000 | 8 << 10 | 15 << 6       ## combat bank, voice 8, program 0 tone 0
const MISSING_TONE := COMBAT_TONE | 3 << 4 | 15       ## program 3 tone 15: not in the bank


func test_a_silent_code_keys_its_voice_off() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.play_code(COMBAT_TONE, 0, 0)
	expect(director.voices[8].playing, "the combat tone plays on voice 8")
	director.play_code(MISSING_TONE, 0, 0)
	expect(not director.voices[8].playing, "a code without a tone stops voice 8")
	director.stop_all()
	director.free()


func _winner_voice_director() -> AudioDirector:
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.set_fighters(PackedInt32Array([0, 2]), PackedInt32Array([0, 1]))
	director.play_code(RoundHud.VOICE_WIN, 0, 0)
	return director


func _after_voice_events(frames: int) -> SimEvents:
	var events := SimEvents.new()
	events.add(SimEvents.Kind.SOUND_AFTER_VOICE, -1, ResultScreens.SOUND_AFTER_VOICE, frames)
	return events


## Both codes sound on voice 1: 0x86DA waits for the winner's name (FUN_8007477C), or it cuts it.
func test_the_follow_up_waits_for_the_winners_voice() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := _winner_voice_director()
	var voice := director.voices[AudioDirector.WINNER_VOICE]
	var name_tone := voice.stream
	expect(voice.playing and name_tone != null, "the name plays on the winner's voice")
	director.handle(_after_voice_events(0))
	director.handle(SimEvents.new())
	expect(voice.playing and voice.stream == name_tone, "the name goes on")
	voice.stop()
	director.handle(SimEvents.new())
	expect(voice.playing and voice.stream != name_tone, "then the follow-up plays")
	voice.stop()
	director.handle(SimEvents.new())
	expect(not voice.playing, "once")
	director.stop_all()
	director.free()


## FUN_80075B4C: on the result screens 15 frames lie between the voice's end and the sound.
func test_the_result_screens_follow_up_waits_frames_more() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := _winner_voice_director()
	var voice := director.voices[AudioDirector.WINNER_VOICE]
	director.handle(_after_voice_events(ResultScreens.SEQ_DELAY))
	voice.stop()
	for frame in ResultScreens.SEQ_DELAY:
		director.handle(SimEvents.new())
		expect(not voice.playing, "quiet on frame %d" % frame)
	director.handle(SimEvents.new())
	expect(voice.playing, "then it plays")
	director.stop_all()
	director.free()


## The voice already quiet: nothing to wait for (a skipped or missing name).
func test_the_follow_up_plays_at_once_after_a_quiet_voice() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := _winner_voice_director()
	var voice := director.voices[AudioDirector.WINNER_VOICE]
	voice.stop()
	director.handle(_after_voice_events(ResultScreens.SEQ_DELAY))
	expect(voice.playing, "it plays at once")
	director.stop_all()
	director.free()


## A skip, a new round or another screen's sound leaves the follow-up unplayed.
func test_the_waiting_follow_up_is_dropped() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := _winner_voice_director()
	var voice := director.voices[AudioDirector.WINNER_VOICE]
	director.handle(_after_voice_events(0))
	var keep := SimEvents.new()
	keep.add(SimEvents.Kind.VOICES_OFF, -1, 1)
	director.handle(keep)
	expect(voice.playing, "a new round leaves the voice on")
	voice.stop()
	director.handle(SimEvents.new())
	expect(not voice.playing, "and nothing follows")
	director.play_code(RoundHud.VOICE_WIN, 0, 0)
	director.handle(_after_voice_events(0))
	director.play_code(RoundHud.VOICE_WIN, 0, 0)
	voice.stop()
	director.handle(SimEvents.new())
	expect(not voice.playing, "another sound on the voice drops it too")
	director.stop_all()
	director.free()


## FUN_8007517c: the staff roll's bank takes the first voice slot, so its opening call (0xC7C0) plays
## from it and not from the winner's voices; the next fight's fighters take the slot back.
func test_the_staff_roll_bank_replaces_the_first_voice_bank() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	expect(director.banks.has(AudioDirector.STAFF_ROLL_BANK), "the bank is converted")
	director.set_fighters(PackedInt32Array([0, 2]), PackedInt32Array([0, 1]))
	var events := SimEvents.new()
	events.add(SimEvents.Kind.STAFF_ROLL_BANK, -1)
	events.add(SimEvents.Kind.SOUND, -1, StaffRoll.SOUND_START, 0)
	director.handle(events)
	expect_equal(director.fighter_banks[0], AudioDirector.STAFF_ROLL_BANK, "the first slot")
	var tones: Dictionary = (director.banks[AudioDirector.STAFF_ROLL_BANK] as Dictionary)["tones"]
	var voice := director.voices[(StaffRoll.SOUND_START >> 10) & 0xF]
	expect(voice.playing, "the opening call plays")
	expect_equal(voice.stream.resource_path.get_file(), str((tones["0_0"] as Dictionary)["file"]).get_file(), "its tone")
	director.set_fighters(PackedInt32Array([0, 2]), PackedInt32Array([0, 1]))
	expect(director.fighter_banks[0] != AudioDirector.STAFF_ROLL_BANK, "a fight takes the slot back")
	director.stop_all()
	director.free()


## The first hit or voice of a fight must not load its tone in the middle of a step: the common
## banks are requested with the director and a fighter's voice bank when the fighter is set, and the
## voice banks of earlier fights are dropped.
func test_tones_are_loaded_ahead_of_their_key_on() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	var common := 0
	for bank: String in AudioDirector.BANK_NAMES.values():
		common += director._bank_files(bank).size()
	expect_equal(director._streams.size() + director._requested.size(), common, "the combat and system banks")
	director.set_fighters(PackedInt32Array([0]), PackedInt32Array([0]))
	var first := director._bank_files(director.fighter_banks[0])
	expect_equal(director._streams.size() + director._requested.size(), common + first.size(), "and the fighter's voice bank")
	for file in first:
		expect(director._stream(file) != null, "the tone %s is there when it is keyed on" % file)
	director.set_fighters(PackedInt32Array([10]), PackedInt32Array([9]))
	var second := director._bank_files(director.fighter_banks[0])
	expect(director.fighter_banks[0] != "voice_00", "another voice bank")
	expect_equal(director._streams.size() + director._requested.size(), common + second.size(), "the earlier voice bank is dropped")
	for file in first:
		expect(not director._streams.has(file) and not director._requested.has(file), "%s is gone" % file)
	director.free()


## Two fighters changing sides between fights keep their voice banks: they are dropped only once
## both fighters are known.
func test_voice_banks_that_change_sides_stay() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.set_fighters(PackedInt32Array([0, 10]), PackedInt32Array([0, 9]))
	var files := director._bank_files(director.fighter_banks[0]) + director._bank_files(director.fighter_banks[1])
	expect(director.fighter_banks[0] != director.fighter_banks[1], "two voice banks")
	for file in files:
		director._stream(file)
	director.set_fighters(PackedInt32Array([10, 0]), PackedInt32Array([9, 0]))
	for file in files:
		expect(director._streams.has(file), "%s stays loaded" % file)
	director.free()


## SPEAKER OUT: MONO folds the master bus down to mono; the downmix leaves with the director.
func test_mono_speaker_out() -> void:
	var effects := AudioServer.get_bus_effect_count(0)
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	var at := AudioServer.get_bus_effect_count(0) - 1
	var downmix := AudioServer.get_bus_effect(0, at) as AudioEffectStereoEnhance
	expect(downmix != null and downmix.pan_pullout == 0.0, "a mono downmix on the master bus")
	expect(not AudioServer.is_bus_effect_enabled(0, at), "off in stereo")
	director.set_mono(true)
	expect(AudioServer.is_bus_effect_enabled(0, at), "on in mono")
	director.set_mono(false)
	expect(not AudioServer.is_bus_effect_enabled(0, at), "off again")
	director.free()
	expect_equal(AudioServer.get_bus_effect_count(0), effects, "removed with the director")


## MusicPlay(track, 1) only loads the stream: the attract demonstration's prepared track must not
## sound before its scene (it is stopped and played again there); it is heard from the volume call.
func test_a_prepared_track_is_silent_until_the_volume_call() -> void:
	if not require(Assets.path("music/music.json"), "no music group"):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	var events := SimEvents.new()
	events.add(SimEvents.Kind.MUSIC_PREPARE, -1, 0)
	director.handle(events)
	expect(not director.music.playing, "prepared, not playing")
	var stop := SimEvents.new()
	stop.add(SimEvents.Kind.MUSIC_STOP, -1)
	stop.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0x7F, -1)
	director.handle(stop)
	expect(not director.music.playing, "a stop forgets the prepared track")
	director.handle(events)
	var ready := SimEvents.new()
	ready.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0x7F, -1)
	director.handle(ready)
	expect(director.music.playing, "the volume call starts it")
	director.stop_all()
	director.free()


## MusicPlay of the track already playing (each round start, the same fight after CONTINUE) does not
## start it again, FUN_8006BF80(0x7F, −1) only brings the volume back at once; a stop (every disc
## read) forgets the track, so the next MusicPlay starts it from the beginning.
func test_the_current_track_is_not_restarted() -> void:
	if not require(Assets.path("music/music.json"), "no music group"):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	var keys: Array = director.tracks.keys()
	var track := (keys[0] as String).to_int()
	director.play_music(track)
	expect(director.music.playing, "the first MusicPlay starts the track")
	director.fade_music(0, 0)
	director.music.stop()            # stands for a position that is no longer the beginning
	director.play_music(track)
	expect(not director.music.playing, "the same track is not started again")
	expect_equal(director._music_level, 1.0, "the volume is back at once")
	director.play_music(-1)
	director.play_music(track)
	expect(director.music.playing, "after a stop the track starts again")
	director.stop_all()
	director.free()


## Dropping a voice bank whose tones are still loading in the background does not wait for them:
## the loads are set aside and taken once finished, or taken back when the bank is wanted again.
func test_dropped_loads_do_not_block() -> void:
	if not require(Assets.path("sounds/sounds.json")):
		return
	if OS.has_feature("web"):
		return
	var director := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	director.set_fighters(PackedInt32Array([0]), PackedInt32Array([0]))
	var first := director._bank_files(director.fighter_banks[0])
	var loading := PackedStringArray()
	for file in first:
		if director._requested.has(file):
			loading.append(file)
	director.set_fighters(PackedInt32Array([10]), PackedInt32Array([9]))
	for file: String in loading:
		expect(director._dropped.has(file) and not director._requested.has(file), "%s set aside, not waited for" % file)
	director.set_fighters(PackedInt32Array([0]), PackedInt32Array([0]))
	for file: String in loading:
		expect(director._requested.has(file) and not director._dropped.has(file), "%s wanted again: a request" % file)
	director.set_fighters(PackedInt32Array([10]), PackedInt32Array([9]))
	var deadline := Time.get_ticks_msec() + 10000
	while not director._dropped.is_empty() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(5)
		director._collect_dropped()
	expect(director._dropped.is_empty(), "the finished loads are taken")
	director.free()


## SectionMusic without files: every section is a second of silence.
class SilentSections extends SectionMusic:
	func _request(_part: Part) -> void:
		pass

	func _music_stream(_part: Part) -> AudioStream:
		var stream := AudioStreamWAV.new()
		stream.mix_rate = 8000
		stream.data = PackedByteArray()
		stream.data.resize(16000)
		return stream


const JIN_TRACK := 16
const OGRE_TRACK := 21
const TRUE_OGRE_TRACK := 27


func _sections_director() -> AudioDirector:
	var director := AudioDirector.new()
	director.sections.free()
	director.sections = SilentSections.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	var rows: Array = []
	for k in 4:
		rows.append({"section": k, "parts": [{"file": "s_%d" % k, "length": 1.0, "loop": 0.0, "delay": 0.0, "cues": [0.5]}]})
	director.sections.load_table({
		"tracks": {"29": {"sections": rows, "peak": 16384}, "30": {"sections": rows, "peak": 30000}},
		"ps_tracks": {
			str(JIN_TRACK): {"sequence": 29, "first_section": 0, "advance": true},
			str(OGRE_TRACK): {"sequence": 30, "first_section": 0, "advance": false},
			str(TRUE_OGRE_TRACK): {"sequence": 30, "first_section": 1, "advance": true},
		},
	})
	director.sections.available = true
	director.music_available = true
	var variants := [{"file": "arrange", "loop": true, "volume": 127}, {"file": "arcade", "loop": true, "volume": 100}]
	director.tracks = {str(JIN_TRACK): variants, str(OGRE_TRACK): variants, str(TRUE_OGRE_TRACK): variants}
	director.soundtrack = AudioDirector.ARCADE
	return director


func _round(director: AudioDirector, track: int, round_number: int) -> int:
	director.fight_round = round_number
	director.play_music(track)
	return director.sections._variable


## Issue n0madic/Tekken3Remake#31: with the arcade's music converted, the ARCADE soundtrack plays a
## fight's track as the arcade BGM, and each later round writes its next section as the arcade does.
func test_each_later_round_moves_an_arcade_bgm_on() -> void:
	var director := _sections_director()
	expect_equal(_round(director, JIN_TRACK, 1), 0, "the first round: the intro")
	expect(director.sections.playing() and not director.music.playing, "the arcade BGM, not the stream")
	expect_equal(director.sections._current.number, 0)
	var written: Array[int] = []
	for r in range(2, 7):
		written.append(_round(director, JIN_TRACK, r))
	expect_equal(written, [1, 2, 3, 2, 3] as Array[int], "rounds 2–6")
	expect_equal(_round(director, JIN_TRACK, 1), 0, "a new match (or a continue) starts the BGM again")
	expect_equal(director.sections._current.number, 0)
	director.stop_all()
	director.free()


func test_the_ogre_fight_stays_in_its_intro_and_true_ogre_goes_on_from_section_1() -> void:
	var director := _sections_director()
	_round(director, OGRE_TRACK, 1)
	expect_equal(_round(director, OGRE_TRACK, 2), 0, "no section in the Ogre fight")
	expect_equal(_round(director, TRUE_OGRE_TRACK, 1), 1, "True Ogre starts in section 1")
	expect_equal(director.sections._current.number, 1)
	expect_equal(_round(director, TRUE_OGRE_TRACK, 2), 2)
	director.stop_all()
	director.free()


func test_the_bgm_takes_the_tracks_volume_and_its_fades() -> void:
	var director := _sections_director()
	_round(director, JIN_TRACK, 1)
	expect_equal(director.sections._gain, 100.0 / AudioDirector.VOLUME_MAX * AudioDirector.ARCADE_MUSIC_GAIN,
		"raised: its peak leaves room")
	_round(director, OGRE_TRACK, 1)
	expect(is_equal_approx(director.sections._gain, 100.0 / AudioDirector.VOLUME_MAX * SectionMusic.FULL_SCALE / 30000.0),
		"raised no further than its peak allows")
	director.fade_music(0, 0)
	expect_equal(director.sections._gain, 0.0, "faded out")
	director.play_music(-1)
	expect(not director.sections.playing(), "a stop stops it")
	director.stop_all()
	director.free()
