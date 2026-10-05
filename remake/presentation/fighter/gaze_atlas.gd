class_name GazeAtlas
extends RefCounted
## Gon's eyes' look direction on his atlas (tools/remake_import/gaze.py, 3dmk-models.md): the
## game shifts the texture strips of his eyes in VRAM; the converter writes the atlas rectangles
## any shift changes, for each shift, into one sheet, and this class pastes them over the atlas
## (the one with his head palette as loaded or swapped) into a texture of its own, for the two
## eyes' current shifts. A pack's replacement of the atlas may be larger: the patches are scaled
## to it (DuckStation's packs do not know the shifted pictures either).

const NO_SHIFT := 99              ## an eye whose strip was never copied shows the atlas as it is
const SHEET_WIDTH := 1024         ## the converter's sheet (gaze.SHEET_WIDTH)

var texture: ImageTexture                 ## the atlas with the patches, updated in place
var _size := Vector2i()                   ## the atlas's size at the converter's scale
var _patches: Dictionary = {}
var _bases: Array[Image] = []             ## the atlas with the head palette as loaded, swapped
var _sheet: Image
var _sheet_scale := 1.0
var _scale := 1.0
var _work: Image
var _swapped := false
var _shifts := PackedInt32Array([NO_SHIFT, NO_SHIFT])


func _init(data: Dictionary, open: Texture2D, swapped: Texture2D, sheet: Texture2D) -> void:
	var size := JsonFile.ints(data["size"])
	_size = Vector2i(size[0], size[1])
	_patches = data["patches"]
	_bases.append(_rgba(open.get_image()))
	_bases.append(_rgba(swapped.get_image()))
	# A texture pack may replace one atlas and not the other: the texture, the patches' scale and
	# the working picture all follow the atlas as loaded, the other is scaled to it.
	if _bases[1].get_size() != _bases[0].get_size():
		_bases[1].resize(_bases[0].get_width(), _bases[0].get_height(), Image.INTERPOLATE_NEAREST)
	_sheet = _rgba(sheet.get_image())
	_scale = float(_bases[0].get_width()) / float(_size.x)
	_sheet_scale = float(_sheet.get_width()) / float(SHEET_WIDTH)


## The texture for the head palette (`swapped`) and each eye's shift (NO_SHIFT: as loaded).
func show(swapped: bool, shifts: PackedInt32Array) -> ImageTexture:
	var changed := false
	if _work == null or swapped != _swapped:
		_swapped = swapped
		_work = Image.new()
		_work.copy_from(_bases[1 if swapped else 0])
		_shifts = PackedInt32Array([NO_SHIFT, NO_SHIFT])
		changed = true
	for eye in 2:
		if shifts[eye] != _shifts[eye]:
			_paste(eye, shifts[eye])
			_shifts[eye] = shifts[eye]
			changed = true
	if texture == null:
		texture = ImageTexture.create_from_image(_work)
	elif changed:
		texture.update(_work)
	return texture


## The picture the texture shows (tests read it: a headless renderer keeps no copy of a texture).
func image() -> Image:
	return _work


## Eye `eye`'s rectangles with the pictures of `shift`, or of the atlas as it is for NO_SHIFT.
func _paste(eye: int, shift: int) -> void:
	var patch: Variant = (_patches.get(str(int(_swapped)), {}) as Dictionary).get(str(eye))
	if patch == null:
		return
	var rects: Array = (patch as Dictionary)["rects"]
	var from: Array = [] if shift == NO_SHIFT else (((patch as Dictionary)["shifts"] as Dictionary)[str(shift)] as Array)
	for i in rects.size():
		var r := JsonFile.ints(rects[i] as Array)
		var target := Rect2i(Vector2i(roundi(r[0] * _scale), roundi(r[1] * _scale)),
				Vector2i(roundi(r[2] * _scale), roundi(r[3] * _scale)))
		var picture: Image
		if shift == NO_SHIFT:
			picture = _bases[1 if _swapped else 0].get_region(target)
		else:
			var at := JsonFile.ints(from[i] as Array)
			picture = _sheet.get_region(Rect2i(Vector2i(roundi(at[0] * _sheet_scale), roundi(at[1] * _sheet_scale)),
					Vector2i(roundi(r[2] * _sheet_scale), roundi(r[3] * _sheet_scale))))
			if picture.get_size() != target.size:
				picture.resize(target.size.x, target.size.y, Image.INTERPOLATE_NEAREST)
		_work.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), target.position)


static func _rgba(image: Image) -> Image:
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
