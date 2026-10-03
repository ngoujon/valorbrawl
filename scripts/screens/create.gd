extends Control
## Création d'une brute : nom + apparence (les statistiques et le premier bonus sont tirés au sort par le serveur).

var _hero := "barbare"
var _name: LineEdit
var _preview: TextureRect
var _hero_name: Label
var _hero_desc: Label
var _status: Label
var _buttons := {}


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	add_child(Game.background("menu_bg", 0.5))
	var root := Game.hbox(30)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 60
	root.offset_bottom = -30
	add_child(root)

	var left := Game.vbox(6)
	left.custom_minimum_size = Vector2(400, 0)
	root.add_child(left)
	_preview = Game.icon(null, 380)
	left.add_child(_preview)
	_hero_name = Game.title("", 40)
	left.add_child(_hero_name)
	_hero_desc = Game.label("", 18, Game.CREAM)
	_hero_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_hero_desc)

	var right := Game.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(Game.title("Forge ta brute", 48))
	var p := Game.panel()
	right.add_child(p)
	var v := Game.vbox(12)
	p.add_child(v)
	v.add_child(Game.label("Choisis ton apparence :", 20, Game.GOLD, Game.font_bold))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for h in Game.content.heroes:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 130)
		b.icon = Game.look_tex(h.id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = h.name
		b.toggle_mode = true
		var id: String = h.id
		b.pressed.connect(func() -> void: _pick(id))
		grid.add_child(b)
		_buttons[h.id] = b
	v.add_child(Game.label("Nom de ta brute :", 20, Game.GOLD, Game.font_bold))
	_name = LineEdit.new()
	_name.placeholder_text = "ex : Grobalaf le Terrible"
	_name.max_length = 16
	v.add_child(_name)
	var info := Game.label("Tes caractéristiques, ainsi qu'une arme, une compétence ou un familier, seront tirés au sort par les dieux de l'arène.", 16, Game.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	var h2 := Game.hbox(12)
	v.add_child(h2)
	h2.add_child(Game.button("Créer ma brute !", _create, 240, Game.GREEN.darkened(0.35)))
	if Game.account.brutes.size() > 0:
		h2.add_child(Game.button("Retour", func() -> void: Game.goto("select"), 140))
	_status = Game.label("", 18, Game.GOLD)
	v.add_child(_status)
	_pick(Game.content.heroes[randi() % Game.content.heroes.size()].id)


func _pick(id: String) -> void:
	_hero = id
	for k in _buttons:
		_buttons[k].button_pressed = k == id
	_preview.texture = Game.look_tex(id)
	var h: Dictionary = Game.heroes[id]
	_hero_name.text = h.name
	var bonus := []
	for k in h.bonus:
		bonus.append("%+d %s" % [h.bonus[k], Game.STAT_NAMES[k]])
	_hero_desc.text = "%s\n%s" % [h.desc, ", ".join(bonus)]
	_preview.pivot_offset = Vector2(190, 380)
	_preview.scale = Vector2(0.9, 1.1)
	create_tween().tween_property(_preview, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _create() -> void:
	_status.text = "..."
	var res := await Api.post("/brute/create", {"name": _name.text.strip_edges(), "hero": _hero})
	if res.has("error"):
		_status.text = res.error
		return
	Audio.sfx("levelup")
	Game.account.brutes.append(res.brute)
	Game.brute = res.brute
	Api.ws_connect(res.brute.id)
	Game.goto("hub", {"new": true})
