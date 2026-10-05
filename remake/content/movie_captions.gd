class_name MovieCaptions
extends RefCounted
## The ending movies' captions (formats/sound-and-video.md, "Movie captions"): `movies/captions.json`,
## or the USA release's English ones in `usa/captions.json` (tools/remake_import/captions.py). Each
## caption is a picture with its place in the movie's pixels (from the picture's top-left corner);
## each caption set lists its changes by decoded movie frame, as FUN_8010F0B4 shows them; `movies`
## names the set of each movie of the ending list (the releases caption different movies).

var pictures: Array[Texture2D] = []
var places: Array[Vector2i] = []
var sets: Array[PackedInt32Array] = []   ## per set (1 the first): frame, caption, frame, caption, …
var movies := PackedInt32Array()          ## per ending movie: its caption set, 0 none


## The captions of `path`, or null when it was not converted.
static func load_from(path: String) -> MovieCaptions:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var d: Dictionary = JsonFile.read(path)
	var c := MovieCaptions.new()
	for entry: Dictionary in d.get("captions", []):
		c.pictures.append(load(path.get_base_dir().path_join(str(entry["picture"]))) as Texture2D)
		c.places.append(Vector2i(JsonFile.number(entry["x"]), JsonFile.number(entry["y"])))
	for changes: Array in d.get("sets", []):
		var flat := PackedInt32Array()
		for change: Array in changes:
			flat.append_array(JsonFile.ints(change))
		c.sets.append(flat)
	c.movies = JsonFile.ints(d.get("movies", []))
	return c


## The caption set of ending movie `movie` (0 none).
func set_of(movie: int) -> int:
	return movies[movie] if movie >= 0 and movie < movies.size() else 0


## The caption of set `set_number` (1 the first) shown on decoded frame `frame` (1 the first), −1 none.
func caption_at(set_number: int, frame: int) -> int:
	if set_number < 1 or set_number > sets.size():
		return -1
	var changes := sets[set_number - 1]
	var shown := -1
	for k in range(0, changes.size(), 2):
		if changes[k] > frame:
			break
		shown = changes[k + 1]
	return shown if shown < pictures.size() else -1
