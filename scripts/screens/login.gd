extends Control
## Écran titre : connexion / inscription (reconnexion automatique si une session est enregistrée).

var _user: LineEdit
var _pass: LineEdit
var _status: Label
var _box: VBoxContainer


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	add_child(Game.background("menu_bg", 0.25))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := Game.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var logo := Game.icon(Game.tex("res://assets/ui/logo.png"), 0)
	logo.custom_minimum_size = Vector2(560, 300)
	col.add_child(logo)
	var p := Game.panel(Vector2(420, 0))
	col.add_child(p)
	_box = Game.vbox(10)
	p.add_child(_box)
	_status = Game.label("", 18, Game.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Api.token != "":
		_status.text = "Connexion à la taverne..."
		_box.add_child(_status)
		_auto_login()
	else:
		_build_form()


func _build_form() -> void:
	Game.clear(_box)
	_box.add_child(Game.label("Entre dans l'arène !", 24, Game.GOLD, Game.font_title))
	_user = LineEdit.new()
	_user.placeholder_text = "Pseudo"
	_user.max_length = 16
	_box.add_child(_user)
	_pass = LineEdit.new()
	_pass.placeholder_text = "Mot de passe"
	_pass.secret = true
	_pass.text_submitted.connect(func(_t: String) -> void: _submit(false))
	_box.add_child(_pass)
	var h := Game.hbox(10)
	h.add_child(Game.button("Connexion", func() -> void: _submit(false), 190))
	h.add_child(Game.button("Créer un compte", func() -> void: _submit(true), 190, Game.GREEN.darkened(0.35)))
	_box.add_child(h)
	_status = Game.label("", 18, Game.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	_box.add_child(_status)
	var hint := Game.label("Nouveau ? Choisis un pseudo et un mot de passe puis « Créer un compte ».", 15, Game.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(380, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(hint)
	_user.grab_focus.call_deferred()


func _submit(register: bool) -> void:
	_status.text = "..."
	var res := await Api.post("/register" if register else "/login", {"user": _user.text.strip_edges(), "pass": _pass.text})
	if res.has("error"):
		_status.text = res.error
		return
	Api.save_session(res.token)
	_enter(res.account)


func _auto_login() -> void:
	var res := await Api.get_json("/me")
	if res.has("error"):
		Api.save_session("")
		_build_form()
		_status.text = res.error
		return
	_enter(res.account)


func _enter(acc: Dictionary) -> void:
	Game.account = acc
	if acc.brutes.size() == 0:
		Game.goto("create")
	else:
		Game.goto("select")
