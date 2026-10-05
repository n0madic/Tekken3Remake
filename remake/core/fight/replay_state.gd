class_name ReplayState
extends RefCounted
## The round-end replay (`ReplayUpdate` 0x800323CC and its hooks): a ring of 300 recorded
## frames per fighter — pose and blend moves and frames, root position and rotation, anchor,
## hand, wing and power-timer values — plus the frame's sounds and the effect log, played back
## at half speed after a KO (the root is interpolated on the odd half frames).
##
## Every hook takes the live value and returns the value to use: while recording it stores the
## value, on the first played frame it also saves the live state (restored when the replay
## ends), while playing it returns the recorded one.

const FRAMES := 300
const HALF_FRAMES := 600
const WRAP := 0x4B00                ## the game adds 0x4B00 before its modulo
const RECORDING := 7
const STARTING := 2
const FIRST_FRAME := 3
const PLAYING := 1
const ENDING := 4
const DONE := 5
const START_BACK := 0x96             ## the playback starts at most 150 frames back
const LAST_FRAMES := 0x12A
const LOG_ENTRIES := 64
const LOG_CYCLE_LIMIT := 0x41
const BALL_BACK := 0x1E              ## Tekken Ball replays the last 30 frames
const BALL_FRAMES := 0x1E            ## the ball's ring (0x7EF8 in the replay buffer)

## One fighter's recorded frame (0x34 bytes in the game).
class Frame:
	var pose_move: MoveRow           ## +0x00
	var blend_src: MoveRow           ## +0x04
	var blend_dst: MoveRow           ## +0x08
	var root := PackedInt32Array([0, 0, 0])     ## +0x0C
	var pos := PackedInt32Array([0, 0, 0])      ## +0x18
	var angles := PackedInt32Array([0, 0, 0])   ## +0x24 root rotation (s16)
	var hands := PackedInt32Array([0, 0])       ## +0x2A vertex variants
	var src_frame := 0               ## +0x2C
	var dst_frame := 0               ## +0x2D
	var pose_frame := 0              ## +0x2E (u8)
	var blend_frames := 0            ## +0x2F (u8)
	var wings := 0                   ## +0x30
	var power := 0                   ## +0x31
	var blend_bits := 0              ## +0x33: blend mode << 4 | blend active & 0xF

## One effect log entry (0x1C bytes): a flipbook (mode 0) or a landing dust ring (mode 1).
class LogEntry:
	var point := PackedInt32Array([0, 0, 0])
	var direction := PackedInt32Array([0, 0, 0])   ## s16 direction (or damage in the third)
	var mode := 0
	var set := 0
	var index := 0

var stage := 0x17                   ## 0x8009C040 (ReplayInit(0) sets 0x17)
var mode := RECORDING               ## 0x8009C050
var bank := 0                       ## 0x8009C054
var record := 0                     ## 0x8009C060: the frame being recorded
var play := 0                       ## 0x8009C064: the half frame being played
var mark := -2                      ## 0x8009C068: where the playback starts (half frames)
var sound_delay := 0                ## 0x8009C06C
var skip := 0                       ## 0x8009C070
var recorded := 0                   ## 0x8009C078: frames recorded this round
var sounds := PackedInt32Array()    ## per frame: code | kind << 16 | player << 24
var frames: Array[Array] = [[], []] ## per fighter: FRAMES × Frame
var saved: Array[Frame] = [Frame.new(), Frame.new()]   ## the live state (0x79E0)
# The effect log (0x8009EBD8 …).
var log_on := 0
var log_frame := 0                  ## the frame slot being written
var log_read := 0                   ## the frame slot being played
var log_cycle := 0                  ## entries written since the frame ring last wrapped
var log_write := 0                  ## the next entry
var log_frames := PackedInt32Array()      ## per frame slot: first entry | count << 16
var log_entries: Array[LogEntry] = []
var balls: Array[PackedByteArray] = []   ## Tekken Ball: per frame of the ball's ring, 0x24 bytes


func _init() -> void:
	sounds.resize(FRAMES)
	log_frames.resize(FRAMES)
	for p in 2:
		for i in FRAMES:
			frames[p].append(Frame.new())
	for i in LOG_ENTRIES:
		log_entries.append(LogEntry.new())
	for i in BALL_FRAMES:
		var r := PackedByteArray()
		r.resize(0x24)
		balls.append(r)


## ReplayInit(0) at a mode start: the replay's stage word; started from the attract
## demonstration (game state 6) the replay mode is 0.
func init_attract(from_demonstration: bool) -> void:
	stage = 0x17
	if from_demonstration:
		mode = 0


## ReplayInit(2) at a round start.
func reset() -> void:
	mode = RECORDING
	record = 0
	play = 0
	mark = -2
	sound_delay = 0
	bank = 0
	skip = 0
	recorded = 0


## FUN_8004A6A4 (FUN_800777AC at a round start): the effect log starts empty.
func log_reset() -> void:
	log_on = 1
	log_frame = 0
	log_cycle = 0
	log_write = 0
	log_frames[0] = 0


## FUN_8004A700: logs an effect (mode 0: a flipbook of `set` and `index`; mode 1: a dust ring).
## At most 64 entries per cycle of the frame ring; the entries themselves are a ring of 64.
func log_effect(set: int, index: int, point: PackedInt32Array, direction: PackedInt32Array, log_mode: int) -> void:
	if log_on == 0:
		return
	log_cycle += 1
	if log_cycle >= LOG_CYCLE_LIMIT:
		return
	log_frames[log_frame] += 1 << 16
	var e := log_entries[log_write]
	e.mode = log_mode
	if log_mode == 0:
		e.point = point.duplicate()
		e.direction = direction.duplicate()
		e.set = set
		e.index = index
	elif log_mode == 1:
		e.point = point.duplicate()
	log_write = (log_write + 1) % LOG_ENTRIES


## FUN_8004A8AC: the effect log's next frame slot.
func log_advance() -> void:
	if log_on == 0:
		return
	log_frame += 1
	if log_frame >= FRAMES:
		log_frame = 0
		log_cycle = 0
	log_frames[log_frame] = log_write


## FUN_8004A954's read side: the entries of the frame slot being played, then the next slot.
func log_take() -> Array[LogEntry]:
	var out: Array[LogEntry] = []
	var slot := log_frames[log_read]
	var at := slot & 0xFFFF
	for k in (slot >> 16) & 0xFFFF:
		out.append(log_entries[(at + k) % LOG_ENTRIES])
	log_read = (log_read + 1) % FRAMES
	return out


## ReplayRecordSound (0x80033780): while recording, a sound goes to the frame slot `record +
## sound_delay` (several sounds of one frame spread over the following slots).
func record_sound(kind: int, player: int, code: int) -> void:
	if mode != RECORDING:
		return
	var at := record + sound_delay
	if at < 0:
		at += WRAP
	sound_delay += 1
	sounds[at % FRAMES] = (code & 0xFFFF) | (kind & 0xFF) << 16 | (player & 0xFF) << 24


## FUN_80032030 at the first KO: the playback starts 30 frames before the move of the
## opponent (`opp`, the fighter that landed the KO) began.
func start_ko(opp: FighterState) -> void:
	mark = ((record - opp.pose_frame) - 0x1E) * 2
	if mark < 0:
		mark += WRAP
	mark %= HALF_FRAMES


## ReplayStart (0x8003209C) with `back` frames (0: from the KO mark). Without a mark (a time
## out) there is nothing to play.
func start(fight: FightState, back: int) -> void:
	if recorded < back:
		back = recorded - 2
	if back == 0 and mark < 0:
		mode = DONE
		mark = record * 2 - 0x140
		if mark < 0:
			mark = record * 2 + 0x49C0
		mark %= HALF_FRAMES
		log_on = 0
		return
	if back > LAST_FRAMES:
		back = LAST_FRAMES
	if back != 0:
		var from := record - back
		if from < 0:
			from += WRAP
		mark = (from % FRAMES) * 2
	var age := record - (mark >> 1)
	if age < 0:
		age += WRAP
	if age % FRAMES < START_BACK and recorded > START_BACK + 2:
		mark = (record - START_BACK) * 2
	if fight.mode == GameMode.BALL:
		mark = (record - BALL_BACK) * 2
	if mark < 0:
		mark += WRAP
	mode = STARTING
	fight.blend_hold = 0x14
	play = mark % HALF_FRAMES
	var first := record - (play >> 1)
	if first < 0:
		first += WRAP
	mark = play
	# FUN_8004A91C: the effect log is played from the same frame.
	log_read = log_frame - first % FRAMES
	if log_read < 0:
		log_read += FRAMES
	log_on = 0


## ReplayUpdate (0x800323CC): the recording and playback step of the frame; non-zero while the
## replay plays (the replay's first frame, STARTING, swaps the roots and sets the camera).
func update(fight: FightState, sim: FightSimulation) -> int:
	var last := record * 2 - 2
	var shown := fight.region.ctx_s32(TekkenBall.LAST_POINT)
	var shows := fight.region.ctx_s32(TekkenBall.RESULT)
	if fight.mode == GameMode.BALL:
		# Tekken Ball: the sixth replay of a lethal iron ball ends 16 frames earlier.
		if shown == 3 and shows > 3:
			last = record * 2 - 0x20
		if last < 0:
			last += HALF_FRAMES
	elif last < 0:
		last = 0x256
	match mode:
		PLAYING:
			if fight.frame_counter & 0x10:
				sim.events.add(SimEvents.Kind.REPLAY_TEXT, -1)
			# Tekken Ball's replays run at full speed but the last.
			play += 2 if fight.mode == GameMode.BALL and shown < shows else 1
			if play < 0:
				play += WRAP
			play %= HALF_FRAMES
			if play == last or skip != 0:
				mode = ENDING
			_play_sounds(fight, sim)
			return mode
		STARTING:
			mode = FIRST_FRAME
			for p in 2:
				var f := fight.fighters[p]
				var r: Frame = frames[p][(play >> 1) % FRAMES]
				saved[p].root = PackedInt32Array([f.root_x, f.root_y, f.root_z])
				f.root_x = r.root[0]
				f.root_y = r.root[1]
				f.root_z = r.root[2]
			sim.camera.replay_start(fight.fighters[0], fight.fighters[1])
			for f in fight.active():
				sim.hands_rest(f)
			return mode
		FIRST_FRAME:
			mode = PLAYING
			skip = 0
			return mode
		ENDING:
			mode = DONE
			fight.blend_hold = 0x14
			for f in fight.active():
				f.blend_frames = 0
				f.blend_counter = 0
				f.blend_weight = 0
				f.blend_root_delta = PackedInt32Array([0, 0, 0])
			return 0
		RECORDING:
			if recorded < 0x70000000:
				recorded += 1
			record = (record + 1) % FRAMES
			if sound_delay > 0:
				sound_delay -= 1
			var at := record + sound_delay
			if at < 0:
				at += WRAP
			sounds[at % FRAMES] &= ~(0xFF << 16)
			return 0
	return 0


## FUN_800338E0: on the even half frames, the recorded sounds of the frame.
func _play_sounds(fight: FightState, sim: FightSimulation) -> void:
	if play & 1:
		return
	var s := sounds[(play >> 1) % FRAMES]
	var code := Fx.s16(s & 0xFFFF)
	var player := (s >> 24) & 0xFF
	match (s >> 16) & 0xFF:
		1:
			sim.events.add(SimEvents.Kind.SYSTEM_SOUND, -1, code & 0xFFF)
		2:
			var f := fight.fighters[player]
			FighterSounds.replay_voice(fight, player, f.voice_set, code, sim.events)
		3:
			FighterSounds.replay_sound(fight, player, code, sim.events)


# ==== hooks =======================================================================================

## The replay buffer of a record: player 1's for every record but the first (the game compares
## with 0x800A96F0), so Tekken Force's third record shares the second's.
static func _side(f: FighterState) -> int:
	return 0 if f.index == 0 else 1


func _playing() -> bool:
	return mode == FIRST_FRAME or mode == PLAYING or mode == 6


func _frame_of(p: int) -> Frame:
	return frames[p][(play >> 1) % FRAMES]


## ReplayRecordPose (0x80032DE8, after the transition blend) and ReplayPlayPose (0x80032EC8,
## at the start of FighterAnimate).
func record_pose(f: FighterState) -> void:
	if mode != RECORDING:
		return
	var r: Frame = frames[_side(f)][record]
	_store_pose(r, f)


func play_pose(f: FighterState) -> void:
	var p := _side(f)
	if mode == FIRST_FRAME:
		_store_pose(saved[p], f)
	var r: Frame
	if mode == ENDING:
		r = saved[p]
	elif _playing():
		r = _frame_of(p)
	else:
		return
	f.root_move = r.pose_move
	f.pose_move = r.pose_move
	f.blend_src_move = r.blend_src
	f.blend_dst_move = r.blend_dst
	f.blend_src_frame = r.src_frame
	f.blend_dst_frame = r.dst_frame
	f.pose_frame = r.pose_frame
	f.blend_frames = r.blend_frames
	f.blend_mode = r.blend_bits >> 4
	f.blend_active = r.blend_bits & 0xF


func _store_pose(r: Frame, f: FighterState) -> void:
	r.pose_move = f.pose_move
	r.blend_src = f.blend_src_move
	r.blend_dst = f.blend_dst_move
	r.src_frame = f.blend_src_frame & 0xFF
	r.dst_frame = f.blend_dst_frame & 0xFF
	r.pose_frame = f.pose_frame & 0xFF
	r.blend_frames = f.blend_frames & 0xFF
	r.blend_bits = ((f.blend_mode << 4) + (f.blend_active & 0xF)) & 0xFF


## ReplayRootRotation (0x80032C0C): the root rotation angles (−tilt x, heading − 0x8000, −tilt z).
func root_rotation(f: FighterState, angles: PackedInt32Array) -> PackedInt32Array:
	var p := _side(f)
	match mode:
		FIRST_FRAME, PLAYING, 6:
			if mode == FIRST_FRAME:
				saved[p].angles = angles.duplicate()
			return _frame_of(p).angles.duplicate()
		ENDING:
			return saved[p].angles.duplicate()
		RECORDING:
			frames[p][record].angles = angles.duplicate()
	return angles


## ReplayRootPosition (0x80032838): the root (interpolated on odd half frames) and the anchor.
func root_position(f: FighterState) -> void:
	var p := _side(f)
	match mode:
		FIRST_FRAME, PLAYING, 6:
			if mode == FIRST_FRAME:
				saved[p].pos = PackedInt32Array([f.pos_x, f.pos_y, f.pos_z])
			var a: Frame = frames[p][(play >> 1) % FRAMES]
			var b: Frame = frames[p][((play >> 1) + 1) % FRAMES]
			var root := a.root.duplicate()
			if play & 1:
				for i in 3:
					root[i] = Fx.div_trunc(a.root[i] + b.root[i], 2)
			f.root_x = root[0]
			f.root_y = root[1]
			f.root_z = root[2]
			f.pos_x = a.pos[0]
			f.pos_y = a.pos[1]
			f.pos_z = a.pos[2]
		ENDING:
			var s := saved[p]
			f.root_x = s.root[0]
			f.root_y = s.root[1]
			f.root_z = s.root[2]
			f.pos_x = s.pos[0]
			f.pos_y = s.pos[1]
			f.pos_z = s.pos[2]
		RECORDING:
			var r: Frame = frames[p][record]
			r.root = PackedInt32Array([f.root_x, f.root_y, f.root_z])
			r.pos = PackedInt32Array([f.pos_x, f.pos_y, f.pos_z])


## ReplayHandPose (0x800332D8), FUN_80033158 (the wings) and ReplayPowerTimer (0x80033600):
## one byte each.
func hand_pose(f: FighterState, value: int, channel: int) -> int:
	return _byte(f, value, 0, channel)


func wings(f: FighterState, value: int) -> int:
	return _byte(f, value, 1, 0)


func power_timer(f: FighterState) -> int:
	return _byte(f, f.power_timer, 2, 0)


func _byte(f: FighterState, value: int, field: int, index: int) -> int:
	var p := _side(f)
	match mode:
		FIRST_FRAME, PLAYING, 6:
			if mode == FIRST_FRAME:
				_set_byte(saved[p], field, index, value)
			return _get_byte(_frame_of(p), field, index)
		ENDING:
			return _get_byte(saved[p], field, index)
		RECORDING:
			var r: Frame = frames[p][record]
			_set_byte(r, field, index, value)
	return value


static func _set_byte(r: Frame, field: int, index: int, value: int) -> void:
	match field:
		0:
			r.hands[index] = value & 0xFF
		1:
			r.wings = value & 0xFF
		2:
			r.power = value & 0xFF


static func _get_byte(r: Frame, field: int, index: int) -> int:
	match field:
		0:
			return r.hands[index]
		1:
			return r.wings
	return r.power


## FUN_800339F4: Tekken Ball's ball in the replay: recorded while the replay records (its
## position, angles, squash axis and amount, render kind and timer), played back while it plays;
## a charged ball played back starts its glow again.
func ball(tb: TekkenBall) -> void:
	var b := tb.b
	if mode == RECORDING:
		var r := balls[record % BALL_FRAMES]
		for k in 4:
			r.encode_u32(4 * k, b.u32(TekkenBall.B_POS + 4 * k))
		r.encode_u32(0x10, b.u32(TekkenBall.B_ANGLES))
		for k in 8:
			r.encode_u8(0x1A + k, b.u8(TekkenBall.B_SQUASH_AXIS + k))
		r.encode_u8(0x18, b.u8(TekkenBall.B_KIND))
		r.encode_u8(0x19, b.u8(TekkenBall.B_TIMER))
		r.encode_u16(0x22, b.u16(TekkenBall.B_SQUASH))
	elif mode == PLAYING or mode == FIRST_FRAME:
		var r := balls[(play >> 1) % BALL_FRAMES]
		for k in 4:
			b.put32(TekkenBall.B_POS + 4 * k, r.decode_u32(4 * k))
		b.put32(TekkenBall.B_ANGLES, r.decode_u32(0x10))
		for k in 8:
			b.put8(TekkenBall.B_SQUASH_AXIS + k, r.decode_u8(0x1A + k))
		b.put8(TekkenBall.B_KIND, r.decode_u8(0x18))
		b.put8(TekkenBall.B_TIMER, r.decode_u8(0x19))
		b.put16(TekkenBall.B_SQUASH, r.decode_u16(0x22))
		match r.decode_u8(0x18):
			6:
				tb.glow(0, 0)
			7:
				tb.glow(1, 0)
			9:
				tb.glow(0, 1)
