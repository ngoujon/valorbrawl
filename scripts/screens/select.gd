extends Control
## Choix de la brute à jouer (3 maximum par compte).


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	add_child(Game.background("menu_bg", 0.45))
	var col := Game.vbox(24)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	col.add_child(Game.title("Tes brutes, %s" % Game.account.get("name", ""), 46))
	var row := Game.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for b in Game.account.brutes:
		var p := Game.panel(Vector2(260, 0))
		var v := Game.vbox(8)
		p.add_child(v)
		v.add_child(Game.brute_card(b, 200))
		var rec := Game.label("%d victoires - %d défaites" % [b.wins, b.losses], 16, Game.MUTED)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rec)
		var brute: Dictionary = b
		v.add_child(Game.button("Jouer", func() -> void: _play(brute)))
		row.add_child(p)
	if Game.account.brutes.size() < 3:
		var p := Game.panel(Vector2(260, 0))
		var v := Game.vbox(8)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(v)
		var plus := Game.title("+", 120)
		v.add_child(plus)
		v.add_child(Game.button("Nouvelle brute", func() -> void: Game.goto("create"), 0, Game.GREEN.darkened(0.35)))
		row.add_child(p)


func _play(b: Dictionary) -> void:
	Game.brute = b
	Api.ws_connect(b.id)
	Game.goto("hub")
