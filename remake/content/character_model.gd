class_name CharacterModel
extends RefCounted
## A converted character model: the 22 draw parts and the seam-blended mesh surfaces.
## See tools/remake_import/character.py for the mesh layout. An arcade model
## (tools/remake_import/arcade_character.py) keeps the PlayStation's parts, which the fight builds
## its joints from, and adds its own attachments on joints ARCADE_JOINT and up.

const PART_COUNT := 22
const ARCADE_JOINT := 22         ## the first arcade attachment's joint
const JOINT_COUNT := 28          ## the joints a mesh may be skinned to
const OPEN_SHAPE := 0             ## the eye shapes: the eyes as loaded
const CLOSED_SHAPE := 1           ## and the PlayStation's blink (the arcade's shapes are ArcadeEyes')
## The floats of a corner's three positions (pa, pb, pc) in the mesh, which a packed variant group
## patches (character.POSITION_FLOATS).
const POSITION_FLOATS := [0, 3, 23]
const POSITION_BYTES := 12          ## a position in the pose tables: three float32
const REF_BYTES := 12               ## a corner's three vertex numbers in the pose refs: three int32

class Part:
	var row: int
	var parent: int          ## parent draw part, −1 for the root part
	var offset: Vector3i     ## KMD joint offset; the joint translation is (x, y, −z)
	var joint: int           ## matrix slot of the part
	var drawn: bool
	var rest := PackedInt32Array()       ## attachments: rest Euler angles (16-bit units)
	var dynamics := PackedInt32Array()   ## attachments: FUN_80037F10's record, empty when static

## An arcade attachment (rows 18–23 of the arcade model, FUN_8019b634).
class ArcadeAttachment:
	var joint: int
	var parent: int          ## parent joint (a skeleton joint or an earlier attachment's)
	var offset: Vector3i     ## joint offset; the translation is (x, y, −z)
	var rest := PackedInt32Array()       ## rest Euler angles (16-bit units)
	var static_record: bool  ## FUN_8019b6d8's static record: the rest rotation only
	var record := PackedInt32Array()     ## the dynamics record (s16)

## An arcade costume's face (tools/remake_import/arcade_eyes.py, ArcadeFace): the eye shapes the
## game shows for the blink, a move that closes the eyes, a lying fighter and a shout (0: the eyes
## as loaded, NO_SHAPE: the costume lacks that shape), and the frames of each shout voice.
class ArcadeEyes:
	const NO_SHAPE := -1
	var blink: int
	var held: int
	var down: int
	var shout: int
	var shout_frames := PackedInt32Array()   ## per voice code 0x2000 on, empty when the character does not shout

class Surface:
	var double_sided: bool
	var vertices: PackedFloat32Array   ## vertex_floats per corner

## The faces that use the vertices a posable part moves, once per vertex variant: a hand's
## (FighterHandPoses), or the arcade True Ogre's wings and tail (arcade/README.md#true-ogres-wings).
## `channel` indexes the pose value that selects the variant (FighterView.set_hand_variants,
## set_wing_variants); `part` is the hand's part (the jaw's: the head's), or the wing's first row.
## `select` maps a pose value's variant to its entry of `variants` when the converter kept only the
## distinct ones (the arcade's hands: 41 variants, 33–38 distinct); empty: the identity.
class VariantGroup:
	var channel: int
	var part: int
	var variants: Array[Array] = []    ## per distinct variant: Array of Surface
	var select := PackedInt32Array()

var name: String
var arcade := false              ## converted from the arcade's model (its hands select the arcade's variants)
var costume_slot: int
var scale_percent: int
var vertex_floats: int
var smooth_crease_cos: float     ## the shader joins a smooth normal's halves within this angle
var curved_cache: RefCounted     ## CurvedMesh's grids of this model, built on first use
var parts: Array[Part] = []
var surfaces: Array[Surface] = []
var directory: String
var texture: String      ## atlas of the used texture regions
var eye_textures := {}       ## eye shape (int) → the atlas with that shape over the eyes (PlayStation: 1 closed)
var arcade_eyes: ArcadeEyes  ## an arcade model's face changes, null for the PlayStation's
var swap_texture := ""       ## Gon's: the atlas with his head's palette swapped (PartSelectVertexVariant), else ""
var swap_variants := PackedInt32Array()   ## the hand variants (of either channel) that swap it
var gaze: Dictionary = {}    ## Gon's eyes' look direction (tools/remake_import/gaze.py, GazeAtlas), else empty
var hands: Array[VariantGroup] = []
var wings: Array[VariantGroup] = []
var arcade_attachments: Array[ArcadeAttachment] = []


static func load_from(dir: String) -> CharacterModel:
	var data: Dictionary = JsonFile.read(dir + "/model.json")
	var mesh := DataFile.read(dir + "/mesh.bin.gz")
	var m := CharacterModel.new()
	m.directory = dir
	m.name = data.get("name", "")
	m.arcade = data.get("source", "") == "arcade"
	m.costume_slot = data.get("costume_slot", 0)
	m.scale_percent = data.get("scale_percent", 100)
	m.vertex_floats = data.get("vertex_floats", 0)
	m.smooth_crease_cos = data.get("smooth_crease_cos", 1.0)
	m.texture = data.get("texture", "")
	for p: Dictionary in data.get("parts", []):
		var part := Part.new()
		part.row = p["row"]
		part.parent = p["parent"]
		var o := JsonFile.ints(p["offset"])
		part.offset = Vector3i(o[0], o[1], o[2])
		part.joint = p["joint"]
		part.drawn = p["drawn"]
		part.rest = JsonFile.ints(p.get("rest", []))
		var dynamics: Variant = p.get("dynamics")
		if dynamics != null:
			part.dynamics = JsonFile.ints(dynamics)
		m.parts.append(part)
	for a: Dictionary in data.get("arcade_attachments", []):
		var attachment := ArcadeAttachment.new()
		attachment.joint = a["joint"]
		attachment.parent = a["parent"]
		var ao := JsonFile.ints(a["offset"])
		attachment.offset = Vector3i(ao[0], ao[1], ao[2])
		attachment.rest = JsonFile.ints(a["rest"])
		attachment.static_record = a["static"]
		attachment.record = JsonFile.ints(a["record"])
		m.arcade_attachments.append(attachment)
	if data.has("texture_closed"):
		m.eye_textures[CLOSED_SHAPE] = data["texture_closed"]
	var swap: Dictionary = data.get("palette_swap", {})
	if not swap.is_empty():
		m.swap_texture = swap["texture"]
		m.swap_variants = JsonFile.ints(swap["variants"])
	m.gaze = data.get("gaze", {})
	var shapes: Dictionary = data.get("eye_textures", {})
	for shape: String in shapes:
		m.eye_textures[int(shape)] = shapes[shape]
	var eyes: Dictionary = data.get("arcade_eyes", {})
	if not eyes.is_empty():
		m.arcade_eyes = ArcadeEyes.new()
		m.arcade_eyes.blink = eyes["blink"]
		m.arcade_eyes.held = eyes["held"]
		m.arcade_eyes.down = eyes["down"]
		m.arcade_eyes.shout = eyes["shout"]
		m.arcade_eyes.shout_frames = JsonFile.ints(eyes["shout_frames"])
	var surfaces: Array = data.get("surfaces", [])
	m.surfaces = _surfaces(surfaces, mesh, m.vertex_floats)
	m.hands = _groups(data.get("hands", []) as Array, mesh, m.vertex_floats)
	m.wings = _groups(data.get("wings", []) as Array, mesh, m.vertex_floats)
	return m


## The hands' and the wings' groups together.
func variant_groups() -> Array[VariantGroup]:
	var groups: Array[VariantGroup] = []
	groups.append_array(hands)
	groups.append_array(wings)
	return groups


static func _groups(list: Array, mesh: PackedByteArray, floats: int) -> Array[VariantGroup]:
	var out: Array[VariantGroup] = []
	for g: Dictionary in list:
		var group := VariantGroup.new()
		group.channel = g["channel"]
		group.part = g["part"]
		if g.has("poses"):
			var base := _surfaces((g["variants"] as Array)[0] as Array, mesh, floats)
			group.variants = _posed(base, g["poses"] as Dictionary, mesh, floats)
			group.select = JsonFile.ints(g["select"])
		else:
			for variant: Array in g["variants"]:
				group.variants.append(_surfaces(variant, mesh, floats))
		out.append(group)
	return out


## The surface sets of a packed group (character.VariantGroup.packed): `base` is the first
## variant's; the group's "poses" give every distinct variant's positions of the moving vertices
## (`table`, per variant `vertices` float32 triples) and, per corner of `base` in order, the
## numbers of the vertices its three positions are (`refs`, int32, −1: the position stays).
static func _posed(base: Array[Surface], poses: Dictionary, mesh: PackedByteArray, floats: int) -> Array[Array]:
	var count: int = poses["count"]
	var vertices: int = poses["vertices"]
	var table_start: int = poses["table"]
	var table := mesh.slice(table_start, table_start + count * vertices * POSITION_BYTES).to_float32_array()
	var corners := 0
	for surface in base:
		corners += surface.vertices.size() / floats
	var refs_start: int = poses["refs"]
	var refs := mesh.slice(refs_start, refs_start + corners * REF_BYTES).to_int32_array()
	# The positions a pose moves, found once: per surface the float each one is at and its vertex.
	var moving: Array[PackedInt32Array] = []
	var corner := 0
	for source in base:
		var found := PackedInt32Array()
		for i in source.vertices.size() / floats:
			for k in POSITION_FLOATS.size():
				var ref := refs[(corner + i) * 3 + k]
				if ref >= 0:
					found.append(i * floats + (POSITION_FLOATS[k] as int))
					found.append(ref)
		corner += source.vertices.size() / floats
		moving.append(found)
	var out: Array[Array] = []
	for pose in count:
		var surfaces: Array[Surface] = []
		for s in base.size():
			var surface := Surface.new()
			surface.double_sided = base[s].double_sided
			surface.vertices = base[s].vertices.duplicate()
			var found := moving[s]
			for j in range(0, found.size(), 2):
				var from := (pose * vertices + found[j + 1]) * 3
				surface.vertices[found[j]] = table[from]
				surface.vertices[found[j] + 1] = table[from + 1]
				surface.vertices[found[j] + 2] = table[from + 2]
			surfaces.append(surface)
		out.append(surfaces)
	return out


static func _surfaces(list: Array, mesh: PackedByteArray, floats: int) -> Array[Surface]:
	var out: Array[Surface] = []
	for s: Dictionary in list:
		var surface := Surface.new()
		surface.double_sided = s["double_sided"]
		var start: int = s["offset"]
		var count: int = s["vertex_count"]
		surface.vertices = mesh.slice(start, start + count * floats * 4).to_float32_array()
		out.append(surface)
	return out


## Fighter scale in 4.12 (`value × 4096 / 100`, fighter +0x4EE).
func scale_fixed() -> int:
	return scale_percent * Fx.ONE / 100


## Local joint translation of each matrix slot (the game stores (x, y, −z)).
func joint_offsets() -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	out.resize(PART_COUNT)
	for part in parts:
		out[part.joint] = PackedInt32Array([part.offset.x, part.offset.y, -part.offset.z])
	return out


## Parent matrix slot of each matrix slot (−1 for the root joint).
func joint_parents() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PART_COUNT)
	for part in parts:
		out[part.joint] = parts[part.parent].joint if part.parent >= 0 else -1
	return out
