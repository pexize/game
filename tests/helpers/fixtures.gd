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
		{"id": "core", "outputs": {"energy": 1.0}, "output_ports": 10,
			"removable": false, "build_limit": 1},
		{"id": "generator", "cost": {"energy": 10}, "outputs": {"energy": 1.5},
			"output_ports": 1},
		{"id": "collector", "cost": {"matter": 10}, "inputs": {"energy": 0.5},
			"outputs": {"matter": 0.5}, "output_ports": 1, "protect_last": true},
		{"id": "analyzer", "cost": {"matter": 25},
			"inputs": {"energy": 1.0, "matter": 0.2}, "outputs": {"data": 0.1},
			"output_ports": 1},
		{"id": "relay", "cost": {"matter": 15}, "inputs": {"energy": 0.3},
			"output_ports": 4},
		{"id": "processor", "cost": {"matter": 40, "data": 10},
			"inputs": {"energy": 0.8}, "output_ports": 2, "child_multiplier": 1.5},
	]


static func raw_balance() -> Dictionary:
	return {
		"core_component": "core",
		"start_resources": {"energy": 5, "matter": 10},
		"start_unlocked": ["generator", "collector", "analyzer", "relay", "processor"],
		"dt_active_ms": 1000,
		"dt_offline_ms": 60000,
		"offline_cap_s": 28800,
		"offline_efficiency": 0.7,
		"removal_refund": 0.5,
	}


## Melhorias de teste, com números fáceis de conferir à mão.
static func raw_upgrades() -> Array:
	return [
		{"id": "gen_up", "category": "production", "target": "generator",
			"effect": {"type": "output_multiplier", "per_level": 0.25},
			"cost": {"matter": 20}, "growth": 1.6, "max_level": 4,
			"requires_features": ["production_upgrades"]},
		{"id": "global_up", "category": "production", "target": "all",
			"effect": {"type": "output_multiplier", "per_level": 0.1},
			"cost": {"matter": 50, "data": 10}, "growth": 2.0, "max_level": 3,
			"requires_features": ["data_upgrades"], "prerequisites": ["gen_up"]},
		{"id": "col_eff", "category": "efficiency", "target": "collector",
			"effect": {"type": "input_multiplier", "per_level": 0.1},
			"cost": {"data": 5}, "growth": 1.5, "max_level": 5,
			"requires_features": ["data_upgrades"]},
	]


## Descoberta que concede os recursos de jogo exigidos pelas melhorias de teste.
static func raw_feature_discovery() -> Dictionary:
	return {"id": "grants", "prerequisites": [],
		"conditions": [{"type": "lifetime_produced", "resource": "energy", "min": 1}],
		"rewards": [
			{"type": "unlock_feature", "feature": "production_upgrades"},
			{"type": "unlock_feature", "feature": "data_upgrades"},
			{"type": "unlock_feature", "feature": "automation"},
		]}


static func defs_with_upgrades() -> NxDefinitions:
	return NxDefinitions.from_dicts(raw_resources(), raw_components(), raw_balance(),
		[raw_feature_discovery()], raw_upgrades())


static func defs() -> NxDefinitions:
	return NxDefinitions.from_dicts(raw_resources(), raw_components(), raw_balance())


## Cria o componente (sem cobrar) e o liga ao ativo mais próximo do Core com
## porta livre. Devolve o instance_id.
static func add_connected(state: NxGameState, defs: NxDefinitions, def_id: String) -> int:
	var instance_id := state.add_component(def_id)
	NxNetwork.connect_components(state, defs, NxNetwork.first_free_parent(state, defs), instance_id)
	return instance_id


## Estado vazio com recursos zerados e só o Core, para cenários controlados.
static func blank_state(defs: NxDefinitions) -> NxGameState:
	var state := NxGameState.new()
	for rid in defs.resource_ids:
		state.resources[rid] = 0
		state.lifetime_produced[rid] = 0
	state.add_component("core")
	return state
