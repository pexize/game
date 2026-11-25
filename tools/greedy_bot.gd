class_name NxGreedyBot
extends RefCounted
## Jogador automático simples, usado pelo simulador e pelos testes de
## alcançabilidade econômica. Segue uma lista de prioridades estrita:
## constrói o primeiro item cujo limite ainda não foi atingido e, se não
## puder pagar, espera. Não otimiza nada; serve para detectar bloqueios.

## [id do componente, quantidade desejada]
const DEFAULT_PLAN := [
	["generator", 1], ["collector", 1], ["generator", 2],
	["analyzer", 1], ["collector", 2], ["generator", 4], ["analyzer", 2],
]

var plan: Array


func _init(p_plan: Array = DEFAULT_PLAN) -> void:
	plan = p_plan


## Tenta uma construção por chamada. Devolve o id construído ou "".
func act(state: NxGameState, defs: NxDefinitions) -> String:
	for entry: Array in plan:
		var def_id: String = entry[0]
		if state.count_of(def_id) >= int(entry[1]):
			continue
		return def_id if NxBuildService.build(state, defs, def_id).ok else ""
	return ""
