extends CanvasLayer
## The remake's own boot splash (D21): the user's relief picture is shown reduced
## on a black screen with a vignette; it holds ~3 s, then fades out and hands the
## screen over to the title sequence. The engine's boot splash is off
## (`boot_splash/show_image=false`): this layer starts after the project loads.
##
## While the layer lives, game.gd holds the physics back, so the title sequence
## (its «NAMCO PRESENTS.») starts only after the fade.

signal finished

const SPLASH_PATH := "res://app/boot_splash.png"
const HOLD_SECONDS := 3.0     ## the picture's time on screen
const FADE_SECONDS := 0.8     ## the fade-out into the title sequence
## The picture's frame as screen anchors (resolution-independent): 55 % of the
## width, centred a little above the middle (the base's weight).
const FRAME_ANCHORS := Vector4(0.225, 0.2, 0.775, 0.76)
const VIGNETTE_CODE := "
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	COLOR = vec4(0.0, 0.0, 0.0, 0.9 * smoothstep(0.4, 1.35, d));
}
"

var _root: Control


func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var img := Image.load_from_file(SPLASH_PATH)
	if img == null:
		# No picture: no splash at all, the title sequence starts at once.
		_done()
		return
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)
	# The frame box (anchors), the relief as large as fits it, centred.
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.anchor_left = FRAME_ANCHORS.x
	frame.anchor_top = FRAME_ANCHORS.y
	frame.anchor_right = FRAME_ANCHORS.z
	frame.anchor_bottom = FRAME_ANCHORS.w
	_root.add_child(frame)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   ## not the texture's native size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(rect)
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var code := Shader.new()
	code.code = VIGNETTE_CODE
	var material := ShaderMaterial.new()
	material.shader = code
	vignette.material = material
	_root.add_child(vignette)
	var tween := create_tween()
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(_done)


func _done() -> void:
	finished.emit()
	queue_free()
