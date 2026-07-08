extends HBoxContainer
class_name EffectDisplayUI

const EFFECT_ICON_SCENE = preload("res://scr/Resources/effects/EffectIcon.tscn")

var tracked_entity: Entity

# Словарь: effect_type → { "container": Control, "label": Label }
var effect_icons: Dictionary = {}

func _ready():
	set_process(true)

func set_entity(entity: Entity) -> void:
	if tracked_entity and tracked_entity.effect_manager:
		tracked_entity.effect_manager.effect_added.disconnect(_on_effect_added)
		tracked_entity.effect_manager.effect_removed.disconnect(_on_effect_removed)

	tracked_entity = entity

	if tracked_entity and tracked_entity.effect_manager:
		tracked_entity.effect_manager.effect_added.connect(_on_effect_added)
		tracked_entity.effect_manager.effect_removed.connect(_on_effect_removed)

		for active_effect in tracked_entity.effect_manager.get_active_effects():
			_on_effect_added(active_effect.effect)

func _process(_delta: float) -> void:
	if not tracked_entity or not tracked_entity.effect_manager:
		return

	for effect_type in effect_icons.keys():
		var entry: Dictionary = effect_icons[effect_type]
		var timer_label: Label = entry.get("label")
		if not timer_label:
			continue

		var time_left: float = tracked_entity.effect_manager.get_effect_time_remaining(effect_type)

		if time_left > 0.0:
			timer_label.text = str(ceili(time_left))
			timer_label.visible = true
		else:
			# Мгновенный или постоянный эффект — прячем таймер
			timer_label.visible = false

func _on_effect_added(effect: Effect) -> void:
	if effect_icons.has(effect.effect_type):
		return

	var container: Control = _create_effect_icon(effect)
	add_child(container)

	# Сохраняем прямую ссылку на лейбл — не ищем по имени каждый кадр
	var timer_label: Label = container.get_node("Margin/VBox/Timer")
	effect_icons[effect.effect_type] = {
		"container": container,
		"label":     timer_label,
	}

func _on_effect_removed(effect: Effect) -> void:
	if not effect_icons.has(effect.effect_type):
		return

	var entry: Dictionary = effect_icons[effect.effect_type]
	entry["container"].queue_free()
	effect_icons.erase(effect.effect_type)

func _create_effect_icon(effect: Effect) -> Control:
	var container := PanelContainer.new()
	container.custom_minimum_size = Vector2(48, 48)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left",   4)
	margin.add_theme_constant_override("margin_right",  4)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 4)
	container.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)

	# ── Иконка ──────────────────────────────────────────
	var icon_texture: Texture2D = effect.effect_icon if effect.effect_icon else effect.icon

	if icon_texture:
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(32, 32)
		texture_rect.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.texture      = icon_texture
		vbox.add_child(texture_rect)
	else:
		# Цветной квадрат как заглушка
		var color_rect := ColorRect.new()
		color_rect.color               = effect.particle_color
		color_rect.custom_minimum_size = Vector2(32, 32)
		vbox.add_child(color_rect)

	# ── Таймер ──────────────────────────────────────────
	var timer_label := Label.new()
	timer_label.name                 = "Timer"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 10)
	# Сразу ставим начальное значение — до первого _process
	if effect.duration > 0.0:
		timer_label.text    = str(ceili(effect.duration))
		timer_label.visible = true
	else:
		timer_label.text    = ""
		timer_label.visible = false
	vbox.add_child(timer_label)

	# ── Тултип ──────────────────────────────────────────
	container.tooltip_text = effect.get_tooltip_text()

	# ── Анимация появления ──────────────────────────────
	container.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(container, "modulate:a", 1.0, 0.3)

	return container

func clear_effects() -> void:
	for entry in effect_icons.values():
		entry["container"].queue_free()
	effect_icons.clear()
