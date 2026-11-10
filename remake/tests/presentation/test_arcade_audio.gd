extends TestSuite
## SectionMusic's decisions that need no files: the music's cues, and its sections on made-up ones.


const CUES := [2.0, 4.0, 6.0]


func _crossed(before: float, now: float) -> float:
	return SectionMusic._crossed_cue(PackedFloat32Array(CUES), before, now)


func test_a_cue_counts_when_the_position_passes_it() -> void:
	expect_equal(_crossed(1.0, 1.5), -1.0)
	expect_equal(_crossed(1.5, 2.0), 2.0)
	expect_equal(_crossed(2.0, 2.5), -1.0, "the position it was at does not count again")
	expect_equal(_crossed(3.9, 4.1), 4.0)


func test_a_loops_return_passes_the_cues_on_both_sides() -> void:
	expect_equal(_crossed(5.9, 1.0), 6.0, "before the return")
	expect_equal(_crossed(6.5, 2.5), 2.0, "after the return")
	expect_equal(_crossed(6.5, 1.0), -1.0, "none in between")


func test_the_written_sections_go_1_2_3_then_2_and_3() -> void:
	var order: Array[int] = []
	var section := 0
	for i in 6:
		section = SectionMusic.next_section(section)
		order.append(section)
	expect_equal(order, [1, 2, 3, 2, 3, 2] as Array[int])


func test_sections_are_found_by_number() -> void:
	var audio := SectionMusic.new()
	var first := SectionMusic.Section.new()
	first.number = 1
	audio._track = [first]
	expect_equal(audio._section_numbered(1), first)
	expect_equal(audio._section_numbered(2), null)
	audio.free()


## SectionMusic on a clock of its own and silent files: what it starts, and when.
class ClockedSections extends SectionMusic:
	var now := 0.0
	var started: Dictionary = {}       ## file → the time it started

	func _request(_part: Part) -> void:
		pass

	func _music_stream(part: Part) -> AudioStream:
		started[part.file] = now
		var stream := AudioStreamWAV.new()
		stream.mix_rate = 8000
		stream.data = PackedByteArray()
		stream.data.resize(16000)
		return stream

	func _position(_lane: Lane) -> float:
		return now


func _part(file: String, cue: float, delay: float, length := 2.0) -> Dictionary:
	return {"file": file, "length": length, "loop": 0.0, "delay": delay, "cues": [cue]}


## Where a BGM's channels go into a section at different bars (the gated ones a bar after those that
## test the section variable itself), each part's file changes at its own bar, after its own delay.
func test_each_part_changes_section_at_its_own_bar() -> void:
	var music := ClockedSections.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	music.available = true
	music.load_table({"tracks": {"16": {"sections": [
		{"section": 0, "parts": [_part("main_0", 1.0, 0.0), _part("lead_0", 0.5, 0.0)]},
		{"section": 1, "parts": [_part("main_1", 1.0, 0.25), _part("lead_1", 0.5, 0.0)]},
	]}}})
	music.play(16)
	expect_equal(music.started.keys(), ["main_0", "lead_0"])
	music.write(1)
	var section_at_lead := -1
	for step in 90:
		music.now = step / 60.0
		music.advance(2)
		if music.started.has("lead_1") and section_at_lead < 0:
			section_at_lead = music._current.number
	expect(is_equal_approx(music.started.get("lead_1", -1.0) as float, 0.5), "the lead at its cue")
	expect(is_equal_approx(music.started.get("main_1", -1.0) as float, 1.0), "the others at theirs, after the gate")
	expect_equal(section_at_lead, 0, "the section is reached when every part has gone over")
	expect_equal(music._current.number, 1)
	music.stop()
	music.free()


## Started in a section (the PlayStation's True Ogre track), the parts play together: one whose
## channels went into it earlier (a longer file, as every part ends at the same tick) is that much
## further into its file.
func test_parts_started_in_a_section_play_together() -> void:
	var music := ClockedSections.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	music.available = true
	music.load_table({"tracks": {"16": {"sections": [
		{"section": 0, "parts": [_part("main_0", 1.0, 0.0), _part("lead_0", 0.5, 0.0)]},
		{"section": 1, "parts": [_part("main_1", 1.0, 0.25), _part("lead_1", 0.5, 0.0, 2.5)]},
	]}}})
	music.play(16)
	expect_equal([music._lanes[0].last_position, music._lanes[1].last_position], [0.0, 0.0], "the intro")
	music.play(16, 1)
	expect_equal(music._lanes[0].last_position, 0.0)
	expect_equal(music._lanes[1].last_position, 0.5, "the lead a bar into its file")
	music.stop()
	music.free()


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
			for part: Dictionary in row["parts"] as Array:
				var name := "%x section %d, %s" % [sequence, row["section"] as int, part["file"] as String]
				expect(not (part["cues"] as Array).is_empty(), "%s: cues" % name)
				expect(part["loop"] != null, "%s: loops" % name)
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
