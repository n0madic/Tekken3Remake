class_name ForceItemsView
extends Node3D
## Tekken Force's items (force.ovl FUN_800B4374, `items` in tools/research/force_sim.py): per placed item
## two camera-facing quads above its projected point (y 0x420, under the floor), both SZ / 4-sized
## by 0x15E00 wide, the picture 0x2BC00 high (opaque) and its shadow as high as wide (texture
## shaded by 0x20, half and half) behind it. The game sorts them into the scene's ordering table
## at the point's depth; here they stand in the scene at that depth, so fighters in front of the
## item hide it (in front of the floor under the picture's bottom, which the game draws behind
## everything).

const WIDTH := 0x15E00
const HEIGHT := 0x2BC00
const SHADOW_SHADE := Color(0.25, 0.25, 0.25, 0.5)
const SHADOW_BEHIND := 0.01            ## Godot units: the shadow's quad just behind the picture's

var _meshes: Array[MeshInstance3D] = []   ## per item: picture, shadow
## Per item and step (previous, current): the picture's screen box in frame-buffer units (left, top,
## width, height) and the point's depth SZ; width 0 when not placed.
var _boxes: Array[PackedFloat32Array] = []


func setup(stage: StageData) -> void:
	var picture := TexturePacks.texture(stage.directory.path_join(str(stage.item["picture"])))
	var shadow := TexturePacks.texture(stage.directory.path_join(str(stage.item["shadow"])))
	var picture_material := _material(picture)
	picture_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var shadow_material := _material(shadow)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_color = SHADOW_SHADE
	for i in 2:
		for m: StandardMaterial3D in [picture_material, shadow_material]:
			var quad := MeshInstance3D.new()
			quad.mesh = ImmediateMesh.new()
			quad.material_override = m
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			quad.visible = false
			add_child(quad)
			_meshes.append(quad)
		_boxes.append(PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))


static func _material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = texture
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_fog = true
	return m


## After a simulation step: each item's box.
func apply(sim: FightSimulation) -> void:
	var force := sim.fight.force
	if force == null:
		return
	for i in 2:
		var box := _boxes[i]
		for k in 5:
			box[k] = box[5 + k]
		var it := force.item(i)
		if it[0] != 1 or sim.view == null:
			box[7] = 0
			continue
		var cur := picture_box(sim.view.screen_of(JointFrame.new(Fx.identity(), PackedInt32Array([it[1], it[2], it[3]]))))
		if box[2] == 0:
			# Newly placed: no movement to interpolate from.
			for k in 5:
				box[k] = cur[k]
		for k in 5:
			box[5 + k] = cur[k]


## The picture's box (left, top, width, height in frame-buffer units, and the depth SZ) over an
## item's projected point (screen x, y, SZ): its bottom a picture's height above the point.
static func picture_box(s: PackedInt32Array) -> PackedFloat32Array:
	var d := maxi(s[2] >> 2, 1)
	var w := Fx.div_trunc(WIDTH, d)
	var h := Fx.div_trunc(HEIGHT, d)
	var left := s[0] - Fx.div_trunc(w, 2)
	var base := s[1] - h
	return PackedFloat32Array([left, base - h, w, h, s[2]])


## Every rendered frame: the quads between the last two steps, in the camera's view.
func show_between(weight: float, camera: Camera3D, frame: Rect2) -> void:
	for i in 2:
		var box := _boxes[i]
		var picture := _meshes[2 * i]
		var shadow := _meshes[2 * i + 1]
		picture.visible = box[7] != 0
		shadow.visible = picture.visible
		if not picture.visible:
			continue
		var b := PackedFloat32Array()
		for k in 5:
			b.append(lerpf(box[k], box[5 + k], weight))
		var left := b[0]
		var top := b[1]
		var w := b[2]
		var h := b[3]
		var bottom := HudFrame.point(frame, left + w / 2.0, top + h)
		# Short of the floor by the shadow's step too, so that the floor does not hide the shadow's
		# bottom.
		var depth := minf(b[4] / WorldSpace.UNITS_PER_METRE, _floor_depth(camera, bottom) - 2.0 * SHADOW_BEHIND)
		_quad(picture, camera, frame, Rect2(left, top, w, h), depth)
		_quad(shadow, camera, frame, Rect2(left, top + h - w, w, w), depth + SHADOW_BEHIND)


## The view depth at which the ray through a window point meets the floor (y 0), or a large depth
## when it does not.
static func _floor_depth(camera: Camera3D, at: Vector2) -> float:
	var origin := camera.project_ray_origin(at)
	var ray := camera.project_ray_normal(at)
	if ray.y >= -1e-6:
		return INF
	var hit := origin + ray * (-origin.y / ray.y)
	return (hit - camera.global_position).dot(-camera.global_basis.z)


static func _quad(quad: MeshInstance3D, camera: Camera3D, frame: Rect2, box: Rect2, depth: float) -> void:
	var corners: Array[Vector3] = []
	for c: Vector2 in [box.position, Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), box.end]:
		corners.append(camera.project_position(HudFrame.point(frame, c.x, c.y), depth))
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var mesh := quad.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in [0, 1, 2, 1, 3, 2]:
		mesh.surface_set_uv(uvs[k])
		mesh.surface_add_vertex(corners[k])
	mesh.surface_end()
