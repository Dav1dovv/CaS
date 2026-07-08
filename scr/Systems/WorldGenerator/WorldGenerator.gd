@tool
extends Node2D
class_name WorldGenerator

# ═══════════════════════════════════════════════════════════════════════════════
#  WorldGenerator — спавнит объекты внутри формы (Polygon2D)
#  Сид берётся из GameManager и сохраняется в файл →
#  одинаковый сид = одинаковые объекты при каждой загрузке.
#
#  ИЗМЕНЕНИЯ В ЭТОЙ ВЕРСИИ:
#   • debug_logging — весь print() спрятан за флаг, чтобы не спамить релизную консоль.
#   • _pick_item(): веса больше не пересчитываются с нуля на каждую точку спавна —
#     базовые веса и индекс item->позиция кэшируются один раз в _cache_weights().
#   • Заражение (corruption) больше не хранится отдельно от Global.corruption —
#     если задан biome_key, WorldGenerator читает/пишет уровень заражения
#     напрямую в Global, а не держит собственную копию, которая может разойтись.
#     Если biome_key пуст — работает как раньше, локально (обратная совместимость).
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────
#  Основные параметры
# ─────────────────────────────────────────
@export var generation_items: Array[Generation]
@export var zones: Array[GenerationZone]
@export_range(0.0, 1.0) var object_spawn_chance: float = 0.4
@export var location_id: String = "default_location"
@export var generate_on_start: bool = true

## Ключ биома в Global.corruption ("Forest", "Desert", "Thundra", "Deep").
## Если пусто — заражение считается локальным для этой локации (старое поведение).
@export var biome_key: String = ""

## Уровень заражения этой локации (0–3). Если biome_key задан — служит только
## начальным значением для превью в редакторе, в рантайме перезаписывается из Global.
@export_range(0, 3, 1) var corruption_level: int = 0

@export var debug_logging: bool = false

# ─────────────────────────────────────────
#  Форма области генерации
# ─────────────────────────────────────────
@export_group("Spawn Shape")

## Polygon2D нода — задаёт форму локации.
## Добавь Polygon2D как дочернюю ноду и назначь сюда.
## Рисуй и двигай точки мышью прямо в редакторе.
@export var spawn_shape: Polygon2D:
	set(value):
		spawn_shape = value
		queue_redraw()

# ─────────────────────────────────────────
#  Расстояния и кластеры
# ─────────────────────────────────────────
@export_group("Spacing")
@export var min_distance: float = 50.0
@export var max_cluster_size: int = 5
@export var cluster_radius: float = 100.0

# ─────────────────────────────────────────
#  Шум
# ─────────────────────────────────────────
@export_group("Noise")
@export var noise_scale: float = 0.005
@export var noise_octaves: int = 3

# ─────────────────────────────────────────
#  Сетка (только в редакторе)
# ─────────────────────────────────────────
@export_group("Debug Grid")
@export var show_grid: bool = false:
	set(value):
		show_grid = value
		queue_redraw()
@export var grid_cell_size: float = 50.0:
	set(value):
		grid_cell_size = max(1.0, value)
		queue_redraw()
@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.15):
	set(value):
		grid_color = value
		queue_redraw()

# ─────────────────────────────────────────
#  Специальные структуры
# ─────────────────────────────────────────
@export_group("Special Structures")
@export var special_structures: Array[SpecialStructure] = []
@export var max_structure_attempts: int = 100

# ─────────────────────────────────────────
#  Внутреннее состояние
# ─────────────────────────────────────────
var _noise: FastNoiseLite
var _rng: RandomNumberGenerator  # изолированный — не трогает глобальный seed()
var _location_seed: int
var _placed_structures: Array[Dictionary] = []
var _structure_type_counts: Dictionary = {}
var _game_manager: Node
var _world_polygon: PackedVector2Array = []

# Кэш весов для _pick_item(): считается один раз в _cache_weights(),
# вместо пересчёта на каждую точку спавна.
var _base_weights: Array[float] = []
var _item_index: Dictionary = {}          # Generation -> int (индекс в generation_items)
var _zone_index_multipliers: Array = []   # [{ "noise_threshold": float, "indices": Array[int], "mult": float }]


# ═══════════════════════════════════════════════════════════════════════════════
#  СТАРТ
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	location_id = location_id + Global.player_name
	_game_manager = get_parent()
	_setup_noise()
	_cache_polygon()
	_cache_weights()
	_sync_corruption_from_global()

	if generate_on_start:
		if _game_manager and _game_manager.has_signal("world_ready"):
			_game_manager.world_ready.connect(_generate, CONNECT_ONE_SHOT)
		else:
			_generate()

func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_octaves = noise_octaves
	_noise.frequency = noise_scale

	# GameManager сохраняет сид в JSON-файл при первой генерации
	# и возвращает тот же сид при следующих загрузках
	if _game_manager and _game_manager.has_method("get_or_create_location_seed"):
		_location_seed = _game_manager.get_or_create_location_seed(location_id)
		_log("[WorldGenerator] Сид '%s': %d" % [location_id, _location_seed])
	else:
		push_warning("[WorldGenerator '%s'] GameManager не найден, случайный сид." % location_id)
		_location_seed = ResourceUID.create_id()

	_noise.seed = _location_seed

	# Изолированный RNG — вся генерация только через него.
	# Глобальный seed() не трогаем, чтобы другие ноды не сбивали нашу последовательность.
	_rng = RandomNumberGenerator.new()
	_rng.seed = _location_seed


func _cache_polygon() -> void:
	_world_polygon = PackedVector2Array()
	if spawn_shape == null or not is_instance_valid(spawn_shape):
		push_warning("[WorldGenerator] spawn_shape не задан — генерация не запустится!")
		return
	for p in spawn_shape.polygon:
		_world_polygon.append(spawn_shape.to_global(p))


## Пересчитывает базовые веса предметов и зональные множители ОДИН РАЗ.
## Раньше это делалось в _pick_item() на каждую точку спавна — на большой
## карте (сотни-тысячи точек) это была самая горячая часть генерации.
func _cache_weights() -> void:
	_base_weights.clear()
	_item_index.clear()
	_zone_index_multipliers.clear()

	for i in generation_items.size():
		var item := generation_items[i]
		_base_weights.append(item.spawn_weight if item else 0.0)
		if item:
			_item_index[item] = i

	for zone in zones:
		var indices: Array[int] = []
		for item in zone.dominant_items:
			if _item_index.has(item):
				indices.append(_item_index[item])
		_zone_index_multipliers.append({
			"noise_threshold": zone.noise_threshold,
			"indices": indices,
			"mult": zone.spawn_weight_multiplier,
		})


## Синхронизирует corruption_level с Global.corruption[biome_key], если задан.
## Единственный источник истины — Global.corruption; локация лишь читает/пишет туда.
func _sync_corruption_from_global() -> void:
	if biome_key.is_empty():
		return
	if not ("corruption" in Global) or not Global.corruption.has(biome_key):
		return
	var pct: float = Global.corruption[biome_key]  # 0..100
	corruption_level = int(clamp(round(pct / 100.0 * 3.0), 0, 3))


# ═══════════════════════════════════════════════════════════════════════════════
#  ГЕНЕРАЦИЯ
# ═══════════════════════════════════════════════════════════════════════════════

func _generate() -> void:
	if Engine.is_editor_hint():
		return
	if _world_polygon.is_empty():
		return

	_placed_structures.clear()
	_structure_type_counts.clear()

	_generate_area(_polygon_bounds())
	await get_tree().physics_frame


func _generate_area(bounds: Rect2) -> void:
	_generate_special_structures(bounds)

	var spawned_positions: Array[Vector2] = []

	for pos in _poisson_points(bounds):
		if not Geometry2D.is_point_in_polygon(pos, _world_polygon): continue
		if _in_structure_zone(pos): continue
		if _too_close_to_any(pos, spawned_positions): continue

		var cluster_size := _rng.randi_range(1, max_cluster_size) if _rng.randf() < object_spawn_chance else 1
		for cluster_pos in _cluster_points(pos, cluster_size, spawned_positions):
			if not Geometry2D.is_point_in_polygon(cluster_pos, _world_polygon): continue
			if _in_structure_zone(cluster_pos): continue
			_try_spawn(cluster_pos, spawned_positions)


func _try_spawn(pos: Vector2, spawned_positions: Array[Vector2]) -> void:
	if _is_harvested(pos):
		return
	var item := _pick_item((_noise.get_noise_2d(pos.x, pos.y) + 1.0) * 0.5)
	if not item:
		return
	var scene := _pick_scene(item)
	if not scene:
		return
	var obj := scene.instantiate()
	obj.global_position = pos
	_apply_transform(obj, item)
	call_deferred("add_child", obj)
	spawned_positions.append(pos)


func _apply_transform(obj: Node, item: Generation) -> void:
	if not item.random_scales.is_empty():
		obj.scale = item.random_scales.values()[_rng.randi() % item.random_scales.size()]
	if item.random_rotation_degress > 0:
		obj.rotation_degrees = _rng.randf_range(-item.random_rotation_degress, item.random_rotation_degress)


# ─── Специальные структуры ────────────────────────────────────────────────────

func _generate_special_structures(bounds: Rect2) -> void:
	if special_structures.is_empty():
		return

	var sorted := special_structures.duplicate()
	sorted.sort_custom(func(a, b): return a.spawn_priority > b.spawn_priority)

	for structure in sorted:
		if not structure.generation_item or _rng.randf() > structure.spawn_chance:
			continue

		var placed := 0
		for _attempt in range(max_structure_attempts):
			if placed >= structure.max_instances:
				break
			var pos := Vector2(
				bounds.position.x + _rng.randf() * bounds.size.x,
				bounds.position.y + _rng.randf() * bounds.size.y
			)
			if not Geometry2D.is_point_in_polygon(pos, _world_polygon): continue
			if not _can_place_structure(structure, pos): continue
			var scene := _pick_scene(structure.generation_item)
			if not scene: continue
			var obj := scene.instantiate()
			obj.global_position = pos
			_apply_transform(obj, structure.generation_item)
			call_deferred("add_child", obj)
			_placed_structures.append({ "position": pos, "structure": structure, "instance": obj })
			_structure_type_counts[structure.structure_type] = \
				_structure_type_counts.get(structure.structure_type, 0) + 1
			placed += 1


## Число структур на локацию обычно небольшое (единицы-десятки), поэтому линейный
## перебор тут не является узким местом — но считаем через distance_squared_to,
## чтобы не тратиться на sqrt на каждое сравнение.
func _can_place_structure(structure: SpecialStructure, pos: Vector2) -> bool:
	var any_sq := structure.min_distance_between_any * structure.min_distance_between_any
	var same_sq := structure.min_distance_between_same_type * structure.min_distance_between_same_type
	for placed in _placed_structures:
		var d_sq: float = pos.distance_squared_to(placed["position"])
		if d_sq < any_sq: return false
		if placed["structure"].structure_type == structure.structure_type and d_sq < same_sq:
			return false
	return true


func _in_structure_zone(pos: Vector2) -> bool:
	for placed in _placed_structures:
		var excl: float = placed["structure"].exclusion_radius
		if pos.distance_squared_to(placed["position"]) < excl * excl:
			return true
	return false


# ═══════════════════════════════════════════════════════════════════════════════
#  POISSON DISK SAMPLING
# ═══════════════════════════════════════════════════════════════════════════════

func _poisson_points(bounds: Rect2) -> Array:
	var cell := min_distance / sqrt(2.0)
	var cols := int(bounds.size.x / cell) + 1
	var rows := int(bounds.size.y / cell) + 1
	var grid := []; grid.resize(cols * rows)
	var points: Array[Vector2] = []
	var active: Array[Vector2] = []

	var first := bounds.position + bounds.size * Vector2(_rng.randf(), _rng.randf())
	points.append(first); active.append(first)
	_grid_set(grid, cols, cell, bounds, first)

	while not active.is_empty():
		var idx  := _rng.randi() % active.size()
		var base := active[idx]
		var found := false
		for _k in 30:
			var angle := _rng.randf() * TAU
			var pt    := base + Vector2(cos(angle), sin(angle)) * _rng.randf_range(min_distance, min_distance * 2.0)
			if bounds.has_point(pt) and _grid_valid(grid, cols, rows, cell, bounds, pt):
				points.append(pt); active.append(pt)
				_grid_set(grid, cols, cell, bounds, pt)
				found = true; break
		if not found:
			active.remove_at(idx)
	return points


func _grid_set(grid: Array, cols: int, cell: float, bounds: Rect2, pt: Vector2) -> void:
	var gx := int((pt.x - bounds.position.x) / cell)
	var gy := int((pt.y - bounds.position.y) / cell)
	if gx >= 0 and gx < cols and gy >= 0 and gy * cols + gx < grid.size():
		grid[gy * cols + gx] = pt


func _grid_valid(grid: Array, cols: int, rows: int, cell: float, bounds: Rect2, pt: Vector2) -> bool:
	var gx := int((pt.x - bounds.position.x) / cell)
	var gy := int((pt.y - bounds.position.y) / cell)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var nx := gx + dx; var ny := gy + dy
			if nx >= 0 and nx < cols and ny >= 0 and ny < rows:
				var nb = grid[ny * cols + nx]
				if nb != null and pt.distance_to(nb) < min_distance:
					return false
	return true


func _cluster_points(center: Vector2, size: int, existing: Array[Vector2]) -> Array:
	var result: Array[Vector2] = [center]
	for _i in size - 1:
		var placed := false
		for _attempt in 10:
			var angle := _rng.randf() * TAU
			var pt    := center + Vector2(cos(angle), sin(angle)) * _rng.randf_range(0.0, cluster_radius)
			if not _too_close_to_any(pt, existing) and not _too_close_to_any(pt, result):
				result.append(pt); placed = true; break
		if not placed: break
	return result


# ═══════════════════════════════════════════════════════════════════════════════
#  ВЫБОР ОБЪЕКТА
# ═══════════════════════════════════════════════════════════════════════════════

## Больше не пересчитывает веса с нуля — использует кэш из _cache_weights().
## Зональные множители применяются поверх копии базовых весов (копия дешёвая:
## это один Array[float] размера generation_items, а не N find() + N сумм).
func _pick_item(noise_val: float) -> Generation:
	if generation_items.is_empty(): return null

	var weights := _base_weights.duplicate()
	for zone_data in _zone_index_multipliers:
		if noise_val >= zone_data["noise_threshold"]:
			for i in zone_data["indices"]:
				weights[i] *= zone_data["mult"]

	var total := 0.0
	for w in weights: total += w
	if total == 0.0: return null

	var roll := _rng.randf() * total
	var acc  := 0.0
	for i in generation_items.size():
		acc += weights[i]
		if roll <= acc: return generation_items[i]
	return generation_items[-1]


func _pick_scene(item: Generation) -> PackedScene:
	if item.Generation_random_versions.is_empty():
		return item.Generation_scene
	var pool := [item.Generation_scene] + item.Generation_random_versions
	return pool[_rng.randi() % pool.size()]


# ═══════════════════════════════════════════════════════════════════════════════
#  ВСПОМОГАТЕЛЬНЫЕ
# ═══════════════════════════════════════════════════════════════════════════════

func _polygon_bounds() -> Rect2:
	var r := Rect2(_world_polygon[0], Vector2.ZERO)
	for p in _world_polygon:
		r = r.expand(p)
	return r

func _too_close_to_any(pos: Vector2, others: Array) -> bool:
	var min_sq := min_distance * min_distance
	for other in others:
		if pos.distance_squared_to(other) < min_sq: return true
	return false

func _is_harvested(pos: Vector2) -> bool:
	if _game_manager and _game_manager.has_method("is_harvested"):
		var scene_path := get_tree().current_scene.scene_file_path
		return _game_manager.is_harvested(scene_path, pos)
	return false

func _log(msg: String) -> void:
	if debug_logging:
		print(msg)


# ═══════════════════════════════════════════════════════════════════════════════
#  ПУБЛИЧНЫЙ API
# ═══════════════════════════════════════════════════════════════════════════════

func get_placed_structures() -> Array[Dictionary]:
	return _placed_structures

func get_structures_of_type(type: SpecialStructure.StructureType) -> Array[Dictionary]:
	return _placed_structures.filter(func(p): return p["structure"].structure_type == type)

func get_nearest_structure(pos: Vector2, type: int = -1) -> Dictionary:
	var best := {}
	var best_dist := INF
	for placed in _placed_structures:
		if type != -1 and placed["structure"].structure_type != type: continue
		var d := pos.distance_to(placed["position"])
		if d < best_dist:
			best_dist = d; best = placed
	return best


## Изменить заражение на delta (положительное = больше заражения).
## Возвращает новый уровень (0-3).
## Если biome_key задан — пишет изменение НАПРЯМУЮ в Global.corruption (единый
## источник истины), а не в локальное поле. Если biome_key пуст — старое
## локальное поведение сохраняется для обратной совместимости.
func modify_corruption(delta: int) -> int:
	if not biome_key.is_empty() and ("corruption" in Global) and Global.corruption.has(biome_key):
		var pct: float = Global.corruption[biome_key]
		pct = clamp(pct + delta * (100.0 / 3.0), 0.0, 100.0)
		Global.corruption[biome_key] = pct
		corruption_level = int(clamp(round(pct / 100.0 * 3.0), 0, 3))
	else:
		corruption_level = clamp(corruption_level + delta, 0, 3)
	return corruption_level


# ═══════════════════════════════════════════════════════════════════════════════
#  РЕДАКТОР — превью формы и сетки
# ═══════════════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if spawn_shape == null or not is_instance_valid(spawn_shape) or spawn_shape.polygon.size() < 3:
		return

	var local_pts := PackedVector2Array()
	for p in spawn_shape.polygon:
		local_pts.append(to_local(spawn_shape.to_global(p)))

	draw_colored_polygon(local_pts, Color(0.0, 1.0, 0.3, 0.10))
	for i in local_pts.size():
		draw_line(local_pts[i], local_pts[(i + 1) % local_pts.size()],
				  Color(0.0, 1.0, 0.3, 0.8), 2.0)

	if not show_grid:
		return

	var min_pt := local_pts[0]
	var max_pt := local_pts[0]
	for p in local_pts:
		min_pt = Vector2(min(min_pt.x, p.x), min(min_pt.y, p.y))
		max_pt = Vector2(max(max_pt.x, p.x), max(max_pt.y, p.y))

	var start_x: float = floor(min_pt.x / grid_cell_size) * grid_cell_size
	var start_y: float = floor(min_pt.y / grid_cell_size) * grid_cell_size

	var x: float = start_x
	while x <= max_pt.x + grid_cell_size:
		draw_line(Vector2(x, min_pt.y - grid_cell_size), Vector2(x, max_pt.y + grid_cell_size), grid_color, 1.0)
		x += grid_cell_size

	var y: float = start_y
	while y <= max_pt.y + grid_cell_size:
		draw_line(Vector2(min_pt.x - grid_cell_size, y), Vector2(max_pt.x + grid_cell_size, y), grid_color, 1.0)
		y += grid_cell_size
