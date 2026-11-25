extends "res://tests/framework/suite.gd"
## Progresso offline: tempo simulado, limite, eficiência, relógio, convergência.

const Fixtures := preload("res://tests/helpers/fixtures.gd")


func _defs() -> NxDefinitions:
	return Fixtures.defs_with_upgrades()


## Rede estável: geradores, Collectors e Analyzer, com estoque para não travar.
func _network(defs: NxDefinitions) -> NxGameState:
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 50000
	state.resources["matter"] = 200000
	for kind in ["generator", "generator", "collector", "collector", "analyzer"]:
		Fixtures.add_connected(state, defs, kind)
	return state


func _relative_difference(a: int, b: int) -> float:
	return absf(float(a - b)) / maxf(1.0, maxf(absf(float(a)), absf(float(b))))


# --- tempo e limites ----------------------------------------------------------------

func test_zero_elapsed_changes_nothing() -> bool:
	var defs := _defs()
	var state := _network(defs)
	var before := state.state_hash()
	var report := NxOfflineCalculator.apply(state, defs, 0.0)
	assert_eq(state.state_hash(), before)
	assert_eq(report.simulated_ms, 0)
	assert_eq(report.steps, 0)
	return true


func test_efficiency_applies_to_time() -> bool:
	# Só o Core: 1,0 de Energy por segundo. 1000 s de ausência a 70% = 700 s simulados.
	var defs := _defs()
	var state := Fixtures.blank_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 1000.0)
	assert_eq(report.simulated_ms, 700000)
	assert_eq(report.produced["energy"], 700000, "700 s x 1,0/s, em milésimos")
	assert_eq(state.time_ms, 700000, "o relógio do jogo avançou o tempo simulado")
	assert_false(report.capped)
	assert_false(report.suspicious)
	return true


func test_elapsed_is_capped() -> bool:
	var defs := _defs()
	var state := Fixtures.blank_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 100000.0)    # > 8 h
	assert_true(report.capped)
	assert_eq(report.simulated_ms, 20160000, "8 h x 70%")
	assert_eq(report.produced["energy"], 20160000)
	assert_eq(report.steps, 336, "passos de 60 s: não é segundo a segundo")
	return true


func test_gain_is_identical_at_the_cap_and_far_beyond_it() -> bool:
	var defs := _defs()
	var at_cap := _network(defs)
	var far_beyond := _network(defs)
	NxOfflineCalculator.apply(at_cap, defs, 28800.0)
	var report := NxOfflineCalculator.apply(far_beyond, defs, 60.0 * 24.0 * 3600.0)   # 60 dias
	assert_eq(far_beyond.state_hash(), at_cap.state_hash(), "relógio adiantado não rende mais que o teto")
	assert_true(report.suspicious, "ausência de 60 dias é marcada como suspeita")
	return true


func test_negative_elapsed_grants_nothing() -> bool:
	var defs := _defs()
	var state := _network(defs)
	var before := state.state_hash()
	var report := NxOfflineCalculator.apply(state, defs, -5000.0)
	assert_eq(state.state_hash(), before, "relógio para trás: sem ganho")
	assert_true(report.clock_went_back)
	assert_true(report.suspicious)
	assert_eq(report.simulated_ms, 0)
	return true


func test_last_step_is_partial() -> bool:
	var defs := _defs()
	var state := Fixtures.blank_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 100.0)       # 70 s = 60 s + 10 s
	assert_eq(report.steps, 2)
	assert_eq(state.time_ms, 70000, "o tempo simulado fecha exatamente")
	return true


# --- mesmas regras da partida ativa -----------------------------------------------------------

func test_offline_matches_second_by_second_simulation() -> bool:
	# Convergência: passos de 60 s contra passos de 1 s, mesma rede, mesmo tempo.
	var defs := _defs()
	var coarse := _network(defs)
	var fine := _network(defs)
	var report := NxOfflineCalculator.apply(coarse, defs, 7200.0)
	for i in range(report.simulated_ms / 1000):
		NxSimulation.tick(fine, defs, 1000)
	for rid in defs.resource_ids:
		assert_true(_relative_difference(coarse.amount(rid), fine.amount(rid)) < 0.01,
			"%s: %d contra %d" % [rid, coarse.amount(rid), fine.amount(rid)])
		assert_true(_relative_difference(coarse.lifetime_produced[rid], fine.lifetime_produced[rid]) < 0.01,
			"produzido de %s" % rid)
	return true


func _starved_state(defs: NxDefinitions) -> NxGameState:
	# Cinco Collectors e um Analyzer pedem 3,5 de Energy e o Core dá 1,0.
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 3000
	state.resources["matter"] = 100000
	for kind in ["collector", "collector", "collector", "collector", "collector", "analyzer"]:
		Fixtures.add_connected(state, defs, kind)
	return state


func test_offline_is_accurate_under_shortage() -> bool:
	# Eficiência exata do Analyzer = 1,0 / 3,5. Em 3600 s simulados ele produz
	# 3600 x 100 x (1/3,5) = 102857 milésimos de Data. O passo offline de 60 s
	# precisa ficar muito perto disso.
	var defs := _defs()
	var state := _starved_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 3600.0 / 0.7)
	assert_eq(report.simulated_ms, 3600000)
	assert_true(_relative_difference(report.produced["data"], 102857) < 0.01,
		"Data produzido: %d (exato 102857)" % report.produced["data"])
	return true


func test_one_second_step_loses_precision_under_shortage_by_rounding() -> bool:
	# LIMITAÇÃO CONHECIDA (D-030): o passo ativo de 1 s arredonda para baixo em
	# milésimos, e com eficiência fracionária numa taxa pequena (Data a 0,1/s)
	# isso perde até ~2%. O passo offline é MAIS exato, não menos. Este teste
	# fixa o limite do viés: sempre para baixo, nunca para cima, e abaixo de 3%.
	var defs := _defs()
	var fine := _starved_state(defs)
	for i in range(3600):
		NxSimulation.tick(fine, defs, 1000)
	var exact := 102857
	assert_true(fine.lifetime_produced["data"] <= exact, "o arredondamento nunca cria recursos")
	assert_true(_relative_difference(fine.lifetime_produced["data"], exact) < 0.03, "viés abaixo de 3%%: %d" % fine.lifetime_produced["data"])
	return true


func test_offline_uses_the_current_network_not_a_constant_rate() -> bool:
	# Estoque pequeno e consumo maior que a produção: o gargalo aparece durante a
	# ausência, e a taxa do instante de fechar não se mantém.
	var defs := _defs()
	var state := Fixtures.blank_state(defs)
	state.resources["energy"] = 100000
	state.resources["matter"] = 1000
	for kind in ["analyzer", "analyzer", "analyzer", "analyzer", "analyzer"]:
		Fixtures.add_connected(state, defs, kind)
	var report := NxOfflineCalculator.apply(state, defs, 3600.0)
	var constant_rate_matter := 5 * 200 * 2520              # 5 Analyzers x 0,2/s x 2520 s, em milésimos
	assert_true(state.amount("matter") == 0, "Matter acabou e não ficou negativa")
	assert_true(report.produced["data"] < 5 * 100 * 2520, "Data produzido ficou abaixo do que a taxa inicial prometia")
	assert_true(constant_rate_matter > 1000, "sanidade do cenário")
	return true


func test_discoveries_are_granted_and_reported_while_away() -> bool:
	var defs := _defs()
	var state := Fixtures.blank_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 600.0)
	assert_eq(report.discoveries, ["grants"])
	assert_true(state.has_feature("automation"), "as recompensas foram aplicadas")
	return true


func test_resources_never_negative_or_above_the_cap_after_a_long_absence() -> bool:
	var defs := _defs()
	var state := _network(defs)
	state.upgrades = {"gen_up": 3, "col_eff": 2}
	NxAutomation.configure(state, defs, true, "gen_up") if state.has_feature("automation") else null
	NxOfflineCalculator.apply(state, defs, 40000.0)
	for rid in defs.resource_ids:
		assert_true(state.amount(rid) >= 0, "%s não negativo" % rid)
		var cap := defs.max_storage(rid)
		assert_true(cap == NxDefinitions.UNLIMITED or state.amount(rid) <= cap, "%s dentro do limite" % rid)
	assert_eq(NxNetwork.validate(state, defs).size(), 0, "a árvore continua válida")
	return true


func test_report_deltas_match_the_state_change() -> bool:
	var defs := _defs()
	var state := _network(defs)
	var before := state.resources.duplicate()
	var produced_before := state.lifetime_produced.duplicate()
	var report := NxOfflineCalculator.apply(state, defs, 1800.0)
	for rid in defs.resource_ids:
		assert_eq(report.resource_delta[rid], state.amount(rid) - before[rid], "variação de %s" % rid)
		assert_eq(report.produced[rid], state.lifetime_produced[rid] - produced_before[rid], "produzido de %s" % rid)
	return true


# --- automação offline -----------------------------------------------------------------------------

func _automated_state(defs: NxDefinitions) -> NxGameState:
	var state := Fixtures.blank_state(defs)
	for feature in ["production_upgrades", "data_upgrades", "automation"]:
		state.features[feature] = true
	state.resources["matter"] = 1000000000
	state.discoveries["grants"] = {"order": 1, "time_ms": 0}
	NxAutomation.configure(state, defs, true, "gen_up")
	return state


func test_automation_buys_while_away_up_to_its_limit() -> bool:
	var defs := _defs()
	defs.balance["offline_auto_purchase_limit"] = 3
	var state := _automated_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 3600.0)
	assert_eq(NxUpgrades.level(state, "gen_up"), 3, "parou no limite da ausência")
	assert_eq(report.purchases, {"gen_up": 3})
	assert_true(report.purchase_limit_reached)
	return true


func test_automation_below_the_limit_is_not_flagged() -> bool:
	var defs := _defs()
	var state := _automated_state(defs)                  # limite 20, a melhoria só vai a 4
	var report := NxOfflineCalculator.apply(state, defs, 3600.0)
	assert_eq(NxUpgrades.level(state, "gen_up"), 4, "chegou ao nível máximo")
	assert_false(report.purchase_limit_reached)
	return true


func test_zero_limit_disables_offline_purchases() -> bool:
	var defs := _defs()
	defs.balance["offline_auto_purchase_limit"] = 0
	var state := _automated_state(defs)
	var report := NxOfflineCalculator.apply(state, defs, 3600.0)
	assert_eq(NxUpgrades.level(state, "gen_up"), 0)
	assert_eq(report.purchases, {})
	return true
