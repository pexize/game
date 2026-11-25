class_name NxStateValidator
extends RefCounted
## Valida o estado de um save contra as definições do jogo, SEM confiar nele.
##
## Roda sobre o dicionário lido do disco, antes de NxGameState.from_dict, para
## que um save adulterado ou truncado nunca derrube o carregamento. Qualquer
## erro significa "save inválido": o gerenciador cai no backup em vez de
## tentar consertar às cegas. Mudanças de conteúdo entre versões do jogo
## (ids removidos ou renomeados) são tratadas por migrações explícitas, não
## por uma limpeza silenciosa aqui.

const REQUIRED_KEYS := [
	"resources", "components", "next_instance_id", "unlocked", "lifetime_produced",
	"time_ms", "discoveries", "condition_progress", "features", "stage",
	"upgrades", "automation",
]
## Maior inteiro que o ponto flutuante guarda sem perda.
const MAX_EXACT := 9007199254740992.0


static func validate_dict(data: Variant, defs: NxDefinitions) -> PackedStringArray:
	var errors := PackedStringArray()
	if not (data is Dictionary):
		errors.append("o estado não é um objeto")
		return errors
	for key in REQUIRED_KEYS:
		if not data.has(key):
			errors.append("falta o campo '%s'" % key)
	if not errors.is_empty():
		return errors

	_resources(data, defs, errors)
	_components(data, defs, errors)
	_unlocked(data, defs, errors)
	_progression(data, defs, errors)
	_upgrades_and_automation(data, defs, errors)
	if not errors.is_empty():
		return errors

	# Estrutura básica correta: agora dá para montar o estado e checar a árvore.
	var state := NxGameState.from_dict(data)
	var cores := state.count_of(defs.balance["core_component"])
	if cores != 1:
		errors.append("deve haver exatamente um Core (há %d)" % cores)
	errors.append_array(NxNetwork.validate(state, defs))
	return errors


static func validate_state(state: NxGameState, defs: NxDefinitions) -> PackedStringArray:
	return validate_dict(state.to_dict(), defs)


# --- partes ------------------------------------------------------------------

static func _resources(data: Dictionary, defs: NxDefinitions, errors: PackedStringArray) -> void:
	for field in ["resources", "lifetime_produced"]:
		if not (data[field] is Dictionary):
			errors.append("'%s' deve ser um objeto" % field)
			continue
		for rid: Variant in data[field]:
			if not defs.resources.has(rid):
				errors.append("%s: recurso desconhecido '%s'" % [field, rid])
			elif not _whole(data[field][rid], 0):
				errors.append("%s.%s deve ser um inteiro ≥ 0" % [field, rid])
			elif field == "resources":
				var cap := defs.max_storage(rid)
				if cap != NxDefinitions.UNLIMITED and float(data[field][rid]) > cap:
					errors.append("resources.%s passa do armazenamento máximo" % rid)
		for rid in defs.resource_ids:
			if not data[field].has(rid):
				errors.append("%s: falta o recurso '%s'" % [field, rid])
	if not _whole(data["time_ms"], 0):
		errors.append("'time_ms' deve ser um inteiro ≥ 0")


static func _components(data: Dictionary, defs: NxDefinitions, errors: PackedStringArray) -> void:
	if not (data["components"] is Dictionary):
		errors.append("'components' deve ser um objeto")
		return
	var highest := 0
	for key: Variant in data["components"]:
		if not (key is String and key.is_valid_int() and int(key) > 0):
			errors.append("componente com id inválido '%s'" % key)
			continue
		highest = maxi(highest, int(key))
		var inst: Variant = data["components"][key]
		if not (inst is Dictionary):
			errors.append("componente #%s não é um objeto" % key)
			continue
		if not (inst.get("def") is String and defs.components.has(inst["def"])):
			errors.append("componente #%s: definição desconhecida" % key)
		if not (inst.get("enabled") is bool):
			errors.append("componente #%s: 'enabled' deve ser verdadeiro ou falso" % key)
		if not inst.has("parent") or not _whole(inst["parent"], 0):
			errors.append("componente #%s: 'parent' deve ser um inteiro ≥ 0" % key)
	if not _whole(data["next_instance_id"], 1) or int(data["next_instance_id"]) <= highest:
		errors.append("'next_instance_id' deve ser maior que todos os ids de componente")


static func _unlocked(data: Dictionary, defs: NxDefinitions, errors: PackedStringArray) -> void:
	if not (data["unlocked"] is Array):
		errors.append("'unlocked' deve ser uma lista")
		return
	for cid: Variant in data["unlocked"]:
		if not (cid is String and defs.components.has(cid)):
			errors.append("unlocked: componente desconhecido '%s'" % cid)


static func _progression(data: Dictionary, defs: NxDefinitions, errors: PackedStringArray) -> void:
	# recursos de jogo conhecidos = os que alguma descoberta concede
	var known_features := {}
	for discovery: Dictionary in defs.discoveries.values():
		for reward: Dictionary in discovery["rewards"]:
			if reward["type"] == "unlock_feature":
				known_features[reward["feature"]] = true
	if not (data["features"] is Array):
		errors.append("'features' deve ser uma lista")
	else:
		for feature: Variant in data["features"]:
			if not (feature is String and known_features.has(feature)):
				errors.append("features: recurso desconhecido '%s'" % feature)

	if not (data["discoveries"] is Dictionary):
		errors.append("'discoveries' deve ser um objeto")
	else:
		var orders := []
		for did: Variant in data["discoveries"]:
			if not defs.discoveries.has(did):
				errors.append("discoveries: descoberta desconhecida '%s'" % did)
				continue
			var entry: Variant = data["discoveries"][did]
			if not (entry is Dictionary and _whole(entry.get("order"), 1) and _whole(entry.get("time_ms"), 0)):
				errors.append("discoveries.%s: 'order' e 'time_ms' inválidos" % did)
				continue
			orders.append(int(entry["order"]))
			for prereq: String in defs.discoveries[did]["prerequisites"]:
				if not data["discoveries"].has(prereq):
					errors.append("discoveries.%s foi concedida sem o pré-requisito '%s'" % [did, prereq])
		orders.sort()
		for index in range(orders.size()):
			if orders[index] != index + 1:
				errors.append("a ordem das descobertas deve ser 1..N sem repetição")
				break

	if not (data["condition_progress"] is Dictionary):
		errors.append("'condition_progress' deve ser um objeto")
	else:
		for did: Variant in data["condition_progress"]:
			if not defs.discoveries.has(did):
				errors.append("condition_progress: descoberta desconhecida '%s'" % did)
				continue
			if data["discoveries"] is Dictionary and data["discoveries"].has(did):
				errors.append("condition_progress.%s sobrou de uma descoberta já concedida" % did)
			var counters: Variant = data["condition_progress"][did]
			if not (counters is Dictionary):
				errors.append("condition_progress.%s deve ser um objeto" % did)
				continue
			for index: Variant in counters:
				var valid_index: bool = index is String and index.is_valid_int() and int(index) >= 0 \
					and int(index) < defs.discoveries[did]["conditions"].size()
				if not valid_index or defs.discoveries[did]["conditions"][int(index)]["type"] != "sustained":
					errors.append("condition_progress.%s: contador '%s' não corresponde a uma condição sustentada" % [did, index])
				elif not _whole(counters[index], 0):
					errors.append("condition_progress.%s.%s deve ser um inteiro ≥ 0" % [did, index])

	var max_stage := 1
	for discovery: Dictionary in defs.discoveries.values():
		for reward: Dictionary in discovery["rewards"]:
			if reward["type"] == "set_stage":
				max_stage = maxi(max_stage, int(reward["stage"]))
	if not _whole(data["stage"], 1) or int(data["stage"]) > max_stage:
		errors.append("'stage' deve estar entre 1 e %d" % max_stage)


static func _upgrades_and_automation(data: Dictionary, defs: NxDefinitions, errors: PackedStringArray) -> void:
	if not (data["upgrades"] is Dictionary):
		errors.append("'upgrades' deve ser um objeto")
	else:
		for uid: Variant in data["upgrades"]:
			if not defs.upgrades.has(uid):
				errors.append("upgrades: melhoria desconhecida '%s'" % uid)
			elif not _whole(data["upgrades"][uid], 1) or int(data["upgrades"][uid]) > int(defs.upgrades[uid]["max_level"]):
				errors.append("upgrades.%s: nível fora de 1..%d" % [uid, defs.upgrades[uid]["max_level"]])

	var automation: Variant = data["automation"]
	if not (automation is Dictionary and automation.get("enabled") is bool and automation.get("target") is String):
		errors.append("'automation' deve ter 'enabled' (booleano) e 'target' (texto)")
	elif not automation["target"].is_empty() and not defs.upgrades.has(automation["target"]):
		errors.append("automation: melhoria desconhecida '%s'" % automation["target"])


## Inteiro (guardado como int ou float, porque o JSON lê tudo como float) ≥ minimum.
static func _whole(value: Variant, minimum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return number == floorf(number) and number >= minimum and number <= MAX_EXACT
