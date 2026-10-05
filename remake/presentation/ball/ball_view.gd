class_name BallView
extends Node3D
## Tekken Ball's ball and court (volley.ovl FUN_800B3198 and FUN_800B3DA4, `ball_draw` and
## `court_draw` in tools/research/ball_sim.py): the game's 42-vertex sphere (16 triangles and 32
## quads) in the ball type's colours, lit, or in a flat colour for the flash kinds; squashed
## along an axis on impact, casting the stage light's shadow as the fighters do; the court's
## centre band and side lines, placed between the fighters along z.
##
## Render kinds 0 and 10 go into the 2D ordering table: over the whole scene. Kind 2's streaks
## are ModeHudView's.

const VERTICES := 0x800B64A8           ## 42 SVECTORs
const NORMALS := 0x800B65F8            ## per vertex: SVECTOR
const TRIANGLES := 0x800B6748          ## 16 × 4 vertex indices
const QUADS := 0x800B6788              ## 32 × 4
const COLOURS := 0x800B6828            ## per type (64 bytes): 8 triangle colours, 8 quad colours
const STYLES := 0x800B6460             ## per type (24 bytes): +0xC specular power, +0xD… back colour
const VERTEX_COUNT := 42
const FACE_COUNTS := [16, 32]          ## triangles, quads
const FLAT_KINDS := [0, 1, 2, 5, 8]
const OVERLAY_KINDS := [0, 10]
const OVERLAY_PRIORITY := 100
const COURT_START := -0x1F40
const COURT_STEP := 0x600
const COURT_ROWS := 9
const BAND_HALF := 0x64
const LINE_WIDTH := 24.0

var _ram: GameRam
var _ball := MeshInstance3D.new()
var _court := MeshInstance3D.new()
var _materials: Array[StandardMaterial3D] = []
var _overlay_materials: Array[StandardMaterial3D] = []   ## kind 10: the same, over the scene
var _flat := StandardMaterial3D.new()
var _flat_overlay: StandardMaterial3D
var _meshes: Array[ArrayMesh] = []      ## per ball type
var _previous := Transform3D()
var _current := Transform3D()
var _court_z := PackedFloat32Array([0, 0])
var _type := -1
var _snap := true                       ## the next step's pose is not interpolated into (the first, a return)


func setup(ram: GameRam) -> void:
	_ram = ram
	for t in 3:
		_meshes.append(_sphere(t))
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		# The face colours are the game's display values (sRGB), like textures.
		m.vertex_color_is_srgb = true
		var power := ram.u8(STYLES + 24 * t + 0xC)
		m.roughness = clampf(1.0 - power / 128.0, 0.1, 1.0)
		m.metallic_specular = 0.8
		_materials.append(m)
		_overlay_materials.append(_over_scene(m.duplicate() as StandardMaterial3D))
	_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat.vertex_color_use_as_albedo = false
	_flat_overlay = _over_scene(_flat.duplicate() as StandardMaterial3D)
	# Like the fighters, the ball casts the stage light's shadow (the game's flattened ring of
	# the equator is replaced as the fighters' flat shadows are).
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_ball)
	_court.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_court)


static func _over_scene(m: StandardMaterial3D) -> StandardMaterial3D:
	m.no_depth_test = true
	m.render_priority = OVERLAY_PRIORITY
	return m


## A game SVECTOR (three s16) in RAM, in the game's frame.
static func svector(ram: GameRam, at: int) -> Vector3:
	return Vector3(ram.s16(at), ram.s16(at + 2), ram.s16(at + 4))


## Face `i` of a pass (0: the triangles, 1: the quads): its vertex indices, and its colour in a
## ball type (the colours cycle by face index & 7).
static func face_corners(ram: GameRam, pass_: int, i: int) -> PackedInt32Array:
	var table := TRIANGLES if pass_ == 0 else QUADS
	var idx := PackedInt32Array()
	for k in 3 + pass_:
		idx.append(ram.u8(table + 4 * i + k))
	return idx


static func face_colour(ram: GameRam, t: int, pass_: int, i: int) -> Color:
	return ScreenCanvas.psx(ram.u32(COLOURS + 64 * t + 0x20 * pass_ + 4 * (i & 7)))


## The sphere of a ball type: each face in its colour (colours cycle by face index & 7), with
## the game's vertex normals.
func _sphere(t: int) -> ArrayMesh:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for pass_ in 2:
		for i: int in FACE_COUNTS[pass_]:
			var c := face_colour(_ram, t, pass_, i)
			var idx := face_corners(_ram, pass_, i)
			# PSX quads are (0, 1, 2) and (1, 3, 2); the game's winding faces outwards with y down.
			var tris: Array = [[0, 1, 2]] if pass_ == 0 else [[0, 1, 2], [1, 3, 2]]
			for tri: Array in tris:
				for k: int in [tri[0], tri[2], tri[1]]:
					var v := idx[k]
					var at := svector(_ram, VERTICES + 8 * v)
					positions.append(WorldSpace.point(at.x, at.y, at.z))
					var n := svector(_ram, NORMALS + 8 * v)
					normals.append(WorldSpace.point(n.x, n.y, n.z).normalized())
					colours.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The court: the centre band (x ±100) and the side lines (x ± the neutral zone) in nine rows
## 0x600 apart from z = −8000, brightest in the middle (ball_init's shades), added to the floor.
func _court_mesh(zone: int) -> ArrayMesh:
	var shades := PackedFloat32Array()
	for k in COURT_ROWS:
		var v := 0xC0 - (0x30 * (4 - k) if k < 4 else 0x30 * (k - 4))
		shades.append(maxi(v, 0) / 255.0)
	var positions := PackedVector3Array()
	var colours := PackedColorArray()
	for strip: Array in [[-BAND_HALF, BAND_HALF], [-zone - LINE_WIDTH / 2, -zone + LINE_WIDTH / 2],
			[zone - LINE_WIDTH / 2, zone + LINE_WIDTH / 2]]:
		var x0: float = strip[0]
		var x1: float = strip[1]
		for j in COURT_ROWS - 1:
			var z0 := COURT_START + COURT_STEP * j
			var z1 := z0 + COURT_STEP
			var c0 := Color(shades[j], shades[j], shades[j])
			var c1 := Color(shades[j + 1], shades[j + 1], shades[j + 1])
			var quad := [[x0, z0, c0], [x1, z0, c0], [x0, z1, c1], [x1, z1, c1]]
			for k: int in [0, 2, 1, 1, 2, 3]:
				var q: Array = quad[k]
				positions.append(WorldSpace.point(q[0] as float, -1, q[1] as float))
				colours.append(q[2] as Color)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	mesh.surface_set_material(0, m)
	return mesh


## After a simulation step.
func apply(sim: FightSimulation) -> void:
	var tb := sim.fight.ball
	if tb == null:
		visible = false
		_snap = true
		return
	visible = true
	if _court.mesh == null:
		_court.mesh = _court_mesh(tb.neutral_zone())
	var b := tb.b
	var t := sim.fight.region.ctx8(TekkenBall.BALL_TYPE) % 3
	if t != _type:
		_type = t
		_ball.mesh = _meshes[t]
	var kind := b.u8(TekkenBall.B_KIND)
	var over := kind in OVERLAY_KINDS
	if kind in FLAT_KINDS:
		# The faces' flat grey: kind 0 fades out from black by 8 a frame, kind 1 in from 7, the
		# others white.
		var k := b.u8(TekkenBall.B_TIMER)
		var level := 0xFF
		match kind:
			0:
				level = (-8 * k) & 0xFF
			1:
				level = (8 * k - 1) & 0xFF
		var flat := _flat_overlay if over else _flat
		flat.albedo_color = Color8(level, level, level)
		_ball.material_override = flat
	else:
		_ball.material_override = _overlay_materials[t] if over else _materials[t]
	var angles := PackedInt32Array([b.u16(TekkenBall.B_ANGLES), b.u16(TekkenBall.B_ANGLES + 2), b.u16(TekkenBall.B_ANGLES + 4)])
	var rotation_basis := _psx_rotation(angles)
	var squash := b.s16(TekkenBall.B_SQUASH) / 4096.0
	var squash_basis := Basis.IDENTITY
	if squash != 0.0:
		var axis := _psx_rotation(PackedInt32Array([b.u16(TekkenBall.B_SQUASH_AXIS), b.u16(TekkenBall.B_SQUASH_AXIS + 2),
			b.u16(TekkenBall.B_SQUASH_AXIS + 4)]))
		var scale := Basis.from_scale(Vector3(1.0 - squash, 1.0 + squash, 1.0 + squash))
		squash_basis = axis * scale * axis.transposed()
	var pos := WorldSpace.point(b.s32(TekkenBall.B_POS), b.s32(TekkenBall.B_POS + 4), b.s32(TekkenBall.B_POS + 8))
	var pose := Transform3D(squash_basis * rotation_basis, pos)
	var f0 := sim.fight.fighters[0]
	var f1 := sim.fight.fighters[1]
	var court_z := (f0.root_z + f1.root_z) >> 1
	_previous = pose if _snap else _current
	_current = pose
	_court_z[0] = court_z if _snap else _court_z[1]
	_court_z[1] = court_z
	_snap = false


## libgte RotMatrix (4096 units): R = Rx · Ry · Rz in the game's y-down frame.
static func rot_matrix(angles: PackedInt32Array) -> Basis:
	return Basis(Vector3.RIGHT, WorldSpace.radians(angles[0])) * Basis(Vector3.UP, WorldSpace.radians(angles[1])) \
		* Basis(Vector3.BACK, WorldSpace.radians(angles[2]))


## rot_matrix turned into Godot's frame.
static func _psx_rotation(angles: PackedInt32Array) -> Basis:
	# WorldSpace flips y and z: conjugate by that flip.
	var flip := Basis.from_scale(Vector3(1, -1, -1))
	return flip * rot_matrix(angles) * flip


## Every rendered frame.
func show_between(weight: float) -> void:
	if not visible:
		return
	_ball.transform = _previous.interpolate_with(_current, weight)
	_court.position = WorldSpace.point(0, 0, lerpf(_court_z[0], _court_z[1], weight))
