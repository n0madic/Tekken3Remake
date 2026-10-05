class_name CharacterSelect
extends FlowPart
## The character select screen (select.ovl FUN_8011056C, game state 9; modes.md#character-select),
## written from the verified port `tools/research/select_sim.py` and the decompiled overlay (the
## sounds). The screen's context (0x80118C48) and its portrait grid (0x80129CE8) are kept as bytes.
##
## Context: +0x00 mode, +0x04 layout (0: one row, 1: two rows), +0x08 frame counter, +0x0C
## cursor-moved flag, +0x10 NEW blink timer, +0x14 / +0x18 time limit and its step, +0x1C unlocked
## mask, +0x20 unlocked count, +0x24 / +0xA0 the players' records (0x7C bytes), +0x11C layout.
## Grid cells (12 bytes): +0 index, +1…+4 the cell up, down, left, right (0x16 none), +5 shown,
## +6 s16 character (0x16 locked), +8 / +0xA s16 x, y.

const BASE := 0x80118C48
const SIZE := 0x14C
const CELLS_BASE := 0x80129CE8
const CELL_COUNT := 22
const CELL_SIZE := 12
const NO_CELL := 0x16
const DUMMY_CELL := -1               ## 0x800B9650: an all-0x16 cell for an empty row (read-only)
const CELL_STEP := 0x23              ## the portraits' horizontal spacing
const RECORDS := 0x24
const RECORD_SIZE := 0x7C
const LAYOUT := 0x11C
const LAYOUT_SIZE := 0x30
const NEW_BLINK := 0xB4
const CHOSEN_WAIT := 0x5A
const CHOSEN_ANIM := 0x1C
const DRAW_FROM := 3                 ## the screen draws (and Select + Start leaves) from frame 3
const SOUND_MOVE := 0x55F5
const SOUND_CHOOSE := 0x50F4
const SOUND_JOIN := 0x49A1
const MUSIC_SELECT := 1
const SPARK_COUNT := 64
const SPARK_HEIGHT := 0xA0
const SPARK_BRIGHT := 0x60
const LAYOUT_SPARK_Y := 0x124        ## context: the sparks' starting y
const START_COSTUME_BUTTONS := PadState.START | PadState.TRIANGLE
## Record fields.
const R_STATE := 0x00
const R_CELL := 0x04
const R_ANIM := 0x08
const R_FLIP := 0x10
const R_SHOWN_KEY := 0x14
const R_SHOWN_COSTUME := 0x18
const R_KEY := 0x1C
const R_COSTUME := 0x20
const R_TIMER := 0x24
const R_BASE := 0x28
const R_RECORD5 := 0x2C
const R_CHOSEN_ANIM := 0x30
const R_CHOSEN_KEY := 0x3C
const R_CHOSEN_COSTUME := 0x40
const R_CLASH := 0x44
const R_LAYOUT := 0x54
const R_FACING := 0x60               ## u16 in the layout words: 1 faces right
const R_DEFAULT_CELL := 0x78         ## u16 in the layout words
## Player states: set-up, choosing, waiting for the other side, choosing for the other side (its
## pad drives), CPU side (a challenger may join), no fighter, chosen, chosen by the other pad.
enum { SET_UP, CHOOSING, WAITING, CHOOSING_OTHER, CPU, NONE, CHOSEN, CHOSEN_BY_OTHER }


## The grid builder's per-row record (a stack struct in the game).
class Row:
	extends RefCounted
	var first := 0
	var cur := 0
	var last := 0
	var x := 0xB
	var y := 0
	var row := 0
	var phase := 0
	var odd := 0
	var middle := NO_CELL
	var skip := 0
	var remaining := 0
	var half := 0
	var total := 0

	func _init(first_cell: int, row_index: int, row_y: int) -> void:
		first = first_cell
		cur = first_cell
		last = first_cell
		row = row_index
		y = row_y


var ctx := ByteBlock.new(SIZE)
var cells := ByteBlock.new(CELL_COUNT * CELL_SIZE)
var sparks: Array[Spark] = []        ## context +0x14C: 64 rising streaks behind the portraits


## A rising, fading streak (20 bytes in the game).
class Spark:
	extends RefCounted
	var active := 0
	var started := 0
	var x := 0
	var y := 0
	var top := 0                     ## the y it rises from
	var frame := 0                   ## the frame it started
	var bright := 0
	var fade := 0


func _init(flow: GameFlow) -> void:
	super(flow)
	ctx.bytes = flow.data.select_context.duplicate()
	for i in SPARK_COUNT:
		sparks.append(Spark.new())


func rec(player: int) -> int:
	return RECORDS + RECORD_SIZE * player


func r32(player: int, at: int) -> int:
	return ctx.u32(rec(player) + at)


func rs32(player: int, at: int) -> int:
	return ctx.s32(rec(player) + at)


func w32(player: int, at: int, v: int) -> void:
	ctx.put32(rec(player) + at, v)


func frames() -> int:
	return ctx.s32(8)


## A cell's byte (the dummy cell reads 0x16 everywhere).
func cell8(cell: int, at: int) -> int:
	return NO_CELL if cell == DUMMY_CELL else cells.u8(CELL_SIZE * cell + at)


func cell_key(cell: int) -> int:
	return cells.s16(CELL_SIZE * cell + 6)


func _cell_put8(cell: int, at: int, v: int) -> void:
	cells.put8(CELL_SIZE * cell + at, v)


func step() -> void:
	if g.sub > 0 and frames() >= DRAW_FROM and g.menu_exit():
		return
	match g.sub:
		0:
			g.music_stop()
			ctx.put32(0, g.region.mode)
			grid_build()
			var at := ctx.u32(4) * LAYOUT_SIZE
			for k in LAYOUT_SIZE:
				ctx.put8(LAYOUT + k, g.data.select_layouts[at + k])
			g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
			g.music(MUSIC_SELECT)
			ctx.put32(8, 0)
			ctx.put32(0xC, 2)
			for p in 2:
				w32(p, R_STATE, SET_UP)
				var b := g.progress.last_character(p)
				w32(p, R_CHOSEN_KEY, b >> 2)
				w32(p, R_CHOSEN_COSTUME, b & 3)
				player_step(p)
			for spark in sparks:
				spark.active = 0
				spark.started = 0
			g.sub = 1
		1:
			var t := ctx.s32(0x14)
			if t > 0:
				ctx.put32(0x14, t - 1)
			var a := player_step(0)
			var b := player_step(1)
			if a and b:
				g.sub = 2
		2:
			commit()
			g.state = GameFlow.target_state(g.region.vs_next_state)
			g.sub = g.region.vs_next_sub
	portrait_update()
	if frames() >= DRAW_FROM:
		# The drawing's own state: the sparks, the portraits' slide-in (FUN_8010F760) and the NEW
		# arrows' blink (FUN_8010EC9C).
		_sparks()
		for p in 2:
			var slide := rs32(p, R_CHOSEN_ANIM)
			if slide != 0:
				w32(p, R_CHOSEN_ANIM, slide - 1)
		if ctx.u32(0x10) != 0:
			ctx.put32(0x10, ctx.u32(0x10) - 1)
		var t := ctx.s32(0xC)
		if t > 0:
			ctx.put32(0xC, t - 1)


## FUN_8010F1B4: every 4th frame a new streak rises from alternating portraits (the frame
## generator places it and sets its fade); FUN_8010F020 moves and fades each one.
func _sparks() -> void:
	var n := ctx.u32(8)
	if n & 3 == 0:
		var k := (n >> 3) & 3
		k = ((k << 1) | (k >> 1)) & 3
		var p := (n >> 2) & 1
		var free: Spark = null
		for spark in sparks:
			if spark.active == 0:
				spark.started = 0
				free = spark
				break
		if free != null:
			var r := Opponents.frame_random(g.fight)
			var a := (k << 10) | ((Fx.w32(r) >> 2) & 0x3FF)
			free.active = 1
			free.x = (ctx.u16(rec(p) + R_LAYOUT) + (a * 0x7E >> 12)) & 0xFFFF
			var y := ctx.u16(LAYOUT_SPARK_Y)
			free.top = y
			free.y = y
	var now := g.fight.vblank & 0xFFFF
	for spark in sparks:
		if spark.active != 1:
			continue
		if spark.started == 0:
			spark.bright = SPARK_BRIGHT
			spark.frame = now
			spark.started = 1
			spark.fade = (Opponents.frame_random(g.fight) & 3) + 4
		elif spark.started != 1:
			continue
		spark.bright -= spark.fade
		spark.y = Fx.s16((spark.top - ((now - spark.frame) << 4)) & 0xFFFF)
		if spark.y + SPARK_HEIGHT < 0 or spark.bright <= 0:
			spark.active = 0


# ---- the grid (FUN_8010DC04, FUN_8010DA30, FUN_8010D810) ----------------------------------

## The portrait grid from the unlocked characters (cells 10 and 21 are hidden extras that only
## start the NEW blink).
func grid_build() -> void:
	var mask := g.progress.unlocked & 0x1FFFFF
	ctx.put32(0x10, 0)
	var shown := 0
	for i in CELL_COUNT:
		var at := CELL_SIZE * i
		cells.put8(at, i)
		var key := g.data.select_grid_keys[i]
		if (mask >> key) & 1:
			cells.put16(at + 6, key)
			if i % 11 < 10:
				cells.put8(at + 5, 1)
			else:
				cells.put8(at + 5, 0)
				ctx.put32(0x10, NEW_BLINK)
			shown |= 1 << key
		else:
			cells.put16(at + 6, NO_CELL)
			cells.put8(at + 5, 0)
		for k in range(1, 5):
			cells.put8(at + k, NO_CELL)
	ctx.put32(0x20, ProgressRules.popcount(shown))
	ctx.put32(0x1C, shown)
	var rows: Array[Row] = [Row.new(0, 0, 0), Row.new(11, 1, 0x3E)]
	for r in 2:
		var row := rows[r]
		var found := false
		var last := row.first
		for k in 11:
			var c := 11 * r + k
			if cell_key(c) == NO_CELL:
				continue
			if not found:
				row.cur = c
				found = true
			else:
				_cell_put8(last, 4, c)
				_cell_put8(c, 3, last)
			row.total = (row.total + 1) & 0xFF
			if k < 10:
				row.remaining = (row.remaining + 1) & 0xFF
			last = c
		_cell_put8(last, 4, row.cur)          # close the ring
		_cell_put8(row.cur, 3, last)
		row.last = last
	ctx.put32(4, 1 if rows[1].remaining != 0 else 0)
	_pair_rows(rows[0], rows[1])


## The cell's link toward the other row (up from the bottom row, down from the top).
func _vertical(row: Row, cell: int) -> int:
	return cell8(cell, 1) if row.row != 0 else cell8(cell, 2)


## FUN_8010D810: place one cell of a row and return the cell to pair with next.
func _row_step(row: Row, cell: int) -> int:
	if row.phase >= 3:
		return cell
	if row.phase == 0:
		if row.skip != 0:
			_cell_put8(cell, 3, _vertical(row, cell))
			row.skip = (row.skip - 1) & 0xFF
			return cell
		if row.odd != 0:
			_cell_put8(cell, 3, _vertical(row, cell))
		row.phase += 1
	if row.phase == 1:
		if row.remaining != 0:
			if row.odd != 0 and row.remaining == row.middle:
				row.middle = 0xFF
				return cell
			cells.put16(CELL_SIZE * cell + 8, row.x)
			cells.put16(CELL_SIZE * cell + 0xA, row.y)
			row.remaining = (row.remaining - 1) & 0xFF
			row.x = (row.x + CELL_STEP) & 0xFFFF
			if row.remaining != 0:
				return cell8(cell, 4)
		row.phase += 1
	if row.odd != 0:
		_cell_put8(cell, 4, _vertical(row, cell))
	elif row.half != 0:
		_cell_put8(cell, 4, cell8(_vertical(row, cell), 4))
	row.phase += 1
	return cell


## FUN_8010DA30: centre the shorter row under the longer one and link the rows vertically.
func _pair_rows(a: Row, b: Row) -> void:
	var big := b if a.remaining < b.remaining else a
	var small := a if a.remaining < b.remaining else b
	if big.remaining == 0:
		big.cur = DUMMY_CELL
		big.phase = 3
	if small.remaining != 0:
		var diff := (big.remaining - small.remaining) & 0xFFFFFFFF
		if diff & 1:
			small.odd = 1
		small.half = (diff >> 1) & 0xFF
		small.skip = small.half
		small.middle = (small.remaining >> 1) + 1
		small.x = (small.x + ((10 - small.remaining) * CELL_STEP >> 1)) & 0xFFFF
	else:
		small.cur = DUMMY_CELL
		small.phase = 3
	var c1 := big.cur
	var c0 := small.cur
	for i in big.remaining:
		if big.phase < 3:
			_cell_put8(c1, 1 if big.row != 0 else 2, cell8(c0, 0))
		if small.phase < 3:
			_cell_put8(c0, 1 if small.row != 0 else 2, cell8(c1, 0))
		c1 = _row_step(big, c1)
		c0 = _row_step(small, c0)


# ---- the players (FUN_8010E250) -------------------------------------------------------------

## One player's selection; true when this side is done.
func player_step(player: int) -> bool:
	var other := (player + 1) & 1
	var gl := g.globals
	var done := false
	match r32(player, R_STATE):
		SET_UP:
			for k in 0x28:
				ctx.put8(rec(player) + R_LAYOUT + k, g.data.select_player_layout[0x28 * player + k])
			w32(player, R_RECORD5, 0)
			w32(player, R_BASE, 0)
			var n := ctx.s32(0x20)
			var t := 0x3C if n < 11 else (n - 10) * 3 + 0x3C
			ctx.put32(0x18, t)
			ctx.put32(0x14, t * 20)
			w32(player, R_TIMER, 0)
			w32(player, R_CHOSEN_ANIM, 0)
			if gl.player_keep[player] != 0:
				w32(player, R_TIMER, CHOSEN_WAIT)
				w32(player, R_CHOSEN_ANIM, CHOSEN_ANIM)
			_start(player)
			var mode := ctx.u32(0)
			var active := gl.player_active[player]
			if mode in [GameMode.TIME_ATTACK, GameMode.SURVIVAL, GameMode.FORCE]:
				w32(player, R_STATE, CHOOSING if active != 0 else NONE)
			elif mode == GameMode.PRACTICE:
				w32(player, R_STATE, CHOOSING if active != 0 else WAITING)
			else:
				var kind := (2 if active != 0 else 0) | (1 if gl.player_keep[player] != 0 else 0)
				var states: Array[int] = [CPU, CPU, CHOOSING, CHOSEN]
				w32(player, R_STATE, states[kind])
		CHOOSING:
			_move(player, player)
			if not _choose(player, g.pressed(player)):
				w32(player, R_TIMER, CHOSEN_WAIT)
				w32(player, R_CHOSEN_ANIM, CHOSEN_ANIM)
				w32(player, R_STATE, CHOSEN)
		WAITING:
			if r32(other, R_STATE) == CHOSEN:
				w32(player, R_STATE, CHOOSING_OTHER)
				w32(player, R_CELL, r32(other, R_CELL))
		CHOOSING_OTHER:
			_move(player, other)
			if g.pressed(other) & PadState.SELECT:
				# Select: back to the other side's choice.
				w32(other, R_STATE, CHOOSING)
				w32(player, R_STATE, WAITING)
				ctx.put32(0xC, 2)
				w32(player, R_KEY, NO_CELL)
				w32(player, R_COSTUME, 0)
				g.sound(SOUND_CHOOSE)
			elif not _choose(player, g.pressed(other)):
				w32(player, R_TIMER, CHOSEN_WAIT)
				w32(player, R_CHOSEN_ANIM, CHOSEN_ANIM)
				w32(player, R_STATE, CHOSEN_BY_OTHER)
		CPU:
			if g.region.challengers != 0 and g.match_flow.challenger_join(player):
				w32(player, R_STATE, SET_UP)
				g.sound(SOUND_JOIN)
			else:
				done = true
		NONE:
			done = true
		CHOSEN, CHOSEN_BY_OTHER:
			var pad := player if r32(player, R_STATE) == CHOSEN else other
			if g.pressed(pad) & PadState.START:
				w32(player, R_TIMER, 0)
			var t := rs32(player, R_TIMER)
			if t > 0:
				w32(player, R_TIMER, t - 1)
			else:
				done = true
	var s := r32(player, R_STATE)
	w32(player, R_ANIM, g.data.select_state_anim[2 * s])
	w32(player, R_ANIM + 4, g.data.select_state_anim[2 * s + 1])
	return done


## FUN_8010DF20: the starting cursor from the kept character (or the last choice).
func _start(player: int) -> void:
	var gl := g.globals
	var kind := (2 if gl.player_active[player] != 0 else 0) | (1 if gl.player_keep[player] != 0 else 0)
	var key := NO_CELL
	var costume := 0
	if kind == 1:
		key = gl.player_char[player]
		costume = gl.player_costume[player]
	elif kind != 0:
		if kind == 2:
			key = r32(player, R_CHOSEN_KEY)
			costume = r32(player, R_CHOSEN_COSTUME)
		else:
			key = gl.player_char[player]
			costume = gl.player_costume[player]
		var i := _find_cell(Fx.w32(key))
		if i >= 0:
			w32(player, R_CELL, i)
		else:
			i = ctx.u16(rec(player) + R_DEFAULT_CELL)
			w32(player, R_CELL, i)
			key = cell_key(i)
	w32(player, R_SHOWN_KEY, NO_CELL)
	w32(player, R_KEY, key)
	w32(player, R_COSTUME, costume)
	w32(player, R_SHOWN_COSTUME, 1)


func _find_cell(key: int) -> int:
	if key < NO_CELL:
		for i in CELL_COUNT:
			if cell_key(i) == key:
				return i
	return -1


## The cursor follows `pad`'s direction to the neighbouring cell (repeat for left and right,
## repeat or press for up and down).
func _move(player: int, pad: int) -> void:
	var rep := g.repeat(pad)
	var v := (rep & ~PadState.VERTICAL & 0xFFFF) | (g.pressed(pad) & PadState.VERTICAL)
	if rep & PadState.HORIZONTAL:
		v = rep & PadState.HORIZONTAL
	var link := 0
	match v:
		0x1000: link = 1
		0x4000: link = 2
		0x8000: link = 3
		0x2000: link = 4
	var cell := r32(player, R_CELL)
	var next := cell8(cell, link) if link != 0 else NO_CELL
	if next != NO_CELL:
		w32(player, R_CELL, next)
		w32(player, R_COSTUME, 0)
		ctx.put32(0xC, 2)
		g.sound(SOUND_MOVE)
	w32(player, R_KEY, cell_key(r32(player, R_CELL)))


## FUN_8010E0D8: a face button (or the time running out) picks the costume; false once chosen.
## □ and ✕ costume 0, ○ and △ costume 1, Start or L1 the Start costume when it is unlocked.
func _choose(player: int, pressed: int) -> bool:
	var extra := START_COSTUME_BUTTONS if (g.progress.start_costumes >> (r32(player, R_KEY) & 31)) & 1 else 0
	if (extra | GameFlow.FACE_BUTTONS) & pressed == 0 and ctx.u32(0x14) != 0:
		return true
	var costume := 2 if extra & pressed else (1 if pressed & (PadState.CIRCLE | PadState.CROSS) else 0)
	var key := rs32(player, R_KEY)
	if key < 0x17:
		w32(player, R_COSTUME, costume)
		for q in 2:
			w32(q, R_CLASH, r32(q, R_KEY))
			w32(q, R_CLASH + 4, r32(q, R_COSTUME))
			var s := r32(q, R_STATE)
			w32(q, R_CLASH + 8, g.data.select_decided[2 * s])
			w32(q, R_CLASH + 12, g.data.select_decided[2 * s + 1])
		QuickSelect.costume_clash(ctx, rec(player) + R_CLASH, rec((player + 1) & 1) + R_CLASH)
		for q in 2:
			w32(q, R_KEY, r32(q, R_CLASH))
			w32(q, R_COSTUME, r32(q, R_CLASH + 4))
		w32(player, R_CHOSEN_KEY, r32(player, R_KEY))
		w32(player, R_CHOSEN_COSTUME, r32(player, R_COSTUME))
		g.sound(SOUND_CHOOSE)
	return key >= NO_CELL


## FUN_8010E948: the chosen characters into the fight variables and the select memory.
func commit() -> void:
	var gl := g.globals
	for q in 2:
		var key := r32(q, R_CHOSEN_KEY)
		var costume := r32(q, R_CHOSEN_COSTUME)
		var active := gl.player_active[q]
		if g.region.mode != GameMode.PRACTICE or active != 0:
			g.progress.set_last_character(q, ((key << 2) | (costume & 3)) & 0xFF)
		if active != 0 or ctx.u32(0) == 5:
			gl.player_char[q] = key & 0xFFFF
			gl.player_costume[q] = costume & 0xFFFF
			gl.player_keep[q] = 1
			gl.player_cpu[q] = 0


## FUN_8010EA2C: every other frame one side's big portrait follows its cursor (the side's
## picture id goes into the progress block, as the VS screen's does).
func portrait_update() -> void:
	var n := (ctx.u32(8) + 1) & 0xFFFFFFFF
	ctx.put32(8, n)
	var p := n & 1
	if r32(p, R_SHOWN_KEY) == r32(p, R_KEY) and r32(p, R_SHOWN_COSTUME) == r32(p, R_COSTUME):
		return
	var key := rs32(p, R_KEY)
	var costume := rs32(p, R_COSTUME)
	w32(p, R_SHOWN_KEY, key)
	w32(p, R_SHOWN_COSTUME, costume)
	var attr := g.data.attribute(key, costume) & 0xFF
	var k := (key << 2) | costume
	var record := g.fight.tables.character(ModeRules.KEY_NONE if k > 0x5C or k < 0 else k)
	var extra: Array = record["unknown"]
	w32(p, R_RECORD5, JsonFile.number(extra[0]))
	w32(p, R_BASE, JsonFile.number(record["base"]))
	var facing_right := ctx.u16(rec(p) + R_FACING) == 1
	var flip := ((attr & 0x20) != 0) != facing_right and r32(p, R_SHOWN_KEY) != NO_CELL
	w32(p, R_FLIP, 1 if flip else 0)
	g.progress.put8(VsScreen.PROGRESS_PICTURES + p, attr & 0x1F)
