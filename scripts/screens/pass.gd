extends Control
## Passe de combat saisonnier : 30 paliers, piste gratuite + piste Légendaire (achetée avec les écus gagnés en jeu).

var _body: VBoxContainer


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	_body = Game.frame(self, "Passe de combat", "key_dragon")
	_build()


func _build() -> void:
	Game.clear(_body)
	var pass_data: Dictionary = Game.account.get("pass", {})
	if pass_data.is_empty():
		return
	var season: Dictionary = pass_data.season
	var head := Game.hbox(16)
	_body.add_child(head)
	var hv := Game.vbox(2)
	Game.expand(hv)
	head.add_child(hv)
	hv.add_child(Game.label(season.name, 26, Game.GOLD, Game.font_title, 6))
	var xp_in := int(pass_data.xp) % int(season.xpPerTier)
	var tier := int(pass_data.tier)
	hv.add_child(Game.label("Palier %d / %d   -   %d écus d'or" % [tier, season.tiers, int(Game.account.gold)], 18, Game.CREAM, Game.font_bold, 4))
	var b := Game.bar(xp_in if tier < int(season.tiers) else season.xpPerTier, season.xpPerTier, Color(0.85, 0.6, 0.15), 18)
	b.custom_minimum_size = Vector2(420, 18)
	hv.add_child(b)
	hv.add_child(Game.label("Gagne de l'XP de passe en combattant (victoire +40, défaite +20, x1,25 en multijoueur) et avec les quêtes du jour (+120).", 15, Game.MUTED, null, 3))
	var buy: Control
	if not pass_data.premium:
		buy = Game.button("Débloquer la piste Légendaire (%d écus)" % season.premiumCost, _buy, 0, Color(0.55, 0.42, 0.1))
	else:
		buy = Game.label("Piste Légendaire débloquée !", 20, Game.GOLD, Game.font_bold, 5)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(buy)
	var all := Game.button("Tout récupérer", _claim_all, 0, Game.GREEN.darkened(0.35))
	all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(all)
	# paliers
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(sc)
	var row := Game.hbox(8)
	sc.add_child(row)
	var labels := Game.vbox(8)
	labels.add_child(Game.label(" ", 18))
	var lf := Game.label("Gratuit", 18, Game.CREAM, Game.font_bold, 4)
	lf.custom_minimum_size = Vector2(100, 150)
	lf.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	labels.add_child(lf)
	var lp := Game.label("Légendaire", 18, Game.GOLD, Game.font_bold, 4)
	lp.custom_minimum_size = Vector2(100, 150)
	lp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	labels.add_child(lp)
	row.add_child(labels)
	for t in pass_data.tiers:
		var col := Game.vbox(8)
		var num := Game.label("%d" % t.tier, 18, Game.GOLD if int(t.tier) <= tier else Game.MUTED, Game.font_title, 4)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(num)
		col.add_child(_cell(t, "free", tier, pass_data))
		col.add_child(_cell(t, "premium", tier, pass_data))
		row.add_child(col)
	await get_tree().process_frame
	if is_inside_tree():
		sc.scroll_horizontal = max(0, (tier - 2) * 128)


func _reward_text(r: Dictionary) -> String:
	match r.type:
		"gold": return "%d écus" % r.v
		"energy": return "%d potions d'énergie" % r.v
		"aura": return Game.account.auras.get(r.id, {}).get("name", r.id)
		"title": return "Titre : %s" % r.id
	return "?"


func _cell(t: Dictionary, track: String, tier: int, pass_data: Dictionary) -> Control:
	var r: Dictionary = t[track]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(120, 150)
	var st := StyleBoxFlat.new()
	var reached := int(t.tier) <= tier
	var claimed: bool = int(t.tier) in pass_data.claimed[track]
	var locked: bool = track == "premium" and not pass_data.premium
	st.bg_color = Color(0.35, 0.27, 0.1, 0.95) if track == "premium" else Color(0.22, 0.15, 0.1, 0.95)
	if not reached: st.bg_color = st.bg_color.darkened(0.45)
	st.border_color = Game.GOLD if reached and not claimed else Color(0.4, 0.33, 0.25)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", st)
	var v := Game.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var icon_tex: Texture2D = null
	match r.type:
		"gold": icon_tex = Game.weapon_tex("dague")
		"energy": icon_tex = Game.skill_tex("potion")
		"aura": icon_tex = Game.skill_tex("vitalite")
		"title": icon_tex = Game.skill_tex("maitre")
	if r.type == "gold": icon_tex = Game.tex("res://assets/ui/coin.png") if Game.tex("res://assets/ui/coin.png") else Game.skill_tex("maitre")
	var ic := Game.icon(icon_tex, 54)
	if r.type == "aura":
		ic.modulate = Color(Game.account.auras.get(r.id, {}).get("color", "#ffffff"))
	v.add_child(ic)
	var l := Game.label(_reward_text(r), 14, Game.CREAM, Game.font_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(108, 0)
	v.add_child(l)
	if claimed:
		v.add_child(Game.label("Récupéré", 13, Game.GREEN.lightened(0.3)))
	elif locked:
		v.add_child(Game.label("Verrouillé", 13, Game.MUTED))
	elif reached:
		var tr := track
		var tn := int(t.tier)
		var b := Game.button("Prendre", func() -> void: _claim(tr, tn), 0, Game.GREEN.darkened(0.35))
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", 14)
		v.add_child(b)
	return p


func _claim(track: String, tier: int) -> void:
	var res := await Api.post("/pass/claim", {"track": track, "tier": tier})
	_after(res, "Récompense récupérée !")


func _claim_all() -> void:
	var res := await Api.post("/pass/claimall", {})
	_after(res, "%d récompense(s) récupérée(s) !" % int(res.get("claimed", 0)))


func _buy() -> void:
	var res := await Api.post("/pass/premium", {})
	_after(res, "Piste Légendaire débloquée !")


func _after(res: Dictionary, ok: String) -> void:
	if res.has("error"):
		Game.toast(res.error, Color(1, 0.55, 0.45))
		return
	Audio.sfx("coins")
	Game.account = res.account
	Game.toast(ok, Game.GOLD)
	_build()
