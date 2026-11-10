extends TestSuite
## SectionMusic's decisions that need no files: the music's cues, and its sections on made-up ones.


func _audio() -> SectionMusic:
	var audio := SectionMusic.new()
	audio._current = SectionMusic.Section.new()
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


func test_the_written_sections_go_1_2_3_then_2_and_3() -> void:
	var order: Array[int] = []
	var section := 0
	for i in 6:
		section = SectionMusic.next_section(section)
		order.append(section)
	expect_equal(order, [1, 2, 3, 2, 3, 2] as Array[int])


func test_sections_are_found_by_number() -> void:
	var audio := _audio()
	var first := SectionMusic.Section.new()
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
	var path := AssetCatalog.ROOT.path_join(SectionMusic.TABLE)
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


## On a conversion next to a disc (`--arcade`), every fight track (7–28) stands for a converted BGM
## with its sections, for the ARCADE soundtrack (issue n0madic/Tekken3Remake#31).
func test_every_fight_track_has_an_arcade_bgm_next_to_a_disc() -> void:
	var path := AssetCatalog.ROOT.path_join(SectionMusic.TABLE)
	if not require(path) or Assets.arcade_only():
		return
	var data: Dictionary = JsonFile.read(path)
	var tracks: Dictionary = data["tracks"]
	var ps_tracks: Dictionary = data.get("ps_tracks", {})
	for track in range(7, 29):
		expect(ps_tracks.has(str(track)), "track %d" % track)
		if ps_tracks.has(str(track)):
			var sequence := (ps_tracks[str(track)] as Dictionary)["sequence"] as int
			expect(tracks.has(str(sequence)), "track %d: sequence %x converted" % [track, sequence])
