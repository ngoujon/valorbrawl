extends Control
## Cellule de la brute : caractéristiques, armes, compétences, familiers, accès aux modes de jeu et historique.

var _content: Control


func setup(params: Dictionary) -> void:
	Audio.music("menu")
	add_child(Game.background("arene", 0.55))
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_build()
	if params.get("new", false):
		var ch: Array = []
		for w in Game.brute.weapons: ch.append(Game.weapons[w].name)
		for s in Game.brute.skills: ch.append(Game.skills[s].name)
		for p in Game.brute.pets: ch.append(Game.pets[p].name)
		Game.toast("Les dieux de l'arène t'offrent : %s !" % ", ".join(ch), Game.GOLD)
	_refresh()


func _refresh() -> void:
	var res := await Api.get_json("/me")
	if res.has("error") or not is_inside_tree():
		return
	Game.account = res.account
	for b in res.account.brutes:
		if b.id == Game.brute.id:
			Game.brute = b
	_build()


func _build() -> void:
	Game.clear(_content)
	var b: Dictionary = Game.brute
	var root := Game.hbox(16)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_right = -20
	root.offset_top = 60
	root.offset_bottom = -16
	_content.add_child(root)

	var top := Game.hbox(12)
	top.position = Vector2(20, 10)
	_content.add_child(top)
	top.add_child(Game.button("< Mes brutes", func() -> void: Game.goto("select"), 150))
	var en := Game.label("Énergie : %d / %d" % [b.energy, b.energyMax], 19, Game.GOLD, Game.font_bold, 6)
	en.tooltip_text = "Combats restants aujourd'hui (la campagne n'en consomme pas)."
	en.mouse_filter = Control.MOUSE_FILTER_STOP
	top.add_child(en)
	var acc: Dictionary = Game.account
	var potions: int = int(acc.get("items", {}).get("energy", 0))
	if potions > 0:
		top.add_child(Game.button("Potion d'énergie (%d)" % potions, _use_potion, 0, Color(0.2, 0.4, 0.55)))
	top.add_child(Game.label("   %d écus d'or" % int(acc.get("gold", 0)), 19, Color(1, 0.85, 0.3), Game.font_bold, 6))

	# --- colonne gauche : la brute
	var left := Game.panel(Vector2(360, 0))
	root.add_child(left)
	var lv := Game.vbox(6)
	left.add_child(lv)
	var name_l := Game.title(b.name, 38)
	lv.add_child(name_l)
	var sub := "Niveau %d" % b.level
	if b.get("title"): sub += "  -  %s" % b.title
	var sub_l := Game.label(sub, 19, Game.MUTED)
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(sub_l)
	var img := Game.icon(Game.look_tex(b.hero), 250)
	lv.add_child(img)
	img.pivot_offset = Vector2(160, 250)
	var tw := img.create_tween().set_loops()
	tw.tween_property(img, "scale", Vector2(1.0, 1.03), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(img, "scale", Vector2(1.0, 1.0), 0.9).set_trans(Tween.TRANS_SINE)
	lv.add_child(Game.label("Expérience", 16, Game.MUTED))
	lv.add_child(Game.bar(b.xp, b.xpNext, Color(0.3, 0.55, 0.9), 18))
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	lv.add_child(stats)
	for k in ["hp", "str", "agi", "spd"]:
		stats.add_child(Game.label(Game.STAT_NAMES[k], 19, Game.CREAM))
		stats.add_child(Game.label(str(int(b.stats[k])), 19, Game.GOLD, Game.font_bold))
	var rec := Game.label("%d victoires  -  %d défaites" % [b.wins, b.losses], 17, Game.MUTED)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(rec)

	# --- colonne centrale : équipement
	var mid := Game.panel()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	var mv := Game.vbox(8)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(mv)
	_section(mv, "Armes", b.weapons, func(id: String) -> Array:
		var w: Dictionary = Game.weapons[id]
		return [Game.weapon_tex(id), "%s\n%d dégâts, vitesse x%.2f" % [w.name, w.dmg, w.speed]], "Aucune arme : ta brute se bat à mains nues !")
	_section(mv, "Compétences", b.skills, func(id: String) -> Array:
		var s: Dictionary = Game.skills[id]
		return [Game.skill_tex(id), "%s%s\n%s" % [s.name, " (super)" if s.kind == "super" else "", s.desc]], "Aucune compétence pour l'instant.")
	_section(mv, "Familiers", b.pets, func(id: String) -> Array:
		var p: Dictionary = Game.pets[id]
		return [Game.pet_tex(id), "%s\n%d PV, %d dégâts\n%s" % [p.name, p.hp, p.dmg, p.desc]], "Aucun familier.")

	# --- colonne droite : modes + historique
	var right := Game.vbox(8)
	right.custom_minimum_size = Vector2(330, 0)
	root.add_child(right)
	right.add_child(Game.button("Arène : défier un joueur", func() -> void: Game.goto("arena"), 0, Color(0.55, 0.14, 0.1)))
	right.add_child(Game.button("Défier l'IA", func() -> void: Game.goto("ai"), 0, Color(0.42, 0.22, 0.45)))
	right.add_child(Game.button("Campagne", func() -> void: Game.goto("campaign"), 0, Color(0.2, 0.38, 0.22)))
	right.add_child(Game.button("Multijoueur : salons & taverne", func() -> void: Game.goto("tavern"), 0, Color(0.5, 0.33, 0.12)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	var nreq: int = int(Game.account.get("friendRequests", 0))
	var small := [
		["Passe de combat", "pass", Color(0.55, 0.42, 0.1)],
		["Amis" + (" (%d)" % nreq if nreq > 0 else ""), "friends", Color(0.2, 0.42, 0.42)],
		["Profil", "profile", Color(0.35, 0.28, 0.45)],
		["Classement", "leaderboard", Color(0.25, 0.3, 0.45)],
	]
	for it in small:
		var target: String = it[1]
		var bt := Game.button(it[0], func() -> void: Game.goto(target), 0, it[2])
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.add_theme_font_size_override("font_size", 17)
		grid.add_child(bt)
	var quests: Array = Game.account.get("quests", [])
	if quests.size() > 0:
		var qp := Game.panel()
		right.add_child(qp)
		var qv := Game.vbox(2)
		qp.add_child(qv)
		qv.add_child(Game.label("Quêtes du jour", 18, Game.GOLD, Game.font_title))
		for q in quests:
			var ql := Game.label("%s %s (%d/%d)" % ["[OK]" if q.done else "-", q.text, q.progress, q.goal], 15, Game.GREEN.lightened(0.3) if q.done else Game.CREAM)
			qv.add_child(ql)
	var hp := Game.panel()
	hp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(hp)
	var hv := Game.vbox(4)
	hp.add_child(hv)
	hv.add_child(Game.label("Derniers combats", 20, Game.GOLD, Game.font_title))
	var hs := ScrollContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hv.add_child(hs)
	var list := Game.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.add_child(list)
	if b.history.is_empty():
		list.add_child(Game.label("Aucun combat. En avant !", 16, Game.MUTED))
	for h in b.history:
		var mode_names := {"arena": "Arène", "arena_def": "Défense", "ai": "IA", "campaign": "Campagne", "live": "Duel", "live_def": "Duel",
			"pvp": "PvP", "coop_ai": "Coop IA", "coop_campaign": "Campagne coop"}
		var btn := Button.new()
		btn.text = "%s  %s - %s" % ["V" if h.won else "D", mode_names.get(h.mode, h.mode), h.foe]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", Game.GREEN.lightened(0.3) if h.won else Color(1, 0.5, 0.45))
		btn.custom_minimum_size = Vector2(0, 30)
		btn.clip_text = true
		btn.tooltip_text = "Revoir ce combat"
		var fid: String = h.id
		btn.pressed.connect(func() -> void: _replay(fid))
		list.add_child(btn)

	if b.get("levelup") != null:
		_levelup_modal(b.levelup)


func _section(parent: Control, title_text: String, ids: Array, info: Callable, empty: String) -> void:
	parent.add_child(Game.label(title_text, 24, Game.GOLD, Game.font_title))
	if ids.is_empty():
		parent.add_child(Game.label(empty, 16, Game.MUTED))
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	for id in ids:
		var d: Array = info.call(id)
		var cell := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.32, 0.22, 0.14)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(4)
		cell.add_theme_stylebox_override("panel", st)
		cell.add_child(Game.icon(d[0], 76, d[1]))
		cell.tooltip_text = d[1]
		flow.add_child(cell)


func _use_potion() -> void:
	var res := await Api.post("/item/energy", {"brute": Game.brute.id})
	if res.has("error"):
		Game.toast(res.error)
		return
	Audio.sfx("heal")
	Game.account = res.account
	Game.set_brute(res.brute)
	Game.toast("+5 combats pour aujourd'hui !", Game.GOLD)
	_build()


func _replay(id: String) -> void:
	var res := await Api.get_json("/fight?id=" + id)
	if res.has("error"):
		Game.toast(res.error)
		return
	var side := 0
	for t in res.fight.teams[1]:
		if t.id == Game.brute.id:
			side = 1
	Game.goto("fight", {"fight": res.fight, "side": side, "replay": true})


func _levelup_modal(choices: Array) -> void:
	Audio.sfx("levelup")
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.add_child(shade)
	var col := Game.vbox(20)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	shade.add_child(col)
	col.add_child(Game.title("Niveau %d !" % Game.brute.level, 56))
	var l := Game.label("Choisis ton bonus :", 22, Game.CREAM, Game.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var row := Game.hbox(30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for i in choices.size():
		var t: Array = Game.choice_text(choices[i])
		var p := Game.panel(Vector2(300, 300))
		var v := Game.vbox(8)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(v)
		if t[2]:
			v.add_child(Game.icon(t[2], 130))
		else:
			v.add_child(Game.title("+", 100))
		var n := Game.label(t[0], 22, Game.GOLD, Game.font_bold)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
		var d := Game.label(t[1], 16, Game.CREAM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(260, 0)
		v.add_child(d)
		var idx := i
		v.add_child(Game.button("Choisir", func() -> void: _choose(idx), 0, Game.GREEN.darkened(0.35)))
		row.add_child(p)
		p.scale = Vector2(0.6, 0.6)
		p.pivot_offset = Vector2(150, 150)
		p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_delay(0.1 * i)


func _choose(i: int) -> void:
	var res := await Api.post("/brute/levelup", {"brute": Game.brute.id, "choice": i})
	if res.has("error"):
		Game.toast(res.error)
		return
	Audio.sfx("coins")
	Game.set_brute(res.brute)
	Game.toast("Tu obtiens : %s" % Game.choice_text(res.chosen)[0], Game.GOLD)
	_build()
