class_name TexturePacks
extends RefCounted
## Replacement texture packs (remake-plan.md, "Graphics modernisation"): a pack is a folder
## `user://texture_packs/<name>/` with a `pack.json` and PNG pictures named after the texture they
## replace: `<key>.png`, the key being the first 16 hex digits of the SHA-256 of the converted
## picture (`imported/texture_index.json`, written by tools/remake_import/convert.py;
## `tools/remake/texture_pack.py dump` writes the originals under their keys). A replacement may
## have any size: the meshes address their textures in normalised coordinates, so a picture
## scaled by n keeps its layout (and the atlases' 2-texel gutters scale with it); 2D pictures keep
## their original size (the texture's size override) and draw their texels finer.
##
## The converted pictures (fighters, stages, HUD, effects' flipbooks, screens) can be replaced.
## The 2D screens cut their sprites from a VRAM image at run time (`VramImage`): a pack's
## `vram.json` lists replacements of VRAM rectangles (`vram/<name>.png`, from
## `texture_pack.py import-duckstation`), each for a texture page, a texel rectangle and the CLUT
## colours it was made for, drawn only while the VRAM holds the words it replaces (their SHA-256).
## Nothing else reads them: the game is unchanged.

const DIR := "user://texture_packs"
const MANIFEST := "pack.json"
const VRAM_INDEX := "vram.json"
const INDEX := "res://imported/texture_index.json"
const ROOT := "res://imported/"
const PAGE_TEXELS := 256

static var directory := DIR                ## where the packs are (tests use their own)
static var _index: Dictionary = {}          ## imported path (relative) → key
static var _loaded := false
static var _textures: Dictionary = {}       ## path → Texture2D (the original or its replacement)
static var _vram_pack := ""                 ## the pack whose vram.json is loaded
static var _vram: Dictionary = {}           ## "page x,page y,depth" → Array of entries (Dictionary)
static var _images: Dictionary = {}         ## VRAM replacement file → Image
## Changes with the chosen pack (`clear`): VRAM images drop the sprites they cut before.
static var generation := 0


## The packs installed: the folders of DIR with a pack.json.
static func installed(dir := directory) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_directories():
		if FileAccess.file_exists(dir.path_join(name).path_join(MANIFEST)):
			out.append(name)
	out.sort()
	return out


## The texture at `path` (res://imported/…), or the chosen pack's replacement of it, reporting the
## original's size.
static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = _load_texture(path)
	return _textures[path] as Texture2D


static func _load_texture(path: String) -> Texture2D:
	var original := load(path) as Texture2D
	var replacement := replacement_file(path, chosen())
	if replacement.is_empty():
		return original
	var image := Image.load_from_file(replacement)
	if image == null or image.is_empty():
		Log.warning("TexturePacks: cannot read %s" % replacement)
		return original
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	if original != null:
		tex.set_size_override(Vector2i(original.get_size()))
	return tex


## Uses a pack for this session (`--texture-pack=`): an installed pack's name, or a pack's folder.
## Choosing a pack in the settings ends it (Settings.set_value).
## An argument with a "/" is a folder (`mypack/`, `./mypack`, an absolute path), else an installed
## pack's name.
static func use_for_session(pack: String) -> void:
	if pack.contains("/"):
		var dir := DirAccess.open(pack)
		if dir == null:
			Log.warning("TexturePacks: no folder %s" % pack)
		var folder := dir.get_current_dir() if dir != null else pack.simplify_path()
		pack = folder if folder.contains("/") else pack  # "./x" stays a folder
	Settings.session["texture_pack"] = pack
	clear()


## The pack in use ("" none): the session's (an installed pack's name or a folder) or the setting's.
static func chosen() -> String:
	return Settings.text("texture_pack")


## The folder of a pack: the session's folder (`use_for_session`, with a "/") as it is, else the
## pack's under `directory` (a saved setting never names a folder elsewhere).
static func pack_dir(pack: String) -> String:
	if pack.contains("/") and Settings.session.get("texture_pack") == pack:
		return pack
	return directory.path_join(pack)


## The replacement file of `path` in `pack` ("" none, or when the pack has no such picture).
static func replacement_file(path: String, pack: String) -> String:
	if pack.is_empty():
		return ""
	var key := key_of(path)
	if key.is_empty():
		return ""
	var file := pack_dir(pack).path_join(key + ".png")
	return file if FileAccess.file_exists(file) else ""


## A converted picture's key ("" when it is not replaceable).
static func key_of(path: String) -> String:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(INDEX):
			_index = JsonFile.read(INDEX)
	return str(_index.get(path.trim_prefix(ROOT), ""))


## The chosen pack's replacement of a w × h sprite at texel (u, v) of the 4- or 8-bit texture
## page at VRAM word (page_x, page_y), through the CLUT at (clut_x, clut_y), or null. Its size is
## w × h; `checks` (the VRAM image's, cleared on each upload) caches the VRAM checks.
static func vram_sprite(vram: VramImage, checks: Dictionary, page_x: int, page_y: int, depth: int,
		u: int, v: int, w: int, h: int, clut_x: int, clut_y: int) -> Texture2D:
	if u + w > PAGE_TEXELS or v + h > PAGE_TEXELS:
		return null
	var entries := _vram_entries(chosen(), "%d,%d,%d" % [page_x, page_y, depth])
	for i in entries.size():
		var e := entries[i] as Dictionary
		var rect := e["rect"] as PackedInt32Array
		if u < rect[0] or v < rect[1] or u + w > rect[0] + rect[2] or v + h > rect[1] + rect[3]:
			continue
		if not _palette_matches(vram, clut_x, clut_y, e["palette"] as PackedInt32Array):
			continue
		var check_key := "%d,%d,%d,%d" % [page_x, page_y, depth, i]
		if not checks.has(check_key):
			checks[check_key] = _words_digest(vram, page_x, page_y, depth, rect) == str(e["check"])
		if not checks[check_key]:
			continue
		var image := _vram_image(str(e["file"]))
		if image == null:
			continue
		var scale := e["scale"] as int
		var source := Rect2i((u - rect[0]) * scale, (v - rect[1]) * scale, w * scale, h * scale)
		if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(source):
			continue
		var region := image.get_region(source)
		var tex := ImageTexture.create_from_image(region)
		tex.set_size_override(Vector2i(w, h))
		return tex
	return null


static func _vram_entries(pack: String, key: String) -> Array:
	if pack != _vram_pack:
		_vram_pack = pack
		_vram.clear()
		_images.clear()
		var file := pack_dir(pack).path_join(VRAM_INDEX)
		if not pack.is_empty() and FileAccess.file_exists(file):
			# Not JsonFile.read (nor JSON.parse_string): a user's broken file is a warning, not an
			# error of the game's data.
			var json := JSON.new()
			var index: Variant = json.data if json.parse(FileAccess.get_file_as_string(file)) == OK else null
			var entries: Variant = (index as Dictionary).get("entries", []) if index is Dictionary else null
			if not entries is Array:
				Log.warning("TexturePacks: %s %s" % [file, "has no entries list" if index != null
					else "is not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]])
				entries = []
			for e: Variant in entries as Array:
				var entry := _vram_entry(e)
				if entry.is_empty():
					Log.warning("TexturePacks: %s: skipped a malformed entry" % file)
					continue
				var page := entry["page"] as PackedInt32Array
				var k := "%d,%d,%d" % [page[0], page[1], entry["depth"] as int]
				if not _vram.has(k):
					_vram[k] = []
				(_vram[k] as Array).append(entry)
	return _vram.get(key, []) as Array


## A vram.json entry with its numbers converted, or {} when a field is missing or out of range (a
## user's pack is not trusted).
static func _vram_entry(e: Variant) -> Dictionary:
	if not e is Dictionary:
		return {}
	var d := e as Dictionary
	for field: String in ["rect", "palette", "page"]:
		if not d.get(field) is Array:
			return {}
	if not (d.get("file") is String and d.get("check") is String) or not _inside_pack(d["file"] as String):
		return {}
	var rect := JsonFile.ints(d["rect"])
	var page := JsonFile.ints(d["page"])
	var scale := JsonFile.number(d.get("scale"))
	var depth := JsonFile.number(d.get("depth"))
	if rect.size() != 4 or page.size() != 2 or scale <= 0 or not depth in [4, 8]:
		return {}
	if rect[0] < 0 or rect[1] < 0 or rect[2] <= 0 or rect[3] <= 0 \
			or rect[0] + rect[2] > PAGE_TEXELS or rect[1] + rect[3] > PAGE_TEXELS:
		return {}
	if page[0] < 0 or page[1] < 0 or page[0] + PAGE_TEXELS * depth / 16 > VramImage.WIDTH \
			or page[1] + PAGE_TEXELS > VramImage.HEIGHT:
		return {}
	return {"rect": rect, "palette": JsonFile.ints(d["palette"]), "page": page, "scale": scale, "depth": depth,
		"file": d["file"], "check": d["check"]}


## Whether a file named by a pack stays inside the pack's folder: relative, no `..`, no
## backslashes or drive letters.
static func _inside_pack(file: String) -> bool:
	if file.is_empty() or not file.is_relative_path() or file.contains("\\") or file.contains(":"):
		return false
	return not ".." in file.simplify_path().split("/")


static func _palette_matches(vram: VramImage, x: int, y: int, palette: PackedInt32Array) -> bool:
	if x + palette.size() > VramImage.WIDTH:
		return false
	for i in palette.size():
		if vram.word(x + i, y) != palette[i]:
			return false
	return true


## SHA-256 of the VRAM words of a texel rectangle (duckstation_pack.py's vram_check).
static func _words_digest(vram: VramImage, page_x: int, page_y: int, depth: int, rect: PackedInt32Array) -> String:
	var per_word := 16 / depth
	var x0 := page_x + rect[0] / per_word
	var width := rect[2] / per_word
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for row in rect[3]:
		var at := 2 * ((page_y + rect[1] + row) * VramImage.WIDTH + x0)
		ctx.update(vram.words.slice(at, at + 2 * width))
	return ctx.finish().hex_encode()


static func _vram_image(file: String) -> Image:
	if not _images.has(file):
		var image := Image.load_from_file(pack_dir(_vram_pack).path_join(file))
		if image != null and not image.is_empty():
			image.convert(Image.FORMAT_RGBA8)
		else:
			Log.warning("TexturePacks: cannot read %s" % file)
			image = null
		_images[file] = image
	return _images[file] as Image


## Drops the loaded replacements (after the pack setting changed).
static func clear() -> void:
	generation += 1
	_textures.clear()
	_vram_pack = ""
	_vram.clear()
	_images.clear()
