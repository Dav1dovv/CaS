extends Node
class_name  MarkovNameGenerator

# Добавь в начало файла:
var markov_chain: Dictionary = {}
var markov_order: int = 2  # Порядок цепи — сколько букв анализируем за раз

# Обучающие данные — реальные европейские и славянские имена
const TRAINING_NAMES = [
	# Европейские
	"Aldric", "Theron", "Gareth", "Edwyn", "Dorian", "Brennan", "Percival",
	"Aldwin", "Corvyn", "Tristan", "Roland", "Godwin", "Edwin", "Oswin",
	"Leofric", "Mira", "Elara", "Seraphine", "Lyra", "Vesper", "Isolde",
	"Elowen", "Rowena", "Nessa", "Calla", "Elspeth", "Moira", "Fiona",
	"Brenna", "Cerys", "Gwyneth", "Maeve", "Rhiannon", "Seren", "Niamh",
	# Славянские
	"DobroMir", "Radoslav", "Vlastimir", "Borislav", "Miroslav", "Tikhomir",
	"Velibor", "Svetozar", "Stanmir", "Gadoslav", "Yaromir", "Dobroslav",
	#Armenian
	"Vardan","Davit","Ashot","Hayk","Areg","Bagrat","Karen","Arshavir","Harut",
	"Garik","Surik","Sasun","Levon","Mihran","Vahagn","Vazgen","Tigran"
]

func _build_markov_chain() -> void:
	markov_chain.clear()
	for name in TRAINING_NAMES:
		var lower = name.to_lower()
		# Стартовые слоги
		var start_key = "^"
		var first_chars = lower.substr(0, markov_order)
		if not markov_chain.has(start_key):
			markov_chain[start_key] = []
		markov_chain[start_key].append(first_chars)
		# Переходы
		for i in range(len(lower) - markov_order):
			var key = lower.substr(i, markov_order)
			var next_char = lower[i + markov_order]
			if not markov_chain.has(key):
				markov_chain[key] = []
			markov_chain[key].append(next_char)
		# Конец слова
		var end_key = lower.substr(len(lower) - markov_order, markov_order)
		if not markov_chain.has(end_key):
			markov_chain[end_key] = []
		markov_chain[end_key].append("$")

func _generate_random_name() -> String:
	if markov_chain.is_empty():
		_build_markov_chain()
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Пробуем несколько раз — на случай если цепь зашла в тупик
	for _attempt in range(20):
		var result = ""
		# Берём случайный стартовый слог
		var starts = markov_chain.get("^", [])
		if starts.is_empty():
			continue
		result = starts[rng.randi_range(0, starts.size() - 1)]
		
		# Генерируем до 12 символов
		for _i in range(12):
			if len(result) < markov_order:
				break
			var key = result.substr(len(result) - markov_order, markov_order)
			var nexts = markov_chain.get(key, [])
			if nexts.is_empty():
				break
			var next = nexts[rng.randi_range(0, nexts.size() - 1)]
			if next == "$":
				break
			result += next
		
		# Фильтр: имя от 3 до 10 букв
		if len(result) >= 3 and len(result) <= 10:
			return result.capitalize()
	
	# Запасной вариант если все попытки неудачные
	return "Aldric"
