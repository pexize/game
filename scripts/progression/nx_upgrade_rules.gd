class_name NxUpgradeRules
extends RefCounted
## Carrega e valida as definições de melhorias (GDD §8, ECONOMY §6).
##
## Uma melhoria tem níveis repetíveis, custo crescente e um efeito sobre um
## componente ou sobre todos ("all"):
##   output_multiplier (categoria production): multiplica a produção em
##       (1 + per_level × nível);
##   input_multiplier  (categoria efficiency): reduz o consumo em
##       (1 − per_level × nível), nunca abaixo de 10%.
## A automação não é uma melhoria: é um recurso liberado por descoberta
## (ver NxAutomation).
##
## Verificado na carga: referências, limites numéricos, ciclos entre
## pré-requisitos e que os recursos do jogo permitem comprar a melhoria
## (os recursos do custo são produzíveis e os `requires_features` são
## concedidos por alguma descoberta).

const MAX_LEVEL_LIMIT := 100
const MAX_GROWTH := 10.0
const MIN_INPUT_FACTOR := 0.1
const EFFECT_CATEGORY := {"output_multiplier": "production", "input_multiplier": "efficiency"}
const KEYS := [
	"id", "name_key", "category", "target", "effect", "cost", "growth",
	"max_level", "requires_features", "prerequisites", "_file",
]


static func build(defs: NxDefinitions, raw_list: Array) -> void:
	for raw: Variant in raw_list:
		if not (raw is Dictionary):
			defs.errors.append("melhoria: entrada não é um objeto")
			continue
		var id := str(raw.get("id", ""))
		var where := "melhoria '%s'" % id
		for key: Variant in raw:
			if not KEYS.has(key):
				defs.errors.append("%s: campo desconhecido '%s'" % [where, key])
		if id.is_empty():
			defs.errors.append("%s: falta 'id'" % where)
			continue
		if defs.upgrades.has(id):
			defs.errors.append("%s: id duplicado" % where)
			continue
		if raw.has("_file") and raw["_file"] != id:
			defs.errors.append("%s: o id difere do nome do arquivo '%s'" % [where, raw["_file"]])
		defs.upgrades[id] = _normalize(defs, raw, id, where)
	_check_prerequisites(defs)
	_check_purchasable(defs)


static func _normalize(defs: NxDefinitions, raw: Dictionary, id: String, where: String) -> Dictionary:
	var upgrade := {
		"id": id, "name_key": str(raw.get("name_key", "")),
		"category": str(raw.get("category", "")), "target": str(raw.get("target", "")),
		"effect_type": "", "per_level": 0.0, "cost": {}, "growth": 1.0,
		"max_level": 1, "requires_features": [], "prerequisites": [],
	}

	# efeito
	var effect: Variant = raw.get("effect")
	if not (effect is Dictionary):
		defs.errors.append("%s: falta 'effect'" % where)
	else:
		var effect_type := str(effect.get("type", ""))
		var per_level: Variant = effect.get("per_level")
		if not EFFECT_CATEGORY.has(effect_type):
			defs.errors.append("%s: efeito desconhecido '%s'" % [where, effect_type])
		elif upgrade["category"] != EFFECT_CATEGORY[effect_type]:
			defs.errors.append("%s: o efeito '%s' pertence à categoria '%s'" % [where, effect_type, EFFECT_CATEGORY[effect_type]])
		if not ((per_level is float or per_level is int) and per_level > 0):
			defs.errors.append("%s: 'effect.per_level' deve ser um número positivo" % where)
		else:
			upgrade["per_level"] = float(per_level)
		upgrade["effect_type"] = effect_type

	# alvo
	var target: String = upgrade["target"]
	if target != "all" and not defs.components.has(target):
		defs.errors.append("%s: alvo desconhecido '%s'" % [where, target])
	elif upgrade["effect_type"] == "input_multiplier":
		var targets: Array = defs.components.keys() if target == "all" else [target]
		for cid: String in targets:
			if not defs.components[cid]["inputs"].is_empty():
				continue
			if target != "all":
				defs.errors.append("%s: '%s' não consome nada, então a melhoria não teria efeito" % [where, target])
	elif upgrade["effect_type"] == "output_multiplier" and target != "all":
		if defs.components[target]["outputs"].is_empty():
			defs.errors.append("%s: '%s' não produz nada, então a melhoria não teria efeito" % [where, target])

	# níveis e curva de custo
	var max_level: Variant = raw.get("max_level")
	if (max_level is float or max_level is int) and float(max_level) == floorf(float(max_level)) and max_level >= 1 and max_level <= MAX_LEVEL_LIMIT:
		upgrade["max_level"] = int(max_level)
	else:
		defs.errors.append("%s: 'max_level' deve ser um inteiro entre 1 e %d" % [where, MAX_LEVEL_LIMIT])
	var growth: Variant = raw.get("growth")
	if (growth is float or growth is int) and growth >= 1.0 and growth <= MAX_GROWTH:
		upgrade["growth"] = float(growth)
	else:
		defs.errors.append("%s: 'growth' deve estar entre 1 e %s" % [where, MAX_GROWTH])
	if upgrade["effect_type"] == "input_multiplier" and upgrade["per_level"] * upgrade["max_level"] > 1.0 - MIN_INPUT_FACTOR:
		defs.errors.append("%s: no nível máximo o consumo cairia abaixo de %d%%" % [where, roundi(MIN_INPUT_FACTOR * 100)])

	var cost: Variant = raw.get("cost")
	if not (cost is Dictionary) or cost.is_empty():
		defs.errors.append("%s: 'cost' deve ser um objeto não vazio" % where)
	else:
		for rid: String in cost:
			if not defs.resources.has(rid):
				defs.errors.append("%s: custo usa recurso desconhecido '%s'" % [where, rid])
			elif (cost[rid] is float or cost[rid] is int) and cost[rid] > 0:
				upgrade["cost"][rid] = roundi(float(cost[rid]) * NxDefinitions.MILLI)
			else:
				defs.errors.append("%s: 'cost.%s' deve ser um número positivo" % [where, rid])

	for key in ["requires_features", "prerequisites"]:
		var values: Variant = raw.get(key, [])
		if values is Array:
			for value: Variant in values:
				upgrade[key].append(str(value))
		else:
			defs.errors.append("%s: '%s' deve ser uma lista" % [where, key])
	return upgrade


static func _check_prerequisites(defs: NxDefinitions) -> void:
	for id: String in defs.upgrades:
		for prereq: String in defs.upgrades[id]["prerequisites"]:
			if not defs.upgrades.has(prereq):
				defs.errors.append("melhoria '%s': pré-requisito desconhecido '%s'" % [id, prereq])
	# Ciclos: DFS com cores (0 = novo, 1 = em andamento, 2 = terminado).
	var color := {}
	for id: String in defs.upgrades:
		if _has_cycle(defs, id, color):
			defs.errors.append("melhorias com pré-requisitos circulares (a partir de '%s')" % id)
			return


static func _has_cycle(defs: NxDefinitions, id: String, color: Dictionary) -> bool:
	if color.get(id, 0) == 2:
		return false
	if color.get(id, 0) == 1:
		return true
	color[id] = 1
	for prereq: String in defs.upgrades[id]["prerequisites"]:
		if defs.upgrades.has(prereq) and _has_cycle(defs, prereq, color):
			return true
	color[id] = 2
	return false


## A melhoria precisa ser comprável em algum momento do jogo: os recursos
## do custo são produzíveis por algum componente que o jogo libera, e cada
## recurso de jogo exigido é concedido por alguma descoberta.
static func _check_purchasable(defs: NxDefinitions) -> void:
	if not defs.balance.has("start_unlocked") or not defs.components.has(defs.balance.get("core_component", "")):
		return
	var granted_features := {}
	var producible := {}
	var available: Array = defs.balance["start_unlocked"].duplicate()
	available.append(defs.balance["core_component"])
	for discovery: Dictionary in defs.discoveries.values():
		for reward: Dictionary in discovery["rewards"]:
			if reward["type"] == "unlock_feature":
				granted_features[reward["feature"]] = true
			elif reward["type"] == "unlock_component":
				available.append(reward["component"])
	for cid: String in available:
		if defs.components.has(cid):
			for rid: String in defs.components[cid]["outputs"]:
				producible[rid] = true

	for id: String in defs.upgrades:
		var upgrade: Dictionary = defs.upgrades[id]
		for feature: String in upgrade["requires_features"]:
			if not granted_features.has(feature):
				defs.errors.append("melhoria '%s': o recurso '%s' nunca é liberado por uma descoberta (inalcançável)" % [id, feature])
		for rid: String in upgrade["cost"]:
			if int(defs.balance["start_resources"].get(rid, 0)) == 0 and not producible.has(rid):
				defs.errors.append("melhoria '%s': nenhum componente liberado produz '%s' (inalcançável)" % [id, rid])
