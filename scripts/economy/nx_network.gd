class_name NxNetwork
extends RefCounted
## Rede de componentes: uma árvore com raiz no Core (D-016, D-017).
##
## - Cada componente que não é o Core tem no máximo um pai (`parent`).
## - O número de filhos de um componente não passa de `output_ports`.
## - Como todo nó tem um único pai e a raiz é o Core, ciclos são
##   rejeitados na ligação e não existem em estados válidos.
## - Um componente está ATIVO se for o Core habilitado, ou se estiver
##   habilitado e o pai estiver ativo. Desabilitar ou desconectar um nó
##   desativa toda a sua sub-árvore (D-036).
## - Recursos ficam num reservatório global; conexões só decidem quem opera.
##
## Todas as alterações passam por aqui e devolvem NxResult; a interface
## nunca edita `parent` diretamente.


static func children_of(state: NxGameState, parent_id: int) -> Array:
	var out := []
	for instance_id: int in state.components:
		if int(state.components[instance_id]["parent"]) == parent_id:
			out.append(instance_id)
	out.sort()
	return out


static func free_ports(state: NxGameState, defs: NxDefinitions, instance_id: int) -> int:
	var def: Dictionary = defs.components[state.components[instance_id]["def"]]
	return int(def["output_ports"]) - children_of(state, instance_id).size()


static func is_root(state: NxGameState, defs: NxDefinitions, instance_id: int) -> bool:
	return state.components[instance_id]["def"] == defs.balance["core_component"]


## Conjunto {instance_id: true} dos componentes ativos.
static func active_ids(state: NxGameState, defs: NxDefinitions) -> Dictionary:
	var kids := {}
	var pending := []
	for instance_id: int in state.components:
		var inst: Dictionary = state.components[instance_id]
		if is_root(state, defs, instance_id):
			if inst["enabled"]:
				pending.append(instance_id)
			continue
		var parent := int(inst["parent"])
		if parent != 0:
			if not kids.has(parent):
				kids[parent] = []
			kids[parent].append(instance_id)

	var active := {}
	while not pending.is_empty():
		var current: int = pending.pop_back()
		active[current] = true
		for child: int in kids.get(current, []):
			if state.components[child]["enabled"]:
				pending.append(child)
	return active


## Primeiro componente ativo com porta livre, do mais próximo do Core ao
## mais distante (empates pelo menor id). 0 se não houver.
static func first_free_parent(state: NxGameState, defs: NxDefinitions) -> int:
	var active := active_ids(state, defs)
	var level := []
	for instance_id: int in state.components:
		if is_root(state, defs, instance_id) and active.has(instance_id):
			level.append(instance_id)
	level.sort()
	while not level.is_empty():
		var next_level := []
		for instance_id: int in level:
			if free_ports(state, defs, instance_id) > 0:
				return instance_id
			next_level.append_array(children_of(state, instance_id).filter(
				func(child: int) -> bool: return active.has(child)))
		level = next_level
	return 0


static func connect_components(state: NxGameState, defs: NxDefinitions, parent_id: int, child_id: int) -> NxResult:
	if not state.components.has(parent_id) or not state.components.has(child_id):
		return NxResult.failure("unknown_instance", "Componente inexistente.")
	if parent_id == child_id:
		return NxResult.failure("self_connection", "Um componente não pode ligar a si mesmo.")
	if is_root(state, defs, child_id):
		return NxResult.failure("core_has_no_parent", "O Core é a raiz e não recebe entrada.")
	if int(state.components[child_id]["parent"]) != 0:
		return NxResult.failure("already_connected", "O componente já tem uma entrada; desconecte-o antes.")
	if _is_in_subtree(state, parent_id, child_id):
		return NxResult.failure("would_create_cycle", "A ligação criaria um ciclo.")
	if free_ports(state, defs, parent_id) <= 0:
		return NxResult.failure("no_free_port", "O componente de origem não tem portas livres.")
	state.components[child_id]["parent"] = parent_id
	return NxResult.success()


static func disconnect_component(state: NxGameState, child_id: int) -> NxResult:
	if not state.components.has(child_id):
		return NxResult.failure("unknown_instance", "Componente inexistente.")
	if int(state.components[child_id]["parent"]) == 0:
		return NxResult.failure("not_connected", "O componente já está desconectado.")
	state.components[child_id]["parent"] = 0
	return NxResult.success()


## O Core não pode ser desabilitado: desligaria a rede inteira.
static func set_enabled(state: NxGameState, defs: NxDefinitions, instance_id: int, enabled: bool) -> NxResult:
	if not state.components.has(instance_id):
		return NxResult.failure("unknown_instance", "Componente inexistente.")
	if is_root(state, defs, instance_id):
		return NxResult.failure("not_removable", "O Core não pode ser desabilitado.")
	state.components[instance_id]["enabled"] = enabled
	return NxResult.success()


## Remove um componente e reembolsa `removal_refund` do custo (arredondado
## para baixo, com limite de armazenamento). Os filhos ficam desconectados.
static func remove_component(state: NxGameState, defs: NxDefinitions, instance_id: int) -> NxResult:
	if not state.components.has(instance_id):
		return NxResult.failure("unknown_instance", "Componente inexistente.")
	var def_id: String = state.components[instance_id]["def"]
	var def: Dictionary = defs.components[def_id]
	if not def["removable"]:
		return NxResult.failure("not_removable", "Este componente não pode ser removido.")
	if def["protect_last"] and state.count_of(def_id) <= 1:
		return NxResult.failure("last_protected", "O último %s não pode ser removido." % def_id)

	var refund := {}
	var ratio: float = defs.balance["removal_refund"]
	for rid: String in def["cost"]:
		var amount := floori(float(def["cost"][rid]) * ratio)
		NxLedger.credit(state, defs, rid, amount)
		refund[rid] = amount
	for child: int in children_of(state, instance_id):
		state.components[child]["parent"] = 0
	state.components.erase(instance_id)
	return NxResult.success({"refund": refund})


## Confere as invariantes da árvore (usado em testes e na validação de saves).
static func validate(state: NxGameState, defs: NxDefinitions) -> PackedStringArray:
	var errors := PackedStringArray()
	for instance_id: int in state.components:
		var inst: Dictionary = state.components[instance_id]
		if not defs.components.has(inst["def"]):
			errors.append("#%d: definição desconhecida '%s'" % [instance_id, inst["def"]])
			continue
		var parent := int(inst["parent"])
		if is_root(state, defs, instance_id) and parent != 0:
			errors.append("#%d: o Core não pode ter pai" % instance_id)
		if parent != 0:
			if not state.components.has(parent):
				errors.append("#%d: pai #%d não existe" % [instance_id, parent])
			elif _is_in_subtree(state, parent, instance_id):
				errors.append("#%d: ciclo na árvore" % instance_id)
		if free_ports(state, defs, instance_id) < 0:
			errors.append("#%d: mais filhos que portas de saída" % instance_id)
	return errors


## Verdadeiro se `node_id` é `ancestor_id` ou descende dele, subindo pelos pais.
## Limitado ao tamanho do mapa para não travar em dados corrompidos com ciclo.
static func _is_in_subtree(state: NxGameState, node_id: int, ancestor_id: int) -> bool:
	var current := node_id
	for _i in range(state.components.size() + 1):
		if current == ancestor_id:
			return true
		if current == 0 or not state.components.has(current):
			return false
		current = int(state.components[current]["parent"])
	return true
