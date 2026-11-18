class_name StageBackdrop
extends Node3D
## A stage without fighters behind a screen: the ranking's turning view (ranking.ovl
## FUN_800C3AAC: the camera orbits the stage's centre, FUN_80046458 makes the block's pitch, yaw
## and eye the camera).

var stage_view := StageView.new()
var lighting := StageLighting.new()
var rig := CameraRig.new()
var number := -1


func setup(stage: StageData) -> void:
	number = stage.number
	stage_view.setup(stage)
	add_child(stage_view)
	lighting.setup(stage, rig.camera)
	stage_view.apply_environment(lighting.environment)
	add_child(lighting)
	rig.coverage = stage_view.coverage()
	add_child(rig)
	stage_view.follow(WorldSpace.point(0, 0, 0))


## After a step: the view of this frame (`cut`: no interpolation into it).
func show_view(view: CameraView, cut: bool) -> void:
	rig.set_view(view, cut)
	stage_view.step()


func interpolate(weight: float, window: Vector2) -> void:
	rig.place(weight, window)
	stage_view.place_sky(rig.camera, rig.frame_tan)
