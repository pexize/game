extends "res://tests/framework/suite.gd"
## Cenários de jogo com os dados reais de `data/`: alcançabilidade,
## ausência de bloqueio e invariantes ao longo de uma partida completa.

const DT := 1000


func _defs() -> NxDefinitions:
	return NxDefinitions.load_from_dir("res://data")


## Joga `seconds` com o plano dado e confere os invariantes a cada passo:
## saldos dentro dos limites e árvore de conexões válida.
func _play(plan: Array, seconds: int, defs: NxDefinitions) -> NxGameState:
	var state := NxGameState.new_game(defs)
	var bot := NxGreedyBot.new(plan)
	for second in range(seconds):
		bot.act(state, defs)
		NxSimulation.tick(state, defs, DT)
		var tree_errors := NxNetwork.validate(state, defs)
		if not tree_errors.is_empty():
			fail("árvore inválida em %ds: %s" % [second, tree_errors[0]])
			return state
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


func test_default_plan_completes_every_discovery() -> bool:
	var defs := _defs()
	var state := _play(NxGreedyBot.DEFAULT_PLAN, 1500, defs)
	for id in defs.discovery_order:
		assert_true(state.has_discovery(id), "descoberta '%s' foi concedida" % id)
	assert_eq(state.stage, 2, "Stage II alcançado")
	for feature in ["data_upgrades", "efficiency_upgrades", "automation", "advanced_upgrades"]:
		assert_true(state.has_feature(feature), "recurso '%s' liberado" % feature)
	return true


func test_discoveries_are_granted_after_their_prerequisites() -> bool:
	var defs := _defs()
	var state := _play(NxGreedyBot.DEFAULT_PLAN, 1500, defs)
	for id in defs.discovery_order:
		if not state.has_discovery(id):
			continue
		for prereq: String in defs.discoveries[id]["prerequisites"]:
			assert_true(
				state.discoveries[prereq]["order"] < state.discoveries[id]["order"],
				"'%s' vem antes de '%s'" % [prereq, id])
	return true


func test_components_stay_locked_until_their_discovery() -> bool:
	var defs := _defs()
	var state := NxGameState.new_game(defs)
	state.resources["matter"] = 500000
	for locked in ["collector", "analyzer", "relay", "processor"]:
		assert_eq(NxBuildService.build(state, defs, locked).code, "locked", "%s começa bloqueado" % locked)
	return true


func test_first_discovery_unlocks_the_collector() -> bool:
	var defs := _defs()
	var state := _play([["generator", 1]], 10, defs)
	assert_true(state.has_discovery("first_connection"), "D1 com um componente ligado")
	assert_true(state.is_unlocked("collector"), "Collector liberado pela recompensa")
	return true


func test_idle_player_makes_no_discovery_and_never_stalls() -> bool:
	# Sem construir nada nenhuma descoberta é possível, mas o Core segue gerando.
	var defs := _defs()
	var state := _play([], 3600, defs)
	assert_eq(state.discoveries.size(), 0, "nada a descobrir sem construir")
	assert_true(state.amount("energy") > 5000, "Core sozinho continua gerando Energy")
	return true


func test_waiting_alone_never_grows_matter() -> bool:
	# Documenta a dependência: sem Collector, Matter não cresce.
	var defs := _defs()
	var state := _play([], 1800, defs)
	assert_eq(state.amount("matter"), 10000, "Matter parada sem Collector")
	return true


func test_discovery_timeline_is_reasonable_for_short_sessions() -> bool:
	# Meta de design (VISION): sessões de 2 a 5 minutos. A primeira descoberta
	# e a segunda precisam chegar cedo; os números ainda são provisórios.
	var defs := _defs()
	var state := _play(NxGreedyBot.DEFAULT_PLAN, 600, defs)
	assert_true(state.has_discovery("first_connection"))
	assert_true(state.discoveries["first_connection"]["time_ms"] <= 10000, "D1 em até 10 s")
	assert_true(state.has_discovery("production_cycle"), "D2 antes dos 10 min")
	assert_true(state.discoveries["production_cycle"]["time_ms"] <= 300000, "D2 em até 5 min")
	return true
