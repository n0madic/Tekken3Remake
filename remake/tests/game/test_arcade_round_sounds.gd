extends TestSuite
## ArcadeRoundSounds on made-up fights: when the fight's music and announcements are asked for.

const TRACK := 0x12
const ROUND_TWO_VOICE := 0x1234


func _fight() -> FightState:
	var fight := FightState.new(FightTables.new(), RuleSet.original())
	fight.tables.round_voices = PackedInt32Array([0, 0x1000, ROUND_TWO_VOICE, 0x1002])
	fight.round_state = ArcadeRoundSounds.ROUND_START
	fight.rounds_played = 1
	fight.max_rounds = 3
	return fight


## What a frame of the round start asks for, as [kind, a].
func _frame(sounds: ArcadeRoundSounds, fight: FightState, frame: int) -> Array:
	var events := SimEvents.new()
	fight.round_frame = frame
	sounds.step(fight, events)
	var rows: Array = []
	for e: SimEvents.Event in events.items:
		rows.append([e.kind, e.a])
	return rows


func _sounds() -> ArcadeRoundSounds:
	var sounds := ArcadeRoundSounds.new()
	sounds.stage_music = TRACK
	return sounds


func test_first_round_starts_the_track_on_its_frame() -> void:
	var sounds := _sounds()
	var fight := _fight()
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME - 1), [])
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [[SimEvents.Kind.MUSIC, TRACK]])
	expect_equal(sounds.track, TRACK)


func test_later_rounds_move_the_section_and_come_back_to_the_second() -> void:
	var sounds := _sounds()
	var fight := _fight()
	_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME)
	for expected: int in [1, 2, 3, 2, 3]:
		expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [[SimEvents.Kind.MUSIC_SECTION, expected]])


func test_the_round_calls_have_their_own_frames_in_the_first_round() -> void:
	var sounds := _sounds()
	var fight := _fight()
	var first: Array = ArcadeRoundSounds.CALL_FRAMES_FIRST
	expect_equal(_frame(sounds, fight, first[0] as int), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.CALL_ROUND]])
	expect_equal(_frame(sounds, fight, first[2] as int), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.CALL_FIGHT]])
	fight.rounds_played = 2
	var later: Array = ArcadeRoundSounds.CALL_FRAMES_LATER
	expect_equal(_frame(sounds, fight, later[1] as int), [[SimEvents.Kind.SOUND, ROUND_TWO_VOICE]])


func test_the_last_possible_round_is_called_final_without_a_number() -> void:
	var sounds := _sounds()
	var fight := _fight()
	fight.rounds_played = fight.max_rounds
	var later: Array = ArcadeRoundSounds.CALL_FRAMES_LATER
	expect_equal(_frame(sounds, fight, later[0] as int), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.CALL_FINAL]])
	expect_equal(_frame(sounds, fight, later[1] as int), [])


func test_the_true_ogre_writes_the_section_before_it_starts_the_ogres_track() -> void:
	var sounds := _sounds()
	sounds.stage_music = ArcadeRoundSounds.TRUE_OGRE_TRACK
	var fight := _fight()
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [
		[SimEvents.Kind.MUSIC_SECTION, 1], [SimEvents.Kind.MUSIC, ArcadeRoundSounds.OGRE_BGM]])


func test_the_ogres_track_keeps_its_section_until_the_scene() -> void:
	var sounds := _sounds()
	sounds.stage_music = ArcadeRoundSounds.OGRE_BGM
	var fight := _fight()
	_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME)
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [], "no section before the scene")
	fight.round_state = ArcadeRoundFlow.OGRE_SCENE_STATE
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.MUSIC_SECTION, 1]])
	expect_equal(_frame(sounds, fight, 1), [], "once per scene")
	fight.round_state = ArcadeRoundSounds.ROUND_START
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [[SimEvents.Kind.MUSIC_SECTION, 2]])


func test_a_silent_game_asks_for_nothing() -> void:
	var sounds := _sounds()
	sounds.silent = true
	var fight := _fight()
	expect_equal(_frame(sounds, fight, ArcadeRoundSounds.BGM_FRAME), [])
	expect_equal(sounds.track, 0)


func test_a_new_match_stops_the_old_music_at_its_first_round_only() -> void:
	var sounds := _sounds()
	sounds.before_load()
	sounds.after_load()
	var events := SimEvents.new()
	sounds.round_start(events)
	var kinds: Array = []
	for e: SimEvents.Event in events.items:
		kinds.append(e.kind)
	expect_equal(kinds, [SimEvents.Kind.VOICE_OFF, SimEvents.Kind.MUSIC_STOP])
	events.clear()
	sounds.round_start(events)
	expect_equal(events.items.size(), 1, "only the players' silence")


func test_after_the_ogre_scene_the_load_keeps_the_music() -> void:
	var sounds := _sounds()
	sounds.ogre_section = 1
	sounds.before_load()
	sounds.after_load()
	var events := SimEvents.new()
	sounds.round_start(events)
	expect_equal(events.items.size(), 1, "only the players' silence")
	expect_equal(sounds.ogre_section, 0)


func test_the_result_is_called_once() -> void:
	var sounds := _sounds()
	var fight := _fight()
	fight.round_state = ArcadeRoundSounds.ROUND_RESULT
	fight.result_flags = ArcadeRoundSounds.RESULT_TIME_UP
	fight.round_counter = 1
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.VOICE_TIME_UP]])
	fight.round_counter = 2
	expect_equal(_frame(sounds, fight, 0), [])
	fight.round_counter = 1
	fight.result_flags = 0
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.VOICE_KO]])


func test_the_winner_call_follows_who_plays() -> void:
	var sounds := _sounds()
	var fight := _fight()
	fight.round_state = ArcadeRoundSounds.ROUND_WINNER_A
	fight.round_counter = 1
	fight.match_result = 1
	fight.human_mask = 1
	fight.fighters[0].round_won = 1
	fight.fighters[1].round_won = 0
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.VOICE_YOU_WIN]])
	fight.human_mask = 2
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.VOICE_YOU_LOSE]])
	fight.fighters[1].round_won = 1
	expect_equal(_frame(sounds, fight, 0), [[SimEvents.Kind.SOUND, ArcadeRoundSounds.VOICE_DRAW]])
