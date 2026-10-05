class_name QuickSelect
extends FlowPart
## The resident character select of VS, team battle and Tekken Ball, and of QUICK SELECT and
## challengers (FUN_80055878, game state 10; modes.md#character-select), written from the
## decompiled FUN_800532E8 / FUN_800530CC / FUN_80054294 and the verified port in
## `tools/research/select_sim.py`. The screen's context (0x800B9378) is kept as bytes: the mode, the
## fade-in, and one 0xAC-byte record per player (state, cursor, team, handicap, picks).
## Tekken Ball's hooks (volley.ovl): the ball preview (FUN_800B5B6C), the ball damage bar
## (FUN_800B5C4C) and the ball type chosen by the first side to finish (FUN_800B569C).

const BASE := 0x800B9378
const SIZE := 0x170
const RECORDS := 0x18
const RECORD_SIZE := 0xAC
const LOCKED := 0x58
const TAKEN := 0x59
const COLUMNS := 7
const ROWS := 3
const CHOOSE := PadState.CONFIRM
const SOUND_MOVE := 0x55F5
const SOUND_PICK := 0x50F4
const SOUND_JOIN := 0x49A1
const MUSIC_SELECT := 1
const START_COSTUME_BUTTONS := PadState.START | PadState.TRIANGLE
## Record fields.
const R_STATE := 0x00
const R_PLAYER := 0x04
const R_COLUMN := 0x08
const R_ROW := 0x0C
const R_AVAILABLE := 0x24
const R_WANTED := 0x28
const R_COUNT := 0x2C
const R_ORDER := 0x34
const R_MEMBERS := 0x38
const R_HANDICAP := 0x58
const R_LAST := 0x64
const R_CLASH := 0x68
const R_PREFS := 0x78
## Player states: set-up, the team size, choosing (team battle: Start ends the team early),
## the handicap, waiting for the other side, choosing for the other side (its pad drives), CPU
## side (a challenger may join; the team variant copies the size), no fighter, chosen, handicap
## set, chosen by the other pad, and Tekken Ball's wait for the ball type and its choice.
enum {
	SET_UP = 0, TEAM_SIZE = 1, TEAM_CHOOSING = 2, CHOOSING = 3, HANDICAP = 4, WAITING = 6,
	CHOOSING_OTHER = 7, CPU = 8, CPU_TEAM = 9, NONE = 0xA, CHOSEN = 0xB, HANDICAP_SET = 0xC,
	CHOSEN_BY_OTHER = 0xD, BALL_WAITING = 0xE, BALL_TYPE = 0xF,
}

var ctx := ByteBlock.new(SIZE)


func mode() -> int:
	return ctx.u32(0)


func fading() -> bool:
	return ctx.u32(8) != 0


func fade_level() -> int:
	return ctx.s32(0xC)


func rec(player: int) -> int:
	return RECORDS + RECORD_SIZE * player


func r32(player: int, at: int) -> int:
	return ctx.u32(rec(player) + at)


func rs32(player: int, at: int) -> int:
	return ctx.s32(rec(player) + at)


func r16(player: int, at: int) -> int:
	return ctx.u16(rec(player) + at)


func w32(player: int, at: int, v: int) -> void:
	ctx.put32(rec(player) + at, v)


## The costume key in a grid cell (s16 x, s16 y, u8 key).
func cell_key(column: int, row: int) -> int:
	return g.data.quick_grid[6 * ((column + row * COLUMNS) & 0xFFFFFFFF) + 4]


func step() -> void:
	if g.sub != 0 and ctx.u32(8) == 0 and g.menu_exit():
		return
	match g.sub:
		0:
			g.display(0)
			g.sub = 1
			return
		1:
			ctx.put32(0xC, 0)
			ctx.put32(4, 0)
			ctx.put32(0x10, 0)
			ctx.put32(0x14, 0)
			ctx.put32(0, g.region.mode)
			ctx.put32(8, 1)
			for p in 2:
				w32(p, R_STATE, SET_UP)
				w32(p, R_PLAYER, p)
				w32(p, R_LAST, g.progress.last_character(p))
				player_step(p)
			if g.region.mode == GameMode.BALL:
				g.sim.ball.preview()
			g.music(MUSIC_SELECT)
			g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
			g.sub = 2
		2:
			var a := player_step(0)
			var b := player_step(1)
			if a & b:
				g.sub = 3
		3:
			commit()
			g.state = GameFlow.target_state(g.region.vs_next_state)
			g.sub = g.region.vs_next_sub
	if ctx.u32(8) == 1:
		var level := ctx.s32(0xC) + 0x10
		ctx.put32(0xC, level)
		if level > 0x100:
			ctx.put32(8, 0)


## FUN_800513FC: 2 for an active human, +1 when the pick is kept.
func _kind(player: int) -> int:
	return (2 if g.globals.player_active[player] != 0 else 0) | (1 if g.globals.player_keep[player] != 0 else 0)


## The cursor on the cell of `key` (else of the record's default key).
func _find(player: int, key: int) -> void:
	var target := key & ~3 if key < LOCKED else r32(player, 0x84)
	for row in ROWS:
		for column in COLUMNS:
			if cell_key(column, row) == target & 0xFFFFFFFF:
				w32(player, R_COLUMN, column)
				w32(player, R_ROW, row)
				return


## The common set-up: one member, the kept character (or the last pick) under the cursor.
func _start_cursor(player: int) -> void:
	w32(player, R_COUNT, 0)
	w32(player, R_WANTED, 1)
	w32(player, 0x30, 1)
	var key := 0
	if g.globals.player_keep[player] != 0:
		w32(player, R_COUNT, 1)
		key = g.globals.player_char[player] * 4 + g.globals.player_costume[player]
		w32(player, R_MEMBERS, key)
	else:
		key = rs32(player, R_LAST)
		w32(player, R_MEMBERS, LOCKED)
	_find(player, key)


## Select: the last picked member back (its character is available again). The picks are
## members 0 to count − 1 (`pick` stores at `count`, then counts up).
func _undo(player: int) -> bool:
	var count := rs32(player, R_COUNT)
	if count <= 0:
		return false
	var n := count - 1
	var key := rs32(player, R_MEMBERS + 4 * n)
	w32(player, R_LAST, key)
	w32(player, R_MEMBERS + 4 * n, LOCKED)
	w32(player, R_COUNT, n)
	w32(player, R_AVAILABLE, r32(player, R_AVAILABLE) | (1 << ((key >> 2) & 31)))
	g.sound(SOUND_PICK)
	return true


## FUN_800532E8: one player's quick select; true when this side is done.
## States: 0 set-up, 1 team size, 2 team members, 3 choosing, 4 VS handicap, 6/7 the other pad
## chooses for this side, 8 CPU side (a challenger may join), 9 team size from the other side,
## 10–13 done, 14 waiting for the ball side select, 15 the ball side select.
func player_step(player: int) -> int:
	var other := (player + 1) & 1
	var done := 0
	var state := r32(player, R_STATE)
	match state:
		SET_UP:
			_setup(player)
		TEAM_SIZE:
			_team_size_step(player)
		TEAM_CHOOSING, CHOOSING:
			_choose_step(player, state)
		HANDICAP:
			_handicap_step(player)
		WAITING:
			if r32(other, R_STATE) == CHOSEN:
				w32(player, R_COLUMN, r32(other, R_COLUMN))
				w32(player, R_STATE, CHOOSING_OTHER)
				w32(player, R_ROW, r32(other, R_ROW))
		CHOOSING_OTHER:
			_move(player, other)
			var pressed := g.pressed(other)
			if pressed & PadState.SELECT:
				_undo(other)
				w32(player, R_STATE, WAITING)
				w32(other, R_STATE, CHOOSING)
				for k in 3:
					w32(other, 0x18 + 4 * k, k + 1)
			elif pick(player, pressed) == 0:
				w32(player, R_STATE, CHOSEN_BY_OTHER)
		CPU, CPU_TEAM:
			if state == CPU_TEAM:
				w32(player, R_WANTED, r32(other, R_WANTED))
			if g.region.challengers != 0 and g.match_flow.challenger_join(player):
				w32(player, R_STATE, SET_UP)
				g.sound(SOUND_JOIN)
			else:
				done = 1
		NONE, CHOSEN, HANDICAP_SET, CHOSEN_BY_OTHER:
			done = 1
		BALL_WAITING:
			if g.pressed(player) & PadState.SELECT:
				_undo(player)
				w32(player, R_STATE, CHOOSING)
				if g.region.ctx8(TekkenBall.CHOOSER) == 1 << player:
					g.region.ctx_put8(TekkenBall.CHOOSER, 0)
			else:
				done = 1
		BALL_TYPE:
			var chosen := g.sim.ball.side_select(g.pressed(g.region.ctx8(TekkenBall.SERVE_SIDE)), g.sim.events)
			if chosen == -1:
				_undo(player)
				w32(player, R_STATE, CHOOSING)
				g.region.ctx_put8(TekkenBall.CHOOSER, 0)
			elif chosen == 1:
				w32(player, R_STATE, BALL_WAITING)
	var s := r32(player, R_STATE)
	for k in 3:
		w32(player, 0x18 + 4 * k, g.data.quick_state_anim[3 * s + k])
	return done


## Team battle: left / right set the number of members (1–8); a choice button goes on to the
## characters (the order by buttons 0x60).
func _team_size_step(player: int) -> void:
	var n := r32(player, R_WANTED)
	var rep := g.repeat(player)
	var lr := ((rep >> 13) & 1) - (rep >> 15)
	var v := n
	if lr != 0 and ((n + lr) & 0xFFFFFFFF) < 9:
		v = n + lr
	if v > 8:
		v = 8
	if v == 0:
		v = 1
	if n != v:
		g.sound(SOUND_MOVE)
	w32(player, R_WANTED, v)
	var pressed := g.pressed(player)
	if pressed & CHOOSE:
		w32(player, R_ORDER, 1 if pressed & (PadState.CIRCLE | PadState.CROSS) else 0)
		g.sound(SOUND_PICK)
		w32(player, R_STATE, TEAM_CHOOSING)


## Choosing a character; in team battle Start ends the team early and Select takes back the last
## pick (or returns to the team size). A finished side goes on by the mode.
func _choose_step(player: int, state: int) -> void:
	_move(player, player)
	var pressed := g.pressed(player)
	var finish := false
	if state == TEAM_CHOOSING and pressed & PadState.START:
		g.sound(SOUND_PICK)
		finish = true
	elif state == TEAM_CHOOSING and pressed & PadState.SELECT:
		if not _undo(player):
			w32(player, R_STATE, TEAM_SIZE)
		else:
			finish = pick(player, pressed) == 0
	else:
		finish = pick(player, pressed) == 0
	if finish:
		match mode():
			GameMode.ARCADE, GameMode.TIME_ATTACK, GameMode.SURVIVAL, GameMode.PRACTICE, GameMode.DEMO, GameMode.FORCE:
				w32(player, R_STATE, CHOSEN)
			GameMode.VS:
				w32(player, R_STATE, HANDICAP)
			GameMode.TEAM:
				w32(player, R_STATE, NONE)
			GameMode.BALL:
				w32(player, R_STATE, BALL_WAITING)
				if g.region.ctx8(TekkenBall.CHOOSER) == 0:
					g.region.ctx_put8(TekkenBall.CHOOSER, 1 << player)
					g.region.ctx_put8(TekkenBall.SERVE_SIDE, player)
					w32(player, R_STATE, BALL_TYPE)


## VS and Tekken Ball: left / right move the handicap bar (0–7, twice as fast for the ball); Select
## takes back the pick, a face button sets it.
func _handicap_step(player: int) -> void:
	w32(player, 0x5C, r16(player, 0x9A))
	var h := r32(player, R_HANDICAP)
	var rep := g.repeat(player)
	var lr := ((rep >> 13) & 1) - (rep >> 15)
	if g.region.mode == GameMode.BALL:
		lr *= 2
	var v := h
	if lr != 0:
		if Fx.s16(r16(player, 0x98)) == 0:
			lr = -lr
		if ((h + lr) & 0xFFFFFFFF) < 8:
			v = h + lr
	if h != v:
		g.sound(SOUND_MOVE)
	w32(player, R_HANDICAP, v)
	var pressed := g.pressed(player)
	if pressed & PadState.SELECT:
		w32(player, 0x5C, r16(player, 0x9C))
		_undo(player)
		w32(player, R_STATE, CHOOSING)
	elif pressed & GameFlow.FACE_BUTTONS:
		g.sound(SOUND_PICK)
		w32(player, R_STATE, HANDICAP_SET)


func _setup(player: int) -> void:
	for k in 0x34:
		ctx.put8(rec(player) + R_PREFS + k, g.data.quick_prefs[0x34 * player + k])
	w32(player, R_AVAILABLE, g.progress.unlocked)
	var m := mode()
	var kind := _kind(player)
	match m:
		GameMode.ARCADE, GameMode.DEMO, GameMode.BALL:
			if kind == 2:
				w32(player, R_STATE, CHOOSING)
			elif kind == 3:
				w32(player, R_STATE, CHOSEN if m != GameMode.BALL else BALL_WAITING)
			elif kind < 2:
				w32(player, R_STATE, CPU)
			_start_cursor(player)
		GameMode.TIME_ATTACK, GameMode.SURVIVAL, GameMode.FORCE:
			w32(player, R_STATE, CHOOSING if g.globals.player_active[player] != 0 else NONE)
			_start_cursor(player)
		GameMode.PRACTICE:
			w32(player, R_STATE, CHOOSING if g.globals.player_active[player] != 0 else WAITING)
			_start_cursor(player)
		GameMode.VS:
			w32(player, R_STATE, CHOOSING)
			_start_cursor(player)
		GameMode.TEAM:
			w32(player, R_STATE, TEAM_SIZE if g.globals.player_active[player] != 0 else CPU_TEAM)
			w32(player, R_COUNT, 0)
			w32(player, R_WANTED, 4)
			w32(player, 0x30, 0)
			w32(player, R_ORDER, 0)
			for i in 8:
				w32(player, R_MEMBERS + 4 * i, LOCKED)
			w32(player, R_WANTED, g.region.ctx8(0x65 + 13 * player))
			_find(player, LOCKED)
			w32(player, 0x10, r16(player, 0xA8))
			w32(player, 0x14, r16(player, 0xAA))
	match m:
		GameMode.ARCADE, GameMode.TIME_ATTACK, GameMode.SURVIVAL, GameMode.PRACTICE, GameMode.DEMO, GameMode.FORCE:
			w32(player, 0x10, r16(player, 0x90))
			w32(player, 0x14, r16(player, 0x92))
		GameMode.VS, GameMode.BALL:
			var handicap := g.region.ctx16(0x3A + 4 * player)
			w32(player, 0x10, r16(player, 0x94))
			w32(player, 0x14, r16(player, 0x96))
			w32(player, 0x5C, r16(player, 0x9C))
			w32(player, 0x60, r16(player, 0x9C))
			w32(player, R_HANDICAP, handicap)
			if m == GameMode.BALL:
				# FUN_800B5C4C: the bar starts at 6 and slides in from the side.
				w32(player, R_HANDICAP, 6)
				w32(player, 0x10, r16(player, 0x94))
				w32(player, 0x14, r16(player, 0x96))
				w32(player, 0x5C, r16(player, 0x9C))
				w32(player, 0x60, r16(player, 0x9C))
				ctx.put16(rec(player) + 0x9A, r16(player, 0x9A) + (0x28 if player != 0 else -0x28))


## The cursor of `player`'s record moved by `pad`'s repeating directions (a sound on a move).
func _move(player: int, pad: int) -> void:
	var rep := g.repeat(pad)
	var column := r32(player, R_COLUMN)
	var row := r32(player, R_ROW)
	if column >= COLUMNS:
		column = 0
	if row >= ROWS:
		row = 0
	var lr := ((rep >> 13) & 1) - (rep >> 15)
	var new_column := column
	var new_row := row
	if lr != 0:
		var t := (column + lr) & 0xFFFFFFFF
		new_column = t if t < COLUMNS else 6 - column
	else:
		var t := (row + ((rep >> 14) & 1) - ((rep >> 12) & 1)) & 0xFFFFFFFF
		if t < ROWS:
			new_row = t
	if r32(player, R_COLUMN) != new_column & 0xFFFFFFFF or r32(player, R_ROW) != new_row & 0xFFFFFFFF:
		g.sound(SOUND_MOVE)
	w32(player, R_COLUMN, new_column)
	w32(player, R_ROW, new_row)


## FUN_800530CC: the character under the cursor for a face button (Start or △ the Start costume
## when unlocked, ✕ / ○ costume 1, □ 0); 0 once the side's picks are complete.
func pick(player: int, pressed: int) -> int:
	var key := cell_key(r32(player, R_COLUMN), r32(player, R_ROW))
	var c := key >> 2
	if (r32(player, R_AVAILABLE) >> (c & 31)) & 1 == 0:
		key = TAKEN if (g.progress.unlocked >> (c & 31)) & 1 else LOCKED
		c = key >> 2
	var extra := START_COSTUME_BUTTONS if (g.progress.start_costumes >> (c & 31)) & 1 else 0
	if (extra | 0xF0) & pressed == 0:
		return 1
	var costume := 2 if extra & pressed else (1 if pressed & (PadState.CIRCLE | PadState.CROSS) else 0)
	var k := key + costume
	if key < LOCKED:
		var n := r32(player, R_COUNT)
		w32(player, R_MEMBERS + 4 * n, k)
		if mode() != GameMode.TEAM:
			for q in 2:
				var m := r32(q, R_MEMBERS)
				w32(q, R_CLASH, m >> 2)
				w32(q, R_CLASH + 4, m & 3)
				var s := r32(q, R_STATE)
				w32(q, R_CLASH + 8, g.data.quick_decided[2 * s])
				w32(q, R_CLASH + 12, g.data.quick_decided[2 * s + 1])
			costume_clash(ctx, rec(player) + R_CLASH, rec((player + 1) & 1) + R_CLASH)
			for q in 2:
				w32(q, R_MEMBERS, ((r32(q, R_CLASH) << 2) | (r32(q, R_CLASH + 4) & 3)) & 0xFFFFFFFF)
			k = r32(player, R_MEMBERS + 4 * n)
		w32(player, R_LAST, k)
		w32(player, R_COUNT, r32(player, R_COUNT) + 1)
		w32(player, R_AVAILABLE, r32(player, R_AVAILABLE) & ~(1 << ((Fx.w32(k) >> 2) & 31)) & 0xFFFFFFFF)
		g.sound(SOUND_PICK)
	return 1 if r32(player, R_COUNT) < r32(player, R_WANTED) else 0


## FUN_8004F334 on two (key, costume, decided, human) records at `a` and `b`: the same costume
## twice changes one of them (the undecided or CPU side's, else `a`'s).
static func costume_clash(block: ByteBlock, a: int, b: int) -> void:
	if block.u32(b + 8) != 0 and block.u32(a) == block.u32(b) and block.u32(a + 4) == block.u32(b + 4):
		var c := block.s32(a + 4)
		if block.u32(b + 12) == 0 and block.u32(a + 12) != 0:
			block.put32(b + 4, c ^ 1 if c < 2 else 0)
		else:
			var cb := block.s32(b + 4)
			block.put32(a + 4, cb ^ 1 if cb < 2 else 0)


## FUN_80054294: the picks into the players' choices (team battle: the member lists).
func commit() -> void:
	var region := g.region
	var gl := g.globals
	for q in 2:
		var active := gl.player_active[q]
		if region.mode != GameMode.PRACTICE or active != 0:
			g.progress.set_last_character(q, ctx.u8(rec(q) + R_LAST))
		var key := rs32(q, R_MEMBERS)
		var m := mode()
		match m:
			GameMode.PRACTICE:
				gl.player_char[q] = (key >> 2) & 0xFFFF
				gl.player_costume[q] = key & 3
				gl.player_cpu[q] = 0
				gl.player_keep[q] = 1
			GameMode.TEAM:
				var t := 13 * q
				region.ctx_put8(t + 0x62, 0)
				region.ctx_put8(t + 0x63, ctx.u8(rec(q) + R_COUNT))
				region.ctx_put8(t + 0x65, ctx.u8(rec(q) + R_WANTED))
				region.ctx_put8(t + 0x64, ctx.u8(rec(q) + R_ORDER))
				for i in 8:
					region.ctx_put8(t + 0x59 + i, ctx.u8(rec(q) + R_MEMBERS + 4 * i))
				if active != 0:
					gl.player_keep[q] = 1
					gl.player_cpu[q] = 0
				else:
					gl.player_cpu[q] = 1
			_:
				if m < 9:
					if m == GameMode.VS:
						region.ctx_put16(0x3A + 4 * q, r16(q, R_HANDICAP))
					if active != 0:
						gl.player_char[q] = (key >> 2) & 0xFFFF
						gl.player_costume[q] = key & 3
						gl.player_keep[q] = 1
						gl.player_cpu[q] = 0
