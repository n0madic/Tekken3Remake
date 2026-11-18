class_name NetSession
extends Node
## The remake's local network play (docs/DECISIONS.md D16): lockstep over ENet for two players.
## One side hosts (`--host[=port]`), the other joins (`--join=<ip>[:port]`). On a connect the
## server sends its game seed and both games rebuild their flows with it, so they run the same
## simulation from frame 0. After a flow has rebuilt, each side says GO; then every physics tick
## both send their physical pad word for frame + DELAY (ENet's reliable channel 0), and a frame
## steps only when both words for it have arrived (GGPO-style input delay, no rollback): menus,
## the VS screen and the fight all run in lockstep, each player's own pad standing for their side.

signal session_ready(seed: int)
signal status_changed(text: String)

const DEFAULT_PORT := 31313
const DELAY := 3                    ## input frames held back (60 Hz frames of input lag)
const CMD_INIT := 1                 ## the server's seed (the client sends it back as CMD_ACK)
const CMD_ACK := 2
const CMD_INPUT := 0                ## an input word: [CMD_INPUT, frame, pad word, escape bit]
                                    ## (a prefix, so that frames 1–3 cannot collide with the
                                    ## commands)
const CMD_GO := 3                   ## a side's flow has rebuilt with the seed: frames may start
const CMD_ESC := 4                  ## [CMD_ESC, frame]: the escape press of a frame whose word
                                    ## went out earlier (the game was waiting for the peer)
const TIMEOUT_FRAMES := 240         ## running ticks without the peer's word before the drop

enum Role { NONE, SERVER, CLIENT }

var role := Role.NONE
var session_active := false         ## the seed has crossed (session_ready has fired)
var running := false                ## both flows are up: the input exchange is on
var local_player := 0               ## the server is player 1, the client player 2
var seed := 0                       ## the flow's seed: the server's, sent to the client
var game_seed := 0                  ## this side's own flow seed (the NET screen hosts with it)
var net_ip := ""                    ## the NET screen's IP field (digits and dots)
var frame := 0                      ## the next simulation frame to step
var status := "": set = _set_status

var _conn: ENetConnection
var _peer: ENetPacketPeer
var _port := DEFAULT_PORT
var _words: Array[Dictionary] = [{}, {}]   ## per player: frame -> the pad word
var _esc: Array[Dictionary] = [{}, {}]     ## per player: frame -> 1 while the remake's Escape was
                                           ## pressed on that frame (the pause menu's leave)
var _go_local := false              ## our flow has rebuilt and said GO
var _go_remote := false
var _peer_missing := 0              ## running ticks without the peer's next word


func _ready() -> void:
	set_process(false)


## The server: waits for one opponent on the port. `game_seed` is the flow seed both sides use.
func host(port: int, game_seed: int) -> void:
	role = Role.SERVER
	local_player = 0
	seed = game_seed
	_port = port
	_conn = ENetConnection.new()
	if _conn.create_host_bound("*", _port, 1, 1) != OK:
		status = tr("NET_BIND_FAILED") % _port
		role = Role.NONE
		_conn = null
		return
	Log.debug("net: hosting on port %d (seed %d)" % [_port, seed])
	status = tr("NET_HOSTING") % _port


## The client: joins the server's address, takes its seed and becomes player 2.
func join(address: String, port: int) -> void:
	role = Role.CLIENT
	local_player = 1
	_port = port
	_conn = ENetConnection.new()
	_conn.create_host(1, 1)
	_peer = _conn.connect_to_host(address, _port, 1)
	Log.debug("net: joining %s:%d" % [address, _port])
	status = tr("NET_JOINING") % address


## Cancels a wait or drops a session: the game carries on offline.
func shutdown() -> void:
	var was := session_active
	session_active = false
	running = false
	role = Role.NONE
	if _conn != null:
		_conn.destroy()
	_conn = null
	_peer = null
	_words = [{}, {}]
	_esc = [{}, {}]
	_go_local = false
	_go_remote = false
	frame = 0
	status = tr("NET_LOST") if was else tr("NET_FAILED")


## The game has rebuilt its flow with the shared seed: says GO; the frames start when both have.
func flow_ready() -> void:
	if not session_active:
		return
	_go_local = true
	_send([CMD_GO])
	_maybe_start()


## A fresh flow: the buffers empty and both sides count frames from 0.
func reset_session() -> void:
	frame = 0
	_words = [{}, {}]
	_esc = [{}, {}]
	_go_local = false
	_go_remote = false
	running = false
	_peer_missing = 0


## One tick of the connection: events, packets, housekeeping. Called every physics tick.
func poll() -> void:
	if _conn == null:
		return
	while true:
		var event: Array = _conn.service(0)
		var type: int = event[0]
		match type:
			ENetConnection.EVENT_NONE:
				break
			ENetConnection.EVENT_ERROR:
				shutdown()
				break
			ENetConnection.EVENT_CONNECT:
				_peer = event[1] as ENetPacketPeer
				Log.debug("net: peer connected")
				if role == Role.SERVER:
					_send([CMD_INIT, seed])
				status = tr("NET_CONNECTED")
			ENetConnection.EVENT_DISCONNECT:
				shutdown()
				break
			ENetConnection.EVENT_RECEIVE:
				if event[1] == _peer:
					_receive()
	if running:
		_peer_missing += 1
		if _peer_missing > TIMEOUT_FRAMES:
			shutdown()


## Sends this tick's local word (with the local Escape's state) and returns both players' words
## and escape bits for the frame to step, or false when the peer's word has not arrived yet (the
## game waits and tries again next tick).
func exchange(local_word: int, local_escape: bool, out: PackedInt32Array,
		out_escape: PackedInt32Array) -> bool:
	if not running or _peer == null:
		return false
	var at := frame + DELAY
	var esc := 1 if local_escape else 0
	if not _words[local_player].has(at):
		var word := local_word & 0xFFFF
		_words[local_player][at] = word
		_esc[local_player][at] = esc
		_send([CMD_INPUT, at, word, esc])
	elif esc != 0 and (_esc[local_player].get(at, 0) as int) == 0:
		# The press came while the game was waiting for the peer: the frame's word went out
		# earlier, so the bit travels on its own.
		_esc[local_player][at] = 1
		_send([CMD_ESC, at])
	var remote := 1 - local_player
	if not _words[remote].has(frame):
		return false
	out[0] = _words[0][frame] as int
	out[1] = _words[1][frame] as int
	out_escape[0] = _esc[0].get(frame, 0) as int
	out_escape[1] = _esc[1].get(frame, 0) as int
	_words[0].erase(frame)
	_words[1].erase(frame)
	_esc[0].erase(frame)
	_esc[1].erase(frame)
	frame += 1
	_peer_missing = 0
	return true


func _maybe_start() -> void:
	if running or not _go_local or not _go_remote:
		return
	running = true
	# The delay's first frames use no held pad: the pads are read from the delay's tick on.
	for f in DELAY:
		_words[0][f] = 0
		_words[1][f] = 0
		_esc[0][f] = 0
		_esc[1][f] = 0
	_peer_missing = 0
	Log.debug("net: running (local go + remote go)")


func _send(packet: Array) -> void:
	if _peer != null:
		_peer.put_var(packet)


func _receive() -> void:
	while _peer.get_available_packet_count() > 0:
		var v: Variant = _peer.get_var()
		if not (v is Array):
			continue
		var packet: Array = v
		var cmd: int = packet[0]
		match cmd:
			CMD_INIT:
				if role == Role.CLIENT and not session_active:
					seed = packet[1]
					_send([CMD_ACK])
					session_active = true
					status = tr("NET_CONNECTED")
					Log.debug("net: seed received (%d), ack sent" % seed)
					session_ready.emit(seed)
			CMD_ACK:
				if role == Role.SERVER and not session_active:
					session_active = true
					status = tr("NET_CONNECTED")
					Log.debug("net: ack received, session up")
					session_ready.emit(seed)
			CMD_GO:
				_go_remote = true
				Log.debug("net: remote go")
				_maybe_start()
			CMD_INPUT:
				# An input word: [CMD_INPUT, frame, pad word, escape bit].
				var input_frame: int = packet[1]
				_words[1 - local_player][input_frame] = packet[2]
				if (packet[3] as int) != 0:
					_esc[1 - local_player][input_frame] = 1
				_peer_missing = 0
			CMD_ESC:
				# The escape press of a frame whose word went out earlier.
				_esc[1 - local_player][packet[1] as int] = 1


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


## The NET screen's IP field: a keystroke (only digits and dots count as an IP character).
func type_char(text: String) -> void:
	if net_ip.length() < 15 and (text >= "0" and text <= "9" or text == "."):
		net_ip += text


func backspace() -> void:
	if not net_ip.is_empty():
		net_ip = net_ip.left(net_ip.length() - 1)
