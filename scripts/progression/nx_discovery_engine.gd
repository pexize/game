class_name NxDiscoveryEngine
extends RefCounted
## Avalia as descobertas depois de cada passo de simulação (FR-06).
##
## - Só avalia uma descoberta quando todos os pré-requisitos foram obtidos.
## - `discovery_order` é topológica, então uma descoberta concedida neste
##   passo já libera as seguintes no mesmo passo.
## - Cada descoberta é concedida uma única vez e registra ordem e tempo.
## - As recompensas são mudanças de dados no estado (componentes e
##   recursos liberados, estágio); nenhum outro módulo é chamado.
## - Condições "sustained" acumulam `report.dt_ms` enquanto a condição
##   interna é verdadeira e zeram quando ela falha. Todas as condições de
##   uma descoberta são avaliadas a cada passo, sem curto-circuito, para
##   que os contadores avancem de forma independente.

const FULL_EFFICIENCY := 0.999999


## Devolve os ids concedidos neste passo, em ordem de concessão.
static func evaluate(state: NxGameState, defs: NxDefinitions, report: NxStepReport) -> Array:
	var granted := []
	var context := {
		"state": state, "defs": defs, "report": report,
		"active": NxNetwork.active_ids(state, defs),
	}
	for id in defs.discovery_order:
		if state.discoveries.has(id):
			continue
		var discovery: Dictionary = defs.discoveries[id]
		if not _prerequisites_met(state, discovery):
			continue
		var all_met := true
		for index in range(discovery["conditions"].size()):
			if not _check(discovery["conditions"][index], id, index, context):
				all_met = false
		if all_met:
			_grant(state, discovery)
			granted.append(id)
	return granted


static func _prerequisites_met(state: NxGameState, discovery: Dictionary) -> bool:
	for prereq: String in discovery["prerequisites"]:
		if not state.discoveries.has(prereq):
			return false
	return true


static func _grant(state: NxGameState, discovery: Dictionary) -> void:
	state.discoveries[discovery["id"]] = {"order": state.discoveries.size() + 1, "time_ms": state.time_ms}
	state.condition_progress.erase(discovery["id"])
	for reward: Dictionary in discovery["rewards"]:
		match reward["type"]:
			"unlock_component":
				state.unlocked[reward["component"]] = true
			"unlock_feature":
				state.features[reward["feature"]] = true
			"set_stage":
				state.stage = maxi(state.stage, int(reward["stage"]))


static func _check(condition: Dictionary, discovery_id: String, index: int, context: Dictionary) -> bool:
	if condition["type"] == "sustained":
		var holds := _check_instant(condition["condition"], context)
		var progress: Dictionary = context["state"].condition_progress.get(discovery_id, {})
		var key := str(index)
		var elapsed: int = int(progress.get(key, 0)) + int(context["report"].dt_ms) if holds else 0
		progress[key] = elapsed
		context["state"].condition_progress[discovery_id] = progress
		return elapsed >= int(condition["ms"])
	return _check_instant(condition, context)


static func _check_instant(condition: Dictionary, context: Dictionary) -> bool:
	var state: NxGameState = context["state"]
	var defs: NxDefinitions = context["defs"]
	var report: NxStepReport = context["report"]
	var active: Dictionary = context["active"]

	match condition["type"]:
		"active_component_count":
			var count := 0
			for instance_id: int in active:
				var def_id: String = state.components[instance_id]["def"]
				if condition.has("component"):
					if def_id == condition["component"]:
						count += 1
				elif def_id != defs.balance["core_component"]:
					count += 1
			return count >= int(condition["min"])
		"active_distinct_types":
			return _active_types(state, defs, active).size() >= int(condition["min"])
		"parent_distinct_children":
			for instance_id: int in active:
				if state.components[instance_id]["def"] != condition["parent"]:
					continue
				var types := {}
				for child: int in NxNetwork.children_of(state, instance_id):
					if active.has(child):
						types[state.components[child]["def"]] = true
				if types.size() >= int(condition["min_distinct"]):
					return true
			return false
		"resource_amount":
			return state.amount(condition["resource"]) >= int(condition["min"])
		"lifetime_produced":
			return int(state.lifetime_produced.get(condition["resource"], 0)) >= int(condition["min"])
		"net_rate_positive":
			for rid: String in condition["resources"]:
				# Produção − consumo antes do limite de armazenamento (D-028).
				if int(report.produced.get(rid, 0)) - int(report.consumed.get(rid, 0)) <= 0:
					return false
			return true
		"all_active_full_efficiency":
			if _active_non_core_count(state, defs, active) < int(condition["min_active"]):
				return false
			var types := _active_types(state, defs, active)
			for cid: String in condition["require"]:
				if not types.has(cid):
					return false
			for instance_id: int in active:
				if float(report.efficiency.get(instance_id, 0.0)) < FULL_EFFICIENCY:
					return false
			return true
	return false


static func _active_types(state: NxGameState, defs: NxDefinitions, active: Dictionary) -> Dictionary:
	var types := {}
	for instance_id: int in active:
		var def_id: String = state.components[instance_id]["def"]
		if def_id != defs.balance["core_component"]:
			types[def_id] = true
	return types


static func _active_non_core_count(state: NxGameState, defs: NxDefinitions, active: Dictionary) -> int:
	var count := 0
	for instance_id: int in active:
		if state.components[instance_id]["def"] != defs.balance["core_component"]:
			count += 1
	return count
