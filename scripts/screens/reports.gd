extends Control
## Bugs & suggestions de la communauté : consulter, voter « Moi aussi », commenter, en créer un nouveau.

var _list: VBoxContainer
var _filter := ""


func setup(_params: Dictionary) -> void:
	Audio.music("menu")
	var body := Game.frame(self, "Bugs & suggestions", "key_tavern")
	var h := Game.hbox(8)
	body.add_child(h)
	h.add_child(Game.button("Nouveau signalement", func() -> void: Game.main.report_popup(), 0, Game.GREEN.darkened(0.35)))
	for f in [["", "Tout"], ["bug", "Bugs"], ["suggestion", "Suggestions"]]:
		var key: String = f[0]
		h.add_child(Game.button(f[1], func() -> void:
			_filter = key
			_load(), 0))
	_list = Game.scroll_list(body, 8)
	_load()


func _load() -> void:
	var res := await Api.get_json("/reports" + ("?type=" + _filter if _filter != "" else ""))
	if not is_inside_tree(): return
	Game.clear(_list)
	var reports: Array = res.get("reports", [])
	if reports.is_empty():
		_list.add_child(Game.label("Aucun signalement pour l'instant.", 18, Game.MUTED))
	for r in reports:
		_card(r)


func _card(r: Dictionary) -> void:
	var p := Game.panel()
	_list.add_child(p)
	var v := Game.vbox(4)
	p.add_child(v)
	var h := Game.hbox(10)
	v.add_child(h)
	var tag := Game.label("[BUG]" if r.type == "bug" else "[IDÉE]", 17, Color(1, 0.5, 0.4) if r.type == "bug" else Color(0.5, 0.85, 1), Game.font_bold)
	h.add_child(tag)
	h.add_child(Game.expand(Game.label(r.title, 20, Game.GOLD, Game.font_bold)))
	h.add_child(Game.label("Statut : %s" % r.status, 15, Game.GREEN.lightened(0.3) if r.status == "résolu" else Game.MUTED))
	var id: String = r.id
	var vote := Game.button("Moi aussi (%d)%s" % [r.votes, " - voté" if r.voted else ""], func() -> void: _post("/report/vote", {"id": id}), 0,
		Game.GREEN.darkened(0.4) if r.voted else Color(0.35, 0.28, 0.2))
	vote.custom_minimum_size = Vector2(0, 32)
	h.add_child(vote)
	var t := Game.label(r.text, 16, Game.CREAM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var date := Time.get_datetime_string_from_unix_time(int(r.date / 1000)).replace("T", " ").substr(0, 16)
	v.add_child(Game.label("par %s, le %s%s" % [r.author, date, ("  - v%s %s" % [r.version, r.platform]) if str(r.version) != "" else ""], 13, Game.MUTED))
	for c in r.comments:
		var cl := Game.label("    %s%s : %s" % [c.author, " (équipe)" if c.get("admin", false) else "", c.text], 15, Game.GOLD if c.get("admin", false) else Color(0.85, 0.8, 0.7))
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(cl)
	var ch := Game.hbox(6)
	v.add_child(ch)
	var input := LineEdit.new()
	input.placeholder_text = "Ajouter un commentaire..."
	Game.expand(input)
	ch.add_child(input)
	var send := func() -> void:
		if input.text.strip_edges() != "":
			_post("/report/comment", {"id": id, "text": input.text})
	input.text_submitted.connect(func(_t: String) -> void: send.call())
	var b := Game.button("Commenter", send, 0)
	b.custom_minimum_size = Vector2(0, 32)
	ch.add_child(b)
	if Game.account.get("admin", false):
		for s in ["en cours", "résolu", "refusé"]:
			var st: String = s
			var sb := Game.button(s, func() -> void: _post("/report/status", {"id": id, "status": st}), 0)
			sb.custom_minimum_size = Vector2(0, 32)
			ch.add_child(sb)


func _post(path: String, body: Dictionary) -> void:
	var res := await Api.post(path, body)
	if res.has("error"):
		Game.toast(res.error)
	_load()
