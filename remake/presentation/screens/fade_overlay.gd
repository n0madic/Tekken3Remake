class_name FadeOverlay
extends Control
## Full-screen fades with the semantics of FUN_8004E2E8 (draw_sim.fade): level 0x100 draws
## nothing, below it a subtractive grey of 255 − level darkens, above it an additive grey of
## level − 0x100 brightens (at most 255). Several fades of one frame are applied in order.

const NEUTRAL := 0x100
const MAX_LEVEL := 0x1FF

var _rects: Array[ColorRect] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_levels(levels: PackedInt32Array) -> void:
	while _rects.size() < levels.size():
		var r := ColorRect.new()
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = CanvasItemMaterial.new()
		add_child(r)
		_rects.append(r)
	for i in _rects.size():
		var r := _rects[i]
		if i >= levels.size() or levels[i] == NEUTRAL:
			r.visible = false
			continue
		var level := mini(levels[i], MAX_LEVEL)
		var material := r.material as CanvasItemMaterial
		var v := 0.0
		if level < NEUTRAL:
			v = (0xFF - level) / 255.0
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		else:
			v = (level - NEUTRAL) / 255.0
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		r.color = Color(v, v, v, 1.0)
		r.visible = true
