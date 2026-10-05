class_name ModeHudView
extends FightCanvas
## Tekken Ball's and Tekken Force's parts of the fight HUD, over FightHud (which keeps the timer,
## and in Tekken Ball the usual bars, marks and names):
##
## - Tekken Force (force.ovl): the player's and the shown enemies' name plates and health bars
##   (FUN_800B3790, FUN_800B3118), the level progress bar (FUN_800B3D34), the keys earned
##   (FUN_800B4924), LIFE UP! (FUN_800B4374), "+n SEC" over a defeated enemy,
##   NOW LOADING..., the bonus time left over the player and the stage clear tally
##   (FUN_800B1778; `tally`, `items`, `progress_draw`, `key_icons` in tools/research/force_sim.py);
## - Tekken Ball (volley.ovl): the two power gauges (FUN_800B4E6C), the popup texts
##   (FUN_800B4350; `ball_gauges`, `ball_popups` in tools/research/draw_sim.py) and a point's four
##   streaks (FUN_800B3198, `_streaks` in tools/research/ball_sim.py).

const NAME_POS := 0x800B0EC8           ## force.ovl: per record (x, y); the enemies' right-aligned
const BAR_COLOURS := 0x800B69FC        ## 4 × RGB (4 bytes apart): the progress bar's segments
const HALF_DARK := Color(0, 0, 0, 0.5)   ## a black texel half and half: the scene halved
const STR_NOW_LOADING := 0x800B0D54
const STR_BONUS_LEFT := 0x800B0D6C
const STR_STAGE_BONUS := 0x800B0D80
const STR_CLEAR_BONUS := 0x800B0D9C
const STR_CLEAR_TIME := 0x800B0DB8
const STR_BONUS_TIME := 0x800B0DDC
const STR_KEY := 0x800B0E00
const STR_FINAL := 0x800B0E18
const STR_LIFE_UP := 0x800B0EF0
const PLAYER_BAR := 0x9C
const BAR_HEIGHT := 0x18
const CAP := Vector2(6, 24)
const BAR_TOP := 0x1B4
const BAR_BOTTOM := 0x1C4
const BAR_LEFT := 0x40
const SEGMENT := 0x3C
const POINTER_Y := 0x1A8
const KEY_SIZE := Vector2i(20, 36)
const KEY_Y := 0x1A4
const KEY_VRAM := Vector2i(688, 320)
const KEY_CLUT := Vector2i(128, 486)
const GAUGE_WIDTH := 0x4C
const GAUGE_CAP_RIGHT := 0x4A
const GAUGE_FILL_CLUTS := [0x7EDE, 0x7EDD]   ## the fill: channel 0x3E, 0x3D of the bar CLUTs
const POPUP_SHIFT := {0: Vector2i(5, 8), 1: Vector2i(7, 12), 2: Vector2i(12, 20)}
const TALLY_AT := [0x1E, 0x3C, 0x5A, 0x78]
const STREAK_BOTTOM := 0x1E0

var force_ram: GameRam
var keys_vram: VramImage
var _sim: FightSimulation
var _shown := false
var _glow := Rect2()                   ## the progress bar's additive part this frame
var _glow_colour := Color.BLACK


func setup_modes(hud_data: HudData, exe: GameRam, system: VramImage, force: GameRam, screens_dir: String) -> void:
	setup_psx(hud_data, exe, system)
	force_ram = force
	keys_vram = system.duplicate_image()
	keys_vram.upload_file(screens_dir.path_join("force_keys.tims"))
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _streaks)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _progress_glow)


## After a simulation step.
func show_state(sim: FightSimulation, fighting: bool) -> void:
	_sim = sim
	var mode := sim.fight.mode
	_shown = fighting and (mode == GameMode.BALL or mode == GameMode.FORCE)
	visible = _shown
	if _shown:
		redraw()


func _draw() -> void:
	if not _shown or _sim == null:
		return
	begin()
	var fight := _sim.fight
	if fight.mode == GameMode.FORCE and fight.force != null:
		_force(fight)
	elif fight.mode == GameMode.BALL and fight.ball != null:
		_ball(fight)


# ---- Tekken Force -------------------------------------------------------------------------------

func _force(fight: FightState) -> void:
	var force := fight.force
	if fight.replay_playing == 0 and fight.hud_shown != 0:
		for i in 3:
			if _visible(fight, i):
				_name(fight, i)
				_bar(force, i)
		_progress(force)
		_keys(force)
	_life_up(force)
	for i in 2:
		if force.slot_popup_shown(i):
			_seconds(force, i)
	match force.g32(TekkenForce.STATE):
		4:
			print_fmt(ram_text(STR_NOW_LOADING), [0, 6, 0xF2, 0x1A6])
		6:
			_bonus_left(force)
		7:
			_tally(force)


func _record(fight: FightState, i: int) -> FighterState:
	return fight.force.player() if i == 0 else fight.force.slot_fighter(i - 1)


## A shown enemy: not hidden (+0xC2) and past the round's intro.
func _visible(fight: FightState, i: int) -> bool:
	if i == 0:
		return true
	return _record(fight, i).invulnerable == 0 and fight.round_state != RoundState.INTRO


func ram_text(address: int) -> String:
	return force_ram.string(address)


func _name(fight: FightState, i: int) -> void:
	var f := _record(fight, i)
	var tex := hud.name_texture(f.costume_slot)
	if tex == null:
		return
	var w := hud.name_width(f.costume_slot)
	var x := force_ram.s16(NAME_POS + 8 * i)
	var y := force_ram.s16(NAME_POS + 8 * i + 2)
	if i > 0:
		x -= w
	var plate := hud.plate_texture(f.costume_slot)
	if plate != null:
		image(plate, x - 4, y + 9, w + 8, 10)
	image(tex, x, y, w, 16)


func _bar(force: TekkenForce, i: int) -> void:
	var b := force.bar(i)
	var fill := b[1]
	var recent := b[2]
	var right := b[3] == 1
	var bx := b[4]
	var y := b[5]
	var length := b[6]
	var full := length - 4
	var x := bx if i == 0 else bx - (length - PLAYER_BAR)
	image(hud.texture("bar_cap_left.png"), x, y, CAP.x, CAP.y)
	image(hud.texture("bar_cap_right.png"), x + length - 6, y, CAP.x, CAP.y)
	var pos := float(bx + 0x9A)
	var parts := [["bar_health.png", fill], ["bar_damage.png", recent - fill], ["bar_empty.png", full - recent]]
	for part: Array in parts:
		var n: int = part[1]
		if n <= 0:
			continue
		var a := pos
		if right:
			pos += n
		else:
			pos -= n
			a = pos
		image(hud.texture(str(part[0])), a, y, n, BAR_HEIGHT)


## The level progress bar: four 60-pixel segments from x 64 (lit up to the current level, the
## current one pulsing and split at the camera's marker), the marker and its pointer.
func _progress(force: TekkenForce) -> void:
	var level := force.level()
	var start := level * SEGMENT
	var x0 := start + BAR_LEFT
	var mark := start + 0x7C
	if force.gu32(TekkenForce.BAR_DONE) == 0:
		var v := Fx.w32((_sim.camera.view.x - force.g32(TekkenForce.START_X)) * SEGMENT)
		mark = mini(x0 + ((v + 0x7FFF if v < 0 else v) >> 15), start + 0x7C)
	if level == 4:
		mark = x0 + 0xC
	var phase := force.gu32(TekkenForce.BAR_PHASE) & 0xFFF
	var pulse := mini(((_sim.fight.tables.sin_table[phase] + 0x1000) >> 6) + 0x80, 0xFF)
	var height := BAR_BOTTOM - BAR_TOP
	_glow = Rect2()
	# Each segment is one texel through its CLUT (a colour of BAR_COLOURS at 5 bits, semi-
	# transparent): half and half over the scene when lit (vertex colour 0x80), the scene halved
	# when not (colour 0); the current level's part up to the marker is additive and pulses.
	for i in 4:
		var x := BAR_LEFT + SEGMENT * i
		if i == level:
			_glow = Rect2(x0, BAR_TOP, mark - x0, height)
			_glow_colour = _modulated(_bar_colour(i), pulse)
			fill(mark, BAR_TOP, x0 + SEGMENT - mark, height, HALF_DARK)
		elif i < level:
			fill(x, BAR_TOP, SEGMENT, height, Color(_bar_colour(i), 0.5))
		else:
			fill(x, BAR_TOP, SEGMENT, height, HALF_DARK)
	if level == 4:
		# The Doctor B. level: the short fifth piece after the four segments pulses instead.
		_glow = Rect2(BAR_LEFT + 4 * SEGMENT, BAR_TOP, 0xC, height)
		_glow_colour = _modulated(_bar_colour(3), pulse)
	for k in 5:
		line(0x3F + SEGMENT * k, BAR_TOP, 0x3F + SEGMENT * k, BAR_BOTTOM, Color.WHITE)
	line(mark, BAR_TOP, mark, BAR_BOTTOM, Color.WHITE)
	var s := _sim.fight.tables.sin_table[phase] * 12
	var half := (Fx.div_trunc(s, 4096)) >> 1
	var points := PackedVector2Array([pt(mark - half, POINTER_Y), pt(mark + half, POINTER_Y), pt(mark, BAR_TOP)])
	target.draw_polygon(points, PackedColorArray([Color8(0, 0x80, 0xFF), Color8(0, 0x80, 0xFF), Color.WHITE]))


## A segment's CLUT colour: BAR_COLOURS (4 bytes apart) at 5 bits per channel (FUN_800B396C).
func _bar_colour(i: int) -> Color:
	var c := PackedFloat32Array()
	for k in 3:
		c.append((force_ram.u8(BAR_COLOURS + 4 * i + k) >> 3) / 31.0)
	return Color(c[0], c[1], c[2])


## A texel modulated by a vertex colour (0x80 neutral, saturating).
static func _modulated(c: Color, level: int) -> Color:
	var m := level / 128.0
	return Color(minf(c.r * m, 1.0), minf(c.g * m, 1.0), minf(c.b * m, 1.0))


## The additive pass: the current level's pulsing part of the progress bar.
func _progress_glow() -> void:
	if not _shown or _sim == null or _sim.fight.mode != GameMode.FORCE or not _glow.has_area():
		return
	if _sim.fight.replay_playing != 0 or _sim.fight.hud_shown == 0:
		return
	fill(_glow.position.x, _glow.position.y, _glow.size.x, _glow.size.y, _glow_colour)


## One key per key earned: copper, silver, gold (20 × 36 at x 0, 20, 40).
func _keys(force: TekkenForce) -> void:
	for i in 3:
		if force.g32(TekkenForce.KEYS) > i:
			var tex := keys_vram.picture(KEY_VRAM.x, KEY_VRAM.y + KEY_SIZE.y * i, KEY_SIZE.x, KEY_SIZE.y,
				(KEY_CLUT.y << 6) | ((KEY_CLUT.x + 16 * i) >> 4), 0)
			image(tex, KEY_SIZE.x * i, KEY_Y, KEY_SIZE.x, KEY_SIZE.y)


func _screen(point: PackedInt32Array, view: ViewMatrix) -> PackedInt32Array:
	if view == null:
		return PackedInt32Array([0, 0, 0])
	return view.screen_of(JointFrame.new(Fx.identity(), point))


## A picked-up item's LIFE UP!, rising half a pixel a frame, flashing (the placed items are
## ForceItemsView's, in the scene).
func _life_up(force: TekkenForce) -> void:
	var clock := force.g32(TekkenForce.CLOCK)
	for i in 2:
		if force.gu32(TekkenForce.ITEMS + 0xBC * i) == 2:
			var p := force.item_popups[i]
			var s := _screen(p.point, p.view)
			var elapsed := clock - (p.until - 0x3C)
			var colour := 2 if clock & 2 else 5
			print_fmt(ram_text(STR_LIFE_UP), [0, colour, s[0] - 0x24, s[1] - (elapsed * 8 >> 4)])


## "+n SEC" over a defeated enemy, rising half a pixel a frame.
func _seconds(force: TekkenForce, i: int) -> void:
	var p := force.slot_popups[i]
	var s := _screen(p.point, p.view)
	var clock := force.g32(TekkenForce.CLOCK)
	var y := s[1] - ((clock - (p.until - 0x3C)) * 8 >> 4)
	var kind := force.g16(TekkenForce.slot(i) + 0xE)
	var seconds := force_ram.u16(TekkenForce.KILL_SECONDS + 4 * kind + 2)
	var x := float(s[0] - 0x1B)
	print_fmt("%f%c%H%V+", [0, 5, x, y + 4])
	x += text_width("+", 0)
	print_fmt("%f%c%H%V%d", [1, 5, x, y, seconds])
	x += text_width(str(seconds), 1)
	print_fmt("%f%c%H%VSEC", [0, 6, x, y + 6])


## The bonus time left over the player (FUN_800B1778 state 6).
func _bonus_left(force: TekkenForce) -> void:
	var b := force.g32(TekkenForce.BONUS_TIME)
	var p := force.player()
	if b <= 0 or p.health <= 0:
		return
	var s := _screen(PackedInt32Array([p.root_x, p.root_y - 500, p.root_z]), _sim.view)
	var seconds := Fx.div_trunc(b, 60)
	seconds -= Fx.div_trunc(seconds, 60) * 60
	var hundredths := Fx.div_trunc(Fx.w32(b * 100), 60)
	hundredths -= Fx.div_trunc(hundredths, 100) * 100
	print_fmt(ram_text(STR_BONUS_LEFT), [0, 5, s[0] - 0x16, s[1], seconds, hundredths])


static func _mss(t: int) -> PackedInt32Array:
	var m := Fx.div_trunc(t, 3600)
	var hundredths := Fx.div_trunc(t * 100, 60)
	return PackedInt32Array([m - Fx.div_trunc(m, 60) * 60, Fx.div_trunc(t, 60) - 60 * m,
		hundredths - Fx.div_trunc(hundredths, 100) * 100])


## The stage clear tally (state 7): the lines appear 30 frames apart.
func _tally(force: TekkenForce) -> void:
	var lines := force.tally_lines()
	var t := lines[0]
	if t >= TALLY_AT[0]:
		print_fmt(ram_text(STR_STAGE_BONUS), [1, 4, 0x2F, 0xB4, lines[1]])
	if t >= TALLY_AT[1]:
		print_fmt(ram_text(STR_CLEAR_BONUS), [1, 1, 0x2F, 0xE8, lines[2]])
	var cs := 0
	if t >= TALLY_AT[2]:
		var clear := _mss(lines[3])
		cs = clear[2]
		print_fmt(ram_text(STR_CLEAR_TIME), [1, 5, 0x2F, 0x11C, clear[0], clear[1], clear[2]])
	if t < TALLY_AT[3]:
		return
	match lines[5]:
		0:
			var bonus := _mss(lines[4])
			var c := bonus[2]
			if cs + c < 100:
				c = 100 - cs
			print_fmt(ram_text(STR_BONUS_TIME), [1, 6, 0x2F, 0x150, bonus[0], bonus[1], c])
		1:
			print_fmt(ram_text(STR_KEY), [1, 6 if t & 2 else 2, 0x56, 0x150])
		2:
			print_fmt(ram_text(STR_FINAL), [1, 6 if t & 4 else 2, 0x22, 0x150])


# ---- Tekken Ball ---------------------------------------------------------------------------------

func _ball(fight: FightState) -> void:
	var tb := fight.ball
	if fight.replay_playing == 0 and fight.hud_shown != 0:
		for g in 2:
			_gauge(fight, tb, g)
	for p: TekkenBall.BallPopup in tb.popups:
		var s := _screen(p.point, p.view)
		var shift: Vector2i = POPUP_SHIFT.get(p.font, Vector2i.ZERO)
		var x := s[0] - shift.x * p.text.length()
		var y := s[1] - shift.y - p.rise
		print_fmt("%c%f%H%V" + p.text, [p.colour, p.font, x, y])


## The ball's render kind 2 (a point): four additive Gouraud triangles in the 2D ordering table,
## white at the ball's centre, 0x303030 at the screen's bottom (the first two) or top edge, 8 ×
## the kind's strength wide there, from the centre's x plus each streak's jitter.
func _streaks() -> void:
	if not _shown or _sim == null or _sim.fight.mode != GameMode.BALL or _sim.fight.ball == null:
		return
	var b := _sim.fight.ball.b
	if b.u8(TekkenBall.B_KIND) != 2:
		return
	var c := _screen(PackedInt32Array([b.s32(TekkenBall.B_POS), b.s32(TekkenBall.B_POS + 4),
		b.s32(TekkenBall.B_POS + 8)]), _sim.view)
	var k := b.u8(TekkenBall.B_TIMER)
	var edge := Color8(0x30, 0x30, 0x30)
	for i in 4:
		var x := c[0] + _sim.fight.ball.streaks[i]
		var y := 0 if i & 2 else STREAK_BOTTOM
		# The packet's coordinates as the GPU takes them (the jitter can reach past 11 bits).
		var v: Array[Vector2i] = []
		for p: Vector2i in [Vector2i(c[0], c[1]), Vector2i(x, y), Vector2i(x + 8 * k, y)]:
			v.append(Vector2i(gpu_coordinate(p.x), gpu_coordinate(p.y)))
		if not gpu_draws(v):
			continue
		target.draw_primitive(PackedVector2Array([pt(v[0].x, v[0].y), pt(v[1].x, v[1].y), pt(v[2].x, v[2].y)]),
			PackedColorArray([Color.WHITE, edge, edge]), PackedVector2Array())


## A 76-pixel power gauge: the fill in the player's colour, the trail, the rest; the charging
## player's pulses.
func _gauge(fight: FightState, tb: TekkenBall, g: int) -> void:
	var s := tb.gauge(g)
	var fill_px := s[0]
	var trail := s[1]
	var right := s[2] == 1
	var x := s[3]
	var y := s[4]
	var tint := Color(0.5, 0.5, 0.5) * 2.0
	if tb.gauge_highlight == 1 << g and fight.pause_request == 0:
		var k := ScreenCanvas.triangle(fight.vblank << 4) / 255.0
		tint = Color(k, k, k) * 2.0
	image(hud.texture("bar_cap_left.png"), x, y, CAP.x, CAP.y, tint)
	image(hud.texture("bar_cap_right.png"), x + GAUGE_CAP_RIGHT, y, CAP.x, CAP.y, tint)
	var pos := float(x + 2 if right else x + 0x4E)
	var parts := [[GAUGE_FILL_CLUTS[g], fill_px], [0x7EDC, trail - fill_px], [0x7EDF, GAUGE_WIDTH - trail]]
	for part: Array in parts:
		var n: int = part[1]
		if n <= 0:
			continue
		var a := pos
		if right:
			pos += n
		else:
			pos -= n
			a = pos
		var tex := vram.sprite(0xE8, 0xA8, 2, 24, part[0] as int, 0x0D)
		image(tex, a, y, n, BAR_HEIGHT, tint)
