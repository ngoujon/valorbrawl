extends Control
## Rejoue un combat simulé par le serveur (journal d'événements) : déplacements, coups, esquives, supers,
## familiers, chiffres de dégâts, sons et commentaire façon La Brute. Gère les équipes (coop / PvP).

const MELEE_GAP := 95.0
const BRUTE_H := 230.0
const BOSS_H := 300.0
const PET_H := {"loup": 105.0, "ours": 175.0, "dragonnet": 115.0, "golem": 185.0}
const BRUTE_SLOTS := [Vector2(0.30, 0.80), Vector2(0.20, 0.74), Vector2(0.11, 0.84)]
const PET_SLOTS := [Vector2(0.40, 0.88), Vector2(0.37, 0.72), Vector2(0.44, 0.78), Vector2(0.33, 0.93), Vector2(0.25, 0.92), Vector2(0.47, 0.94)]
const SKILL_LINES := {
	"potion": "%s boit une potion de soin !",
	"feu": "%s lance une boule de feu !",
	"eclair": "%s invoque la foudre !",
	"cri": "%s pousse un terrible cri de guerre !",
	"sabotage": "%s sabote l'arme de son adversaire !",
	"charme": "%s charme un familier ennemi !",
	"fureur": "%s entre dans une fureur berserk !",
}

var fight: Dictionary
var my_side := 0
var params: Dictionary
var speed := 1.0
var skipping := false
var finished := false
var views := {}  ## id -> Dictionary (nœuds et état d'un combattant)
var hud := {}  ## id -> ProgressBar des brutes en haut de l'écran
var world: Node2D
var fx: Node2D
var commentary: Label
var _speed_btn: Button
var _vp := Vector2(1280, 720)


func setup(p: Dictionary) -> void:
	params = p
	fight = p.fight
	my_side = int(p.get("side", 0))
	_vp = get_viewport_rect().size
	var campaign: bool = str(fight.mode).contains("campaign")
	Audio.music("boss" if campaign else "combat")
	add_child(Game.background(fight.get("arena", "arene"), 0.0))
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	fx = Node2D.new()
	add_child(fx)
	_build_hud()
	for f in fight.fighters:
		_spawn(f)
	_layout_all(false)
	_play()


# ------------------------------------------------------------------ construction
func _is_left(side: int) -> bool:
	return side == my_side


func _spawn(f: Dictionary) -> void:
	var v := {"data": f, "side": int(f.side), "hp": int(f.hp), "dead": false, "weapon_id": ""}
	var root := Node2D.new()
	world.add_child(root)
	var is_pet: bool = f.kind == "pet"
	var tex: Texture2D = Game.pet_tex(f.look) if is_pet else Game.look_tex(f.look, f.get("boss", false))
	var h: float = PET_H.get(f.look, 120.0) if is_pet else (BOSS_H if f.get("boss", false) else BRUTE_H)
	if f.get("boss", false) and f.look == "dragon": h = 340.0
	# ombre
	var shadow := Sprite2D.new()
	shadow.texture = _radial(Color(0, 0, 0, 0.45))
	shadow.scale = Vector2(h * 0.0085, h * 0.0022)
	root.add_child(shadow)
	# aura cosmétique
	var aura_id = f.get("aura") if f.has("aura") else null
	if aura_id == null and not is_pet:
		aura_id = _aura_of(f)
	if aura_id != null and Game.account.get("auras", {}).has(aura_id):
		var au := Sprite2D.new()
		au.texture = _radial(Color(Game.account.auras[aura_id].color))
		au.scale = Vector2(h * 0.012, h * 0.016)
		au.position.y = -h * 0.5
		au.modulate.a = 0.55
		root.add_child(au)
		var tw := au.create_tween().set_loops()
		tw.tween_property(au, "modulate:a", 0.25, 0.8)
		tw.tween_property(au, "modulate:a", 0.6, 0.8)
	var body := Sprite2D.new()
	body.texture = tex
	if tex:
		var s := h / tex.get_height()
		body.scale = Vector2(s, s)
	body.position.y = -h * 0.5
	root.add_child(body)
	var weapon := Sprite2D.new()
	weapon.position = Vector2(h * 0.28, -h * 0.5)
	weapon.scale = Vector2(0.32, 0.32)
	weapon.rotation = -0.6
	root.add_child(weapon)
	var tag := Game.label(f.name if is_pet else "%s  niv %d" % [f.name, f.level], 15 if is_pet else 17, Game.CREAM, Game.font_bold, 5)
	tag.position = Vector2(-80, -h - 30)
	tag.custom_minimum_size = Vector2(160, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tag)
	var bar: ProgressBar = null
	if is_pet:
		bar = Game.bar(f.hp, f.maxHp, Color(0.85, 0.3, 0.2), 8, false)
		bar.position = Vector2(-40, -h - 8)
		bar.size = Vector2(80, 8)
		bar.custom_minimum_size = Vector2(80, 8)
		root.add_child(bar)
	v.merge({"root": root, "body": body, "weapon": weapon, "h": h, "bar": bar, "tag": tag, "pet": is_pet})
	views[int(f.id)] = v


func _aura_of(f: Dictionary):
	## L'aura choisie par le propriétaire (transmise dans la vue des brutes de joueurs).
	for t in fight.get("teams", []):
		for b in t:
			if b.get("name") == f.name and b.has("aura"):
				return b.aura
	if f.name == Game.brute.get("name", "") and Game.account.get("profile", {}).get("aura") != null:
		return Game.account.profile.aura
	return null


func _radial(c: Color) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _layout_all(animate: bool) -> void:
	var counts := {}
	for id in _sorted_ids():
		var v: Dictionary = views[id]
		var left := _is_left(v.side)
		var key := "%s_%s" % [left, v.pet]
		var idx: int = counts.get(key, 0)
		counts[key] = idx + 1
		var slots: Array = PET_SLOTS if v.pet else BRUTE_SLOTS
		var s: Vector2 = slots[idx % slots.size()]
		var pos := Vector2(s.x * _vp.x, s.y * _vp.y)
		if not left:
			pos.x = _vp.x - pos.x
		v.home = pos
		v.left = left
		v.body.flip_h = not left
		v.weapon.position.x = abs(v.weapon.position.x) * (1 if left else -1)
		v.weapon.flip_h = not left
		v.weapon.rotation = -0.6 if left else 0.6
		if animate:
			create_tween().tween_property(v.root, "position", pos, 0.5 / speed)
		else:
			v.root.position = pos


func _sorted_ids() -> Array:
	var ids := views.keys()
	ids.sort()
	return ids


func _build_hud() -> void:
	var top := Game.hbox(10)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 10
	add_child(top)
	var cols := [Game.vbox(4), Game.vbox(4)]
	cols[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cols[0])
	var vs := Game.title("VS", 40)
	top.add_child(vs)
	top.add_child(cols[1])
	for f in fight.fighters:
		if f.kind != "brute":
			continue
		var left := _is_left(int(f.side))
		var row := Game.hbox(8)
		if not left:
			row.alignment = BoxContainer.ALIGNMENT_END
		var pic := Game.icon(Game.look_tex(f.look, f.get("boss", false)), 52)
		pic.flip_h = not left
		var info := Game.vbox(0)
		info.custom_minimum_size = Vector2(300, 0)
		var n := Game.label("%s  (niv %d)" % [f.name, f.level], 19, Game.GOLD, Game.font_bold, 6)
		if not left: n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.add_child(n)
		var bar := Game.bar(f.hp, f.maxHp, Color(0.25, 0.7, 0.25) if left else Color(0.8, 0.22, 0.15), 20)
		info.add_child(bar)
		hud[int(f.id)] = bar
		if left:
			row.add_child(pic)
			row.add_child(info)
		else:
			row.add_child(info)
			row.add_child(pic)
		cols[0 if left else 1].add_child(row)
	# commentaire + contrôles
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -10
	add_child(bottom)
	var bh := Game.hbox(10)
	bottom.add_child(bh)
	commentary = Game.label("Le combat va commencer !", 20, Game.CREAM, Game.font_bold)
	commentary.custom_minimum_size = Vector2(620, 0)
	commentary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_child(commentary)
	_speed_btn = Game.button("Vitesse x1", _toggle_speed, 130)
	if params.get("cinematic", false):
		return
	bh.add_child(_speed_btn)
	bh.add_child(Game.button("Passer", func() -> void: skipping = true, 100))


func _toggle_speed() -> void:
	speed = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}[speed]
	_speed_btn.text = "Vitesse x%d" % int(speed)


# ------------------------------------------------------------------ lecture
func _wait(t: float) -> void:
	if skipping or not is_inside_tree():
		return
	await get_tree().create_timer(t / speed).timeout


func _tw(node: Object, prop: String, to, t: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(node, prop, to, max(0.01, t / speed)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


func _say(text: String) -> void:
	commentary.text = text


func _name(id) -> String:
	return views[int(id)].data.name if views.has(int(id)) else "?"


func _play() -> void:
	Audio.sfx("gong", 0.0, 0.8)
	_say("%s contre %s !" % [_team_names(0), _team_names(1)])
	await _wait(1.4)
	var log: Array = fight.log
	for i in log.size():
		if not is_inside_tree():
			return
		if skipping:
			_apply_instant(log.slice(i))
			break
		var ev: Dictionary = log[i]
		var nxt: Dictionary = log[i + 1] if i + 1 < log.size() else {}
		await _event(ev, nxt)
	_finish()


func _team_names(side: int) -> String:
	var names := []
	for f in fight.fighters:
		if f.kind == "brute" and int(f.side) == side:
			names.append(f.name)
	return " & ".join(names)


func _event(ev: Dictionary, nxt: Dictionary) -> void:
	match ev.t:
		"draw":
			var v: Dictionary = views[int(ev.a)]
			v.weapon_id = ev.w
			v.weapon.texture = Game.weapon_tex(ev.w)
			v.weapon.scale = Vector2.ZERO
			_tw(v.weapon, "scale", Vector2(0.32, 0.32), 0.25).set_trans(Tween.TRANS_BACK)
			Audio.sfx("draw")
			_say("%s dégaine : %s !" % [_name(ev.a), Game.weapons[ev.w].name])
			await _wait(0.55)
		"hit", "miss":
			await _attack(ev, nxt)
		"super":
			await _super(ev)
		"heal":
			var v: Dictionary = views[int(ev.a)]
			_set_hp(int(ev.a), int(ev.hp))
			_float(v, "+%d" % ev.v, Color(0.4, 1, 0.4), 30)
			_flash(v, Color(0.5, 1.5, 0.5))
			if ev.get("src") == "potion":
				Audio.sfx("heal")
				_say("%s récupère %d PV !" % [_name(ev.a), ev.v])
				await _wait(0.7)
			else:
				await _wait(0.2)
		"stun":
			var v: Dictionary = views[int(ev.d)]
			_float(v, "Étourdi !", Color(1, 0.9, 0.3), 24)
			_say("%s est étourdi !" % _name(ev.d))
			await _wait(0.5)
		"stunned":
			var v: Dictionary = views[int(ev.a)]
			var tw := create_tween().set_loops(2)
			tw.tween_property(v.body, "rotation", 0.12, 0.12 / speed)
			tw.tween_property(v.body, "rotation", -0.12, 0.12 / speed)
			tw.finished.connect(func() -> void: v.body.rotation = 0.0)
			_say("%s titube, sonné..." % _name(ev.a))
			await _wait(0.6)
		"break":
			var v: Dictionary = views[int(ev.d)]
			Audio.sfx("break")
			var w: Sprite2D = v.weapon
			_tw(w, "rotation", w.rotation + 6.0, 0.6)
			_tw(w, "modulate:a", 0.0, 0.6)
			_say("L'arme de %s vole en éclats !" % _name(ev.d))
			await _wait(0.7)
			w.texture = null
			w.modulate.a = 1.0
			v.weapon_id = ""
		"charm":
			var v: Dictionary = views[int(ev.d)]
			v.side = int(ev.side)
			_flash(v, Color(1.6, 0.6, 1.4))
			_say("%s change de camp !" % _name(ev.d))
			_layout_all(true)
			await _wait(0.8)
		"survive":
			var v: Dictionary = views[int(ev.d)]
			_set_hp(int(ev.d), 1)
			_float(v, "Dernier souffle !", Color(1, 0.8, 0.2), 26)
			Audio.sfx("crowd_ooh")
			_say("%s refuse de tomber !" % _name(ev.d))
			await _wait(0.9)
		"die":
			var v: Dictionary = views[int(ev.d)]
			v.dead = true
			Audio.sfx("death")
			var fall := 1.5 if v.left else -1.5
			_tw(v.body, "rotation", -fall, 0.45)
			_tw(v.root, "modulate:a", 0.45, 0.8)
			v.weapon.texture = null
			if v.pet:
				_say("%s s'effondre." % _name(ev.d))
			else:
				Audio.sfx("crowd_cheer", 0.0, 0.8)
				_say("%s est K.O. !" % _name(ev.d))
			await _wait(1.0 if not v.pet else 0.6)
		"timeout":
			_say("Le temps est écoulé ! Victoire aux points.")
			await _wait(1.2)
		"end":
			pass


func _attack(ev: Dictionary, nxt: Dictionary) -> void:
	var a: Dictionary = views[int(ev.a)]
	var d: Dictionary = views[int(ev.d)]
	if ev.get("magic") != null:
		# coup magique (boule de feu / foudre) : l'effet a déjà été montré, on applique les dégâts
		_impact(ev, a, d)
		await _wait(0.45)
		return
	var w_id: String = a.weapon_id
	var wtype: String = Game.weapons[w_id].type if w_id != "" else ("pet" if a.pet else "fist")
	var ranged := wtype == "ranged" or wtype == "magic"
	if ev.get("c") != null:
		_say("%s riposte !" % _name(ev.a))
	if not ranged:
		var dir := 1.0 if a.left else -1.0
		var target_pos: Vector2 = d.root.position + Vector2(-dir * MELEE_GAP * (1.3 if d.h > 250 else 1.0), 2)
		if a.root.position.distance_to(target_pos) > 8:
			Audio.sfx("whoosh", 0.15, 0.5)
			_tw(a.root, "position", target_pos, 0.28)
			await _wait(0.3)
		# élan du coup
		var swing := 0.35 * dir
		_tw(a.body, "rotation", swing, 0.08)
		_tw(a.weapon, "rotation", (0.9 if a.left else -0.9), 0.08)
		await _wait(0.1)
		_tw(a.body, "rotation", 0.0, 0.15)
		_tw(a.weapon, "rotation", (-0.6 if a.left else 0.6), 0.15)
	else:
		Audio.sfx("arrow" if wtype == "ranged" else "lightning", 0.1, 0.5)
		var proj := Sprite2D.new()
		proj.texture = Game.weapon_tex(w_id) if wtype == "ranged" else Game.skill_tex("eclair")
		proj.scale = Vector2(0.18, 0.18)
		proj.position = a.root.position + Vector2(0, -a.h * 0.55)
		fx.add_child(proj)
		var to: Vector2 = d.root.position + Vector2(0, -d.h * 0.5)
		proj.rotation = (to - proj.position).angle()
		_tw(proj, "position", to, 0.3)
		await _wait(0.3)
		proj.queue_free()
	if ev.t == "miss":
		if ev.how == "block":
			Audio.sfx("block")
			_float(d, "Bloqué !", Color(0.7, 0.85, 1.0), 24)
			_say("%s bloque le coup de %s !" % [_name(ev.d), _name(ev.a)])
			_tw(d.root, "position", d.root.position + Vector2(8 if d.left else -8, 0), 0.08)
		else:
			Audio.sfx("dodge")
			_float(d, "Esquive !", Color(0.8, 1, 0.8), 24)
			_say("%s esquive l'attaque de %s !" % [_name(ev.d), _name(ev.a)])
			var hop := Vector2(-40 if d.left else 40, -30)
			var base: Vector2 = d.root.position
			_tw(d.root, "position", base + hop, 0.12)
			await _wait(0.13)
			_tw(d.root, "position", base, 0.15)
	else:
		_impact(ev, a, d, wtype)
		if a.pet and randf() < 0.35:
			Audio.sfx({"loup": "growl_wolf", "ours": "roar_bear", "dragonnet": "roar_dragon"}.get(a.data.look, "punch"), 0.1, 0.5)
	await _wait(0.42)
	# retour au poste sauf si le même attaquant enchaîne
	var chain: bool = not nxt.is_empty() and (nxt.t == "hit" or nxt.t == "miss") and int(nxt.get("a", -1)) == int(ev.a) and nxt.get("magic") == null
	if not chain and not a.dead:
		_tw(a.root, "position", a.home, 0.25)
		await _wait(0.18)


func _impact(ev: Dictionary, a: Dictionary, d: Dictionary, wtype := "") -> void:
	var crit: bool = ev.get("crit") != null
	var snd: String = {"sharp": "hit_sharp", "blunt": "hit_blunt", "fist": "punch", "pet": "hit_sharp", "ranged": "hit_sharp", "magic": "hit_blunt"}.get(wtype, "hit_blunt")
	if ev.get("magic") == "feu": snd = "fire"
	elif ev.get("magic") == "eclair": snd = "lightning"
	Audio.sfx("crit" if crit else snd, 0.12, 1.0)
	_set_hp(int(ev.d), int(ev.hp))
	_float(d, ("-%d !" if crit else "-%d") % ev.dmg, Color(1, 0.25, 0.2) if crit else Color(1, 0.95, 0.85), 40 if crit else 28)
	_flash(d, Color(2.2, 0.6, 0.6))
	var base: Vector2 = d.home if not d.dead else d.root.position
	var kb := Vector2(-18 if d.left else 18, 0) * (2.0 if crit else 1.0)
	var tw := create_tween()
	tw.tween_property(d.root, "position", d.root.position + kb, 0.06 / speed)
	tw.tween_property(d.root, "position", base if d.root.position.distance_to(d.home) < 30 else d.root.position, 0.12 / speed)
	if crit:
		_shake(14.0)
		Audio.sfx("crowd_ooh", 0.1, 0.6)
		_say("COUP CRITIQUE de %s sur %s : %d dégâts !" % [_name(ev.a), _name(ev.d), ev.dmg])
	elif ev.get("magic") == null:
		var verb: String = ["frappe", "cogne", "touche", "malmène", "tabasse"][randi() % 5]
		var extra := " (enchaînement)" if ev.get("combo") != null else ""
		_say("%s %s %s : -%d%s" % [_name(ev.a), verb, _name(ev.d), ev.dmg, extra])


func _super(ev: Dictionary) -> void:
	var a: Dictionary = views[int(ev.a)]
	var s: String = ev.s
	# bannière
	var ban := Game.hbox(12)
	var ic := Game.icon(Game.skill_tex(s), 90)
	ban.add_child(ic)
	ban.add_child(Game.label(Game.skills[s].name, 46, Game.GOLD, Game.font_title, 12))
	ban.position = Vector2(_vp.x * 0.5 - 260, _vp.y * 0.32)
	add_child(ban)
	ban.modulate.a = 0.0
	ban.scale = Vector2(0.6, 0.6)
	_tw(ban, "modulate:a", 1.0, 0.15)
	_tw(ban, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_say(SKILL_LINES.get(s, "%s utilise une compétence !") % _name(ev.a))
	match s:
		"cri": Audio.sfx("shout"); _shake(10.0)
		"fureur": Audio.sfx("shout", 0.2); _flash(a, Color(2.0, 0.5, 0.4))
		"potion": pass
		"eclair":
			Audio.sfx("lightning")
			var flash := ColorRect.new()
			flash.color = Color(1, 1, 1, 0.85)
			flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(flash)
			_tw(flash, "color:a", 0.0, 0.5).finished.connect(flash.queue_free)
		"charme": Audio.sfx("heal", 0.2)
		"sabotage": Audio.sfx("whoosh")
		"feu": pass
	await _wait(0.8)
	if s == "feu" and ev.has("d") and views.has(int(ev.d)):
		var d: Dictionary = views[int(ev.d)]
		Audio.sfx("fire")
		var ball := Sprite2D.new()
		ball.texture = Game.skill_tex("feu")
		ball.scale = Vector2(0.45, 0.45)
		ball.position = a.root.position + Vector2(0, -a.h * 0.55)
		fx.add_child(ball)
		var to: Vector2 = d.root.position + Vector2(0, -d.h * 0.5)
		_tw(ball, "position", to, 0.4)
		_tw(ball, "rotation", 8.0, 0.4)
		await _wait(0.4)
		_tw(ball, "scale", Vector2(1.4, 1.4), 0.25)
		_tw(ball, "modulate:a", 0.0, 0.25).finished.connect(ball.queue_free)
		_shake(8.0)
	_tw(ban, "modulate:a", 0.0, 0.2).finished.connect(ban.queue_free)


func _set_hp(id: int, hp: int) -> void:
	var v: Dictionary = views[id]
	v.hp = hp
	if hud.has(id):
		var b: ProgressBar = hud[id]
		_tw(b, "value", float(hp), 0.3)
		var t: Label = b.get_node_or_null("Text")
		if t: t.text = "%d / %d" % [hp, int(b.max_value)]
	if v.bar:
		_tw(v.bar, "value", float(hp), 0.3)


func _float(v: Dictionary, text: String, color: Color, size: int) -> void:
	var l := Game.label(text, size, color, Game.font_bold, 8)
	l.position = v.root.position + Vector2(-60 + randf_range(-20, 20), -v.h - 40)
	l.custom_minimum_size = Vector2(120, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fx.add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 60, 0.9 / speed)
	tw.tween_property(l, "modulate:a", 0.0, 0.9 / speed).set_delay(0.4 / speed)
	tw.chain().tween_callback(l.queue_free)


func _flash(v: Dictionary, c: Color) -> void:
	v.body.modulate = c
	_tw(v.body, "modulate", Color.WHITE, 0.3)


func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(world, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.035)
	tw.tween_property(world, "position", Vector2.ZERO, 0.05)


func _apply_instant(rest: Array) -> void:
	## « Passer » : applique directement l'état final.
	for ev in rest:
		match ev.t:
			"hit", "heal": _set_hp(int(ev.get("d", ev.get("a"))) if ev.t == "hit" else int(ev.a), int(ev.hp))
			"survive": _set_hp(int(ev.d), 1)
			"charm": views[int(ev.d)].side = int(ev.side)
			"die":
				var v: Dictionary = views[int(ev.d)]
				v.dead = true
				v.body.rotation = -1.5 if v.left else 1.5
				v.root.modulate.a = 0.45
	_layout_all(false)


# ------------------------------------------------------------------ fin du combat
func _finish() -> void:
	if finished or not is_inside_tree():
		return
	finished = true
	var won: bool = int(fight.winner) == my_side
	Audio.music("victoire" if won else "defaite", false)
	Audio.sfx("crowd_cheer" if won else "crowd_ooh", 0.0, 0.8)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var p := Game.panel(Vector2(520, 0))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(p)
	var v := Game.vbox(8)
	p.add_child(v)
	var t := Game.title("VICTOIRE !" if won else "DÉFAITE...", 60)
	t.add_theme_color_override("font_color", Game.GOLD if won else Color(0.85, 0.35, 0.3))
	v.add_child(t)
	var rw: Dictionary = fight.get("rewards", {}).get(Game.brute.get("id", ""), {})
	if params.get("replay", false):
		v.add_child(_center_label("Rediffusion du combat", 18, Game.MUTED))
	elif not rw.is_empty():
		var parts := []
		if rw.get("xp", 0) > 0: parts.append("+%d XP" % rw.xp)
		if rw.get("gold", 0) > 0: parts.append("+%d écus" % rw.gold)
		if rw.get("passXp", 0) > 0: parts.append("+%d XP de passe" % rw.passXp)
		if parts.size() > 0: v.add_child(_center_label("  ".join(parts), 22, Game.CREAM))
		if rw.get("levelup", false):
			Audio.sfx("levelup")
			v.add_child(_center_label("NIVEAU SUPÉRIEUR ! Choisis ton bonus dans ta cellule.", 20, Game.GOLD))
		if rw.has("reward"):
			v.add_child(_center_label("Récompense de campagne : %s" % Game.choice_text(rw.reward)[0], 20, Game.GOLD))
		for q in rw.get("quests", []):
			v.add_child(_center_label("Quête accomplie : %s" % q, 18, Game.GREEN.lightened(0.3)))
	if fight.get("stage") and won and not params.get("replay", false):
		var st: Dictionary = Game.stages.get(fight.stage, {})
		if st.has("outro"):
			var o := _center_label(st.outro, 17, Game.CREAM)
			o.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			o.custom_minimum_size = Vector2(480, 0)
			v.add_child(o)
	var h := Game.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	h.add_child(Game.button("Revoir", func() -> void:
		var pp: Dictionary = params.duplicate()
		pp.replay = true
		Game.goto("fight", pp), 140))
	h.add_child(Game.button("Continuer", _leave, 180, Game.GREEN.darkened(0.35)))
	p.scale = Vector2(0.7, 0.7)
	p.pivot_offset = Vector2(260, 150)
	_tw(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func _center_label(text: String, size: int, color: Color) -> Label:
	var l := Game.label(text, size, color, Game.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _leave() -> void:
	var mode := str(fight.mode)
	if not Game.party.is_empty() and mode in ["pvp", "coop_ai", "coop_campaign"]:
		Game.goto("tavern")
	elif mode == "campaign":
		Game.goto("campaign")
	elif mode == "arena":
		Game.goto("arena")
	elif mode == "ai":
		Game.goto("ai")
	else:
		Game.goto("hub")
