class_name ArcadePoses
extends RefCounted
## The pose values the arcade selects an arcade model's vertex variants by (FUN_80194458,
## arcade/README.md#true-ogres-wings-and-the-variant-selection), computed from the channels the
## simulation steps: its hand channels' `current` values approach their targets as the arcade's do.
## The game picks a variant index of the row's 41 (a block of the file, not a blend of two):
## a hand's (or Kuma's and Panda's jaw) is `value >> 4` for a value up to the closed fist's 0x200,
## 33 steps of a blend from the open hand, and `value − 0x1E0` above, the shapes 33–40; the PlayStation's
## `FighterHands.variant` has the coarser numbers 0–9 (tools/research/verify_arcade_wings.py).

const BLEND_SHIFT := 4              ## a blend step is 1/16 of a channel value
const SHAPE_BASE := 0x1E0           ## the channel value of variant 0 of the shapes above the fist: 0x201 is variant 33
const TAIL_LEVEL_SHIFT := 4         ## True Ogre's tail: his level channel's value >> 4 (0–0x100 give 0–16)


## The variant a hand (or jaw) channel's value selects.
static func hand_variant(value: int) -> int:
	return value >> BLEND_SHIFT if value <= FighterHands.FIST else value - SHAPE_BASE


## The variant of each hand channel (the order of `FighterHands.current`).
static func hand_variants(hands: FighterHands) -> PackedInt32Array:
	var out := PackedInt32Array()
	for value: int in hands.current:
		out.append(hand_variant(value))
	return out


## True Ogre's wings (the wing sequence's variant) and tail (the level channel) variants.
static func wing_variants(hands: FighterHands) -> PackedInt32Array:
	return PackedInt32Array([hands.wing_variant, hands.current[0] >> TAIL_LEVEL_SHIFT])
