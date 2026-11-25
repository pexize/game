extends "res://tests/framework/suite.gd"
## Descobertas: validação das definições, condições, concessão, contadores
## sustentados, recompensas e visibilidade.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const DT := 1000


# --- helpers -----------------------------------------------------------------

func _disc(id: String, conditions: Array, prerequisites: Array = [], rewards: Array = [], extra: Dictionary = {}) -> Dictionary:
	var raw := {"id": id, "title_key": "T_" + id, "hint_key": "H_" + id,
		"prerequisites": prerequisites, "conditions": conditions, "rewards": rewards}
	raw.merge(extra, true)
	return raw


func _defs(discoveries: Array, start_unlocked: Array = []) -> NxDefinitions:
	var balance := Fixtures.raw_balance()
	if not start_unlocked.is_empty():
		balance["start_unlocked"] = start_unlocked
	return NxDefinitions.from_dicts(Fixtures.raw_resources(), Fixtures.raw_components(), balance, discoveries)


func _error_text(discoveries: Array, start_unlocked: Array = []) -> String:
	return "\n".join(_defs(discoveries, start_unlocked).errors)


func _tick(state: NxGameState, defs: NxDefinitions, times: int = 1) -> NxStepReport:
	var report: NxStepReport
	for i in range(times):
		report = NxSimulation.tick(state, defs, DT)
	return report


func _count(kind: String, minimum: int = 1) -> Dictionary:
	return {"type": "active_component_count", "component": kind, "min": minimum}


# --- validação ----------------------------------------------------------------

func test_real_discoveries_are_valid_and_topologically_ordered() -> bool:
	var defs := NxDefinitions.load_from_dir("res://data")
	assert_eq("\n".join(defs.errors), "")
	assert_eq(defs.discovery_order.size(), 8, "as oito descobertas planejadas")
	var position := {}
	for index in range(defs.discovery_order.size()):
		position[defs.discovery_order[index]] = index
	for id in defs.discovery_order:
		for prereq: String in defs.discoveries[id]["prerequisites"]:
			assert_true(position[prereq] < position[id], "'%s' antes de '%s'" % [prereq, id])
	return true


func test_rejects_unknown_and_self_prerequisites() -> bool:
	var errors := _error_text([
		_disc("a", [_count("generator")], ["fantasma"]),
		_disc("b", [_count("generator")], ["b"]),
	])
	assert_true(errors.contains("fantasma"), "pré-requisito desconhecido")
	assert_true(errors.contains("pré-requisito de si mesma"), "autorreferência")
	return true


func test_rejects_prerequisite_cycles() -> bool:
	var errors := _error_text([
		_disc("a", [_count("generator")], ["b"]),
		_disc("b", [_count("generator")], ["a"]),
	])
	assert_true(errors.contains("circulares"), "ciclo entre pré-requisitos")
	return true


func test_rejects_unknown_condition_and_reward_types() -> bool:
	var errors := _error_text([
		_disc("a", [{"type": "magia"}], [], [{"type": "premio"}]),
	])
	assert_true(errors.contains("'magia'"), "condição desconhecida")
	assert_true(errors.contains("'premio'"), "recompensa desconhecida")
	return true


func test_rejects_unknown_references_and_bad_numbers() -> bool:
	var errors := _error_text([
		_disc("a", [
			{"type": "active_component_count", "component": "fantasma", "min": 1},
			{"type": "lifetime_produced", "resource": "plasma", "min": 5},
			{"type": "resource_amount", "resource": "energy", "min": -1},
			{"type": "active_distinct_types", "min": 0},
		], [], [{"type": "set_stage", "stage": 1}, {"type": "unlock_component", "component": "nada"}]),
	])
	for fragment in ["fantasma", "plasma", "'min' deve ser um número positivo", "'min' deve ser um inteiro", "stage", "nada"]:
		assert_true(errors.contains(fragment), "deve apontar: %s" % fragment)
	return true


func test_rejects_empty_conditions_and_nested_sustained() -> bool:
	var nested := {"type": "sustained", "seconds": 5, "condition":
		{"type": "sustained", "seconds": 5, "condition": _count("generator")}}
	var errors := _error_text([_disc("a", []), _disc("b", [nested])])
	assert_true(errors.contains("não vazia"), "sem condições")
	assert_true(errors.contains("aninhado"), "sustained dentro de sustained")
	return true


func test_rejects_duplicate_ids_and_unknown_fields() -> bool:
	var errors := _error_text([
		_disc("a", [_count("generator")]),
		_disc("a", [_count("generator")]),
		_disc("b", [_count("generator")], [], [], {"recompensa": []}),
	])
	assert_true(errors.contains("duplicado"))
	assert_true(errors.contains("recompensa"), "campo desconhecido")
	return true


func test_rejects_unreachable_component() -> bool:
	# Collector só começa liberado no balance padrão; aqui o início só tem o Generator.
	var errors := _error_text([_disc("a", [_count("collector")])], ["generator"])
	assert_true(errors.contains("inalcançável"), errors)
	return true


func test_accepts_component_unlocked_by_a_prerequisite_chain() -> bool:
	var unlock_collector := [{"type": "unlock_component", "component": "collector"}]
	var errors := _error_text([
		_disc("a", [_count("generator")], [], unlock_collector),
		_disc("b", [{"type": "lifetime_produced", "resource": "energy", "min": 1}], ["a"]),
		_disc("c", [_count("collector")], ["b"]),
	], ["generator"])
	assert_eq(errors, "", "c herda o desbloqueio de a por b")
	return true


func test_rejects_requirement_that_only_a_later_discovery_unlocks() -> bool:
	# "a" exige o Collector, que só "b" (que depende de "a") libera.
	var errors := _error_text([
		_disc("a", [_count("collector")]),
		_disc("b", [_count("generator")], ["a"], [{"type": "unlock_component", "component": "collector"}]),
	], ["generator"])
	assert_true(errors.contains("inalcançável"), errors)
	return true


func test_rejects_resource_nobody_available_can_produce() -> bool:
	var errors := _error_text([_disc("a", [{"type": "lifetime_produced", "resource": "data", "min": 1}])], ["generator"])
	assert_true(errors.contains("nenhum componente disponível produz"), errors)
	return true


func test_unlocked_component_must_still_be_economically_buildable() -> bool:
	# D-014 vale para o que as descobertas liberam: reserva de Matter menor
	# que o custo do Collector e ninguém produz Matter sem ele.
	var balance := Fixtures.raw_balance()
	balance["start_unlocked"] = ["generator"]
	balance["start_resources"] = {"energy": 5, "matter": 5}
	var defs := NxDefinitions.from_dicts(Fixtures.raw_resources(), Fixtures.raw_components(), balance, [
		_disc("a", [_count("generator")], [], [{"type": "unlock_component", "component": "collector"}]),
	])
	assert_true("\n".join(defs.errors).contains("D-014"), "\n".join(defs.errors))
	return true


# --- concessão e recompensas -----------------------------------------------------

func test_granted_once_with_order_and_time() -> bool:
	var defs := _defs([_disc("a", [_count("generator")])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	var first := _tick(state, defs)
	assert_eq(first.granted, ["a"], "concedida no primeiro passo")
	assert_eq(state.discoveries["a"], {"order": 1, "time_ms": 1000})
	var second := _tick(state, defs, 5)
	assert_eq(second.granted, [], "a condição continua verdadeira, mas não repete")
	assert_eq(state.discoveries.size(), 1)
	assert_eq(state.discoveries["a"]["order"], 1, "ordem preservada")
	return true


func test_rewards_are_applied_to_state() -> bool:
	var defs := _defs([_disc("a", [_count("generator")], [], [
		{"type": "unlock_component", "component": "relay"},
		{"type": "unlock_feature", "feature": "automation"},
		{"type": "set_stage", "stage": 2},
	])], ["generator"])
	var state := Fixtures.blank_state(defs)
	state.unlocked["generator"] = true
	Fixtures.add_connected(state, defs, "generator")
	assert_false(state.is_unlocked("relay"))
	_tick(state, defs)
	assert_true(state.is_unlocked("relay"), "componente liberado")
	assert_true(state.has_feature("automation"), "recurso liberado")
	assert_eq(state.stage, 2, "estágio")
	return true


func test_stage_never_goes_backwards() -> bool:
	var defs := _defs([_disc("a", [_count("generator")], [], [{"type": "set_stage", "stage": 2}])])
	var state := Fixtures.blank_state(defs)
	state.stage = 3
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs)
	assert_eq(state.stage, 3)
	return true


func test_prerequisites_gate_evaluation() -> bool:
	var defs := _defs([
		_disc("a", [{"type": "resource_amount", "resource": "energy", "min": 1000}]),
		_disc("b", [{"type": "lifetime_produced", "resource": "energy", "min": 1}], ["a"]),
	])
	var state := Fixtures.blank_state(defs)
	_tick(state, defs, 5)
	assert_false(state.has_discovery("b"), "condição de b é verdadeira, mas a ainda não foi obtida")
	assert_eq(state.discoveries.size(), 0)
	return true


func test_chain_is_granted_in_one_tick_in_dependency_order() -> bool:
	# Declaradas de trás para frente de propósito: a ordem vem do grafo.
	var defs := _defs([
		_disc("c", [{"type": "lifetime_produced", "resource": "energy", "min": 1}], ["b"]),
		_disc("b", [{"type": "lifetime_produced", "resource": "energy", "min": 1}], ["a"]),
		_disc("a", [{"type": "lifetime_produced", "resource": "energy", "min": 1}]),
	])
	var state := Fixtures.blank_state(defs)
	var report := _tick(state, defs)
	assert_eq(report.granted, ["a", "b", "c"])
	assert_eq(state.discoveries["a"]["order"], 1)
	assert_eq(state.discoveries["c"]["order"], 3)
	return true


# --- condições -------------------------------------------------------------------

func test_active_component_count_ignores_disconnected_and_core() -> bool:
	var defs := _defs([_disc("a", [{"type": "active_component_count", "min": 2}])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	state.add_component("generator")                    # solto: não conta
	_tick(state, defs, 3)
	assert_false(state.has_discovery("a"), "só um ativo (o Core não conta)")
	Fixtures.add_connected(state, defs, "collector")
	_tick(state, defs)
	assert_true(state.has_discovery("a"))
	return true


func test_resource_amount_and_lifetime_produced() -> bool:
	var defs := _defs([
		_disc("amount", [{"type": "resource_amount", "resource": "energy", "min": 8}]),
		_disc("lifetime", [{"type": "lifetime_produced", "resource": "energy", "min": 3}]),
	])
	var state := Fixtures.blank_state(defs)
	_tick(state, defs, 2)
	assert_eq(state.discoveries.size(), 0, "2 passos: saldo 2, produzido 2")
	_tick(state, defs)
	assert_true(state.has_discovery("lifetime"), "produzido 3")
	assert_false(state.has_discovery("amount"))
	_tick(state, defs, 5)
	assert_true(state.has_discovery("amount"), "saldo 8")
	return true


func test_lifetime_counts_production_not_balance() -> bool:
	# Gastar o saldo não desfaz o histórico.
	var defs := _defs([_disc("a", [{"type": "lifetime_produced", "resource": "energy", "min": 4}])])
	var state := Fixtures.blank_state(defs)
	_tick(state, defs, 2)
	NxLedger.try_spend(state, {"energy": state.amount("energy")})
	_tick(state, defs, 2)
	assert_true(state.has_discovery("a"), "4 produzidos mesmo com o saldo gasto")
	return true


func test_net_rate_positive_requires_surplus() -> bool:
	var defs := _defs([_disc("a", [{"type": "net_rate_positive", "resources": ["energy"]}])])
	var starved := Fixtures.blank_state(defs)
	for i in range(4):
		Fixtures.add_connected(starved, defs, "collector")  # consumo igual à produção do Core
	_tick(starved, defs, 3)
	assert_false(starved.has_discovery("a"), "saldo líquido zero não é positivo")
	var healthy := Fixtures.blank_state(defs)
	_tick(healthy, defs)
	assert_true(healthy.has_discovery("a"))
	return true


func test_net_rate_is_positive_even_when_storage_is_full() -> bool:
	# D-028: o limite de armazenamento não pode bloquear a descoberta.
	var defs := _defs([_disc("a", [{"type": "net_rate_positive", "resources": ["energy"]}])])
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 100000
	var report := _tick(state, defs)
	assert_eq(report.lost["energy"], 1000, "toda a produção foi perdida por limite")
	assert_true(state.has_discovery("a"), "mesmo assim há produção líquida")
	return true


func test_active_distinct_types() -> bool:
	var defs := _defs([_disc("a", [{"type": "active_distinct_types", "min": 2}])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 2)
	assert_false(state.has_discovery("a"), "dois geradores são um tipo só")
	Fixtures.add_connected(state, defs, "collector")
	_tick(state, defs)
	assert_true(state.has_discovery("a"))
	return true


func test_parent_distinct_children() -> bool:
	var defs := _defs([_disc("a", [{"type": "parent_distinct_children", "parent": "processor", "min_distinct": 2}])])
	var state := Fixtures.blank_state(defs)
	var processor := Fixtures.add_connected(state, defs, "processor")
	for kind in ["generator", "generator"]:
		var child := state.add_component(kind)
		NxNetwork.connect_components(state, defs, processor, child)
	state.resources["energy"] = 50000
	_tick(state, defs, 2)
	assert_false(state.has_discovery("a"), "filhos do mesmo tipo")
	# Troca um gerador por um Collector: dois tipos diferentes.
	var swapped: int = NxNetwork.children_of(state, processor)[1]
	NxNetwork.remove_component(state, defs, swapped)
	var collector := state.add_component("collector")
	NxNetwork.connect_components(state, defs, processor, collector)
	NxNetwork.set_enabled(state, defs, processor, false)
	_tick(state, defs, 2)
	assert_false(state.has_discovery("a"), "Processor desabilitado não conta")
	NxNetwork.set_enabled(state, defs, processor, true)
	_tick(state, defs)
	assert_true(state.has_discovery("a"))
	return true


func test_all_active_full_efficiency() -> bool:
	var defs := _defs([_disc("a", [{"type": "all_active_full_efficiency",
		"require": ["collector", "analyzer"], "min_active": 2}])])
	var starved := Fixtures.blank_state(defs)
	Fixtures.add_connected(starved, defs, "collector")
	for i in range(3):
		Fixtures.add_connected(starved, defs, "analyzer")  # 3 W de demanda contra 1 W do Core
	_tick(starved, defs, 3)
	assert_false(starved.has_discovery("a"), "algum componente abaixo de 100%")

	var healthy := Fixtures.blank_state(defs)
	healthy.resources["energy"] = 50000
	healthy.resources["matter"] = 50000
	Fixtures.add_connected(healthy, defs, "collector")
	Fixtures.add_connected(healthy, defs, "analyzer")
	_tick(healthy, defs)
	assert_true(healthy.has_discovery("a"))
	return true


func test_all_active_full_efficiency_requires_the_listed_types() -> bool:
	var defs := _defs([_disc("a", [{"type": "all_active_full_efficiency",
		"require": ["analyzer"], "min_active": 1}])])
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 50000
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 3)
	assert_false(state.has_discovery("a"), "sem Analyzer, mesmo com tudo a 100%")
	return true


func test_all_conditions_must_hold_together() -> bool:
	var defs := _defs([_disc("a", [
		{"type": "active_component_count", "min": 1},
		{"type": "resource_amount", "resource": "energy", "min": 10},
	])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 3)
	assert_false(state.has_discovery("a"), "só a primeira condição vale")
	state.resources["energy"] = 20000
	_tick(state, defs)
	assert_true(state.has_discovery("a"))
	return true


# --- condições sustentadas --------------------------------------------------------

func _sustained_defs(seconds: int) -> NxDefinitions:
	return _defs([_disc("a", [{"type": "sustained", "seconds": seconds,
		"condition": _count("generator")}])])


func test_sustained_needs_continuous_time() -> bool:
	var defs := _sustained_defs(5)
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 4)
	assert_false(state.has_discovery("a"), "4 s de 5")
	assert_eq(state.condition_progress["a"]["0"], 4000, "progresso acumulado")
	_tick(state, defs)
	assert_true(state.has_discovery("a"), "5 s")
	return true


func test_sustained_resets_when_the_condition_breaks() -> bool:
	var defs := _sustained_defs(5)
	var state := Fixtures.blank_state(defs)
	var generator := Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 3)
	NxNetwork.set_enabled(state, defs, generator, false)
	_tick(state, defs)
	assert_eq(state.condition_progress["a"]["0"], 0, "interrupção zera o contador")
	NxNetwork.set_enabled(state, defs, generator, true)
	_tick(state, defs, 4)
	assert_false(state.has_discovery("a"), "recomeçou do zero: 4 s de 5")
	_tick(state, defs)
	assert_true(state.has_discovery("a"))
	return true


func test_sustained_progress_survives_serialization() -> bool:
	var defs := _sustained_defs(5)
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 3)
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(state.to_dict())), OK)
	var restored := NxGameState.from_dict(json.data)
	_tick(restored, defs, 2)
	assert_true(restored.has_discovery("a"), "3 s salvos + 2 s depois de carregar")
	return true


func test_sustained_counts_even_while_another_condition_is_false() -> bool:
	# Todas as condições são avaliadas a cada passo, sem curto-circuito:
	# o contador de tempo não pode parar só porque a outra condição falha.
	var defs := _defs([_disc("a", [
		{"type": "resource_amount", "resource": "energy", "min": 100},
		{"type": "sustained", "seconds": 3, "condition": _count("generator")},
	])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 3)
	assert_eq(state.condition_progress["a"]["1"], 3000, "contador avançou com a outra condição falsa")
	assert_false(state.has_discovery("a"))
	state.resources["energy"] = 100000
	_tick(state, defs)
	assert_true(state.has_discovery("a"), "assim que a outra condição vale, concede")
	return true


func test_progress_is_cleared_once_granted() -> bool:
	var defs := _sustained_defs(2)
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 2)
	assert_true(state.has_discovery("a"))
	assert_false(state.condition_progress.has("a"), "sem contador órfão no save")
	return true


func test_sustained_waits_for_prerequisites() -> bool:
	var defs := _defs([
		_disc("a", [{"type": "resource_amount", "resource": "energy", "min": 6}]),
		_disc("b", [{"type": "sustained", "seconds": 3, "condition":
			{"type": "lifetime_produced", "resource": "energy", "min": 1}}], ["a"]),
	])
	var state := Fixtures.blank_state(defs)
	_tick(state, defs, 5)
	assert_false(state.condition_progress.has("b"), "b não conta tempo antes de a")
	_tick(state, defs, 2)
	assert_true(state.has_discovery("a"))
	assert_false(state.has_discovery("b"))
	_tick(state, defs, 3)
	assert_true(state.has_discovery("b"))
	return true


# --- visibilidade -----------------------------------------------------------------

func test_visibility_states() -> bool:
	var defs := _defs([
		_disc("first", [_count("generator")], [], [{"type": "unlock_feature", "feature": "x"}]),
		_disc("second", [
			{"type": "sustained", "seconds": 5, "condition": _count("generator")},
			{"type": "lifetime_produced", "resource": "energy", "min": 50},
		], ["first"]),
		_disc("third", [_count("collector")], ["second"]),
	])
	var state := Fixtures.blank_state(defs)
	assert_eq(NxDiscoveryView.status(state, defs, "first")["state"], "available")
	assert_eq(NxDiscoveryView.status(state, defs, "second")["state"], "distant")
	var distant := NxDiscoveryView.status(state, defs, "second")
	assert_false(distant.has("categories"), "descoberta distante não revela requisitos")

	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs)
	var obtained := NxDiscoveryView.status(state, defs, "first")
	assert_eq(obtained["state"], "obtained")
	assert_eq(obtained["rewards"], [{"type": "unlock_feature", "feature": "x"}], "recompensa completa")
	assert_eq(obtained["order"], 1)
	var near := NxDiscoveryView.status(state, defs, "second")
	assert_eq(near["state"], "available")
	assert_eq(near["categories"], ["functional", "historical"], "só categorias, sem números")
	assert_eq(NxDiscoveryView.next_available(state, defs), "second")
	return true


func test_secret_discovery_is_hidden_until_obtained() -> bool:
	var defs := _defs([_disc("hidden", [_count("generator")], [], [], {"visibility": "secret"})])
	var state := Fixtures.blank_state(defs)
	var before := NxDiscoveryView.status(state, defs, "hidden")
	assert_eq(before, {"state": "hidden", "id": "hidden"}, "nada vaza antes de obtida")
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs)
	assert_eq(NxDiscoveryView.status(state, defs, "hidden")["state"], "obtained")
	return true


func test_next_available_is_empty_when_everything_is_done() -> bool:
	var defs := _defs([_disc("a", [_count("generator")])])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs)
	assert_eq(NxDiscoveryView.next_available(state, defs), "")
	return true


# --- estado ------------------------------------------------------------------------

func test_progression_state_round_trips() -> bool:
	var defs := _defs([
		_disc("a", [_count("generator")], [], [
			{"type": "unlock_feature", "feature": "f"}, {"type": "set_stage", "stage": 2}]),
		_disc("b", [{"type": "sustained", "seconds": 9, "condition": _count("generator")}], ["a"]),
	])
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	_tick(state, defs, 4)
	var copy := NxGameState.from_dict(state.to_dict())
	assert_eq(copy.state_hash(), state.state_hash(), "hash igual")
	assert_eq(copy.stage, 2)
	assert_true(copy.has_feature("f"))
	assert_eq(copy.discoveries["a"]["order"], 1)
	# "b" já conta o passo em que "a" foi concedida (mesmo passo, ordem topológica).
	assert_eq(copy.condition_progress["b"]["0"], 4000)
	return true
