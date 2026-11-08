class_name ArcadeFlowPart
extends RefCounted
## A part of ArcadeGameFlow, which owns it.

var flow: ArcadeGameFlow:
	get: return _flow.get_ref() as ArcadeGameFlow

var _flow: WeakRef


func _init(game: ArcadeGameFlow) -> void:
	_flow = weakref(game)
