class_name MovieFile
extends RefCounted
## The fallback movie container (`imported/movies/<name>.bin`, tools/remake_import/media.py, when
## FFmpeg has no Theora encoder): JPEG frames with the CD sector at which each frame arrives
## (150 sectors per second); the audio is `<name>.wav`, the length is the movies.json entry's
## `duration`.

const MAGIC := "T3MV"
const VERSION := 1

var width: int
var height: int
var sectors_per_second: int
var offsets := PackedInt32Array()
var sizes := PackedInt32Array()
var sectors := PackedInt32Array()
var file: FileAccess


static func open(path: String) -> MovieFile:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(4).get_string_from_ascii() != MAGIC or f.get_32() != VERSION:
		Log.error("MovieFile: %s is not a version %d movie" % [path, VERSION])
		return null
	var m := MovieFile.new()
	m.file = f
	m.width = f.get_16()
	m.height = f.get_16()
	var count := f.get_32()
	m.sectors_per_second = f.get_32()
	for i in count:
		m.offsets.append(f.get_32())
		m.sizes.append(f.get_32())
		m.sectors.append(f.get_32())
	return m


func frame_count() -> int:
	return offsets.size()


## The time (seconds from the start) at which frame `i` appears.
func frame_time(i: int) -> float:
	return float(sectors[i] - sectors[0]) / sectors_per_second



func image(i: int) -> Image:
	file.seek(offsets[i])
	var img := Image.new()
	if img.load_jpg_from_buffer(file.get_buffer(sizes[i])) != OK:
		return null
	return img
