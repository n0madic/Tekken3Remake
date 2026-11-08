class_name ArcadeEnding
extends ArcadeFlowPart
## The game flow's state 8 (FUN_801E5F50): ALL STAGE CLEAR, the staff roll over the replays of the
## fights the player won, the winner's last pose with the credits, the logo. Start leaves it for the
## ranking from the staff roll on. Two blocking waits of the game (VSync in a loop, which hold the
## last picture until a page has had its 400 vblanks) make their frame last longer (`wait_vblanks`).

const CLEAR := 1
const FIRST_PAGE_START := 4
const FIRST_PAGE_LOAD := 6
const PAGE_SUBS := 4
const FIRST_PAGE := 7
const LAST_PAGE := 9
const POSE_WAIT := 0x34
const POSE_START := 0x35
const POSE := 0x36
const LOGO_START := 0x37
const LOGO := 0x38
const MUSIC := 0x65
const WIN_POSE_SLOT := 0xE5D            ## FUN_8018ED4C
const PAGE_VBLANKS := 400
const PAGE_SHORT := 0x18E
const FADE_IN_END := 0x40
const FADE_IN_TOP := 0x1FF
const NEUTRAL_FADE := 0x100
const HELD_FADE := 0xCA
const FADE_OUT_FROM := 0x120
const FADE_OUT_FIRST := 0x11F
const CLEAR_END := 0x160
const OFF_SCREEN := 0x200
const TEXT_LEAD := 0x50
const SLIDE_END := 0x40
const SLIDE_STEP := 4
const STOPPED_FRAMES := 1
const ROUND_ENDED := 2
const CREDITS_FROM := 0x1E
const LOGO_CLOCK := 0x140
const LOGO_RISE := 0x100
const LOGO_HOLD := 0x80

var winner := 0                         ## 0x80375182
var clock := 0                          ## 0x8021FA7C
var page_start := 0                     ## 0x8021FA88
var page_frames := 0                    ## 0x8021FA8C
var stopped := 0                        ## 0x8021FD50
var win_pose: MoveRow                   ## 0x8021FA84
var replays := 0                        ## 0x8021FA94: the pages played
var wait_vblanks := 0                   ## the frame's blocking wait before a page or the last pose

# What the view shows of this frame.
var slide := OFF_SCREEN                 ## FUN_801E5E4C's offset of the page's two blocks
var title_shown := false                ## the first page's title
var credits_shown := false              ## the last pose's
var clear_clock := 0                    ## the clear screen's clock


func start(player: int) -> void:
	winner = player
	replays = 0


## The page of a sub-state.
func page() -> int:
	return (flow.sub - FIRST_PAGE) >> 2


## The frames that show the fight view: from the first replay on.
func in_fight() -> bool:
	return replays > 0 and flow.sub <= POSE


func step() -> void:
	var g := flow
	wait_vblanks = 0
	if g.pressed(winner) & ArcadeGameFlow.START != 0 and g.sub > 3:
		_leave()
		return
	match g.sub:
		0:
			g.music(MUSIC)
			clock = 0
			stopped = 0
			g.sub = CLEAR
			_clear()
		CLEAR:
			_clear()
		POSE_WAIT:
			_pose_wait()
		POSE_START:
			_pose_start()
		POSE:
			_pose()
		LOGO_START:
			g.sub = LOGO
			_logo()
		LOGO:
			_logo()
		_:
			_pages()


func _leave() -> void:
	var g := flow
	g.stop_sounds(1)
	g.state = ArcadeGameFlow.State.RANKING
	g.sub = 0


func _clear() -> void:
	var g := flow
	var next := clock + 1
	var level := NEUTRAL_FADE
	if next < FADE_IN_END:
		level = next * -4 + FADE_IN_TOP
	elif next < FADE_OUT_FROM:
		if next > FADE_IN_END:
			level = HELD_FADE
	else:
		level = (clock - FADE_OUT_FIRST) * 5 + HELD_FADE
		if next > CLEAR_END:
			g.sub = FIRST_PAGE_START
	clock = next
	clear_clock = clock
	g.add_fade(level)


## The sub-states from 2 to 0x33, four per page: the wait and load, the page, two frames between.
func _pages() -> void:
	var g := flow
	var kind := (g.sub - FIRST_PAGE_START) & (PAGE_SUBS - 1)
	if g.sub == FIRST_PAGE_START:
		page_start = g.frame()
	if g.sub >= FIRST_PAGE_LOAD and kind == FIRST_PAGE_LOAD - FIRST_PAGE_START:
		_page_load()
	elif g.sub >= FIRST_PAGE and kind == FIRST_PAGE - FIRST_PAGE_START:
		_page()
	else:
		g.sub += 1


func _page_load() -> void:
	var g := flow
	var elapsed := g.frame() - page_start
	if elapsed < PAGE_SHORT and g.sub != FIRST_PAGE_LOAD:
		wait_vblanks = maxi((PAGE_VBLANKS - elapsed) >> 1, 0) * 2
	page_start = g.frame()
	if not g.sim.load_kept_fight((g.sub - FIRST_PAGE_START) >> 2):
		g.sub += 2
		return
	flow.fight.freeze = 0
	replays += 1
	page_frames = (g.fight.replay as ArcadeReplay).kept[(g.sub - FIRST_PAGE_START) >> 2].count - 1
	clock = 0
	stopped = 0
	g.sub += 1
	_page()


## FUN_801E5E4C's offset: the page's blocks arrive 0x50 frames before the replay's end, in 16 frames.
func _page() -> void:
	var g := flow
	title_shown = clock < page_frames - TEXT_LEAD and page() == 0
	if clock < page_frames - TEXT_LEAD:
		slide = OFF_SCREEN
	elif clock < page_frames - SLIDE_END:
		slide = (page_frames - (clock + SLIDE_END)) << SLIDE_STEP
	else:
		slide = 0
	clock += 1
	var replay := g.fight.replay as ArcadeReplay
	var result := g.sim.fight_frame()
	if result > ROUND_ENDED or replay.kept_running == 0:
		if page() == LAST_PAGE:
			g.sub = POSE_WAIT
			clock = 0
		elif stopped < STOPPED_FRAMES:
			g.fight.freeze = 1
			stopped += 1
		else:
			g.sub += 1


func _pose_wait() -> void:
	var g := flow
	var elapsed := g.frame() - page_start
	if elapsed < PAGE_SHORT:
		wait_vblanks = maxi((PAGE_VBLANKS - elapsed) >> 2, 0) * 2
	page_start = g.frame()
	g.sub = POSE_START
	_pose_start()


func _pose_start() -> void:
	var g := flow
	var f := g.fight.fighters[winner]
	win_pose = g.fight.move_for_slot(f, WIN_POSE_SLOT)
	(g.fight.replay as ArcadeReplay).mode = ArcadeReplay.POSE_ONLY
	f.pos_x = f.root_x
	f.pos_z = f.root_z
	g.sim.winner_frames = 0
	clock = 0
	g.sub = POSE
	_pose()


func _pose() -> void:
	var g := flow
	var f := g.fight.fighters[winner]
	g.fight.blend_hold = 2
	f.pose_move = win_pose
	f.root_move = win_pose
	f.pose_frame = clock
	if clock == win_pose.length - 1:
		clock = LOGO_CLOCK
		g.sub = LOGO_START
	g.sim.winner_frame(winner)
	credits_shown = clock > CREDITS_FROM
	clock += 1


func _logo() -> void:
	var g := flow
	clock -= 1
	var level := NEUTRAL_FADE
	if clock > LOGO_RISE:
		level = (LOGO_CLOCK - clock) * 4
	elif clock <= LOGO_HOLD:
		level = clock * 2
		if clock < 1:
			level = 0
			_leave()
	g.add_fade(level)
