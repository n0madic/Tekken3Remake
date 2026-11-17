class_name NetMenu
extends FlowPart
## The remake's NET MODE screen (docs/DECISIONS.md D16): reached from the main menu's NET MODE
## entry. Three items: HOST GAME (waits for an opponent on the port), JOIN GAME (types the host's
## IP on the keyboard) and BACK. On a connect both sides rebuild their flows with the shared seed
## (game.gd watches for NetPlay.session_active) and the session runs in lockstep from the title.
## The screen draws through game.gd's message label (flow.net.screen_text() every frame).

const ITEMS := 3
const ITEM_HOST := 0
const ITEM_JOIN := 1
const ITEM_BACK := 2
const CHOOSE := PadState.CONFIRM
const BACK := PadState.SELECT


## The NetPlay autoload, reached by node: this screen compiles in the test runner (GameFlow loads
## it), where the autoloads do not exist and the NetPlay identifier is not known.
func _net() -> NetSession:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"NetPlay") as NetSession
const JOIN_TIMEOUT := 15 * 60        ## 15 s of connecting, then the failure status and back

var cursor := 0


func step() -> void:
	var pressed := g.pressed_any()
	var rep := g.repeat(0) | g.repeat(1)
	match g.sub:
		0:
			# The directions move the cursor (as the main menu's list does, with repeat).
			var step_dir := ((rep >> 14) & 1) - ((rep >> 12) & 1)
			if step_dir != 0:
				cursor = (cursor + step_dir + ITEMS) % ITEMS
				g.sound(MainMenu.SOUND_CURSOR)
			if pressed & CHOOSE:
				g.sound(MainMenu.SOUND_CHOOSE)
				match cursor:
					ITEM_HOST:
						var net := _net()
						net.host(net.DEFAULT_PORT, net.game_seed)
						g.sub = 1
					ITEM_JOIN:
						g.sub = 2
					_:
						_back()
			elif pressed & BACK:
				_back()
		1:
			# Hosting: the game.gd rebuild takes over once NetPlay.session_active rises.
			if pressed & BACK:
				_net().shutdown()
				_back()
		2:
			# The IP field (game.gd feeds the keystrokes into NetPlay).
			if pressed & CHOOSE:
				g.sound(MainMenu.SOUND_CHOOSE)
				var net := _net()
				if net.net_ip.is_empty():
					g.sound(MainMenu.SOUND_CURSOR)
				else:
					net.join(net.net_ip, net.DEFAULT_PORT)
					g.sim.state_timer = 0
					g.sub = 3
			elif pressed & BACK:
				g.sub = 0
		3:
			# Connecting: the rebuild takes over on a connect; a timeout goes back with the
			# failure status.
			g.sim.state_timer += 1
			var net := _net()
			if pressed & BACK:
				net.shutdown()
				g.sub = 0
			elif not net.session_active and g.sim.state_timer > JOIN_TIMEOUT:
				net.shutdown()
				g.sub = 0


## Back to the main menu through the transition screen.
func _back() -> void:
	g.goto_transition(GameFlow.State.MENU)
