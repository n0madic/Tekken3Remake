class_name QuickSelectView
extends PsxCanvas
## The resident character select (FUN_80055878's drawing, select_sim.quick_*): the gradient
## backdrop with the scrolling floor stripes and banner, the mode's picture, the 21 HUD portraits,
## each side's picked members, cursor frames and tags, the texts (team size, the name on its plate,
## NO ENTRY / SOLD OUT, the coin prompt, the mode caption), the title that gives way to the exit
## hint after eight idle seconds, and VS's handicap bars and win record. The game's ordering
## table draws the background first, then the portraits, the cursors and the texts; the
## semi-transparent parts are passes in their blend modes.
##
## The drawing's own counters (the idle time, the stripes' and banner's scroll, the handicap bars'
## slide) live here: the game keeps them in the screen's context, which only its drawing reads.

const CTX := QuickSelect.BASE
const GRID := 0x800229D4               ## 21 × (s16 x, s16 y, u8 key, pad)
const TITLES := 0x800985A8
const PROMPT := 0x800985C0
const BANNER := 0x800985CC
const CAPTIONS := {3: 0x80022BD8, 4: 0x80022BE8, 5: 0x80022BF4, 8: 0x80022C00}
const CAPTION_WAIT := 0x80022C10
const STR_NO_ENTRY := 0x80022B98
const STR_SOLD_OUT := 0x80022BA4
const STR_PLAYER := 0x80022BB0
const STR_PLAYERS := 0x80022BB8
const STRIPES := 0x80022A54
const BACK_COLOURS := 0x80022DB8
const PLATE_COLOURS := 0x80022198
const VS_RECORD_COLOURS: Array[int] = [0x800B4EA8, 0x800B4EAC]
const VS_LIFE := 0x800B0B94
const VS_PERCENT := 0x800B4EB0
const VS_BAR := 0x800B0B24
const MODE_CTX := ModeRegion.BASE + 0x50
const LOCKED := QuickSelect.LOCKED
const TAKEN := QuickSelect.TAKEN
const IDLE_FRAMES := 0x1E0
const STRIPE_PERIOD := 0x180
const BANNER_PERIOD := 0x344
const BALL_NAMES := 0x800B6928         ## volley.ovl: per type (level, name) string pointers
## The preview's projection (FUN_800B5B6C): the view is 0x800AE460, which GsInitGraph sets to
## the identity at start-up (no display aspect: the ball shows flattened), translated by
## (−0x40, 0x440, 0x1380); the GTE's H 500 and screen offsets 192, 240.
const BALL_VIEW_T := Vector3(-0x40, 0x440, 0x1380)
const BALL_H := 500.0
const BALL_OFFSET := Vector2(192, 240)
## The light of the preview's scene (FUN_80039BB4(5) and SetBackColor(64, 64, 64)): the back colour
## is 64 / 128; the lit share and direction stand in for stage 5's light matrix.
const BALL_BACK := 0.5
const BALL_LIGHT := 0.75
const BALL_LIGHT_DIR := Vector3(-0.4, -0.6, -0.7)
const BALL_ARROWS := [[Vector2(0xFC, 0x14E), Vector2(0xFC, 0x15E), Vector2(0x104, 0x156)],
	[Vector2(0x74, 0x14E), Vector2(0x74, 0x15E), Vector2(0x6C, 0x156)]]

var flow: GameFlow
var frame_count := 0
var _idle := 0
var _stripe := 0
var _banner := 0
var _bars := PackedInt32Array([0, 0])
var _started := false


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage) -> void:
	setup_psx(hud_data, game_ram, image)
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, _mode_picture)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _stripes)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, func() -> void: backdrop(1, ram.u32(BACK_COLOURS + 4 + 8 * _mode())))
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


func show_state(game: GameFlow) -> void:
	flow = game
	frame_count = game.fight.vblank
	fade_level = NO_FADE
	if game.sub <= 1:
		_started = false
		return
	if not _started:
		_started = true
		_idle = 0
		_stripe = 0
		_banner = 0
		for p in 2:
			_bars[p] = ram.s32(_rec(p) + 0x60)
	# The frame's counters, as the drawing advances them.
	_idle = 0 if game.held(0) != 0 or game.held(1) != 0 else _idle + 1
	_stripe = posmod(_stripe + 0x17F, STRIPE_PERIOD)
	_banner = (_banner + 0x342) % BANNER_PERIOD
	for p in 2:
		var target := ram.s32(_rec(p) + 0x5C)
		var cur := _bars[p]
		if cur != target:
			cur = target if absi(target - cur) < 0x18 else cur + (0x18 if target > cur else -0x18)
		_bars[p] = cur
	if ram.u32(CTX + 8) == 1:
		fade_level = ram.s32(CTX + 0xC)
	redraw()


func _mode() -> int:
	return ram.u32(CTX)


func _rec(p: int) -> int:
	return CTX + QuickSelect.RECORDS + QuickSelect.RECORD_SIZE * p


func _cell(column: int, row: int) -> int:
	return GRID + 6 * ((column + row * 7) & 0xFFFFFFFF)


func _key_under_cursor(rec: int) -> int:
	var key := ram.u8(_cell(ram.u32(rec + 8), ram.u32(rec + 0xC)) + 4)
	var bit := 1 << ((key >> 2) & 31)
	if not ram.u32(rec + 0x24) & bit:
		key = TAKEN if ram.u32(GameProgress.BASE) & bit else LOCKED
	return key


func _draw() -> void:
	begin()
	black()
	if flow == null or not _started:
		return
	backdrop(0, ram.u32(BACK_COLOURS + 8 * _mode()))


## The mode's picture (arcade.ovl 0x800B33CC, 0x800B34A8, 0x800B367C): shading subtracted from
## the backdrop.
func _mode_picture() -> void:
	if not _started:
		return
	var mode := _mode()
	var grey := psx(0x808080)
	var none := Color.BLACK
	if mode in [GameMode.ARCADE, GameMode.TIME_ATTACK, GameMode.SURVIVAL, GameMode.PRACTICE, GameMode.DEMO, GameMode.FORCE]:
		gradient(0x50, 0x140, 0x44, 0x70, none, psx(0x282828), none, grey)
		gradient(0xDC, 0x140, 0x44, 0x70, psx(0x282828), none, grey, none)
	elif mode == GameMode.VS or mode == GameMode.BALL:
		var c := psx(0x404040)
		fill(0x58, 0x13B, 0xC0, 0x50, c)
		gradient(0x30, 0x13B, 0x28, 0x50, none, c, none, c)
		gradient(0x118, 0x13B, 0x28, 0x50, c, none, c, none)
		fill(0xA8, 0x18B, 0x20, 0x16, c)
		quad(Vector2(0x9A, 0x18B), Vector2(0xA8, 0x18B), Vector2(0xA6, 0x1A1), Vector2(0xA8, 0x1A1), c, c, c, c)
		quad(Vector2(0xC8, 0x18B), Vector2(0xD6, 0x18B), Vector2(0xC8, 0x1A1), Vector2(0xCA, 0x1A1), c, c, c, c)



## FUN_80055368: the banner (its %p puts it in the background slot) and the floor's stripes
## scrolling left.
func _stripes() -> void:
	if not _started:
		return
	if _mode() == GameMode.TEAM:
		# Team battle's picture: the member areas at half brightness (blend mode 0 over black).
		for p in 2:
			var rec := _rec(p)
			fill(ram.u16(rec + 0x10), ram.s32(rec + 0x14), 0x90, 0x80, Color(0, 0, 0, 0.5))
	var bx := _banner - BANNER_PERIOD
	while bx < 0x170:
		text(ram.string(BANNER), 2, 6, bx, 0xCB)
		bx += BANNER_PERIOD
	var x := _stripe - STRIPE_PERIOD
	for i in 7:
		var w := ram.u32(STRIPES + 4 * i)
		var u := w & 0xFF
		var v := (w >> 8) & 0xFF
		var xx := x
		while xx < 0x170:
			if xx > -0x30:
				ft4(xx, 0x5F, 0x30, 0x50, u, v, 0x18, 0x28, w >> 16, 0x6E)
			xx += STRIPE_PERIOD
		x += 0x30


## The portraits, cursors and texts over the backdrop.
func _front() -> void:
	if not _started:
		return
	_grid()
	_members()
	_cursors()
	var mode := _mode()
	if mode == GameMode.VS:
		_vs_handicaps()
		_vs_record()
	elif mode <= GameMode.FORCE and mode != GameMode.BALL:
		text("VS", 2, 7, 0xA1, 0x15C)
	_texts()
	_title()
	if mode == GameMode.BALL and flow.region.ctx8(TekkenBall.CHOOSER) == 3 and flow.sim.ball != null:
		_ball_types()


## volley.ovl FUN_800B593C and FUN_800B569C while a side chooses the ball: the ball rolling in
## from the side it was pushed to (the fight's renderer FUN_800B3198, render kind 10: the type's
## Gouraud faces, back faces removed), and once it rests its level, name and damage, with the two
## arrows blinking.
func _ball_types() -> void:
	var tb := flow.sim.ball
	var volley := flow.content.mode_ram("volley")
	var kind := flow.region.ctx8(TekkenBall.BALL_TYPE) % 3
	_ball_sphere(tb, volley, kind)
	if absi(tb.b.s32(TekkenBall.B_POS) - tb.b.s32(TekkenBall.B_VEL)) >= 0x40:
		return
	var level := volley.string(volley.u32(BALL_NAMES + 8 * kind))
	var name := volley.string(volley.u32(BALL_NAMES + 8 * kind + 4))
	text(level, 0, 0xB, 0xB8 - (level.length() * 9 >> 1), 0x144)
	text(name, 1, 4, 0xB8 - (name.length() * 0xD >> 1), 0x156)
	text("BALL DAMAGE", 0, 5, 0x87, 0x19E)
	print_fmt("%c%f%H%V%3d%f%H%V%%", [6, 1, 0xA0, 0x1B0, kind * 0x14 + 0x3C, 0, 0xC9, 0x1B6])
	if frame_count & 0x20:
		for arrow: Array in BALL_ARROWS:
			var tri := PackedVector2Array()
			for v: Vector2 in arrow:
				tri.append(pt(v.x, v.y))
			target.draw_colored_polygon(tri, Color8(0xFF, 0xFF, 0))


## The preview's sphere: the 42 vertices turned by the ball's angles (RotMatrix: Rx · Ry · Rz),
## moved to its position, projected; each front face in its colour (cycling by index & 7) shaded
## per vertex by its normal.
func _ball_sphere(tb: TekkenBall, volley: GameRam, kind: int) -> void:
	var b := tb.b
	var r := BallView.rot_matrix(PackedInt32Array([b.u16(TekkenBall.B_ANGLES), b.u16(TekkenBall.B_ANGLES + 2),
		b.u16(TekkenBall.B_ANGLES + 4)]))
	var at := Vector3(b.s32(TekkenBall.B_POS), b.s32(TekkenBall.B_POS + 4), b.s32(TekkenBall.B_POS + 8)) + BALL_VIEW_T
	var light := BALL_LIGHT_DIR.normalized()
	var screen := PackedVector2Array()
	var shade := PackedFloat32Array()
	for v in BallView.VERTEX_COUNT:
		var p := r * BallView.svector(volley, BallView.VERTICES + 8 * v) + at
		screen.append(pt(BALL_OFFSET.x + BALL_H * p.x / p.z, BALL_OFFSET.y + BALL_H * p.y / p.z))
		var n := (r * BallView.svector(volley, BallView.NORMALS + 8 * v)).normalized()
		shade.append(BALL_BACK + BALL_LIGHT * maxf(0.0, n.dot(-light)))
	for pass_ in 2:
		for i: int in BallView.FACE_COUNTS[pass_]:
			var c := BallView.face_colour(volley, kind, pass_, i)
			var idx := BallView.face_corners(volley, pass_, i)
			var p0 := screen[idx[0]]
			# NormalClip: only faces turned to the screen.
			if (screen[idx[1]] - p0).cross(screen[idx[2]] - p0) < 0:
				continue
			var tris: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 2])]
			if pass_ == 1:
				tris.append(PackedInt32Array([1, 3, 2]))
			for tri in tris:
				var points := PackedVector2Array()
				var colours := PackedColorArray()
				for k in tri:
					points.append(screen[idx[k]])
					var l := minf(shade[idx[k]], 2.0)
					colours.append(Color(c.r * l, c.g * l, c.b * l))
				target.draw_primitive(points, colours, PackedVector2Array())


## FUN_80054FE8: the 21 portraits; those under a choosing cursor are lit.
func _grid() -> void:
	var under := PackedInt32Array([TAKEN, TAKEN])
	var shown := PackedInt32Array([TAKEN, TAKEN])
	for p in 2:
		var rec := _rec(p)
		if ram.u32(rec + 0x18) == 1:
			under[p] = ram.u8(_cell(ram.u32(rec + 8), ram.u32(rec + 0xC)) + 4)
			shown[p] = _key_under_cursor(rec)
	if under[0] == under[1] and (shown[0] != TAKEN or shown[1] != TAKEN):
		under = PackedInt32Array([TAKEN, TAKEN])
	var h0 := under[0] if shown[0] == TAKEN else TAKEN
	var h1 := under[1] if shown[1] == TAKEN else TAKEN
	for i in 21:
		var c := GRID + 6 * i
		var key := ram.u8(c + 4)
		var flags := 0x20 if key == h0 or key == h1 else 0
		if not (ram.u32(GameProgress.BASE) >> ((key >> 2) & 31)) & 1:
			key = TAKEN
		portrait(ram.u16(c), ram.s16(c + 2), key, flags, frame_count)


## FUN_8005447C: each side's picked members (the one being chosen shows the cursor's character).
func _members() -> void:
	for p in 2:
		var rec := _rec(p)
		var x0 := ram.s32(rec + 0x10)
		var y0 := ram.s32(rec + 0x14)
		var kind := ram.u32(rec + 0x20)
		for i in maxi(ram.s32(rec + 0x28), 0):
			var key := ram.s32(rec + 0x38 + 4 * i)
			var flags := 0
			if key > 0x57:
				key = LOCKED
			if kind == 1:
				flags = 0x84
			elif kind == 2 and i == ram.u32(rec + 0x2C):
				flags = 0x10
			elif kind == 3 and i == ram.u32(rec + 0x2C):
				key = mini(_key_under_cursor(rec), LOCKED)
			portrait(x0 + (i & 3) * 0x24, y0 + (i >> 2) * 0x40, key, flags, frame_count)


## FUN_80054668: each side's cursor frame on the grid and its tag. A frame is drawn in two halves
## clipped to draw areas, each side's own half in the higher ordering slot (P1's on the left, P2's
## on the right on top when both are on a cell); a choosing cursor's slots are above a chosen one's.
## The tags are over the frames.
func _cursors() -> void:
	var level := triangle(frame_count << 4)
	var halves: Array[Array] = []
	var tags: Array[Array] = []
	for p in 2:
		var rec := _rec(p)
		var kind := ram.u32(rec + 0x18)
		if kind == 0:
			continue
		var cell := _cell(ram.u32(rec + 8), ram.u32(rec + 0xC))
		var sx := ram.s16(cell)
		var sy := ram.u16(cell + 2)
		var flags := 0
		var tint := Color.WHITE
		var layer := 0
		if kind == 1 or kind == 3:
			flags = (ram.u32(rec + 0x78) | 0x10) if kind == 1 else 0x93
			tint = Color(level / 128.0, level / 128.0, level / 128.0)
			layer = 2
			if _key_under_cursor(rec) > 0x57:
				flags = 0x90
		else:
			flags = ram.u32(rec + 0x78) if kind == 2 else 0x83
		var chosen := ((kind - 3) & 0xFFFFFFFF) < 2
		var dx := ram.s16(rec + (0x8A if chosen else 0x88))
		var uv := ram.u32(rec + (0x80 if chosen else 0x7C))
		tags.append([sx + dx, sy - 4, uv, tint])
		for i in 2:
			# [ordering slot, link order reversed, x, y, flags, half]
			halves.append([layer * 4 + (4 if i == p else 0), -(p * 2 + i), sx, sy, flags, i])
	halves.sort()
	for h: Array in halves:
		var sx: int = h[2]
		var sy: int = h[3]
		var half: int = h[5]
		portrait_frame(sx, sy, h[4] as int, frame_count, Rect2(sx + 0x12 * half, sy, 0x12, 0x40))
	for t: Array in tags:
		sprt(t[0] as int, t[1] as int, 0x14, 0x10, t[2] as int, 0xE, t[3] as Color)


## FUN_8004E9EC: the textured plate under a name.
func _name_plate(x: int, y: int, w: int, colour: int) -> void:
	ft4(x, y, w, 10, 0xDC, 0xA8, 2, 10, ram.u16(PLATE_COLOURS + 2 * colour), 0xD)


## FUN_8005497C: per side the team size, the name under the cursor, the prompt or the caption.
func _texts() -> void:
	for p in 2:
		var rec := _rec(p)
		var x := ram.u16(rec + 0x8C)
		var y := ram.u16(rec + 0x8E)
		var kind := ram.u32(rec + 0x1C)
		if kind == 1:
			var y1 := ram.s32(rec + 0x14)
			var xx := ram.s32(rec + 0x10) + 8
			var n := ram.u32(rec + 0x28)
			for i in 8:
				var colour := 10
				if n - 1 == i:
					fill(xx - 2, y1 + 0x34, 0x11, 4, psx(0xFF))
					colour = 1 if frame_count & 2 else 6
				text(str(i + 1), 1, colour, xx, y1 + 0x18)
				xx += 0x10
			var who := ram.string(STR_PLAYER if n < 2 else STR_PLAYERS)
			text("%x %s\n ON TEAM" % [n & 0xF, who], 1, 5, ram.s32(rec + 0x10) + 0xC, ram.s32(rec + 0x14) + 0x48)
		elif kind == 2 or kind == 3:
			var key := 0
			if kind == 2:
				key = _key_under_cursor(rec)
			else:
				var n := ram.u32(rec + 0x28)
				var done := ram.u32(rec + 0x2C)
				var i := n - 1 if n <= done else (done - 1 if Fx.w32(done) > 0 else done)
				key = ram.s32(rec + 0x38 + 4 * (i & 0xFFFFFFFF))
			var s := ""
			var colour := 6
			var named := false
			if key < 0x58:
				named = true
				s = str(flow.fight.tables.character(key & ~3)["name"]) if key >= 0 else ""
			elif key == 0x58:
				s = ram.string(STR_NO_ENTRY)
				colour = 9
			else:
				s = ram.string(STR_SOLD_OUT)
				colour = 5
			var x0 := x - ((s.length() * 0xD) >> 1)
			text(s, 1, colour, x0, y)
			if named:
				_name_plate(x0 - 4, y + 0x12, s.length() * 0xD + 10, key & 3)
		elif kind == 4:
			coin(p, x, y + 4, 10, frame_count)
		elif kind == 5:
			var s := ram.string(CAPTIONS.get(_mode(), CAPTION_WAIT) as int)
			var w := s.length() * 0xD
			var x0 := x - (w >> 1)
			var right := x0 + w
			if x0 < 8:
				x0 = 8
				right = w + 8
			if right > 0x168:
				x0 = 0x168 - w
			text(s, 1, 5, x0, y)


## FUN_80054E30: the title; after 480 idle frames it slides out and the exit hint slides in.
func _title() -> void:
	var u := (_idle - IDLE_FRAMES) & 0xFFFFFFFF if _idle > IDLE_FRAMES - 1 else 0
	var x := 0x228 if u & 0x100 else 0xB8
	if u & 0xE0 == 0xE0:
		var d := ((u & 0x1F) * 0x170) >> 5
		x = x - d if u & 0x100 else x + d
	var title := ram.string(ram.u32(TITLES + 4 * _mode()))
	text(title, 1, 6, x - ((title.length() * 0xD) >> 1), 0x1C)
	# The hint's width counts its colour codes, as the game's strlen of the format does.
	var hint := ram.string(ram.u32(PROMPT))
	var parts := hint.split("%c")
	var runs: Array = []
	var colours: Array[int] = [5, 6, 5, 6, 5]
	for i in parts.size():
		if i > 0:
			runs.append(colours[i - 1])
		runs.append(parts[i])
	text_runs(runs, 0, 6, x - ((hint.length() * 9) >> 1) - 0x170, 0x20)


## arcade.ovl FUN_800B3204: both handicap bars sliding toward their value, LIFE and the percentage.
func _vs_handicaps() -> void:
	for p in 2:
		var rec := _rec(p)
		_vs_bar(_bars[p], ram.s16(rec + 0x9E), ram.u16(rec + 0x98), ram.u32(rec + 0x58), ram.u32(rec) == 4)
	for p in 2:
		var rec := _rec(p)
		var cur := _bars[p]
		text(ram.string(VS_LIFE), 0, 5, ram.s16(rec + 0xA0) + cur, ram.s16(rec + 0xA2))
		var pct := ram.string(ram.u32(VS_PERCENT + 4 * ram.u32(rec + 0x58))).replace("%%", "%")
		text(pct, 0, 6, ram.s16(rec + 0xA4) + cur, ram.s16(rec + 0xA6))


## arcade.ovl FUN_800B2EE0: a handicap bar (8 segments, `lit` of them bright) with its end caps.
func _vs_bar(x: int, y: int, right: int, lit: int, pulse: bool) -> void:
	var level := triangle(frame_count << 4)
	var tint := Color(level / 128.0, level / 128.0, level / 128.0) if pulse else Color.WHITE
	fill((x + 2) if right else (x - 0x80 + 2), y + 4, 0x7C, 0x10, Color.BLACK)
	sprt(x + 0x57 if right else x - 0x5F, y, 8, 0xA, 0x7E55B6D6, 0xD)
	var edge := x + 2 if right == 1 else x - 1
	for i in 8:
		var e := VS_BAR + 6 * i
		var w := ram.u8(e)
		var x0 := edge if right == 1 else edge - w
		var uvt := ram.u16(e + 4) if lit < i else ram.u16(e + 2)
		ft4(x0, y + 4, w - 1, 0x10, 0xE8, 0xAC, 1, 0x10, uvt, 0xD)
		edge = w + edge if right == 1 else edge - w
	var bx := x if right else x - 0x80
	sprt(bx, y, 8, 0x18, 0x7EDCA8E0, 0xD, tint)
	sprt(bx + 0x78, y, 8, 0x18, 0x7EDCA8E8, 0xD, tint)
	ft4(bx + 8, y, 0x70, 0x18, 0xE6, 0xA8, 4, 0x18, 0x7EDC, 0xD, tint)


## arcade.ovl FUN_800B2D44: the VS win – win record and the draws.
func _vs_record() -> void:
	var rows: Array = [[0x38, 0x78, 0x14E, 2, VS_RECORD_COLOURS[0]], [0x3C, 0xCC, 0x14E, 2, VS_RECORD_COLOURS[0]],
		[0x40, 0xAB, 0x181, 1, VS_RECORD_COLOURS[1]]]
	for row: Array in rows:
		var n := ram.u16(MODE_CTX + (row[0] as int))
		var colours: int = row[4]
		text("%02d" % (n % 100), row[3] as int, ram.u8(colours + ((n / 100) & 3)), row[1] as int, row[2] as int)
	text("-", 2, 7, 0xAD, 0x14E)
	text("DRAW", 0, 7, 0xA6, 0x16D)
