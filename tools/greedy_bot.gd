class_name NxGreedyBot
extends RefCounted
## Jogador automático simples, usado pelo simulador e pelos testes de
## alcançabilidade econômica. Segue uma lista de prioridades estrita:
## constrói o primeiro item cujo limite ainda não foi atingido e, se não
## puder pagar, espera. Não otimiza nada; serve para detectar bloqueios.

## [id do componente, quantidade desejada]
const DEFAULT_PLAN := [
	["generator", 1], ["collector", 1], ["relay", 1], ["generator", 2],
	["analyzer", 1], ["collector", 2], ["generator", 4], ["analyzer", 2],
	["processor", 1],
]

var plan: Array


func _init(p_plan: Array = DEFAULT_PLAN) -> void:
	plan = p_plan


## Uma ação por chamada: liga primeiro os componentes soltos (se houver
## porta livre) e depois tenta a próxima construção do plano. Cada
## construção nova é ligada ao componente ativo mais próximo do Core que
## tenha porta livre. Devolve o id construído ou "".
func act(state: NxGameState, defs: NxDefinitions) -> String:
	_attach_orphans(state, defs)
	for entry: Array in plan:
		var def_id: String = entry[0]
		if state.count_of(def_id) >= int(entry[1]):
			continue
		var result := NxBuildService.build(state, defs, def_id)
		if not result.ok:
			return ""
		var parent := NxNetwork.first_free_parent(state, defs)
		if parent != 0:
			NxNetwork.connect_components(state, defs, parent, result.data["instance_id"])
		return def_id
	return ""


func _attach_orphans(state: NxGameState, defs: NxDefinitions) -> void:
	var ids := state.components.keys()
	ids.sort()
	for instance_id: int in ids:
		if NxNetwork.is_root(state, defs, instance_id) or int(state.components[instance_id]["parent"]) != 0:
			continue
		var parent := NxNetwork.first_free_parent(state, defs)
		if parent == 0:
			return
		NxNetwork.connect_components(state, defs, parent, instance_id)
