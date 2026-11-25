class_name NxDiscoveryRules
extends RefCounted
## Carrega e valida as definições de descobertas (GDD §7).
##
## Garantias verificadas na carga, sem precisar jogar:
##  - ids estáveis e únicos; pré-requisitos existem e não formam ciclo
##    (`discovery_order` fica em ordem topológica);
##  - toda condição usa um tipo conhecido, com parâmetros válidos;
##  - ALCANÇABILIDADE: tudo o que uma descoberta exige (componentes e
##    recursos produzidos) já está disponível pelo estado inicial ou pelas
##    recompensas de descobertas que ela tem como pré-requisito, direta ou
##    indiretamente. Assim nenhuma descoberta depende de algo que só ela, ou
##    uma posterior, libera.
##
## Condições (todas de uma descoberta valem juntas):
##   quantitativas: active_component_count, resource_amount
##   estruturais:   active_distinct_types, parent_distinct_children
##   funcionais:    net_rate_positive, all_active_full_efficiency,
##                  sustained (envolve uma condição instantânea e exige que
##                  ela se mantenha por `seconds`)
##   históricas:    lifetime_produced
## Recompensas: unlock_component, unlock_feature, set_stage.

const CONDITION_TYPES := [
	"active_component_count", "active_distinct_types", "parent_distinct_children",
	"resource_amount", "lifetime_produced", "net_rate_positive",
	"all_active_full_efficiency", "sustained",
]
const REWARD_TYPES := ["unlock_component", "unlock_feature", "set_stage"]
const VISIBILITIES := ["normal", "secret"]
const KEYS := [
	"id", "title_key", "hint_key", "prerequisites", "conditions", "rewards",
	"visibility", "_file",
]
const CATEGORY := {
	"active_component_count": "quantitative", "resource_amount": "quantitative",
	"active_distinct_types": "structural", "parent_distinct_children": "structural",
	"net_rate_positive": "functional", "all_active_full_efficiency": "functional",
	"sustained": "functional", "lifetime_produced": "historical",
}


static func build(defs: NxDefinitions, raw_list: Array) -> void:
	for raw: Variant in raw_list:
		if not (raw is Dictionary):
			defs.errors.append("descoberta: entrada não é um objeto")
			continue
		var id := str(raw.get("id", ""))
		var where := "descoberta '%s'" % id
		for key: Variant in raw:
			if not KEYS.has(key):
				defs.errors.append("%s: campo desconhecido '%s'" % [where, key])
		if id.is_empty():
			defs.errors.append("%s: falta 'id'" % where)
			continue
		if defs.discoveries.has(id):
			defs.errors.append("%s: id duplicado" % where)
			continue
		if raw.has("_file") and raw["_file"] != id:
			defs.errors.append("%s: o id difere do nome do arquivo '%s'" % [where, raw["_file"]])

		var visibility := str(raw.get("visibility", "normal"))
		if not VISIBILITIES.has(visibility):
			defs.errors.append("%s: 'visibility' deve ser 'normal' ou 'secret'" % where)
			visibility = "normal"

		var prerequisites := []
		var raw_prereqs: Variant = raw.get("prerequisites", [])
		if raw_prereqs is Array:
			for p: Variant in raw_prereqs:
				prerequisites.append(str(p))
		else:
			defs.errors.append("%s: 'prerequisites' deve ser uma lista" % where)

		var conditions := []
		var raw_conditions: Variant = raw.get("conditions", [])
		if not (raw_conditions is Array) or raw_conditions.is_empty():
			defs.errors.append("%s: 'conditions' deve ser uma lista não vazia" % where)
		else:
			for raw_condition: Variant in raw_conditions:
				var condition := _condition(defs, raw_condition, where, false)
				if not condition.is_empty():
					conditions.append(condition)

		var rewards := []
		var raw_rewards: Variant = raw.get("rewards", [])
		if not (raw_rewards is Array):
			defs.errors.append("%s: 'rewards' deve ser uma lista" % where)
		else:
			for raw_reward: Variant in raw_rewards:
				var reward := _reward(defs, raw_reward, where)
				if not reward.is_empty():
					rewards.append(reward)

		defs.discoveries[id] = {
			"id": id,
			"title_key": str(raw.get("title_key", "")),
			"hint_key": str(raw.get("hint_key", "")),
			"prerequisites": prerequisites,
			"conditions": conditions,
			"rewards": rewards,
			"visibility": visibility,
		}

	_check_prerequisites_and_order(defs)
	_check_reachability(defs)


# --- condições e recompensas ------------------------------------------------

static func _condition(defs: NxDefinitions, raw: Variant, where: String, nested: bool) -> Dictionary:
	if not (raw is Dictionary):
		defs.errors.append("%s: condição não é um objeto" % where)
		return {}
	var type := str(raw.get("type", ""))
	if not CONDITION_TYPES.has(type):
		defs.errors.append("%s: tipo de condição desconhecido '%s'" % [where, type])
		return {}
	var here := "%s, condição '%s'" % [where, type]
	var out := {"type": type}
	match type:
		"active_component_count":
			if raw.has("component"):
				out["component"] = _component_ref(defs, raw["component"], here)
			out["min"] = _positive_int(defs, raw, "min", here)
		"active_distinct_types":
			out["min"] = _positive_int(defs, raw, "min", here)
		"parent_distinct_children":
			out["parent"] = _component_ref(defs, raw.get("parent"), here)
			out["min_distinct"] = _positive_int(defs, raw, "min_distinct", here)
		"resource_amount", "lifetime_produced":
			out["resource"] = _resource_ref(defs, raw.get("resource"), here)
			var minimum: Variant = raw.get("min")
			if (minimum is float or minimum is int) and minimum > 0:
				out["min"] = roundi(float(minimum) * NxDefinitions.MILLI)
			else:
				defs.errors.append("%s: 'min' deve ser um número positivo" % here)
				out["min"] = 0
		"net_rate_positive":
			var resource_ids := []
			var raw_ids: Variant = raw.get("resources", [])
			if raw_ids is Array and not raw_ids.is_empty():
				for rid: Variant in raw_ids:
					resource_ids.append(_resource_ref(defs, rid, here))
			else:
				defs.errors.append("%s: 'resources' deve ser uma lista não vazia" % here)
			out["resources"] = resource_ids
		"all_active_full_efficiency":
			var required := []
			var raw_required: Variant = raw.get("require", [])
			if raw_required is Array:
				for cid: Variant in raw_required:
					required.append(_component_ref(defs, cid, here))
			else:
				defs.errors.append("%s: 'require' deve ser uma lista" % here)
			out["require"] = required
			out["min_active"] = _positive_int(defs, raw, "min_active", here)
		"sustained":
			if nested:
				defs.errors.append("%s: 'sustained' não pode ser aninhado" % where)
				return {}
			var seconds: Variant = raw.get("seconds")
			if (seconds is float or seconds is int) and seconds > 0:
				out["ms"] = roundi(float(seconds) * 1000.0)
			else:
				defs.errors.append("%s: 'seconds' deve ser um número positivo" % here)
				out["ms"] = 0
			var inner := _condition(defs, raw.get("condition"), here, true)
			if inner.is_empty():
				return {}
			out["condition"] = inner
	return out


static func _reward(defs: NxDefinitions, raw: Variant, where: String) -> Dictionary:
	if not (raw is Dictionary):
		defs.errors.append("%s: recompensa não é um objeto" % where)
		return {}
	var type := str(raw.get("type", ""))
	if not REWARD_TYPES.has(type):
		defs.errors.append("%s: tipo de recompensa desconhecido '%s'" % [where, type])
		return {}
	var here := "%s, recompensa '%s'" % [where, type]
	match type:
		"unlock_component":
			return {"type": type, "component": _component_ref(defs, raw.get("component"), here)}
		"unlock_feature":
			var feature := str(raw.get("feature", ""))
			if feature.is_empty():
				defs.errors.append("%s: falta 'feature'" % here)
			return {"type": type, "feature": feature}
		"set_stage":
			var stage: Variant = raw.get("stage")
			if (stage is float or stage is int) and int(stage) >= 2 and float(stage) == floorf(float(stage)):
				return {"type": type, "stage": int(stage)}
			defs.errors.append("%s: 'stage' deve ser um inteiro ≥ 2" % here)
	return {}


static func _component_ref(defs: NxDefinitions, value: Variant, where: String) -> String:
	var id := str(value) if value != null else ""
	if not defs.components.has(id):
		defs.errors.append("%s: componente desconhecido '%s'" % [where, id])
	return id


static func _resource_ref(defs: NxDefinitions, value: Variant, where: String) -> String:
	var id := str(value) if value != null else ""
	if not defs.resources.has(id):
		defs.errors.append("%s: recurso desconhecido '%s'" % [where, id])
	return id


static func _positive_int(defs: NxDefinitions, raw: Dictionary, key: String, where: String) -> int:
	var value: Variant = raw.get(key)
	if (value is float or value is int) and float(value) == floorf(float(value)) and value >= 1:
		return int(value)
	defs.errors.append("%s: '%s' deve ser um inteiro ≥ 1" % [where, key])
	return 1


# --- pré-requisitos e ordem -------------------------------------------------

static func _check_prerequisites_and_order(defs: NxDefinitions) -> void:
	var remaining := {}
	for id: String in defs.discoveries:
		var valid := []
		for prereq: String in defs.discoveries[id]["prerequisites"]:
			if prereq == id:
				defs.errors.append("descoberta '%s': é pré-requisito de si mesma" % id)
			elif not defs.discoveries.has(prereq):
				defs.errors.append("descoberta '%s': pré-requisito desconhecido '%s'" % [id, prereq])
			else:
				valid.append(prereq)
		remaining[id] = valid

	# Kahn com desempate pelo id, para uma ordem estável.
	var order := PackedStringArray()
	var done := {}
	while not remaining.is_empty():
		var ready := []
		for id: String in remaining:
			if remaining[id].all(func(p: String) -> bool: return done.has(p)):
				ready.append(id)
		if ready.is_empty():
			var stuck := remaining.keys()
			stuck.sort()
			defs.errors.append("descobertas com pré-requisitos circulares: %s" % ", ".join(stuck))
			return
		ready.sort()
		var chosen: String = ready[0]
		order.append(chosen)
		done[chosen] = true
		remaining.erase(chosen)
	defs.discovery_order = order


# --- alcançabilidade ----------------------------------------------------------

## Para cada descoberta, componentes e recursos que ela exige precisam estar
## disponíveis pelo início ou pelas recompensas dos seus pré-requisitos.
static func _check_reachability(defs: NxDefinitions) -> void:
	if defs.discovery_order.size() != defs.discoveries.size() or not defs.balance.has("start_unlocked"):
		return  # ciclo ou balance inválido: já reportado
	var available := {}  # id da descoberta -> {componente: true} liberados ANTES dela
	for id in defs.discovery_order:
		var before := {}
		for cid: String in defs.balance["start_unlocked"]:
			before[cid] = true
		for prereq: String in defs.discoveries[id]["prerequisites"]:
			if not available.has(prereq):
				continue  # desconhecido ou a própria descoberta: já reportado
			for cid: String in available[prereq]:
				before[cid] = true
			for reward: Dictionary in defs.discoveries[prereq]["rewards"]:
				if reward["type"] == "unlock_component":
					before[reward["component"]] = true
		available[id] = before

		var producible := {}
		var core_id: String = defs.balance["core_component"]
		if defs.components.has(core_id):
			for rid: String in defs.components[core_id]["outputs"]:
				producible[rid] = true
		for cid: String in before:
			if not defs.components.has(cid):
				continue  # referência inválida: já reportada
			for rid: String in defs.components[cid]["outputs"]:
				producible[rid] = true

		for condition: Dictionary in defs.discoveries[id]["conditions"]:
			_check_condition_reachable(defs, id, condition, before, producible)


static func _check_condition_reachable(defs: NxDefinitions, id: String, condition: Dictionary, available: Dictionary, producible: Dictionary) -> void:
	var core_id: String = defs.balance["core_component"]
	var needed_components := []
	var needed_resources := []
	match condition["type"]:
		"active_component_count":
			if condition.has("component"):
				needed_components.append(condition["component"])
		"parent_distinct_children":
			needed_components.append(condition["parent"])
		"all_active_full_efficiency":
			needed_components.append_array(condition["require"])
		"lifetime_produced":
			needed_resources.append(condition["resource"])
		"resource_amount":
			if int(defs.balance["start_resources"].get(condition["resource"], 0)) < int(condition["min"]):
				needed_resources.append(condition["resource"])
		"net_rate_positive":
			needed_resources.append_array(condition["resources"])
		"sustained":
			_check_condition_reachable(defs, id, condition["condition"], available, producible)
			return
	for cid: String in needed_components:
		if cid != core_id and not available.has(cid) and defs.components.has(cid):
			defs.errors.append("descoberta '%s': exige '%s', que nenhum pré-requisito (nem o início) libera (inalcançável)" % [id, cid])
	for rid: String in needed_resources:
		if defs.resources.has(rid) and not producible.has(rid):
			defs.errors.append("descoberta '%s': exige '%s', que nenhum componente disponível produz (inalcançável)" % [id, rid])
