class_name AttractScreen
extends Control
## Draws the attract loop's 2D screens in vector form: the transition screen's
## `NAMCO PRESENTS.` and the title picture with its prompt, logo and copyright
## (FUN_8004FA38, FUN_800DAAD8). Texts use an open font in the original colours, laid out on
## the original 368 × 480 screen scaled into the window's 4:3 area.

const PICTURE_BLACK := 0
const PICTURE_TITLE_PROMPT := 2
const PICTURE_TITLE_LOGO := 3
const PICTURE_TITLE_COPYRIGHT := 4
const PICTURE_TITLE := 5
const PROMPT_BLINK := 0x30                ## the prompt shows while bit 4 or 5 of the frame counter is set
const TEXT_BOLDNESS := 0.55
const OUTLINE_SHARE := 0.16               ## outline width per font height

var data: ScreenData
var title_texture: Texture2D
var logo_texture: Texture2D
var font := FontVariation.new()
var presents_mode := -1
var presents_level := 0
var picture := -1
var frame_count := 0
var prompt := 1                           ## which start prompt: no pad, P1, P2, both
var _drawn := PackedInt32Array()          ## what the last drawing showed (show_frame redraws on a change)


var enbu_variant := false
var locale: TextLocale                    ## the texts' language (the copyright; the USA title picture)


func setup(screens: ScreenData, enbu: bool) -> void:
	data = screens
	enbu_variant = enbu
	reload_pictures()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = TEXT_BOLDNESS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The title picture of title.ovl, or the copy enbu.ovl shows after the demonstration.
func setup_variant(enbu: bool) -> void:
	if enbu != enbu_variant:
		enbu_variant = enbu
		reload_pictures()


## The pictures of the variant in the texts' language (the USA title picture in English), from
## the texture pack in use.
func reload_pictures() -> void:
	if data == null:
		return
	var suffix := "_enbu" if enbu_variant else ""
	var title := data.directory.path_join("title%s.png" % suffix)
	title_texture = TexturePacks.texture(locale.file_or("title%s.png" % suffix, title) if locale != null else title)
	logo_texture = TexturePacks.texture(data.directory.path_join("namco%s.png" % suffix))
	_drawn = PackedInt32Array()
	queue_redraw()


func set_locale(texts: TextLocale) -> void:
	locale = texts
	if data != null:
		reload_pictures()


func show_frame(presents: int, level: int, kind: int, frames: int) -> void:
	presents_mode = presents
	presents_level = level
	picture = kind
	frame_count = frames
	# Only what the drawing reads: the fade level while the line fades in, the prompt and its blink
	# on the title with the prompt.
	var with_prompt := picture == PICTURE_TITLE_PROMPT
	var shown := PackedInt32Array([presents_mode, presents_level if presents_mode == 0 else 0, picture,
		frame_count & PROMPT_BLINK if with_prompt else 0, prompt if with_prompt else 0])
	if shown != _drawn:
		_drawn = shown
		queue_redraw()


func _draw() -> void:
	if data == null or size.y < 1.0:
		return
	var box := ScreenBox.rect(size)
	if presents_mode >= 0 and presents_mode <= 2:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		if presents_mode != 2:
			var alpha := clampf(presents_level / 256.0, 0.0, 1.0) if presents_mode == 0 else 1.0
			_line(box, data.presents, alpha)
	match picture:
		PICTURE_BLACK:
			draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		PICTURE_TITLE_PROMPT, PICTURE_TITLE_LOGO, PICTURE_TITLE_COPYRIGHT, PICTURE_TITLE:
			draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
			draw_texture_rect(title_texture, box, false)
			if picture == PICTURE_TITLE_PROMPT and frame_count & PROMPT_BLINK:
				var p := data.prompts[clampi(prompt, 0, data.prompts.size() - 1)]
				_text(box, p, p.at.x, 1.0)
			if picture == PICTURE_TITLE_PROMPT or picture == PICTURE_TITLE_LOGO:
				var tl := ScreenBox.point(box, data.screen, data.logo_at.x, data.logo_at.y)
				var logo := logo_texture.get_size()
				var sz := Vector2(logo.x / data.screen.x * box.size.x, logo.y / data.screen.y * box.size.y)
				draw_texture_rect(logo_texture, Rect2(tl, sz), false)
			if picture != PICTURE_TITLE:
				for t in data.copyright:
					_text(box, t, data.run_centre(t), 1.0)


## Consecutive texts of one original line (different colours), centred as the whole run.
func _line(box: Rect2, parts: Array[ScreenData.Text], alpha: float) -> void:
	var size_px := _size_px(box, parts[0])
	var whole := ""
	var shown := ""                   # what _draw_text draws of each part, in the texts' language
	for t in parts:
		whole += t.text
		shown += _shown(t).strip_edges(true, false)
	var run := ScreenData.Text.new()
	run.text = whole
	run.font = parts[0].font
	run.at = parts[0].at
	var width := font.get_string_size(shown.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var x := ScreenBox.point(box, data.screen, data.run_centre(run), 0).x - width / 2.0
	for t in parts:
		x += _draw_text(box, t, x, alpha)


func _size_px(box: Rect2, t: ScreenData.Text) -> int:
	return roundi(data.font_height[t.font] * ScreenBox.line_scale(box, data.screen) * 1.05)


## A text centred on `centre_x` (original x), its top at the original y.
func _text(box: Rect2, t: ScreenData.Text, centre_x: float, alpha: float) -> void:
	var size_px := _size_px(box, t)
	var width := font.get_string_size(_shown(t).strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var left := ScreenBox.point(box, data.screen, centre_x, 0).x - width / 2.0
	_draw_text(box, t, left, alpha)


## A text in the texts' language (the converted texts show the font's @ as ©; the locale knows
## the game's strings).
func _shown(t: ScreenData.Text) -> String:
	if locale == null:
		return t.text
	return locale.text("title", t.text.replace("©", "@")).replace("@", "©")


## Draws a text from window x `left` at its original y; returns its width (with trailing spaces).
func _draw_text(box: Rect2, t: ScreenData.Text, left: float, alpha: float) -> float:
	var size_px := _size_px(box, t)
	var text := _shown(t).strip_edges(true, false)
	var top := ScreenBox.point(box, data.screen, 0, t.at.y)
	var baseline := Vector2(left, top.y + font.get_ascent(size_px) * 0.92)
	var colours := data.text_colour(t.font, t.colour)
	var fill := colours[0]
	var outline := colours[1]
	fill.a = alpha
	outline.a = alpha
	var outline_px := maxi(1, roundi(size_px * OUTLINE_SHARE))
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, outline_px, outline)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, fill)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
