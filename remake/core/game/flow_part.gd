class_name FlowPart
extends RefCounted
## Base of the screens and parts GameFlow owns: they reach the flow through `g`, held weakly
## so the flow and its parts do not keep each other alive.

var g: GameFlow:
	get: return _flow.get_ref() as GameFlow
var _flow: WeakRef


func _init(flow: GameFlow) -> void:
	_flow = weakref(flow)
