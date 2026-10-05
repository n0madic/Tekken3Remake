class_name TekkenForce
extends RefCounted
## Tekken Force (force.ovl, mode 8; modes.md#tekken-force), written from the verified ports in
## tools/research/force_sim.py and the decompiled overlay: the level runner FUN_800B1778 (the level
## script, the spawn patterns, the two enemy slots, the items, the score, timer and countdown,
## the end of a level with its tally), who fights whom (FUN_800B5EC0, FUN_800B598C, the hidden
## manual switch), the side-scrolling camera (FUN_800B545C, FUN_800B5504) with the camera's
## view-space x the walls follow (FUN_800B4DF8, FUN_800B2F98, FUN_800B3020, FUN_800B309C), the
## boss of each level (FUN_800B2B3C) and the mode's hooks.
##
## State keeps the game's layout, as practice's does: force.ovl's data and bss from BASE (`v`),
## loaded from the overlay image when the mode's overlay is loaded. Fighter pointers are the
## records' fixed addresses; the level script pointer is kept as an offset into the level script.
## The screen points of the "+n SEC" and LIFE UP! texts are the presentation's: the state keeps
## the world point they are placed over.

const BASE := 0x800B69C0              ## force.ovl's data and bss from its HUD bars
const SIZE := 0x750

# ---- force.ovl (addresses)
const PATTERNS := 0x800B0A10          ## 6-byte (variant, type, 0) entries; 99 ends a pattern
const KILL_SECONDS := 0x800B0B38      ## per enemy type: u16 ?, u16 seconds added for a kill
const ENEMY_HEALTH := 0x800B0B4C      ## per level 5 types (16.16)
const ENEMY_KEYS := 0x800B0BB0        ## per level: the costume keys of variants 0 and 1
const ALLOWANCE := 0x800B0BBC         ## per level: the bonus time allowance (frames)
const STAGE_BONUS := 0x800B0BD0       ## per level
const QUADRANT_ORDER := 0x800B0F04    ## s32[4]
const BOSS_TABLE := 0x800B685C        ## per costume key: pointer to 4 × (u16 character, s16 costume or −1)
const BARS := 0x800B69CC              ## 3 × 0x10: health seen, target, fill, trail, direction, x, y
const CLOSE_A := 0x800B6A0C
const CLOSE_B := 0x800B6A10
const MANUAL := 0x800B6A14
const MANUAL_BUTTON := 0x800B6A18
const MANUAL_SIDE := 0x800B6A1C
const TARGET_WAIT := 0x800B6A20
const TALLY := 0x800B6A6C
const SCROLL_PARAM := 0x800B6A70
const SLOTS := 0x800B6A7C             ## 2 × 0x18
const PLAYER := 0x800B6AAC
const ENEMIES := 0x800B6AB4           ## the two enemy records
const THIRD := 0x800B6AB8
const SCRIPT_PTR := 0x800B6ABC
const WAIT_DEFEATED := 0x800B6AC0
const WAIT_COUNT := 0x800B6AC4
const PATTERN_ON := 0x800B6AC8
const PATTERN_STOP_X := 0x800B6ACC
const PATTERN_PTR := 0x800B6AD0
const FIGHT_START_TIMER := 0x800B6AD4
const CLEAR_TIME := 0x800B6AD8
const BONUS_TIME := 0x800B6ADC
const CLEAR_BONUS := 0x800B6AE0
const DRAWN := 0x800B6AE4
const WALLS := 0x800B6AE8             ## 3 lines (k, c): left x, right x, stage 18's lower z
const ITEMS := 0x800B6E90             ## 2 × 0xBC
const BAR_PHASE := 0x800B6DE8
const BAR_DONE := 0x800B6DEC
const CAM := 0x800B7098               ## the camera record: player, x, y, z, pitch, yaw?, h, mode, …
const CAM_X := 0x800B709C
const CAM_Y := 0x800B70A0
const CAM_Z := 0x800B70A4
const CAM_PITCH := 0x800B70A8
const CAM_YAW := 0x800B70AC
const CAM_H := 0x800B70B0
const SCROLL_MODE := 0x800B70B4
const CAM_TARGET_X := 0x800B70B8
const CAM_PITCH_TARGET := 0x800B70BC
const SCROLL_LEFT := 0x800B70C0
const SCROLL_RIGHT := 0x800B70C4
const SCROLL_MIN := 0x800B70C8
const SCROLL_MAX := 0x800B70CC
const KEYS := 0x800B70D0
const CLOCK := 0x800B70D4
const SLOT_TIMER := 0xC                ## a slot's +0xC: its state's timer (the level clock or the text-frame count)
const POPUP_TIMER := 0x14              ## a slot's +0x14: the end of its "+n SEC"
const HUMAN := 0x800B70D8
const STATE := 0x800B70DC
const TALLY_DONE := 0x800B70E0
const START_X := 0x800B70E4
const LEVEL_ENDED := 0x800B70E8
const SCORE := 0x800B70EC
const VIEW_X := 0x800B70F0
const TILE_ONLY := 0x800B70F4
const TILE_ONLY_LIGHT_STAGE := 12
const FINAL_CHALLENGE := 0x800B70F8
const KEY_EARNED := 0x800B70FC
const HISCORE := 0x800B7100
const LEVEL := 0x800B7104

# ---- the mode context (0x800AFF50 + x)
const RESULT_FLAGS := 0x40            ## 0x800AFF90: keys earned, Doctor B. saved, boss list
const BOSSES := 0x41                  ## 0x800AFF91 + level: the bosses met (character · 4 + costume)
const DEFEATED := 0x3C                ## 0x800AFF8C: enemies defeated (u16)
const NEW_RECORD := 0x3F              ## 0x800AFF8F
const FINAL_SCORE := 0x38             ## 0x800AFF88: the score at the result
const FEATURE_PAUSE := 4              ## 0x800AFF54 (mode context): pausing allowed

const ENEMY := 0x15                   ## the enemies' character
const ENEMY_KEY_OFFSET := 0x54        ## costume key of an enemy: 0x54 + the level's key
const FORCE_AI_LEVELS: Array[int] = [0, 3, 4, 5, 5]
const SCORE_CAP := 99_999_990
const TIMER_CAP := 0x1734
const COUNTDOWN_SOUNDS := 0x8009747E  ## the announcer's 1..5
const SOUND_ITEM := 0x4E6A
const SOUND_ITEM_END := 0x87C0
const SOUND_TALLY := 0x4C6C
const SOUND_TALLY_KEY := 0x4CEB
const ITEM_REACH := 0x1F5
const ITEM_HEALTH := 0x320000
const ITEM_BEHIND := 5000
const ITEM_Y := 0x420
const SPAWN_EDGE := 5000
const BOSS_AHEAD := 0x1000
const SLOT_FREE := 1
const TARGET_WAIT_FRAMES := 0x78
const CLOSE_LIMIT := 399
const NEAR := 0x9C4
const NEAR_GAP := 0x190
const LEVEL_4 := 3
const DOCTOR_LEVEL := 4
const CAMERA_ROLL_LEVEL_4 := 0x82
const STAGE_18 := 0x12

## A "+n SEC" or LIFE UP! text over a world point (the presentation projects the point).
class ForcePopup:
	var point := PackedInt32Array([0, 0, 0])
	var view: ViewMatrix
	var until := 0                     ## the level clock at which it ends

var fight: FightState:                 ## held weakly: FightState owns this object
	get: return _fight.get_ref() as FightState
var _fight: WeakRef
var t: FightTables
var ram: GameRam                       ## force.ovl's tables
var v := ByteBlock.new(SIZE)
var script_bytes := PackedByteArray()  ## the level script (stage ARC member 3, 20-byte records)
var slot_popups: Array[ForcePopup] = [ForcePopup.new(), ForcePopup.new()]
## Bug #41 fixed (RuleSet.fix_force_slot_timers): per slot the +0xC and +0x14 timers as 32-bit
## values; the slot record keeps the game's 16-bit copies.
var _slot_timers := PackedInt32Array([0, 0, 0, 0])
var item_popups: Array[ForcePopup] = [ForcePopup.new(), ForcePopup.new()]


func _init(fight_state: FightState, overlay: GameRam) -> void:
	_fight = weakref(fight_state)
	t = fight_state.tables
	ram = overlay
	v.bytes = overlay.bytes(BASE, SIZE)


# ==== byte access by game address =================================================================

func g32(a: int) -> int:
	return v.s32(a - BASE)


func gu32(a: int) -> int:
	return v.u32(a - BASE)


func g16(a: int) -> int:
	return v.s16(a - BASE)


func gu16(a: int) -> int:
	return v.u16(a - BASE)


func put32(a: int, x: int) -> void:
	v.put32(a - BASE, x)


func put16(a: int, x: int) -> void:
	v.put16(a - BASE, x)


func level() -> int:
	return g32(LEVEL)


func score() -> int:
	return gu32(SCORE)


## 0x800B70D8: the pad the player uses (the human's side; the player's record is always the first).
func human() -> int:
	return gu32(HUMAN)


## 0x800B70E8: the level's enemies are over (the boss fight, or the level won).
func level_ended() -> bool:
	return gu32(LEVEL_ENDED) != 0


## HitApply's mode-8 scoring: ten points per damage the player (or a forced hit) did to an enemy.
func add_score(points: int) -> void:
	put32(SCORE, Fx.w32(g32(SCORE) + points * 10))


## FUN_800B2E60: the player's record.
func player() -> FighterState:
	return fight.fighters[FighterState.index_at(gu32(PLAYER))]


## FUN_800B2E90: enemy slot `i` (0x18 bytes at SLOTS).
static func slot(i: int) -> int:
	return SLOTS + 0x18 * (i & 1)


func slot_fighter(i: int) -> FighterState:
	return fight.fighters[FighterState.index_at(gu32(slot(i)))]


func slot_state(i: int) -> int:
	return g16(slot(i) + 8)


## FUN_800B2EEC: enemy slot `i` is free while the level runs (PairwiseDistances then counts the
## CPU record `i + 1` as off screen).
func slot_free(i: int) -> bool:
	return slot_state(i) == 1 and g32(LEVEL_ENDED) == 0


# ==== the mode's start and each level's set-up ===================================================

## FUN_800B1508 (the mode's start, FUN_800B60A4): the keys from the save, the score and the
## saved hi-score.
func mode_start() -> void:
	put32(KEYS, fight.progress.force_keys)
	put32(SCORE, 0)
	put32(HISCORE, fight.progress.force_hi_score)


## FUN_800B2E10: the player (fighter 0, or 1 when the other side started) and the enemy records.
func assign_records() -> void:
	var p := 1 if fight.fighters[0].is_cpu != 0 else 0
	put32(PLAYER, FighterState.address(p))
	put32(ENEMIES, FighterState.address(1 - p))
	put32(THIRD, FighterState.address(2))


## FUN_800B15EC (the level's set-up at each round start): the slots empty, the script from the
## start, the camera and walls, the progress bar; the Doctor B. level has no script and starts
## with its boss (state 8) and 60 seconds.
func level_setup(level_script: PackedByteArray) -> void:
	assign_records()
	for i in 2:
		var s := slot(i)
		put16(s + 8, 0)
		put16(s + 0xA, 0)
		_set_timer(i, SLOT_TIMER, 0)
		put32(s, gu32(ENEMIES + 4 * i))
		put16(s + 0xE, 0)
		put16(s + 0x10, i)
		var f := slot_fighter(i)
		f.active = 0
		f.health = 0
		f.invulnerable = 1
	put32(CLOCK, 0)
	put32(STATE, 0)
	put32(SCROLL_PARAM, 0)
	scroll_mode(0)
	put32(LEVEL_ENDED, 0)
	put32(LEVEL, fight.region.fight_index)
	script_bytes = level_script
	put32(SCRIPT_PTR, 0)
	for a: int in [KEY_EARNED, FINAL_CHALLENGE, TALLY_DONE, WAIT_DEFEATED, WAIT_COUNT, PATTERN_ON,
			PATTERN_STOP_X, PATTERN_PTR, FIGHT_START_TIMER, CLEAR_TIME, BONUS_TIME, DRAWN]:
		put32(a, 0)
	_progress_setup()
	_items_setup()
	_walls_setup()
	var doctor := tile_only_level(fight.region.fight_index)
	if doctor:
		put32(STATE, 8)
		fight.timer = 0xE10
	put32(TILE_ONLY, 1 if doctor else 0)


## Whether the level of `fight_index` is the Doctor B. level: no script, its boss from the start,
## only the ground tile of the panorama (TILE_ONLY), and in the resident code (FUN_80039BB4,
## FUN_8003A030, mode 8 with TILE_ONLY) stage TILE_ONLY_LIGHT_STAGE's light record for the stage's
## lights and the fighters' base colour.
static func tile_only_level(fight_index: int) -> bool:
	return fight_index > LEVEL_4


## FUN_800B396C's state: the bar's phase and done flag.
func _progress_setup() -> void:
	put32(BAR_PHASE, 0)
	put32(BAR_DONE, 0)


## FUN_800B4198's state: both items free, at y 0x420 (the point the picture is drawn above).
func _items_setup() -> void:
	for i in 2:
		var it := ITEMS + 0xBC * i
		for off: int in [0, 4, 0xC, 0x18]:
			put32(it + off, 0)
		put32(it + 8, ITEM_Y)


const WALL_LINES: Array[int] = [-0x143, -0x9F9, 0x149, 0x7B3]
const WALL_LINES_18: Array[int] = [-0x177, -0x98D, 0x14D, 0x87F]

## FUN_800B2F98: the wall lines by stage.
func _walls_setup() -> void:
	var lines: Array[int] = WALL_LINES_18 if fight.stage == STAGE_18 else WALL_LINES
	for k in 4:
		put32(WALLS + 4 * k, lines[k])
	put32(WALLS + 0x10, -0x103)
	put32(WALLS + 0x14, -0x8ED)


## FUN_800B53E0: 0 free scrolling, 1 locked, 2 locked within 5,000 units either side.
func scroll_mode(mode: int) -> void:
	if mode == 0:
		put32(SCROLL_RIGHT, 1)
	elif mode == 2:
		put32(SCROLL_LEFT, -100)
		put32(SCROLL_RIGHT, 60)
		put32(SCROLL_MIN, g32(CAM_X) - SPAWN_EDGE)
		put32(SCROLL_MAX, g32(CAM_X) + SPAWN_EDGE)
	put32(SCROLL_MODE, mode)


# ==== who fights whom (FUN_800B5EC0, FUN_800B598C) =================================================

## FUN_800B5910 at the mode's fight hook: holding all four face buttons turns the hidden manual
## target switch on (L1 if held, else L2, R1 or R2; L2 without a shoulder button).
func manual_target_setup(held: int) -> void:
	if held & PadState.FACE_BUTTONS != PadState.FACE_BUTTONS:
		return
	var button := 4 if held & 4 else 1 if held & 1 else 8 if held & 8 else 2 if held & 2 else 1
	put32(MANUAL_BUTTON, button)
	put32(MANUAL, 1)


## FUN_800B58FC.
func manual_target_off() -> void:
	put32(MANUAL_BUTTON, 0)
	put32(MANUAL, 0)


## FUN_800B5EC0: the player, the enemy it faces and the other one (and every fighter's opponent).
func roles(moves: MoveSystem, pads: FighterInput.PadWords) -> Array[FighterState]:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var f2 := fight.fighters[2]
	var p := f0 if f0.is_cpu == 0 else f1
	var a := f1 if p == f0 else f0
	var b := f2
	if p.index == 0:
		if p.opp_index == 1:
			a = f1
			b = f2
		else:
			a = f2
			b = f1
	else:
		if p.opp_index == 0:
			a = f0
			b = f1
		else:
			a = f1
			b = f0
	put32(CLOSE_A, 1 if ((a.screen_x & 0xFFFF) - 1) & 0xFFFFFFFF < CLOSE_LIMIT else 0)
	put32(CLOSE_B, 1 if ((b.screen_x & 0xFFFF) - 1) & 0xFFFFFFFF < CLOSE_LIMIT else 0)
	var target := _choose_target(moves, pads, p, a, b)
	var other := b if a == target else a
	p.fixed_facing = 0 if a.invulnerable == 0 or b.invulnerable == 0 else 1
	p.fixed_facing_side = 0
	p.opp_index = target.index
	target.opp_index = p.index
	other.opp_index = p.index
	for f: FighterState in [p, target, other]:
		f.cur_opp_index = fight.opponent_index(f)
	return [p, target, other]


## FUN_800B598C: which enemy the player faces. A hidden enemy (+0xC2) is skipped; while only
## one is close it is taken; with both close the nearer one wins by 400 units, else the one more
## in front of the player; a change waits 120 frames. The manual switch swaps the two. (Bug #47,
## not reproduced: the player's angle fields are restored from a full copy.)
func _choose_target(moves: MoveSystem, pads: FighterInput.PadWords, p: FighterState, a: FighterState,
		b: FighterState) -> FighterState:
	var wait := g32(TARGET_WAIT)
	if wait > 0:
		put32(TARGET_WAIT, wait - 1)
	if g32(TARGET_WAIT) < 0:
		put32(TARGET_WAIT, 0)
	var pick := a
	if a.invulnerable != 0:
		if b.invulnerable == 0:
			pick = b
	elif b.invulnerable != 0:
		pass
	elif gu32(CLOSE_A) == 0:
		if gu32(CLOSE_B) != 0:
			pick = b
	elif gu32(CLOSE_B) == 0 or gu32(TARGET_WAIT) != 0:
		pass
	else:
		var da := fight.pair_distance[Combat._pair(p.index, a.index)]
		var db := fight.pair_distance[Combat._pair(p.index, b.index)]
		var diff := Fx.w32(da - db)
		if da < NEAR or db < NEAR:
			if absi(diff) >= NEAR_GAP:
				pick = b if diff > 0 else a
			else:
				var saved := _angles(p)
				moves.relative_angles(p, a)
				var qa := Fx.s16(p.facing_quadrant)
				var ra := Fx.s16(p.rel_angle)
				moves.relative_angles(p, b)
				var qb := Fx.s16(p.facing_quadrant)
				var rb := Fx.s16(p.rel_angle)
				if qa == qb:
					var threshold := 0x1000 if qa == 0 else 0x2000 if qa == 2 else 0x3000
					if absi(ra - rb) >= threshold:
						pick = a if ra < rb else b
				else:
					pick = a if ram.s32(QUADRANT_ORDER + 4 * qb) < ram.s32(QUADRANT_ORDER + 4 * qa) else b
				_restore_angles(p, saved)
		if gu32(MANUAL) != 0:
			var side := gu32(MANUAL_SIDE)
			# The side of the human: the first player's CPU flag (0x800A95F0), i.e. HUMAN.
			var pressed := pads.physical_pressed[human()]
			if pressed & gu32(MANUAL_BUTTON) != 0:
				side = (side + 1) & 1
				put32(MANUAL_SIDE, side)
			pick = b if gu32(MANUAL_SIDE) != 0 else a
		if pick.index != a.index:
			put32(TARGET_WAIT, TARGET_WAIT_FRAMES)
	if gu32(MANUAL) != 0:
		put32(MANUAL_SIDE, 1 if pick != a else 0)
	return pick


## The player's twelve angle fields (+0x2A … +0x42) FUN_800B598C saves around its tests.
static func _angles(f: FighterState) -> PackedInt32Array:
	return PackedInt32Array([f.target_dir, f.heading, f.heading_delta, f.rel_angle, f.facing_quadrant,
		f.aim_dir, f.opp_to_self_dir, f.opp_heading, f.opp_heading_delta, f.opp_rel_angle,
		f.opp_quadrant, f.opp_aim_dir])


static func _restore_angles(f: FighterState, a: PackedInt32Array) -> void:
	f.target_dir = a[0]
	f.heading = a[1]
	f.heading_delta = a[2]
	f.rel_angle = a[3]
	f.facing_quadrant = a[4]
	f.aim_dir = a[5]
	f.opp_to_self_dir = a[6]
	f.opp_heading = a[7]
	f.opp_heading_delta = a[8]
	f.opp_rel_angle = a[9]
	f.opp_quadrant = a[10]
	f.opp_aim_dir = a[11]


# ==== the camera (FUN_800B545C, FUN_800B5504) and the walls =======================================

## FUN_800B545C: the side-scrolling camera starts on the player (level 4 rolls it slightly).
func camera_setup(view: CameraView) -> void:
	view.roll = CAMERA_ROLL_LEVEL_4 if fight.region.fight_index == LEVEL_4 else 0
	put32(SCROLL_RIGHT, 1)
	put32(CAM_Y, -0xDAC)
	put32(CAM_Z, -0x1B58)
	put32(SCROLL_MODE, 0)
	put32(CAM_X, 0)
	put32(CAM_PITCH, 0x2AAA)
	put32(CAM_YAW, 0)
	put32(CAM_H, 500)
	put32(CAM_PITCH_TARGET, 0x2AAA)
	put32(CAM_TARGET_X, 0)
	put32(CAM, gu32(PLAYER))
	put32(START_X, g32(CAM_X))


## FUN_800B5504: the camera scrolls with the player's projected screen x (in scroll mode 0 past
## the centre, in mode 2 within its bounds), and pitches back when the player nears the bottom
## of the screen. Returns the source record (x, y, z, pitch, yaw, h) for CameraUseSource(0).
func camera_frame(view: CameraView) -> PackedInt32Array:
	var pitch_q := Fx.div_trunc(-g32(CAM_PITCH) + (0x3F if -g32(CAM_PITCH) < 0 else 0), 1) >> 5 & 0x1FFE
	var p := fight.fighters[FighterState.index_at(gu32(CAM))]
	var dx := p.root_x - g32(CAM_X)
	var roll := -view.roll & 0xFFF
	var cr := FightMath.cos12(roll, t)
	var sr := FightMath.sin12(roll, t)
	var cam_y := g32(CAM_Y)
	var u := cr * dx - sr * -cam_y
	u = u + 0xFFF if u < 0 else u
	var cp := t.sin_table[(pitch_q >> 1) + 1024]
	var sp := t.sin_table[pitch_q >> 1]
	var dz := p.root_z - g32(CAM_Z)
	var w := sr * dx + cr * -cam_y
	w = w + 0xFFF if w < 0 else w
	var depth := cp * dz - sp * (w >> 12)
	depth = depth + 0xFFF if depth < 0 else depth
	var up := sp * dz + cp * (w >> 12)
	up = up + 0xFFF if up < 0 else up
	var bottom := Fx.div_trunc(Fx.div_trunc((up >> 12) * 0x9C4, depth >> 12), 3)
	var screen := Fx.div_trunc((u >> 12) * 500, depth >> 12)
	put32(CAM_TARGET_X, g32(CAM_X))
	var mode := g32(SCROLL_MODE)
	if mode == 0 or mode == 2:
		if mode == 2 and screen < g32(SCROLL_LEFT):
			put32(CAM_TARGET_X, g32(CAM_X) + (g32(SCROLL_LEFT) - screen) * -5)
		if g32(SCROLL_RIGHT) < screen:
			put32(CAM_TARGET_X, g32(CAM_X) + (screen - g32(SCROLL_RIGHT)) * 5)
	if (screen > 0 and g32(CAM_X) < g32(CAM_TARGET_X)) or (screen < 0 and g32(CAM_TARGET_X) < g32(CAM_X)):
		put32(CAM_X, g32(CAM_TARGET_X))
	if mode == 2:
		if g32(CAM_X) < g32(SCROLL_MIN):
			put32(CAM_X, g32(SCROLL_MIN))
		if g32(SCROLL_MAX) < g32(CAM_X):
			put32(CAM_X, g32(SCROLL_MAX))
	if bottom >= 0xD5:
		put32(CAM_PITCH_TARGET, g32(CAM_PITCH) + 0x2D8)
	elif bottom < 0xBC:
		put32(CAM_PITCH_TARGET, g32(CAM_PITCH) - 0x2D8)
	var pitch := g32(CAM_PITCH)
	if pitch != g32(CAM_PITCH_TARGET):
		var d := pitch - g32(CAM_PITCH_TARGET)
		put32(CAM_PITCH, pitch - ((d + 7 if d < 0 else d) >> 3))
	put32(CAM_PITCH, clampi(g32(CAM_PITCH), 0x2AAA, 0x10000))
	return PackedInt32Array([g32(CAM_X), g32(CAM_Y), g32(CAM_Z), g32(CAM_PITCH), g32(CAM_YAW), g32(CAM_H)])


## FUN_800B4DF8's first part: the camera's view-space x (the walls follow it).
func background(view: ViewMatrix, camera: CameraView) -> void:
	var p := Gte.apply_lv(view.rot, PackedInt32Array([camera.x, camera.y, camera.z]))
	put32(VIEW_X, p[0])


## A wall line (FUN_800B3020 / FUN_800B309C): v · k / 1000 + c.
func _line(at: int, x: int) -> int:
	return Fx.w32(Fx.div_trunc(Fx.w32(x * g32(at)), 1000) + g32(at + 4))


## ArenaBounds in Tekken Force: z within [−0x898, 0x8FC] (on stage 18 the lower limit is a line
## of x), the player's x between two lines of z relative to the camera's view x, an enemy within
## 0x1068 of it. Returns Vector2i(dz, dx).
func walls(f: FighterState) -> Vector2i:
	var dz := 0
	var dx := 0
	var z := f.root_z
	if Fx.w32(z - 0x8FC) > 0:
		dz = Fx.w32(-(z - 0x8FC))
	var low := Fx.w32(z + 0x898)
	if fight.stage == STAGE_18:
		low = Fx.w32(f.root_z - _line(WALLS + 0x10, Fx.w32(f.root_x - g32(VIEW_X))))
	if low < 0:
		dz = Fx.w32(-low)
	var view := g32(VIEW_X)
	var high := 0
	if f.is_cpu == 0:
		var rel := Fx.w32(f.root_x - view)
		var lo := _line(WALLS, f.root_z)
		var hi := _line(WALLS + 8, f.root_z)
		if Fx.w32(rel - lo) < 0:
			dx = Fx.w32(-(rel - lo))
		high = Fx.w32(rel - hi)
	else:
		var left := Fx.w32(Fx.w32(f.root_x + 0x1068) - view)
		if left < 0:
			dx = Fx.w32(-left)
		high = Fx.w32(Fx.w32(f.root_x - 0x1068) - view)
	if high > 0:
		dx = Fx.w32(-high)
	return Vector2i(dz, dx)


# ==== the level runner (FUN_800B1778) =============================================================

## One frame of the level: the script, the enemy slots, the progress bar's phase, the items, the
## score and timer caps and the announcer's countdown. Returns true on the frame NOW LOADING ends
## (FightFrame then changes the area: round state 7).
func level_frame(sim: FightSimulation, events: SimEvents) -> bool:
	var p := player()
	var area_change := _script_frame(sim, events)
	for i in 2:
		_enemy_slot(sim, i, p, events)
	if fight.paused_player == 0:
		put32(BAR_PHASE, gu32(BAR_PHASE) + 0x40)
	if gu32(BAR_DONE) == 0 and gu32(LEVEL_ENDED) != 0:
		put32(BAR_DONE, 1)
	_items(sim, p, events)
	if SCORE_CAP < gu32(SCORE):
		put32(SCORE, SCORE_CAP)
	if gu32(HISCORE) < gu32(SCORE):
		fight.region.ctx_put8(NEW_RECORD, 1)
		put32(HISCORE, gu32(SCORE))
	if fight.timer >= TIMER_CAP + 1:
		fight.timer = TIMER_CAP
	if fight.paused_player == 0 and fight.round_state == RoundState.FIGHT:
		var left := fight.timer
		if left in [60, 120, 180, 240, 300]:
			_sound(ram.u16(COUNTDOWN_SOUNDS + 2 * (left / 60 - 1)), events)
	return area_change


func _sound(code: int, events: SimEvents) -> void:
	events.add(SimEvents.Kind.SOUND, 0, code, 0)


## The level script's part (FUN_800B1778 up to its enemy slots).
func _script_frame(sim: FightSimulation, events: SimEvents) -> bool:
	var area_change := false
	var progress := Fx.w32(g32(CAM_X) - g32(START_X))
	if fight.paused_player == 0:
		put32(CLOCK, gu32(CLOCK) + 1)
	put32(DRAWN, gu32(DRAWN) + 1)
	var clock := g32(CLOCK)
	var frozen := fight.paused_player != 0
	match gu32(STATE):
		0:
			_commands(progress, events)
		1:
			var w := g32(WAIT_COUNT)
			if w < 0:
				if slot_state(0) == SLOT_FREE and slot_state(1) == SLOT_FREE:
					put32(STATE, 0)
			elif not g32(WAIT_DEFEATED) < w:
				put32(STATE, 0)
		3:
			if g32(TALLY) < clock and not frozen:
				put32(TALLY, clock + 2)
				put32(STATE, 4)
		4:
			if g32(TALLY) < clock and not frozen:
				area_change = true
				put32(STATE, 5)
		5:
			put32(LEVEL_ENDED, 1)
			fight.region.ctx_put8(FEATURE_PAUSE, 1)
			put32(STATE, 6)
			put32(FIGHT_START_TIMER, fight.timer)
		6:
			_bonus_frame()
		7:
			_tally(events)
		8:
			_boss(sim, events)
		9:
			var d := g32(FIGHT_START_TIMER) - fight.timer
			put32(CLEAR_TIME, maxi(d, 0))
			if fight.round_state == RoundState.STAGE_CLEAR:
				put32(TALLY, 0)
				put32(STATE, 10)
				fight.region.ctx_put8(RESULT_FLAGS, fight.region.ctx8(RESULT_FLAGS) | 8)
		10:
			var n := g32(TALLY)
			put32(TALLY, n + 1)
			if n >= 0xB5:
				put32(TALLY_DONE, 1)
	_patterns(progress)
	return area_change


## A script record (20 bytes): s32 trigger, s16 command, dx, _, z, _, param, u16 arg.
func _rec32(at: int) -> int:
	return script_bytes.decode_s32(at) if at + 4 <= script_bytes.size() else 0x7FFFFFFF


func _rec16(at: int) -> int:
	return script_bytes.decode_s16(at) if at + 2 <= script_bytes.size() else 0


func _recu16(at: int) -> int:
	return script_bytes.decode_u16(at) if at + 2 <= script_bytes.size() else 0


## State 0: every record whose trigger the camera has passed runs.
func _commands(progress: int, events: SimEvents) -> void:
	if fight.round_state != RoundState.FIGHT or progress < _rec32(gu32(SCRIPT_PTR)):
		return
	while true:
		var rec := gu32(SCRIPT_PTR)
		var cmd := _rec16(rec + 4)
		var cam := g32(CAM_X)
		var stop := false
		match cmd:
			0:
				put32(SCROLL_PARAM, _rec16(rec + 0xE))
				scroll_mode(_rec16(rec + 0xE))
			1:
				var s := free_slot()
				if s >= 0:
					_spawn(s, _recu16(rec + 0xE), _recu16(rec + 0x10), cam + _rec16(rec + 6), _rec16(rec + 0xA))
			2:
				put32(PATTERN_ON, gu32(PATTERN_ON) + 1)
				put32(PATTERN_STOP_X, _recu16(rec + 0x10))
				if _recu16(rec + 0xE) < 0x31:
					put32(PATTERN_PTR, PATTERNS + 6 * _rec16(rec + 0xE))
			3:
				stop = true
				put32(WAIT_DEFEATED, 0)
				put32(STATE, 1)
				put32(WAIT_COUNT, _rec16(rec + 0xE))
			4:
				_place_item(cam + _rec16(rec + 6), _rec16(rec + 0xA))
			6:
				for i in 2:
					_release(i)
				events.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0, 30)
				stop = true
				fight.region.ctx_put8(FEATURE_PAUSE, 0)
				put32(PATTERN_ON, 0)
				put32(STATE, 3)
				put32(TALLY, gu32(CLOCK) + 0x3C)
		put32(SCRIPT_PTR, rec + 0x14)
		if stop or progress < _rec32(rec + 0x14):
			break


## FUN_800B2EB0: the first free enemy slot, −1 for none.
func free_slot() -> int:
	for i in 2:
		if slot_state(i) == SLOT_FREE:
			return i
	return -1


## FUN_800B2F30.
func _release(i: int) -> void:
	var f := slot_fighter(i)
	f.health = 0
	f.active = 0
	f.invulnerable = 1
	put16(slot(i) + 8, 1)


## A new enemy in slot `i`: state 4 (enter) when its model is loaded, else 2 (load it first).
func _spawn(i: int, variant: int, kind: int, x: int, z: int) -> void:
	var s := slot(i)
	if g16(s + 0x10) == Fx.s16(variant):
		put16(s + 8, 4)
	else:
		put16(s + 8, 2)
		put16(s + 0x12, variant)
	put16(s + 0xE, Fx.div_trunc(Fx.s16(kind), 5) * -5 + Fx.s16(kind))
	place(slot_fighter(i), x, z)


## FUN_800B2F50: anchor and root at (x, z).
static func place(f: FighterState, x: int, z: int) -> void:
	f.root_x = x
	f.pos_x = x
	f.root_z = z
	f.pos_z = z


## FUN_800B4328: the first free item slot gets the item.
func _place_item(x: int, z: int) -> void:
	for i in 2:
		var it := ITEMS + 0xBC * i
		if gu32(it) == 0:
			put32(it + 4, x)
			put32(it + 0xC, z)
			put32(it, 1)
			return


## The spawn pattern (command 2): a new enemy enters from the right whenever a slot is free, until
## the pattern's 99 or the camera passing its stop x.
func _patterns(progress: int) -> void:
	if gu32(PATTERN_ON) != 1:
		return
	if not progress < g32(PATTERN_STOP_X):
		put32(PATTERN_ON, 0)
		return
	var at := gu32(PATTERN_PTR)
	if ram.u16(at) == 0x63:
		return
	var s := free_slot()
	if s < 0:
		return
	_spawn(s, ram.u16(at), ram.u16(at + 2), g32(CAM_X) + SPAWN_EDGE, 0)
	put32(PATTERN_PTR, at + 6)


## State 6: the clear and bonus time, and on the stage clear (round state 8) the clear bonus and
## the key rule.
func _bonus_frame() -> void:
	var p := player()
	var clear := g32(FIGHT_START_TIMER) - fight.timer
	var bonus := ram.s32(ALLOWANCE + 4 * level()) - clear
	put32(CLEAR_TIME, clear if clear >= 0 else 0)
	put32(BONUS_TIME, bonus if bonus >= 0 else 0)
	if fight.round_state != RoundState.STAGE_CLEAR:
		return
	var health := p.health
	put32(CLEAR_BONUS, ((health + 0xFFFF if health < 0 else health) >> 16) * 100)
	if level() == LEVEL_4:
		var doctor := (fight.progress.unlocked >> 19) & 1
		var keys := g32(KEYS)
		if keys < 3 and doctor == 0:
			put32(KEY_EARNED, 1)
			fight.progress.force_keys = mini(fight.progress.force_keys + 1, 0xFF)
			fight.save_request = true
			var flag := {0: 1, 1: 3, 2: 7}.get(keys, 0) as int
			if flag != 0:
				fight.region.ctx_put8(RESULT_FLAGS, fight.region.ctx8(RESULT_FLAGS) | flag)
		elif keys == 3 and doctor == 0:
			put32(FINAL_CHALLENGE, 1)
	put32(TALLY, 0)
	put32(STATE, 7)


## State 7: STAGE BONUS, CLEAR BONUS, CLEAR TIME, then BONUS TIME (or the key or final stage
## message) 30 frames apart, each with its sound; the bonuses go to the score as they appear.
func _tally(events: SimEvents) -> void:
	var n := g32(TALLY) + 1
	put32(TALLY, n)
	if n == 0x1E:
		put32(SCORE, gu32(SCORE) + ram.u32(STAGE_BONUS + 4 * level()))
		_sound(SOUND_TALLY, events)
	if n == 0x3C:
		put32(SCORE, gu32(SCORE) + gu32(CLEAR_BONUS))
		_sound(SOUND_TALLY, events)
	if n == 0x5A:
		_sound(SOUND_TALLY, events)
	if n < 0x78:
		return
	put32(TALLY_DONE, 1)
	var b := g32(BONUS_TIME)
	if level() < LEVEL_4 and b != 0:
		if n == 0x78:
			fight.timer = Fx.w32(fight.timer + b)
			_sound(SOUND_TALLY, events)
	elif gu32(KEY_EARNED) != 0:
		if n == 0x78:
			put32(KEYS, gu32(KEYS) + 1)
			_sound(SOUND_TALLY_KEY, events)
	elif gu32(FINAL_CHALLENGE) != 0 and n == 0x78:
		_sound(SOUND_TALLY_KEY, events)


## The tally's lines for the presentation: (frames shown, stage bonus, clear bonus, clear time,
## bonus time) and which last line shows (0 bonus time, 1 the key, 2 the final stage, −1 none).
func tally_lines() -> PackedInt32Array:
	var last := -1
	if level() < LEVEL_4 and g32(BONUS_TIME) != 0:
		last = 0
	elif gu32(KEY_EARNED) != 0:
		last = 1
	elif gu32(FINAL_CHALLENGE) != 0:
		last = 2
	return PackedInt32Array([g32(TALLY), ram.u32(STAGE_BONUS + 4 * level()), gu32(CLEAR_BONUS),
		g32(CLEAR_TIME), g32(BONUS_TIME), last])


## State 8 (the Doctor B. level's fight): slot 0 becomes a type-4 enemy with the level's boss
## health, its entrance starts, the camera locks (scroll mode 2) and state 9 times the fight.
func _boss(sim: FightSimulation, events: SimEvents) -> void:
	var s := slot(0)
	var f := slot_fighter(0)
	put16(s + 0xE, 4)
	put16(s + 8, 1)
	put16(s + 0xA, 0)
	sim.start_move(f, 3)
	f.active = 1
	var hp := ram.s32(ENEMY_HEALTH + 20 * level() + 4 * g16(s + 0xE))
	f.invulnerable = 0
	f.pos_y = 0
	f.ballistic = 0
	f.air_phase = 0
	f.health_max = hp
	f.health = hp
	events.add(SimEvents.Kind.FORCE_NAMES, -1, 1, Character.DOCTOR_B)
	put32(SCROLL_PARAM, 2)
	scroll_mode(2)
	put32(LEVEL_ENDED, 1)
	put32(STATE, 9)
	put32(FIGHT_START_TIMER, fight.timer)


## One enemy slot: 0 release, 1 free, 2–3 load the costume's model, 4 enter with full health,
## 5 fight, 6 defeated (+n SEC), 7 blink out.
func _enemy_slot(sim: FightSimulation, i: int, p: FighterState, events: SimEvents) -> void:
	var s := slot(i)
	var f := slot_fighter(i)
	var clock := g32(CLOCK)
	match slot_state(i):
		0:
			f.active = 0
			f.health = 0
			f.invulnerable = 1
			put16(s + 8, 1)
		2:
			f.active = 0
			put16(s + 8, 3)
			_set_timer(i, SLOT_TIMER, g32(DRAWN) + 2)
		3:
			if _timer(i, SLOT_TIMER) < g32(DRAWN):
				var variant := gu16(s + 0x12)
				put16(s + 0x10, variant)
				var key := enemy_key(level(), Fx.s16(variant))
				f.costume_key = key + ENEMY_KEY_OFFSET
				sim.reload_enemy(f)
				events.add(SimEvents.Kind.FORCE_NAMES, -1, f.index, ENEMY)
				put16(s + 8, 4)
		4:
			f.active = 1
			var hp := ram.s32(ENEMY_HEALTH + 20 * level() + 4 * g16(s + 0xE))
			f.invulnerable = 0
			f.health_max = hp
			f.health = hp
			put16(s + 8, 5)
			sim.start_move(f, 3)
			f.pos_y = 0
			f.ballistic = 0
			f.air_phase = 0
		5:
			if f.health > 0:
				return
			put16(s + 8, 6)
			_set_timer(i, SLOT_TIMER, clock + 0x3C)
			if f.last_attacker != p.index and f.forced_hit_in == 0:
				return
			var tm := fight.timer
			var sec := ram.u16(KILL_SECONDS + 4 * g16(s + 0xE) + 2)
			fight.timer = Fx.w32(tm + 59 - (tm - Fx.div_trunc(tm, 60) * 60) + sec * 60)
			var head := f.body.joints[2].t
			slot_popups[i].point = PackedInt32Array([head[0], head[1] - 300, head[2]])
			slot_popups[i].view = sim.view
			_set_timer(i, POPUP_TIMER, clock + 0x3C)
			slot_popups[i].until = _timer(i, POPUP_TIMER)
			fight.region.ctx_put16(DEFEATED, fight.region.ctx16(DEFEATED) + 1)
		6:
			if _timer(i, SLOT_TIMER) < clock and f.in_throw == 0:
				put16(s + 8, 7)
				_set_timer(i, SLOT_TIMER, clock + 0x28)
				f.invulnerable = 1
			elif f.got_hit != 0 and f.last_attacker == p.index:
				_set_timer(i, SLOT_TIMER, clock + 0x3C)
		7:
			f.active = gu32(CLOCK) & 1
			if _timer(i, SLOT_TIMER) < clock:
				put32(WAIT_DEFEATED, gu32(WAIT_DEFEATED) + 1)
				f.active = 0
				put16(s + 8, 1)


## The boss of the level for the player's costume key (FUN_800B2B3C's table): (character,
## costume); a costume of −1 is the player's other costume when the boss is the player's own
## character, else costume 0.
func boss_of(key: int) -> Vector2i:
	var entry := ram.u32(BOSS_TABLE + 4 * key) + 4 * (level() & 3)
	var character := ram.u16(entry)
	var costume := ram.s16(entry + 2)
	if costume == -1:
		if key >> 2 == character:
			costume = 1 if key & 3 == 0 else 0
		else:
			costume = 1 if key & 3 != 0 else 0
	return Vector2i(character, costume)


## FUN_800B2F64: the costume key of an enemy variant on a level.
func enemy_key(lv: int, variant: int) -> int:
	return ram.u8(ENEMY_KEYS + 2 * (lv & 3) + (variant & 1))


## Whether a slot's "+n SEC" shows (the presentation draws it rising over its point).
func slot_popup_shown(i: int) -> bool:
	return slot_state(i) == 6 and g32(CLOCK) < _timer(i, POPUP_TIMER)


## A slot's timer (SLOT_TIMER, POPUP_TIMER): the game's 16-bit copy, sign-extended and compared with
## the 32-bit clocks (bug #41), or the whole value with the fix.
func _timer(i: int, field: int) -> int:
	if fight.rules.fix_force_slot_timers:
		return _slot_timers[2 * i + int(field == POPUP_TIMER)]
	return g16(slot(i) + field)


func _set_timer(i: int, field: int, value: int) -> void:
	put16(slot(i) + field, value)
	_slot_timers[2 * i + int(field == POPUP_TIMER)] = value


## FUN_800B4374: the two items. A placed item is removed 5,000 units behind the camera; the player
## picks it up within 500 units in x and z (health +50, sound 0x4E6A), which starts LIFE UP! for
## 60 frames (sound 0x87C0 15 frames before its end).
func _items(sim: FightSimulation, p: FighterState, events: SimEvents) -> void:
	for i in 2:
		var it := ITEMS + 0xBC * i
		match gu32(it):
			1:
				if g32(it + 4) < Fx.w32(g32(CAM_X) - ITEM_BEHIND):
					put32(it, 0)
					continue
				var dx := absi(Fx.w32(p.root_x - g32(it + 4)))
				var dz := absi(Fx.w32(p.root_z - g32(it + 0xC)))
				if dx < ITEM_REACH and dz < ITEM_REACH and p.health > 0 and p.in_air == 0:
					p.health = Fx.w32(p.health + ITEM_HEALTH)
					_sound(SOUND_ITEM, events)
					var head := p.body.joints[2].t
					item_popups[i].point = PackedInt32Array([head[0], head[1] - 300, head[2]])
					item_popups[i].view = sim.view
					put32(it, 2)
					put32(it + 0x18, gu32(CLOCK) + 0x3C)
					item_popups[i].until = g32(it + 0x18)
					fight.health_flash[p.player_index] = 1
			2:
				if gu32(CLOCK) == (gu32(it + 0x18) - 0xF) & 0xFFFFFFFF:
					_sound(SOUND_ITEM_END, events)
				if g32(it + 0x18) < g32(CLOCK):
					put32(it, 0)


## An item's state (0 none, 1 placed, 2 picked up: LIFE UP! shows) and world point.
func item(i: int) -> PackedInt32Array:
	var it := ITEMS + 0xBC * i
	return PackedInt32Array([gu32(it), g32(it + 4), g32(it + 8), g32(it + 0xC)])


# ==== the health bars (FUN_800B30DC, FUN_800B3118) ================================================

## FUN_800B30DC: the three bars empty (they fill up at the round start).
func bars_reset() -> void:
	for k in 3:
		var r := BARS + 0x10 * k
		put32(r, 0)
		for off: int in [4, 6, 8]:
			put16(r + off, 0)


## FUN_800B3118's state: the player's bar (0x9C pixels) and each shown enemy's (as wide as its
## type's entry): a drop shows at once, a refill grows 3 pixels per frame, the recent-damage part
## closes a sixteenth per frame.
func bars_step() -> void:
	for k in 3:
		var f := player() if k == 0 else slot_fighter(k - 1)
		if k > 0 and (f.invulnerable != 0 or fight.round_state == RoundState.INTRO):
			continue
		var width := 0x9C if k == 0 else ram.u16(KILL_SECONDS + 4 * g16(slot(k - 1) + 0xE))
		var r := BARS + 0x10 * k
		var target := g16(r + 4)
		var fill := g16(r + 6)
		var trail := g16(r + 8)
		var room := width - 4
		if g32(r) != f.health:
			var step := Fx.div_trunc(f.health_max, room)
			put32(r, f.health)
			target = Fx.div_trunc(f.health - 1 + step, step) if step != 0 else 0
		target = mini(target, room)
		var recent := trail - ((trail - fill + 0xF) >> 4) if fill < trail else fill
		var grown := target if target <= fill or target < fill + 3 else fill + 3
		if recent < grown:
			recent = grown
		put16(r + 4, target)
		put16(r + 6, grown)
		put16(r + 8, recent)


## A bar for the presentation: target, fill, recent damage, grows rightwards, x, y, width.
func bar(k: int) -> PackedInt32Array:
	var r := BARS + 0x10 * k
	var width := 0x9C if k == 0 else ram.u16(KILL_SECONDS + 4 * g16(slot(k - 1) + 0xE))
	return PackedInt32Array([g16(r + 4), g16(r + 6), g16(r + 8), g16(r + 0xA), gu16(r + 0xC), gu16(r + 0xE), width])
