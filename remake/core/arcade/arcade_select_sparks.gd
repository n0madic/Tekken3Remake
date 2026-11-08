class_name ArcadeSelectSparks
extends SelectSparks
## The arcade's character select sparks (FUN_801BF8B4, FUN_801BF6B4, FUN_801BF990): the PlayStation's
## machine on the arcade's numbers.

const PORTRAIT_WIDTH := 0xA8
const START_BRIGHTNESS := 0xA0
const FADE_MIN := 6


func _init() -> void:
	super(PORTRAIT_WIDTH, START_BRIGHTNESS, FADE_MIN)
