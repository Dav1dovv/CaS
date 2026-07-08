extends Area2D
class_name WindZone

# ═════════════════════════════════════════════════════════════════════════════
#  ЗОНА ВЕТРА — толкает корабль в определённом направлении
# ═════════════════════════════════════════════════════════════════════════════
#
# Как использовать:
# 1. Создай Area2D узел и прикрепи этот скрипт
# 2. Добавь дочерний CollisionShape2D (например, прямоугольник или круг)
# 3. Настрой параметры в инспекторе:
#    - wind_direction — направление ветра (0° = вправо, 90° = вниз)
#    - wind_strength — сила толчка
#    - visual_particles — путь к частицам (опционально)
#
# ═════════════════════════════════════════════════════════════════════════════

## Направление ветра в градусах (0° = вправо, 90° = вниз, 180° = влево, 270° = вверх)
@export_range(0, 360, 1) var wind_direction: float = 0.0

## Сила ветра (пикселей/сек² ускорения)
@export var wind_strength: float = 150.0

## Опционально: путь к GPUParticles2D или CPUParticles2D для визуализации
@export var visual_particles: NodePath

## Показывать стрелку направления ветра в редакторе
@export var show_debug_arrow: bool = true

# Список кораблей внутри зоны
var ships_in_zone: Array[Node] = []

# Для визуализации в редакторе
var arrow_points: PackedVector2Array = []


func _ready() -> void:
	# Подключаем сигналы Area2D
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Настраиваем частицы (если указаны)
	if not visual_particles.is_empty():
		var particles = get_node_or_null(visual_particles)
		if particles:
			_setup_particles(particles)
	
	# Создаём стрелку для редактора
	_update_debug_arrow()


func _physics_process(delta: float) -> void:
	# Применяем силу ветра ко всем кораблям в зоне
	for ship in ships_in_zone:
		if not is_instance_valid(ship):
			continue
		
		_apply_wind_force(ship, delta)


# ─── Вход корабля в зону ветра ──────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	# Проверяем что это корабль (CharacterBody2D с методом управления)
	if body is CharacterBody2D and body.has_method("_move_toward_mouse"):
		ships_in_zone.append(body)
		print("WindZone: Корабль вошёл в зону ветра")


func _on_body_exited(body: Node2D) -> void:
	if body in ships_in_zone:
		ships_in_zone.erase(body)
		print("WindZone: Корабль покинул зону ветра")


# ─── Применение силы ветра ──────────────────────────────────────────────────

func _apply_wind_force(ship: Node, delta: float) -> void:
	# Вычисляем вектор направления ветра
	var wind_vector := Vector2.RIGHT.rotated(deg_to_rad(wind_direction))
	
	# Применяем силу к velocity корабля
	if "_velocity" in ship:
		ship._velocity += wind_vector * wind_strength * delta


# ─── Настройка частиц для визуализации ──────────────────────────────────────

func _setup_particles(particles: Node) -> void:
	if particles is GPUParticles2D or particles is CPUParticles2D:
		# Поворачиваем частицы по направлению ветра
		particles.rotation = deg_to_rad(wind_direction)
		particles.emitting = true


# ─── Визуализация в редакторе ───────────────────────────────────────────────

func _update_debug_arrow() -> void:
	if not show_debug_arrow:
		return
	
	var length: float = 50.0
	var end_point := Vector2.RIGHT.rotated(deg_to_rad(wind_direction)) * length
	
	# Стрелка: линия + два крыла
	arrow_points = PackedVector2Array([
		Vector2.ZERO,
		end_point,
		end_point + Vector2(-10, -5).rotated(deg_to_rad(wind_direction)),
		end_point,
		end_point + Vector2(-10, 5).rotated(deg_to_rad(wind_direction))
	])
	
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_debug_arrow:
		return
	
	# Рисуем стрелку направления
	var color := Color(0.3, 0.7, 1.0, 0.8)  # Голубой
	for i in range(arrow_points.size() - 1):
		draw_line(arrow_points[i], arrow_points[i + 1], color, 2.0)
	
	# Текст с информацией
	var text := "Wind %d° (%d)" % [wind_direction, wind_strength]
	draw_string(ThemeDB.fallback_font, Vector2(-30, -60), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)


# ─── Для live-редактирования в инспекторе ───────────────────────────────────

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	# Проверяем наличие CollisionShape2D
	var has_collision := false
	for child in get_children():
		if child is CollisionShape2D:
			has_collision = true
			break
	
	if not has_collision:
		warnings.append("Добавь CollisionShape2D чтобы определить зону ветра")
	
	return warnings


# Для обновления стрелки при изменении параметров в редакторе
func _set(property: StringName, value: Variant) -> bool:
	if property == "wind_direction" or property == "wind_strength":
		_update_debug_arrow()
	return false
