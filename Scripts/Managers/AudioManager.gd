extends Node

const SFX_POOL_SIZE: int = 20
const DEFAULT_MUSIC_DB: float = -4.0

const SFX_PATHS: Dictionary = {
	&"ui_hover": "res://Assets/Audio/SFX/ui_hover.wav",
	&"ui_click": "res://Assets/Audio/SFX/ui_click.wav",
	&"ui_confirm": "res://Assets/Audio/SFX/ui_confirm.wav",
	&"ui_cancel": "res://Assets/Audio/SFX/ui_cancel.wav",
	&"ui_error": "res://Assets/Audio/SFX/ui_error.wav",
	&"ui_window_open": "res://Assets/Audio/SFX/ui_window_open.wav",
	&"ui_window_close": "res://Assets/Audio/SFX/ui_window_close.wav",
	&"ui_map_open": "res://Assets/Audio/SFX/ui_map_open.wav",
	&"ui_pause": "res://Assets/Audio/SFX/ui_pause.wav",

	&"gold_coins": "res://Assets/Audio/SFX/gold_coins.wav",
	&"item_equip": "res://Assets/Audio/SFX/item_equip.wav",
	&"item_unequip": "res://Assets/Audio/SFX/item_unequip.wav",
	&"item_move": "res://Assets/Audio/SFX/item_move.wav",
	&"potion_drink": "res://Assets/Audio/SFX/potion_drink.wav",
	&"smith_craft": "res://Assets/Audio/SFX/smith_craft.wav",
	&"smith_upgrade": "res://Assets/Audio/SFX/smith_upgrade.wav",
	&"enchant_apply": "res://Assets/Audio/SFX/enchant_apply.wav",
	&"level_up": "res://Assets/Audio/SFX/level_up.wav",
	&"title_unlock": "res://Assets/Audio/SFX/title_unlock.wav",
	&"victory_fanfare": "res://Assets/Audio/SFX/victory_fanfare.wav",
	&"defeat_stinger": "res://Assets/Audio/SFX/defeat_stinger.wav",

	&"step_hero": "res://Assets/Audio/SFX/step_hero.wav",
	&"step_enemy": "res://Assets/Audio/SFX/step_enemy.wav",
	&"portal_enter": "res://Assets/Audio/SFX/portal_enter.wav",

	&"sword_swing": "res://Assets/Audio/SFX/sword_swing.wav",
	&"heavy_cleave": "res://Assets/Audio/SFX/heavy_cleave.wav",
	&"hit_melee": "res://Assets/Audio/SFX/hit_melee.wav",
	&"crit_slam": "res://Assets/Audio/SFX/crit_slam.wav",
	&"knockback_slide": "res://Assets/Audio/SFX/knockback_slide.wav",
	&"shield_block": "res://Assets/Audio/SFX/shield_block.wav",
	&"dodge_whoosh": "res://Assets/Audio/SFX/dodge_whoosh.wav",
	&"bow_release": "res://Assets/Audio/SFX/bow_release.wav",
	&"arrow_hit": "res://Assets/Audio/SFX/arrow_hit.wav",
	&"spell_fire": "res://Assets/Audio/SFX/spell_fire.wav",
	&"spell_ice": "res://Assets/Audio/SFX/spell_ice.wav",
	&"spell_holy": "res://Assets/Audio/SFX/spell_holy.wav",
	&"spell_heal": "res://Assets/Audio/SFX/spell_heal.wav",
	&"element_swap": "res://Assets/Audio/SFX/element_swap.wav",

	&"monster_growl": "res://Assets/Audio/SFX/monster_growl.wav",
	&"bleed_inflict": "res://Assets/Audio/SFX/bleed_inflict.wav",
	&"werewolf_regen": "res://Assets/Audio/SFX/werewolf_regen.wav",
	&"necro_cast": "res://Assets/Audio/SFX/necro_cast.wav",
	&"necro_summon": "res://Assets/Audio/SFX/necro_summon.wav",
	&"necro_vanish": "res://Assets/Audio/SFX/necro_vanish.wav",
	&"necro_reappear": "res://Assets/Audio/SFX/necro_reappear.wav",
	&"hurt_hero": "res://Assets/Audio/SFX/hurt_hero.wav",
	&"hurt_enemy": "res://Assets/Audio/SFX/hurt_enemy.wav",
	&"death_hero": "res://Assets/Audio/SFX/death_hero.wav",
	&"death_enemy": "res://Assets/Audio/SFX/death_enemy.wav",
	&"enemy_revive": "res://Assets/Audio/SFX/enemy_revive.wav",
}

const MUSIC_PATHS: Dictionary = {
	&"menu": "res://Assets/Audio/Music/menu_theme.ogg",
	&"lobby": "res://Assets/Audio/Music/lobby_theme.ogg",
	&"dungeon": "res://Assets/Audio/Music/dungeon_theme.ogg",
	&"battle": "res://Assets/Audio/Music/battle_theme.ogg",
	&"boss": "res://Assets/Audio/Music/boss_theme.ogg",
}

var _stream_cache: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _last_sfx_ms: Dictionary = {}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _current_music_id: StringName = &""
var _music_tween: Tween
var _context_timer: float = 0.0
var _suppress_music_context: bool = false
var _boss_encounter_active: bool = false
var _last_scene_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_build_players()

	var tree := get_tree()
	if tree != null:
		if not tree.node_added.is_connected(_on_tree_node_added):
			tree.node_added.connect(_on_tree_node_added)
		call_deferred("_scan_initial_ui", tree.root)
		call_deferred("refresh_music_context")


func _exit_tree() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
	_active_music_player = null
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for m in [_music_a, _music_b]:
		if is_instance_valid(m):
			m.stop()
			m.stream = null
	_stream_cache.clear()


func _process(delta: float) -> void:
	_context_timer += delta
	if _context_timer >= 0.30:
		_context_timer = 0.0
		refresh_music_context()


func sfx(sound_id: StringName, pitch_min: float = 0.96, pitch_max: float = 1.04, volume_db: float = 0.0, cooldown_sec: float = 0.035) -> void:
	play_sfx(sound_id, pitch_min, pitch_max, volume_db, cooldown_sec)


func music(track_id: StringName, fade_sec: float = 0.65) -> void:
	play_music(track_id, fade_sec)


func fade_out_music(fade_sec: float = 0.45) -> void:
	_suppress_music_context = true
	stop_music(fade_sec)


func resume_music_context() -> void:
	_suppress_music_context = false
	refresh_music_context()


func set_boss_encounter_active(active: bool) -> void:
	_boss_encounter_active = active
	if not _suppress_music_context:
		refresh_music_context()


func mark_custom_button_sfx(button: BaseButton) -> void:
	if button != null and is_instance_valid(button):
		button.set_meta(&"sfx_custom", true)


func play_sfx(sound_id: StringName, pitch_min: float = 0.96, pitch_max: float = 1.04, volume_db: float = 0.0, cooldown_sec: float = 0.035) -> void:
	var path: String = String(SFX_PATHS.get(sound_id, ""))
	if path.is_empty():
		return

	var now_ms := Time.get_ticks_msec()
	var prev_ms := int(_last_sfx_ms.get(sound_id, -999999))
	if now_ms - prev_ms < int(cooldown_sec * 1000.0):
		return
	_last_sfx_ms[sound_id] = now_ms

	var stream := _load_stream(path)
	if stream == null:
		return

	var player := _acquire_sfx_player()
	if player == null:
		return

	player.bus = _resolve_bus(&"SFX")
	player.stream = stream
	player.volume_db = volume_db
	if is_equal_approx(pitch_min, pitch_max):
		player.pitch_scale = maxf(0.2, pitch_min)
	else:
		player.pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	player.play()


func play_music(track_id: StringName, fade_sec: float = 0.65) -> void:
	if track_id == &"":
		stop_music(fade_sec)
		return
	if _current_music_id == track_id and _active_music_player != null and _active_music_player.playing:
		return

	var path: String = String(MUSIC_PATHS.get(track_id, ""))
	if path.is_empty():
		return

	if not is_inside_tree() or _music_a == null or _music_b == null:
		return

	var stream := _load_stream(path)
	if stream == null:
		return

	_current_music_id = track_id
	var incoming := _music_b if _active_music_player == _music_a else _music_a
	var outgoing := _active_music_player
	if incoming == null:
		return
	_active_music_player = incoming

	incoming.bus = _resolve_bus(&"Music")
	incoming.stream = stream
	incoming.volume_db = -42.0 if fade_sec > 0.05 else DEFAULT_MUSIC_DB
	incoming.play()

	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()

	if fade_sec <= 0.05:
		if outgoing != null:
			outgoing.stop()
		incoming.volume_db = DEFAULT_MUSIC_DB
		return

	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", DEFAULT_MUSIC_DB, fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if outgoing != null and outgoing.playing:
		_music_tween.tween_property(outgoing, "volume_db", -45.0, fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.chain().tween_callback(func():
			if is_instance_valid(outgoing) and outgoing != _active_music_player:
				outgoing.stop()
		)


func stop_music(fade_sec: float = 0.45) -> void:
	_current_music_id = &""
	if not is_inside_tree():
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if fade_sec <= 0.05:
		if _music_a != null: _music_a.stop()
		if _music_b != null: _music_b.stop()
		return
	_music_tween = create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		if p != null and p.playing:
			_music_tween.tween_property(p, "volume_db", -45.0, fade_sec)
	_music_tween.chain().tween_callback(func():
		if _current_music_id == &"":
			if is_instance_valid(_music_a): _music_a.stop()
			if is_instance_valid(_music_b): _music_b.stop()
	)


func refresh_music_context() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return

	var sid := scene.get_instance_id()
	if sid != _last_scene_id:
		_last_scene_id = sid
		_boss_encounter_active = false
		_suppress_music_context = false

	if _suppress_music_context:
		return

	var death_ui := tree.get_first_node_in_group("death_screen")
	if death_ui != null and bool(death_ui.get("visible")):
		if _current_music_id != &"":
			stop_music(0.35)
		return

	var scene_name := scene.name.to_lower()
	var scene_path := scene.scene_file_path.to_lower()

	if "mainmenu" in scene_name or "mainmenu" in scene_path or "main_menu" in scene_path:
		play_music(&"menu", 0.7)
		return
	if "lobby" in scene_name or "lobby" in scene_path:
		play_music(&"lobby", 0.7)
		return

	# Dungeon / Debug room / Battle / Boss
	var battle_ui := tree.get_first_node_in_group("battle_ui")
	if battle_ui != null and bool(battle_ui.get("combat_active")):
		var raw_enemy: Variant = battle_ui.get("enemy_ref")
		var enemy_node: Node = raw_enemy as Node if is_instance_valid(raw_enemy) else null
		if _is_necromancer_node(enemy_node) or _boss_encounter_active:
			play_music(&"boss", 0.35)
		else:
			play_music(&"battle", 0.35)
		return

	if _boss_encounter_active or _is_boss_encounter_active(tree):
		play_music(&"boss", 0.65)
	else:
		play_music(&"dungeon", 0.75)


func _is_boss_encounter_active(tree: SceneTree) -> bool:
	var hero := tree.get_first_node_in_group("player") as Node2D
	for enemy in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not _is_necromancer_node(enemy):
			continue
		if enemy.has_method("is_monster_alive") and not enemy.is_monster_alive():
			continue
		var combat_node := enemy.get_node_or_null("Combat")
		if combat_node != null and combat_node.get("elite_combat") != null:
			var elite = combat_node.elite_combat
			if int(elite.necromancer_phase) > 0:
				return true
		if hero != null and is_instance_valid(hero) and hero.global_position.distance_to((enemy as Node2D).global_position) <= 260.0:
			return true
	return false


func _is_necromancer_node(enemy: Node) -> bool:
	if not is_instance_valid(enemy):
		return false
	var data = enemy.get("enemy_data")
	return data != null and int(data.get("special_profile")) == 4


func _build_players() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer_%d" % i
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = _resolve_bus(&"SFX")
		add_child(p)
		_sfx_players.append(p)

	_music_a = AudioStreamPlayer.new()
	_music_a.name = "MusicPlayerA"
	_music_a.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a.bus = _resolve_bus(&"Music")
	_music_a.finished.connect(_on_music_finished.bind(_music_a))
	add_child(_music_a)

	_music_b = AudioStreamPlayer.new()
	_music_b.name = "MusicPlayerB"
	_music_b.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_b.bus = _resolve_bus(&"Music")
	_music_b.finished.connect(_on_music_finished.bind(_music_b))
	add_child(_music_b)


func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player == _active_music_player and _current_music_id != &"" and not _suppress_music_context:
		player.play()


func _acquire_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	if _sfx_players.is_empty():
		return null
	var chosen := _sfx_players[_sfx_cursor % _sfx_players.size()]
	_sfx_cursor += 1
	return chosen


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and FileAccess.file_exists(path):
		if path.ends_with(".wav"):
			stream = AudioStreamWAV.load_from_file(path)
		elif path.ends_with(".ogg"):
			stream = AudioStreamOggVorbis.load_from_file(path)
	if stream != null:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_stream_cache[path] = stream
	return stream


func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


func _resolve_bus(target_bus: StringName) -> StringName:
	return target_bus if AudioServer.get_bus_index(target_bus) >= 0 else &"Master"


func _scan_initial_ui(root: Node) -> void:
	if not is_instance_valid(root):
		return
	_hook_ui_node(root)
	for child in root.get_children():
		_scan_initial_ui(child)


func _on_tree_node_added(node: Node) -> void:
	_hook_ui_node(node)


func _hook_ui_node(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta(&"sfx_hooked"):
		return
	if node is BaseButton:
		var btn := node as BaseButton
		btn.set_meta(&"sfx_hooked", true)
		btn.mouse_entered.connect(func():
			if is_instance_valid(btn) and btn.visible and not btn.disabled:
				play_sfx(&"ui_hover", 0.96, 1.05, -9.0, 0.045)
		)
		btn.pressed.connect(func():
			if is_instance_valid(btn) and not bool(btn.get_meta(&"sfx_custom", false)):
				play_sfx(&"ui_click", 0.95, 1.05, -2.0, 0.04)
		)
	elif node is TabBar:
		var tb := node as TabBar
		tb.set_meta(&"sfx_hooked", true)
		tb.tab_changed.connect(func(_idx: int):
			play_sfx(&"ui_click", 0.98, 1.06, -3.0, 0.05)
		)
	elif node is OptionButton:
		var ob := node as OptionButton
		ob.set_meta(&"sfx_hooked", true)
		ob.item_selected.connect(func(_idx: int):
			play_sfx(&"ui_confirm", 0.98, 1.04, -3.0, 0.05)
		)
