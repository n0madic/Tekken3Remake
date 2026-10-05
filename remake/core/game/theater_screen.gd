class_name TheaterScreen
extends FlowPart
## THEATER MODE (ending.ovl, game state 19 with 0x800AE158 set; modes.md#theater), written from
## the verified port `tools/research/theater_sim.py` (entry_status, movie_input, sound_input) and the
## decompiled state handler FUN_8010E8C0. The movie page (a grid of the Tekken 3 movies) and the
## sound player (the Tekken 3 tracks, arranged or arcade). The Tekken 1 and 2 disc mode is out of
## scope: the DISC button is never offered. Without movies the Theater opens on the sound page;
## without music the sound page is not offered.

const PAGE_MOVIES := 1
const PAGE_ARRANGE := 2
const PAGE_ARCADE := 3
const COLUMNS := 6
const ROWS_SHOWN := 4
const LINES_SHOWN := 14
const SOUND_MOVE := 0x546C
const SOUND_OK := 0x4CEB
const CHOOSE := PadState.CONFIRM
## The clear bits naming a shared ending slot: the first name, the second (NAMES in theater_sim).
static var SHARED_SLOTS := {"0": PackedInt32Array([0x10, 0x80000]), "1": PackedInt32Array([0x800, 0x800]),
	"2": PackedInt32Array([0x10000, 0x10000]), "3": PackedInt32Array([0x4000, 0x100000])}
enum Focus { LIST, EXIT, SWITCH, DISC, BGM }
enum Choice { NONE, PLAY, EXIT = 4, DISC = 5 }

var kind := 0                        ## 0x800AE158: 0 arcade ending, 1 movies, 2 arranged sound, 3 arcade sound
var disc := 3                        ## 0x800AE159
var movie := 0                       ## 0x800AE15C: the movie to play
var track := 0                       ## 0x800AE15D: the sound list entry to play
var cursor := 0                      ## 0x800AE15E
var top := 0                         ## 0x800AE15F: the first row (grid) or line (list) shown
var focus := Focus.LIST              ## 0x800AE162
var music_available := true


## FUN_8010FC7C: the movie a list entry plays, −1 while locked (−2 marks an empty cell).
func entry_status(i: int) -> int:
	var e: Dictionary = g.data.theater_movies[i]
	var mask := JsonFile.number(e["mask"])
	if mask == 0:
		return JsonFile.number(e["movie"])
	var cleared := g.progress.cleared
	var cleared2 := g.progress.cleared2
	match JsonFile.number(e["rule"]):
		0:
			return JsonFile.number(e["movie"]) if cleared & mask else -1
		1, 2:
			# Kuma / Panda, Gun Jack's two endings.
			var bit := 0x800 if JsonFile.number(e["rule"]) == 1 else 0x10000
			if cleared2 & bit:
				return JsonFile.number(e["alternative"])
			return JsonFile.number(e["movie"]) if cleared & bit else -1
		3:
			# Tiger: Eddy's second-costume clear.
			return JsonFile.number(e["movie"]) if cleared2 & 0x100 else -1
	return -1


## FUN_801109D4: 1 when no Tekken 3 movie is locked.
func all_movies() -> int:
	for i in g.data.theater_movies.size():
		if entry_status(i) == -1:
			return 0
	return 1


## FUN_8010F634: an entry's name; names "0"–"3" stand for shared ending slots, named by the clears.
func movie_name(i: int) -> String:
	var e: Dictionary = g.data.theater_movies[i]
	var name := str(e["name"])
	if not g.data.theater_names.has(name):
		return name
	var pair: PackedInt32Array = SHARED_SLOTS[name]
	var c := g.progress.cleared
	var second := g.progress.cleared2 if name in ["1", "2"] else c
	var which := (1 if c & pair[0] else 0) | (2 if second & pair[1] else 0)
	if which == 0:
		return ""
	var names: Array = g.data.theater_names[name]
	return str(names[which - 1])


## FUN_80111A08.
func reset() -> void:
	cursor = 0
	top = 0
	focus = Focus.LIST


## Sub-state 0 of Theater: its first page.
func open() -> void:
	reset()
	if not g.movies_available and music_available:
		kind = PAGE_ARRANGE
	g.sub = 1


## Sub-states 1 (the pages) and 10 (leaving).
func step() -> void:
	match g.sub:
		1:
			match _input():
				Choice.PLAY:
					if kind == PAGE_MOVIES:
						g.sub = 2
					else:
						g.sim.events.add(SimEvents.Kind.MUSIC_TRACK, -1, track >> 1, track & 1)
				Choice.EXIT:
					g.sub = 10
		10:
			g.music_stop()
			g.goto_transition(GameFlow.State.MENU)
		_:
			g.sub = 1


## The movie has ended: back to the grid.
func after_movie() -> void:
	g.sub = 1


func _input() -> int:
	return _movie_input() if kind == PAGE_MOVIES else _sound_input()


func _pads() -> Vector2i:
	return Vector2i(g.pressed_any(), g.repeat(0) | g.repeat(1))


## FUN_80111A68: the movie grid.
func _movie_input() -> int:
	var pads := _pads()
	var pressed := pads.x
	var rep := pads.y
	var count := g.data.theater_movies.size()
	var old := cursor
	var focus0 := focus
	var col := old % COLUMNS
	var row := old / COLUMNS
	var sound_page := music_available and all_movies() != 0
	if focus0 == Focus.LIST:
		if rep & PadState.LEFT:
			if col > 0 and entry_status(row * COLUMNS + col - 1) >= -1:
				col -= 1
		elif rep & PadState.RIGHT:
			if col < COLUMNS - 1 and entry_status(row * COLUMNS + col + 1) >= -1:
				col += 1
		if rep & PadState.UP:
			if row > 0:
				row -= 1
			if row < top:
				top -= 1
		elif rep & PadState.DOWN:
			row += 1
			if row < count / COLUMNS:
				if entry_status(col + row * COLUMNS) < -1:
					# An empty cell: slide towards the middle.
					var dir := 1 if col < 3 else -1
					while entry_status(col + row * COLUMNS) < -1:
						col += dir
			else:
				focus = Focus.SWITCH if sound_page else Focus.EXIT
				row -= 1
			if row >= top + ROWS_SHOWN:
				top += 1
	else:
		if sound_page:
			if rep & PadState.LEFT and focus0 == Focus.EXIT:
				focus = Focus.SWITCH
			elif rep & PadState.RIGHT and focus0 == Focus.SWITCH:
				focus = Focus.EXIT
		if rep & PadState.UP:
			focus = Focus.LIST
	var cur := col + row * COLUMNS
	if cur < 0:
		cur = count - 1
	elif cur >= count:
		cur = 0
	cursor = cur
	if cur != old or focus != focus0:
		g.sound(SOUND_MOVE)
	if pressed & CHOOSE == 0:
		if pressed & PadState.SELECT:
			g.sound(SOUND_OK)
			return Choice.EXIT
		return Choice.NONE
	match focus:
		Focus.LIST:
			var s := entry_status(cursor)
			if s < 0:
				return Choice.NONE
			g.music_stop()
			movie = s
			return Choice.PLAY
		Focus.SWITCH:
			g.sound(SOUND_OK)
			reset()
			kind = PAGE_ARRANGE
		Focus.EXIT:
			g.sound(SOUND_OK)
			return Choice.EXIT
	return Choice.NONE


## FUN_80111FEC: the sound list.
func _sound_input() -> int:
	var pads := _pads()
	var pressed := pads.x
	var rep := pads.y
	var old := cursor
	var count := g.data.theater_tracks.size()
	var focus0 := focus
	var cur := old
	# Without movies the THEATER button (SWITCH) is not offered: the buttons start at BGM SELECT.
	var top_button := Focus.SWITCH if g.movies_available else Focus.BGM
	if focus0 == Focus.LIST:
		if rep & PadState.RIGHT:
			focus = top_button
		elif rep & PadState.UP:
			if old > 0:
				cur = old - 1
				if cur < top:
					top -= 1
		elif rep & PadState.DOWN:
			if old < count - 1:
				cur = old + 1
				if cur >= top + LINES_SHOWN:
					top += 1
	elif rep & PadState.LEFT:
		focus = Focus.LIST
	elif rep & PadState.UP:
		# Up: EXIT, (DISC,) BGM SELECT, THEATER.
		match focus0:
			Focus.EXIT: focus = Focus.BGM
			Focus.BGM: focus = top_button
	elif rep & PadState.DOWN:
		match focus0:
			Focus.SWITCH: focus = Focus.BGM
			Focus.BGM: focus = Focus.EXIT
	cursor = cur
	if cur != old or focus != focus0:
		g.sound(SOUND_MOVE)
	if pressed & CHOOSE == 0:
		if pressed & PadState.SELECT:
			g.sound(SOUND_OK)
			return Choice.EXIT
		return Choice.NONE
	match focus:
		Focus.LIST:
			var entry: Dictionary = g.data.theater_tracks[cursor]
			track = JsonFile.number(entry["track"])
			if kind == PAGE_ARCADE:
				track |= 1
			g.music_stop()
			return Choice.PLAY
		Focus.SWITCH:
			g.music_stop()
			g.sound(SOUND_OK)
			reset()
			kind = PAGE_MOVIES
		Focus.BGM:
			g.music_stop()
			g.sound(SOUND_OK)
			kind ^= 1
		Focus.EXIT:
			g.sound(SOUND_OK)
			return Choice.EXIT
	return Choice.NONE
