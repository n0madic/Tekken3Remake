class_name ScreenData
extends RefCounted
## The attract loop's 2D screen data (`imported/screens/`, tools/remake_import/screens.py):
## the title pictures, texts with their original font, colour and position on the 368 × 480
## screen, and the text colours.


class Text:
	var text: String
	var font: int
	var colour: int
	var at: Vector2i


var directory: String
var screen := Vector2i(368, 480)
var presents: Array[Text] = []
var prompts: Array[Text] = []        ## no pad, P1, P2, both; `at.x` is the centre
var copyright: Array[Text] = []
var logo_at: Vector2i
var font_advance := PackedInt32Array()
var font_height := PackedInt32Array()
var colours: Array = []              ## per font, per colour: [top, bottom, outline] Color


static func load_from(dir: String) -> ScreenData:
	var data: Dictionary = JsonFile.read(dir.path_join("screens.json"))
	var s := ScreenData.new()
	s.directory = dir
	var size := JsonFile.ints(data.get("screen", [368, 480]))
	s.screen = Vector2i(size[0], size[1])
	for f: Dictionary in data.get("fonts", []):
		var advance: int = f["advance"]
		var height: int = f["height"]
		s.font_advance.append(advance)
		s.font_height.append(height)
	var presents: Dictionary = data.get("presents", {})
	var at := JsonFile.ints(presents.get("at", [0, 0]))
	var x := at[0]
	var presents_font: int = presents.get("font", 0)
	for part: Dictionary in presents.get("parts", []):
		var colour: int = part["colour"]
		var t := _text(str(part["text"]), presents_font, colour, Vector2i(x, at[1]))
		s.presents.append(t)
		x += t.text.length() * s.font_advance[t.font]
	var prompts: Dictionary = data.get("start_prompts", {})
	var prompt_font: int = prompts.get("font", 0)
	var prompt_colour: int = prompts.get("colour", 5)
	var centre: int = prompts.get("centre_x", 184)
	var prompt_y: int = prompts.get("y", 0)
	for p: Dictionary in prompts.get("texts", []):
		s.prompts.append(_text(str(p["text"]), prompt_font, prompt_colour, Vector2i(centre, prompt_y)))
	for c: Dictionary in data.get("copyright", []):
		var a := JsonFile.ints(c["at"])
		var font: int = c["font"]
		var colour: int = c["colour"]
		s.copyright.append(_text(str(c["text"]), font, colour, Vector2i(a[0], a[1])))
	var logo := JsonFile.ints(data.get("logo_at", [0, 0]))
	s.logo_at = Vector2i(logo[0], logo[1])
	for font: Array in data.get("text_colours", []):
		var palette: Array = []
		for entry: Array in font:
			var colours: Array[Color] = []
			for rgb: Array in entry:
				var c := JsonFile.ints(rgb)
				colours.append(Color8(c[0], c[1], c[2]))
			palette.append(colours)
		s.colours.append(palette)
	return s


static func _text(text: String, font: int, colour: int, at: Vector2i) -> Text:
	var t := Text.new()
	t.text = text
	t.font = font
	t.colour = colour
	t.at = at
	return t


## The centre x of a left-aligned original text run (the original font is fixed-pitch).
func run_centre(t: Text) -> float:
	var text := t.text
	var lead := text.length() - text.lstrip(" ").length()
	var body := text.strip_edges().length()
	return t.at.x + font_advance[t.font] * (lead + body / 2.0)


## Fill and outline colours of a text colour: the glyph gradient's upper part, the outline.
func text_colour(font: int, colour: int) -> Array[Color]:
	var entry: Array = colours[font][colour]
	var top: Color = entry[0]
	var bottom: Color = entry[1]
	var outline: Color = entry[2]
	return [top.lerp(bottom, 0.25), outline]
