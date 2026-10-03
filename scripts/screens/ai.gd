extends Control
## Défier l'IA : une brute générée par le serveur, de niveau adapté à la difficulté choisie.

const LEVELS := [
	["facile", "Facile", "Un adversaire 2 niveaux en dessous. Idéal pour s'échauffer.", Color(0.25, 0.45, 0.2)],
	["normal", "Normal", "Un adversaire de ton niveau. Un vrai duel.", Color(0.45, 0.35, 0.12)],
	["difficile", "Difficile", "Un adversaire 2 niveaux au-dessus. Ça va piquer.", Color(0.55, 0.2, 0.1)],
	["legendaire", "Légendaire", "5 niveaux au-dessus. Pour les brutes sans peur (et sans cervelle).", Color(0.42, 0.12, 0.4)],
]


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Défier l'IA", "arene_chateau")
	body.add_child(Game.label("Énergie : %d / %d - Victoire : +2 XP (+1 si l'IA est plus forte), défaite : +1 XP." % [Game.brute.energy, Game.brute.energyMax], 18, Game.CREAM, Game.font_bold, 5))
	var row := Game.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var looks := ["orc", "chevalier", "minotaure", "mage"]
	for i in LEVELS.size():
		var l: Array = LEVELS[i]
		var p := Game.panel(Vector2(270, 0))
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := Game.vbox(10)
		p.add_child(v)
		v.add_child(Game.icon(Game.look_tex(looks[i]), 180))
		v.add_child(Game.title(l[1], 34))
		var lv := Game.label("Niveau %d" % max(1, int(Game.brute.level) + [-2, 0, 2, 5][i]), 18, Game.GOLD, Game.font_bold)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lv)
		var d := Game.label(l[2], 16, Game.CREAM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size = Vector2(240, 60)
		v.add_child(d)
		var diff: String = l[0]
		v.add_child(Game.button("Combattre", func() -> void: Game.start_fight("/fight/ai", {"brute": Game.brute.id, "difficulty": diff}), 0, l[3]))
		row.add_child(p)
	var tip := Game.label("Astuce : pour affronter l'IA à plusieurs, crée un salon « Coop contre l'IA » dans le menu Multijoueur.", 16, Game.MUTED, null, 4)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(tip)
