extends "res://tests/framework/suite.gd"
## Motor de simulação: produção, consumo, déficit, limite, determinismo.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const DT := 1000


func _run(state: NxGameState, defs: NxDefinitions, steps: int) -> void:
	for i in range(steps):
		NxEconomyEngine.step(state, defs, DT)


func test_core_alone_produces_energy() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	_run(state, defs, 10)
	assert_eq(state.amount("energy"), 15000, "5 inicial + 10 passos x 1/s")
	assert_eq(state.amount("matter"), 10000, "matter não muda sem Collector")
	assert_eq(state.lifetime_produced["energy"], 10000, "estatística acumulada")
	assert_eq(state.time_ms, 10000, "tempo simulado")
	return true


func test_generator_adds_energy() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	Fixtures.add_connected(state, defs, "generator")
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 2500, "core 1.0 + generator 1.5")
	return true


func test_collector_converts_energy_to_matter() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 10000
	Fixtures.add_connected(state, defs, "collector")
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("matter"), 500, "produz 0.5")
	assert_eq(state.amount("energy"), 10500, "10 + core 1.0 - collector 0.5")
	assert_eq(report.consumed["energy"], 500)
	assert_near(report.efficiency[2], 1.0, 0.0001)
	return true


func test_shortage_slows_consumers_proportionally() -> bool:
	# Core dá 1.0; quatro Collectors pedem 2.0: razão 0.5, cada um a 50%.
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	for i in range(4):
		Fixtures.add_connected(state, defs, "collector")
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_near(report.ratios["energy"], 0.5, 0.0001, "razão de Energy")
	assert_eq(state.amount("energy"), 0, "toda a energia foi usada")
	assert_eq(state.amount("matter"), 1000, "4 x 0.5 x 50%")
	for instance_id in [2, 3, 4, 5]:
		assert_near(report.efficiency[instance_id], 0.5, 0.0001)
	return true


func test_rounding_never_creates_resources() -> bool:
	# Três Collectors pedem 1.5 de energy e há 1.0: razão 2/3. A produção
	# exata seria 1.000 de matter; arredondar para cima daria 1.002.
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	for i in range(3):
		Fixtures.add_connected(state, defs, "collector")
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_eq(report.produced["matter"], 999, "3 x floor(500 x 2/3)")
	assert_true(report.produced["matter"] <= 1000, "nunca acima do valor exato")
	assert_eq(report.consumed["energy"], 999, "consumo também arredonda para baixo")
	assert_eq(state.amount("energy"), 1, "sobra 0.001, nunca falta")
	return true


func test_component_limited_by_its_scarcest_input() -> bool:
	# Analyzer pede energy 1.0 e matter 0.2; só há matter para 25%.
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 10000
	state.resources["matter"] = 50  # 0.05 de 0.2 pedidos
	Fixtures.add_connected(state, defs, "analyzer")
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_near(report.ratios["matter"], 0.25, 0.0001)
	assert_near(report.efficiency[2], 0.25, 0.0001, "vale a menor razão")
	assert_eq(state.amount("data"), 25, "0.1 x 25%")
	assert_eq(state.amount("matter"), 0, "matter esgotada, nunca negativa")
	return true


func test_resource_cap_discards_excess_but_reports_production() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 99500
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 100000)
	assert_eq(report.lost["energy"], 500, "perda por limite")
	assert_eq(report.produced["energy"], 1000, "produção medida antes do limite (D-028)")
	assert_near(report.net_rate("energy"), 1000.0, 0.001, "taxa líquida continua positiva no limite")
	return true


func test_disabled_component_is_inactive() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var generator := Fixtures.add_connected(state, defs, "generator")
	state.components[generator]["enabled"] = false
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 1000, "só o Core produz")
	return true


func test_zero_or_negative_dt_changes_nothing() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	var before := state.state_hash()
	NxEconomyEngine.step(state, defs, 0)
	NxEconomyEngine.step(state, defs, -500)
	assert_eq(state.state_hash(), before)
	return true


func test_never_negative_and_conserves_resources() -> bool:
	# Cenário com déficit: confere, passo a passo, saldo = antes + produzido - consumido - perdido.
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 3000
	state.resources["matter"] = 40000
	for kind in ["collector", "collector", "analyzer", "analyzer", "generator"]:
		Fixtures.add_connected(state, defs, kind)
	for step in range(200):
		var before := state.resources.duplicate()
		var report := NxEconomyEngine.step(state, defs, DT)
		for rid in defs.resource_ids:
			var expected: int = before[rid] + report.produced[rid] - report.consumed[rid] - report.lost[rid]
			assert_eq(state.amount(rid), expected, "conservação de %s no passo %d" % [rid, step])
			assert_true(state.amount(rid) >= 0, "%s nunca negativo (passo %d)" % [rid, step])
	return true


func test_result_does_not_depend_on_component_order() -> bool:
	var defs := Fixtures.defs()
	var kinds := ["generator", "collector", "analyzer", "collector", "analyzer", "generator", "collector"]
	var forward := Fixtures.blank_state(defs)
	var backward := Fixtures.blank_state(defs)
	for kind in kinds:
		Fixtures.add_connected(forward, defs, kind)
	var reversed := kinds.duplicate()
	reversed.reverse()
	for kind in reversed:
		Fixtures.add_connected(backward, defs, kind)
	for state in [forward, backward]:
		state.resources["energy"] = 4000
		state.resources["matter"] = 30000
	_run(forward, defs, 120)
	_run(backward, defs, 120)
	for rid in defs.resource_ids:
		assert_eq(forward.amount(rid), backward.amount(rid), "saldo de %s" % rid)
		assert_eq(forward.lifetime_produced[rid], backward.lifetime_produced[rid], "total de %s" % rid)
	return true


func test_same_inputs_give_same_hash() -> bool:
	var defs := Fixtures.defs()
	var first := _scripted_run(defs)
	var second := _scripted_run(defs)
	assert_eq(first, second, "duas execuções idênticas")
	return true


## Hash de referência: se mudar, o motor ou o arredondamento mudou.
## Calculado primeiro em x86_64; conferir também em arm64 (determinismo).
func test_golden_hash_of_scripted_run() -> bool:
	assert_eq(_scripted_run(Fixtures.defs()), "fb25ddf75503338160c345bc47a8d9eea9e87131664577245bbb735cb0fbf19a", "hash de referência")
	return true


func _scripted_run(defs: NxDefinitions) -> String:
	var state := NxGameState.new_game(defs)
	var bot := NxGreedyBot.new()
	for i in range(300):
		bot.act(state, defs)
		NxEconomyEngine.step(state, defs, DT)
	return state.state_hash()
