extends Control
## Scène principale : écran courant, notifications, messages du lobby (défis, invitations, salons, combats),
## bannière de mise à jour, options et signalement de bug accessibles partout.

const SCREENS := {
	"login": "res://scripts/screens/login.gd",
	"select": "res://scripts/screens/select.gd",
	"create": "res://scripts/screens/create.gd",
	"hub": "res://scripts/screens/hub.gd",
	"arena": "res://scripts/screens/arena.gd",
	"ai": "res://scripts/screens/ai.gd",
	"campaign": "res://scripts/screens/campaign.gd",
	"tavern": "res://scripts/screens/tavern.gd",
	"leaderboard": "res://scripts/screens/leaderboard.gd",
	"fight": "res://scripts/screens/fight.gd",
	"friends": "res://scripts/screens/friends.gd",
	"pass": "res://scripts/screens/pass.gd",
	"profile": "res://scripts/screens/profile.gd",
	"reports": "res://scripts/screens/reports.gd",
}

var current: Control = null
var current_name := ""
var _layer: Control
var _toasts: VBoxContainer
var _top: HBoxContainer
var _banner: PanelContainer
var _banner_label: Label
var _banner_btn: Button


func _ready() -> void:
	Game.main = self
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_top = Game.hbox(6)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_top.position = Vector2(-10, 10)
	add_child(_top)
	var rep := Game.button("Signaler", func() -> void: report_popup(), 0)
	rep.custom_minimum_size = Vector2(0, 38)
	rep.tooltip_text = "Signaler un bug ou proposer une suggestion"
	_top.add_child(rep)
	var opt := Game.button("Options", _open_settings, 0)
	opt.custom_minimum_size = Vector2(0, 38)
	_top.add_child(opt)
	_build_banner()
	_toasts = Game.vbox(6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position.y = 60
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toasts)
	Api.ws_message.connect(_on_ws)
	Updater.update_available.connect(_on_update)
	Updater.progress.connect(func(r: float) -> void: _banner_label.text = "Téléchargement de la mise à jour : %d %%" % int(r * 100))
	Updater.ready_to_restart.connect(_on_update_ready)
	if "--check" in OS.get_cmdline_user_args():
		# Vérification (outil de dev) : charge tous les écrans puis quitte.
		for k in SCREENS:
			var sc = load(SCREENS[k])
			print("CHECK ", k, " ", "OK" if sc != null and sc.can_instantiate() else "ÉCHEC")
		get_tree().quit()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			_tour(a.substr(7))
			return
		if a.begins_with("--play-fight="):
			_play_fight(a.substr(13))
			return
	show_screen("login")


func _shot(dir: String, name: String, wait := 2.0) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("capture ", name)


func _play_fight(path: String) -> void:
	## Outil de bande-annonce : rejoue un combat enregistré (JSON) sans serveur, puis quitte.
	## À combiner avec --write-movie pour filmer (Movie Maker de Godot).
	var fight = JSON.parse_string(FileAccess.get_file_as_string(path))
	Game.brute = {"id": "trailer"}
	show_screen("fight", {"fight": fight, "side": 0, "cinematic": true, "replay": true})
	while is_instance_valid(current) and not current.finished:
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(2.5).timeout
	get_tree().quit()


func _tour(dir: String) -> void:
	## Outil de dev : parcourt tous les écrans avec un compte de test et enregistre des captures.
	DirAccess.make_dir_recursive_absolute(dir)
	Api.save_session("")
	show_screen("login")
	await _shot(dir, "01_login", 2.5)
	var user := "Testeur"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--user="): user = a.substr(7)
	var r := await Api.post("/login", {"user": user, "pass": "testtest"})
	if r.has("error"):
		r = await Api.post("/register", {"user": user, "pass": "testtest"})
	Api.save_session(r.token)
	Game.account = r.account
	if Game.account.brutes.is_empty():
		show_screen("create")
		await _shot(dir, "02_create", 2.0)
		var c := await Api.post("/brute/create", {"name": "Grobalaf", "hero": "barbare"})
		Game.account.brutes.append(c.brute)
	Game.brute = Game.account.brutes[0]
	Api.ws_connect(Game.brute.id)
	var n := 3
	if Game.brute.get("levelup") != null:
		show_screen("hub")
		await _shot(dir, "02_levelup", 3.0)
		var lv := await Api.post("/brute/levelup", {"brute": Game.brute.id, "choice": 0})
		Game.brute = lv.brute
	for scr in ["select", "hub", "arena", "ai", "campaign", "tavern", "leaderboard", "friends", "pass", "profile", "reports"]:
		show_screen(scr)
		await _shot(dir, "%02d_%s" % [n, scr], 3.0)
		n += 1
	var f := await Api.post("/fight/ai", {"brute": Game.brute.id, "difficulty": "normal"})
	if f.has("fight"):
		Game.brute = f.brute
		show_screen("fight", {"fight": f.fight, "side": 0})
		await _shot(dir, "20_fight_a", 4.0)
		await _shot(dir, "21_fight_b", 3.0)
		await _shot(dir, "22_fight_c", 3.0)
		current.speed = 4.0
		var t := 0.0
		while is_instance_valid(current) and not current.finished and t < 90.0:
			await get_tree().create_timer(0.5).timeout
			t += 0.5
		await _shot(dir, "23_fight_end", 1.5)
	get_tree().quit()


func show_screen(name: String, params := {}) -> void:
	if current:
		current.queue_free()
	var s: Control = load(SCREENS[name]).new()
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current = s
	current_name = name
	_layer.add_child(s)
	if s.has_method("setup"):
		s.setup(params)
	_top.visible = name != "fight"
	Api.ws_send({"t": "busy", "busy": name == "fight"})


func toast(text: String, color := Game.CREAM) -> void:
	var p := PanelContainer.new()
	var l := Game.label(text, 19, color, Game.font_bold)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ messages du lobby
func _on_ws(m: Dictionary) -> void:
	match m.get("t", ""):
		"welcome":
			Game.lobby_players = m.players
			Game.parties = m.parties
			Game.chat = m.chat
		"lobby":
			Game.lobby_players = m.players
			Game.parties = m.parties
		"chat":
			Game.chat.append(m)
			if Game.chat.size() > 50: Game.chat.pop_front()
		"pchat":
			Game.party_chat.append(m)
		"party":
			var had: bool = not Game.party.is_empty()
			Game.party = m.party if m.party != null else {}
			if Game.party.is_empty():
				Game.party_chat.clear()
			if m.has("text") and had:
				toast(m.text)
		"challenge":
			if current_name == "fight":
				Api.ws_send({"t": "decline", "from": m.from.id})
				return
			Audio.sfx("gong", 0.0, 0.6)
			_ask("Un défi !", m.from, "%s (%s) te provoque en duel !" % [m.from.name, m.from.owner],
				func() -> void: Api.ws_send({"t": "accept", "from": m.from.id}),
				func() -> void: Api.ws_send({"t": "decline", "from": m.from.id}))
		"invite":
			Audio.sfx("coins", 0.0, 0.7)
			_ask("Invitation", m.from, "%s t'invite dans son salon : %s" % [m.from.name, m.mode],
				func() -> void:
					Api.ws_send({"t": "party_join", "id": m.party})
					if current_name != "fight": show_screen("tavern"),
				func() -> void: pass)
		"fight":
			Game.set_brute(m.brute)
			if m.has("account"): Game.account = m.account
			show_screen("fight", {"fight": m.fight, "side": int(m.side), "live": true})
		"friends":
			if m.has("text"): toast(m.text, Game.GOLD)
		"info":
			toast(m.text)
	Game.lobby_changed.emit(m)


func _ask(title_text: String, who: Dictionary, text: String, yes: Callable, no: Callable) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := Game.panel(Vector2(460, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(p)
	var v := Game.vbox(10)
	p.add_child(v)
	v.add_child(Game.title(title_text, 38))
	v.add_child(Game.brute_card(who, 150))
	var l := Game.label(text, 19)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	v.add_child(l)
	var h := Game.hbox(16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var on_yes := func() -> void:
		shade.queue_free()
		yes.call()
	var on_no := func() -> void:
		shade.queue_free()
		no.call()
	h.add_child(Game.button("Accepter", on_yes, 160, Game.GREEN.darkened(0.3)))
	h.add_child(Game.button("Refuser", on_no, 160))
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		if is_instance_valid(shade): shade.queue_free())


# ------------------------------------------------------------------ mise à jour
func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.position.y = -12
	_banner.visible = false
	add_child(_banner)
	var h := Game.hbox(12)
	_banner.add_child(h)
	_banner_label = Game.label("", 18, Game.GOLD, Game.font_bold)
	h.add_child(_banner_label)
	_banner_btn = Game.button("Télécharger", _banner_action, 0, Game.GREEN.darkened(0.35))
	_banner_btn.custom_minimum_size = Vector2(0, 36)
	h.add_child(_banner_btn)
	var later := Game.button("Plus tard", func() -> void: _banner.visible = false, 0)
	later.custom_minimum_size = Vector2(0, 36)
	h.add_child(later)


func _on_update(info: Dictionary) -> void:
	_banner.visible = true
	var notes := str(info.get("notes", ""))
	_banner_label.text = "Mise à jour %s disponible%s" % [info.version, (" : " + notes) if notes != "" else ""]
	_banner_btn.text = "Recharger la page" if OS.has_feature("web") else "Télécharger"
	_banner_btn.disabled = false


func _on_update_ready() -> void:
	_banner.visible = true
	_banner_label.text = "Mise à jour %s prête ! Elle s'installera au prochain lancement." % Updater.latest.get("version", "")
	_banner_btn.text = "Redémarrer maintenant"
	_banner_btn.disabled = false


func _banner_action() -> void:
	if OS.has_feature("web") or Updater.downloaded:
		Updater.restart()
	else:
		_banner_btn.disabled = true
		_banner_label.text = "Téléchargement de la mise à jour..."
		Updater.download()


# ------------------------------------------------------------------ fenêtres
func modal(min_w := 460) -> Array:
	## Fenêtre modale : renvoie [voile, conteneur vertical].
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := Game.panel(Vector2(min_w, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(p)
	var v := Game.vbox(10)
	p.add_child(v)
	return [shade, v]


func report_popup() -> void:
	if Api.token == "":
		toast("Connecte-toi pour envoyer un signalement.")
		return
	var m := modal(560)
	var shade: ColorRect = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(Game.title("Signaler / Suggérer", 34))
	var type := OptionButton.new()
	type.add_item("Bug / problème")
	type.add_item("Suggestion / idée")
	v.add_child(type)
	var t := LineEdit.new()
	t.placeholder_text = "Titre (ex : le loup sort de l'écran)"
	t.max_length = 80
	v.add_child(t)
	var d := TextEdit.new()
	d.placeholder_text = "Décris ce qui s'est passé, ou ton idée..."
	d.custom_minimum_size = Vector2(520, 160)
	d.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(d)
	var st := Game.label("", 17, Game.GOLD)
	v.add_child(st)
	var h := Game.hbox(10)
	v.add_child(h)
	var send := func() -> void:
		var res := await Api.post("/report", {"type": "suggestion" if type.selected == 1 else "bug", "title": t.text, "text": d.text,
			"version": Updater.current, "platform": OS.get_name()})
		if res.has("error"):
			st.text = res.error
			return
		shade.queue_free()
		toast("Merci ! Ton signalement a bien été envoyé.", Game.GOLD)
	h.add_child(Game.button("Envoyer", send, 160, Game.GREEN.darkened(0.35)))
	h.add_child(Game.button("Voir les signalements", func() -> void:
		shade.queue_free()
		Game.goto("reports"), 0))
	h.add_child(Game.button("Annuler", shade.queue_free, 0))


func _open_settings() -> void:
	var m := modal(440)
	var shade: ColorRect = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(Game.title("Options", 36))
	for pair in [["Musique", "music_volume"], ["Effets sonores", "sfx_volume"]]:
		v.add_child(Game.label(pair[0], 19, Game.GOLD, Game.font_bold))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = Audio.get(pair[1])
		s.custom_minimum_size = Vector2(380, 24)
		var key: String = pair[1]
		s.value_changed.connect(func(val: float) -> void:
			Audio.set(key, val)
			Audio.save_settings())
		v.add_child(s)
	if not OS.has_feature("web"):
		v.add_child(Game.button("Plein écran", func() -> void:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN))
	if Api.token != "":
		v.add_child(Game.button("Se déconnecter", func() -> void:
			shade.queue_free()
			Api.logout()
			show_screen("login")))
	if not OS.has_feature("web"):
		v.add_child(Game.button("Quitter le jeu", func() -> void: get_tree().quit()))
	var ver := Game.label("Version %s" % Updater.current, 15, Game.MUTED)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ver)
	v.add_child(Game.button("Fermer", shade.queue_free))
