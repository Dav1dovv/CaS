extends Area2D
class_name BoostZone

# ═════════════════════════════════════════════════════════════════════════════
#  ЗОНА УСКОРЕНИЯ — течения, пороги, ускорители
# ═════════════════════════════════════════════════════════════════════════════
#
# Увеличивает скорость корабля и может задать направление
#
# Два режима работы:
# 1. boost_mode = "speed" — просто увеличивает max_speed корабля
# 2. boost_mode = "directional" — толкает в определённом направлении (как быстрое течение)
#
# ═════════════════════════════════════════════════════════════════════════════

enum BoostMode { SPEED, DIRECTIONAL }

## Режим работы
@export var boost_mode: BoostMode = BoostMode.SPEED

## Множитель скорости для режима SPEED (1.5 = +50% скорости)
@export_range(1.0, 3.0, 0.1) var speed_multiplier: float = 1.5

## Направление течения для режима DIRECTIONAL (градусы)
@export_range(0, 360, 1) var current_direction: float = 0.0

## Сила течения для режима DIRECTIONAL (пикселей/сек)
@export var current_strength: float = 400.0

var ships_in_zone: Array[Node] = []
var original_speeds: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if boost_mode == BoostMode.DIRECTIONAL:
		_apply_current_force(delta)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and "max_speed" in body:
		ships_in_zone.append(body)
		
		if boost_mode == BoostMode.SPEED:
			# Сохраняем оригинальную скорость
			if not body in original_speeds:
				original_speeds[body] = body.max_speed
			
			# Увеличиваем максимальную скорость
			body.max_speed = original_speeds[body] * speed_multiplier
			print("BoostZone: Скорость увеличена до %s%%" % (speed_multiplier * 100))


func _on_body_exited(body: Node2D) -> void:
	if body in ships_in_zone:
		ships_in_zone.erase(body)
		
		if boost_mode == BoostMode.SPEED and body in original_speeds:
			body.max_speed = original_speeds[body]
			original_speeds.erase(body)
			print("BoostZone: Скорость восстановлена")


# ─── Применение силы течения ────────────────────────────────────────────────

func _apply_current_force(delta: float) -> void:
	var current_vector := Vector2.RIGHT.rotated(deg_to_rad(current_direction))
	
	for ship in ships_in_zone:
		if not is_instance_valid(ship) or not "_velocity" in ship:
			continue
		
		ship._velocity += current_vector * current_strength * delta


# ─── Визуализация ───────────────────────────────────────────────────────────

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	
	var color := Color(0.2, 0.8, 1.0, 0.4)
	
	if boost_mode == BoostMode.DIRECTIONAL:
		# Стрелки течения
		for i in range(5):
			var offset := Vector2(i * 30 - 60, 0)
			var start := offset
			var end := offset + Vector2.RIGHT.rotated(deg_to_rad(current_direction)) * 40
			draw_line(start, end, color, 3.0)
			
			# Наконечник стрелки
			var arrow_tip := end + Vector2(-8, -4).rotated(deg_to_rad(current_direction))
			draw_line(end, arrow_tip, color, 3.0)
			arrow_tip = end + Vector2(-8, 4).rotated(deg_to_rad(current_direction))
			draw_line(end, arrow_tip, color, 3.0)
	else:
		# Иконка ускорения
		draw_circle(Vector2.ZERO, 30, Color(0.3, 1.0, 0.3, 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(-15, 5), "x%.1f" % speed_multiplier, 
					HORIZONTAL_ALIGNMENT_CENTER, -1, 16, color)
