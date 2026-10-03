extends Node
## État global : contenu du jeu, compte et brute courants, état du lobby, thème, navigation, fabriques d'UI.

signal lobby_changed(msg: Dictionary)

const GOLD := Color(0.95, 0.76, 0.33)
const CREAM := Color(0.98, 0.93, 0.82)
const DARK := Color(0.11, 0.07, 0.05)
const WOOD := Color(0.27, 0.17, 0.10)
const RED := Color(0.62, 0.16, 0.12)
const GREEN := Color(0.32, 0.62, 0.25)
const MUTED := Color(0.78, 0.70, 0.58)

const STAT_NAMES := {"hp": "Points de vie", "str": "Force", "agi": "Agilité", "spd": "Rapidité"}
const STAT_SHORT := {"hp": "PV", "str": "FOR", "agi": "AGI", "spd": "RAP"}

var content: Dictionary = {}
var weapons := {}
var pets := {}
var skills := {}
var heroes := {}
var stages := {}

var account: Dictionary = {}
var lobby_players: Array = []
var parties: Array = []
var chat: Array = []
var party: Dictionary = {}
var party_chat: Array = []
var brute: Dictionary = {}  ## brute actuellement jouée (vue complète renvoyée par le serveur)

var font_title: Font
var font_text: Font
var font_bold: Font
var theme: Theme
var main: Node  ## scène principale (scripts/main.gd), qui affiche les écrans
var _tex_cache := {}


func _ready() -> void:
	var f := FileAccess.open("res://data/content.json", FileAccess.READ)
	content = JSON.parse_string(f.get_as_text())
	for w in content.weapons: weapons[w.id] = w
	for p in content.pets: pets[p.id] = p
	for s in content.skills: skills[s.id] = s
	for h in content.heroes: heroes[h.id] = h
	for c in content.campaign: stages[c.id] = c
	font_title = load("res://assets/fonts/MedievalSharp.ttf")
	font_text = load("res://assets/fonts/AlegreyaSans-Medium.ttf")
	font_bold = load("res://assets/fonts/AlegreyaSans-ExtraBold.ttf")
	theme = _build_theme()
	get_tree().root.theme = theme


# ------------------------------------------------------------------ ressources
func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func look_tex(look: String, is_boss := false) -> Texture2D:
	if is_boss or not heroes.has(look):
		var t := tex("res://assets/bosses/%s.png" % look)
		if t: return t
	return tex("res://assets/characters/%s.png" % look)


func weapon_tex(id: String) -> Texture2D: return tex("res://assets/weapons/%s.png" % id)
func skill_tex(id: String) -> Texture2D: return tex("res://assets/skills/%s.png" % id)
func pet_tex(id: String) -> Texture2D: return tex("res://assets/pets/%s.png" % id)
func bg_tex(id: String) -> Texture2D: return tex("res://assets/bg/%s.jpg" % id)


func choice_text(ch: Dictionary) -> Array:
	## [titre, description, texture] d'un bonus de niveau ou d'une récompense.
	match ch.get("type", ""):
		"stat":
			var parts := []
			var bonus: Dictionary = ch.get("bonus", {ch.get("id", "hp"): ch.get("v", 0)})
			for k in bonus: parts.append("+%d %s" % [bonus[k], STAT_NAMES[k]])
			return [", ".join(parts), "Entraînement intensif à la salle d'armes.", null]
		"weapon": return [weapons[ch.id].name, "Nouvelle arme : %d dégâts." % weapons[ch.id].dmg, weapon_tex(ch.id)]
		"skill": return [skills[ch.id].name, skills[ch.id].desc, skill_tex(ch.id)]
		"pet": return [pets[ch.id].name, pets[ch.id].desc, pet_tex(ch.id)]
		"title": return ["Titre : %s" % ch.id, "Un titre honorifique pour l'éternité.", null]
	return ["?", "", null]


# ------------------------------------------------------------------ navigation
func goto(screen: String, params := {}) -> void:
	Audio.click()
	main.show_screen(screen, params)


func set_brute(b: Dictionary) -> void:
	brute = b
	for i in account.get("brutes", []).size():
		if account.brutes[i].id == b.id:
			account.brutes[i] = b


func toast(text: String, color := CREAM) -> void:
	if main: main.toast(text, color)


# ------------------------------------------------------------------ thème
func _box(bg: Color, border: Color, bw := 2, radius := 8, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_text
	t.default_font_size = 19
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 0)
	var btn := _box(Color(0.50, 0.16, 0.10), Color(0.95, 0.76, 0.33), 2, 8, 10)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", _box(Color(0.66, 0.24, 0.14), Color(1, 0.88, 0.5), 2, 8, 10))
	t.set_stylebox("pressed", "Button", _box(Color(0.36, 0.11, 0.07), GOLD, 2, 8, 10))
	t.set_stylebox("disabled", "Button", _box(Color(0.28, 0.22, 0.18), Color(0.45, 0.4, 0.33), 2, 8, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.5))
	t.set_stylebox("panel", "Panel", _box(Color(0.16, 0.10, 0.07, 0.94), GOLD, 2, 10, 12))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.16, 0.10, 0.07, 0.94), Color(0.75, 0.56, 0.27), 2, 10, 14))
	var le := _box(Color(0.96, 0.9, 0.78), Color(0.55, 0.38, 0.2), 2, 6, 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _box(Color(1, 0.96, 0.86), GOLD, 2, 6, 8))
	t.set_color("font_color", "LineEdit", DARK)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.38, 0.3))
	t.set_color("caret_color", "LineEdit", DARK)
	t.set_font_size("font_size", "LineEdit", 20)
	var pb_bg := _box(Color(0.1, 0.05, 0.03), Color(0.05, 0.03, 0.02), 2, 6, 0)
	pb_bg.shadow_size = 0
	var pb_fill := _box(Color(0.75, 0.15, 0.1), Color(0, 0, 0, 0), 0, 5, 0)
	pb_fill.shadow_size = 0
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", CREAM)
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.12, 0.08, 0.05, 0.97), GOLD, 2, 6, 8))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", 17)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	var sb := _box(Color(0.1, 0.06, 0.04, 0.6), Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", _box(Color(0.6, 0.45, 0.25), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(0.8, 0.6, 0.3), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("panel", "PopupPanel", _box(Color(0.16, 0.10, 0.07, 0.97), GOLD, 2, 10, 14))
	t.set_stylebox("slider", "HSlider", _box(Color(0.1, 0.05, 0.03), Color(0, 0, 0, 0), 0, 4, 3))
	return t


# ------------------------------------------------------------------ fabriques d'UI
func label(text: String, size := 19, color := CREAM, font: Font = null, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font: l.add_theme_font_override("font", font)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	return l


func title(text: String, size := 44) -> Label:
	var l := label(text, size, GOLD, font_title, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func button(text: String, cb: Callable, min_w := 0, color := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	if color.a > 0:
		b.add_theme_stylebox_override("normal", _box(color, GOLD, 2, 8, 10))
		b.add_theme_stylebox_override("hover", _box(color.lightened(0.15), Color(1, 0.88, 0.5), 2, 8, 10))
	b.pressed.connect(func() -> void:
		Audio.click()
		cb.call())
	return b


func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func icon(t: Texture2D, size := 48, tip := "") -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.tooltip_text = tip
	r.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" else Control.MOUSE_FILTER_IGNORE
	return r


func bar(value: float, max_value: float, color: Color, h := 18, show_text := true) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max(1.0, max_value)
	p.value = value
	p.custom_minimum_size = Vector2(0, h)
	p.show_percentage = false
	var fill := _box(color, Color(0, 0, 0, 0), 0, 5, 0)
	fill.shadow_size = 0
	p.add_theme_stylebox_override("fill", fill)
	if show_text:
		var l := label("%d / %d" % [value, max_value], max(12, h - 4), CREAM, font_bold, 4)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.name = "Text"
		p.add_child(l)
	return p


func background(id: String, darken := 0.35) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = bg_tex(id)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	if darken > 0:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, darken)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(shade)
	return root


func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


func brute_card(b: Dictionary, size := 140) -> Control:
	## Petite carte : sprite + nom + niveau (+ propriétaire).
	var v := vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var img := icon(look_tex(b.get("hero", "barbare")), size)
	v.add_child(img)
	var n := label(b.get("name", "?"), 21, GOLD, font_bold, 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var info := "Niveau %d" % b.get("level", 1)
	if b.get("title"): info += " - %s" % b.title
	var l := label(info, 16, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


func stat_line(b: Dictionary) -> String:
	var s: Dictionary = b.get("stats", {})
	return "PV %d   FOR %d   AGI %d   RAP %d" % [s.get("hp", 0), s.get("str", 0), s.get("agi", 0), s.get("spd", 0)]


func frame(parent: Control, title_text: String, bg := "arene", back := "hub") -> VBoxContainer:
	## Gabarit d'écran : fond, bouton retour, titre ; renvoie la zone de contenu.
	parent.add_child(background(bg, 0.55))
	var root := vbox(10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 10
	root.offset_bottom = -16
	parent.add_child(root)
	var top := hbox(16)
	root.add_child(top)
	var target := back
	top.add_child(button("< Retour", func() -> void: goto(target), 130))
	var t := title(title_text, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(t)
	var body := vbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	return body


func scroll_list(parent: Control, sep := 6) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := vbox(sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v


func row_panel(parent: Control) -> HBoxContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.2, 0.13, 0.08, 0.92)
	st.border_color = Color(0.55, 0.4, 0.2)
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var h := hbox(12)
	p.add_child(h)
	return h


func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func start_fight(path: String, body: Dictionary) -> void:
	## Lance un combat solo via l'API puis ouvre l'écran de combat.
	var res := await Api.post(path, body)
	if res.has("error"):
		toast(res.error, Color(1, 0.55, 0.45))
		return
	set_brute(res.brute)
	if res.has("account"):
		account = res.account
	goto("fight", {"fight": res.fight, "side": 0})
