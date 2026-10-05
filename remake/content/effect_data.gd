class_name EffectData
extends RefCounted
## Flipbook strips and the landing dust layout (`imported/effects/effects.json`,
## tools/remake_import/effects.py).


class Flipbook:
	var name: String
	var path: String
	## The strip, or the chosen texture pack's replacement of it (reloaded when the pack changes).
	var texture: Texture2D:
		get:
			return TexturePacks.texture(path) if not path.is_empty() else null
	var frames: int
	var additive: bool
	var light: Color                  ## the dynamic light of character sets; black for none


var system: Array[Flipbook] = []      ## set 3: hit, hit without damage, guard, dust
var character: Array[Flipbook] = []   ## sets 0 and 1 (the demonstration's own copies)
var directory: String
var objects: Dictionary = {}          ## the effect objects' page, palettes, models and UV tables
var _costume_entries: Dictionary = {}  ## costume slot (string) → flipbook entry of the fight
var _costumes: Dictionary = {}         ## costume slot → Flipbook, loaded when first used
var dust_offsets: Array[Vector3i] = []
var dust_y: int
var dust_interval: int
var dust: Flipbook


static func load_from(dir: String) -> EffectData:
	var data: Dictionary = JsonFile.read(dir.path_join("effects.json"))
	var e := EffectData.new()
	e.directory = dir
	e._costume_entries = data.get("costumes", {})
	e.objects = data.get("objects", {})
	for f: Dictionary in data.get("system", []):
		e.system.append(_flipbook(dir, f))
	for f: Dictionary in data.get("enbu", []):
		e.character.append(_flipbook(dir, f))
	var ring: Dictionary = data.get("dust_ring", {})
	for o: Array in ring.get("offsets", []):
		var v := JsonFile.ints(o)
		e.dust_offsets.append(Vector3i(v[0], v[1], v[2]))
	e.dust_y = ring.get("y", 0)
	e.dust_interval = ring.get("interval", 2)
	for f in e.system:
		if f.name == ring.get("flipbook", ""):
			e.dust = f
	return e


## The character flipbook a costume slot uploads in a fight (sets 0 and 1), null if none.
func costume(slot: int) -> Flipbook:
	if not _costumes.has(slot):
		var entry: Variant = _costume_entries.get(str(slot))
		_costumes[slot] = _flipbook(directory, entry as Dictionary) if entry is Dictionary else null
	return _costumes[slot] as Flipbook


static func _flipbook(dir: String, f: Dictionary) -> Flipbook:
	var b := Flipbook.new()
	b.name = f["name"]
	b.path = dir.path_join(str(f["file"]))
	b.frames = f["frames"]
	b.additive = f["blend"] == "add"
	var light := JsonFile.ints(f.get("light", [0, 0, 0]))
	b.light = Color8(light[0], light[1], light[2])
	return b
