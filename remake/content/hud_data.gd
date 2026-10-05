class_name HudData
extends RefCounted
## The fight HUD's sprites (`imported/hud/`, tools/remake_import/hud.py): bar caps and fills,
## round marks, timer digits, name plates and names, and the text engine's glyph sheets per
## font and colour. Textures load when first used.

class FontInfo:
	var advance: int
	var line: int
	var width: int
	var height: int
	var first: int
	var columns: int

var directory: String
var names: Dictionary = {}           ## costume slot (string) → {file, width, plate}
var fonts: Dictionary = {}           ## font → FontInfo


static func load_from(dir: String) -> HudData:
	var h := HudData.new()
	h.directory = dir
	var data: Dictionary = JsonFile.read(dir.path_join("hud.json"))
	h.names = data.get("names", {})
	var fonts: Dictionary = data.get("fonts", {})
	for key: String in fonts:
		var f: Dictionary = fonts[key]
		var info := FontInfo.new()
		info.advance = JsonFile.number(f["advance"])
		info.line = JsonFile.number(f["line"])
		info.width = JsonFile.number(f["width"])
		info.height = JsonFile.number(f["height"])
		info.first = JsonFile.number(f["first"])
		info.columns = JsonFile.number(f["columns"])
		h.fonts[key.to_int()] = info
	return h


## A picture of the HUD, or the chosen texture pack's replacement of it.
func texture(file: String) -> Texture2D:
	return TexturePacks.texture(directory.path_join(file))


## The name sprite of a costume slot and its width, or null.
func name_texture(slot: int) -> Texture2D:
	var entry: Variant = names.get(str(slot))
	return texture(str((entry as Dictionary)["file"])) if entry is Dictionary else null


func name_width(slot: int) -> int:
	var entry: Variant = names.get(str(slot))
	return JsonFile.number((entry as Dictionary)["width"]) if entry is Dictionary else 0


func plate_texture(slot: int) -> Texture2D:
	var entry: Variant = names.get(str(slot))
	return texture(str((entry as Dictionary)["plate"])) if entry is Dictionary else null


func glyphs(font: int, colour: int) -> Texture2D:
	return texture("font_%d_%d.png" % [font, colour])
