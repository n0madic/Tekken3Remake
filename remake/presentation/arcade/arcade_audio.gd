class_name ArcadeAudio
extends Node
## The arcade's sound board on the converted files (tools/remake_import/arcade_sounds.py). The
## simulation asks in the board's own ids; what a request plays comes from the tables its scripts
## were read into: `sounds/arcade.json` per route and id the plan of a player sequence (which C352
## voice, when, how loud), `music/arcade.json` per sequence its sections.
##
## A plan runs on a channel: a new request on a channel ends the old one, a note takes the voice
## from whatever holds it, a channel's end takes its voices along, as on the board.
##
## Music: a BGM is a file per section, played by SectionMusic. What the sound channels' voices take
## from the music on the board (the voices are shared by priority) is not reproduced: the music was
## rendered alone.

const SOUND_TABLE := "sounds/arcade.json"
const VOICES := 32
const CHANNELS := 32
const BOARD_RATE := 120              ## ticks per second
const TICKS_PER_STEP := 2            ## per simulation step
const KEPT_CHANNEL := 0x1F           ## what FUN_801B0ACC(1) spares
const PLAYER_CHANNELS: Array[int] = [0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A]    ## FUN_801B0B14
const ID_MASK := 0xFFF
const NIBBLE_VOICE_FIRST := 2
const NIBBLE_VOICE_LAST := 5
const NIBBLE_THROW_VOICE := 4        ## FUN_801A0CD4 echoes it like a replay's
const NIBBLE_HIT := 7
const OWN_WAVE := -1
const SILENT_DB := -80.0


class PlanNote:
	var tick := 0
	var voice := 0
	var wave := OWN_WAVE
	var gain := PackedFloat32Array()


class Plan:
	var channel := 0
	var end := -1
	var notes: Array[PlanNote] = []


class Running:
	var plan: Plan
	var wave := 0
	var bus: StringName
	var started := 0
	var next_note := 0


var available := false
var music := SectionMusic.new()
var _plans: Array[Plan] = []
var _waves: Dictionary = {}          ## wave number → file name
var _table := PackedInt32Array()     ## sound id → wave (the system route's)
var _system := PackedInt32Array()    ## sound id → plan
var _sound: Array[PackedInt32Array] = []    ## per player, sound id → plan
var _hit: Array[PackedInt32Array] = []
var _voice: Array[PackedInt32Array] = []    ## per player: the plan without and with the replay's echoes
var _sequences: Dictionary = {}      ## sequence → plan
var _streams: Dictionary = {}        ## file → AudioStream

var _clock := 0                      ## board ticks
var _players: Array[AudioStreamPlayer] = []
var _running: Array[Running] = []    ## per channel
var _note_channel := PackedInt32Array()
var _note_started := PackedInt32Array()
var _note_gain: Array[PackedFloat32Array] = []



func _ready() -> void:
	for bus in AudioDirector.BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_note_channel.resize(VOICES)
	_note_channel.fill(-1)
	_note_started.resize(VOICES)
	_note_gain.resize(VOICES)
	_running.resize(CHANNELS)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(music)
	_load_sounds()
	Log.debug("arcade audio: %d plans, %d samples, %d music sequences" % [_plans.size(), _waves.size(), music.sequence_count()])


func _load_sounds() -> void:
	var path := Assets.path(SOUND_TABLE)
	if not FileAccess.file_exists(path):
		return
	var data: Dictionary = JsonFile.read(path)
	for row: Dictionary in data["plans"] as Array:
		var plan := Plan.new()
		plan.channel = row["channel"] as int
		plan.end = -1 if row["end"] == null else row["end"] as int
		for n: Dictionary in row["notes"] as Array:
			var note := PlanNote.new()
			note.tick = n["tick"] as int
			note.voice = n["voice"] as int
			note.wave = n["wave"] as int
			for g: float in n["gain"] as Array:
				note.gain.append(g)
			plan.notes.append(note)
		_plans.append(plan)
	_waves = data["waves"]
	_table = JsonFile.ints(data["table"])
	var routes: Dictionary = data["routes"]
	_system = JsonFile.ints(routes["system"])
	for player in 2:
		_sound.append(JsonFile.ints((routes["sound"] as Array)[player]))
		_hit.append(JsonFile.ints((routes["hit"] as Array)[player]))
		_voice.append(JsonFile.ints((routes["voice"] as Array)[player]))
	var sequences: Dictionary = data["sequences"]
	for key: String in sequences:
		_sequences[key.to_int()] = sequences[key]
	available = true


## The step's requests. `sounds_on`: the board hears what the program does not hold back (ArcadeGameFlow.sounds_on).
func handle(events: SimEvents, fight: FightState, sounds_on: bool) -> void:
	for e: SimEvents.Event in events.items:
		match e.kind:
			SimEvents.Kind.VOICES_OFF:
				_stop_all(e.a != 0)
			SimEvents.Kind.MUSIC_STOP:
				if e.fighter < 0:
					music.stop()
			SimEvents.Kind.VOICE_OFF:
				# A fighter's are the PlayStation's voice key-offs, here the board's scripts'.
				if e.fighter < 0 and sounds_on:
					for channel in PLAYER_CHANNELS:
						_end_channel(channel)
			SimEvents.Kind.SOUND:
				if sounds_on:
					_on_sound(e, fight)
			SimEvents.Kind.SOUND_STOP:
				if sounds_on and e.b < _sound.size():
					_end_channel(_plans[_sound[e.b][0]].channel)
			SimEvents.Kind.SYSTEM_SOUND:
				if sounds_on:
					_on_system_sound(e)
			SimEvents.Kind.MUSIC:
				if sounds_on:
					music.play(e.a)
			SimEvents.Kind.MUSIC_SECTION:
				if sounds_on:
					music.write(e.a)


func _on_sound(e: SimEvents.Event, fight: FightState) -> void:
	if e.fighter < 0:
		_system_id(e.a)
		return
	if e.id == 0 or not available:      # EffectObjects' echoes: on the board they are the voice's script
		return
	var nibble := (e.id >> 12) & 0xF
	var player := e.b
	if nibble >= NIBBLE_VOICE_FIRST and nibble <= NIBBLE_VOICE_LAST:
		var echo := nibble == NIBBLE_THROW_VOICE or fight.replay_playing != 0
		_start(_voice[player][1 if echo else 0], e.a, &"Voices", -1)
		return
	var plans := _hit[player] if nibble == NIBBLE_HIT else _sound[player]
	var index := e.id & ID_MASK
	if index > 0 and index < plans.size():
		_start(plans[index], e.a, &"SFX", -1)


func _on_system_sound(e: SimEvents.Event) -> void:
	if e.fighter >= 0:
		_system_id(e.a)
	elif _sequences.has(e.a):
		_start(_sequences[e.a] as int, OWN_WAVE, &"System", e.b)


## FUN_801A0C10.
func _system_id(id: int) -> void:
	var index := id & ID_MASK
	if available and index > 0 and index < _system.size():
		_start(_system[index], _table[index], &"System", -1)


func _start(plan_index: int, wave: int, bus: StringName, channel: int) -> void:
	var run := Running.new()
	run.plan = _plans[plan_index]
	run.wave = wave
	run.bus = bus
	run.started = _clock
	var on := run.plan.channel if channel < 0 else channel
	_end_channel(on)
	_running[on] = run
	Log.debug("arcade audio: channel %02x wave %x" % [on, wave])
	_run_channel(on, run)


func _end_channel(channel: int) -> void:
	_running[channel] = null
	for v in VOICES:
		if _note_channel[v] == channel:
			_players[v].stop()
			_note_channel[v] = -1


## FUN_801B0ACC.
func _stop_all(keep_last: bool) -> void:
	for channel in CHANNELS:
		if not keep_last or channel != KEPT_CHANNEL:
			_end_channel(channel)
	music.stop()


func _run_channel(channel: int, run: Running) -> void:
	var elapsed := _clock - run.started
	while run.next_note < run.plan.notes.size() and run.plan.notes[run.next_note].tick <= elapsed + TICKS_PER_STEP:
		_key_on(channel, run, run.plan.notes[run.next_note])
		run.next_note += 1
	if run.plan.end >= 0 and elapsed >= run.plan.end:
		_end_channel(channel)


func _key_on(channel: int, run: Running, note: PlanNote) -> void:
	var wave := run.wave if note.wave == OWN_WAVE else note.wave
	var stream := _wave_stream(wave)
	if stream == null:
		return
	var p := _players[note.voice]
	p.stream = stream
	p.bus = run.bus
	p.volume_linear = note.gain[0]
	p.play()
	_note_channel[note.voice] = channel
	_note_started[note.voice] = _clock
	_note_gain[note.voice] = note.gain


func _wave_stream(wave: int) -> AudioStream:
	var file := str(_waves.get(str(wave), ""))
	if file.is_empty():
		return null
	if not _streams.has(file):
		_streams[file] = load(Assets.path("sounds/" + file))
	return _streams[file] as AudioStream


## Each simulation step, whether the flow ran or not: the board's clock.
func advance() -> void:
	_clock += TICKS_PER_STEP
	for channel in CHANNELS:
		var run := _running[channel]
		if run != null:
			_run_channel(channel, run)
	for v in VOICES:
		if _note_channel[v] >= 0 and _note_gain[v].size() > 1:
			var at := mini(_clock - _note_started[v], _note_gain[v].size() - 1)
			_players[v].volume_linear = _note_gain[v][at]
	music.advance(TICKS_PER_STEP)


## The pause: the voices and the music hold where they are and go on from there. The board's clock
## stands still meanwhile, as nothing calls `advance`.
func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused
	music.set_paused(paused)
