class_name TekkenBall
extends RefCounted
## Tekken Ball (volley.ovl, mode 7; modes.md#tekken-ball), written from the verified port
## tools/research/ball_sim.py: the ball object, its physics and touches (FUN_800B16A4 with the attack
## and body tests FUN_80048030 / FUN_800481AC), the render kind and squash (FUN_800B2F14), the
## fight-start, round and frame hooks FightFrame calls (FUN_800B0C90, FUN_800B0DD8, FUN_800B0E14),
## the move tuning after MoveStartAll (FUN_800B0B54), and the power gauges and popup texts.
##
## State keeps the game's layout, as practice's does: the ball object (`b`, the fight heap's
## 0x800AE23C record) and volley.ovl's data from BASE (`v`, the ball types, the tuning records,
## the gauges and popups), loaded from the overlay image when the mode starts. The popups keep
## the world point they were placed at; the presentation projects it with the frame's camera
## (FUN_800B445C's screen point).

const BASE := 0x800B6400              ## volley.ovl's data and bss (the flow traces' "ball_mode" range)
const SIZE := 0xA00
const BALL_SIZE := 0x160
const THIRD := 2                       ## the third fighter record: the ball's stand-in attacker

# ---- the ball object
const B_STATE := 0x00
const B_POS := 0x68                    ## s32 x, y, z
const B_VEL := 0x78                    ## 8.8 per frame
const B_GRAVITY := 0x8C
const B_ANGLES := 0x98                 ## u16 x, y, z
const B_SPIN := 0xA0
const B_SPEED := 0xA8                  ## horizontal speed (8.8) along B_DIR
const B_DIR := 0xB0                    ## s16 angle (4096 a turn)
const B_HOMING := 0xB2
const B_CENTRE := 0xB8                 ## the attack test's cylinder: x, y, z, radius, radius²
const B_RADIUS := 0xC4
const B_LOCK := 0xCC                   ## u8 frames without touch tests
const B_SQUASHING := 0xCD
const B_POINTS := 0xD0                 ## 4 swept hit points (start xyz, end xyz)
const B_OWNER := 0x130                 ## fighter record address
const B_TARGET := 0x134
const B_SPIKE_TARGET := 0x138
const B_POWER := 0x13C                 ## s16 per player
const B_CHARGE := 0x140
const B_SPIKE_SPEED := 0x142
const B_REHITS := 0x144
const B_REHIT := 0x145
const B_KIND := 0x146                  ## the render kind
const B_TIMER := 0x147
const B_SQUASH_AXIS := 0x148
const B_SQUASH := 0x150

# ---- volley.ovl (addresses)
const GLOWS := 0x800B645C
const BALL_TABLE := 0x800B6460         ## per type 24 bytes: spike unit, speed unit, gravity, gain, zone
const BALL_VERTICES := 0x800B64A8
const HIT_VOLUME := 0x800B6808         ## 4 SVECTORs around the ball
const GAUGES := 0x800B68E8             ## 2 × 0x10: power seen, target, fill, trail, direction, x, y
const CENTRE_BAND := 0x800B6948
const SIDE_LINES := 0x800B69D8
const COURT := 0x800B6AB8
const SPEED_UNIT := 0x800B6AD8
const SPIKE_UNIT := 0x800B6ADA
const GRAVITY := 0x800B6ADC
const NEUTRAL := 0x800B6ADE
const GAIN := 0x800B6AE0
const IDLE := 0x800B6AE4
const TOUCH_SOUND_WAIT := 0x800B6AE8
const DRIFT := 0x800B6B40              ## per player 6 bytes: angle, speed, two frames, look-ahead
const POINT := 0x800B6B4C              ## 1 + the index of the player who lost the point
const POPUP_NEXT := 0x800B6B50
const CHARGED_HIT := 0x800B6B54
const POPUP_SLOTS := 0x800B6B58        ## 8 × 0x20
const POPUPS := 0x800B6C58             ## the list head
const EXCLAIM := "!"

const RESULT := 0x3C                   ## mode context +0x3C (0x800AFF8C): points per round
const SERVE_SIDE := 0x40               ## +0x40 (0x800AFF90): the side that serves first
const BALL_TYPE := 0x41                ## +0x41 (0x800AFF91)
const LAST_POINT := 0x38               ## +0x38 (0x800AFF88): a point is being scored
const CHOOSER := 0x43                  ## +0x43 (0x800AFF93): 1 << the side choosing the ball type, 3 while it does
const IDENTITY_WORDS: Array[int] = [0, 8, 16]   ## the words of an identity MATRIX holding 0x1000

const SOUND_SERVE := 0x4CE8
const SOUND_RESET := 0x4CE9
const SOUND_BOUNCE := 0x4E6E
const SOUND_TOUCH := 0x704E
const SOUND_SET := 0x7082
const SOUND_SPIKE := 0x4DAF
const SOUND_GUARDED := 0x7043
const SOUND_CHARGED := 0x4E6D
const HIGH := AttackWord.HIGH
const MIDS: Array[int] = [AttackWord.MID_2, AttackWord.MID]
const LOWS: Array[int] = [AttackWord.LOW, AttackWord.LOW_2]
const UNBLOCKABLE: Array[int] = [AttackWord.UNBLOCKABLE, AttackWord.UNBLOCKABLE_2]
const POINT_DAMAGE := 0x1E0000
const IDLE_FRAMES := 600
const FLOOR_Y := -0x180
const COURT_HALF := 0x2800
const CEILING := -0x2000
const SPIKE_CEILING := -0x1400

## One popup text over the ball (FUN_800B445C): `!` or a charged hit's damage.
class BallPopup:
	var text := ""
	var colour := 0
	var font := 0
	var frames := 0
	var rise := 0                      ## pixels risen since it was placed
	var point := PackedInt32Array([0, 0, 0])
	var view: ViewMatrix               ## the camera it was placed with

var fight: FightState:                 ## held weakly: FightState owns this object
	get: return _fight.get_ref() as FightState
var _fight: WeakRef
var t: FightTables
var v := ByteBlock.new(SIZE)
var b := ByteBlock.new(BALL_SIZE)
var popups: Array[BallPopup] = []          ## newest first (the list at 0x800B6C58)


func _init(fight_state: FightState) -> void:
	_fight = weakref(fight_state)
	t = fight_state.tables


## The mode's overlay image: volley.ovl's initial data (the ball types, the sphere, the hit volume).
func load_overlay(ram: GameRam) -> void:
	v.bytes = ram.bytes(BASE, SIZE)


# ==== byte access by game address ===================================================================

func _v16(a: int) -> int:
	return v.s16(a - BASE)


func _vu16(a: int) -> int:
	return v.u16(a - BASE)


func _v32(a: int) -> int:
	return v.s32(a - BASE)


func _vput16(a: int, x: int) -> void:
	v.put16(a - BASE, x)


func _vput32(a: int, x: int) -> void:
	v.put32(a - BASE, x)


## 0x800B6ADE: the half-width of the court's neutral zone (the side lines).
func neutral_zone() -> int:
	return _vu16(NEUTRAL)


## 0x800B6B54: the ball's last hit was a charged one (HitApply takes the attacker's reaction).
func charged_hit() -> bool:
	return v.u8(CHARGED_HIT - BASE) != 0


## 1 + the index of the player who lost the point this frame, 0 for none (MoveStep knocks that
## fighter down).
func point_loser() -> int:
	return _v32(POINT)


func state() -> int:
	return b.s16(B_STATE)


func position() -> PackedInt32Array:
	return PackedInt32Array([b.s32(B_POS), b.s32(B_POS + 4), b.s32(B_POS + 8)])


# ==== hooks =========================================================================================

## FUN_800B0B24: a player's move tuning cleared.
func drift_clear(player: int) -> void:
	var r := DRIFT + 6 * player
	_vput16(r, 0)
	for k in range(2, 6):
		v.put8(r + k - BASE, 0)


## FUN_800B0C90 (the round start in mode 7): the ball type's constants, the ball, the players at
## x = ∓0x1400 facing each other, and two points per round.
func fight_start(sim: FightSimulation) -> void:
	var region := fight.region
	var table := BALL_TABLE + 24 * region.ctx8(BALL_TYPE)
	_vput16(SPIKE_UNIT, _vu16(table))
	_vput16(SPEED_UNIT, _vu16(table + 4))
	_vput16(GRAVITY, _vu16(table + 8))
	_vput16(GAIN, _vu16(table + 0x10))
	_vput16(NEUTRAL, _vu16(table + 0x14))
	ball_init()
	for i in 2:
		var f := fight.fighters[i]
		f.pos_x = -0x1400 if i == 0 else 0x1400
		f.pos_z = 0
		f.facing = 0x4000 if i == 0 else 0xC000
		sim.place(f, fight.fighters[1 - i], false)
	popups.clear()
	v.put32(POPUPS - BASE, 0)
	v.put32(POPUP_NEXT - BASE, 0)
	for i in 8:
		v.put8(POPUP_SLOTS + 0x20 * i + 0x1F - BASE, 0)
	for g in 2:
		var r := GAUGES + 0x10 * g
		_vput32(r, 0)
		for off: int in [4, 6, 8]:
			_vput16(r + off, 0)
	region.ctx_put32(LAST_POINT, 0)
	region.ctx_put32(RESULT, 2)
	v.put8(GLOWS - BASE, 0)
	_vput32(TOUCH_SOUND_WAIT, 0)


## FUN_800B0DD8: the court's matrix and a new ball (the select screen's preview).
func round_reset() -> void:
	_vput32(0x800B6AA8, 0)
	for i in range(0, 0x20, 4):
		_vput32(COURT + i, 0x1000 if i in IDENTITY_WORDS else 0)
	ball_init()


## FUN_800B5B6C: the ball on the select screen: no side has chosen yet, the preview spins at the
## centre (render kind 10).
func preview() -> void:
	fight.region.ctx_put8(CHOOSER, 0)
	round_reset()
	b.put32(B_GRAVITY, 0x220)
	b.put16(B_DIR, 1)
	b.put8(B_KIND, 10)
	b.put32(B_POS, 0)
	b.put32(B_POS + 4, 0)
	b.put32(B_POS + 8, 0)
	b.put32(B_VEL, 0)


## FUN_800B569C: the ball type chosen by the first side to finish (`pressed`: its pad): left /
## right spin the ball to the previous / next type (it slides out and back in), a face button
## takes the type once the ball rests (1), Select backs out (−1); 0 while choosing.
func side_select(pressed: int, events: SimEvents) -> int:
	var region := fight.region
	region.ctx_put8(CHOOSER, 3)
	b.put16(B_ANGLES + 2, b.u16(B_ANGLES + 2) + 8)
	b.put16(B_ANGLES, b.u16(B_ANGLES) + 1)
	var x := b.s32(B_POS) + ((b.s32(B_VEL) - b.s32(B_POS)) >> 3)
	b.put32(B_POS, x)
	b.put16(B_ANGLES + 4, b.u16(B_ANGLES + 4) + 2)
	if x < -0x7FF and b.s16(B_DIR) == -1:
		var ty := region.ctx8(BALL_TYPE) + 1
		region.ctx_put8(BALL_TYPE, 0 if ty > 2 else ty)
		b.put32(B_POS, 0x800)
		b.put32(B_VEL, 0)
	if b.s32(B_POS) > 0x7FF and b.s16(B_DIR) == 1:
		var ty := region.ctx8(BALL_TYPE)
		region.ctx_put8(BALL_TYPE, 2 if ty == 0 else ty - 1)
		b.put32(B_POS, -0x800)
		b.put32(B_VEL, 0)
	if pressed & PadState.LEFT:
		b.put32(B_VEL, -0x1000)
		b.put16(B_DIR, -1)
		_sound(0x55F5, events)
	if pressed & PadState.RIGHT:
		b.put32(B_VEL, 0x1000)
		b.put16(B_DIR, 1)
		_sound(0x55F5, events)
	if absi(b.s32(B_POS) - b.s32(B_VEL)) > 0x3F:
		return 0
	var result := 0
	if pressed & PadState.SELECT:
		result = -1
	if pressed & PadState.FACE_BUTTONS:
		_sound(0x50F4, events)
		result = 1
	return result


## FUN_800B0FDC: the ball at the start of a round (and after a point).
func ball_init() -> void:
	b.put16(B_STATE, 0)
	b.put16(2, 0)
	b.put8(B_TIMER, 100 if fight.rounds_played == 1 else 40)
	b.put32(0x44, 0)
	for i in range(0, 0x20, 4):
		b.put32(0x48 + i, 0x1000 if i in IDENTITY_WORDS else 0)
	var side := fight.region.ctx8(SERVE_SIDE)
	b.put32(B_POS, 0xD00 if side != 0 else -0xD00)
	b.put32(B_OWNER, FighterState.address(side))
	b.put32(B_POS + 4, -0x500)
	b.put16(B_SPIN, 0x20)
	b.put16(B_SPIN + 2, 0x10)
	b.put16(B_SPIN + 4, 4)
	for off: int in [0x70, 0xA8, 0xAC, 0x7C, 0x80, 0x78, 0x90, 0x8C, 0x88]:
		b.put32(off, 0)
	for off: int in [0x13C, 0x13E, 0x140, 0x9C, 0x9A, 0x98, 0xB0, 0xB2, 0x14C, 0x14A, 0x148, 0x150]:
		b.put16(off, 0)
	b.put8(B_LOCK, 0)
	b.put32(B_TARGET, FighterState.address(1 - side))
	b.put32(B_GRAVITY, _v16(GRAVITY))
	b.put8(B_REHITS, 0)
	b.put16(B_RADIUS, 0x260)
	b.put32(0xC8, 0x5A400)
	b.put32(0xB4, BALL_VERTICES)
	for i in 3:
		b.put32(B_CENTRE + 4 * i, b.u32(B_POS + 4 * i))
	_hit_volume()
	_hit_volume()
	var zone := _vu16(NEUTRAL)
	var z := -0x1F40
	for i in 9:
		for pair: Array in [[CENTRE_BAND, 0x64], [SIDE_LINES, zone]]:
			var base: int = pair[0]
			var x: int = pair[1]
			for k in 2:
				var at := base + 16 * i + 8 * k
				_vput16(at, -x if k == 0 else x)
				_vput16(at + 2, 0)
				_vput16(at + 4, z)
		z += 0x600


## FUN_800B0B54 (after MoveStartAll): the Tekken Ball tuning of the running move slot
## (curSlot − 0x18): slots 0x18/0x1A drift (0x8000, 30, 3, 9); 0x1E/0x20 (0x8000, 150, 5, 12,
## look-ahead from frame 18); 0x1F/0x21 only the look-ahead frame 18.
func move_tuning(f: FighterState) -> void:
	var r := DRIFT + 6 * f.player_index
	drift_clear(f.player_index)
	var k := Fx.s16(f.cur_slot - 0x18)
	if k < 0 or k >= 10:
		return
	match k:
		0, 2:
			_vput16(r, 0x8000)
			v.put8(r + 2 - BASE, 0x1E)
			v.put8(r + 3 - BASE, 3)
			v.put8(r + 4 - BASE, 9)
		6, 8:
			_vput16(r, 0x8000)
			v.put8(r + 2 - BASE, 0x96)
			v.put8(r + 3 - BASE, 5)
			v.put8(r + 4 - BASE, 0xC)
			v.put8(r + 5 - BASE, 0x12)
		7, 9:
			v.put8(r + 5 - BASE, 0x12)


## A player's tuning record (the move system reads the look-ahead frame, the physics the drift).
func drift(player: int) -> PackedInt32Array:
	var r := DRIFT + 6 * player - BASE
	return PackedInt32Array([v.u16(r), v.u8(r + 2), v.u8(r + 3), v.u8(r + 4), v.u8(r + 5)])


## FUN_800B0E14 (after MoveBranchAll, and on the frames the fight only draws or replays): the
## ball's physics unless the fight is frozen, then the gauges and popups.
func frame(sim: FightSimulation, events: SimEvents) -> void:
	var f_a := fight.fighters[0]
	var f_b := fight.fighters[1]
	if fight.round_state == RoundState.FIGHT:
		fight.region.ctx_put32(RESULT, 2)
	if _v32(TOUCH_SOUND_WAIT) > 0:
		_vput32(TOUCH_SOUND_WAIT, _v32(TOUCH_SOUND_WAIT) - 1)
	if fight.freeze == 0 and fight.paused_player == 0:
		fight.replay.ball(self)
		if fight.replay_playing == 0:
			update(sim, f_a, f_b, events)
			after_update()
		elif b.u32(0x144) & 0xFFFF0000 == 0x05020000:
			_sound(SOUND_BOUNCE, events)
	if state() != 0:
		_draw_effects()
	var hidden := fight.pause_page == PauseMenu.PAGE_COMMAND and fight.region.human_count != 1
	if not hidden:
		var charge := b.s16(B_CHARGE)
		var highlight := 1 << FighterState.index_at(b.u32(B_OWNER)) if charge != 0 else 0
		_gauges(b.s16(B_POWER), 100, b.s16(B_POWER + 2), highlight)
		_popups_step(fight.paused_player != 0 or fight.freeze != 0)


# ==== physics (FUN_800B16A4) ==========================================================================

func update(sim: FightSimulation, f_a: FighterState, f_b: FighterState, events: SimEvents) -> void:
	var keep := b.u8(B_REHIT) if b.u8(B_LOCK) != 0 else 0
	b.put8(B_REHIT, keep)
	v.put8(CHARGED_HIT - BASE, 0)
	_vput32(POINT, 0)
	var st := state()
	match st:
		0:
			var n := (b.u8(B_TIMER) - 1) & 0xFF
			b.put8(B_TIMER, n)
			if n == 0:
				b.put16(B_STATE, 8)
				b.put8(B_TIMER, 0x20)
				_sound(SOUND_SERVE, events)
			return
		1, 8:
			var n := (b.u8(B_TIMER) - 1) & 0xFF
			b.put8(B_TIMER, n)
			if n != 0:
				return
			b.put16(B_STATE, 9 if st == 8 else 2)
			b.put32(B_SPEED, 0)
			b.put8(B_LOCK, 0)
			b.put16(B_DIR, 0)
			b.put16(B_HOMING, 0)
			var x0 := mini(f_a.root_x, 0)
			var x1 := maxi(f_b.root_x, 0)
			var z0 := f_a.root_z
			var dx := Fx.w32(x1 - x0)
			var dz := Fx.w32(f_b.root_z - z0)
			if dx != 0:
				b.put32(B_POS + 8, z0 + _div(Fx.w32((b.s32(B_POS) - x0) * dz), dx))
			else:
				b.put32(B_POS, x0 + _div(0, dz))
			return
		6:
			b.put16(B_CHARGE, 0)
			b.put8(B_REHITS, 0)
			var n := (b.u8(B_TIMER) - 1) & 0xFF
			b.put8(B_TIMER, n)
			if n != 0:
				return
			b.put16(B_STATE, 1)
			b.put8(B_TIMER, 0x20)
			b.put32(B_POS, 0)
			b.put32(B_POS + 4, -0xE40)
			for off: int in [0x90, 0x88, 0x80, 0x7C, 0x78]:
				b.put32(off, 0)
			for off: int in [0xA4, 0xA2, 0xA0]:
				b.put16(off, 0)
			b.put32(B_GRAVITY, _v16(GRAVITY) >> 1)
			b.put32(B_POS + 8, Fx.w32(f_a.root_z + f_b.root_z) >> 1)
			_hit_volume()
			_hit_volume()
			if fight.no_damage == 0:
				_sound(SOUND_RESET, events)
			return
		7:
			b.put16(B_CHARGE, 0)
			b.put8(B_REHITS, 0)
			var n := (b.u8(B_TIMER) - 1) & 0xFF
			b.put8(B_TIMER, n)
			if n == 0:
				b.put16(B_STATE, 6)
				b.put8(B_TIMER, 0x10)
			return
	# Bug #44 (not reproduced): the frames without touch tests use no hit mask.
	var mask := 0
	var g := _v16(GRAVITY)
	var y := b.s32(B_POS + 4)
	if st == 4 and y < SPIKE_CEILING:
		b.put32(B_POS + 4, SPIKE_CEILING)
		b.put32(B_GRAVITY, g)
		b.put16(B_STATE, 2)
		b.put32(B_TARGET, b.u32(B_SPIKE_TARGET))
		b.put32(B_SPEED, b.s16(B_SPIKE_SPEED))
		b.put32(B_VEL + 4, Fx.div_trunc(b.s16(B_SPIKE_SPEED) * 2, 3) + 0x1000)
	elif st != 4 and y < CEILING:
		b.put32(B_POS + 4, CEILING)
		b.put32(B_VEL + 4, 0)
		b.put32(B_GRAVITY, g)
	else:
		mask = _floor_and_touches(sim, f_a, f_b, mask, events)
	_tail(mask)


func _floor_and_touches(sim: FightSimulation, f_a: FighterState, f_b: FighterState, mask: int, events: SimEvents) -> int:
	var g := _v16(GRAVITY)
	var x := b.s32(B_POS)
	if b.s32(B_POS + 4) >= FLOOR_Y or absi(x) > COURT_HALF:
		b.put32(B_POS + 4, FLOOR_Y)
		b.put32(B_GRAVITY, g)
		var vy := b.s32(B_VEL + 4)
		if vy > 0xD00:
			_sound(SOUND_BOUNCE, events)
		if fight.region.ctx8(BALL_TYPE) == 2:
			if vy > 0x3000:
				CameraShake.start(fight, 1, events)
			elif vy > 0x1800:
				CameraShake.start(fight, 0, events)
		x = b.s32(B_POS)
		if absi(x) <= _v16(NEUTRAL):
			b.put16(B_STATE, 2)
			b.put32(B_VEL + 4, Fx.w32(-b.s32(B_VEL + 4)) >> 1)
			for off: int in [0xA0, 0xA2, 0xA4]:
				b.put16(off, b.s16(off) >> 1)
		else:
			b.put32(B_VEL + 4, 0)
			b.put32(B_SPEED, 0)
			if fight.no_damage != 0 or state() == 5:
				b.put16(B_STATE, 6)
				b.put8(B_TIMER, 0x10)
				return mask
			b.put16(B_POWER if x < 0 else B_POWER + 2, 0)
			var loser := f_a if x < 0 else f_b
			var hp := Fx.w32(loser.health - POINT_DAMAGE)
			loser.health = hp
			loser.last_attacker = (loser.index + 1) & 1
			if hp < 0:
				loser.health = 0
			b.put16(B_STATE, 7)
			b.put8(B_TIMER, 5)
			_vput32(POINT, 0 if fight.throw_count != 0 else loser.index + 1)
			var third := fight.fighters[THIRD]
			third.root_x = b.s32(B_POS)
			third.root_z = b.s32(B_POS + 8)
			return mask
	if b.s32(B_POS + 4) < -0x189:
		_vput32(IDLE, 0)
	else:
		var n := _v32(IDLE) + 1
		_vput32(IDLE, n)
		if n >= IDLE_FRAMES:
			b.put16(B_STATE, 6)
			b.put8(B_TIMER, 0x10)
			return mask
	if b.s16(B_HOMING) == 0:
		b.put32(B_SPEED, maxi(Fx.w32(b.s32(B_SPEED) - 0x20), 0))
	if b.u8(B_LOCK) != 0:
		b.put8(B_LOCK, b.u8(B_LOCK) - 1)
		return mask
	return _touches(sim, f_a, f_b, events)


func _tail(mask: int) -> void:
	var angle := b.u16(B_DIR) & 0xFFF
	var cos := FightMath.cos12(angle, t)
	var sin := FightMath.sin12(angle, t)
	var speed := b.s32(B_SPEED)
	b.put32(B_VEL, Fx.w32(cos * speed) >> 12)
	b.put32(B_VEL + 8, Fx.w32(sin * speed) >> 12)
	if state() == 9:
		# The serve: the ball bobs until someone touches it or 600 frames pass.
		var n := b.u8(B_TIMER)
		var s := FightMath.sin12((n << 6 & 0x1FC0) >> 1, t) & 0xFFFF
		b.put8(B_TIMER, n + 1)
		b.put32(B_POS + 4, (Fx.s16(s) >> 4) - 0x500)
		if fight.round_frame >= 600:
			b.put16(B_STATE, 2)
			b.put32(B_VEL + 4, 0)
	else:
		for i in 3:
			b.put32(B_POS + 4 * i, b.s32(B_POS + 4 * i) + (b.s32(B_VEL + 4 * i) >> 8))
	_hit_volume()
	b.put32(B_VEL + 4, b.s32(B_VEL + 4) + b.s32(B_GRAVITY))
	if mask != 0 and state() != 3:
		angle = b.u16(B_DIR) & 0xFFF
		cos = FightMath.cos12(angle, t)
		sin = FightMath.sin12(angle, t)
		speed = b.s32(B_SPEED)
		var spin := Fx.w32(cos * speed) >> (0x11 if b.s16(B_HOMING) != 0 else 0x13)
		b.put16(B_SPIN + 4, spin)
		b.put16(B_SPIN, Fx.s16(spin) >> 2)
		b.put16(B_SPIN + 2, Fx.w32(sin * speed) >> 0x13)
	for i in 3:
		b.put16(B_ANGLES + 2 * i, b.u16(B_ANGLES + 2 * i) + b.u16(B_SPIN + 2 * i))
	var z_old := b.s32(B_POS + 8)
	var mid := Fx.w32(fight.fighters[0].root_z + fight.fighters[1].root_z) >> 1
	if Fx.w32(z_old - mid) > 0x80:
		b.put32(B_POS + 8, mid + 0x80)
	if Fx.w32(b.s32(B_POS + 8) - mid) < -0x80:
		b.put32(B_POS + 8, mid - 0x80)
	b.put16(B_ANGLES, b.u16(B_ANGLES) + b.u16(B_POS + 8) - (z_old & 0xFFFF))
	var target := fight.fighters[FighterState.index_at(b.u32(B_TARGET))]
	var tx := fight.fighters[target.index].root_x
	var tz := fight.fighters[target.index].root_z
	var a := b.s16(B_DIR)
	if a < -0x800:
		b.put16(B_DIR, a + 0x1000)
	if b.s16(B_DIR) > 0x800:
		b.put16(B_DIR, b.u16(B_DIR) - 0x1000)
	if b.s16(B_HOMING) == 0:
		return
	b.put16(B_DIR, _atan2(tx - b.s32(B_POS), tz - b.s32(B_POS + 8)))
	if b.s32(B_SPEED) <= 0x1000:
		return
	var dx := Fx.w32(b.s32(B_POS) - tx)
	var dz := Fx.w32(b.s32(B_POS + 8) - tz)
	var dist := CameraMath.isqrt(Fx.w32(Fx.w32(dx * dx) + Fx.w32(dz * dz)) & 0xFFFFFFFF)
	var n := _div(dist, b.s32(B_SPEED) >> 8)
	var vy := b.s32(B_VEL + 4)
	var head := target.body.joints[1].t[1]
	var fall := Fx.w32(vy + Fx.w32(n * b.s32(B_GRAVITY))) >> 8
	var miss := Fx.w32(Fx.w32(b.s32(B_POS + 4) + fall - head) << 8)
	var q := _div(Fx.w32(vy - miss), n)
	b.put32(B_VEL + 4, Fx.w32(Fx.w32(vy * 13 + q * 3) << 8) >> 12)


## The four hit points sweep from their last position to the ball's position + offset.
func _hit_volume() -> void:
	for j in 4:
		var s := B_POINTS + 0x18 * j
		for i in 3:
			b.put32(s + 4 * i, b.u32(s + 0xC + 4 * i))
		for i in 3:
			b.put32(s + 0xC + 4 * i, b.s32(B_POS + 4 * i) + _v16(HIT_VOLUME + 8 * j + 2 * i))


# ==== touches ========================================================================================

## The attack and body tests of a flying ball; returns the hit mask.
func _touches(sim: FightSimulation, f_a: FighterState, f_b: FighterState, events: SimEvents) -> int:
	for i in 3:
		b.put32(B_CENTRE + 4 * i, b.u32(B_POS + 4 * i))
	var d := PackedInt32Array([0, 0, 0])
	var mask := _attack_touch(f_a, f_b, d)
	if mask & 7 != 0:
		var hitter := f_a if mask & 2 else f_b
		var other := f_b if mask & 2 else f_a
		if hitter.hit_done[2] == 0:
			_attack_hit(hitter, other, mask, d, events)
		return mask
	mask = 0
	if f_a.in_throw == 0 and f_b.in_throw == 0:
		mask = _body_touch(f_a, f_b)
	if fight.round_state > RoundState.WIN_POSES:
		if f_b.active == 0:
			mask &= 2
		elif f_a.active == 0:
			mask &= 1
	if mask == 0:
		return 0
	var hitter := f_a if mask & 2 else f_b
	var other := f_b if mask & 2 else f_a
	var owner := b.u32(B_OWNER)
	var charge := b.s16(B_CHARGE)
	if FighterState.address(hitter.index) == owner and charge != 0:
		return mask
	b.put32(B_SPEED + 4, 0)
	b.put16(B_HOMING, 0)
	if state() != 3:
		b.put16(B_STATE, 2)
	b.put16(B_DIR, _atan2(other.root_x - b.s32(B_POS), other.root_z - b.s32(B_POS + 8)))
	var lob := fight.fighter_distance & 0xFFFFFFFF
	var g := _v16(GRAVITY)
	var k := Fx.w32((lob >> 7) + 12)
	b.put32(B_GRAVITY, g)
	b.put32(B_VEL + 4, Fx.w32((Fx.w32(-g * k) >> 1) - Fx.w32(b.s32(B_POS + 4) + 0x1000)))
	var dist := Fx.w32(lob - 0x800) if lob > 0x800 else 0x400
	b.put32(B_SPEED, _div(Fx.w32(dist << 8), k))
	if charge == 0 or owner == FighterState.address(hitter.index):
		if _v32(TOUCH_SOUND_WAIT) == 0:
			_sound(SOUND_TOUCH, events)
			_vput32(TOUCH_SOUND_WAIT, 10)
		b.put32(B_OWNER, FighterState.address(hitter.index))
		b.put32(B_TARGET, FighterState.address(other.index))
	else:
		_charged_touch(hitter, other, events)
	return mask


## FUN_80048030: the fighters' attack segments against the ball's cylinder; bit 2 for `f_a`, bit 1
## for `f_b`, bit 8 when a move uses projectile segments. The first hitting segment's direction
## goes to `d`.
func _attack_touch(f_a: FighterState, f_b: FighterState, d: PackedInt32Array) -> int:
	var cyl := PackedInt32Array([b.s32(B_CENTRE), b.s32(B_CENTRE + 4), b.s32(B_CENTRE + 8),
		b.s32(B_RADIUS) & 0xFFFF, b.s32(0xC8)])
	var mask := 0
	var bit := 2
	for fighter: FighterState in [f_a, f_b]:
		var segments: Array = fighter.attack_segs
		var count := mini(fighter.active_segs, 4)
		if AttackRecords.header(fighter.pose_move, t)[0] >= Combat.PROJECTILE_JOINT:
			mask |= 8
			segments = fight.effects.segments[mini(fighter.index, 1)]
			count = segments.size()
		for k in maxi(count, 0):
			var s: PackedInt32Array = segments[k]
			if FightMath.segment_hits_cylinder(s, cyl, fight.rules.fix_segment_hit_overflow):
				for i in 3:
					d[i] = Fx.w32(s[3 + i] - s[i])
				mask |= bit
				break
		bit = 1
	return mask


## FUN_800481AC: the ball's four swept hit points against each fighter's 14 hurt cylinders; the
## first contact goes to the fighter's first hit slot. Bit 2 for `f_a`, bit 1 for `f_b`.
func _body_touch(f_a: FighterState, f_b: FighterState) -> int:
	var mask := 0
	var bit := 2
	for fighter: FighterState in [f_a, f_b]:
		var done := false
		for k in 14:
			var c := fighter.hurt_zones[k]
			if Fx.s16(c[3]) == 0:
				continue
			for j in 4:
				var at := B_POINTS + 0x18 * j
				var s := PackedInt32Array()
				for i in 6:
					s.append(b.s32(at + 4 * i))
				if FightMath.segment_hits_cylinder(s, c, fight.rules.fix_segment_hit_overflow):
					var slot := fighter.hit_slots[0]
					slot.zone = k
					for i in 3:
						slot.point[i] = s[3 + i]
						slot.direction[i] = Fx.s16(s[3 + i] - s[i])
					mask |= bit
					done = true
					break
			if done:
				break
		bit = 1
	return mask


## The shared part of a charging hit: re-hit bookkeeping, the hitter's power gain (damage · gain
## / 100), the charge and the damage popup; returns the speed steps clamped to 20..cap.
func _charge_hit(hitter: FighterState, base_add: int, cap: int) -> int:
	if b.s16(B_CHARGE) != 0:
		b.put8(B_REHIT, 1)
		b.put8(B_REHITS, b.u8(B_REHITS) + 1)
	var add := Fx.div_trunc(Fx.s16(hitter.damage) * _v16(GAIN), 100)
	var slot := B_POWER + 2 * hitter.player_index
	var power := (b.u16(slot) + add) & 0xFFFF
	b.put16(slot, power)
	b.put16(B_CHARGE, power)
	b.put16(B_HOMING, 1)
	var colour := 2 if FighterState.index_at(b.u32(B_OWNER)) == 0 else 5
	_popup_add(str(add), colour, 1, 0x1E)
	var steps := Fx.s16((hitter.damage & 0xFFFF) + base_add)
	if steps >= cap + 1:
		steps = cap
	elif steps < 0x14:
		steps = 0x14
	return steps


func _speed_from_steps(steps: int) -> void:
	var speed := (steps + b.u8(B_REHITS)) * _v16(SPIKE_UNIT)
	if b.u8(B_REHIT) != 0:
		speed += b.s32(B_SPEED) >> 4
	b.put32(B_SPEED, speed)


## A fighter's attack hits the ball: the ball takes the hitter's record as its attacker and flies
## by the attack level.
func _attack_hit(hitter: FighterState, other: FighterState, mask: int, d: PackedInt32Array, events: SimEvents) -> void:
	_take_ball(hitter, other, d, events)
	var g := _v16(GRAVITY)
	var unit := _v16(SPEED_UNIT)
	var x := b.s32(B_POS)
	var level := hitter.attack & 0xFFFF
	var damage := Fx.s16(hitter.damage)
	var lob := fight.fighter_distance
	if mask & 3 == 3:
		# Both players at once: the ball pops up neutrally.
		b.put16(B_CHARGE, 0)
		b.put32(B_SPEED, 0)
		b.put16(B_STATE, 2)
		b.put32(B_VEL + 4, -0x25 * g)
		b.put32(B_GRAVITY, g)
	elif hitter.bank_type == BankType.YOSHIMITSU and level in UNBLOCKABLE and mask & 8 == 0 and hitter.cur_slot != 0x181:
		_yoshimitsu_unblockable(hitter, other)
	elif damage == 0:
		_set_hit(damage, g, unit, x, events)
	elif level in UNBLOCKABLE:
		_homing_hit(hitter, other, lob)
	elif hitter.in_air == 0:
		_ground_hit(hitter, other, level, damage, g, unit, x, lob, events)
	else:
		# The hitter is airborne.
		_speed_from_steps(_charge_hit(hitter, 0xF, 0x28))
		b.put16(B_STATE, 2)
		b.put32(B_GRAVITY, _v16(GRAVITY) >> 1)
		b.put32(B_VEL + 4, Fx.w32(other.root_z - b.s32(B_POS + 4) - lob))


## The hitter takes the ball: the third record carries its move, the ball turns towards the
## other player and squashes by the damage.
func _take_ball(hitter: FighterState, other: FighterState, d: PackedInt32Array, events: SimEvents) -> void:
	Vibration.fighter(fight, hitter.player_index, 5, events)
	b.put32(B_SPEED + 4, 0)
	b.put32(B_OWNER, FighterState.address(hitter.index))
	b.put32(B_TARGET, FighterState.address(other.index))
	b.put16(B_HOMING, 0)
	var third := fight.fighters[THIRD]
	third.copy_from(hitter)
	third.index = THIRD
	third.power_timer = 1
	third.attack = 0xFFFF
	third.about_to_hit = 1
	hitter.hit_done[2] = 1
	hitter.contact_this_move = 1
	hitter.contact = 1
	hitter.last_hit_target = 2
	b.put8(B_LOCK, 5)
	b.put16(B_DIR, _atan2(other.root_x - b.s32(B_POS), other.root_z - b.s32(B_POS + 8)))
	_squash_axis(d)
	b.put8(B_SQUASHING, 1)
	b.put16(B_SQUASH, (hitter.damage & 0xFFFF) * 8 + 0x140)


## Yoshimitsu's unblockable: his own health pays the opponent's stored power, and the point ends.
func _yoshimitsu_unblockable(hitter: FighterState, other: FighterState) -> void:
	var hp := Fx.w32(hitter.health - (b.s16(B_POWER + 2 * other.index) << 16))
	hitter.health = maxi(hp, 0)
	b.put16(B_POWER + 2, 0)
	b.put16(B_POWER, 0)
	b.put16(B_STATE, 7)
	b.put8(B_TIMER, 5)
	_vput32(POINT, hitter.index + 1)


## A move without damage sets a charged ball up, or hits it flat.
func _set_hit(damage: int, g: int, unit: int, x: int, events: SimEvents) -> void:
	if b.s16(B_CHARGE) > 0:
		b.put16(B_STATE, 3)
		b.put32(B_VEL + 4, -0x25 * g)
		b.put32(B_GRAVITY, g)
		b.put16(B_SPIKE_SPEED, b.u16(B_SPEED) + _vu16(SPIKE_UNIT) * 5)
		var quarter := b.s32(B_SPEED) >> 2
		var s := Fx.w32((damage + 8) * unit)
		s = Fx.w32((s + x if x >= 0 else s - x) - quarter)
		b.put32(B_SPEED, s if s >= 0 else 0)
		b.put16(B_CHARGE, 0)
		b.put8(B_LOCK, b.u8(B_LOCK) + 2)
		_popup_add(EXCLAIM, 1, 1, 0x1E)
		_sound(SOUND_SET, events)
	else:
		_flat(10, damage, g, unit, x)


## Unblockable: the ball homes in with the hitter's power as its charge.
func _homing_hit(hitter: FighterState, other: FighterState, lob: int) -> void:
	b.put16(B_HOMING, 1)
	b.put32(B_SPEED, _v16(SPIKE_UNIT) * 60)
	b.put32(B_GRAVITY, _v16(GRAVITY) >> 2)
	b.put16(B_CHARGE, b.u16(B_POWER + 2 * hitter.player_index))
	b.put16(B_STATE, 2)
	b.put32(B_VEL + 4, Fx.w32(other.root_z - 2 * b.s32(B_POS + 4) - lob))
	_popup_add(EXCLAIM, 2, 1, 0x1E)


## A grounded hit by level: mids lob it charged, lows shoot it low, highs hit it flat or spike a
## set ball.
func _ground_hit(hitter: FighterState, other: FighterState, level: int, damage: int, g: int, unit: int,
		x: int, lob: int, events: SimEvents) -> void:
	if level in MIDS:
		# Mids: a charged lob.
		_speed_from_steps(_charge_hit(hitter, 0x12, 0x2E))
		b.put32(B_GRAVITY, _v16(GRAVITY) >> 2)
		b.put16(B_STATE, 2)
		b.put32(B_VEL + 4, Fx.w32(other.root_z - 2 * b.s32(B_POS + 4) - lob))
	elif level in LOWS:
		b.put32(B_VEL + 4, -0x32 * g)
		b.put32(B_GRAVITY, g)
		b.put32(B_SPEED, Fx.w32((Fx.s16(hitter.damage & 0xFFFF) >> 2) * unit + absi(x)))
		b.put16(B_CHARGE, 0)
		b.put16(B_STATE, 2)
	elif level == HIGH:
		if state() != 3:
			_flat(10, damage, g, unit, x)
		else:
			# A spike.
			b.put16(B_STATE, 4)
			b.put32(B_SPIKE_TARGET, FighterState.address(other.index))
			b.put32(B_VEL + 4, -0x48 * g)
			b.put32(B_GRAVITY, g)
			b.put32(B_SPEED, unit * 10)
			_sound(SOUND_SPIKE, events)
			_charge_hit(hitter, 0, 0x7FFF)


## A flat, fast hit (highs, sets without a charge).
func _flat(extra: int, damage: int, g: int, unit: int, x: int) -> void:
	b.put32(B_GRAVITY, g)
	b.put32(B_VEL + 4, -0x25 * g)
	var quarter := b.s32(B_SPEED) >> 2
	var s := Fx.w32((damage + extra) * unit)
	s = s - x if x < 0 else s + x
	s = Fx.w32(s - quarter)
	b.put32(B_SPEED, s if s >= 0 else 0)
	b.put16(B_CHARGE, 0)
	b.put16(B_STATE, 2)


## The charged ball reaches the opponent: the resident hit system with the third record as the
## attacker, whose damage is the charge.
func _charged_touch(hitter: FighterState, other: FighterState, events: SimEvents) -> void:
	var third := fight.fighters[THIRD]
	var charge := b.u16(B_CHARGE)
	third.damage = charge
	b.put32(B_OWNER, FighterState.address(hitter.index))
	b.put32(B_TARGET, FighterState.address(other.index))
	b.put16(B_STATE, 2)
	v.put8(CHARGED_HIT - BASE, 1)
	b.put16(B_CHARGE, 0)
	third.hit_done[other.index] = 1
	third.contact_this_move = 1
	third.contact = 1
	third.last_hit_target = other.index
	hitter.was_hit_this_move = 1
	hitter.got_hit = 1
	hitter.hit_freeze_in = third.pose_move.hit_freeze
	hitter.hit_slots[0].used = 1
	hitter.hit_slots[0].attacker = THIRD
	var c := Fx.s16(third.damage)
	if c != 0 or hitter.in_air != 0:
		hitter.hit_cooldown = 4
	var lethal := c > 99 or b.u8(B_KIND) == 9
	if hitter.guard & third.attack == 0:
		if lethal:
			EffectObjects.burn(fight, hitter.index, events)
			_log_burn(hitter)
			if fight.region.ctx8(BALL_TYPE) == 2:
				fight.region.ctx_put32(RESULT, 6)
		var g := _vu16(GRAVITY)
		b.put32(B_SPEED, 0)
		b.put8(B_REHITS, 0)
		b.put16(B_POWER, 0)
		b.put16(B_POWER + 2, 0)
		b.put16(B_STATE, 5)
		b.put32(B_OWNER, FighterState.address(hitter.index))
		b.put32(B_TARGET, FighterState.address(hitter.index))
		b.put8(B_LOCK, 5)
		b.put32(B_VEL + 4, Fx.s16(g) * -0x25)
		b.put32(B_GRAVITY, Fx.s16(g) >> 1)
		_sound(SOUND_CHARGED if c < 0x32 else SOUND_SPIKE, events)
	else:
		_sound(SOUND_GUARDED, events)
		if lethal and hitter.health <= Fx.w32(c << 13):
			EffectObjects.burn(fight, hitter.index, events)
			_log_burn(hitter)


## The replay's record of a lethal charged hit (FUN_8004A840(player, 0x82, buffer, 1)): a dust
## ring when the replay plays it. Bug #45 (not reproduced): the game copies the point from a stack
## buffer it never fills; here it is the burned fighter's position, as a fall's dust records.
func _log_burn(hitter: FighterState) -> void:
	var point := PackedInt32Array([hitter.root_x, hitter.root_y, hitter.root_z])
	fight.replay.log_effect(hitter.index, 0x82, point, PackedInt32Array([0, 0, 0]), 1)


## volley.ovl FUN_800B3118: the squash axis angles from the hit direction.
func _squash_axis(d: PackedInt32Array) -> void:
	b.put16(B_SQUASH_AXIS, 0)
	b.put16(B_SQUASH_AXIS + 2, _atan2(d[0], d[2]))
	var a := Fx.s16(_atan2(d[0], d[1]))
	b.put16(B_SQUASH_AXIS + 4, a if d[0] > 0 else -a)


# ==== render kind and glow (FUN_800B2F14) ============================================================

func after_update() -> void:
	var s := b.s16(B_SQUASH)
	var relax := true
	if b.s16(B_HOMING) != 0:
		if s < 0x80:
			relax = false
			b.put8(B_SQUASHING, 0)
			_squash_axis(PackedInt32Array([b.s32(B_VEL), b.s32(B_VEL + 4), b.s32(B_VEL + 8)]))
			b.put16(B_SQUASH_AXIS + 4, b.u16(B_SQUASH_AXIS + 4) + 0x400)
			var sq := Fx.div_trunc(b.s16(B_SQUASH) * 2, 3) + Fx.div_trunc(b.s32(B_SPEED) >> 6, 3)
			b.put16(B_SQUASH, sq)
		elif b.u8(B_SQUASHING) == 0:
			relax = false
	if relax:
		s = b.s16(B_SQUASH)
		b.put16(B_SQUASH, b.u16(B_SQUASH) - ((s + 0x10) >> 4))
	var st := state()
	var kind := 0
	if st == 6:
		kind = 1
	elif st == 1 or st == 8:
		b.put8(B_KIND, 0)
		return
	elif st == 7:
		kind = 2
	else:
		var charge := b.s16(B_CHARGE)
		if charge == 0:
			if b.u8(B_LOCK) != 0:
				kind = 5
			else:
				b.put8(B_KIND, 4 if st == 3 else 3)
				return
		else:
			var who := FighterState.index_at(b.u32(B_OWNER))
			b.put8(B_TIMER, who)
			if charge < 100:
				if b.u8(B_LOCK) == 5:
					glow(who, 0)
				b.put8(B_KIND, 7 if b.u8(B_TIMER) != 0 else 6)
			else:
				if b.u8(B_LOCK) == 5:
					glow(who, 1)
				b.put8(B_KIND, 9)
			if b.u8(B_LOCK) == 0:
				return
			kind = 8 if b.u8(B_REHIT) != 0 else 5
	b.put8(B_KIND, kind)


## FUN_800B4720: once per player and size, effect type 15 (the charged ball's glow).
func glow(player: int, big: int) -> void:
	var u := player + 2 * big
	var bit := 1 << (u & 0x1F)
	if v.u8(GLOWS - BASE) & bit:
		return
	var o := EffectObjects.alloc(fight, 15)
	if o == null:
		return
	o.a = u & 1
	o.d = (u & 0xFF) >> 1
	v.put8(GLOWS - BASE, v.u8(GLOWS - BASE) | bit)


# ==== what the drawing does to the state (FUN_800B3198) ==========================================

var streaks := PackedInt32Array([0, 0, 0, 0])   ## kind 2: each streak's x jitter (screen units from the ball)


## The ball's drawing (kind 2, a point) spends rand() on its streaks' jitter while the fight runs,
## and at the point's strength 5 spawns 16 sparks (FUN_800B47B4) around the ball. The drawing
## itself is the presentation's.
func _draw_effects() -> void:
	if b.u8(B_KIND) != 2 or fight.paused_player != 0:
		return
	if b.u8(B_TIMER) == 5:
		_sparks(b.s32(B_POS + 4) < FLOOR_Y)
	for i in 4:
		streaks[i] = (fight.rng.next() >> 4) - 0x400


## FUN_800B47B4: 16 sparks (effect type 1) within ±255 of the ball; above the floor they fly out
## with a random side, on it they take the ball's velocity halfwords.
func _sparks(high: bool) -> void:
	for n in 16:
		var r1 := fight.rng.next()
		var u := ((r1 << 16) + fight.rng.next()) & 0xFFFFFFFF
		var o := EffectObjects.alloc(fight, 1)
		if o == null:
			return
		o.x = Fx.w32(b.s32(B_POS) - 0xFF + (u >> 23))
		o.y = Fx.w32(b.s32(B_POS + 4) - 0xFF + ((Fx.w32(u) >> 14) & 0x1FF))
		o.z = Fx.w32(b.s32(B_POS + 8) - 0xFF + ((Fx.w32(u) >> 5) & 0x1FF))
		if not high:
			o.pitch = 0x400
			o.yaw = Fx.s16((fight.rng.next() - 0x800) & 0x100)
		else:
			o.pitch = Fx.s16(b.u16(B_VEL))
			o.yaw = Fx.s16(b.u16(B_VEL + 4))


# ==== gauges and popups ==============================================================================

## FUN_800B4E6C's state: the fill moves 3 pixels per frame towards power · 76 / maximum; a lighter
## trail follows a drop by a sixteenth of the gap per frame. (The drawing is the presentation's.)
func _gauges(p1: int, maximum: int, p2: int, highlight: int) -> void:
	for g in 2:
		var r := GAUGES + 0x10 * g
		var power := (p1 if g == 0 else p2) & 0xFFFFFFFF
		var target := _v16(r + 4)
		var fill := _v16(r + 6)
		var trail := _v16(r + 8)
		if v.u32(r - BASE) != power:
			_vput32(r, power)
			target = Fx.div_trunc(Fx.w32(Fx.w32(power) * 76), maximum)
		target = mini(target, 0x4C)
		trail = trail - ((trail - fill + 15) >> 4) if fill < trail else fill
		fill = mini(fill + 3, target) if fill < target else target
		if trail < fill:
			trail = fill
		_vput16(r + 4, target)
		_vput16(r + 6, fill)
		_vput16(r + 8, trail)
	gauge_highlight = highlight


var gauge_highlight := 0               ## the gauge that pulses (1 << player): the charging player's


## A gauge's state for the presentation: fill, trail (pixels of 76), grows rightwards, x, y.
func gauge(g: int) -> PackedInt32Array:
	var r := GAUGES + 0x10 * g
	return PackedInt32Array([_v16(r + 6), _v16(r + 8), _vu16(r + 0xA), _vu16(r + 0xC), _vu16(r + 0xE)])


## FUN_800B445C: a popup text over the ball in the next of eight slots (skipped while that slot
## is still showing), at the head of the list.
func _popup_add(text: String, colour: int, font: int, frames: int) -> void:
	var i := _v32(POPUP_NEXT) + 1
	i -= ((i + 7 if i < 0 else i) >> 3) << 3
	_vput32(POPUP_NEXT, i)
	var node := POPUP_SLOTS + 0x20 * i
	if v.u8(node + 0x1F - BASE) != 0:
		return
	v.put8(node + 0x1C - BASE, colour)
	v.put8(node + 0x1D - BASE, font)
	v.put8(node + 0x1E - BASE, frames)
	v.put8(node + 0x1F - BASE, 1)
	var p := BallPopup.new()
	p.text = text
	p.colour = colour
	p.font = font
	p.frames = frames
	p.point = position()
	p.view = view
	popups.push_front(p)
	_slots.insert(0, i)


var view: ViewMatrix                   ## the frame's camera (set by the simulation before the hook)
var _slots := PackedInt32Array()       ## the slot of each popup


## FUN_800B4350's state: each popup rises a pixel per frame and leaves when its frames run out;
## while the fight is frozen they only show.
func _popups_step(frozen: bool) -> void:
	var i := 0
	while i < popups.size():
		var p := popups[i]
		var node := POPUP_SLOTS + 0x20 * _slots[i]
		if not frozen and p.frames == 0:
			v.put8(node + 0x1F - BASE, 0)
			popups.remove_at(i)
			_slots.remove_at(i)
			continue
		if not frozen:
			p.rise += 1
			p.frames -= 1
			v.put8(node + 0x1E - BASE, p.frames)
		i += 1


# ==== helpers ========================================================================================

func _sound(code: int, events: SimEvents) -> void:
	events.add(SimEvents.Kind.SOUND, 0, code, 0)


## C division with the R3000's quotient for a zero divisor.
static func _div(a: int, d: int) -> int:
	a = Fx.w32(a)
	d = Fx.w32(d)
	if d == 0:
		return -1 if a >= 0 else 1
	return Fx.div_trunc(a, d)


## FUN_8004B634: the angle of (x, z) in 4096 units.
func _atan2(x: int, z: int) -> int:
	return CameraMath.atan2_units4096(x, z, t.camera) & 0xFFFF
