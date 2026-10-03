extends Node
## Mises à jour sans couper la partie :
## - le serveur publie /api/version : {version, pck, size, notes} ;
## - sur PC, le nouveau pack (.pck) est téléchargé en arrière-plan dans user://update/ pendant que l'on joue,
##   puis le jeu se relance dessus (--main-pack) quand le joueur le décide ; au lancement suivant il est repris d'office ;
## - sur le web, il suffit de recharger la page (le serveur sert déjà la nouvelle version).

signal update_available(info: Dictionary)
signal progress(ratio: float)
signal ready_to_restart

const DIR := "user://update/"
const CHECK_EVERY := 120.0

var current := ""
var latest: Dictionary = {}
var downloaded := false
var _http: HTTPRequest
var _timer := 0.0
var _downloading := false


func _ready() -> void:
	current = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	if not OS.has_feature("web") and not OS.has_feature("editor"):
		_apply_pending()
	_check.call_deferred()


static func newer(a: String, b: String) -> bool:
	## true si la version a est plus récente que b (format x.y.z).
	var pa := a.split(".")
	var pb := b.split(".")
	for i in max(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func _pending_version() -> String:
	var f := FileAccess.open(DIR + "version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


func _apply_pending() -> void:
	## Au démarrage : si un pack plus récent a été téléchargé et qu'on ne tourne pas déjà dessus, relancer dessus.
	var v := _pending_version()
	var pck := ProjectSettings.globalize_path(DIR + "game.pck")
	if v == "" or not FileAccess.file_exists(DIR + "game.pck"):
		return
	if not newer(v, current):
		if "--main-pack" not in OS.get_cmdline_args():
			DirAccess.remove_absolute(pck)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "version.txt"))
		return
	_relaunch(pck)


func _relaunch(pck: String) -> void:
	var args := PackedStringArray(["--main-pack", pck])
	for a in OS.get_cmdline_args():
		if a.begins_with("--server="):
			args.append(a)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= CHECK_EVERY:
		_timer = 0.0
		_check()


func _check() -> void:
	var res := await Api.get_json("/version")
	if res.has("error") or not res.has("version"):
		return
	if newer(str(res.version), current) and (latest.is_empty() or str(latest.version) != str(res.version)):
		latest = res
		downloaded = false
		update_available.emit(res)
		if not OS.has_feature("web") and _pending_version() == str(res.version) and FileAccess.file_exists(DIR + "game.pck"):
			downloaded = true
			ready_to_restart.emit()


func download() -> void:
	if _downloading or latest.is_empty() or OS.has_feature("web"):
		return
	_downloading = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_http = HTTPRequest.new()
	_http.download_file = DIR + "game.pck.part"
	_http.use_threads = true
	add_child(_http)
	var url := str(latest.pck)
	if not url.begins_with("http"):
		url = Api.base_url.trim_suffix("/api") + "/" + url
	_http.request(url)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	add_child(t)
	t.timeout.connect(func() -> void:
		var total := _http.get_body_size()
		if total > 0: progress.emit(float(_http.get_downloaded_bytes()) / total))
	var res: Array = await _http.request_completed
	t.queue_free()
	_http.queue_free()
	_downloading = false
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		Game.toast("Échec du téléchargement de la mise à jour. Nouvel essai plus tard.", Color(1, 0.5, 0.4))
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(DIR + "game.pck.part"), ProjectSettings.globalize_path(DIR + "game.pck"))
	var f := FileAccess.open(DIR + "version.txt", FileAccess.WRITE)
	f.store_string(str(latest.version))
	f.close()
	downloaded = true
	ready_to_restart.emit()


func restart() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
		return
	if downloaded:
		_relaunch(ProjectSettings.globalize_path(DIR + "game.pck"))
