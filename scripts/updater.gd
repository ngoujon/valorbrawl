extends Node
## Mises à jour sans couper la partie :
## - le serveur publie /api/version : {version, pck, size, notes} ;
## - le nouveau pack (.pck) est téléchargé en arrière-plan dans user://update/ pendant que l'on joue,
##   puis installé à côté de l'exe et le jeu relancé quand le joueur le décide (sinon au lancement suivant).

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
	if not OS.has_feature("editor"):
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
	## Au démarrage : si un pack plus récent a été téléchargé mais pas encore installé, l'installer (relance).
	var v := _pending_version()
	if v == "" or not FileAccess.file_exists(DIR + "game.pck"):
		return
	if not newer(v, current):
		# déjà installé : ménage
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "game.pck"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "version.txt"))
		return
	_install_and_relaunch()


func _install_and_relaunch() -> void:
	## Les templates release de Godot n'acceptent pas --main-pack : un script PowerShell masqué attend la fermeture
	## du jeu, remplace le .pck posé à côté de l'exe par le nouveau, puis relance l'exe.
	var exe := OS.get_executable_path()
	var target := exe.get_basename() + ".pck"
	var src := ProjectSettings.globalize_path(DIR + "game.pck")
	var ps1 := ProjectSettings.globalize_path(DIR + "install.ps1")
	var q := func(p: String) -> String: return "'" + p.replace("/", "\\").replace("'", "''") + "'"
	var lines := PackedStringArray([
		"$ErrorActionPreference = 'SilentlyContinue'",
		"Wait-Process -Id %d -Timeout 15" % OS.get_process_id(),
		"for ($i = 0; $i -lt 20; $i++) { try { Copy-Item -LiteralPath %s -Destination %s -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 } }" % [q.call(src), q.call(target)],
		"Start-Process -FilePath %s" % q.call(exe),
	])
	var script := char(0xFEFF) + "\r\n".join(lines) + "\r\n"
	var f := FileAccess.open(DIR + "install.ps1", FileAccess.WRITE)
	f.store_string(script)
	f.close()
	OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ps1]))
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
		if _pending_version() == str(res.version) and FileAccess.file_exists(DIR + "game.pck"):
			downloaded = true
			ready_to_restart.emit()


func download() -> void:
	if _downloading or latest.is_empty():
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
	if downloaded:
		_install_and_relaunch()
