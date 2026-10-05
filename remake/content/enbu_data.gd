class_name EnbuData
extends RefCounted
## The attract demonstration as converted (`imported/enbu/enbu.json`): per demonstration the
## fighters' starting costume slots, the script and the model of each costume slot; the camera
## reel. See tools/remake_import/enbu.py.


class Demo:
	const COSTUME_EVENTS: Array[int] = [0, 1]   ## event kinds that change fighter 0 / 1's costume

	var number: int
	var start_costumes: PackedInt32Array
	var events: Array[PackedInt32Array] = []    ## [frame, kind, a, b, c] script events
	var models: Dictionary = {}                 ## costume slot → model folder name

	## The costume slots fighter `fighter` wears during the demonstration, the first one first.
	func costume_slots(fighter: int) -> PackedInt32Array:
		var out := PackedInt32Array([start_costumes[fighter]])
		for e in events:
			if e[1] == COSTUME_EVENTS[fighter] and not out.has(e[2]):
				out.append(e[2])
		return out


var bank: String
var camera_reel: PackedInt32Array
var demos: Array[Demo] = []


static func load_from(path: String) -> EnbuData:
	var data: Dictionary = JsonFile.read(path)
	var e := EnbuData.new()
	e.bank = data.get("bank", "")
	e.camera_reel = JsonFile.ints(data.get("camera_reel", []))
	for d: Dictionary in data.get("demonstrations", []):
		var demo := Demo.new()
		demo.number = d["number"]
		demo.start_costumes = JsonFile.ints(d["start_costumes"])
		for event: Array in d["script"]:
			demo.events.append(JsonFile.ints(event))
		var models: Dictionary = d["models"]
		for key: String in models:
			demo.models[int(key)] = str(models[key])
		e.demos.append(demo)
	return e
