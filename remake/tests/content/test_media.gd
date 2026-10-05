extends TestSuite
## The converted music and movies (optional groups) load and last as long as converted.

const MOVIES := AssetCatalog.ROOT + "movies"
const MUSIC := AssetCatalog.ROOT + "music"
const DURATION_TOLERANCE := 0.1
const NO_MEDIA := "no converted media (tools/remake_import/convert.py without --no-music / --no-movies)"


func test_movies_load_with_their_duration() -> void:
	if not require(MOVIES + "/movies.json", NO_MEDIA):
		return
	var index: Dictionary = JsonFile.read(MOVIES + "/movies.json")
	var entries: Array = index["title"]
	expect_equal(entries.size(), 2, "title movies")
	for entry: Dictionary in entries:
		var expected: float = entry["duration"]
		if entry.has("video"):
			var variants: Array = entry["video"]
			expect(not variants.is_empty(), "%s has no video variant" % entry["name"])
			for file: String in variants:
				var stream := load(MOVIES.path_join(file)) as VideoStream
				expect(stream != null, "%s does not load" % file)
				if stream == null:
					continue
				var player := VideoStreamPlayer.new()
				player.stream = stream
				var seconds := player.get_stream_length()
				player.free()
				expect(absf(seconds - expected) <= DURATION_TOLERANCE,
					"%s lasts %.2f s, converted %.2f s" % [file, seconds, expected])
			continue
		var movie := MovieFile.open(MOVIES.path_join(str(entry["frames"])))
		expect(movie != null, "%s does not load" % entry["frames"])
		if movie == null:
			continue
		var last := movie.frame_time(movie.frame_count() - 1)
		expect(load(MOVIES.path_join(str(entry["audio"]))) is AudioStream, "%s does not load" % entry["audio"])
		expect(last < expected and expected - last <= DURATION_TOLERANCE,
			"%s: last frame at %.2f s, converted duration %.2f s" % [entry["name"], last, expected])


func test_music_tracks_load() -> void:
	if not require(MUSIC + "/music.json", NO_MEDIA):
		return
	var index: Dictionary = JsonFile.read(MUSIC + "/music.json")
	var tracks: Dictionary = index["tracks"]
	expect(not tracks.is_empty(), "no tracks")
	for track: String in tracks:
		for variant: Dictionary in tracks[track]:
			var stream := load(MUSIC.path_join(str(variant["file"]))) as AudioStream
			expect(stream != null and stream.get_length() > 0.0, "track %s: %s does not load" % [track, variant["file"]])


## MovieCaptions.caption_at: the last change at or before the decoded frame (FUN_8010F0B4, as the
## converter lists the changes); a set or caption that is not there shows none.
func test_captions_by_frame() -> void:
	var c := MovieCaptions.new()
	c.pictures = [ImageTexture.new(), ImageTexture.new()] as Array[Texture2D]
	c.sets = [PackedInt32Array([4, 0, 11, 1, 21, -1]), PackedInt32Array([6, 5])] as Array[PackedInt32Array]
	var cases := [[1, 3, -1], [1, 4, 0], [1, 10, 0], [1, 11, 1], [1, 20, 1], [1, 21, -1], [2, 7, -1], [0, 5, -1],
		[3, 5, -1]]
	for k: Array in cases:
		expect_equal(c.caption_at(k[0] as int, k[1] as int), k[2] as int, "set %d frame %d" % [k[0], k[1]])


## The converted captions load, name a set for every ending movie, and every ending lists its
## frames' slots.
func test_converted_captions() -> void:
	if not require(MOVIES + "/captions.json", NO_MEDIA):
		return
	var c := MovieCaptions.load_from(MOVIES + "/captions.json")
	var index: Dictionary = JsonFile.read(MOVIES + "/movies.json")
	var endings: Array = index["ending"]
	expect(c != null and not c.sets.is_empty(), "caption sets")
	expect_equal(c.movies.size(), endings.size(), "a caption set per ending movie")
	for m in endings.size():
		expect(c.set_of(m) <= c.sets.size(), "movie %d names a caption set there is" % m)
	for picture in c.pictures:
		expect(picture != null, "a caption picture loads")
	for entry: Dictionary in endings:
		expect(not (entry.get("frame_slots", []) as Array).is_empty() and JsonFile.number(entry.get("fps", 0)) > 0,
			"%s has its frames' slots" % entry["name"])
