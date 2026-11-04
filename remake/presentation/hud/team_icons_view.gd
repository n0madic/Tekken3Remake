class_name TeamIconsView
extends FightCanvas
## Team battle's members under the health bars, in place of the round marks (FUN_800B1C2C;
## `hud_team` in tools/research/draw_sim.py): one icon per member, the defeated ones crossed out,
## and the one a finished match has just beaten blinking. Drawn below FightHud (the name plates
## lie over the icons, as in the game's ordering table).

const ICON_Y := 0x40
const ICON_SIZE := Vector2i(10, 0x18)
const ICON_UV := Vector2i(0x40, 0xE0)
const CROSS_Y := 0x43
const CROSS_SIZE := Vector2i(10, 0x15)
const CROSS_UV_CLUT := 0x7ED1E04A
const TPAGE := 0x1F
const CLUT_LEFT := 0x7ED0
const CLUT_GONE := 0x7ED1
const START_X: Array[int] = [0x9C, 0xCA]
const STEP_X: Array[int] = [-9, 9]
const TEAM_CURRENT := 9                ## a team's +9: the member fighting (the members before it lost)
const TEAM_COUNT := 0xC                ## a team's +0xC: its size

var _fight: FightState


## After a simulation step.
func show_state(sim: FightSimulation, fighting: bool) -> void:
	_fight = sim.fight
	visible = fighting and _fight.mode == GameMode.TEAM
	if visible:
		redraw()


func _draw() -> void:
	if _fight == null or not _shown_now():
		return
	begin()
	for side in 2:
		_side(side)


## The HUD is on and the pause menu's move list does not cover them.
func _shown_now() -> bool:
	if _fight.hud_shown == 0 or _fight.replay_playing != 0:
		return false
	return _fight.pause_page != PauseMenu.PAGE_COMMAND or _fight.pause_delay != 0


func _side(side: int) -> void:
	var region := _fight.region
	var team := ModeRegion.CONTEXT + ModeRules.TEAMS + ModeRules.TEAM_SIZE * side
	var lost := region.u8(team + TEAM_CURRENT)
	var result := region.match_result
	var blinks := result >= 2 if side == 0 else (result == 1 or result == 3)
	# Last member first: the game's ordering table draws its last packets first, so a member lies
	# over the next one on the column they share.
	for k in range(region.u8(team + TEAM_COUNT) - 1, -1, -1):
		var x := START_X[side] + STEP_X[side] * k
		var gone := k < lost
		var beaten := k == lost and blinks
		var clut := CLUT_GONE if gone or (beaten and _fight.vblank & 0x10 == 0) else CLUT_LEFT
		image(vram.sprite(ICON_UV.x, ICON_UV.y, ICON_SIZE.x, ICON_SIZE.y, clut, TPAGE),
			x, ICON_Y, ICON_SIZE.x, ICON_SIZE.y, Color.WHITE, side == 1)
		if gone or beaten:
			sprt(x, CROSS_Y, CROSS_SIZE.x, CROSS_SIZE.y, CROSS_UV_CLUT, TPAGE)
