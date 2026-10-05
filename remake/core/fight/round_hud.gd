class_name RoundHud
extends RefCounted
## HudRoundUpdate (0x8003D904), the round part: the announcer's voices (SimEvents, run by the
## simulation) and the round messages (read by the presentation each frame). The bars, timer and
## round marks the same routine draws are plain FightState fields. See hud.md.

const TIGER_KEY := 0x22
const VOICE_WIN := 0xC640
const VOICE_WIN_BOSS := 0xC64B       ## voice set 0x15

const TIME_UP := 1
const DOUBLE_KO := 4
const PERFECT := 8
const GREAT := 0x10

const FIRST_ROUND_INTRO := 0x3D     ## round frame of the intro voice in round 1 (1 later)
const FIRST_ROUND_NUMBER := 100     ## round frame of "ROUND n" in round 1 (0x28 later)
const LATER_ROUND_NUMBER := 0x28
const FIRST_ROUND_FIGHT := 0x96     ## round frame of "FIGHT" in round 1 (0x5A later)
const LATER_ROUND_FIGHT := 0x5A
const FIRST_ROUND_TITLE := 0x3D     ## "ROUND n" is shown from this round frame (1 later)
const FIRST_ROUND_READY := 0x6A     ## "READY?" is shown from this round frame (0x2E later)
const LATER_ROUND_READY := 0x2E

const VOICE_INTRO := 0x103B         ## before the round number (0x103A in the last round)
const VOICE_INTRO_LAST := 0x103A
const VOICE_FIGHT := 0x103C
const VOICE_WINS := 0x1011
const VOICE_LOSES := 0x1012
const VOICE_DRAW := 0x1014
const VOICE_SET_15 := 0x15           ## the voice set of the bosses with their own win voice
const MUSIC_FADE_FRAMES := 0xB4
const BAR_LENGTH := 0x98            ## health bar pixels
const BAR_GROWTH := 3               ## pixels per frame a bar refills

## One line of text: the game's FUN_8004D15C(text, palette, font, x, y) in 368 × 480 screen units.
class Message:
	var text: String
	var palette: int
	var font: int
	var x: int
	var y: int

	func _init(message_text: String, message_palette: int, message_font: int, at_x: int, at_y: int) -> void:
		text = message_text
		palette = message_palette
		font = message_font
		x = at_x
		y = at_y


## The voices of the frame. FightFrame calls it after the round flow, before the camera, unless
## a replay plays (also on paused frames).
static func update(fight: FightState, events: SimEvents) -> void:
	# The demonstration fight (attract flag) and a challenger's entrance have no announcements.
	if fight.attract == 0 and fight.challenger == 0:
		match fight.round_state:
			RoundState.INTRO:
				if fight.round_frame != 0:
					_round_start_voices(fight, events)
			RoundState.RESULT:
				if (fight.mode != GameMode.FORCE or fight.result_flags & TIME_UP != 0) and fight.pause_request == 0:
					_result_voice(fight, events)
			RoundState.WIN_WAIT, RoundState.END:
				if fight.mode != GameMode.FORCE and fight.mode != GameMode.PRACTICE \
						and (fight.match_result != 0 or fight.replay_skip == 0 or fight.pause_request != 0):
					_winner_voice(fight, events)
	if fight.hud_shown != 0:
		if fight.mode == GameMode.FORCE:
			fight.force.bars_step()
		else:
			_bars(fight)


## FUN_8004E520: the bars start empty at a round start and refill.
static func reset_bars(fight: FightState) -> void:
	for p in 2:
		fight.hud_bars[p] = PackedInt32Array([0, 0, 0, 0])


## FUN_8004E55C: the health bars' lengths. A drop shows at once, a refill grows 3 pixels per
## frame, and the recent-damage part closes 1/16 of its length (rounded up) per frame.
static func _bars(fight: FightState) -> void:
	for p in 2:
		var f := fight.fighters[p]
		var bar := fight.hud_bars[p]
		var target := bar[1]
		var step := Fx.div_trunc(f.health_max, BAR_LENGTH)
		if bar[0] != f.health:
			bar[0] = f.health
			target = Fx.div_trunc(f.health - 1 + step, step)
		target = mini(target, BAR_LENGTH)
		var drawn := bar[2]
		var recent := drawn
		if drawn < bar[3]:
			recent = bar[3] - ((bar[3] - drawn + 0xF) >> 4)
		var grown := target
		if target > drawn and drawn + BAR_GROWTH <= target:
			grown = drawn + BAR_GROWTH
		recent = maxi(recent, grown)
		fight.hud_bars[p] = PackedInt32Array([bar[0], Fx.s16(target), Fx.s16(grown), Fx.s16(recent)])


## The messages shown this frame.
static func messages(fight: FightState) -> Array[Message]:
	var out: Array[Message] = []
	if fight.mode == GameMode.DEMO:                # the demonstration fight shows GAME OVER
		out.append(Message.new("GAME OVER", 2, 1, 0x7E, 0x104))
	if fight.attract != 0 or fight.challenger != 0:
		return out
	match fight.round_state:
		RoundState.INTRO:
			if fight.round_frame != 0:
				_round_start_messages(fight, out)
		RoundState.RESULT:
			if fight.mode != GameMode.FORCE or fight.result_flags & TIME_UP != 0:
				_result_message(fight, out)
		RoundState.WIN_WAIT, RoundState.END:
			if fight.mode != GameMode.FORCE and fight.mode != GameMode.PRACTICE:
				_winner_messages(fight, out)
		RoundState.STAGE_CLEAR:
			out.append(Message.new("STAGE CLEAR!!", 8, 2, 0x29, 0x70))
	return out


# ---- voices ---------------------------------------------------------------------------------

## FUN_8003DCE0: the intro voice, "ROUND n" and "FIGHT".
static func _round_start_voices(fight: FightState, events: SimEvents) -> void:
	var first := fight.rounds_played == 1
	var intro := fight.round_frame == (FIRST_ROUND_INTRO if first else 1)
	match fight.mode:
		GameMode.TEAM, GameMode.SURVIVAL:
			# The USA version says nothing here (usa-version.md); the remake keeps Japan Rev.1's
			# behaviour in both text regions.
			if intro:
				_announce(VOICE_INTRO, events)
		GameMode.PRACTICE:
			if intro:
				win_voice(fight, 1 if fight.human_mask & 1 == 0 else 0, events)
		GameMode.FORCE:
			if intro:
				win_voice(fight, fight.force.player().player_index, events)
		_:
			var last := fight.max_rounds <= fight.rounds_played
			if intro:
				_announce(VOICE_INTRO_LAST if last else VOICE_INTRO, events)
			if fight.round_frame == (FIRST_ROUND_NUMBER if first else LATER_ROUND_NUMBER) and not last:
				_announce(fight.tables.round_voices[fight.rounds_played], events)
	if fight.round_frame == (FIRST_ROUND_FIGHT if first else LATER_ROUND_FIGHT):
		_announce(VOICE_FIGHT, events)


## ResultWinVoice (0x80075A90): the fighter's victory voice (none for Tiger); true when played.
static func win_voice(fight: FightState, index: int, events: SimEvents) -> bool:
	var f := fight.fighters[index]
	if f.costume_key == TIGER_KEY:
		return false
	events.add(SimEvents.Kind.SOUND, -1, VOICE_WIN_BOSS if f.voice_set == VOICE_SET_15 else VOICE_WIN, f.player_index)
	return true


## FUN_8003E158: the result's sound on the first frame of round state 2.
static func _result_voice(fight: FightState, events: SimEvents) -> void:
	if fight.round_counter != 1:
		return
	var voices := fight.tables.result_voices
	var code := voices[0]
	var flags := fight.result_flags
	if flags & TIME_UP == 0:
		code = voices[6]
		if flags & PERFECT == 0:
			code = voices[2]
			if flags & DOUBLE_KO == 0:
				code = voices[7]
				if flags & GREAT != 0:
					code = voices[5]
	events.add(SimEvents.Kind.SOUND, 0, code, 0)


## FUN_8003E2F8: the winner's announcement on the first frame of the result display; the
## music fades out when the match is decided.
static func _winner_voice(fight: FightState, events: SimEvents) -> void:
	if fight.round_counter != 1:
		return
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var fade := fight.match_result != 0
	if f0.round_won == f1.round_won:
		_announce(VOICE_DRAW, events)
	else:
		var winner := 0 if f1.round_won < f0.round_won else 1
		if fight.human_mask == 3 or fight.mode == GameMode.TEAM:
			if win_voice(fight, winner, events):
				EffectObjects.announcer_follow_up(fight)
			else:
				_announce(VOICE_WINS, events)
		elif (fight.human_mask >> winner) & 1 == 0:
			_announce(VOICE_LOSES, events)
			if fight.team_round == 0:
				fade = false
		else:
			_announce(VOICE_WINS, events)
	if fade:
		# FUN_8006B9B0 also sets the music state 0x800A0980 to 3 (fading out).
		events.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0, MUSIC_FADE_FRAMES)


## FUN_80040E98: an announcer sound (SoundPlaySystem of the code's low 12 bits).
static func _announce(code: int, events: SimEvents) -> void:
	events.add(SimEvents.Kind.SYSTEM_SOUND, -1, code & 0xFFF)


# ---- messages -------------------------------------------------------------------------------

## FUN_8003DF60: the round title and "READY?".
static func _round_start_messages(fight: FightState, out: Array[Message]) -> void:
	var first := fight.rounds_played == 1
	match fight.mode:
		GameMode.TEAM:
			out.append(Message.new("TEAM BATTLE", 8, 2, 0x3F, 0x70))
		GameMode.SURVIVAL:
			out.append(Message.new("SURVIVAL BATTLE", 8, 2, 0x13, 0x70))
		GameMode.PRACTICE:
			out.append(Message.new("PRACTICE MODE", 8, 2, 0x29, 0x70))
		GameMode.FORCE:
			if fight.region.fight_index > 3:
				out.append(Message.new("FINAL STAGE", 8, 2, 0x3F, 0x70))
			else:
				out.append(Message.new("STAGE %x" % (fight.region.fight_index + 1), 8, 2, 0x6B, 0x70))
		_:
			if fight.max_rounds <= fight.rounds_played:
				out.append(Message.new("FINAL ROUND", 8, 2, 0x3F, 0x70))
			elif fight.round_frame >= (FIRST_ROUND_TITLE if first else 1):
				out.append(Message.new("ROUND %x" % fight.rounds_played, 8, 2, 0x6B, 0x70))
	if fight.round_frame >= (FIRST_ROUND_READY if first else LATER_ROUND_READY):
		out.append(Message.new("READY?", 9, 2, 0x76, 0xE4))


## FUN_8003E200: the round result.
static func _result_message(fight: FightState, out: Array[Message]) -> void:
	if fight.replay_request != 0:
		return
	var region := fight.region
	if fight.mode == GameMode.BALL and region.ctx_s32(TekkenBall.LAST_POINT) < region.ctx_s32(TekkenBall.RESULT) - 1:
		# Tekken Ball shows the result with its last replay.
		return
	var flags := fight.result_flags
	if flags & TIME_UP != 0:
		out.append(Message.new("TIME UP", 3, 2, 0x6B, 0xE4))
	elif flags & PERFECT != 0:
		out.append(Message.new("PERFECT!", 2, 2, 0x60, 0xE4))
	elif flags & DOUBLE_KO != 0:
		out.append(Message.new("DOUBLE K.O.", 1, 2, 0x3F, 0xE4))
	else:
		out.append(Message.new("K.O.", 1, 2, 0x8C, 0xE4))


## FUN_8003E408: the winner of the round.
static func _winner_messages(fight: FightState, out: Array[Message]) -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	if f0.round_won == f1.round_won:
		out.append(Message.new("DRAW", 6, 2, 0x8C, 0x170))
		return
	var winner := 1 if f0.round_won <= f1.round_won else 0
	if fight.human_mask == 3 or fight.mode == GameMode.TEAM:
		var f := fight.fighters[winner]
		var name: String = fight.tables.character(f.costume_key)["name"]
		var x := Fx.s16(0xB8 - (name.length() * 0xB + 0x42))
		out.append(Message.new("%s WINS!" % name, 4, 2, x, 0x170))
		if fight.match_result != 0 and fight.mode == GameMode.ARCADE:
			out.append(Message.new("WINNER", 9, 1, winner * 0xC4 + 0x2F, 0x68))
			out.append(Message.new("LOSER", 9, 1, (1 - winner) * 0xC3 + 0x36, 0x68))
	elif (fight.human_mask >> winner) & 1 == 0:
		out.append(Message.new("YOU LOSE", 5, 2, 0x60, 0x170))
	else:
		out.append(Message.new("YOU WIN!", 4, 2, 0x60, 0x170))
