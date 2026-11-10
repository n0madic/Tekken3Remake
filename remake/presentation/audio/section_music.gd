class_name SectionMusic
extends Node
## The arcade's BGMs as the sound board plays them (tools/remake_import/arcade_sounds.py): a file
## per section (`music/arcade.json`). The game writes the section variable; the sequence's poller
## answers after its delay, and the music jumps at the next of the file's cues (the bars that test
## it), so a section changes at the bar the cabinet would change it. Both builds play it: the
## arcade's (ArcadeAudio) and the PlayStation's with the arcade's music converted (AudioDirector).
##
## TODO: on the board the channels that test the variable itself change section a bar before the
## others; a file per section has them change together (docs/research/arcade/audio-and-effects.md).

const TABLE := "music/arcade.json"
const BOARD_RATE := 120              ## ticks per second
const SECTION_NONE := -1
const SECTION_FIRST := 1             ## the poller waits for 1, then 2, then 3, then for 2 and 3 in turn
const SECTION_LAST := 3
const SECTION_AGAIN := 2
const SECTION_CROSSFADE := 0.03      ## seconds: the two renderings of the same bar overlap this long
const BUS := &"Music"
const FULL_SCALE := 32767.0


class Section:
	var number := 0
	var file := ""
	var loop := -1.0
	var cues := PackedFloat32Array()
	var delay := 0.0


var available := false
var ps_tracks: Dictionary = {}       ## PlayStation track → {sequence, first_section, advance} (a merged conversion's)
var _tracks: Dictionary = {}         ## sequence → Array[Section]
var _peaks: Dictionary = {}          ## sequence → its loudest sample
var _streams: Dictionary = {}        ## file path → AudioStream
## File path → its Section: a background load not taken yet. Every request is taken (into `_streams`):
## the loader keeps one nobody takes until the end, and it leaks at exit.
var _requested: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _at := 0                         ## the player that sounds
var _track: Array[Section] = []
var _current: Section
var _variable := 0                   ## var[0xE0]
var _expected := SECTION_FIRST
var _pending := SECTION_NONE
var _pending_ticks := 0
var _last_position := 0.0
var _gain := 1.0                     ## the owner's volume (linear)
var _mix := 1.0                      ## the crossfade's progress: the new player's share
var _fade: Tween


## The next value the game writes: 1, 2, 3, then 2 and 3 in turn.
static func next_section(section: int) -> int:
	return SECTION_AGAIN if section >= SECTION_LAST else section + 1


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	available = Assets.has_group("music") and FileAccess.file_exists(Assets.path(TABLE))
	if available:
		load_table(JsonFile.read(Assets.path(TABLE)) as Dictionary)


func _exit_tree() -> void:
	for path: String in _requested.keys():
		_take(path)


## `music/arcade.json`: the sections of each sequence, and the PlayStation tracks they stand for.
func load_table(data: Dictionary) -> void:
	_tracks.clear()
	_peaks.clear()
	var tracks: Dictionary = data["tracks"]
	for key: String in tracks:
		_peaks[key.to_int()] = (tracks[key] as Dictionary).get("peak", 0) as int
		var sections: Array[Section] = []
		for row: Dictionary in (tracks[key] as Dictionary)["sections"] as Array:
			var section := Section.new()
			section.number = row["section"] as int
			section.file = row["file"] as String
			section.loop = -1.0 if row["loop"] == null else row["loop"] as float
			section.delay = row["delay"] as float
			for c: float in row["cues"] as Array:
				section.cues.append(c)
			sections.append(section)
		_tracks[key.to_int()] = sections
	ps_tracks = data.get("ps_tracks", {})


func has_sequence(sequence: int) -> bool:
	return _tracks.has(sequence)


## How far a sequence can be raised before its loudest sample clips.
func headroom(sequence: int) -> float:
	var peak := _peaks.get(sequence, 0) as int
	return FULL_SCALE / peak if peak > 0 else 1.0


func sequence_count() -> int:
	return _tracks.size()


func playing() -> bool:
	return _current != null


## Starts a sequence; `section` > 0 starts it in that section, as if the game had written it and
## the sequence had answered (the PlayStation's True Ogre track). Unknown sequences stop the music.
func play(sequence: int, section := 0) -> void:
	# The script clears the section variables as it starts.
	_variable = 0
	_expected = SECTION_FIRST
	_pending = SECTION_NONE
	if not available or not _tracks.has(sequence):
		stop()
		return
	_track.assign(_tracks[sequence] as Array)
	Log.debug("section music: %02x from section %d" % [sequence, section])
	for s in _track:
		if s.number != 0:
			_request(s)
	var first := _section_numbered(section) if section > 0 else null
	if first == null:
		_change_to(_track[0], 0.0, false)
		return
	_variable = section
	_expected = next_section(section)
	_change_to(first, 0.0, false)


func stop() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null
	for p in _players:
		p.stop()
	_current = null
	_track = []
	_variable = 0
	_pending = SECTION_NONE


## The game's write of the section variable.
func write(section: int) -> void:
	_variable = section


## The owner's volume, faded or not.
func set_gain(gain: float) -> void:
	_gain = gain
	_apply_mix()


func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused
	if _fade != null and _fade.is_valid():
		if paused:
			_fade.pause()
		else:
			_fade.play()


## The board's clock: `ticks` more (the poller's delay counts them).
func advance(ticks: int) -> void:
	_collect_requests()
	if _current == null:
		return
	if _pending == SECTION_NONE and _variable == _expected:
		_pending = _expected
		_expected = next_section(_expected)
		var next := _section_numbered(_pending)
		if next == null:
			_pending = SECTION_NONE
		else:
			_pending_ticks = roundi(next.delay * BOARD_RATE)
	if _pending != SECTION_NONE:
		_pending_ticks -= ticks
	var position := _players[_at].get_playback_position()
	if _pending != SECTION_NONE and _pending_ticks <= 0:
		var cue := _crossed_cue(_last_position, position)
		if cue >= 0.0:
			_change_to(_section_numbered(_pending), maxf(position - cue, 0.0), true)
			_pending = SECTION_NONE
			return
	_last_position = position


## The later sections load in the background while the first plays.
func _request(section: Section) -> void:
	var path := Assets.path("music/" + section.file)
	if _streams.has(path) or _requested.has(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_requested[path] = section


func _music_stream(section: Section) -> AudioStream:
	var path := Assets.path("music/" + section.file)
	if _requested.has(path):
		_take(path)
	if not _streams.has(path):
		_cache(path, load(path) as AudioStream, section)
	return _streams[path] as AudioStream


## A requested load, waiting for it if need be.
func _take(path: String) -> void:
	var section := _requested[path] as Section
	_requested.erase(path)
	_cache(path, ResourceLoader.load_threaded_get(path) as AudioStream, section)


## Takes the requested loads that have finished.
func _collect_requests() -> void:
	if _requested.is_empty():
		return
	for path: String in _requested.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_take(path)


func _cache(path: String, stream: AudioStream, section: Section) -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = section.loop >= 0.0
		ogg.loop_offset = maxf(section.loop, 0.0)
	_streams[path] = stream


func _change_to(section: Section, from: float, crossfade: bool) -> void:
	var stream := _music_stream(section)
	var old := _players[_at]
	_at = 1 - _at
	var new := _players[_at]
	if _fade != null:
		_fade.kill()
		_fade = null
	new.stream = stream
	new.play(from)
	if crossfade and old.playing:
		_set_mix(0.0)
		_fade = create_tween()
		_fade.tween_method(_set_mix, 0.0, 1.0, SECTION_CROSSFADE)
		_fade.tween_callback(old.stop)
	else:
		old.stop()
		_set_mix(1.0)
	_current = section
	_last_position = from
	Log.debug("section music: section %d (%s)" % [section.number, section.file])


func _set_mix(mix: float) -> void:
	_mix = mix
	_apply_mix()


func _apply_mix() -> void:
	if _players.is_empty():
		return
	_players[_at].volume_linear = _gain * _mix
	_players[1 - _at].volume_linear = _gain * (1.0 - _mix)


func _section_numbered(number: int) -> Section:
	for section in _track:
		if section.number == number:
			return section
	return null


## The cue between two playback positions, a loop's return between them too; else −1.
func _crossed_cue(before: float, now: float) -> float:
	for cue in _current.cues:
		if (now >= before and cue > before and cue <= now) or (now < before and (cue > before or cue <= now)):
			return cue
	return -1.0
