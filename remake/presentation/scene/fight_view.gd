class_name FightView
extends Node3D
## Draws a fight: the stage with its light rig, the fighters (costume models, hand variants,
## eyes; Tekken Force's third record too), the flipbook effects and effect objects, Tekken
## Ball's ball and court, Tekken Force's items, and the fight camera, interpolated between
## simulation steps.
##

const CLEAR_STAGE := 11
const CLEAR_STAGE_COLOUR := Color8(72, 104, 200)
const BACKDROP_DEPTH := 0.95           ## of the far plane: behind everything else
## A camera that moves this far (game units) or turns this much (4096 units) between two
## steps is a cut: the rig does not interpolate across it.
const CUT_DISTANCE := 1500
const CUT_ANGLE := 0x200
## The spotlight floors (stages.md#floor, FUN_80049AE0): K per kind and the brightness limits.
const SPOT_K: Array[int] = [0, 253755392, 800000000, 512000000, 414720000]
const SPOT_LIMIT := 254
const SPOT_LIMIT_MIDPOINT := 192
const SPOT_LIMIT_DARK := 128          ## kind 2 on stages 13 and 19 with True Ogre
const DARK_STAGES := [13, 19]
const FORCE_CAMERA_LEVEL := 4         ## Tekken Force's level whose floor is lit from the camera
const FORCE_CAMERA_Z := -2000

var stage_view := StageView.new()
var lighting := StageLighting.new()
var effects := EffectsView.new()
var rig := CameraRig.new()
var fighters: Array[FighterView] = []
var clear_colour := Color.BLACK
var tiled: TiledPanorama               ## the tile-map stages' screen-space backdrop
var _backdrop_viewport: SubViewport
var _backdrop: MeshInstance3D
var ball: BallView                     ## Tekken Ball's ball and court
var items: ForceItemsView              ## Tekken Force's items
var _last_view: CameraView
var _overhead := false                 ## the overhead KO camera: fighters drawn closer to it
var _floor_kind := 0                   ## the stage's floor kind (True Ogre turns 0 into 2)
var _stage_number := 0
var _ambient_level := 0                ## the light record's ambient word (StageData.ambient_level)
var _true_ogre := false
var _wind := ArcadeWind.new()          ## the helicopter stage's wind on the arcade models' attachments
var _wind_rng := RandomNumberGenerator.new()   ## the wind's direction, seeded by the match
var _fighter_lighting: Dictionary = {} ## StageLighting.fighter_parameters of the fight's light record
var _costume_slots := PackedInt32Array()
var _array_cache: Dictionary = {}      ## the fighters' mesh arrays, for this fight (FighterView.array_cache)


## `light_stage`: the stage whose light record lights the fight, when not its own (Tekken Force's
## Doctor B. level).
func setup(stage: StageData, effect_data: EffectData, models: Array[CharacterModel], costume_slots: PackedInt32Array,
		char_ids: PackedInt32Array, light_stage: StageData = null) -> void:
	stage_view.setup(stage)
	add_child(stage_view)
	var lights := light_stage if light_stage != null else stage
	_ambient_level = lights.ambient_level
	lighting.setup(lights, rig.camera)
	add_child(lighting)
	effects.setup(effect_data)
	effects.set_costumes(costume_slots)
	add_child(effects)
	add_child(rig)
	var true_ogre := Character.TRUE_OGRE in char_ids
	_floor_kind = stage_view.floor_kind()
	_stage_number = stage.number
	_true_ogre = true_ogre
	# The arcade draws the wind's direction with rand(); here it follows from the match, so that
	# runs (screenshots, replays) repeat.
	_wind_rng.seed = hash([stage.number, costume_slots])
	_wind.start(stage.number, _wind_rng)
	# stages.md#clear-colour: no panorama in True Ogre fights; stage 11's blue otherwise (the
	# arcade's stages have their sky instead, also gone in True Ogre fights).
	stage_view.panorama.visible = not true_ogre
	clear_colour = CLEAR_STAGE_COLOUR if stage.number == CLEAR_STAGE and not true_ogre and stage_view.arcade == null \
		else Color.BLACK
	lighting.environment.background_color = clear_colour
	stage_view.apply_environment(lighting.environment, true_ogre)
	# Where the clear colour is the sky (stage 11) the view may extend upwards without limit:
	# above the panorama the game shows that colour too.
	rig.coverage = stage_view.coverage() if clear_colour == Color.BLACK else PackedInt32Array()
	_fighter_lighting = StageLighting.fighter_parameters(lights)
	_costume_slots = costume_slots.duplicate()
	for model in models:
		fighters.append(_new_fighter(model))


func _new_fighter(model: CharacterModel) -> FighterView:
	var view := FighterView.new()
	view.array_cache = _array_cache
	view.setup(model)
	view.set_lighting(_fighter_lighting)
	add_child(view)
	return view


## A record's model swapped in during the fight (Tekken Force's enemies and boss, the Ogre scene):
## only its view is built again; it shows from the next step.
func replace_fighter(i: int, model: CharacterModel, costume_slot: int) -> void:
	var old := fighters[i]
	var view := _new_fighter(model)
	view.visible = false
	move_child(view, old.get_index())
	fighters[i] = view
	remove_child(old)
	old.queue_free()
	_costume_slots[i] = costume_slot
	effects.set_costumes(_costume_slots)


## Tekken Ball's and Tekken Force's parts: the tile-map backdrop (drawn into a viewport and
## shown on a quad just before the camera's far plane, behind everything), the ball and the items.
func setup_modes(stage: StageData, tables: FightTables, volley: GameRam) -> void:
	if not stage.tile_map.is_empty():
		_backdrop_viewport = SubViewport.new()
		_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_backdrop_viewport.disable_3d = true
		add_child(_backdrop_viewport)
		tiled = TiledPanorama.new()
		tiled.setup(stage, tables)
		_backdrop_viewport.add_child(tiled)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = _backdrop_viewport.get_texture()
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
		material.disable_fog = true
		_backdrop = MeshInstance3D.new()
		_backdrop.mesh = ImmediateMesh.new()
		_backdrop.material_override = material
		_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_backdrop)
		rig.coverage = PackedInt32Array()
	if not stage.item.is_empty():
		items = ForceItemsView.new()
		items.setup(stage)
		add_child(items)
	if volley != null:
		ball = BallView.new()
		ball.setup(volley)
		add_child(ball)


## The backdrop quad over the whole view at BACKDROP_DEPTH of the far plane.
func _place_backdrop(window: Vector2) -> void:
	var size := Vector2i(maxi(int(window.x), 1), maxi(int(window.y), 1))
	if _backdrop_viewport.size != size:
		_backdrop_viewport.size = size
	var camera := rig.camera
	var depth := CameraRig.FAR * BACKDROP_DEPTH
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		corners.append(camera.project_position(c * window, depth))
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var mesh := _backdrop.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in [0, 1, 2, 1, 3, 2]:
		mesh.surface_set_uv(uvs[k])
		mesh.surface_add_vertex(corners[k])
	mesh.surface_end()


## After a simulation step.
func apply(sim: FightSimulation) -> void:
	for i in fighters.size():
		var f := sim.fight.fighters[i]
		var view := fighters[i]
		var shown := f.body != null and f.active != 0 and sim.fight.undrawn_mask & (1 << i) == 0
		var appearing := shown and not view.visible
		view.visible = shown
		if not shown:
			continue
		view.set_wind(_wind.vector)
		view.set_joints(f.body.draw_joints.slice(0, FighterView.JOINT_SLOTS), appearing)
		view.set_hidden_joints(0 if f.body.stick_shown else 1 << FighterView.STICK_JOINT)
		view.set_overhead(sim.camera.overhead != 0, f.pose_move.flags & MoveFlag.REACT_CHAIN != 0)
		view.set_hands(f.hands)
		view.set_gaze(f.body.gon_gaze)
		for e in sim.events.items:
			if e.kind == SimEvents.Kind.SHOUT and e.b == f.player_index:
				view.shout(e.a)
		if view.face != null:
			view.step_face(Blinker.held(f.pose_move.flags), Blinker.lying(f.pose_move.flags, f.pose_move.state))
		else:
			view.set_eyes_closed(f.hands.face == 1)
		var freeze: Color = sim.fight.signal_colour[f.player_index] if sim.fight.mode == GameMode.PRACTICE else StageLighting.NO_SIGNAL
		view.set_back_colour(StageLighting.fighter_back_colour(_ambient_level, sim.fight.flash_level[i], freeze))
	_wind.step()
	effects.step(sim.events)
	effects.objects.show_pool(sim.fight.effects)
	var v := sim.camera.view
	var view := CameraView.new(v.pitch, v.yaw, v.x, v.y, v.z, v.h)
	rig.set_view(view, _is_cut(view))
	_last_view = view
	_overhead = sim.camera.overhead != 0
	var f0 := sim.fight.fighters[0]
	var f1 := sim.fight.fighters[1]
	stage_view.follow(WorldSpace.point((f0.root_x + f1.root_x) / 2.0, 0, (f0.root_z + f1.root_z) / 2.0))
	_spotlight(sim)
	stage_view.set_floor_distance(_floor_distance(sim))
	stage_view.set_backdrop_turn(sim.fight.backdrop.angle)
	stage_view.step(v.yaw, sim.fight.rounds_played, sim.fight.round_state, sim.pads.physical[0])
	if tiled != null:
		tiled.step(sim)
		stage_view.set_floor_edge(tiled.floor_edge)
	if ball != null:
		ball.apply(sim)
	if items != null:
		items.apply(sim)


## FloorDrawGrid: where the floor's distance shading starts, the camera's horizontal distance to
## the fighters' midpoint (Tekken Force: to the line z = 0).
static func _floor_distance(sim: FightSimulation) -> float:
	var view := sim.camera.view
	if sim.fight.mode == GameMode.FORCE:
		return absf(view.z)
	var f0 := sim.fight.fighters[0]
	var f1 := sim.fight.fighters[1]
	var dx := view.x - Fx.div_trunc(f0.root_x + f1.root_x, 2)
	var dz := view.z - Fx.div_trunc(f0.root_z + f1.root_z, 2)
	return sqrt(float(dx * dx + dz * dz))


## FloorSetup's kind (Tekken Force's camera-lit level forces 4; True Ogre turns a plain floor into
## 2) and FUN_80049AE0's light points of this step.
func _spotlight(sim: FightSimulation) -> void:
	var fight := sim.fight
	var kind := _floor_kind
	if fight.mode == GameMode.FORCE:
		if fight.region.fight_index == FORCE_CAMERA_LEVEL:
			kind = 4
	elif _true_ogre and kind == 0:
		kind = 2
	if kind <= 0 or kind >= SPOT_K.size():
		stage_view.set_spotlight(0, Vector3.ZERO, Vector3.ZERO, 0, 0)
		return
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var a := WorldSpace.point((f0.root_x + f1.root_x) / 2, 0, (f0.root_z + f1.root_z) / 2)
	var b := Vector3.ZERO
	var limit := SPOT_LIMIT
	match kind:
		1:
			a = WorldSpace.point(f0.root_x, 0, f0.root_z)
			b = WorldSpace.point(f1.root_x, 0, f1.root_z)
		2:
			limit = SPOT_LIMIT_DARK if _true_ogre and _stage_number in DARK_STAGES else SPOT_LIMIT_MIDPOINT
		3:
			var p := fight.force.player() if fight.force != null else f0
			a = WorldSpace.point(p.root_x, 0, p.root_z)
		4:
			a = WorldSpace.point(sim.camera.view.x, 0, FORCE_CAMERA_Z)
	var spot_k: int = SPOT_K[kind]
	var k := spot_k / (WorldSpace.UNITS_PER_METRE * WorldSpace.UNITS_PER_METRE)
	stage_view.set_spotlight(kind, a, b, k, limit)


## Every rendered frame: the poses and camera between the last two steps.
func interpolate(weight: float, window: Vector2) -> void:
	for view in fighters:
		if view.visible:
			view.show_between(weight)
	rig.place(weight, window)
	stage_view.place_sky(rig.camera, rig.frame_tan)
	# FUN_80036254: under the overhead KO camera the fighters are drawn ViewMatrix.OVERHEAD_DEPTH
	# units nearer to it (along the view axis).
	var toward := rig.camera.global_basis.z * (ViewMatrix.OVERHEAD_DEPTH / WorldSpace.UNITS_PER_METRE) if _overhead else Vector3.ZERO
	for view in fighters:
		view.position = toward
	if tiled != null:
		tiled.show_between(weight, rig.frame_rect)
		_place_backdrop(window)
	if ball != null:
		ball.show_between(weight)
	if items != null:
		items.show_between(weight, rig.camera, Rect2(rig.frame_rect.position * window, rig.frame_rect.size * window))


func _is_cut(view: CameraView) -> bool:
	if _last_view == null:
		return true
	var a := _last_view
	var moved := Vector3(view.x - a.x, view.y - a.y, view.z - a.z).length()
	var turned := maxi(absi(wrapi(view.yaw - a.yaw, -2048, 2048)), absi(wrapi(view.pitch - a.pitch, -2048, 2048)))
	return moved > CUT_DISTANCE or turned > CUT_ANGLE
