class_name FightSetup
extends RefCounted
## What a VS match is started with (the menus' and the fight setup screen's choices): the two
## fighters, the stage, the options and the random seeds.

var chars := PackedInt32Array([0, 1])       ## character ids
var costumes := PackedInt32Array([0, 0])    ## costume 0–3 of each character
var stage := 0
var round_time := 2                         ## ROUND TIME option: 20, 30, 40, 50, 60 s, 5 infinite
var rounds := 1                             ## FIGHT COUNT option: rounds to win − 1
var chip_damage := false                    ## GUARD DAMAGE option
var handicaps := PackedInt32Array([3, 3])   ## health table index per player (3: 140)
var cpu := PackedInt32Array([0, 0])         ## 1: the player is CPU-controlled
var ai_difficulty := 1                      ## the AI group: DIFFICULTY LEVEL (0x800AE6D0)
var ai_level := 0                           ## the CPU level 0–9 (0x800AE6D9)
var attract := false                        ## the demonstration fight (0x800AE39C)
var key_tables: Array[PackedInt32Array] = []   ## per player: mapped word of each physical bit
var seed := 1                               ## rand(), the camera and the frame generator
var unlocked := 0x3FF                       ## unlocked characters (bit per id) Mokujin may copy


## The key configuration of a new game.
const DEFAULT_KEY_TABLE := [0, 0, 0, 0, 0x10, 0x20, 0x40, 0x80, 0x100, 0, 0, 0x800, 0x1000, 0x2000, 0x4000, 0x8000]


## The humans as a bit per player (0x800AE3D8).
func human_mask() -> int:
	var mask := 0
	for p in 2:
		if cpu[p] == 0:
			mask |= 1 << p
	return mask


func _init() -> void:
	for p in 2:
		key_tables.append(PackedInt32Array(DEFAULT_KEY_TABLE))
