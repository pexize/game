class_name NxLedger
extends RefCounted
## Única autoridade sobre saldos: gastar, creditar e consultar.
## Nenhuma operação deixa um saldo negativo ou acima do armazenamento máximo.


static func can_afford(state: NxGameState, cost: Dictionary) -> bool:
	for rid: String in cost:
		if state.amount(rid) < int(cost[rid]):
			return false
	return true


## Atômico: ou debita todos os recursos, ou não altera nada.
static func try_spend(state: NxGameState, cost: Dictionary) -> bool:
	if not can_afford(state, cost):
		return false
	for rid: String in cost:
		state.resources[rid] = state.amount(rid) - int(cost[rid])
	return true


## Credita respeitando o armazenamento máximo. Devolve a quantidade perdida
## por excesso. Quantidades negativas são ignoradas.
static func credit(state: NxGameState, defs: NxDefinitions, resource_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var total := state.amount(resource_id) + amount
	var cap := defs.max_storage(resource_id)
	var lost := 0
	if cap != NxDefinitions.UNLIMITED and total > cap:
		lost = total - cap
		total = cap
	state.resources[resource_id] = total
	return lost
