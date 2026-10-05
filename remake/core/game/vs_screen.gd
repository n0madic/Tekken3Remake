class_name VsScreen
extends FlowPart
## The pre-fight VS screen (FUN_80052808, game state 11; modes.md#pre-fight-vs-screen): the
## portraits, names and caption of the next fight slide in over 8 frames, stay for one more, and
## the game goes on to FightMain's loading (the state saved in 0x800AFF64/65).
##
## Sub-state 1 builds the screen objects (0x800B9380, the modes' overlay set-ups, VsModeSetups in
## draw_sim.py) and keeps the loaded pictures' ids in the progress block (0x800984E4–E7).
##
## Tekken Ball and Tekken Force read their layouts and captions from their overlays (mode_ram).

const SLIDE_FRAMES := 8
const MAX_OBJECTS := 64
const KEY_NONE := 0x58
const NO_PICTURE := 0x26             ## FUN_80052794: a side without a big picture
const NAME_WIDTH := 0x15             ## pixels per name character
const NAME_LEFT := 0xC
const NAME_RIGHT := 0x164
const SCREEN_WIDTH := 0x170
const VS_TEXT := [0xA2, 0xFA]        ## "VS": colour 0, font 2
const CAPTION_AT := [0x1C, 0x2A]     ## the caption line: colour 6, font 1
const ICON_FLAGS := 8
const ICON_BEATEN := 0x68
const TEAM_STRIDE := 0xD
const TEAM_AT := 0x59                ## mode context: the two teams (keys, current, count, size)
const PROGRESS_BACKGROUND := 0x214   ## 0x800984E4: the loaded background id
const PROGRESS_PICTURES := 0x216     ## 0x800984E6: per side, the loaded big picture
const TEXT_CODES := "%c%f%H%V"       ## the text engine's colour, font and position prefix
# volley.ovl FUN_800B55B4
const BALL_POS := 0x800B6908         ## per side 4 x s16: portrait, then name
const BALL_NAMES := 0x800B6918
const BALL_VS := 0x800B0AA4
const BALL_CAPTION := 0x800B0AB0     ## "TEKKEN BALL"
const BALL_CAPTION_KIND := 5
# force.ovl FUN_800B6648
const FORCE_POS := 0x800B6A24        ## the player's portrait
const FORCE_NAME := 0x800B6A2C       ## the player's name
const FORCE_LEVEL_NAME := 0x800B6A34 ## the level's name lines (x right edge, y, slide)
const FORCE_LEVEL_NAMES := 0x800B6A3C  ## per level two string pointers
const FORCE_LEVEL_COLOURS := 0x800B6A64
const FORCE_CAPTION := 0x800B0FA0    ## "TEKKEN FORCE"
const FORCE_STAGE := 0x800B0FB8      ## "STAGE %d"
const FORCE_FINAL := 0x800B0FCC      ## "FINAL STAGE"
const FORCE_FINAL_LEVEL := 4
const FORCE_SIDE := 0x3E             ## mode context: the player's side
const FORCE_CAPTION_KIND := 6
const STAGE_AT := [0x20, 0x54]
const LEVEL_NAME_STEP := 0x2E

enum Kind { NONE, BACKGROUND, TEAM_BARS, CAPTION_BAR, PORTRAIT, ICON, FRAME, TEXT, NAME }


## A screen object (0x28 bytes at 0x800B9380): where it rests, where it slides in from, and what it draws.
class VsObject:
	extends RefCounted
	var kind := Kind.NONE
	var x := 0
	var y := 0
	var dx := 0                      ## the slide offset at the start (type 1 frame: width)
	var dy := 0                      ## (type 6 frame: height)
	var colour := 0                  ## bar and portrait tint (RGB); text colour index
	var font := 0
	var text := ""                   ## texts: the format without the HUD codes
	var arg := 0                     ## texts: the number printed; icons: the costume key
	var flags := 0                   ## icons: 8, or 0x68 dimmed
	var facing := 0                  ## portraits: 1 mirrored
	var picture := 0                 ## portraits: the side's big picture (attribute & 0x1F)

	## The position this frame (FUN_80052538: the slide scaled by the frames left).
	func at(slide: int) -> Vector2i:
		if slide == 0:
			return Vector2i(x, y)
		return Vector2i(x + (slide * dx >> 3), y + (slide * dy >> 3))


var slide := 0                       ## 0x800B937C: frames left of the slide-in
var background := 0                  ## 0x800B9378: the background id of this screen
var pictures := PackedInt32Array([0, 0])  ## 0x800B937A: per side, the big picture
var objects: Array[VsObject] = []
var shown := false                   ## the screen is drawn this frame (sub-states 2 and 3)


func step() -> void:
	shown = false
	match g.sub:
		0:
			g.display(0)
			g.sub = 1
		1:
			_setup()
			slide = SLIDE_FRAMES
			g.sub = 2
		2:
			shown = true
			slide -= 1
			if slide < 1:
				g.sub = 3
		3:
			shown = true
			g.sub = 4
		4:
			g.state = GameFlow.target_state(g.region.vs_next_state)
			g.sub = g.region.vs_next_sub


## Sub-state 1: the objects of the mode, then the pictures to load (kept in the progress block).
func _setup() -> void:
	objects.clear()
	var gl := g.globals
	var k0 := (gl.player_char[0] << 2) | gl.player_costume[0]
	var k1 := (gl.player_char[1] << 2) | gl.player_costume[1]
	_mode_setup(PackedInt32Array([k0, k1]), 1 if g.region.human_count != 1 else 0)
	# A picture not loaded yet is read from the disc (LoadOverlaySync), which stops the music.
	var progress := g.progress
	if progress.s16(PROGRESS_BACKGROUND) != Fx.s16(background):
		progress.put16(PROGRESS_BACKGROUND, background)
		g.disc_read()
	for side in 2:
		if progress.u8(PROGRESS_PICTURES + side) != pictures[side]:
			progress.put8(PROGRESS_PICTURES + side, pictures[side])
			g.disc_read()


## VsModeSetups: arcade.ovl 0x800B3C70 (arcade, time attack), 0x800B3D70 (VS), 0x800B3E64 (team),
## 0x800B3F98 (survival), 0x800B408C (demonstration).
func _mode_setup(keys: PackedInt32Array, kind: int) -> void:
	var data := g.data
	var region := g.region
	var mode := region.mode
	if mode == GameMode.BALL:
		_ball_setup(keys, kind)
		return
	if mode == GameMode.FORCE:
		_force_setup(keys)
		return
	if mode == GameMode.PRACTICE:
		# practice.ovl FUN_800B713C.
		for side in 2:
			_add_portrait(side, keys[side], data.vs_practice_pos.slice(4 * side, 4 * side + 4))
			_add_name(keys[side], data.vs_practice_names.slice(4 * side, 4 * side + 4))
		_add_text(data.vs_text, 0, 2, VS_TEXT[0], VS_TEXT[1], 0)
		_add_caption(str(data.vs_practice_texts["caption"]), 0)
		_add_background(0, 4)
		return
	var pos := data.vs_team_pos if mode == GameMode.TEAM else data.vs_player_pos
	var names := data.vs_team_names if mode == GameMode.TEAM else data.vs_player_names
	for side in 2:
		if mode == GameMode.TEAM:
			_team_icons(side)
		_add_portrait(side, keys[side], pos.slice(4 * side, 4 * side + 4))
		_add_name(keys[side], names.slice(4 * side, 4 * side + 4))
	_add_text(data.vs_text, 0, 2, VS_TEXT[0], VS_TEXT[1], 0)
	match mode:
		GameMode.DEMO:
			_add_caption(data.vs_demo, 0)
			_add_background(1, 1)
		GameMode.VS:
			_add_caption(data.vs_round, region.ctx32(0x28) + 1)
			_add_background(1, 1)
		GameMode.TEAM:
			_add_caption(data.vs_round, region.ctx8(0x58) + 1)
			_alloc(Kind.TEAM_BARS)
			_add_background(kind, 2)
		GameMode.SURVIVAL:
			_add_caption(data.vs_round, region.ctx32(0x44) + 1)
			_add_background(0, 3)
		_:
			_add_caption(data.vs_stage, region.ctx32(0x24) + 1)
			_add_background(kind, kind)


## volley.ovl FUN_800B55B4: both sides as in versus, captioned TEKKEN BALL.
func _ball_setup(keys: PackedInt32Array, kind: int) -> void:
	var ram := g.content.mode_ram("volley")
	for side in 2:
		_add_portrait(side, keys[side], _ram_pos(ram, BALL_POS + 8 * side))
		_add_name(keys[side], _ram_pos(ram, BALL_NAMES + 8 * side))
	_add_text(_ram_text(ram, BALL_VS), 0, 2, VS_TEXT[0], VS_TEXT[1], 0)
	_add_caption(_ram_text(ram, BALL_CAPTION), 0)
	_add_background(kind, BALL_CAPTION_KIND)


## force.ovl FUN_800B6648: the player's portrait and name, TEKKEN FORCE, STAGE n / FINAL STAGE,
## and the level's name sliding in on the right; the other side has no big picture.
func _force_setup(keys: PackedInt32Array) -> void:
	var ram := g.content.mode_ram("force")
	var region := g.region
	var level := region.ctx32(0x24)
	var side := 1 if region.ctx8(FORCE_SIDE) != 0 else 0
	_add_portrait(side, keys[side], _ram_pos(ram, FORCE_POS))
	pictures[side ^ 1] = NO_PICTURE
	_add_name(keys[side], _ram_pos(ram, FORCE_NAME))
	_add_caption(_ram_text(ram, FORCE_CAPTION), 0)
	if level < FORCE_FINAL_LEVEL:
		_add_text(_ram_text(ram, FORCE_STAGE), 6, 1, STAGE_AT[0], STAGE_AT[1], level + 1)
	else:
		_add_text(_ram_text(ram, FORCE_FINAL), 6, 1, STAGE_AT[0], STAGE_AT[1], 0)
	var pos := _ram_pos(ram, FORCE_LEVEL_NAME)
	for i in 2:
		var o := _alloc(Kind.NAME)
		if o == null:
			break
		_place(o, pos)
		o.font = 3
		o.colour = ram.u8(FORCE_LEVEL_COLOURS + level)
		o.text = ram.string(ram.u32(FORCE_LEVEL_NAMES + 8 * level + 4 * i))
		o.x = Fx.s16(pos[0] - o.text.length() * NAME_WIDTH)
		pos[1] += LEVEL_NAME_STEP
	_add_background(0, FORCE_CAPTION_KIND)


## Four s16 of an overlay table: x, y and the slide offsets.
static func _ram_pos(ram: GameRam, address: int) -> PackedInt32Array:
	return PackedInt32Array([ram.s16(address), ram.s16(address + 2), ram.s16(address + 4), ram.s16(address + 6)])


static func _ram_text(ram: GameRam, address: int) -> String:
	return ram.string(address).replace(TEXT_CODES, "")


## FUN_80051C64: a new object (null when all 64 are used).
func _alloc(kind: Kind) -> VsObject:
	if objects.size() >= MAX_OBJECTS:
		return null
	var o := VsObject.new()
	o.kind = kind
	objects.append(o)
	return o


func _place(o: VsObject, pos: PackedInt32Array) -> void:
	o.x = pos[0]
	o.y = pos[1]
	o.dx = pos[2]
	o.dy = pos[3]


## FUN_800523FC: a side's big picture, facing the other side.
func _add_portrait(side: int, key: int, pos: PackedInt32Array) -> void:
	var o := _alloc(Kind.PORTRAIT)
	if o == null:
		return
	var word := g.data.attribute(key >> 2, key & 3)
	o.colour = word >> 8
	o.facing = (((word & 0xFF) >> 5) ^ (1 if side != 0 else 0)) & 1
	o.picture = word & 0x1F
	pictures[side] = o.picture
	_place(o, pos)


## FUN_80052650: a side's name (colour 8, font 3), kept on screen; a negative x right-aligns.
func _add_name(key: int, pos: PackedInt32Array) -> void:
	var o := _alloc(Kind.NAME)
	if o == null:
		return
	_place(o, pos)
	o.text = str(g.fight.tables.character(KEY_NONE if key > 0x5C else key)["name"])
	o.colour = 8
	o.font = 3
	var w := o.text.length() * NAME_WIDTH
	var right := o.x + w
	var left := o.x
	if o.x < 0:
		right = -o.x
		left = -o.x - w
	left = maxi(left, NAME_LEFT)
	var v := left
	if right > NAME_RIGHT:
		v += NAME_RIGHT - right
	o.x = Fx.s16(v)
	if o.dx != 0:
		o.dx = Fx.s16(-(o.x + w) if o.dx < 1 else SCREEN_WIDTH - o.x)


## FUN_800525DC: a text shown at rest.
func _add_text(text: String, colour: int, font: int, x: int, y: int, arg: int) -> void:
	var o := _alloc(Kind.TEXT)
	if o == null:
		return
	o.text = text
	o.colour = colour
	o.font = font
	o.x = x
	o.y = y
	o.arg = arg


func _add_caption(text: String, arg: int) -> void:
	_add_text(text, 6, 1, CAPTION_AT[0], CAPTION_AT[1], arg)


## FUN_80051FC4: the caption bar and the tiled background.
func _add_background(kind: int, caption: int) -> void:
	var o := _alloc(Kind.CAPTION_BAR)
	if o == null:
		return
	o.y = 0x24
	o.colour = g.data.vs_caption_colours[caption]
	o.dx = g.data.vs_caption_widths[caption]
	if _alloc(Kind.BACKGROUND) != null:
		background = g.data.vs_backgrounds[kind]


## arcade.ovl FUN_800B3928: a team's members but the one fighting (the beaten ones dimmed, the
## ones beyond the team's count locked), and a frame around them.
func _team_icons(side: int) -> void:
	var region := g.region
	var team := TEAM_AT + TEAM_STRIDE * side
	var n := mini(region.ctx8(team + 0xC), 8)
	var icons := g.data.vs_team_icons
	var x := icons[4 * side]
	var y := icons[4 * side + 1]
	var step_x := icons[4 * side + 2]
	if n == 8:
		x = icons[4 * side + 3]
	var w := (step_x << 3) & 0xFFFF
	var fx := (x - 1) & 0xFFFF
	var fy := (y - 2) & 0xFFFF
	var fw := ((n - 1) * 0x21 + 1) & 0xFFFF
	if side != 0:
		fx = (fx + (n - 2) * step_x) & 0xFFFF
	var current := region.ctx8(team + 9)
	var last := region.ctx8(team + 10)
	if not current < last:
		last = current + 1
	var order := range(current, n)
	order.append_array(range(region.ctx8(team + 9)))
	for i: int in order:
		var key := mini(region.ctx8(team + i), KEY_NONE)
		var flags := ICON_FLAGS
		if i >= last:
			key = KEY_NONE
		elif i < current:
			flags = ICON_BEATEN
		elif i == current:
			continue
		var o := _alloc(Kind.ICON)
		if o != null:
			o.arg = key
			o.flags = flags
			o.x = Fx.s16(x)
			o.y = Fx.s16(y)
			o.dx = Fx.s16(w)
		x = (x + step_x) & 0xFFFF
	if n >= 2:
		var o := _alloc(Kind.FRAME)
		if o != null:
			o.x = Fx.s16(fx)
			o.y = Fx.s16(fy)
			o.dx = fw
			o.dy = 0x3E
