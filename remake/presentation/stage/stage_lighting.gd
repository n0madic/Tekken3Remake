class_name StageLighting
extends Node3D
## The stage's light rig (stages.md#lighting) as real lights: the main directional light with
## shadows, the half-strength light shining up from below, and the back colour as ambient
## light, for the floor. The fighters are lit by the record itself as the game's NCCT does
## (fighter_parameters, fighter_skin.gdshaderinc), only the main light's shadows come from here.
## No tonemapping: the unshaded panorama and the fighters show the game's display-space colours.
## The environment is the view's camera's (Camera3D.environment): a WorldEnvironment per view would
## leave only the first one in the tree active, whichever view is shown.
##
## The back colour of a fighter changes per frame (fighter_back_colour: Tekken Force's pick-up
## flash, practice's FREEZE SIGNAL, a burning body); in the game it lights the fighters only (the
## floor and the panorama are not lit by the GTE), so the ambient light here, on the stage's meshes,
## stays the stage's.

const FILL_SHARE := 0.5
const LIGHT_ENERGY := 1.1
const AMBIENT_ENERGY := 0.55
const SHADOW_DISTANCE := 30.0
const NO_FILL_STAGE := 17             ## FUN_80039BB4: no light from below on this stage
const GTE_ONE := 4096.0               ## the GTE's 1.0: colour matrix and back colour are byte << 4
const FLASH_PEAK := 0x2000            ## the pick-up flash starts at 2.0 (GTE units) and falls to the stage's level
const NO_SIGNAL := Color8(0, 0, 0, 0)  ## practice's FREEZE SIGNAL with its flag (alpha) clear
## The fighters are on their own render layer and the fill light does not reach it: the fighter
## shader adds the fill itself (fighter_skin.gdshaderinc) and takes every directional light that
## reaches it for the main light. So the sun is the only directional light that may reach this
## layer: a light added to a scene with fighters in it has to leave FIGHTER_LAYER out of its
## `light_cull_mask` (the tests check the stage's two).
const FIGHTER_LAYER := 1 << 1
const ALL_LAYERS := 0xFFFFF

var environment := Environment.new()
var sun := DirectionalLight3D.new()
var fill := DirectionalLight3D.new()


func setup(stage: StageData, camera: Camera3D) -> void:
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(stage.ambient / 255.0, stage.ambient / 255.0, stage.ambient / 255.0)
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = environment
	sun.light_color = stage.light_colour
	sun.light_energy = LIGHT_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SHADOW_DISTANCE
	add_child(sun)
	aim(sun, light_travel(stage))
	_apply_quality()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	fill.light_color = stage.light_colour
	fill.light_energy = LIGHT_ENERGY * FILL_SHARE
	fill.shadow_enabled = false
	fill.light_cull_mask = ALL_LAYERS & ~FIGHTER_LAYER
	fill.visible = stage.number != NO_FILL_STAGE
	add_child(fill)
	aim(fill, Vector3.UP)


## The graphics preset on the environment and the main light (RenderQuality).
func _apply_quality() -> void:
	RenderQuality.apply_environment(environment)
	RenderQuality.apply_light(sun)


func _on_setting_changed(key: String) -> void:
	if key == "graphics":
		_apply_quality()


## The fighter shader's light rig for `stage` (fighter_skin.gdshaderinc): FUN_80039BB4's colour
## matrix (main light byte << 4, the light from below (byte >> 1) << 4), SetBackColor's level
## (FUN_8003A3B8: ambient << 4) and the base colour, in GTE units of 4096.
static func fighter_parameters(stage: StageData) -> Dictionary:
	var c := stage.light_colour
	var light := Vector3(c.r8, c.g8, c.b8) * 16.0 / GTE_ONE
	var fill := Vector3(c.r8 >> 1, c.g8 >> 1, c.b8 >> 1) * 16.0 / GTE_ONE
	return {
		"base_colour": stage.base_colour,
		"back_colour": back_colour(stage.ambient, stage.ambient, stage.ambient),
		"light_colour": light,
		"fill_colour": fill if stage.number != NO_FILL_STAGE else Vector3.ZERO,
	}


## The back colour FUN_8003AA6C lights a fighter with in one frame, in GTE units of 4096
## (stages.md#lighting), from FightState.flash_level `flash`: black while the fighter burns
## (FighterAnimation.LIT_BLACK), else practice's FREEZE SIGNAL `freeze` while its flag (alpha) is
## set, else the pick-up flash's ramp for the count (1 to 32; 0: none), else the stage's level.
## `ambient_level` is the stage record's word (StageData.ambient_level). The flash's blue is the
## ramp on odd counts and the stage's level on even ones, so it flickers between white and yellow.
static func fighter_back_colour(ambient_level: int, flash: int, freeze: Color) -> Vector3:
	if flash == FighterAnimation.LIT_BLACK:
		return Vector3.ZERO
	if freeze.a8 != 0:
		return back_colour(freeze.r8, freeze.g8, freeze.b8)
	var level := ambient_level >> 4
	if flash == 0:
		return back_colour(level, level, level)
	var ramp := flash_ramp(ambient_level, flash)
	return back_colour(ramp, ramp, ramp if flash & 1 != 0 else level)


## FUN_8003A3B8's ramp for the flash count `flash` (1 to 32): the level, in bytes (up to 0x200,
## 2.0 in GTE units), falling linearly from FLASH_PEAK to the stage's level; the product rounds
## towards zero.
static func flash_ramp(ambient_level: int, flash: int) -> int:
	var t := (FLASH_PEAK - ambient_level) * (FighterAnimation.FLASH_FRAMES + 1 - flash) * 0x80
	if t < 0:
		t += 0xFFF
	return ((t >> 12) + ambient_level) >> 4


## SetBackColor's colour for bytes (r, g, b): byte << 4 in GTE units of 4096.
static func back_colour(r: int, g: int, b: int) -> Vector3:
	return Vector3(r, g, b) * 16.0 / GTE_ONE


## Turns a directional light to shine along `direction`, with an up vector that is never
## parallel to it (a light along ±z uses +y).
static func aim(light: DirectionalLight3D, direction: Vector3) -> void:
	var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.FORWARD)) < 0.99 else Vector3.UP
	light.basis = Basis.looking_at(direction, up)


## The direction the main light travels, in Godot space: the game's
## (cos(yaw − 0x800)·cos p, sin p, sin(yaw − 0x800)·cos p) with y down.
static func light_travel(stage: StageData) -> Vector3:
	var p := WorldSpace.radians(stage.light_pitch)
	var y := WorldSpace.radians(stage.light_yaw - 0x800)
	return WorldSpace.point(cos(y) * cos(p), sin(p), sin(y) * cos(p)).normalized()
