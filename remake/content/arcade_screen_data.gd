class_name ArcadeScreenData
extends RefCounted
## The arcade screens' numbers and pictures (`imported/screens/arcade/`,
## tools/remake_import/arcade_screens.py, whose docstring is the format). Nothing is read from an
## executable image: every string and layout number the draw routines use is in this file.

const FOLDER := "arcade"
const FILE := "screens.json"
const NONE := 0x16
const COSTUMES := 4

var directory := ""
var width := 0
var height := 0
var texts: Dictionary = {}
var prompts: Dictionary = {}
var title: Dictionary = {}
var select: Dictionary = {}
var vs: Dictionary = {}
var ranking: Dictionary = {}
var banner: Dictionary = {}
var ending: Dictionary = {}
var hud: Dictionary = {}
var characters: Array = []
var attributes: Array = []
var default_attribute: Dictionary = {}


static func load_from(dir: String) -> ArcadeScreenData:
	var out := ArcadeScreenData.new()
	out.directory = dir.path_join(FOLDER)
	var d: Dictionary = JsonFile.read(out.directory.path_join(FILE))
	out.width = JsonFile.number(d["width"])
	out.height = JsonFile.number(d["height"])
	out.texts = d["texts"]
	out.prompts = d["prompts"]
	out.title = d["title"]
	out.select = d["select"]
	out.vs = d["vs"]
	out.ranking = d["ranking"]
	out.banner = d["banner"]
	out.ending = d["ending"]
	out.hud = d["hud"]
	out.characters = d["characters"]
	var attribute_set: Dictionary = d["attributes"]
	out.attributes = attribute_set["keys"]
	out.default_attribute = attribute_set["default"]
	return out


## A picture of the screens, or the chosen texture pack's replacement of it.
func texture(file: String) -> Texture2D:
	return TexturePacks.texture(directory.path_join(file))


## The runs of a text: {text, font, colour, x, y}.
func text_runs(key: String) -> Array:
	return texts[key]


## A costume key's record: name, plate, face, ...
func character(key: int) -> Dictionary:
	return characters[key]


## The (x, y) of a pair of the file.
static func point_of(values: Variant) -> Vector2i:
	var parts: Array = values
	var x: int = parts[0]
	var y: int = parts[1]
	return Vector2i(x, y)


## FUN_801BE510: the portrait's attribute of a character in a costume; none shows the white figure.
func attribute(character_id: int, costume: int) -> Dictionary:
	if character_id >= NONE:
		return default_attribute
	return attributes[character_id * COSTUMES + costume]


## An [r, g, b] of the file.
static func colour_of(values: Variant) -> Color:
	var parts: Array = values
	var r: int = parts[0]
	var g: int = parts[1]
	var b: int = parts[2]
	return Color8(r, g, b)
