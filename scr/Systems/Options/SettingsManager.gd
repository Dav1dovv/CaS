## SettingsManager.gd
## Autoload-синглтон. Хранит, сохраняет и применяет все настройки игры.
## Project → Project Settings → Autoload → добавь как "SettingsManager"
extends Node
class_name SettingManager

# ──────────────────────────────────────────
#  CONSTANTS
# ──────────────────────────────────────────

const SETTINGS_PATH := "user://settings.cfg"

const BUS_MASTER := "Master"
const BUS_MUSIC  := "BGM"
const BUS_SFX    := "SFX"

## Доступные языки: [код TranslationServer, отображаемое имя]
const LANGUAGES := [
	["ru", "Русский"],
	["en", "English"],
]

const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

## Действия, которые можно переназначить.
## Ключ — action из InputMap, значение — отображаемое имя.
const REBINDABLE_ACTIONS := {
	"move_up"     : "Вверх",
	"move_down"   : "Вниз",
	"move_left"   : "Влево",
	"move_right"  : "Вправо",
	"jump"        : "Прыжок",
	"interact"    : "Взаимодействие",
	"inventory"   : "Инвентарь",
	"pause"       : "Пауза",
}

# ──────────────────────────────────────────
#  DEFAULTS
# ──────────────────────────────────────────

const DEFAULTS := {
	# Звук
	"master_volume" : 1.0,
	"music_volume"  : 0.8,
	"sfx_volume"    : 1.0,
	"mute_master"   : false,

	# Графика
	"fullscreen"       : false,
	"vsync"            : true,
	"resolution_index" : 0,

	# Язык
	"language" : "ru",
}

# ──────────────────────────────────────────
#  STATE
# ──────────────────────────────────────────

## Текущие настройки (звук, графика, язык)
var data: Dictionary = {}

## Переназначенные клавиши: { action: scancode }
var keybinds: Dictionary = {}

signal settings_changed

# ──────────────────────────────────────────
#  LIFECYCLE
# ──────────────────────────────────────────

func _ready() -> void:
	load_settings()
	apply_all()

# ──────────────────────────────────────────
#  PUBLIC API
# ──────────────────────────────────────────

func get_value(key: String) -> Variant:
	return data.get(key, DEFAULTS.get(key))

func set_value(key: String, value: Variant) -> void:
	data[key] = value
	_apply(key, value)
	settings_changed.emit()

func save_settings() -> void:
	var cfg := ConfigFile.new()

	# Основные настройки
	for key in DEFAULTS:
		cfg.set_value(_section(key), key, get_value(key))

	# Привязки клавиш
	for action in keybinds:
		cfg.set_value("Keybinds", action, keybinds[action])

	if cfg.save(SETTINGS_PATH) != OK:
		push_error("SettingsManager: не удалось сохранить настройки")

func load_settings() -> void:
	data     = DEFAULTS.duplicate()
	keybinds = _default_keybinds()

	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	for key in DEFAULTS:
		if cfg.has_section_key(_section(key), key):
			data[key] = cfg.get_value(_section(key), key)

	for action in REBINDABLE_ACTIONS:
		if cfg.has_section_key("Keybinds", action):
			keybinds[action] = cfg.get_value("Keybinds", action)

func reset_to_defaults() -> void:
	data     = DEFAULTS.duplicate()
	keybinds = _default_keybinds()
	apply_all()
	save_settings()
	settings_changed.emit()

func apply_all() -> void:
	for key in data:
		_apply(key, data[key])
	_apply_keybinds()

# ──────────────────────────────────────────
#  KEYBINDS
# ──────────────────────────────────────────

## Назначить клавишу действию и применить сразу
func rebind_action(action: String, scancode: int) -> void:
	keybinds[action] = scancode
	_apply_single_keybind(action, scancode)
	settings_changed.emit()

## Получить читаемое имя текущей клавиши для действия
func get_key_label(action: String) -> String:
	var sc: int = keybinds.get(action, 0)
	if sc == 0:
		return "—"
	return OS.get_keycode_string(sc)

func _default_keybinds() -> Dictionary:
	var result := {}
	for action in REBINDABLE_ACTIONS:
		result[action] = _get_first_scancode(action)
	return result

func _get_first_scancode(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.keycode
	return 0

func _apply_keybinds() -> void:
	for action in keybinds:
		_apply_single_keybind(action, keybinds[action])

func _apply_single_keybind(action: String, scancode: int) -> void:
	if not InputMap.has_action(action) or scancode == 0:
		return
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.keycode = scancode
	InputMap.action_add_event(action, ev)

# ──────────────────────────────────────────
#  APPLY  (private)
# ──────────────────────────────────────────

func _apply(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			_set_bus_volume(BUS_MASTER, value)
		"music_volume":
			_set_bus_volume(BUS_MUSIC, value)
			_sync_blaze_music(value)
		"sfx_volume":
			_set_bus_volume(BUS_SFX, value)
		"mute_master":
			var idx := AudioServer.get_bus_index(BUS_MASTER)
			if idx >= 0:
				AudioServer.set_bus_mute(idx, value)
		"fullscreen":
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if value
				else DisplayServer.WINDOW_MODE_WINDOWED
			)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			)
		"resolution_index":
			if not get_value("fullscreen"):
				var idx: int = clampi(value, 0, RESOLUTIONS.size() - 1)
				DisplayServer.window_set_size(RESOLUTIONS[idx])
		"language":
			TranslationServer.set_locale(value)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))

## Синхронизация громкости с BlazeMusicManager
func _sync_blaze_music(volume: float) -> void:
	var blaze := _get_blaze()
	if blaze == null:
		return
	# BlazeMusicManager управляет громкостью через volume_db своих плееров.
	# Устанавливаем целевую громкость на активном плеере (_active).
	# Неактивный плеер управляется tween-ом при кроссфейде — он подхватит
	# целевую громкость через set_music_volume(), которую мы добавили в MusicManager.
	if blaze.has_method("set_music_volume"):
		blaze.set_music_volume(volume)

func _get_blaze() -> Node:
	var nodes := get_tree().get_nodes_in_group("MusicManager")
	return nodes[0] if not nodes.is_empty() else null

# ──────────────────────────────────────────
#  HELPERS
# ──────────────────────────────────────────

func _section(key: String) -> String:
	match key:
		"master_volume", "music_volume", "sfx_volume", "mute_master":
			return "Audio"
		"fullscreen", "vsync", "resolution_index":
			return "Graphics"
		"language":
			return "Localization"
	return "General"
