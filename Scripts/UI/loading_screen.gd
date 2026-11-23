extends CanvasLayer
class_name LoadingScreen

signal loading_finished

const TIPS: Array[String] = [
	"Tipp: Nyomd meg az [M] billentyűt a teljes dungeon térkép megnyitásához!",
	"Tipp: Szüneteltetheted a játékot az [ESC] vagy [P] gombbal, illetve a jobb felső SZÜNET gombbal.",
	"Tipp: A kezdeményezés határozza meg, ki támad először a harcban!",
	"Tipp: A fáklyák fényköre feloldja a környező területek ködét.",
	"Tipp: Erősebb ellenfelek legyőzésekor különleges titulust is szerezhetsz!"
]

@onready var root_control: Control = find_child("Root", true, false) as Control
@onready var crest_icon_rect: TextureRect = find_child("CrestIcon", true, false) as TextureRect
@onready var title_label: Label = find_child("TitleLabel", true, false) as Label
@onready var dungeon_info_icon: TextureRect = find_child("DungeonInfoIcon", true, false) as TextureRect
@onready var dungeon_info_label: Label = find_child("DungeonInfoLabel", true, false) as Label
@onready var stage_label: Label = find_child("StageLabel", true, false) as Label
@onready var progress_bar: ProgressBar = find_child("ProgressBar", true, false) as ProgressBar
@onready var percent_label: Label = find_child("PercentLabel", true, false) as Label
@onready var tip_label: Label = find_child("TipLabel", true, false) as Label

var _target_progress: float = 0.0
var _displayed_progress: float = 0.0
var _fade_tween: Tween = null
var _title_base: String = "DUNGEON BETÖLTÉSE"
var _finished_title: String = "DUNGEON BETÖLTVE"
var _finished_stage: String = "Készen állsz! Jó felfedezést!"
var _is_finishing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return

	if _displayed_progress < _target_progress:
		_displayed_progress = move_toward(_displayed_progress, _target_progress, maxf(delta * 1.8, 0.02))
		_apply_progress_visuals(_displayed_progress)

	if title_label and not _is_finishing:
		var dot_count: int = (int(Time.get_ticks_msec() / 350.0) % 3) + 1
		var dots := ".".repeat(dot_count)
		title_label.text = _title_base + dots


func begin_loading(dungeon_name: String, difficulty_name: String) -> void:
	var d_text := dungeon_name if not dungeon_name.is_empty() else "Ismeretlen Dungeon"
	var diff_text := difficulty_name if not difficulty_name.is_empty() else "Normál"
	begin_scene_loading(
		"DUNGEON BETÖLTÉSE",
		"%s  •  Nehézség: %s" % [d_text, diff_text],
		"Előkészítés...",
		UiIcons.PLAY_SWORD,
		"DUNGEON BETÖLTVE",
		"Készen állsz! Jó felfedezést!",
		UiIcons.DUNGEON
	)


func begin_scene_loading(
	title_text: String,
	info_text: String,
	initial_stage: String = "Betöltés...",
	icon_path: String = UiIcons.HOURGLASS,
	finished_title_text: String = "BETÖLTVE",
	finished_stage_text: String = "Kész!",
	info_icon_path: String = UiIcons.DUNGEON
) -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
		_fade_tween = null

	_title_base = title_text if not title_text.is_empty() else "BETÖLTÉS"
	_finished_title = finished_title_text if not finished_title_text.is_empty() else "BETÖLTVE"
	_finished_stage = finished_stage_text if not finished_stage_text.is_empty() else "Kész!"
	_is_finishing = false

	_target_progress = 0.02
	_displayed_progress = 0.02

	if root_control:
		root_control.modulate = Color(1, 1, 1, 1)

	if crest_icon_rect:
		var resolved_crest := icon_path if icon_path.begins_with("res://") else UiIcons.HOURGLASS
		if ResourceLoader.exists(resolved_crest):
			crest_icon_rect.texture = load(resolved_crest) as Texture2D

	if dungeon_info_icon:
		var resolved_info_icon := info_icon_path if info_icon_path.begins_with("res://") else UiIcons.DUNGEON
		if ResourceLoader.exists(resolved_info_icon):
			dungeon_info_icon.texture = load(resolved_info_icon) as Texture2D

	if title_label:
		title_label.text = _title_base + "."

	if dungeon_info_label:
		dungeon_info_label.text = info_text

	if stage_label:
		stage_label.text = initial_stage

	if tip_label and not TIPS.is_empty():
		tip_label.text = TIPS[randi() % TIPS.size()]

	_apply_progress_visuals(_displayed_progress)
	visible = true


func set_progress(progress_ratio: float, stage_text: String = "") -> void:
	_target_progress = maxf(_target_progress, clampf(progress_ratio, 0.0, 1.0))
	if stage_label and not stage_text.is_empty():
		stage_label.text = stage_text


func finish_and_hide() -> void:
	if not visible:
		return

	_is_finishing = true
	_target_progress = 1.0
	_displayed_progress = 1.0
	_apply_progress_visuals(1.0)
	if stage_label:
		stage_label.text = _finished_stage
	if title_label:
		title_label.text = _finished_title

	if root_control:
		_fade_tween = create_tween()
		_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_fade_tween.tween_interval(0.10)
		_fade_tween.tween_property(root_control, "modulate:a", 0.0, 0.22)
		await _fade_tween.finished

	visible = false
	_is_finishing = false
	if root_control:
		root_control.modulate = Color(1, 1, 1, 1)
	loading_finished.emit()


func force_hide() -> void:
	_is_finishing = false
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
		_fade_tween = null
	visible = false
	if root_control:
		root_control.modulate = Color(1, 1, 1, 1)


func _apply_progress_visuals(value_ratio: float) -> void:
	var pct: float = clampf(value_ratio, 0.0, 1.0) * 100.0
	if progress_bar:
		progress_bar.max_value = 100.0
		progress_bar.value = pct
	if percent_label:
		percent_label.text = "%d%%" % roundi(pct)
