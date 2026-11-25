extends "res://tests/framework/suite.gd"
## Cenários de jogo com os dados reais de `data/`: alcançabilidade
## econômica, ausência de bloqueio e invariantes ao longo de uma partida.

const DT := 1000


func _defs() -> NxDefinitions:
	return NxDefinitions.load_from_dir("res://data")


## Joga até `seconds` com o plano dado; confere os invariantes a cada passo.
func _play(plan: Array, seconds: int, defs: NxDefinitions) -> NxGameState:
	var state := NxGameState.new_game(defs)
	var bot := NxGreedyBot.new(plan)
	for second in range(seconds):
		bot.act(state, defs)
		NxEconomyEngine.step(state, defs, DT)
		for rid in defs.resource_ids:
			var amount := state.amount(rid)
			if amount < 0:
				fail("%s negativo (%d) em %ds" % [rid, amount, second])
				return state
			var cap := defs.max_storage(rid)
			if cap != NxDefinitions.UNLIMITED and amount > cap:
				fail("%s acima do limite em %ds" % [rid, second])
				return state
	return state


func test_default_plan_reaches_data_production() -> bool:
	var defs := _defs()
	var state := _play(NxGreedyBot.DEFAULT_PLAN, 900, defs)
	assert_eq(state.count_of("analyzer"), 2, "o plano completo foi construído")
	assert_true(state.lifetime_produced["data"] > 0, "Data foi produzido")
	return true


func test_no_soft_lock_when_collector_is_built_first() -> bool:
	# D-014: mesmo gastando a reserva de Matter no Collector antes do
	# Generator, o jogador ainda consegue chegar ao Generator.
	var defs := _defs()
	var plan := [["collector", 1], ["generator", 1], ["analyzer", 1]]
	var state := _play(plan, 900, defs)
	assert_eq(state.count_of("generator"), 1, "Generator foi construído")
	assert_eq(state.count_of("analyzer"), 1, "Analyzer foi construído")
	assert_true(state.amount("data") > 0, "Data acumulado")
	return true


func test_no_soft_lock_when_analyzer_is_attempted_early() -> bool:
	# Esperar o Analyzer (25 Matter) com um único Collector ainda termina.
	var defs := _defs()
	var state := _play([["collector", 1], ["analyzer", 1]], 900, defs)
	assert_eq(state.count_of("analyzer"), 1)
	return true


func test_idle_player_never_goes_negative_or_stalls_energy() -> bool:
	var defs := _defs()
	var state := _play([], 3600, defs)
	assert_true(state.amount("energy") > 5000, "Core sozinho continua gerando Energy")
	return true


func test_every_start_unlocked_component_is_buildable() -> bool:
	# Todo componente liberado no início é construível por um jogador que
	# monta primeiro a fonte de Matter (Collector) e depois o componente.
	var defs := _defs()
	for def_id: String in defs.balance["start_unlocked"]:
		var plan: Array = [["collector", 1], [def_id, 1]]
		if def_id == "collector":
			plan = [["collector", 1]]
		var state := _play(plan, 1800, defs)
		assert_true(state.count_of(def_id) >= 1, "%s é construível partindo do início" % def_id)
	return true


func test_waiting_alone_never_builds_matter_costing_components() -> bool:
	# Documenta a dependência de propósito: sem Collector, Matter não
	# cresce, então componentes que custam mais que a reserva exigem um
	# Collector antes (a descoberta D1 libera o Collector na Fase 3).
	var defs := _defs()
	var state := _play([], 1800, defs)
	assert_eq(state.amount("matter"), 10000, "Matter fica parada sem Collector")
	return true
