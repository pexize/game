class_name NxBuildService
extends RefCounted
## Construção de componentes (FR-03). Operação atômica: todas as
## validações acontecem antes de qualquer alteração de estado.
## Conexões e posicionamento na rede chegam na Fase 2.


static func build(state: NxGameState, defs: NxDefinitions, def_id: String) -> NxResult:
	if not defs.components.has(def_id):
		return NxResult.failure("unknown_component", "Componente desconhecido: %s" % def_id)
	if not state.is_unlocked(def_id):
		return NxResult.failure("locked", "Componente ainda não desbloqueado: %s" % def_id)
	var comp: Dictionary = defs.components[def_id]
	var limit: int = comp["build_limit"]
	if limit > 0 and state.count_of(def_id) >= limit:
		return NxResult.failure("limit_reached", "Limite de construção atingido: %s" % def_id)
	if not NxLedger.can_afford(state, comp["cost"]):
		return NxResult.failure("insufficient_resources", "Recursos insuficientes para construir %s" % def_id)

	NxLedger.try_spend(state, comp["cost"])
	var instance_id := state.add_component(def_id)
	return NxResult.success({"instance_id": instance_id})
