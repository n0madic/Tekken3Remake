class_name ResultScreens
extends FlowPart
## The result screens of result.ovl (modes.md#result-screens), written from the verified ports in
## `tools/research/screens_sim.py`: team battle (FUN_800EF4AC, game state 12), time attack
## (FUN_800EFF4C, state 13), survival (FUN_800F0A78, state 14) and Tekken Force (FUN_800F1F08,
## state 15, `force_result` in the same file). Their state is kept as the overlay's bytes
## (0x800FAC48 … 0x800FAE7C), as the flow traces record it.

const BASE := 0x800FAC48
const SIZE := 0x238
const BANNER_BASE := 0x80102690
# Team battle.
const T_FIGHT := 0x00
const T_LOST1 := 0x08
const T_LOST2 := 0x0C
const T_LEFT1 := 0x10
const T_LEFT2 := 0x14
const T_MSG := 0x18
const T_SLIDE := 0x1C
const T_LINE := 0x20
const T_MEMBER1 := 0x30              ## s32 per fight: player 1's members lost before it
const T_MEMBER2 := 0xE0
# Time attack.
const A_ROWS := 0x190
const A_ROW_ANIM := 0x194
const A_RECORD := 0x198
const A_PLAYER := 0x19C
const A_KEY := 0x1A0
const A_TOTAL := 0x1A4
const A_SHOW := 0x1A8
const A_WAIT := 0x1AC
const A_FRAME := 0x1B0
# Survival.
const S_COUNT := 0x1B8
const S_CHARS := 0x1C8               ## u8 per row: the characters beaten, most first
const S_ROW := 0x1E0
const S_PLAYER := 0x1E4
const S_RANK := 0x1E8
const S_KEY := 0x1EC
const S_FLAG := 0x1F0
const S_WAIT := 0x1F4
const S_TOTAL := 0x1F8
const S_FRAME := 0x1FC
const S_ANIM := 0x200
# Tekken Force.
const F_TEX := 0x208                 ## 4 × u16: the player's big picture slot (0x800FAC34 per side)
const F_COLOUR := 0x210              ## the picture's tint
const F_FLIP := 0x214                ## u8: mirrored
const F_FRAME := 0x218
const F_SHOWN := 0x21C               ## frames since the fade-in ended: the lines appear by it
const F_BOSS := 0x220                ## the bosses beaten appear by it
const F_PHASE := 0x224               ## the FORCE count: 0 wait, 1 counting, 2 done
const F_FORCE := 0x228               ## the counted enemies
const F_TEX_SLOTS := 0x800FAC34      ## result.ovl
const F_SCORE_AT := 0x1E             ## YOUR SCORE (then HIGH SCORE, the keys or bosses, 30 frames apart)
const F_HIGH_AT := 0x3C
const F_LIST_AT := 0x5A
const F_KEY_AT := [0x5A, 0x78, 0x96]  ## COPPER, SILVER, GOLD
const F_BOSS_AT := [0x14, 0x28, 0x3C]  ## the second to fourth boss
const F_COUNT_AFTER := 0x4F
const F_WAIT := 0x1248
const F_FADE_MUSIC := 0xB4
const SOUND_LINE := 0x4C6C           ## a result line appears
const FORCE_SCORE := 0x38            ## mode context: the score, the enemies, the player, a new record
const FORCE_COUNT := 0x3C
const FORCE_PLAYER := 0x3E
const FORCE_FLAGS := 0x40            ## 1 copper, 2 silver, 4 gold key; 8 the doctor saved; 0x10 bosses
const FORCE_DOCTOR := 8
const FORCE_BOSSES := 0x10
const BRIGHT := 0x230                ## s32 screen brightness (0x100 full)
const RESULT_WAIT := 0x1248          ## 4,680 frames
const TEAM_WAIT := 0x707
const TIME_CAP := 359_999
const SOUND_AFTER_VOICE := 0x86DA
const SEQ_DELAY := 15
const MUSIC_RESULT := 6
const SOUND_TICK := 0x55F5          ## each fight line, stage row and win counted
const SOUND_REVEAL := 0x50F4        ## the team message and the survival rank appear

var state := ByteBlock.new(SIZE)
var banner := ByteBlock.new(8)       ## 0x80102690: the scrolling banner's x, y
var seq_state := 0                   ## 0x800A37A8: the victory voice's sequence
var seq_delay := 0                   ## 0x800A37A9


func brightness() -> int:
	return state.s32(BRIGHT)


func _get32(at: int) -> int:
	return state.s32(at)


func _put(at: int, v: int) -> void:
	state.put32(at, v)


func _ctx8(at: int) -> int:
	return g.region.ctx8(at)


func _fade_in(next_sub: int) -> void:
	var b := _get32(BRIGHT) + 8
	if b < 0x100:
		_put(BRIGHT, b)
		return
	_put(BRIGHT, 0x100)
	g.sub = next_sub


func _fade_out(next_sub: int) -> void:
	var b := _get32(BRIGHT) - 4
	if b < 1:
		b = 0
		g.sub = next_sub
	_put(BRIGHT, b)


## FUN_800F18FC's state: the scrolling tiles and banner.
func _banner_scroll() -> void:
	banner.put32(0, (banner.u32(0) + 0x17F) % 0x180)
	banner.put32(4, (banner.u32(4) + 0x342) % 0x344)


# ---- the victory voice (FUN_80075A90, FUN_80075B1C, FUN_80075B4C) ------------------------

func _seq_reset() -> void:
	seq_state = 0
	seq_delay = SEQ_DELAY


## ResultWinVoice: the winner's victory voice (none for Tiger), then the sequence goes on.
func _result_sounds(player: int) -> void:
	if RoundHud.win_voice(g.fight, player, g.sim.events):
		seq_state += 1


## After the voice (the SPU's voice 2 is never reported busy here) and 15 frames, sound 0x86DA.
func _seq_tick() -> void:
	match seq_state:
		1:
			seq_state = 2
		2:
			seq_state = 3
		3:
			seq_delay = (seq_delay - 1) & 0xFF
			if seq_delay != 0 and seq_delay < 0x80:
				return
			g.sound(SOUND_AFTER_VOICE)
			seq_state = 0


# ---- team battle (game state 12) ---------------------------------------------------------

func team_step() -> void:
	if g.menu_exit():
		return
	var sub := g.sub
	if sub > 1:
		for p in 2:
			if g.pressed(p) & PadState.START:
				g.globals.player_active[p] = 1
				g.globals.set_tie_winner(g.fight, p)
				g.sub = 10
		sub = g.sub
	var timer := g.sim.state_timer
	match sub:
		0:
			_team_setup()
		1:
			_fade_in(2)
		2:
			_team_line()
		3:
			timer += 1
			g.sim.state_timer = timer
			if timer >= 2:
				g.sound(SOUND_TICK)
				_put(T_LINE, 0)
				var fight := _get32(T_FIGHT) + 1
				_put(T_FIGHT, fight)
				g.sub = 4 if _ctx8(ModeRules.TEAM_ROUND) <= fight else 2
		4, 5:
			if sub == 4:
				_put(T_MSG, 1)
				_put(T_SLIDE, 0x1E)
				g.sub = 5
			var slide := _get32(T_SLIDE) - 1
			if slide < 1:
				slide = 0
				g.sound(SOUND_REVEAL)
				g.sub = 6
			_put(T_SLIDE, slide)
		6, 7:
			_team_wait(sub == 6)
		8:
			_fade_out(9)
		9:
			g.state = GameFlow.State.RANKING_LOAD
			g.sub = 0
		10:
			g.state = GameFlow.State.FIGHT
			g.sub = 0
	_banner_scroll()


## Team battle's result: the members' outcomes and the teams' sizes.
func _team_setup() -> void:
	g.music(MUSIC_RESULT)
	g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 1)
	var region := g.region
	var a := 0
	var b := 0
	for k in _ctx8(ModeRules.TEAM_ROUND):
		_put(T_MEMBER1 + 4 * k, b)
		_put(T_MEMBER2 + 4 * k, a)
		var code := region.ctx16(ModeRules.TEAM_OUTCOMES + 2 * k)
		if code == 1 or code == 3:
			a += 1
		if code == 2 or code == 3:
			b += 1
	for at: int in [T_FIGHT, BRIGHT, T_LOST1, T_LOST2, T_LINE, T_MSG, T_SLIDE]:
		_put(at, 0)
	g.sub = 1
	_put(T_LEFT1, _ctx8(ModeRules.TEAMS + 0xC))
	_put(T_LEFT2, _ctx8(ModeRules.TEAMS + ModeRules.TEAM_SIZE + 0xC))


## The joining line of the current fight grows; at its end the loser's member is crossed out.
func _team_line() -> void:
	var region := g.region
	var line := _get32(T_LINE) + 1
	_put(T_LINE, line)
	if line >= 9:
		_put(T_LINE, 8)
		var code := region.ctx16(ModeRules.TEAM_OUTCOMES + 2 * _get32(T_FIGHT))
		if code == 1 or code == 3:
			_put(T_LOST2, _get32(T_LOST2) + 1)
			_put(T_LEFT2, _get32(T_LEFT2) - 1)
		if code == 2 or code == 3:
			_put(T_LOST1, _get32(T_LOST1) + 1)
			_put(T_LEFT1, _get32(T_LEFT1) - 1)
		g.sim.state_timer = 0
		g.sub = 3


## The result holds: face buttons switch the message, Select shows it again, the wait ends it.
func _team_wait(first: bool) -> void:
	var timer := g.sim.state_timer
	if first:
		timer = 0
		g.sim.state_timer = 0
		g.sub = 7
	var pads := g.pressed_any()
	if pads == PadState.SELECT:
		g.sub = 0
	else:
		if pads & GameFlow.FACE_BUTTONS:
			_put(T_MSG, (_get32(T_MSG) + 1) & 1)
		timer += 1
		g.sim.state_timer = timer
		if timer > TEAM_WAIT:
			_put(T_MSG, 0)
			_put(BRIGHT, 0x100)
			g.sub = 8


# ---- time attack (game state 13) ---------------------------------------------------------

func time_attack_step() -> void:
	_put(A_FRAME, _get32(A_FRAME) + 1)
	var sub := g.sub
	if g.pressed_any() & PadState.START and ((sub - 2) & 0xFFFFFFFF) < 5:
		sub = 7
		g.sub = 7
	var timer := g.sim.state_timer
	match sub:
		0:
			g.attract_advance()
			g.music(MUSIC_RESULT)
			for at: int in [A_FRAME, A_ROWS, A_ROW_ANIM, A_SHOW, BRIGHT, A_WAIT]:
				_put(at, 0)
			_put(A_TOTAL, _total_time())
			_put(A_RECORD, g.progress.name_entry & 1)
			g.sub = 1
			_put(A_PLAYER, g.region.ctx32(0x38))
			_put(A_KEY, g.region.ctx32(0x3C))
			_seq_reset()
		1:
			_fade_in(2)
		2:
			var anim := _get32(A_ROW_ANIM) + 1
			_put(A_ROW_ANIM, anim)
			if anim > 0x10:
				g.sound(SOUND_TICK)
				g.sim.state_timer = 0
				_put(A_ROW_ANIM, 0)
				g.sub = 3
				_put(A_ROWS, _get32(A_ROWS) + 1)
		3:
			timer += 1
			g.sim.state_timer = timer
			if timer >= 6:
				g.sub = 4 if _get32(A_ROWS) > 9 else 2
		4, 5:
			if sub == 4:
				_put(A_SHOW, 1)
				_put(A_WAIT, 0x1E)
				g.sub = 5
			var wait := _get32(A_WAIT) - 1
			_put(A_WAIT, wait)
			if wait < 1:
				_put(A_WAIT, 0)
				g.sound(SOUND_TICK)
				_result_sounds(_get32(A_PLAYER))
				g.sub = 6
		6, 7:
			var stay := false
			if sub == 6:
				if g.pressed(_get32(A_PLAYER)) & GameFlow.FACE_BUTTONS:
					_put(A_SHOW, (_get32(A_SHOW) + 1) & 1)
				stay = _get32(A_FRAME) < RESULT_WAIT
			if not stay:
				_put(A_SHOW, 0)
				_put(BRIGHT, 0x100)
				g.sub = 8
		8:
			_fade_out(9)
		9:
			g.state = GameFlow.State.RANKING_LOAD
			g.sub = 0
	_seq_tick()


## FUN_800F28E8: the ten stage times of the run, capped.
func _total_time() -> int:
	var total := 0
	for k in 10:
		total += g.region.ctx32(ModeRules.STAGE_RECORDS + 8 * k)
	total = Fx.w32(total & 0xFFFFFFFF)
	return mini(total, TIME_CAP)


# ---- survival (game state 14) ------------------------------------------------------------

func survival_step() -> void:
	_put(S_FRAME, _get32(S_FRAME) + 1)
	var sub := g.sub
	if g.pressed_any() & PadState.START and ((sub - 2) & 0xFFFFFFFF) < 6:
		sub = 8
		g.sub = 8
	match sub:
		0:
			_survival_setup()
		1:
			var b := _get32(BRIGHT) + 8
			_put(BRIGHT, b)
			if b > 0xFF:
				_put(BRIGHT, 0x100)
				g.sub = 2
				_put(S_ROW, 0)
				_put(S_ANIM, 0)
				if _get32(S_COUNT) < 1:
					g.sub = 4
					_put(S_ROW, _get32(S_COUNT))
		2, 3:
			_survival_count(sub == 2)
		4:
			g.sim.state_timer = 4
			g.sub = 5
		5, 6:
			if sub == 5:
				_put(S_FLAG, 2)
				_put(S_WAIT, 0x1E)
				g.sub = 6
			var wait := _get32(S_WAIT) - 1
			_put(S_WAIT, wait)
			if wait == 0:
				g.sound(SOUND_REVEAL)
				if state.u32(S_RANK) != 0:
					_result_sounds(_get32(S_PLAYER))
				g.sub = 7
		7, 8:
			if sub == 8 or _get32(S_FRAME) >= RESULT_WAIT:
				# FUN_8006B9B0: the music fades out over 180 frames.
				g.music_volume(0, 0xB4)
				_put(S_FLAG, 0)
				_put(BRIGHT, 0x100)
				g.sub = 9
		9:
			_fade_out(10)
		10:
			g.state = GameFlow.State.RANKING_LOAD
			g.sub = 0
		11:
			g.state = GameFlow.State.FIGHT
			g.sub = 0
	_seq_tick()
	_banner_scroll()


## Survival's result: the characters beaten, most wins first, and the rank.
func _survival_setup() -> void:
	var region := g.region
	g.attract_advance()
	g.music(MUSIC_RESULT)
	g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 1)
	_seq_reset()
	var pairs: Array[Vector2i] = []
	for c in Opponents.CHARACTERS:
		var wins := region.ctx16(Opponents.SURVIVAL_MET + 2 * c)
		if wins != 0:
			pairs.append(Vector2i(c, wins))
	_put(S_COUNT, pairs.size())
	Opponents.sort_pairs(pairs, false)
	for i in pairs.size():
		state.put8(S_CHARS + i, pairs[i].x)
	for at: int in [S_FRAME, BRIGHT, S_ROW, S_TOTAL]:
		_put(at, 0)
	g.sim.state_timer = 0
	_put(S_FLAG, 2)
	_put(S_WAIT, 0x1E)
	g.sub = 1
	_put(S_PLAYER, region.ctx32(0x38))
	_put(S_KEY, region.ctx32(0x3C))
	_put(S_RANK, region.ctx32(ModeRules.SURVIVAL_RANK))


## The rows count up one win every 4 frames, a tick each, row by row.
func _survival_count(first: bool) -> void:
	var region := g.region
	var timer := g.sim.state_timer
	if first:
		_put(S_ANIM, 1)
		timer = 4
		g.sub = 3
		_put(S_TOTAL, _get32(S_TOTAL) + 1)
	timer -= 1
	g.sim.state_timer = timer
	if timer < 1:
		g.sound(SOUND_TICK)
		var c := state.u8(S_CHARS + _get32(S_ROW))
		if state.u32(S_ANIM) < region.ctx16(Opponents.SURVIVAL_MET + 2 * c):
			g.sim.state_timer = 4
			_put(S_ANIM, state.u32(S_ANIM) + 1)
			_put(S_TOTAL, _get32(S_TOTAL) + 1)
		else:
			var row := _get32(S_ROW) + 1
			_put(S_ROW, row)
			g.sim.state_timer = 0
			if row < _get32(S_COUNT):
				g.sub = 2
			else:
				g.sub = 4
				_put(S_ROW, _get32(S_COUNT))


# ---- Tekken Force (game state 15) --------------------------------------------------------

## FUN_800F1F08: TEKKEN FORCE, the score and the high score, then the keys found (or the doctor
## saved, or the bosses beaten and the enemies counted); Start or 4,680 frames end it, the
## ranking follows. The lines' sounds are the drawing's.
func force_step() -> void:
	_put(F_FRAME, _get32(F_FRAME) + 1)
	var region := g.region
	var player := region.ctx8(FORCE_PLAYER)
	if g.pressed(player & 1) & PadState.START and g.sub == 2:
		g.sub = 3
	match g.sub:
		0:
			g.attract_advance()
			g.music(MUSIC_RESULT)
			var side := player & 1
			_put(F_FRAME, 0)
			_put(BRIGHT, 0)
			var ram := g.content.mode_ram("result")
			for i in 4:
				state.put16(F_TEX + 2 * i, ram.u16(F_TEX_SLOTS + 8 * side + 2 * i))
			var gl := g.globals
			var c := gl.player_char[side]
			var k := gl.player_costume[side]
			if c > 0x15 or k > 3:
				c = 0x16
				k = 0
			var word := g.data.attribute(c, k)
			_put(F_COLOUR, word >> 8)
			for at: int in [F_SHOWN, F_BOSS, F_PHASE, F_FORCE]:
				_put(at, 0)
			g.sub = 1
			state.put8(F_FLIP, ((word & 0xFF) >> 5) & 1)
			_seq_reset()
		1:
			_fade_in(2)
		2:
			if _get32(F_FRAME) > F_WAIT:
				g.sub = 3
		3:
			g.music_volume(0, F_FADE_MUSIC)
			_put(BRIGHT, 0x100)
			g.sub = 4
		4:
			_fade_out(5)
		5:
			g.state = GameFlow.State.RANKING_LOAD
			g.sub = 0
	if g.sub > 1:
		_put(F_SHOWN, _get32(F_SHOWN) + 1)
	_force_lines()


## The drawing's counters and sounds: each line's sound as it appears, the bosses one by one,
## then the FORCE count ticking up every other frame.
func _force_lines() -> void:
	var region := g.region
	var shown := _get32(F_SHOWN)
	if shown == F_SCORE_AT or shown == F_HIGH_AT:
		g.sound(SOUND_LINE)
	var flags := region.ctx8(FORCE_FLAGS)
	if flags & FORCE_BOSSES == 0:
		if flags & FORCE_DOCTOR != 0:
			if shown == F_LIST_AT:
				g.sound(SOUND_REVEAL)
			return
		for i in 3:
			if flags & (1 << i) != 0 and shown == F_KEY_AT[i]:
				g.sound(SOUND_LINE)
		return
	if shown > F_LIST_AT - 1:
		_put(F_BOSS, _get32(F_BOSS) + 1)
		if shown == F_LIST_AT:
			g.sound(SOUND_LINE)
	var boss := _get32(F_BOSS)
	for at: int in F_BOSS_AT:
		if boss == at:
			g.sound(SOUND_LINE)
	match _get32(F_PHASE):
		1:
			if shown & 1 == 0:
				_put(F_FORCE, _get32(F_FORCE) + 1)
				g.sound(SOUND_TICK)
			if region.ctx16(FORCE_COUNT) < _get32(F_FORCE) or g.sub > 2:
				_put(F_PHASE, 2)
		0:
			if boss > F_COUNT_AFTER:
				_put(F_PHASE, 1)
				_put(F_FORCE, 0)
