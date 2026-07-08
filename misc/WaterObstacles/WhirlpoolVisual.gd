extends Sprite2D

# ═════════════════════════════════════════════════════════════════════════════
#  ВИЗУАЛЬНАЯ АНИМАЦИЯ ВОДОВОРОТА
# ═════════════════════════════════════════════════════════════════════════════
#
# Прикрепи этот скрипт к Sprite2D внутри Whirlpool
# Создаёт эффект вращающейся воды
#
# ═════════════════════════════════════════════════════════════════════════════

## Скорость вращения визуального эффекта (градусов/сек)
@export var rotation_speed: float = 90.0

## Пульсация масштаба (для эффекта "дыхания" водоворота)
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 2.0
@export var pulse_amount: float = 0.1  # 0.1 = ±10% размера

var time_elapsed: float = 0.0


func _ready() -> void:
	# Устанавливаем начальный цвет (голубоватый полупрозрачный)
	modulate = Color(0.6, 0.8, 1.0, 0.7)


func _process(delta: float) -> void:
	time_elapsed += delta
	
	# Вращение
	rotation += deg_to_rad(rotation_speed) * delta
	
	# Пульсация размера
	if pulse_enabled:
		var pulse := 1.0 + sin(time_elapsed * pulse_speed) * pulse_amount
		scale = Vector2.ONE * pulse


# ═════════════════════════════════════════════════════════════════════════════
#  АЛЬТЕРНАТИВА: Процедурная генерация водоворота
# ═════════════════════════════════════════════════════════════════════════════
# Если у тебя нет спрайта водоворота, можно нарисовать его процедурно:

func _draw() -> void:
	var num_spirals := 8
	var max_radius := 80.0
	
	for i in range(num_spirals):
		var points := PackedVector2Array()
		var angle_offset := (TAU / num_spirals) * i
		
		for j in range(30):
			var t := float(j) / 29.0
			var angle := t * TAU * 2 + angle_offset  # 2 полных оборота
			var radius := t * max_radius
			
			var point := Vector2.RIGHT.rotated(angle) * radius
			points.append(point)
		
		# Рисуем спираль
		#var color := Color(0.3, 0.6, 1.0, 0.5 - t * 0.3)
		#for k in range(points.size() - 1):
			#draw_line(points[k], points[k + 1], color, 3.0)
