class_name AssetCatalog
extends Node
## The converted game data in `res://imported/` (autoload `Assets`).
##
## The folder is produced once by `tools/remake_import/convert.py` and packed into the
## PCK at export. `manifest.json` records which optional groups (music, movies, the USA
## localization) the conversion produced; lite builds exclude music and movies by export filters.

const ROOT := "res://imported/"
const MANIFEST := ROOT + "manifest.json"
## The converter output this build reads (tools/remake_import/common.py CONVERTER_VERSION); an
## older conversion counts as missing, so the game asks for a new one instead of misreading it.
const CONVERTER_VERSION := 2
## The message of the entry points when the converted assets are missing (translated as
## MISSING_ASSETS where the translations are imported).
const MISSING_TEXT := "Converted assets are missing.\nRun: python3 tools/remake_import/convert.py"

var manifest: Dictionary = {}


## MISSING_TEXT in the interface language; as written before the project's first import, which
## brings the translations.
static func missing_message() -> String:
	var translated := str(TranslationServer.translate(&"MISSING_ASSETS"))
	return MISSING_TEXT if translated == "MISSING_ASSETS" else translated


func _ready() -> void:
	reload()


func reload() -> void:
	manifest = {}
	if not FileAccess.file_exists(MANIFEST):
		Log.warning("Assets: %s is missing; run tools/remake_import/convert.py" % MANIFEST)
		return
	var data: Variant = JsonFile.read(MANIFEST)
	if not data is Dictionary:
		return
	var version := JsonFile.number((data as Dictionary).get("converter_version", 0))
	if version != CONVERTER_VERSION:
		Log.warning("Assets: %s was written by converter version %d, this build reads version %d; run tools/remake_import/convert.py again" % [MANIFEST, version, CONVERTER_VERSION])
		return
	manifest = data


func is_available() -> bool:
	return not manifest.is_empty()


## Whether an optional group was converted and is present in this build.
func has_group(group: String) -> bool:
	var groups: Dictionary = manifest.get("groups", {})
	if not groups.get(group, false):
		return false
	match group:
		"music", "movies", "usa":
			return DirAccess.dir_exists_absolute(ROOT + group)
	return true


## The release the game was converted from (tools/remake_import/common.py RELEASES): its data is
## in Japan Rev.1's layout whichever it is.
func source() -> String:
	return str(manifest.get("source", "jp_rev1"))


## Whether the Japanese release's texts were converted (not when the game came from the USA disc,
## whose texts are English).
func japanese_texts() -> bool:
	return source() != "usa"


func path(relative: String) -> String:
	return ROOT + relative


func list(key: String) -> PackedStringArray:
	var items: Array = manifest.get(key, [])
	return PackedStringArray(items)
