extends RefCounted
## Definições mínimas e independentes de `data/`: os testes do motor não
## quebram quando o balanceamento muda. Cada chamada devolve cópias novas
## que o teste pode alterar para provocar um erro específico.


static func raw_resources() -> Array:
	return [
		{"id": "energy", "tier": 0, "max_storage": 100},
		{"id": "matter", "tier": 1},
		{"id": "data", "tier": 2},
	]


static func raw_components() -> Array:
	return [
		{"id": "core", "outputs": {"energy": 1.0}, "output_ports": 3,
			"removable": false, "build_limit": 1},
		{"id": "generator", "cost": {"energy": 10}, "outputs": {"energy": 1.5},
			"output_ports": 1},
		{"id": "collector", "cost": {"matter": 10}, "inputs": {"energy": 0.5},
			"outputs": {"matter": 0.5}, "output_ports": 1, "protect_last": true},
		{"id": "analyzer", "cost": {"matter": 25},
			"inputs": {"energy": 1.0, "matter": 0.2}, "outputs": {"data": 0.1},
			"output_ports": 1},
	]


static func raw_balance() -> Dictionary:
	return {
		"core_component": "core",
		"start_resources": {"energy": 5, "matter": 10},
		"start_unlocked": ["generator", "collector", "analyzer"],
		"dt_active_ms": 1000,
		"dt_offline_ms": 60000,
		"offline_cap_s": 28800,
		"offline_efficiency": 0.7,
		"removal_refund": 0.5,
	}


static func defs() -> NxDefinitions:
	return NxDefinitions.from_dicts(raw_resources(), raw_components(), raw_balance())


## Estado vazio com recursos zerados e só o Core, para cenários controlados.
static func blank_state(defs: NxDefinitions) -> NxGameState:
	var state := NxGameState.new()
	for rid in defs.resource_ids:
		state.resources[rid] = 0
		state.lifetime_produced[rid] = 0
	state.add_component("core")
	return state
