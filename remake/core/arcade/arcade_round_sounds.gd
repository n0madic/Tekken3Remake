class_name ArcadeRoundSounds
extends RefCounted
## The fight's announcements and BGM: the sound half of FUN_8019DCA8 (the HUD draws its texts) and
## FUN_8019EED4. The BGM starts on frame 3 of the first round; each later round writes the section
## variable, which the sequence answers by itself at a bar of its own (ArcadeAudio plays that). Only
## SimEvents leave here: no state of the fight depends on it, and it draws no random numbers.

const BGM_FRAME := 3
const CALL_FRAMES_FIRST := [0x3D, 100, 0x96]    ## "round", its number, "fight" in the first round
const CALL_FRAMES_LATER := [1, 0x28, 0x5A]      ## and in the later ones
const CALL_ROUND := 0x103B
const CALL_FINAL := 0x103A
const CALL_FIGHT := 0x103C
const RESULT_PERFECT_A := 1                     ## result_flags
const RESULT_PERFECT_B := 8
const RESULT_TIME_UP := 4
const RESULT_DOUBLE := 0x10
const VOICE_PERFECT_A := 0x1013
const VOICE_PERFECT_B := 0x1019
const VOICE_TIME_UP := 0x1015
const VOICE_DOUBLE := 0x1018
const VOICE_KO := 0x101A
const VOICE_DRAW := 0x1014
const VOICE_YOU_WIN := 0x1011
const VOICE_YOU_LOSE := 0x1012
const WINNER_NAME_ID := 4                       ## the voice set's fifth id: the character's name
const BOTH_HUMANS := 3
const OGRE_BGM := 0x1E
const TRUE_OGRE_TRACK := 1                      ## plays the Ogre's sequence; the script clears the section written just before
const SECTION_LAST := 3
const SECTION_AGAIN := 2
const ROUND_START := 0                          ## fight.round_state
const ROUND_RESULT := 2
const ROUND_WINNER_A := 6
const ROUND_WINNER_B := 7

var stage_music := 0                ## 0x8021FBD4: the track of the fight
var track := 0                      ## 0x8021F0E4: the one playing
var section := 0                    ## 0x8021F0DC
var ogre_section := 0               ## 0x8021F0D4: the Ogre scene moved its section on
var stop_on_round := 0              ## 0x8021F048: the new match's first round stops the old music
var silent := false                 ## 0x8021FC64 or 0x8021FB70: the attract, or a challenger's freeze
var _in_ogre_scene := false


## FUN_8018A44C, before and after the fighters load (FUN_8019EE54).
func before_load() -> void:
	stop_on_round = 1 if ogre_section == 0 else 0


func after_load() -> void:
	ogre_section = 0
	section = 0
	track = 0


## FUN_8018A6D0: every player channel falls silent (FUN_8018C8BC's FUN_801B0B14), and the old music.
func round_start(events: SimEvents) -> void:
	events.add(SimEvents.Kind.VOICE_OFF, -1, 0)
	if stop_on_round != 0:
		events.add(SimEvents.Kind.MUSIC_STOP, -1)
	stop_on_round = 0


## After the round flow's step of the frame.
func step(fight: FightState, events: SimEvents) -> void:
	var scene := fight.round_state == ArcadeRoundFlow.OGRE_SCENE_STATE
	if scene and not _in_ogre_scene:
		# FUN_8019EE9C.
		section = 1
		ogre_section = 1
		events.add(SimEvents.Kind.MUSIC_SECTION, -1, section)
	_in_ogre_scene = scene
	if silent or fight.replay_playing != 0:
		return
	match fight.round_state:
		ROUND_START:
			if fight.round_frame != 0:
				_round_start_calls(fight, events)
		ROUND_RESULT:
			if fight.round_counter == 1:
				events.add(SimEvents.Kind.SOUND, -1, _result_voice(fight.result_flags), 0)
		ROUND_WINNER_A, ROUND_WINNER_B:
			if (fight.match_result != 0 or fight.replay_skip == 0) and fight.round_counter == 1:
				events.add(SimEvents.Kind.SOUND, -1, _winner_voice(fight), 0)


## FUN_8019DEC4.
func _round_start_calls(fight: FightState, events: SimEvents) -> void:
	var frame := fight.round_frame
	if frame == BGM_FRAME:
		_bgm(events)
	var calls: Array = CALL_FRAMES_FIRST if fight.rounds_played == 1 else CALL_FRAMES_LATER
	var has_number := fight.rounds_played < fight.max_rounds
	if frame == (calls[0] as int):
		events.add(SimEvents.Kind.SOUND, -1, CALL_ROUND if has_number else CALL_FINAL, 0)
	if frame == (calls[1] as int) and has_number:
		events.add(SimEvents.Kind.SOUND, -1, fight.tables.round_voices[fight.rounds_played], 0)
	if frame == (calls[2] as int):
		events.add(SimEvents.Kind.SOUND, -1, CALL_FIGHT, 0)


## FUN_8019EED4.
func _bgm(events: SimEvents) -> void:
	if track == stage_music:
		if stage_music != OGRE_BGM or ogre_section != 0:
			section += 1
			if section > SECTION_LAST:
				section = SECTION_AGAIN
			events.add(SimEvents.Kind.MUSIC_SECTION, -1, section)
		return
	track = stage_music
	if stage_music != TRUE_OGRE_TRACK:
		events.add(SimEvents.Kind.MUSIC, -1, stage_music)
	elif ogre_section == 0:
		section = 1
		events.add(SimEvents.Kind.MUSIC_SECTION, -1, section)
		events.add(SimEvents.Kind.MUSIC, -1, OGRE_BGM)


## FUN_8019E1F0.
func _result_voice(flags: int) -> int:
	if flags & RESULT_PERFECT_A:
		return VOICE_PERFECT_A
	if flags & RESULT_PERFECT_B:
		return VOICE_PERFECT_B
	if flags & RESULT_TIME_UP:
		return VOICE_TIME_UP
	if flags & RESULT_DOUBLE:
		return VOICE_DOUBLE
	return VOICE_KO


## FUN_8019E318.
func _winner_voice(fight: FightState) -> int:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	if f0.round_won == f1.round_won:
		return VOICE_DRAW
	var winner := 0 if f1.round_won < f0.round_won else 1
	if fight.human_mask == BOTH_HUMANS or fight.mode == GameMode.TEAM:
		return fight.tables.voices[fight.fighters[winner].voice_set].ids[WINNER_NAME_ID]
	return VOICE_YOU_WIN if (fight.human_mask >> winner) & 1 else VOICE_YOU_LOSE
