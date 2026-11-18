class_name NetView
extends PsxCanvas
## The remake's NET MODE screen (docs/DECISIONS.md D16/D17), drawn in the options' style: the
## options backdrop, the page title in font 1, the three items in font 0 (the cursor's item in
## colour 5 on a pulsing bar, the others 10) and the hints in colour 4 — all the game's own
## fonts. The net menu's sub-state is the flow's sub (flow.sub), the cursor flow.net.cursor.

const BAR := 0xFF4020                ## the cursor bar's GPU colour word (options_view's)

var picture_texture: Texture2D
var flow: GameFlow
var frame_count := 0


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	var own := image.duplicate_image()
	own.upload_file(screens_dir.path_join("options.tims"))
	setup_psx(hud_data, game_ram, own)
	pictures_dir = screens_dir
	picture_texture = TexturePacks.texture(pictures_dir.path_join("options.png"))


func show_state(game: GameFlow) -> void:
	flow = game
	frame_count = game.fight.vblank
	queue_redraw()


func _title_colour() -> int:
	return 1 if flow.progress.options_colour != 0 else 6


func _draw() -> void:
	begin()
	black()
	image(picture_texture, 0, 0, SCREEN.x, SCREEN.y)
	if flow == null:
		return
	text("NET MODE", 1, _title_colour(), 0x8B, 0x28)
	match flow.sub:
		0:
			_items()
		1:
			_waiting()
		2:
			_join()
		3:
			_connecting()


## The three items (as the options' lists: the cursor's in colour 5 on a pulsing bar).
func _items() -> void:
	var labels := ["HOST GAME", "JOIN GAME", "BACK"]
	var x := 0x8B
	var y := 0x78
	for i in labels.size():
		var label: String = labels[i]
		if i == flow.net.cursor:
			_glow(x, y, text_width(label, 0))
			text(label, 0, 5, x, y)
		else:
			text(label, 0, 10, x, y)
		y += 0x1C
	centred("START: CHOOSE    SELECT: BACK", 0, 4, 0xB8, 0x168)


## Hosting: the connection's own status (the port and the wait).
func _waiting() -> void:
	centred("WAITING FOR OPPONENT", 0, 6, 0xB8, 0x9A)
	centred("PORT %d" % NetPlay.DEFAULT_PORT, 0, 6, 0xB8, 0xB4)
	centred("SELECT: CANCEL", 0, 4, 0xB8, 0x168)


## The IP field: the typed address with a cursor.
func _join() -> void:
	centred("TYPE THE HOST IP", 0, 6, 0xB8, 0x8A)
	centred(NetPlay.net_ip + "_", 0, 6, 0xB8, 0xAE)
	centred("START: CONNECT    SELECT: BACK", 0, 4, 0xB8, 0x168)


## Connecting: the address and the wait.
func _connecting() -> void:
	centred("CONNECTING TO %s" % NetPlay.net_ip, 0, 6, 0xB8, 0x9A)
	centred("SELECT: CANCEL", 0, 4, 0xB8, 0x168)


## FUN_800DC838: the cursor bar behind an item (pulsing), as the options' lists have.
func _glow(x: float, y: float, w: float) -> void:
	var c := scale_colour(BAR, (triangle(frame_count << 4) >> 1) + 0x80)
	fill(x - 3, y - 3, w + 6, 0x16, psx(c))
