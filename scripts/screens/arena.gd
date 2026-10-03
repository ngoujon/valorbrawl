extends Control
## Arène : défier les brutes des autres joueurs (combat asynchrone simulé par le serveur) ou en chercher une par nom.

var _list: HFlowContainer
var _search: LineEdit


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Arène : défie un joueur")
	var info := Game.label("Énergie : %d / %d - Choisis un adversaire parmi les brutes des autres joueurs." % [Game.brute.energy, Game.brute.energyMax], 18, Game.CREAM, Game.font_bold, 5)
	body.add_child(info)
	var h := Game.hbox(10)
	body.add_child(h)
	_search = LineEdit.new()
	_search.placeholder_text = "Chercher une brute ou un joueur par nom..."
	_search.custom_minimum_size = Vector2(420, 0)
	_search.text_submitted.connect(func(_t: String) -> void: _do_search())
	h.add_child(_search)
	h.add_child(Game.button("Chercher", _do_search, 130))
	h.add_child(Game.button("Nouveaux adversaires", _load, 0))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	_list = HFlowContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 14)
	_list.add_theme_constant_override("v_separation", 14)
	sc.add_child(_list)
	_load()


func _load() -> void:
	var res := await Api.post("/brute/opponents", {"brute": Game.brute.id})
	if not is_inside_tree(): return
	_show(res.get("opponents", []), "Aucun autre joueur pour l'instant... Invite tes amis ou défie l'IA !")


func _do_search() -> void:
	var res := await Api.post("/brute/search", {"q": _search.text})
	if not is_inside_tree(): return
	var mine := []
	for b in res.get("results", []):
		if b.owner != Game.account.name: mine.append(b)
	_show(mine, "Aucune brute trouvée.")


func _show(list: Array, empty: String) -> void:
	Game.clear(_list)
	if list.is_empty():
		_list.add_child(Game.label(empty, 20, Game.MUTED, null, 4))
	for b in list:
		var p := Game.panel(Vector2(280, 0))
		var v := Game.vbox(6)
		p.add_child(v)
		v.add_child(Game.brute_card(b, 170))
		var own := Game.label("Joueur : %s%s" % [b.owner, "  (en ligne)" if b.get("online", false) else ""], 15, Game.GREEN.lightened(0.3) if b.get("online", false) else Game.MUTED)
		own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(own)
		var st := Game.label(Game.stat_line(b), 15, Game.CREAM)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(st)
		var eq := Game.hbox(2)
		eq.alignment = BoxContainer.ALIGNMENT_CENTER
		for w in b.weapons.slice(0, 5): eq.add_child(Game.icon(Game.weapon_tex(w), 30, Game.weapons[w].name))
		for s in b.skills.slice(0, 4): eq.add_child(Game.icon(Game.skill_tex(s), 30, Game.skills[s].name))
		for pt in b.pets: eq.add_child(Game.icon(Game.pet_tex(pt), 30, Game.pets[pt].name))
		v.add_child(eq)
		var rec := Game.label("%d V - %d D" % [b.wins, b.losses], 15, Game.MUTED)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rec)
		var id: String = b.id
		v.add_child(Game.button("Combattre !", func() -> void: Game.start_fight("/fight/player", {"brute": Game.brute.id, "opponent": id}), 0, Color(0.55, 0.14, 0.1)))
		_list.add_child(p)
