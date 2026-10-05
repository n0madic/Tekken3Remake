class_name MainMenu
extends FlowPart
## The main menu (title.ovl FUN_800DBBD0, game state 4; menu_sim.main_menu, verified): the list of
## modes, the cursor (up / down with repeat, wrapping; VS MODE is skipped with one controller),
## the choice (Start or a face button) and the time-out back to the title after 480 frames.

const TIMEOUT := 0x1E1
const SCROLL_STEP := 0x1C
const CHOOSE_BUTTONS := PadState.CONFIRM
const SOUND_CURSOR := 0x546C
const SOUND_CHOOSE := 0x4D87
const MODE_BALL := GameMode.BALL
const MODE_FORCE := GameMode.FORCE
const MODE_OPTIONS := 9
const MODE_THEATER := 10

class Entry:
	var entry: FlowData.MenuEntry
	var new := false                  ## +7: the NEW mark


var entries: Array[Entry] = []      ## 0x800EC590: the entries shown
var scroll := 0                      ## 0x800EC588: the list's slide offset
var glow := 0                        ## 0x800EC58C
var chosen := 0                      ## 0x800EC580
var players := 0                     ## 0x800EC574: the pads that chose


func cursor() -> int:
	return g.progress.menu_cursor


## The drawing's own state (menu_sim._main_menu_draw): the slide decays by a quarter each frame
## (rounded up), and the choice bars glow in once the list rests.
func draw_step() -> void:
	var v := scroll
	var n := 0
	if v != 0:
		var a := absi(v)
		n = maxi(a - ((a + 3) >> 2), 0)
		if v < 0:
			n = -n
	scroll = n
	if scroll == 0:
		glow = mini(glow + 0x18, 0x100)
	else:
		glow = 0


func step() -> void:
	_step()
	draw_step()


func _step() -> void:
	var pressed := g.pressed_any()
	var rep := g.repeat(0) | g.repeat(1)
	var one_pad := g.sim.pads.connected & 1 == 0 or g.sim.pads.connected & 2 == 0
	match g.sub:
		0:
			_open()
		1:
			g.sim.state_timer += 1
			if g.sim.state_timer < TIMEOUT:
				var cur := g.progress.menu_cursor
				var step_dir := ((rep >> 14) & 1) - ((rep >> 12) & 1)
				var count := entries.size()
				if count <= cur:
					cur = 0
				var nxt := 0
				while true:
					nxt = (cur + step_dir) & 0xFFFFFFFF
					if count <= nxt:
						nxt = (count - (cur + 1)) & 0xFFFFFFFF
					scroll += step_dir * SCROLL_STEP
					if entries[nxt].entry.two_players != 1 or not one_pad:
						break
					cur = nxt
					if step_dir == 0:
						step_dir = 1
				g.progress.menu_cursor = nxt
				if step_dir != 0:
					g.sim.state_timer = 8
					g.sound(SOUND_CURSOR)
				if pressed & CHOOSE_BUTTONS:
					g.sound(SOUND_CHOOSE)
					chosen = 1
					scroll = 0
					glow = 0x100
					players = 1 if g.pressed(0) & CHOOSE_BUTTONS else 0
					if g.pressed(1) & CHOOSE_BUTTONS:
						players |= 2
					g.sub = 2
			else:
				g.sub = 3
				chosen = 1
		2:
			var mode := entries[g.progress.menu_cursor].entry.mode
			if mode == MODE_OPTIONS:
				g.goto_transition(GameFlow.State.OPTIONS)
			elif mode == MODE_THEATER:
				if g.progress.theater_new < 3:
					g.progress.theater_new += 1
				g.fight.human_mask = 0
				g.goto_screen_loader(GameFlow.State.ENDING)
			else:
				if mode == MODE_BALL and g.progress.ball_new < 3:
					g.progress.ball_new += 1
				ModeStart.start(g, mode, players)
		3:
			g.goto_transition(GameFlow.State.TITLE)


## Sub-state 0: the controllers reset, the players and the key configuration, the entries (Tekken
## Ball and Theater once unlocked, NEW while their counter is below 3).
func _open() -> void:
	g.controllers_reset()
	g.globals.player_active[1] = 0
	g.globals.player_active[0] = 0
	button_map(0)
	button_map(1)
	entries.clear()
	chosen = 0
	for e in g.data.menu_entries:
		var v := 3
		if e.mode == MODE_BALL:
			v = g.progress.ball_new
		elif e.mode == MODE_THEATER:
			v = g.progress.theater_new
		if v != 0:
			var shown := Entry.new()
			shown.entry = e
			shown.new = v < 3
			entries.append(shown)
	if g.progress.menu_to_options != 0:
		g.progress.menu_to_options = 0
		var i := 0
		while i < entries.size() and entries[i].entry.mode != MODE_OPTIONS:
			i += 1
		g.progress.menu_cursor = 0 if i > 10 else i
	g.sim.state_timer = 0
	scroll = 0
	glow = 0
	g.sub = 1


## FUN_800DE7B4: a player's button layout (the save block's actions per pad button) into the
## key table the pads are read with.
func button_map(player: int) -> void:
	var table := g.key_tables[player]
	for k in 8:
		table[k] = g.data.button_actions[g.progress.button_action(player, k)]
	for k in 8:
		table[8 + k] = g.data.button_tail[k]
	g.key_tables[player] = table
