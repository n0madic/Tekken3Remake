extends TestSuite
## The game texts in English (TextLocale): the project's generic wording replaces a string's body
## within its block and keeps its format codes; with the USA conversion (imported/usa) the names,
## the staff roll and the move lists follow, and GameRam and FlowData show them.

const DOCTOR_B := 0x800225D4          ## exe: the Japanese release's "DOCTOR.B."


func test_generic_wording() -> void:
	var t := TextLocale.load_from("res://no_such_folder")
	expect_equal(t.text("force", "%f%c%H%VLIFE UP!"), "%f%c%H%VLIFE UP!", "Japanese while English is off")
	t.english = true
	expect_equal(t.text("force", "%f%c%H%VLIFE UP!"), "%f%c%H%V +LIFE!", "the body replaced, the codes kept")
	expect_equal(t.text("title", "%f%c%H%VLIFE UP!"), "%f%c%H%VLIFE UP!", "only in its own block")
	expect_equal(t.text("practice", "FREEZE SIGNAL"), "HIT ANALYSIS", "a practice label")
	var d: Variant = t.texts("practice", {"a": ["TECH ROLL u", "OFF"], "b": "FREE"})
	expect_equal(d, {"a": ["QUICK ROLL u", "OFF"], "b": "1P FREESTYLE"}, "lists and dictionaries")
	expect_equal(t.theater_line(7), "RETURN TO TITLE SCREEN", "a generic Theater line")
	expect_equal(t.theater_line(0), "", "a line with a name needs the USA disc")
	expect(not t.has_usa(), "no USA conversion here")
	expect_equal(t.usa_file("move_glyphs.png"), "", "no USA files")


func test_usa_conversion() -> void:
	if not DirAccess.dir_exists_absolute(AssetCatalog.ROOT.path_join("usa")):
		skip("run tools/remake_import/convert.py with the USA image first")
		return
	var t := TextLocale.load_from(AssetCatalog.ROOT)
	t.english = true
	expect(t.has_usa(), "the USA conversion is found")
	if not Assets.japanese_texts():
		_usa_source(t)
		return
	expect_equal(t.text("exe", "DOCTOR.B."), "DOCTOR B.", "a name from the disc")
	expect(t.staff_rows.size() > 100, "the USA staff roll (%d rows)" % t.staff_rows.size())
	expect(not t.theater_line(0).is_empty(), "the Theater's first line")
	var ram := GameRam.load_from(AssetCatalog.ROOT.path_join("screens"))
	expect_equal(ram.string(DOCTOR_B), "DOCTOR.B.", "GameRam without a locale")
	ram.locale = t
	expect_equal(ram.string(DOCTOR_B), "DOCTOR B.", "GameRam in English")
	var flow := FlowData.load_from(AssetCatalog.ROOT.path_join("tables/flow.json"))
	var japanese_rows := flow.staff_rows
	flow.localize(t)
	expect_equal(flow.practice_texts["freeze"], "HIT ANALYSIS", "FlowData's practice label")
	expect(flow.staff_rows != japanese_rows, "the USA staff roll replaces the Japanese one")
	t.english = false
	flow.localize(t)
	expect_equal(flow.staff_rows, japanese_rows, "back to the Japanese staff roll")
	var content := FightContent.load_from(AssetCatalog.ROOT)
	content.locale = t
	var japanese := content.move_text(0)
	t.english = true
	expect(content.move_text_english(0), "costume 0 has an English list")
	var english := content.move_text(0)
	expect(english != japanese and not english.is_empty(), "the English list is another one")
	expect_equal(english[0], japanese[0], "with the same number of moves")


## Converted from the USA disc: the game's own texts are English, and the USA files are there.
func _usa_source(t: TextLocale) -> void:
	var ram := GameRam.load_from(AssetCatalog.ROOT.path_join("screens"))
	expect_equal(ram.string(DOCTOR_B), "DOCTOR B.", "the name is the USA's own")
	expect(t.staff_rows.size() > 100, "the USA staff roll (%d rows)" % t.staff_rows.size())
	var content := FightContent.load_from(AssetCatalog.ROOT)
	content.locale = t
	expect(content.move_text_english(0), "costume 0's list is the USA's")
	expect(not content.move_text(0).is_empty(), "and it is there")
