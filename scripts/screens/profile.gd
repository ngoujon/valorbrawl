extends Control
## Profil : le sien (avatar, devise, titre, aura, mot de passe) ou celui d'un autre joueur (params.name).

var _body: VBoxContainer


func setup(params: Dictionary) -> void:
	Audio.music("menu")
	var name: String = params.get("name", Game.account.get("name", ""))
	var mine: bool = name == Game.account.get("name", "")
	_body = Game.frame(self, "Mon profil" if mine else "Profil de %s" % name, "menu_bg", "hub" if mine else "friends")
	var res := await Api.get_json("/profile?name=" + name.uri_encode())
	if not is_inside_tree(): return
	if res.has("error"):
		_body.add_child(Game.label(res.error, 20, Color(1, 0.5, 0.4)))
		return
	_build(res.profile, mine)


func _build(pr: Dictionary, mine: bool) -> void:
	Game.clear(_body)
	var row := Game.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)
	var left := Game.panel(Vector2(360, 0))
	row.add_child(left)
	var lv := Game.vbox(8)
	left.add_child(lv)
	lv.add_child(Game.icon(Game.look_tex(pr.avatar, not Game.heroes.has(pr.avatar)), 220))
	lv.add_child(Game.title(pr.name, 36))
	if pr.get("title"):
		var t := Game.label("« %s »" % pr.title, 18, Game.GOLD, Game.font_bold)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(t)
	if str(pr.get("motto", "")) != "":
		var m := Game.label(pr.motto, 17, Game.CREAM)
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(m)
	var stats := Game.label("%d victoires - %d défaites\n%s" % [pr.wins, pr.losses, "En ligne" if pr.online else "Hors ligne"], 17, Game.MUTED)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(stats)
	var mid := Game.panel()
	Game.expand(mid)
	row.add_child(mid)
	var mv := Game.vbox(10)
	mid.add_child(mv)
	mv.add_child(Game.label("Brutes", 24, Game.GOLD, Game.font_title))
	var bh := Game.hbox(16)
	mv.add_child(bh)
	for b in pr.brutes:
		bh.add_child(Game.brute_card(b, 130))
	if not mine:
		if pr.online and pr.get("activeBrute") != null:
			var bid: String = pr.activeBrute
			mv.add_child(Game.button("Défier en duel", func() -> void: Api.ws_send({"t": "challenge", "to": bid}), 0, Color(0.55, 0.14, 0.1)))
		return
	# --- édition de son profil
	mv.add_child(Game.label("Personnalisation", 24, Game.GOLD, Game.font_title))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	mv.add_child(grid)
	grid.add_child(Game.label("Avatar", 18))
	var av := OptionButton.new()
	var avatars := []
	for h in Game.content.heroes: avatars.append([h.id, h.name])
	for st in Game.content.campaign:
		for b in Game.account.brutes:
			if b.campaign.get(st.id, false) and not avatars.any(func(x): return x[0] == st.boss):
				avatars.append([st.boss, Game.content.bosses[st.boss] + " (boss vaincu)"])
	for i in avatars.size():
		av.add_item(avatars[i][1], i)
		if avatars[i][0] == pr.avatar: av.select(i)
	grid.add_child(av)
	grid.add_child(Game.label("Devise", 18))
	var motto := LineEdit.new()
	motto.text = pr.get("motto", "")
	motto.max_length = 80
	motto.placeholder_text = "ex : Je cogne, donc je suis."
	motto.custom_minimum_size = Vector2(380, 0)
	grid.add_child(motto)
	grid.add_child(Game.label("Titre", 18))
	var title_opt := OptionButton.new()
	title_opt.add_item("(aucun)", 0)
	var titles: Array = Game.account.cosmetics.titles
	for i in titles.size():
		title_opt.add_item(titles[i], i + 1)
		if titles[i] == pr.get("title"): title_opt.select(i + 1)
	grid.add_child(title_opt)
	grid.add_child(Game.label("Aura de combat", 18))
	var aura_opt := OptionButton.new()
	aura_opt.add_item("(aucune)", 0)
	var auras: Array = Game.account.cosmetics.auras
	for i in auras.size():
		aura_opt.add_item(Game.account.auras.get(auras[i], {}).get("name", auras[i]), i + 1)
		if auras[i] == Game.account.profile.get("aura"): aura_opt.select(i + 1)
	grid.add_child(aura_opt)
	var hint := Game.label("Titres et auras se débloquent avec le passe de combat ; les avatars de boss en battant la campagne.", 14, Game.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(hint)
	var save := func() -> void:
		var body := {"avatar": avatars[av.selected][0], "motto": motto.text,
			"title": null if title_opt.selected == 0 else titles[title_opt.selected - 1],
			"aura": null if aura_opt.selected == 0 else auras[aura_opt.selected - 1]}
		var res := await Api.post("/profile", body)
		if res.has("error"):
			Game.toast(res.error, Color(1, 0.55, 0.45))
			return
		Game.account = res.account
		Game.toast("Profil enregistré !", Game.GOLD)
		Game.goto("profile")
	mv.add_child(Game.button("Enregistrer", save, 0, Game.GREEN.darkened(0.35)))
	# mot de passe
	mv.add_child(Game.label("Changer de mot de passe", 22, Game.GOLD, Game.font_title))
	var ph := Game.hbox(8)
	mv.add_child(ph)
	var old := LineEdit.new()
	old.secret = true
	old.placeholder_text = "Ancien"
	Game.expand(old)
	ph.add_child(old)
	var nw := LineEdit.new()
	nw.secret = true
	nw.placeholder_text = "Nouveau"
	Game.expand(nw)
	ph.add_child(nw)
	var change := func() -> void:
		var res := await Api.post("/profile/password", {"old": old.text, "new": nw.text})
		Game.toast(res.get("error", "Mot de passe modifié."), Game.GOLD)
		old.clear()
		nw.clear()
	ph.add_child(Game.button("Valider", change, 0))
