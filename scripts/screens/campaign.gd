extends Control
## Campagne « La Quête du Roi-Dragon » : 10 chapitres sur la carte du royaume, en solo ou en coop.

const NODES := [Vector2(0.10, 0.70), Vector2(0.20, 0.50), Vector2(0.30, 0.72), Vector2(0.40, 0.48), Vector2(0.50, 0.66),
	Vector2(0.58, 0.40), Vector2(0.68, 0.26), Vector2(0.75, 0.55), Vector2(0.84, 0.72), Vector2(0.90, 0.36)]

var _detail: PanelContainer
var _map: Control


func setup(_params: Dictionary) -> void:
	Audio.music("campagne")
	add_child(Game.background("map_bg", 0.1))
	_map = Control.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map)
	var top := Game.hbox(16)
	top.position = Vector2(20, 10)
	add_child(top)
	top.add_child(Game.button("< Retour", func() -> void: Game.goto("hub"), 130))
	top.add_child(Game.label("La Quête du Roi-Dragon", 40, Game.GOLD, Game.font_title, 10))
	_detail = Game.panel(Vector2(400, 0))
	_detail.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_detail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_detail.grow_vertical = Control.GROW_DIRECTION_BOTH
	_detail.position.x -= 16
	_detail.visible = false
	add_child(_detail)
	_draw_map.call_deferred()


func _done(id: String) -> bool:
	return Game.brute.get("campaign", {}).get(id, false)


func _draw_map() -> void:
	var vp := get_viewport_rect().size
	var stages: Array = Game.content.campaign
	var line := Line2D.new()
	line.width = 6
	line.default_color = Color(0.35, 0.2, 0.08, 0.8)
	_map.add_child(line)
	var next_open := 0
	for i in stages.size():
		if _done(stages[i].id): next_open = i + 1
	for i in stages.size():
		var st: Dictionary = stages[i]
		var pos := Vector2(40 + NODES[i].x * (vp.x - 470), NODES[i].y * vp.y)
		line.add_point(pos)
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 96)
		b.size = Vector2(96, 96)
		b.position = pos - Vector2(48, 48)
		b.icon = Game.look_tex(st.boss, true)
		b.expand_icon = true
		b.tooltip_text = "Chapitre %d : %s" % [i + 1, st.name]
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(48)
		style.set_border_width_all(4)
		style.set_content_margin_all(6)
		if _done(st.id):
			style.bg_color = Color(0.25, 0.45, 0.2, 0.95)
			style.border_color = Game.GOLD
		elif i == next_open:
			style.bg_color = Color(0.6, 0.2, 0.1, 0.95)
			style.border_color = Color(1, 0.9, 0.5)
			b.pivot_offset = Vector2(48, 48)
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2(1.1, 1.1), 0.6)
			tw.tween_property(b, "scale", Vector2.ONE, 0.6)
		else:
			style.bg_color = Color(0.2, 0.18, 0.16, 0.9)
			style.border_color = Color(0.4, 0.35, 0.3)
			b.modulate = Color(0.6, 0.6, 0.6)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("hover", style)
		b.add_theme_stylebox_override("pressed", style)
		var idx := i
		b.pressed.connect(func() -> void: _show(idx, idx <= next_open))
		_map.add_child(b)
		var num := Game.label(str(i + 1), 22, Game.GOLD, Game.font_title, 8)
		num.position = pos + Vector2(-8, 40)
		_map.add_child(num)
	_show(min(next_open, stages.size() - 1), true)


func _show(i: int, unlocked: bool) -> void:
	Audio.click()
	var st: Dictionary = Game.content.campaign[i]
	Game.clear(_detail)
	_detail.visible = true
	var v := Game.vbox(8)
	_detail.add_child(v)
	v.add_child(Game.label("Chapitre %d" % (i + 1), 18, Game.MUTED))
	v.add_child(Game.label(st.name, 30, Game.GOLD, Game.font_title, 6))
	v.add_child(Game.icon(Game.look_tex(st.boss, true), 190))
	var info := Game.label("Niveau conseillé : %d   -   PV %d   FOR %d" % [st.level, st.stats.hp, st.stats.str], 16, Game.CREAM, Game.font_bold)
	v.add_child(info)
	var intro := Game.label(st.intro, 16, Game.CREAM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(370, 0)
	v.add_child(intro)
	var rw: Array = Game.choice_text(st.reward)
	var rh := Game.hbox(8)
	if rw[2]: rh.add_child(Game.icon(rw[2], 40))
	rh.add_child(Game.label("Récompense : %s" % rw[0], 17, Game.GOLD, Game.font_bold))
	v.add_child(rh)
	if _done(st.id):
		v.add_child(Game.label("Chapitre terminé ! Tu peux le rejouer (sans récompense).", 15, Game.GREEN.lightened(0.3)))
	if not unlocked:
		v.add_child(Game.label("Termine d'abord le chapitre précédent.", 17, Color(1, 0.55, 0.45), Game.font_bold))
		return
	var id: String = st.id
	v.add_child(Game.button("Combattre en solo", func() -> void: Game.start_fight("/fight/campaign", {"brute": Game.brute.id, "stage": id}), 0, Color(0.55, 0.14, 0.1)))
	v.add_child(Game.button("Jouer en coop (créer un salon)", func() -> void:
		Api.ws_send({"t": "party_create", "mode": "coop_campaign", "stage": id, "public": false})
		Game.goto("tavern"), 0, Color(0.2, 0.38, 0.22)))
	v.add_child(Game.label("La campagne ne consomme pas d'énergie.", 14, Game.MUTED))
