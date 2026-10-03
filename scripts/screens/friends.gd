extends Control
## Amis : demandes reçues, liste (statut en ligne), ajout par pseudo, défi, invitation au salon, profil, retrait.

var _list: VBoxContainer
var _name: LineEdit


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Mes amis", "key_tavern")
	var h := Game.hbox(10)
	body.add_child(h)
	_name = LineEdit.new()
	_name.placeholder_text = "Pseudo du joueur à ajouter"
	_name.custom_minimum_size = Vector2(360, 0)
	_name.text_submitted.connect(func(_t: String) -> void: _add())
	h.add_child(_name)
	h.add_child(Game.button("Ajouter en ami", _add, 0, Game.GREEN.darkened(0.35)))
	_list = Game.scroll_list(body, 6)
	Game.lobby_changed.connect(func(m: Dictionary) -> void:
		if m.t == "friends" and is_inside_tree(): _load())
	_load()


func _add() -> void:
	var res := await Api.post("/friends/add", {"name": _name.text.strip_edges()})
	Game.toast(res.get("error", res.get("text", "")))
	if not res.has("error"):
		_name.clear()
		_load()


func _load() -> void:
	var res := await Api.get_json("/friends")
	if not is_inside_tree(): return
	Game.clear(_list)
	var reqs: Array = res.get("requests", [])
	if reqs.size() > 0:
		_list.add_child(Game.label("Demandes d'ami reçues", 22, Game.GOLD, Game.font_title))
		for f in reqs:
			var h := Game.row_panel(_list)
			h.add_child(Game.icon(Game.look_tex(f.avatar), 48))
			h.add_child(Game.expand(Game.label(f.name, 20, Game.CREAM, Game.font_bold)))
			var id: String = f.id
			h.add_child(Game.button("Accepter", func() -> void: _act("/friends/accept", id), 0, Game.GREEN.darkened(0.35)))
			h.add_child(Game.button("Refuser", func() -> void: _act("/friends/decline", id), 0))
	var friends: Array = res.get("friends", [])
	_list.add_child(Game.label("Amis (%d)" % friends.size(), 22, Game.GOLD, Game.font_title))
	if friends.is_empty():
		_list.add_child(Game.label("Pas encore d'amis... Ajoute des joueurs par leur pseudo, ou depuis la taverne.", 17, Game.MUTED))
	for f in friends:
		var h := Game.row_panel(_list)
		h.add_child(Game.icon(Game.look_tex(f.avatar), 52))
		var v := Game.vbox(0)
		Game.expand(v)
		h.add_child(v)
		v.add_child(Game.label(f.name + ("  « %s »" % f.title if f.get("title") else ""), 20, Game.GOLD, Game.font_bold))
		var st := "En ligne" if f.online else "Hors ligne"
		if f.online and f.brute != null: st += " - joue %s (niv %d)" % [f.brute.name, f.brute.level]
		v.add_child(Game.label(st, 15, Game.GREEN.lightened(0.3) if f.online else Game.MUTED))
		var name: String = f.name
		var id: String = f.id
		h.add_child(Game.button("Profil", func() -> void: Game.goto("profile", {"name": name}), 0))
		if f.online and f.brute != null:
			var bid: String = f.brute.id
			h.add_child(Game.button("Défier", func() -> void: Api.ws_send({"t": "challenge", "to": bid}), 0, Color(0.55, 0.14, 0.1)))
			h.add_child(Game.button("Inviter au salon", func() -> void: _invite(bid), 0))
		h.add_child(Game.button("Retirer", func() -> void: _act("/friends/remove", id), 0, Color(0.3, 0.25, 0.22)))


func _invite(bid: String) -> void:
	if Game.party.is_empty():
		Api.ws_send({"t": "party_create", "mode": "coop_ai", "public": false})
		await get_tree().create_timer(0.4).timeout
	Api.ws_send({"t": "party_invite", "to": bid})
	Game.goto("tavern")


func _act(path: String, id: String) -> void:
	var res := await Api.post(path, {"id": id})
	if res.has("error"): Game.toast(res.error)
	_load()
