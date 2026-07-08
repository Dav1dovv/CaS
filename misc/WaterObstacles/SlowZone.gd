extends Area2D
class_name SlowZone

# ═════════════════════════════════════════════════════════════════════════════
#  ЗОНА ЗАМЕДЛЕНИЯ — мелководье, водоросли, лёд
# ═════════════════════════════════════════════════════════════════════════════
#
# Замедляет корабль находящийся в зоне.
# Можно использовать для:
# - Мелководья
# - Полей водорослей
# - Ледяных полей
# - Болот
#
# ═════════════════════════════════════════════════════════════════════════════

## Множитель скорости (0.5 = половина скорости, 0.1 = очень медленно)
@export_range(0.1, 1.0, 0.05) var speed_multiplier: float = 0.5

## Цвет подкраски зоны в редакторе
@export var zone_color: Color = Color(0.3, 0.6, 0.3, 0.3)

var ships_in_zone: Array[Node] = []
var original_speeds: Dictionary = {}  # Запоминаем оригинальные значения


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and "max_speed" in body:
		ships_in_zone.append(body)
		
		# Сохраняем оригинальную скорость
		if not body in original_speeds:
			original_speeds[body] = body.max_speed
		
		# Применяем замедление
		body.max_speed = original_speeds[body] * speed_multiplier
		print("SlowZone: Корабль замедлен до %s%%" % (speed_multiplier * 100))


func _on_body_exited(body: Node2D) -> void:
	if body in ships_in_zone:
		ships_in_zone.erase(body)
		
		# Восстанавливаем скорость
		if body in original_speeds:
			body.max_speed = original_speeds[body]
			original_speeds.erase(body)
			print("SlowZone: Скорость корабля восстановлена")


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Визуализация зоны
	var shape := get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D:
		var rect: RectangleShape2D = shape.shape
		draw_rect(Rect2(-rect.size / 2, rect.size), zone_color)
	elif shape and shape.shape is CircleShape2D:
		var circle: CircleShape2D = shape.shape
		draw_circle(Vector2.ZERO, circle.radius, zone_color)
