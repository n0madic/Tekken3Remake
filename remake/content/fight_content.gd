class_name FightContent
extends RefCounted
## The converted assets a fight needs (`res://imported/`): the fight tables, the motion banks
## by bank type with their linked move rows (linked once, with the common bank) and the
## character models by costume slot, loaded when first used.

const MOTION := "motion"
const COMMON_BANK := "divmot99"
const STAGE_LETTERS := "abcdefgnijklmtupqrsv"   ## stage number → letter (stages.md)

var root: String
var tables: FightTables
var common: MotionBank
var common_rows: Array[MoveRow] = []
var _banks: Dictionary = {}          ## bank type → MotionBank
var _rows: Dictionary = {}           ## bank type → Array[MoveRow]
var _models: Dictionary = {}         ## costume slot → CharacterModel
var _stages: Dictionary = {}         ## stage letter → StageData
var _move_texts: Dictionary = {}     ## file path → PackedByteArray
var _move_paths: Dictionary = {}     ## costume slot → _move_text_path, for _move_paths_locale / _english
var _move_paths_locale: TextLocale
var _move_paths_english := false
var _screens_ram: GameRam            ## the memory images the mode RAMs share, read once
var _mode_rams: Dictionary = {}      ## mode overlay name → GameRam
var locale: TextLocale               ## the texts' language for the mode overlays' strings (null: Japanese)


static func load_from(folder: String) -> FightContent:
	var c := FightContent.new()
	c.root = folder
	c.tables = FightTables.load_from(folder.path_join("tables"))
	c.common = MotionBank.load_named(folder.path_join(MOTION), COMMON_BANK)
	c.common_rows = c.common.link(c.common, c.tables.builtin_attack_ids)
	return c


## The motion bank of a bank type (divmot<type>).
func bank(bank_type: int) -> MotionBank:
	if not _banks.has(bank_type):
		var b := MotionBank.load_named(root.path_join(MOTION), "divmot%02d" % bank_type)
		_banks[bank_type] = b
		_rows[bank_type] = b.link(common, tables.builtin_attack_ids)
	return _banks[bank_type]


## The linked move rows of a bank type.
func rows(bank_type: int) -> Array[MoveRow]:
	bank(bank_type)
	return _rows[bank_type]


## The model of a costume slot.
func model(costume_slot: int) -> CharacterModel:
	if not _models.has(costume_slot):
		_models[costume_slot] = CharacterModel.load_from(root.path_join("characters/costume_%02d" % costume_slot))
	return _models[costume_slot]


## The converted stage of a letter (STAGE_LETTERS, or the attract demonstration's), loaded once:
## the fights, the ranking's backdrop and the demonstration share it (the views do not change it).
func stage(letter: String) -> StageData:
	if not _stages.has(letter):
		_stages[letter] = StageData.load_from(root.path_join("stages/" + letter))
	return _stages[letter]


## The stage of a stage number (out of range: the nearest one).
func stage_number(number: int) -> StageData:
	return stage(STAGE_LETTERS[clampi(number, 0, STAGE_LETTERS.length() - 1)])


## The game's memory image with a mode overlay (`force`, `volley`) in its slot: the overlay's
## tables and initial data, read by address.
func mode_ram(overlay: String) -> GameRam:
	if not _mode_rams.has(overlay):
		if _screens_ram == null:
			_screens_ram = GameRam.load_from(root.path_join("screens"))
		var ram := _screens_ram.fresh()
		ram.locale = locale
		ram.load_overlay(overlay)
		_mode_rams[overlay] = ram
	return _mode_rams[overlay]


## Tekken Force's level script of a stage (stage ARC member 3; empty for other stages).
func level_script(stage: int) -> PackedByteArray:
	var path := root.path_join("stages/%s/level.bin" % STAGE_LETTERS[stage]) if stage < STAGE_LETTERS.length() else ""
	return FileAccess.get_file_as_bytes(path) if path != "" and FileAccess.file_exists(path) else PackedByteArray()


## The move list of a costume slot (ARC member 4: a count, then name / command strings), empty
## when the slot has none: the USA release's English one when English is on and it was converted
## (its own encoding, move_text_english), else the Japanese one (the English one when the game
## was converted from the USA disc, which has no other).
func move_text(costume_slot: int) -> PackedByteArray:
	var path := _move_text_path(costume_slot)
	if not _move_texts.has(path):
		_move_texts[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	return _move_texts[path]


## Whether move_text gives the USA encoding for this costume.
func move_text_english(costume_slot: int) -> bool:
	return _move_text_path(costume_slot) == _usa_path(costume_slot)


func _usa_path(costume_slot: int) -> String:
	return root.path_join(TextLocale.USA_DIR).path_join("move_lists/costume_%02d.bin" % costume_slot)


## The move list file of a costume slot, remembered while the locale and its English flag stay.
func _move_text_path(costume_slot: int) -> String:
	var english := locale != null and locale.english
	if locale != _move_paths_locale or english != _move_paths_english:
		_move_paths.clear()
		_move_paths_locale = locale
		_move_paths_english = english
	if not _move_paths.has(costume_slot):
		_move_paths[costume_slot] = _find_move_text(costume_slot)
	return _move_paths[costume_slot] as String


func _find_move_text(costume_slot: int) -> String:
	var japanese := root.path_join("characters/costume_%02d/move_list.bin" % costume_slot)
	var english := _usa_path(costume_slot)
	var usa_on := locale != null and locale.english and not locale.usa_dir.is_empty()
	if (usa_on or not FileAccess.file_exists(japanese)) and FileAccess.file_exists(english):
		return english
	return japanese