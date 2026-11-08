class_name ArcadeReplay
extends ReplayState
## The arcade's replay (FUN_8019541C and its hooks) records the same frames without the anchor, starts
## from the KO mark alone, and at least 150 frames back whatever was recorded.
##

const SLOTS := 10                   ## a fight of the ladder each
const NO_STAGE := 0x17
const PLAYING_KEPT := 6             ## 0x8021F640 while the staff roll plays a kept fight
const KEPT_CAMERA_PLAY := 2         ## the half frame of a kept fight that starts its camera
const POSE_ONLY := 8                ## FUN_801956D4: neither recording nor playing
const LEVEL_FIELD := 2              ## ReplayState._byte's field of the frame's last byte
const LEVEL_READ_MODES: Array[int] = [FIRST_FRAME, PLAYING, PLAYING_KEPT, ENDING]
const FLIPBOOK_ENTRIES := 40
const FLIPBOOK_LIMIT := 0x29
const DUST_ENTRIES := 20
const DUST_LIMIT := 0x15

## A kept fight's last 300 frames, oldest first (0x80220FE0, 0x8022100C, 0x80221038, 0x8024AACC…).
class Kept:
	var stage := NO_STAGE
	var count := 0                  ## the frames kept − 1
	var chars := PackedInt32Array([0, 0])
	var costumes := PackedInt32Array([0, 0])
	var frames: Array[Array] = [[], []]
	var sounds := PackedInt32Array()
	var flipbook_log: EffectLog
	var dust_log: EffectLog

var dust_log := EffectLog.new(DUST_ENTRIES, DUST_LIMIT)  ## `effect_log` holds the flipbooks
var stored := 0                     ## 0x8021F64C: this fight's KO was kept
var kept: Array[Kept] = []
var kept_running := 0               ## 0x8021F664: FUN_801956C8 is its absence
var _live_frames: Array[Array]
var _live_sounds: PackedInt32Array


func _init() -> void:
	super()
	effect_log = EffectLog.new(FLIPBOOK_ENTRIES, FLIPBOOK_LIMIT)
	_live_frames = frames
	_live_sounds = sounds
	clear_kept()


## FUN_80194EFC(0).
func clear_kept() -> void:
	kept.clear()
	for i in SLOTS:
		kept.append(Kept.new())


## FUN_80194EFC(2) as well as the common reset: what follows records into the live ring again.
func reset() -> void:
	super()
	frames = _live_frames
	sounds = _live_sounds


## FUN_80195178: when the round is over a round of a joined player's, ahead on health, is kept.
func store_round(fight: FightState) -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var keeps := (f1.health <= f0.health and fight.human_mask & 1 != 0) or (f0.health <= f1.health and fight.human_mask & 2 != 0)
	if not keeps:
		return
	if mark < 0:
		if stored != 0:
			return
	else:
		stored = 1
	var slot := fight.region.fight_index
	recorded = mini(recorded, FRAMES)
	if slot < SLOTS:
		_keep(kept[slot], fight)


func _keep(out: Kept, fight: FightState) -> void:
	out.stage = fight.stage
	out.count = recorded - 1
	var first := record if recorded >= FRAMES else 0
	out.sounds = PackedInt32Array()
	out.sounds.resize(FRAMES)
	for p in 2:
		var f := fight.fighters[p]
		out.chars[p] = f.char_id
		out.costumes[p] = f.costume_key & 3
		var copied: Array = []
		copied.resize(FRAMES)
		for i in FRAMES:
			var source: Frame = frames[p][(first + i) % FRAMES]
			copied[i] = source.copy()
		out.frames[p] = copied
	for i in FRAMES:
		out.sounds[i] = sounds[(first + i) % FRAMES]
	out.flipbook_log = effect_log.kept()
	out.dust_log = dust_log.kept()


## The end of FUN_801969C8, after the round's start: plays the kept fight at full speed. The round
## start has reset the frame being recorded, so the replay always runs to the 299th frame, whatever
## was kept (the frames past those are the ring's earlier contents).
func play_kept(slot: int) -> void:
	frames = kept[slot].frames
	sounds = kept[slot].sounds
	mode = PLAYING_KEPT
	kept_running = 1


## FUN_801ADF88, FUN_801AE888, before the round's start (which empties only the logs' first slot): the
## logs of a kept fight, aligned with its last frame, so they start two frames after the poses do.
func restore_logs(slot: int) -> void:
	var fight_kept := kept[slot]
	var first := FRAMES - 1 - (fight_kept.count - 2)
	effect_log.restore(fight_kept.flipbook_log, first)
	dust_log.restore(fight_kept.dust_log, first)


func log_reset() -> void:
	super()
	dust_log.reset()


func log_effect(set: int, index: int, point: PackedInt32Array, direction: PackedInt32Array, log_mode: int) -> void:
	if log_mode == EffectLog.DUST:
		dust_log.add(set, index, point, direction, log_mode)
	else:
		super(set, index, point, direction, log_mode)


func log_advance() -> void:
	super()
	dust_log.advance()


## FUN_801AE6B4 before FUN_801ADD18: the dust rings first.
func log_take() -> Array[EffectLog.Entry]:
	var out := dust_log.take()
	out.append_array(super())
	return out


func log_rewind(back: int) -> void:
	super(back)
	dust_log.rewind(back)


func log_stop() -> void:
	super()
	dust_log.on = 0


## FUN_8019541C with the modes of the staff roll.
func update(fight: FightState, sim: FightSimulation) -> int:
	match mode:
		PLAYING_KEPT:
			play = _half_frame(play + 2)
			if play == _half_frame(record * 2 - 2):
				kept_running = 0
			_play_sounds(fight, sim)
			return mode
		POSE_ONLY:
			return 0
	return super(fight, sim)


## FUN_80194FD4.
func start(fight: FightState, _back: int) -> void:
	log_stop()
	if mark < 0:
		mode = DONE
		mark = _half_frame(record * 2 - 0x140)
		return
	if _ring_frame(record - (_half_frame(mark) >> 1)) < START_BACK:
		mark = (record - START_BACK) * 2
	mark = _half_frame(mark)
	mode = STARTING
	fight.blend_hold = 0x14
	play = mark
	log_rewind(_ring_frame(record - (play >> 1)))


static func _half_frame(v: int) -> int:
	return (v + WRAP if v < 0 else v) % HALF_FRAMES


static func _ring_frame(v: int) -> int:
	return (v + WRAP if v < 0 else v) % FRAMES


## FUN_80196484: True Ogre's level, kept at half its value in the frame's byte that the PlayStation's
## frame gives to the power timer (the arcade's logs none).
func ogre_level(f: FighterState) -> int:
	var level := f.hands.ogre_level
	var kept := _byte(f, Fx.div_trunc(level, 2), LEVEL_FIELD, 0)
	return 2 * kept if mode in LEVEL_READ_MODES else level


## FUN_8019571C's call of FUN_801D6DA8: a kept fight's playback chooses its replay camera on its
## second half frame, after the second fighter's root.
func starts_kept_camera(f: FighterState) -> bool:
	return mode == PLAYING_KEPT and play == KEPT_CAMERA_PLAY and f.index == 1


## FUN_8019571C: only the root, interpolated on the odd half frames.
func root_position(f: FighterState) -> void:
	var p := _side(f)
	match mode:
		FIRST_FRAME, PLAYING, PLAYING_KEPT:
			var a: Frame = frames[p][(play >> 1) % FRAMES]
			var b: Frame = frames[p][((play >> 1) + 1) % FRAMES]
			var root := a.root.duplicate()
			if play & 1:
				for i in 3:
					root[i] = Fx.div_trunc(a.root[i] + b.root[i], 2)
			f.root_x = root[0]
			f.root_y = root[1]
			f.root_z = root[2]
		ENDING:
			var s := saved[p]
			f.root_x = s.root[0]
			f.root_y = s.root[1]
			f.root_z = s.root[2]
		RECORDING:
			frames[p][record].root = PackedInt32Array([f.root_x, f.root_y, f.root_z])
