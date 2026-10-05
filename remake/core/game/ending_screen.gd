class_name EndingScreen
extends FlowPart
## Game state 19 (ending.ovl FUN_8010E8C0; modes.md#arcade-ending-and-staff-roll): after an
## arcade clear the winner's ending movie, then the staff roll over black, then the ranking.
## Theater (the same state with 0x800AE158 set) is TheaterScreen.
##
## The game plays the movie inside one frame (the main loop waits); GameFlow does the same by
## holding its frames while `movie_blocking` is set, and finishes the frame when the movie ends.

const SECOND_CLEAR_MOVIE := 0x18
const CHARACTERS_WITH_ENDINGS := 0x15
const MUSIC_ROLL := 4

var roll: StaffRoll
var all_movies := 0                  ## 0x800AE164: every movie is open (Theater's disc buttons)


func _init(flow: GameFlow) -> void:
	super(flow)
	roll = StaffRoll.new(flow.data)


## The screen overlay was loaded: its flags start clear.
func loaded() -> void:
	roll.reset()


func step() -> void:
	match g.sub:
		0:
			g.sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
			g.theater.disc = 3
			all_movies = g.theater.all_movies()
			g.theater.movie = ending_movie()
			if g.theater.kind != 0:
				g.theater.open()
				return
			g.sub = 2
		2:
			g.start_blocking_movie(g.theater.movie)
		3:
			if roll.step(g):
				g.goto_ranking()
		_:
			g.theater.step()


## The movie has ended (the rest of sub-state 2's frame): the roll starts.
func after_movie() -> void:
	if g.theater.kind != 0:
		g.theater.after_movie()
		return
	roll.start()
	g.sim.events.add(SimEvents.Kind.MUSIC_PREPARE, -1, MUSIC_ROLL)
	g.sub = 3


## FUN_8010E7D0: the ending of the human's character and costume (Doctor B.'s second clear has
## its own); with no single human, movie 0 and Theater's flag set (as the game does).
func ending_movie() -> int:
	var mask := g.fight.human_mask
	g.theater.kind = 0
	if mask >= 3 or mask == 0:
		g.theater.kind = 1
		return 0
	var key := g.fight.fighters[mask - 1].costume_key
	var character := Fx.s16(key) >> 2 if key >= 0 else (Fx.s16(key) + 3) >> 2
	var costume := key & 3
	if character < 0 or character >= CHARACTERS_WITH_ENDINGS:
		character = 0
		costume = 0
	var m := g.data.ending_movies[character * 4 + costume]
	if character == Character.GUN_JACK and g.progress.cleared2 & (1 << Character.GUN_JACK):
		m = SECOND_CLEAR_MOVIE
	return m
