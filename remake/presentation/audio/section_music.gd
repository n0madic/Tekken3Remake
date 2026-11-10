class_name SectionMusic
extends Node
## The arcade's BGMs as the sound board plays them (tools/remake_import/arcade_sounds.py): a file
## per section, or per section and part when converted with `--music-parts` (`music/arcade.json`).
## The game writes the section variable; a part's channels answer after its delay (the poller's,
## for those that wait for its gate) at the next of its file's cues (the bars that test it). With
## parts each changes section at the bar the cabinet changes it: in most BGMs the channels that
## test the variable itself go a bar before the others; one file per section has them go with the
## others (docs/research/arcade/audio-and-effects.md#sections). Both builds play it: the arcade's
## (ArcadeAudio) and the PlayStation's with the arcade's music converted (AudioDirector).

const TABLE := "music/arcade.json"
const BOARD_RATE := 120              ## ticks per second
const SECTION_NONE := -1
const SECTION_FIRST := 1             ## the poller waits for 1, then 2, then 3, then for 2 and 3 in turn
const SECTION_LAST := 3
const SECTION_AGAIN := 2
const SECTION_CROSSFADE := 0.03      ## seconds: the two renderings of the same bar overlap this long
const BUS := &"Music"
const FULL_SCALE := 32767.0


## A group of channels' file in a section. A section's parts end at the same tick.
class Part:
	var file := ""
	var length := 0.0                ## seconds
	var loop := -1.0
	var cues := PackedFloat32Array()
	var delay := 0.0                 ## seconds from the write until its channels may answer


class Section:
	var number := 0
	var parts: Array[Part] = []


## A part as it plays: two players to cross-fade from one section's file to the next.
class Lane:
	var players: Array[AudioStreamPlayer] = []
	var at := 0                      ## the player that sounds
	var part: Part
	var mix := 1.0                   ## the crossfade's progress: the new player's share
	var fade: Tween
	var last_position := 0.0
	var waiting := false             ## for the pending section
	var ticks := 0                   ## of its delay left


var available := false
var ps_tracks: Dictionary = {}       ## PlayStation track → {sequence, first_section, advance} (a merged conversion's)
var _tracks: Dictionary = {}         ## sequence → Array[Section]
var _peaks: Dictionary = {}          ## sequence → its loudest sample
var _streams: Dictionary = {}        ## file path → AudioStream
## File path → its Part: a background load not taken yet. Every request is taken (into `_streams`):
## the loader keeps one nobody takes until the end, and it leaks at exit.
var _requested: Dictionary = {}
var _lanes: Array[Lane] = []         ## grows to the most parts a sequence had; the first `_active` play
var _active := 0
var _track: Array[Section] = []
var _current: Section                ## the section every part is in
var _target: Section                 ## the section the parts are going to
var _variable := 0                   ## var[0xE0]
var _expected := SECTION_FIRST
var _pending := SECTION_NONE
var _gain := 1.0                     ## the owner's volume (linear)


## The next value the game writes: 1, 2, 3, then 2 and 3 in turn.
static func next_section(section: int) -> int:
	return SECTION_AGAIN if section >= SECTION_LAST else section + 1


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
	_add_lane()
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
			for entry: Dictionary in row["parts"] as Array:
				var part := Part.new()
				part.file = entry["file"] as String
				part.length = entry["length"] as float
				part.loop = -1.0 if entry["loop"] == null else entry["loop"] as float
				part.delay = entry["delay"] as float
				for c: float in entry["cues"] as Array:
					part.cues.append(c)
				section.parts.append(part)
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
	if not available or not _tracks.has(sequence):
		stop()
		return
	_silence()
	# The script clears the section variables as it starts.
	_variable = 0
	_expected = SECTION_FIRST
	_pending = SECTION_NONE
	_target = null
	_track.assign(_tracks[sequence] as Array)
	Log.debug("section music: %02x from section %d" % [sequence, section])
	for s in _track:
		if s.number != 0:
			for part in s.parts:
				_request(part)
	var first := _section_numbered(section) if section > 0 else null
	if first == null:
		first = _track[0]
	else:
		_variable = section
		_expected = next_section(section)
	_active = first.parts.size()
	while _lanes.size() < _active:
		_add_lane()
	# The parts end together: each starts where the one whose channels go in last starts.
	var shortest := INF
	for part in first.parts:
		shortest = minf(shortest, part.length)
	for i in _active:
		_change_lane(_lanes[i], first.parts[i], first.parts[i].length - shortest, false)
	_current = first


func stop() -> void:
	_silence()
	_current = null
	_target = null
	_track = []
	_variable = 0
	_pending = SECTION_NONE


## The game's write of the section variable.
func write(section: int) -> void:
	_variable = section


## The owner's volume, faded or not.
func set_gain(gain: float) -> void:
	_gain = gain
	for lane in _lanes:
		_apply_mix(lane)


func set_paused(paused: bool) -> void:
	for lane in _lanes:
		for p in lane.players:
			p.stream_paused = paused
		if lane.fade != null and lane.fade.is_valid():
			if paused:
				lane.fade.pause()
			else:
				lane.fade.play()


## The board's clock: `ticks` more (the delays count them).
func advance(ticks: int) -> void:
	_collect_requests()
	if _current == null:
		return
	if _pending == SECTION_NONE and _variable == _expected:
		var next := _section_numbered(_expected)
		_expected = next_section(_expected)
		if next != null:
			_pending = next.number
			_target = next
			for i in _active:
				_lanes[i].waiting = true
				_lanes[i].ticks = roundi(next.parts[i].delay * BOARD_RATE)
	var waiting := false
	for i in _active:
		var lane := _lanes[i]
		var position := _position(lane)
		if lane.waiting:
			lane.ticks -= ticks
			var cue := _crossed_cue(lane.part.cues, lane.last_position, position) if lane.ticks <= 0 else -1.0
			if cue >= 0.0:
				lane.waiting = false
				_change_lane(lane, _target.parts[i], maxf(position - cue, 0.0), true)
				continue
			waiting = true
		lane.last_position = position
	if _pending != SECTION_NONE and not waiting:
		_current = _target
		_target = null
		_pending = SECTION_NONE
		Log.debug("section music: section %d" % _current.number)


func _add_lane() -> void:
	var lane := Lane.new()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		lane.players.append(p)
	_lanes.append(lane)


func _silence() -> void:
	for lane in _lanes:
		if lane.fade != null:
			lane.fade.kill()
			lane.fade = null
		lane.waiting = false
		for p in lane.players:
			p.stop()


func _position(lane: Lane) -> float:
	return lane.players[lane.at].get_playback_position()


## The later sections load in the background while the first plays.
func _request(part: Part) -> void:
	var path := Assets.path("music/" + part.file)
	if _streams.has(path) or _requested.has(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_requested[path] = part


func _music_stream(part: Part) -> AudioStream:
	var path := Assets.path("music/" + part.file)
	if _requested.has(path):
		_take(path)
	if not _streams.has(path):
		_cache(path, load(path) as AudioStream, part)
	return _streams[path] as AudioStream


## A requested load, waiting for it if need be.
func _take(path: String) -> void:
	var part := _requested[path] as Part
	_requested.erase(path)
	_cache(path, ResourceLoader.load_threaded_get(path) as AudioStream, part)


## Takes the requested loads that have finished.
func _collect_requests() -> void:
	if _requested.is_empty():
		return
	for path: String in _requested.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_take(path)


func _cache(path: String, stream: AudioStream, part: Part) -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = part.loop >= 0.0
		ogg.loop_offset = maxf(part.loop, 0.0)
	_streams[path] = stream


func _change_lane(lane: Lane, part: Part, from: float, crossfade: bool) -> void:
	var stream := _music_stream(part)
	var old := lane.players[lane.at]
	lane.at = 1 - lane.at
	var new := lane.players[lane.at]
	if lane.fade != null:
		lane.fade.kill()
		lane.fade = null
	new.stream = stream
	new.play(from)
	if crossfade and old.playing:
		_set_mix(0.0, lane)
		lane.fade = create_tween()
		lane.fade.tween_method(_set_mix.bind(lane), 0.0, 1.0, SECTION_CROSSFADE)
		lane.fade.tween_callback(old.stop)
	else:
		old.stop()
		_set_mix(1.0, lane)
	lane.part = part
	lane.last_position = from
	Log.debug("section music: %s" % part.file)


func _set_mix(mix: float, lane: Lane) -> void:
	lane.mix = mix
	_apply_mix(lane)


func _apply_mix(lane: Lane) -> void:
	lane.players[lane.at].volume_linear = _gain * lane.mix
	lane.players[1 - lane.at].volume_linear = _gain * (1.0 - lane.mix)


func _section_numbered(number: int) -> Section:
	for section in _track:
		if section.number == number:
			return section
	return null


## The cue between two playback positions, a loop's return between them too; else −1.
static func _crossed_cue(cues: PackedFloat32Array, before: float, now: float) -> float:
	for cue in cues:
		if (now >= before and cue > before and cue <= now) or (now < before and (cue > before or cue <= now)):
			return cue
	return -1.0
