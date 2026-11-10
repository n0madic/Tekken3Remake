extends TestSuite
## ArcadeAudio's decisions that need no files: the music's cues, and its section poller on made-up sections.


func _audio() -> ArcadeAudio:
	var audio := ArcadeAudio.new()
	audio._current = ArcadeAudio.Section.new()
	audio._current.cues = PackedFloat32Array([2.0, 4.0, 6.0])
	return audio


func test_a_cue_counts_when_the_position_passes_it() -> void:
	var audio := _audio()
	expect_equal(audio._crossed_cue(1.0, 1.5), -1.0)
	expect_equal(audio._crossed_cue(1.5, 2.0), 2.0)
	expect_equal(audio._crossed_cue(2.0, 2.5), -1.0, "the position it was at does not count again")
	expect_equal(audio._crossed_cue(3.9, 4.1), 4.0)
	audio.free()


func test_a_loops_return_passes_the_cues_on_both_sides() -> void:
	var audio := _audio()
	expect_equal(audio._crossed_cue(5.9, 1.0), 6.0, "before the return")
	expect_equal(audio._crossed_cue(6.5, 2.5), 2.0, "after the return")
	expect_equal(audio._crossed_cue(6.5, 1.0), -1.0, "none in between")
	audio.free()


func test_sections_are_found_by_number() -> void:
	var audio := _audio()
	var first := ArcadeAudio.Section.new()
	first.number = 1
	audio._track = [first]
	expect_equal(audio._section_numbered(1), first)
	expect_equal(audio._section_numbered(2), null)
	audio.free()


## On an arcade conversion every BGM (the stage records' sequences 0x10–0x1E) has its intro and
## sections 1–3, and each of them has cues, the bars the next section can start at: issue
## n0madic/Tekken3Remake#31 (Jin's BGM, whose channels test the section variable itself, stayed in
## its intro).
func test_every_bgm_reaches_its_sections_at_cues() -> void:
	var path := AssetCatalog.ROOT.path_join(ArcadeAudio.MUSIC_TABLE)
	if not require(path) or not Assets.arcade_only():
		return
	var tracks: Dictionary = (JsonFile.read(path) as Dictionary)["tracks"]
	for sequence in range(0x10, 0x1F):
		var rows: Array = (tracks[str(sequence)] as Dictionary)["sections"]
		var numbers: Array[int] = []
		for row: Dictionary in rows:
			numbers.append(row["section"] as int)
			expect(not (row["cues"] as Array).is_empty(), "%x section %d: cues" % [sequence, row["section"] as int])
			expect(row["loop"] != null, "%x section %d: loops" % [sequence, row["section"] as int])
		expect_equal(numbers, [0, 1, 2, 3] as Array[int], "%x: its sections" % sequence)
