class_name HitSlot
extends RefCounted
## One of a defender's two 0x2C-byte hit records (fighter +0x13C): the contact found by HitTest
## and its outcome from HitApply (combat.md#classification-and-damage).

var point := PackedInt32Array([0, 0, 0])   ## +0x00 the segment end at contact
var direction := PackedInt32Array([0, 0, 0])   ## +0x10 end − start (s16)
var zone := 0                   ## +0x18 hurt cylinder
var base_damage := 0            ## +0x1C the attacker's damage (u16)
var damage := 0                 ## +0x1E damage of the hit (s16)
var attacker := 0               ## +0x20
var used := 0                   ## +0x21
var guarded := 0                ## +0x22
var chip := 0                   ## +0x23
var hit := 0                    ## +0x24
var counter := 0                ## +0x25
var close := 0                  ## +0x26
var airborne := 0               ## +0x27
var no_damage := 0              ## +0x28


## HitClearSlots: the outcome (+0x1C … +0x28), not the contact geometry.
func clear() -> void:
	base_damage = 0
	damage = 0
	attacker = 0
	used = 0
	guarded = 0
	chip = 0
	hit = 0
	counter = 0
	close = 0
	airborne = 0
	no_damage = 0


## HitBestSlot's severity: the summed weights of the outcome flags.
func score() -> int:
	return no_damage + 2 * guarded + 3 * chip + 4 * close + 5 * hit + 6 * counter + 7 * airborne
