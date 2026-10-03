extends Control
## Multijoueur : joueurs connectés (duel direct, invitation, ami), salons hébergés par le serveur
## (PvP en équipes, coop contre l'IA, campagne en coop), parties publiques et chat de la taverne.

const MODES := [["pvp", "PvP en équipes"], ["coop_ai", "Coop contre l'IA"], ["coop_campaign", "Campagne en coop"]]
const DIFFS := [["facile", "Facile"], ["normal", "Normal"], ["difficile", "Difficile"], ["legendaire", "Légendaire"]]

var _players: VBoxContainer
var _center: VBoxContainer
var _chat: VBoxContainer
var _chat_in: LineEdit
var _pchat_in: LineEdit
var _status: Label
var _dirty := false


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Multijoueur : la Taverne", "key_tavern")
	_status = Game.label("", 16, Game.MUTED)
	body.add_child(_status)
	var row := Game.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	# joueurs
	var lp := Game.panel(Vector2(320, 0))
	row.add_child(lp)
	var lv := Game.vbox(6)
	lp.add_child(lv)
	lv.add_child(Game.label("Joueurs en ligne", 22, Game.GOLD, Game.font_title))
	_players = Game.scroll_list(lv, 4)
	# centre : salon
	var cp := Game.panel()
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cp)
	var cv := Game.vbox(6)
	cp.add_child(cv)
	_center = Game.scroll_list(cv, 8)
	# chat
	var rp := Game.panel(Vector2(330, 0))
	row.add_child(rp)
	var rv := Game.vbox(6)
	rp.add_child(rv)
	rv.add_child(Game.label("Chat de la taverne", 22, Game.GOLD, Game.font_title))
	_chat = Game.scroll_list(rv, 2)
	_chat_in = LineEdit.new()
	_chat_in.placeholder_text = "Écrire un message... (Entrée)"
	_chat_in.max_length = 200
	_chat_in.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "": Api.ws_send({"t": "chat", "text": t})
		_chat_in.clear())
	rv.add_child(_chat_in)
	Game.lobby_changed.connect(_on_lobby)
	Api.ws_state.connect(func(_c: bool) -> void: _dirty = true)
	if not Api.ws_connected():
		Api.ws_connect(Game.brute.id)
	_rebuild_all()


func _process(_d: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild_all()


func _on_lobby(m: Dictionary) -> void:
	if m.t == "chat":
		_build_chat()
	elif m.t in ["welcome", "lobby", "party", "pchat"]:
		_dirty = true


func _rebuild_all() -> void:
	_status.text = "Connecté au serveur - %d joueur(s) en ligne" % Game.lobby_players.size() if Api.ws_connected() else "Connexion au serveur..."
	_build_players()
	_build_center()
	_build_chat()


func _build_players() -> void:
	Game.clear(_players)
	var in_party := not Game.party.is_empty()
	for p in Game.lobby_players:
		var me: bool = p.id == Game.brute.id
		var h := Game.row_panel(_players)
		h.add_child(Game.icon(Game.look_tex(p.hero), 44))
		var v := Game.vbox(0)
		Game.expand(v)
		h.add_child(v)
		v.add_child(Game.label("%s%s" % [p.name, " (toi)" if me else ""], 17, Game.GOLD, Game.font_bold))
		var sub := "niv %d - %s" % [p.level, p.owner]
		if p.get("busy", false): sub += " - en combat"
		elif p.get("party") != null: sub += " - en salon"
		v.add_child(Game.label(sub, 14, Game.MUTED))
		if me:
			continue
		var bv := Game.vbox(2)
		h.add_child(bv)
		var pid: String = p.id
		var duel := _small("Duel", func() -> void: Api.ws_send({"t": "challenge", "to": pid}))
		duel.tooltip_text = "Duel immédiat en 1 contre 1"
		bv.add_child(duel)
		if in_party and not _member(pid):
			bv.add_child(_small("Inviter", func() -> void: Api.ws_send({"t": "party_invite", "to": pid})))
		var owner: String = p.owner
		if owner != Game.account.name:
			bv.add_child(_small("+ Ami", func() -> void: _add_friend(owner)))
	if Game.lobby_players.is_empty():
		_players.add_child(Game.label("Personne... pour l'instant !", 16, Game.MUTED))


func _small(text: String, cb: Callable) -> Button:
	var b := Game.button(text, cb, 80)
	b.custom_minimum_size = Vector2(80, 28)
	b.add_theme_font_size_override("font_size", 14)
	return b


func _member(bid: String) -> bool:
	for m in Game.party.get("members", []):
		if m.id == bid: return true
	return false


func _add_friend(name: String) -> void:
	var res := await Api.post("/friends/add", {"name": name})
	Game.toast(res.get("error", res.get("text", "")))


func _build_center() -> void:
	Game.clear(_center)
	_pchat_in = null
	if Game.party.is_empty():
		_build_no_party()
	else:
		_build_party()


func _build_no_party() -> void:
	_center.add_child(Game.label("Crée un salon et invite des joueurs", 24, Game.GOLD, Game.font_title))
	var info := Game.label("Les parties sont hébergées sur le serveur : invite tes amis ou des joueurs en ligne, ou rends ton salon public.", 16, Game.CREAM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center.add_child(info)
	var h := Game.hbox(8)
	_center.add_child(h)
	var colors := [Color(0.55, 0.14, 0.1), Color(0.42, 0.22, 0.45), Color(0.2, 0.38, 0.22)]
	for i in MODES.size():
		var mode: String = MODES[i][0]
		var b := Game.button(MODES[i][1], func() -> void: Api.ws_send({"t": "party_create", "mode": mode, "public": true}), 0, colors[i])
		Game.expand(b)
		h.add_child(b)
	_center.add_child(Game.label("Salons publics", 22, Game.GOLD, Game.font_title))
	if Game.parties.is_empty():
		_center.add_child(Game.label("Aucun salon public ouvert. Crée le tien !", 16, Game.MUTED))
	for p in Game.parties:
		var r := Game.row_panel(_center)
		var desc := "%s - hôte : %s (niv ~%d)" % [p.modeName, p.host, p.level]
		if p.mode == "coop_campaign": desc += " - %s" % Game.stages.get(p.stage, {}).get("name", "")
		elif p.mode == "coop_ai": desc += " - %s" % p.difficulty
		r.add_child(Game.expand(Game.label(desc, 17, Game.CREAM)))
		r.add_child(Game.label("%d/%d" % [p.size, p.max], 17, Game.GOLD, Game.font_bold))
		var id: String = p.id
		r.add_child(_small("Rejoindre", func() -> void: Api.ws_send({"t": "party_join", "id": id})))


func _build_party() -> void:
	var p: Dictionary = Game.party
	var host: bool = p.host == Game.brute.id
	var hdr := Game.hbox(10)
	_center.add_child(hdr)
	hdr.add_child(Game.expand(Game.label("Salon : %s" % p.modeName, 26, Game.GOLD, Game.font_title)))
	hdr.add_child(Game.label("Public" if p.public else "Privé", 16, Game.MUTED))
	if host:
		var opts := Game.hbox(8)
		_center.add_child(opts)
		var mode := OptionButton.new()
		for i in MODES.size():
			mode.add_item(MODES[i][1], i)
			if MODES[i][0] == p.mode: mode.select(i)
		mode.item_selected.connect(func(i: int) -> void: Api.ws_send({"t": "party_settings", "mode": MODES[i][0]}))
		opts.add_child(mode)
		if p.mode == "coop_ai":
			var diff := OptionButton.new()
			for i in DIFFS.size():
				diff.add_item(DIFFS[i][1], i)
				if DIFFS[i][0] == p.difficulty: diff.select(i)
			diff.item_selected.connect(func(i: int) -> void: Api.ws_send({"t": "party_settings", "difficulty": DIFFS[i][0]}))
			opts.add_child(diff)
		if p.mode == "coop_campaign":
			var st := OptionButton.new()
			var stages: Array = Game.content.campaign
			for i in stages.size():
				st.add_item("Ch. %d : %s" % [i + 1, stages[i].name], i)
				if stages[i].id == p.stage: st.select(i)
			st.item_selected.connect(func(i: int) -> void: Api.ws_send({"t": "party_settings", "stage": Game.content.campaign[i].id}))
			opts.add_child(st)
		var pub := CheckBox.new()
		pub.text = "Salon public"
		pub.button_pressed = p.public
		pub.toggled.connect(func(on: bool) -> void: Api.ws_send({"t": "party_settings", "public": on}))
		opts.add_child(pub)
	else:
		var d := "Mode : %s" % p.modeName
		if p.mode == "coop_ai": d += " - difficulté %s" % p.difficulty
		if p.mode == "coop_campaign": d += " - %s" % Game.stages.get(p.stage, {}).get("name", "")
		_center.add_child(Game.label(d, 17, Game.CREAM))
	if p.mode == "coop_campaign":
		var stg: Dictionary = Game.stages.get(p.stage, {})
		_center.add_child(Game.label("Boss : %s (renforcé selon le nombre de joueurs)" % stg.get("name", "?"), 16, Game.MUTED))
	# membres
	if p.mode == "pvp":
		var cols := Game.hbox(10)
		_center.add_child(cols)
		for side in 2:
			var col := Game.vbox(4)
			Game.expand(col)
			cols.add_child(col)
			col.add_child(Game.label("Équipe %d" % (side + 1), 20, Game.GOLD if side == 0 else Color(1, 0.55, 0.45), Game.font_title))
			for m in p.members:
				if int(m.side) == side: _member_row(col, m, host, p)
			var s := side
			col.add_child(_small("Rejoindre l'équipe %d" % (side + 1), func() -> void: Api.ws_send({"t": "party_side", "side": s})))
	else:
		var col := Game.vbox(4)
		_center.add_child(col)
		col.add_child(Game.label("Équipe (%d/%d)" % [p.members.size(), p.max], 20, Game.GOLD, Game.font_title))
		for m in p.members: _member_row(col, m, host, p)
	# actions
	var act := Game.hbox(8)
	_center.add_child(act)
	if host:
		act.add_child(Game.button("Lancer le combat !", func() -> void: Api.ws_send({"t": "party_start"}), 0, Game.GREEN.darkened(0.35)))
	else:
		var ready := false
		for m in p.members:
			if m.id == Game.brute.id: ready = m.ready
		var r := ready
		act.add_child(Game.button("Je ne suis plus prêt" if ready else "Je suis prêt !", func() -> void: Api.ws_send({"t": "party_ready", "ready": not r}), 0, Game.GREEN.darkened(0.35) if not ready else Color(0.4, 0.3, 0.2)))
	act.add_child(Game.button("Inviter des amis", _invite_friends, 0))
	act.add_child(Game.button("Quitter le salon", func() -> void: Api.ws_send({"t": "party_leave"}), 0))
	if p.get("lastFight") != null:
		var fid: String = p.lastFight
		act.add_child(Game.button("Revoir le dernier combat", func() -> void: _replay(fid), 0))
	# chat du salon
	_center.add_child(Game.label("Discussion du salon", 18, Game.GOLD, Game.font_bold))
	for msg in Game.party_chat.slice(-8):
		_center.add_child(Game.label("%s : %s" % [msg.from, msg.text], 15, Game.CREAM))
	_pchat_in = LineEdit.new()
	_pchat_in.placeholder_text = "Message au salon..."
	_pchat_in.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "": Api.ws_send({"t": "pchat", "text": t})
		_pchat_in.clear())
	_center.add_child(_pchat_in)


func _member_row(parent: Control, m: Dictionary, host: bool, p: Dictionary) -> void:
	var h := Game.row_panel(parent)
	h.add_child(Game.icon(Game.look_tex(m.hero), 48))
	var v := Game.vbox(0)
	Game.expand(v)
	h.add_child(v)
	var crown := " (hôte)" if m.id == p.host else ""
	v.add_child(Game.label("%s%s" % [m.name, crown], 18, Game.GOLD, Game.font_bold))
	v.add_child(Game.label("niv %d - %s - %s" % [m.level, m.owner, Game.stat_line(m)], 13, Game.MUTED))
	var state := "Hôte" if m.id == p.host else ("Prêt" if m.ready else "Pas prêt")
	if not m.get("connected", true): state = "Reconnexion..."
	h.add_child(Game.label(state, 16, Game.GREEN.lightened(0.3) if (m.ready or m.id == p.host) else Color(1, 0.6, 0.4), Game.font_bold))
	if host and m.id != Game.brute.id:
		var bid: String = m.id
		h.add_child(_small("Exclure", func() -> void: Api.ws_send({"t": "party_kick", "brute": bid})))


func _invite_friends() -> void:
	var res := await Api.get_json("/friends")
	var m: Array = Game.main.modal(460)
	var shade: ColorRect = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(Game.title("Inviter des amis", 32))
	var any := false
	for f in res.get("friends", []):
		if not f.online or f.brute == null:
			continue
		any = true
		var h := Game.row_panel(v)
		h.add_child(Game.icon(Game.look_tex(f.brute.hero), 40))
		h.add_child(Game.expand(Game.label("%s (%s, niv %d)" % [f.name, f.brute.name, f.brute.level], 17)))
		var bid: String = f.brute.id
		h.add_child(_small("Inviter", func() -> void: Api.ws_send({"t": "party_invite", "to": bid})))
	if not any:
		v.add_child(Game.label("Aucun ami connecté. Tu peux inviter n'importe quel\njoueur en ligne depuis la liste de gauche.", 16, Game.MUTED))
	v.add_child(Game.button("Fermer", shade.queue_free))


func _replay(id: String) -> void:
	var res := await Api.get_json("/fight?id=" + id)
	if res.has("error"):
		Game.toast(res.error)
		return
	var side := 0
	for t in res.fight.teams[1]:
		if t.id == Game.brute.id: side = 1
	Game.goto("fight", {"fight": res.fight, "side": side, "replay": true})


func _build_chat() -> void:
	Game.clear(_chat)
	for msg in Game.chat.slice(-40):
		var l := Game.label("%s : %s" % [msg.from, msg.text], 15, Game.GOLD if msg.from == "Héraut" else Game.CREAM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(290, 0)
		_chat.add_child(l)
	await get_tree().process_frame
	if is_inside_tree():
		var sc := _chat.get_parent() as ScrollContainer
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
