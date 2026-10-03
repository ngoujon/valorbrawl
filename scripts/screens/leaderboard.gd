extends Control
## Classement des 50 meilleures brutes.


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Classement des brutes", "arene")
	var list := Game.scroll_list(body, 4)
	list.add_child(Game.label("Chargement...", 18, Game.MUTED))
	var res := await Api.get_json("/leaderboard")
	if not is_inside_tree(): return
	Game.clear(list)
	var rank := 1
	for b in res.get("brutes", []):
		var h := Game.row_panel(list)
		var medal := [Game.GOLD, Color(0.8, 0.8, 0.85), Color(0.8, 0.5, 0.3)]
		h.add_child(Game.label("#%d" % rank, 26, medal[rank - 1] if rank <= 3 else Game.CREAM, Game.font_title))
		h.add_child(Game.icon(Game.look_tex(b.hero), 52))
		var v := Game.vbox(0)
		Game.expand(v)
		h.add_child(v)
		var name: String = b.name + ("  - %s" % b.title if b.get("title") else "")
		v.add_child(Game.label(name, 20, Game.GOLD if b.owner == Game.account.get("name") else Game.CREAM, Game.font_bold))
		v.add_child(Game.label("Joueur : %s%s" % [b.owner, ("  « %s »" % b.ownerTitle) if b.get("ownerTitle") else ""], 15, Game.MUTED))
		h.add_child(Game.label("Niveau %d" % b.level, 20, Game.GOLD, Game.font_bold))
		h.add_child(Game.label("%d V / %d D" % [b.wins, b.losses], 18, Game.CREAM))
		rank += 1
	if rank == 1:
		list.add_child(Game.label("Personne n'est encore classé. À toi de jouer !", 18, Game.MUTED))
