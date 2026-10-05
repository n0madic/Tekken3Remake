class_name MoviePlayer
extends Control
## Plays a converted movie in the window's 4:3 area (the original display is 256 or 320 pixels
## wide, 240 lines), with a smooth filter. An Ogg Theora movie (`video`: its variants, preferred
## first; a build packs one) plays through a VideoStreamPlayer; the fallback (`frames` +
## `audio`, a MovieFile and a WAV) shows the frame due at the audio position until the entry's
## `duration`. `finished` is emitted at the end, or when `stop()` is called.
## An ending movie (`caption_movie`, its place in the ending list) shows the caption set `captions`
## names for it over the picture by decoded frame: the Theora movie's frame from the entry's
## `frame_slots` (each decoded frame's first slot of the `fps` grid), the fallback's from the frame
## shown.

signal finished

const DISPLAY_LINES := 240.0

var movie: MovieFile
var audio := AudioStreamPlayer.new()
var video := VideoStreamPlayer.new()
var texture: ImageTexture
var shown := -1
var playing := false
var captions: MovieCaptions           ## the language's captions (game.gd), null: none converted
var caption := TextureRect.new()
var _captions: MovieCaptions          ## the captions this movie started with (their set numbering)
var _caption_set := 0
var _caption_shown := -1
var _frame_times := PackedFloat64Array()
var _width := 0.0
var _lines := DISPLAY_LINES
var _duration := 0.0
var _started_at := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio.bus = &"Music"
	add_child(audio)
	video.bus = &"Music"
	video.expand = true
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.visible = false
	video.finished.connect(stop)
	add_child(video)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	caption.stretch_mode = TextureRect.STRETCH_SCALE
	caption.visible = false
	add_child(caption)


## Plays movie `entry` of `movies/movies.json` from `folder` (`caption_movie`: its place in the
## ending list, −1 for a title movie); false when it cannot be played.
func play(folder: String, entry: Dictionary, volume: float, caption_movie := -1) -> bool:
	# Whatever played before stops (both paths: a Theora movie's video, a fallback's sound).
	_reset()
	var lines: float = entry.get("height", DISPLAY_LINES)
	_lines = lines
	_width = JsonFile.number(entry.get("width", 0))
	_captions = captions
	_caption_set = _captions.set_of(caption_movie) if _captions != null else 0
	_frame_times = PackedFloat64Array()
	var fps := JsonFile.number(entry.get("fps", 0))
	for slot: Variant in entry.get("frame_slots", []):
		_frame_times.append(JsonFile.number(slot) / float(fps))
	_show_caption(-1)
	if entry.has("video"):
		var variants: Array = entry["video"]
		var stream := _first_video(folder, variants)
		if stream == null:
			return false
		movie = null
		video.stream = stream
		video.volume_db = linear_to_db(volume)
		video.visible = true
		_start()
		video.play()
		if not video.is_playing():
			_reset()
			return false
		return true
	if not entry.has("frames"):
		return false
	movie = MovieFile.open(folder.path_join(str(entry["frames"])))
	if movie == null or movie.frame_count() == 0 or not entry.has("duration"):
		return false
	_lines = movie.height
	var duration: float = entry["duration"]
	_duration = duration
	var sound := load(folder.path_join(str(entry.get("audio", "")))) as AudioStream if entry.has("audio") else null
	audio.stream = sound
	audio.volume_db = linear_to_db(volume)
	texture = null
	shown = -1
	_start()
	if sound != null:
		audio.play()
	return true


## The first variant present in this build.
static func _first_video(folder: String, variants: Array) -> VideoStream:
	for file: String in variants:
		var path := folder.path_join(file)
		if ResourceLoader.exists(path):
			return load(path) as VideoStream
	return null


func _start() -> void:
	playing = true
	visible = true
	_started_at = Time.get_ticks_msec() / 1000.0
	_place_video()


func stop() -> void:
	if not playing:
		return
	_reset()
	finished.emit()


## Back to idle without a `finished` signal (a movie that did not start).
func _reset() -> void:
	playing = false
	audio.stop()
	video.stop()
	video.visible = false
	visible = false
	_show_caption(-1)


func _process(_delta: float) -> void:
	if not playing:
		return
	if movie == null:
		_place_video()
		_update_caption(_frame_times.bsearch(video.stream_position, false))
		return
	var t := audio.get_playback_position() + AudioServer.get_time_since_last_mix() if audio.playing \
		else Time.get_ticks_msec() / 1000.0 - _started_at
	if t >= _duration:
		stop()
		return
	var i := shown
	while i + 1 < movie.frame_count() and movie.frame_time(i + 1) <= t:
		i += 1
	if i != shown and i >= 0:
		var img := movie.image(i)
		if img != null:
			if texture == null:
				texture = ImageTexture.create_from_image(img)
			else:
				texture.update(img)
		shown = i
		queue_redraw()
	_update_caption(shown + 1)


## The caption of decoded frame `frame` (1 the first) and its place over the picture.
func _update_caption(frame: int) -> void:
	if _caption_set == 0:
		return
	var index := _captions.caption_at(_caption_set, frame)
	if index != _caption_shown:
		_show_caption(index)
	if index < 0 or _width <= 0.0:
		return
	var r := _picture_rect()
	var scale := Vector2(r.size.x / _width, ScreenBox.rect(size).size.y / DISPLAY_LINES)
	var picture := _captions.pictures[index]
	caption.position = r.position + Vector2(_captions.places[index]) * scale
	caption.size = picture.get_size() * scale


func _show_caption(index: int) -> void:
	_caption_shown = index
	caption.texture = _captions.pictures[index] if index >= 0 else null
	caption.visible = index >= 0


## The picture's rectangle: the 4:3 box, a shorter picture centred on its 240 lines.
func _picture_rect() -> Rect2:
	var box := ScreenBox.rect(size)
	var h := box.size.y * minf(_lines / DISPLAY_LINES, 1.0)
	return Rect2(box.position.x, box.position.y + (box.size.y - h) / 2.0, box.size.x, h)


func _place_video() -> void:
	var r := _picture_rect()
	video.position = r.position
	video.size = r.size


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if movie != null and texture != null:
		draw_texture_rect(texture, _picture_rect(), false)
