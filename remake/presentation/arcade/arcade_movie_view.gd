class_name ArcadeMovieView
extends Control
## The attract movie (tools/remake_import/arcade_movie.py): the frame the flow's timer names, over
## the title view's black. FUN_801BE1C0 stretches the 320 × 240 picture over five quads 104 pixels
## wide and 480 lines tall, so its right side passes the 512-wide screen, and covers the last two
## columns and lines with black.
##
## An Ogg Theora movie cannot seek, so its player runs at the speed that brings it to the frame by
## the next render and stays there while the flow waits. The fallback (`frames`, a MovieFile) has
## every frame at hand.

const MOVIES_FILE := "movies/movies.json"
const ENTRY := "attract"
const PICTURE_SIZE := Vector2(520.0, 480.0)
const SHOWN_SIZE := Vector2(510.0, 478.0)
const FRAME_MIDDLE := 0.5               ## where the player aims inside a frame's time
const MAX_SPEED := 64.0
const SHORTEST_DELTA := 0.001

var fps := 0
var frames := 0
var movie: MovieFile
var video := VideoStreamPlayer.new()
var still := TextureRect.new()
var frame := 0                          ## the frame shown
var playing := false
var _stream: VideoStream
var _still_frame := -1
var _clip := Control.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	video.bus = &"Music"
	video.expand = true
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(video)
	still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	still.stretch_mode = TextureRect.STRETCH_SCALE
	still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(still)


## The movie's entry in the converted files; without it, nothing shows.
func load_entry() -> void:
	var path := Assets.path(MOVIES_FILE)
	if not FileAccess.file_exists(path):
		return
	var table: Dictionary = JsonFile.read(path)
	var entries: Array = table.get(ENTRY, [])
	if entries.is_empty():
		return
	var entry: Dictionary = entries[0]
	fps = JsonFile.number(entry["fps"])
	frames = JsonFile.number(entry["frame_count"])
	var folder := Assets.path(MOVIES_FILE).get_base_dir()
	if entry.has("video"):
		var variants: Array = entry["video"]
		_stream = MoviePlayer._first_video(folder, variants)
	elif entry.has("frames"):
		movie = MovieFile.open(folder.path_join(str(entry["frames"])))
	if not available():
		Log.warning("ArcadeMovieView: the movie's file cannot be read")


func available() -> bool:
	return _stream != null or movie != null


## Shows a frame, starting the movie if it is not playing yet.
func show_frame(number: int) -> void:
	if not available():
		return
	frame = mini(number, frames - 1)
	if not playing:
		_start()
	if movie != null:
		_show_still()


## Back to nothing (the flow left the movie, or the view is hidden).
func stop() -> void:
	if not playing:
		return
	playing = false
	visible = false
	video.stop()
	_still_frame = -1


func _start() -> void:
	playing = true
	visible = true
	_place()
	still.visible = movie != null
	video.visible = _stream != null
	if _stream == null:
		return
	video.stream = _stream
	video.speed_scale = 0.0
	video.play()


func _show_still() -> void:
	if frame == _still_frame:
		return
	_still_frame = frame
	var picture := movie.image(frame)
	if picture != null:
		still.texture = ImageTexture.create_from_image(picture)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		stop()


func _process(delta: float) -> void:
	if not playing:
		return
	_place()
	if video.is_playing():
		var wanted := (frame + FRAME_MIDDLE) / float(fps)
		video.speed_scale = clampf((wanted - video.stream_position) / maxf(delta, SHORTEST_DELTA), 0.0, MAX_SPEED)


## The clip is the part of the screen the picture shows on, in the window's 4:3 area.
func _place() -> void:
	var box := ScreenBox.rect(size)
	_clip.position = box.position
	_clip.size = ScreenBox.point(Rect2(Vector2.ZERO, box.size), ArcadeCanvas.LAYOUT, SHOWN_SIZE.x, SHOWN_SIZE.y)
	var picture := ScreenBox.point(Rect2(Vector2.ZERO, box.size), ArcadeCanvas.LAYOUT, PICTURE_SIZE.x, PICTURE_SIZE.y)
	video.size = picture
	still.size = picture
