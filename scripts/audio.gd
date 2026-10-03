extends Node
## Musique (fondu enchaîné) et effets sonores, volumes enregistrés dans user://settings.cfg.

const SETTINGS := "user://settings.cfg"

var music_volume := 0.7
var sfx_volume := 0.8
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS)
	if _music_a.playing:
		_music_a.volume_db = _db(music_volume)


func _db(v: float) -> float:
	return linear_to_db(max(v, 0.0001))


func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func music(id: String, loop := true) -> void:
	if id == _current:
		return
	_current = id
	var s := _stream("res://assets/music/%s.ogg" % id)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		s.loop = loop
	# fondu : l'ancien lecteur s'éteint, le nouveau monte
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	_music_a.stream = s
	_music_a.volume_db = -40.0
	_music_a.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_music_a, "volume_db", _db(music_volume), 1.2)
	if _music_b.playing:
		tw.tween_property(_music_b, "volume_db", -60.0, 1.0)
		tw.chain().tween_callback(_music_b.stop)


func stop_music() -> void:
	_current = ""
	var tw := create_tween()
	tw.tween_property(_music_a, "volume_db", -60.0, 0.6)
	tw.tween_callback(_music_a.stop)


func sfx(id: String, pitch_var := 0.08, vol := 1.0) -> void:
	var s := _stream("res://assets/sfx/%s.wav" % id)
	if s == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = s
			p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.volume_db = _db(sfx_volume * vol)
			p.play()
			return


func click() -> void:
	sfx("click", 0.05, 0.6)
