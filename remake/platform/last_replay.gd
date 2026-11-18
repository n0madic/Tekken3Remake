class_name LastReplay
extends RefCounted
## The remake's last-battle replay (docs/DECISIONS.md D19): a session's pads recorded from its
## boot, with the flow seed and the boot-time progress block. The replay session boots fresh
## (`--fresh` semantics), applies the progress as pokes and feeds the recorded pads, so the
## deterministic simulation repeats the session exactly: the menus, the battle and what follows.

const MAGIC := 0x50523354            ## "T3RP" as a little-endian word
const VERSION := 2

var seed := 0                        ## the recorded session's flow seed
var progress := PackedByteArray()    ## the boot-time progress block (GameProgress.SIZE bytes)
var words := PackedInt32Array()      ## two 16-bit pad words per step (players 1, 2)
var flags := PackedByteArray()       ## per step: 0 normal, 1 the flow was movie-blocked,
                                     ## 2 the blocked frame finishes (the movie ended)


## The step count: the game's replay reader asks for `frames` and `pad(step, player)`.
var frames: int:
	get: return words.size() >> 1


## The step's pad word (zero past the recording's end: the session idled on).
func pad(step: int, player: int) -> int:
	var at := step * 2 + player
	return words[at] if at < words.size() else 0


## The step's movie flag (zero past the recording's end).
func step_flag(step: int) -> int:
	return flags[step] if step < flags.size() else 0


## The boot-time progress as (address, value) pokes; the game's replay boot puts them back.
func pokes() -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	for i in progress.size():
		out.append(PackedInt64Array([GameProgress.BASE + i, progress[i]]))
	return out


## Writes the file (created on demand): magic, version, seed, the progress block, the pads.
static func save(path: String, flow_seed: int, progress_bytes: PackedByteArray,
		pad_words: PackedInt32Array, step_flags: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(MAGIC)
	f.store_16(VERSION)
	f.store_32(flow_seed & 0xFFFFFFFF)
	f.store_32(progress_bytes.size())
	f.store_buffer(progress_bytes)
	f.store_32(pad_words.size())
	for w in pad_words:
		f.store_16(w & 0xFFFF)
	f.store_32(step_flags.size())
	f.store_buffer(step_flags)
	return true


## Reads a file back, or null when it is missing or not a replay of this version.
static func read(path: String) -> LastReplay:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_32() != MAGIC or f.get_16() != VERSION:
		return null
	var out := LastReplay.new()
	out.seed = f.get_32()
	var size := f.get_32()
	out.progress = f.get_buffer(size)
	if size == 0 or out.progress.size() != size:
		return null
	var count := f.get_32()
	out.words.resize(count)
	for i in count:
		out.words[i] = f.get_16()
	var flag_count := f.get_32()
	out.flags = f.get_buffer(flag_count)
	if out.flags.size() != flag_count or out.words.size() != out.flags.size() * 2:
		return null
	return out
