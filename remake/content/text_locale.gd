class_name TextLocale
extends RefCounted
## The game's texts in English (remake-plan.md, "Game texts"): the remake plays as Japan Rev.1
## and, when English is on, shows the USA release's English wherever it has one. The generic
## interface wording is the project's own (`content/texts_en.json`); names, titles, the staff
## roll, the Theater's lines, the move lists and the pictures with text come from the USA disc
## (`imported/usa/`, tools/remake_import/usa.py) and are used when it was converted.
##
## Strings are replaced by their body (the text after its leading `%x` format codes) within the
## game memory block they come from, so a string keeps its own codes.

const STATIC_PATH := "res://content/texts_en.json"
const USA_DIR := "usa"
const THEATER_LINES := 8

var english := false
var blocks: Dictionary = {}          ## block name → {Japanese body: English body}
var theater_help := PackedStringArray()   ## the USA help lines by the Japanese strip index ("" none)
var practice_prompt := ""            ## the recording prompt (drawn with a down arrow for `d`)
var record_rank := "%d%s"            ## the records' rank format
var staff_titles := PackedStringArray()   ## the USA staff roll, empty without the conversion
var staff_rows := PackedStringArray()
var usa_dir := ""                    ## the converted USA folder, "" when missing


## The project's wording and, when `imported_root` has it, the converted USA localization.
static func load_from(imported_root: String) -> TextLocale:
	var t := TextLocale.new()
	t.theater_help.resize(THEATER_LINES)
	t.theater_help.fill("")
	t._merge(JsonFile.read(STATIC_PATH) as Dictionary)
	var dir := imported_root.path_join(USA_DIR)
	if FileAccess.file_exists(dir.path_join("texts.json")):
		t.usa_dir = dir
		var usa: Dictionary = JsonFile.read(dir.path_join("texts.json"))
		t._merge(usa)
		t.staff_titles = PackedStringArray(usa.get("staff_titles", []) as Array)
		t.staff_rows = PackedStringArray(usa.get("staff_rows", []) as Array)
	return t


func _merge(d: Dictionary) -> void:
	var more: Dictionary = d.get("blocks", {})
	for block: String in more:
		if not blocks.has(block):
			blocks[block] = {}
		(blocks[block] as Dictionary).merge(more[block] as Dictionary, true)
	var help: Array = d.get("theater_help", [])
	for i in mini(help.size(), THEATER_LINES):
		if not str(help[i]).is_empty():
			theater_help[i] = str(help[i])
	practice_prompt = str(d.get("practice_prompt", practice_prompt))
	record_rank = str(d.get("record_rank", record_rank))


## Whether the converted USA localization is present (move lists, pictures, names).
func has_usa() -> bool:
	return not usa_dir.is_empty()


## A string of `block` as shown: its English when English is on and one is known.
func text(block: String, s: String) -> String:
	if not english:
		return s
	var table: Dictionary = blocks.get(block, {})
	if table.is_empty():
		return s
	var i := 0
	while i + 1 < s.length() and s[i] == "%" and _is_letter(s.unicode_at(i + 1)):
		i += 2
	var key := s.substr(i)
	return s.substr(0, i) + str(table[key]) if table.has(key) else s


## `value` (a string, or arrays and dictionaries of them) with each string localized.
func texts(block: String, value: Variant) -> Variant:
	if value is String:
		return text(block, value as String)
	if value is Array:
		var out: Array = []
		for v: Variant in value as Array:
			out.append(texts(block, v))
		return out
	if value is PackedStringArray:
		var out := PackedStringArray()
		for v: String in value as PackedStringArray:
			out.append(text(block, v))
		return out
	if value is Dictionary:
		var out := {}
		var d: Dictionary = value
		for k: Variant in d:
			out[k] = texts(block, d[k])
		return out
	return value


## The Theater's help line for strip `k` in English, or "" (the Japanese picture strip).
func theater_line(k: int) -> String:
	return theater_help[k] if english and k >= 0 and k < theater_help.size() else ""


## A converted USA file (`usa/<name>`) when English is on and it exists, else "".
func usa_file(name: String) -> String:
	if not english or usa_dir.is_empty():
		return ""
	var path := usa_dir.path_join(name)
	return path if FileAccess.file_exists(path) or ResourceLoader.exists(path) else ""


## The converted USA file `name` when English is on and it exists, else `fallback` (the Japanese
## release's).
func file_or(name: String, fallback: String) -> String:
	var english := usa_file(name)
	return english if not english.is_empty() else fallback


static func _is_letter(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
