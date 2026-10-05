extends SceneTree
## Debugging aid for the fight trace suite: runs a scenario up to a frame and prints fighter
## properties of the simulation next to the trace's fields around it.
##
##     godot --headless --path remake -s res://tests/support/fight_debug.gd -- \
##         <scenario> <first frame> <last frame> <property> [<property> …]
##
## A property is a FighterState name (snake_case, "0." / "1." for one fighter) or "global.<name>"
## for a FightState field, "camera.<path>" for a CameraDirector field ("camera.view.yaw") or
## "ram.<hex address>[:<size>]" for a traced RAM word (negative size: signed), or "events" for the
## step's SimEvents next to the trace's calls; the trace value
## of a fighter property is read through FighterCompare's field table.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: <scenario> <first frame> <last frame> <property> …")
		quit(1)
		return
	var trace := FightTrace.load_scenario(args[0])
	var first := args[1].to_int()
	var last := args[2].to_int()
	var props := args.slice(3)
	var content := FightContent.load_from(AssetCatalog.ROOT)
	var setup := FightSetup.new()
	var s: Dictionary = trace.header["scenario"]
	setup.chars = JsonFile.ints(s["chars"])
	setup.costumes = JsonFile.ints(s["costumes"])
	setup.stage = JsonFile.number(s["stage"])
	setup.seed = JsonFile.number(s["seed"])
	setup.round_time = JsonFile.number(s["round_time"])
	setup.rounds = JsonFile.number(s["rounds"])
	setup.chip_damage = s["chip"]
	var fixes: bool = s.get("gameplay_fixes", false)
	var sim := FightSimulation.new(content, setup, RuleSet.with_gameplay_fixes() if fixes else RuleSet.original())
	var compare := FighterCompare.new(trace)
	var by_prop := {}
	for d in compare.fields:
		by_prop[d["property"]] = d
	for frame in mini(last + 1, trace.frames):
		sim.step(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		if frame < first:
			continue
		var line := "%5d:" % frame
		for p: String in props:
			if p.begins_with("global."):
				line += " %s=%s" % [p, sim.fight.get(p.substr(7))]
				continue
			if p == "events":
				line += " events=%s calls=%s" % [sim.events.items, trace.calls(frame)]
				continue
			if p.begins_with("camera."):
				line += " %s=%s" % [p, _path(sim.camera, p.substr(7))]
				continue
			if p.begins_with("ram."):
				var spec := p.substr(4).split(":")
				var address := spec[0].hex_to_int()
				var size := spec[1].to_int() if spec.size() > 1 else -4
				var value := "-"
				if trace.has_ram(address, absi(size)):
					value = str(trace.ram(frame, address, size))
				line += " %s=%s" % [p, value]
				continue
			var fighters := [0, 1]
			var name := p
			if p[1] == ".":
				fighters = [p.to_int()]
				name = p.substr(2)
			for i: int in fighters:
				var ours: Variant = sim.fight.fighters[i].get(name)
				if ours is MoveRow:
					var row := ours as MoveRow
					ours = "%s:%d" % [row.bank.name, row.index]
				var theirs := "?"
				if by_prop.has(name):
					var d: Dictionary = by_prop[name]
					var off: int = d["offset"]
					var type: String = d["type"]
					if type == "void*":
						theirs = str(trace.row_of(frame, trace.fighter_u32(frame, i, off)))
					else:
						var size: int = FightTrace.SIZES[type]
						theirs = str(trace.read(trace.record(frame, i) + off, -size if type.begins_with("s") else size))
				line += " %d.%s=%s/%s" % [i, name, ours, theirs]
		print(line)
	quit(0)


## Follows a dotted property path ("view.yaw", "sources.0") from `root`.
func _path(root: Variant, path: String) -> Variant:
	var value: Variant = root
	for part in path.split("."):
		if value is Object:
			value = (value as Object).get(part)
		elif part.is_valid_int():
			value = value[part.to_int()]
		else:
			return "?"
	return value
