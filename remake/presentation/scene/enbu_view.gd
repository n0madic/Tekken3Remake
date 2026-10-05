class_name EnbuView
extends Node3D
## Draws the attract demonstration's performance: stage 4 with its light rig, the two fighters
## in their current costumes (a view per costume slot, shown only on the frames the game draws
## the fighter), the frame effects and the camera reel, interpolated between simulation steps.
##
## The original draws a flat grey floor in the demonstration; the stage's normal floor is used
## here (remake-plan.md#m1-the-attract-sequence-on-the-engine).

var stage_view := StageView.new()
var lighting := StageLighting.new()
var effects := EffectsView.new()
var rig := CameraRig.new()
var models: Dictionary = {}            ## costume slot → CharacterModel
var views: Array[Dictionary] = [{}, {}]   ## per fighter: costume slot → FighterView
var _shown: Array[FighterView] = [null, null]
var _fighter_lighting: Dictionary = {} ## the stage's light rig for the fighters


func setup(stage: StageData, effect_data: EffectData) -> void:
	stage_view.setup(stage)
	add_child(stage_view)
	lighting.setup(stage, rig.camera)
	stage_view.apply_environment(lighting.environment)
	add_child(lighting)
	_fighter_lighting = StageLighting.fighter_parameters(stage)
	effects.setup(effect_data)
	add_child(effects)
	rig.coverage = stage_view.coverage()
	add_child(rig)


## Binds a demonstration's models and builds, hidden, the view of every costume each fighter
## wears in it, so that no mesh is built while the performance runs.
func load_demo(demo: EnbuData.Demo, costume_models: Dictionary) -> void:
	models = costume_models
	for per_fighter in views:
		for slot: int in per_fighter:
			(per_fighter[slot] as FighterView).queue_free()
		per_fighter.clear()
	_shown = [null, null]
	effects.clear()
	for fighter in views.size():
		for slot in demo.costume_slots(fighter):
			_view(fighter, slot)


## After a simulation step of the performance.
func apply(perf: EnbuPerformance) -> void:
	for i in 2:
		var sf := perf.fighters[i]
		var view := _view(i, sf.model_costume)
		if _shown[i] != null and _shown[i] != view:
			_shown[i].visible = false
		var appearing := _shown[i] != view or not view.visible
		_shown[i] = view
		view.visible = sf.drawn and perf.drawn
		if view.visible:
			view.set_joints(sf.skeleton.joints, appearing)
			view.set_hidden_joints(0 if sf.stick_shown else 1 << FighterView.STICK_JOINT)
			view.set_hands(sf.fighter.hands)
	effects.step(perf.events)
	stage_view.set_backdrop_turn(perf.backdrop.angle)
	stage_view.step()
	if perf.camera_drawn != null:
		rig.set_view(perf.camera_drawn, perf.camera_drawn.cut)
		stage_view.set_view_pitch(perf.camera_drawn.pitch)


## Every rendered frame: the pose and camera between the last two steps.
func interpolate(weight: float, window: Vector2) -> void:
	for view in _shown:
		if view != null and view.visible:
			view.show_between(weight)
	rig.place(weight, window)


func _view(fighter: int, slot: int) -> FighterView:
	var per_fighter := views[fighter]
	if not per_fighter.has(slot):
		var view := FighterView.new()
		view.setup(models[slot] as CharacterModel)
		view.set_lighting(_fighter_lighting)
		view.visible = false
		add_child(view)
		per_fighter[slot] = view
	return per_fighter[slot] as FighterView
