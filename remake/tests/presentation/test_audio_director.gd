extends TestSuite
## AudioDirector plays sound codes on emulated SPU voices as SoundPlayFighter does: the voice is
## keyed off before the key-on, so a code with no tone behind it still cuts the old sound.

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
