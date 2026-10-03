extends Node
## Client du serveur : requêtes HTTP (JSON) et WebSocket de la taverne.

signal ws_message(msg: Dictionary)
signal ws_state(connected: bool)

const DESKTOP_SERVER := "https://vps-3962b7dc.vps.ovh.net/test-labrute/api"
const SESSION_FILE := "user://session.cfg"

var base_url := DESKTOP_SERVER
var token := ""
var _ws: WebSocketPeer = null
var _ws_open := false
var _ws_ping := 0.0
var _ws_brute := ""
var _retry := 0.0
var _retry_delay := 1.0
var _was_connected := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--server="):
			base_url = arg.substr(9)
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_FILE) == OK:
		token = cfg.get_value("session", "token", "")


func save_session(tok: String) -> void:
	token = tok
	var cfg := ConfigFile.new()
	cfg.load(SESSION_FILE)
	cfg.set_value("session", "token", tok)
	cfg.save(SESSION_FILE)


func logout() -> void:
	save_session("")
	ws_close()
	Game.account = {}
	Game.brute = {}


## Requête JSON. Renvoie le dictionnaire de réponse ; en cas d'erreur, {"error": "..."}.
func request(method: String, path: String, body = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var m := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var data := JSON.stringify(body) if body != null else ""
	var err := http.request(base_url + path, headers, m, data)
	if err != OK:
		http.queue_free()
		return {"error": "Impossible de joindre le serveur."}
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Serveur injoignable. Vérifie ta connexion."}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "Réponse invalide du serveur (%d)." % res[1]}
	if res[1] == 401 and token != "":
		save_session("")
	return parsed


func post(path: String, body := {}) -> Dictionary:
	return await request("POST", path, body)


func get_json(path: String) -> Dictionary:
	return await request("GET", path)


# ------------------------------------------------------------------ WebSocket (taverne)
func ws_connect(brute_id: String) -> void:
	_ws_brute = brute_id
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_send({"t": "hello", "brute": brute_id})
		return
	_ws = WebSocketPeer.new()
	var url := base_url.replace("https://", "wss://").replace("http://", "ws://") + "/ws?token=" + token
	_ws_open = false
	if _ws.connect_to_url(url) != OK:
		_ws = null
		ws_state.emit(false)


func ws_close() -> void:
	_ws_brute = ""
	if _ws:
		_ws.close()
	_ws = null
	_ws_open = false


func ws_send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func ws_connected() -> bool:
	return _ws != null and _ws_open


func _process(delta: float) -> void:
	if _ws == null:
		# Reconnexion automatique (serveur redémarré pour une mise à jour, coupure réseau...).
		if _ws_brute != "" and token != "":
			_retry -= delta
			if _retry <= 0.0:
				_retry_delay = min(_retry_delay * 1.6, 10.0)
				_retry = _retry_delay
				ws_connect(_ws_brute)
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _ws_open:
			_ws_open = true
			_retry_delay = 1.0
			if _was_connected:
				Game.toast("Reconnecté au serveur.", Game.GREEN.lightened(0.3))
			_was_connected = true
			ws_state.emit(true)
			ws_send({"t": "hello", "brute": _ws_brute})
		while _ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if typeof(m) == TYPE_DICTIONARY:
				ws_message.emit(m)
		_ws_ping += delta
		if _ws_ping > 25.0:
			_ws_ping = 0.0
			ws_send({"t": "ping"})
	elif st == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_ws_open = false
		ws_state.emit(false)
