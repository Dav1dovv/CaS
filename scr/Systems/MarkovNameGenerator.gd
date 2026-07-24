extends Node
class_name MarkovNameGenerator

# ============================================================
# Генератор имён на основе цепей Маркова
# Улучшения относительно старой версии:
#  - имена не повторяются, пока не закончится "пул" вариантов
#  - гибридная цепь (порядок 3 с откатом на порядок 2) даёт
#    более "настоящие" на слух имена и меньше мусора
#  - веса переходов считаются по частоте, а не только списком
#  - RNG создаётся один раз, а не на каждый вызов
#  - можно генерировать имя по конкретной культуре (или любой)
# ============================================================

enum Culture { ANY, EUROPEAN, SLAVIC, ARMENIAN }

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# markov_order_hi — основной (более "умный") порядок цепи
# markov_order_lo — запасной порядок, если для hi-ключа нет данных
var markov_order_hi: int = 3
var markov_order_lo: int = 2

var min_len: int = 3
var max_len: int = 11

# Цепи хранятся отдельно для каждой культуры и для каждого порядка:
# _chains_hi[culture][key] = { "next_char": count, ... }
var _chains_hi: Dictionary = {}
var _chains_lo: Dictionary = {}
var _starts_hi: Dictionary = {}  # culture -> Array
var _starts_lo: Dictionary = {}  # culture -> Array

var _built: bool = false

# Имена, которые уже были выданы в текущем "цикле" —
# используются чтобы не повторяться
var _used_names: Dictionary = {}

const TRAINING_DATA = {
	Culture.EUROPEAN: [
		"Aldric", "Theron", "Gareth", "Edwyn", "Dorian", "Brennan", "Percival",
		"Aldwin", "Corvyn", "Tristan", "Roland", "Godwin", "Edwin", "Oswin",
		"Leofric", "Mira", "Elara", "Seraphine", "Lyra", "Vesper", "Isolde",
		"Elowen", "Rowena", "Nessa", "Calla", "Elspeth", "Moira", "Fiona",
		"Brenna", "Cerys", "Gwyneth", "Maeve", "Rhiannon", "Seren", "Niamh",
		"Alaric", "Cedric", "Wendell", "Osric", "Fenwick", "Ambrose", "Barnaby",
		"Thaddeus", "Cormac", "Emrys", "Peregrine", "Wulfric", "Ysolde",
	],
	Culture.SLAVIC: [
		"DobroMir", "Radoslav", "Vlastimir", "Borislav", "Miroslav", "Tikhomir",
		"Velibor", "Svetozar", "Stanmir", "Gadoslav", "Yaromir", "Dobroslav",
		"Zbyshek", "Bratislav", "Vseslav", "Lyubomir", "Rostislav", "Casimir",
		"Vratislav", "Zdenko", "Chestmir", "Bogdan", "Vladan", "Dragomir",
	],
	Culture.ARMENIAN: [
		"Vardan", "Davit", "Ashot", "Hayk", "Areg", "Bagrat", "Karen", "Arshavir",
		"Harut", "Garik", "Surik", "Sasun", "Levon", "Mihran", "Vahagn", "Vazgen",
		"Tigran", "Gagik", "Aram", "Norayr", "Artak", "Vachagan", "Smbat",
		"Ruben", "Grachya", "Andranik", "Vahan", "Nerses",
	],
}

func _ready() -> void:
	rng.randomize()

# ------------------------------------------------------------
# Построение цепей (вызывается лениво при первом обращении)
# ------------------------------------------------------------
func _build_chains() -> void:
	_chains_hi.clear()
	_chains_lo.clear()
	_starts_hi.clear()
	_starts_lo.clear()

	for culture in [Culture.ANY, Culture.EUROPEAN, Culture.SLAVIC, Culture.ARMENIAN]:
		_chains_hi[culture] = {}
		_chains_lo[culture] = {}
		_starts_hi[culture] = []
		_starts_lo[culture] = []

	for culture in TRAINING_DATA.keys():
		for raw_name in TRAINING_DATA[culture]:
			var lower = raw_name.to_lower()
			# Обучаем цепь конкретной культуры...
			_train_on_name(lower, markov_order_hi, _chains_hi[culture], _starts_hi[culture])
			_train_on_name(lower, markov_order_lo, _chains_lo[culture], _starts_lo[culture])
			# ...и заодно общую цепь ANY (смесь всех культур)
			_train_on_name(lower, markov_order_hi, _chains_hi[Culture.ANY], _starts_hi[Culture.ANY])
			_train_on_name(lower, markov_order_lo, _chains_lo[Culture.ANY], _starts_lo[Culture.ANY])

	_built = true

func _train_on_name(word: String, order: int, chain: Dictionary, starts: Array) -> void:
	if word.length() <= order:
		return

	var first_chars = word.substr(0, order)
	starts.append(first_chars)

	for i in range(word.length() - order):
		var key = word.substr(i, order)
		var next_char = word[i + order]
		_add_weighted(chain, key, next_char)

	var end_key = word.substr(word.length() - order, order)
	_add_weighted(chain, end_key, "$")

func _add_weighted(chain: Dictionary, key: String, next_char: String) -> void:
	if not chain.has(key):
		chain[key] = {}
	if not chain[key].has(next_char):
		chain[key][next_char] = 0
	chain[key][next_char] += 1

# Выбор следующего символа с учётом веса (частоты в обучающих данных)
func _weighted_pick(options: Dictionary) -> String:
	var total: int = 0
	for count in options.values():
		total += count
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for key in options.keys():
		acc += options[key]
		if roll <= acc:
			return key
	return options.keys()[0]

# ------------------------------------------------------------
# Основная генерация одного имени (без проверки повторов)
# ------------------------------------------------------------
func _generate_raw(culture: int = Culture.ANY) -> String:
	if not _built:
		_build_chains()

	var chain_hi: Dictionary = _chains_hi.get(culture, _chains_hi[Culture.ANY])
	var chain_lo: Dictionary = _chains_lo.get(culture, _chains_lo[Culture.ANY])
	var starts_pool = _starts_hi.get(culture, []) if not _starts_hi.get(culture, []).is_empty() else _starts_lo.get(culture, [])
	if starts_pool.is_empty():
		return "Aldric"

	var result: String = starts_pool[rng.randi_range(0, starts_pool.size() - 1)]

	for _i in range(max_len + markov_order_hi):
		if result.length() >= max_len:
			break

		var key_hi = result.substr(result.length() - markov_order_hi, markov_order_hi) \
			if result.length() >= markov_order_hi else ""
		var key_lo = result.substr(result.length() - markov_order_lo, markov_order_lo) \
			if result.length() >= markov_order_lo else ""

		var options: Dictionary = {}
		if chain_hi.has(key_hi):
			options = chain_hi[key_hi]
		elif chain_lo.has(key_lo):
			options = chain_lo[key_lo]
		else:
			break

		var next_char = _weighted_pick(options)
		if next_char == "$":
			break
		result += next_char

	return result.capitalize()

# ------------------------------------------------------------
# Публичный API
# ------------------------------------------------------------

# Генерирует одно уникальное имя (не повторяется, пока не исчерпан пул).
# culture: Culture.ANY / EUROPEAN / SLAVIC / ARMENIAN
func generate_name(culture: int = Culture.ANY) -> String:
	if not _built:
		_build_chains()

	for _attempt in range(40):
		var candidate = _generate_raw(culture)
		if candidate.length() < min_len or candidate.length() > max_len:
			continue
		if _used_names.has(candidate):
			continue
		_used_names[candidate] = true
		return candidate

	# Если за 40 попыток не нашли новое имя (пул почти исчерпан) —
	# сбрасываем историю и пробуем ещё раз, чтобы не зависнуть.
	if not _used_names.is_empty():
		_used_names.clear()
		return generate_name(culture)

	return "Aldric"

# Генерирует сразу список из N уникальных имён
func generate_names(count: int, culture: int = Culture.ANY) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(generate_name(culture))
	return out

# Сбросить историю выданных имён (например, при старте новой игры)
func reset_used_names() -> void:
	_used_names.clear()

# Можно вручную задать конкретный сид для воспроизводимой генерации
func set_seed(value: int) -> void:
	rng.seed = value
