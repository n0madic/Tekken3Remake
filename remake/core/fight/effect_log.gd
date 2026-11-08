class_name EffectLog
extends RefCounted
## A log of the effects each frame started, which the replay starts again: a ring of frame slots over a
## ring of entries, with a limit on the entries per cycle of the frame ring. The PlayStation keeps one
## for flipbooks and dust rings (FUN_8004A6A4, FUN_8004A700, FUN_8004A8AC, FUN_8004A954); the arcade one
## of each (FUN_801ADB1C, FUN_801ADB6C, FUN_801ADC64, FUN_801ADD18; FUN_801AE50C, FUN_801AE55C,
## FUN_801AE600, FUN_801AE6B4), and keeps them with a kept fight (FUN_801ADE80, FUN_801ADF88).

const FRAMES := 300
const FLIPBOOK := 0                 ## `Entry.mode`
const DUST := 1
const SYSTEM_SET := 3               ## `Entry.set` of the system's flipbooks (the arcade's own number is 2)
const OBJECTS := 0x80               ## `Entry.index`: not a flipbook, the effect objects of a hit

## One entry (0x1C bytes on the PlayStation, 0x18 and 0x10 on the arcade).
class Entry:
	var point := PackedInt32Array([0, 0, 0])
	var direction := PackedInt32Array([0, 0, 0])   ## s16 direction (or damage in the third)
	var mode := FLIPBOOK
	var set := 0
	var index := 0

	func copy() -> Entry:
		var out := Entry.new()
		out.point = point.duplicate()
		out.direction = direction.duplicate()
		out.mode = mode
		out.set = set
		out.index = index
		return out


var on := 0
var frame := 0                      ## the frame slot being written
var read := 0                       ## the frame slot being played
var cycle := 0                      ## entries written since the frame ring last wrapped
var write := 0                      ## the next entry
var slots := PackedInt32Array()     ## per frame slot: first entry | count << 16
var entries: Array[Entry] = []
var _cycle_limit := 0


func _init(entry_count: int, cycle_limit: int) -> void:
	_cycle_limit = cycle_limit
	slots.resize(FRAMES)
	for i in entry_count:
		entries.append(Entry.new())


## At a round start: the log starts empty.
func reset() -> void:
	on = 1
	frame = 0
	cycle = 0
	write = 0
	slots[0] = 0


func add(set: int, index: int, point: PackedInt32Array, direction: PackedInt32Array, mode: int) -> void:
	if on == 0:
		return
	cycle += 1
	if cycle >= _cycle_limit:
		return
	slots[frame] += 1 << 16
	var e := entries[write]
	e.mode = mode
	if mode == FLIPBOOK:
		e.point = point.duplicate()
		e.direction = direction.duplicate()
		e.set = set
		e.index = index
	elif mode == DUST:
		e.point = point.duplicate()
	write = (write + 1) % entries.size()


## The next frame slot.
func advance() -> void:
	if on == 0:
		return
	frame += 1
	if frame >= FRAMES:
		frame = 0
		cycle = 0
	slots[frame] = write


## The playback starts `back` frames before the slot being written.
func rewind(back: int) -> void:
	read = frame - back
	if read < 0:
		read += FRAMES


## The entries of the frame slot being played, then the next slot.
func take() -> Array[Entry]:
	var out: Array[Entry] = []
	var slot := slots[read]
	var at := slot & 0xFFFF
	for k in (slot >> 16) & 0xFFFF:
		out.append(entries[(at + k) % entries.size()])
	read = (read + 1) % FRAMES
	return out


## A copy whose last slot is the one being written.
func kept() -> EffectLog:
	var out := EffectLog.new(entries.size(), _cycle_limit)
	for i in entries.size():
		out.entries[i] = entries[i].copy()
	for i in FRAMES:
		out.slots[i] = slots[(frame + 1 + i) % FRAMES]
	return out


## A kept copy in place of the live one, played from the slot `first`.
func restore(from: EffectLog, first: int) -> void:
	for i in entries.size():
		entries[i] = from.entries[i].copy()
	slots = from.slots.duplicate()
	read = first % FRAMES
