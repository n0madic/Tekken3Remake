extends TestSuite
## The converted music and movies (optional groups) load and last as long as converted.

const DISC_DATA := [
	"test_movies_load_with_their_duration",
	"test_music_tracks_load",
]
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


## A one-frame fallback movie (MovieFile's container) at `path`.
static func _write_movie(path: String) -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var jpg := img.save_jpg_to_buffer()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(MovieFile.MAGIC.to_ascii_buffer())
	f.store_32(MovieFile.VERSION)
	f.store_16(16)
	f.store_16(16)
	f.store_32(1)
	f.store_32(150)
	f.store_32(4 + 4 + 4 + 4 + 4 + 12)
	f.store_32(jpg.size())
	f.store_32(0)
	f.store_buffer(jpg)
	f.close()


## MoviePlayer at the end of a movie: it finishes, or starts over when the entry loops (the
## descriptor's restart flag, Gon's ending: issue n0madic/Tekken3Remake#34) until it is stopped.
func test_a_looping_movie_starts_over_at_its_end() -> void:
	var path := "user://test_movie_loop_%d.bin" % OS.get_process_id()
	_write_movie(path)
	for loop: bool in [false, true]:
		var player := MoviePlayer.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(player)
		var ended := [0]
		player.finished.connect(func() -> void: ended[0] += 1)
		var entry := {"frames": path.get_file(), "duration": 0.5, "loop": loop}
		expect(player.play(path.get_base_dir(), entry, 1.0), "plays")
		player._process(0.0)
		expect_equal(player.shown, 0, "the first frame")
		player._started_at -= 1.0
		player._process(0.0)
		if loop:
			expect(player.playing, "a looping movie plays on past its end")
			expect_equal(ended[0], 0, "and does not finish")
			expect_equal(player.shown, 0, "from its first frame")
			player.stop()
			expect_equal(ended[0], 1, "until it is stopped")
		else:
			expect(not player.playing, "a movie ends at its end")
			expect_equal(ended[0], 1, "finished")
		player.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
