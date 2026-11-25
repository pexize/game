class_name NxGreedyBot
extends RefCounted
## Jogador automático simples, usado pelo simulador e pelos testes de
## alcançabilidade econômica. Segue uma lista de prioridades estrita:
## constrói o primeiro item cujo limite ainda não foi atingido e, se não
## puder pagar, espera. Não otimiza nada; serve para detectar bloqueios.

## [id do componente, quantidade desejada]
## A ordem respeita os desbloqueios: Collector vem de D1, Relay de D3 (três
## componentes ativos), Analyzer de D2 e Processor de D5.
const DEFAULT_PLAN := [
	["generator", 1], ["collector", 1], ["generator", 2], ["relay", 1],
	["analyzer", 1], ["generator", 3], ["collector", 2], ["processor", 1],
]

## Tipos que o bot põe sob o Processor para cumprir a estrutura de D7.
const PROCESSOR_CHILDREN := ["generator", "collector"]

var plan: Array


func _init(p_plan: Array = DEFAULT_PLAN) -> void:
	plan = p_plan


## Uma ação por chamada: liga primeiro os componentes soltos (se houver
## porta livre) e depois tenta a próxima construção do plano. Cada
## construção nova é ligada ao componente ativo mais próximo do Core que
## tenha porta livre. Devolve o id construído ou "".
func act(state: NxGameState, defs: NxDefinitions) -> String:
	_attach_orphans(state, defs)
	_arrange_processor(state, defs)
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


## Move, um por vez, um gerador e um Collector para baixo do Processor ativo,
## para que ele tenha filhos de tipos diferentes (D7). Se a ligação falhar
## (por exemplo, por criar um ciclo), devolve o componente ao pai antigo.
func _arrange_processor(state: NxGameState, defs: NxDefinitions) -> void:
	var active := NxNetwork.active_ids(state, defs)
	var ids := state.components.keys()
	ids.sort()
	var processor_id := 0
	for instance_id: int in ids:
		if state.components[instance_id]["def"] == "processor" and active.has(instance_id):
			processor_id = instance_id
			break
	if processor_id == 0:
		return

	var present := {}
	for child: int in NxNetwork.children_of(state, processor_id):
		present[state.components[child]["def"]] = true
	for def_id: String in PROCESSOR_CHILDREN:
		if present.has(def_id):
			continue
		if NxNetwork.free_ports(state, defs, processor_id) <= 0:
			return
		for candidate: int in ids:
			if state.components[candidate]["def"] != def_id:
				continue
			if int(state.components[candidate]["parent"]) in [0, processor_id]:
				continue
			var old_parent := int(state.components[candidate]["parent"])
			NxNetwork.disconnect_component(state, candidate)
			if NxNetwork.connect_components(state, defs, processor_id, candidate).ok:
				return
			NxNetwork.connect_components(state, defs, old_parent, candidate)
