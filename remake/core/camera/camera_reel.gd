class_name CameraReel
extends RefCounted
## A reel of camera streams played back to back (`FUN_800673E4` / `FUN_80066D00`,
## camera.md#camera-streams-bank-section-8): the attract demonstration plays the streams of
## its bank's camera ids 0x2B, 0x2D, …
##
## Each step turns the current stream sample into the camera source and takes the next
## sample, so the reel is one continuous sequence of samples. Reel samples are halved (toward
## zero) and authored for the projection distance 450; the eye is moved along the view line
## so that the same framing holds at the actual projection distance.
##
## The Ogre scene's reel (kind 2, one stream, then the director) is CameraDirector.ogre_start.

const STREAM_H := 0x1C2            ## the projection distance the reel was authored for

var bank: MotionBank
var streams: PackedInt32Array      ## section-8 offsets, in order
var tables: CameraTables
var stream := 0                    ## index of the playing stream
var next_frame := 0                ## its next sample
var sample := PackedInt32Array()   ## the sample the next step uses
var sample_starts_stream := false  ## `sample` is the first of its stream (a cut)
var chooses := 0                   ## CameraChoose calls so far (each draws a random number)


func _init(motion_bank: MotionBank, offsets: PackedInt32Array, camera_tables: CameraTables) -> void:
	bank = motion_bank
	streams = offsets
	tables = camera_tables


## Starts the reel from its first stream (FUN_800673E4(1)).
func start() -> void:
	chooses += 1
	stream = 0
	next_frame = 0
	sample = _take()


## True once every stream has been played; the game would then read past the reel.
func finished() -> bool:
	return stream >= streams.size()


## One reel step: the camera of the current sample for projection distance `h`.
func step(h: int) -> CameraView:
	var view := view_of(sample, h)
	view.cut = sample_starts_stream
	sample = _take()
	return view


func _take() -> PackedInt32Array:
	while stream < streams.size() and next_frame >= bank.camera_frames(streams[stream]):
		stream += 1
		chooses += 1
		next_frame = 0
	if finished():
		sample_starts_stream = false
		return sample
	sample_starts_stream = next_frame == 0
	var s := bank.camera_sample(streams[stream], next_frame)
	next_frame += 1
	return s


## FUN_80066D00 → FUN_800641D4 → CameraUseSource: the view of one halved reel sample.
func view_of(s: PackedInt32Array, h: int) -> CameraView:
	var rec := source_of(s, h, tables)
	return CameraView.new(CameraMath.sar6(rec[3]), CameraMath.sar6(rec[4]), rec[0], rec[1], rec[2], h)


## FUN_80066D00 → FUN_800641D4: the camera source (x, y, z, pitch and yaw in 18-bit units, H) of
## one halved reel sample for projection distance `h` (a reel has no origin, yaw or mirroring).
static func source_of(s: PackedInt32Array, h: int, camera_tables: CameraTables) -> PackedInt32Array:
	var e := PackedInt32Array([_half(s[0]), _half(s[1]), _half(s[2])])
	var t := PackedInt32Array([_half(s[3]), _half(s[4]), _half(s[5])])
	var eye := PackedInt32Array()
	eye.resize(3)
	for k in 3:
		eye[k] = Fx.s16(t[k] + Fx.s16(Fx.div_trunc(Fx.w32((e[k] - t[k]) * h), STREAM_H)))
	var dx := t[0] - eye[0]
	var dz := t[2] - eye[2]
	var flat := CameraMath.isqrt(Fx.w32(Fx.w32(dx * dx) + Fx.w32(dz * dz)))
	var pitch := Fx.s16(CameraMath.atan2_units4096(flat, t[1] - eye[1], camera_tables)) << 6
	var yaw := Fx.s16(CameraMath.atan2_units4096(dz, -dx, camera_tables)) << 6
	return PackedInt32Array([eye[0], eye[1], eye[2], pitch, yaw, h])


## `(v − (v >> 31)) >> 1` on a 16-bit sample: halving toward zero.
static func _half(v: int) -> int:
	return Fx.s16(Fx.div_trunc(v, 2))
