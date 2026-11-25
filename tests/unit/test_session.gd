extends "res://tests/framework/suite.gd"
## Sessão: abrir (carregar + offline + salvar) e fechar. Cobre o critério de
## saída da Fase 5: fechar e reabrir preserva o estado e aplica o offline.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const T0 := 1700000000


func _defs() -> NxDefinitions:
	return Fixtures.defs_with_upgrades()


func _manager(name: String) -> NxSaveManager:
	return NxSaveManager.new(Fixtures.temp_dir(name))


func _play(state: NxGameState, defs: NxDefinitions, seconds: int) -> void:
	var bot := NxGreedyBot.new()
	for i in range(seconds):
		bot.act(state, defs)
		NxSimulation.tick(state, defs, 1000)


func test_first_launch_creates_and_saves_a_new_game() -> bool:
	var defs := _defs()
	var manager := _manager("session_new")
	var result := NxSession.start(manager, defs, T0)
	assert_true(result.ok)
	assert_true(result.data["new_game"])
	assert_eq(result.data["offline"], null, "sem ausência para recuperar")
	assert_eq(result.data["state"].state_hash(), NxGameState.new_game(defs).state_hash())
	assert_true(result.data["save_ok"])
	assert_true(FileAccess.file_exists(manager.path_of("save.json")))
	Fixtures.remove_dir(manager.dir)
	return true


func test_close_and_reopen_preserves_state_and_applies_offline() -> bool:
	var defs := _defs()
	var manager := _manager("session_reopen")
	var state := NxGameState.new_game(defs)
	_play(state, defs, 120)
	assert_true(NxSession.suspend(manager, state, defs, T0).ok)
	var saved_hash := state.state_hash()

	# O que foi salvo é exatamente o que estava na tela.
	assert_eq(manager.load_latest(defs).data["state"].state_hash(), saved_hash, "salvo = em jogo")

	var reopened := NxSession.start(manager, defs, T0 + 3600)       # uma hora depois
	assert_true(reopened.ok)
	assert_false(reopened.data["new_game"])
	var report: NxOfflineReport = reopened.data["offline"]
	assert_eq(report.simulated_ms, 2520000, "1 h x 70%")
	var after: NxGameState = reopened.data["state"]
	assert_eq(after.time_ms, state.time_ms + 2520000, "o tempo do jogo avançou")
	assert_true(after.lifetime_produced["energy"] > state.lifetime_produced["energy"], "houve produção offline")
	assert_eq(after.components.size(), state.components.size(), "a rede foi preservada")
	assert_true(reopened.data["save_ok"])
	Fixtures.remove_dir(manager.dir)
	return true


func test_reopening_again_does_not_repeat_the_offline_gain() -> bool:
	var defs := _defs()
	var manager := _manager("session_idempotent")
	var state := NxGameState.new_game(defs)
	_play(state, defs, 60)
	NxSession.suspend(manager, state, defs, T0)
	var first := NxSession.start(manager, defs, T0 + 7200)
	var second := NxSession.start(manager, defs, T0 + 7200)         # abre de novo no mesmo instante
	assert_eq(second.data["offline"].simulated_ms, 0, "o save já tem a data de agora")
	assert_eq(second.data["state"].state_hash(), first.data["state"].state_hash(), "nada foi contado duas vezes")
	Fixtures.remove_dir(manager.dir)
	return true


func test_clock_set_back_gives_no_gain_and_does_not_lose_progress() -> bool:
	var defs := _defs()
	var manager := _manager("session_clock")
	var state := NxGameState.new_game(defs)
	_play(state, defs, 60)
	NxSession.suspend(manager, state, defs, T0)
	var reopened := NxSession.start(manager, defs, T0 - 86400)       # relógio um dia atrás
	assert_true(reopened.data["offline"].clock_went_back)
	assert_eq(reopened.data["state"].state_hash(), state.state_hash(), "estado igual, sem ganho")
	assert_true(reopened.data["save_ok"])
	Fixtures.remove_dir(manager.dir)
	return true


func test_a_very_long_absence_is_capped() -> bool:
	var defs := _defs()
	var manager := _manager("session_cap")
	var state := NxGameState.new_game(defs)
	_play(state, defs, 60)
	NxSession.suspend(manager, state, defs, T0)
	var reopened := NxSession.start(manager, defs, T0 + 90 * 86400)  # 90 dias
	var report: NxOfflineReport = reopened.data["offline"]
	assert_true(report.capped)
	assert_true(report.suspicious)
	assert_eq(report.simulated_ms, 20160000, "no máximo 8 h x 70%")
	Fixtures.remove_dir(manager.dir)
	return true


func test_reopen_recovers_from_a_corrupt_save() -> bool:
	var defs := _defs()
	var manager := _manager("session_recover")
	var state := NxGameState.new_game(defs)
	_play(state, defs, 60)
	NxSession.suspend(manager, state, defs, T0)
	_play(state, defs, 60)
	NxSession.suspend(manager, state, defs, T0 + 60)                  # bak1 = o de T0
	Fixtures.write_file(manager.path_of("save.json"), "corrompido")
	var reopened := NxSession.start(manager, defs, T0 + 660)
	assert_true(reopened.ok)
	assert_true(reopened.data["recovered"])
	assert_eq(reopened.data["source"], "backup1")
	assert_eq(reopened.data["offline"].elapsed_s, 660.0, "ausência contada a partir do backup (T0)")
	Fixtures.remove_dir(manager.dir)
	return true


func test_unusable_saves_are_reported_and_never_auto_replaced() -> bool:
	var defs := _defs()
	var manager := _manager("session_invalid")
	var state := NxGameState.new_game(defs)
	NxSession.suspend(manager, state, defs, T0)
	Fixtures.write_file(manager.path_of("save.json"), "lixo")
	var before := Fixtures.read_file(manager.path_of("save.json"))
	var result := NxSession.start(manager, defs, T0 + 100)
	assert_false(result.ok)
	assert_eq(result.code, "all_invalid")
	assert_eq(Fixtures.read_file(manager.path_of("save.json")), before, "nada foi sobrescrito sem o jogador decidir")
	# Se o jogador escolhe começar de novo, o arquivo ruim fica guardado.
	var fresh := NxSession.new_game(manager, defs, T0 + 200)
	assert_true(fresh.data["save_ok"])
	assert_eq(Fixtures.read_file(manager.path_of("save.corrupt.json")), before, "o corrompido foi preservado")
	Fixtures.remove_dir(manager.dir)
	return true


func test_a_newer_save_blocks_the_session_and_is_never_overwritten() -> bool:
	var defs := _defs()
	var manager := _manager("session_newer")
	var payload := {"schema_version": 99, "game_version": "futuro", "saved_at": T0,
		"state": NxGameState.new_game(defs).to_dict()}
	Fixtures.write_file(manager.path_of("save.json"), NxSaveManager._encode(payload))
	var before := Fixtures.read_file(manager.path_of("save.json"))
	var result := NxSession.start(manager, defs, T0 + 100)
	assert_eq(result.code, "version_too_new")
	var fresh := NxSession.new_game(manager, defs, T0 + 200)
	assert_false(fresh.data["save_ok"], "o jogo novo não pode apagar o save da versão futura")
	assert_eq(Fixtures.read_file(manager.path_of("save.json")), before)
	Fixtures.remove_dir(manager.dir)
	return true


func test_full_flow_with_the_real_game_data() -> bool:
	# Critério de saída da Fase 5 com os dados reais de data/.
	var defs := NxDefinitions.load_from_dir("res://data")
	var manager := _manager("session_real")
	var state := NxGameState.new_game(defs)
	var bot := NxGreedyBot.new()
	for i in range(240):
		bot.act(state, defs)
		NxSimulation.tick(state, defs, 1000)
	assert_true(state.discoveries.size() >= 5, "o jogo avançou antes de fechar")
	assert_true(NxSession.suspend(manager, state, defs, T0).ok)
	var reopened := NxSession.start(manager, defs, T0 + 12 * 3600)   # 12 h fora
	assert_true(reopened.ok)
	var after: NxGameState = reopened.data["state"]
	assert_true(reopened.data["offline"].capped, "12 h passam do limite de 8 h")
	assert_eq(reopened.data["offline"].simulated_ms, 20160000)
	assert_true(after.discoveries.size() >= state.discoveries.size(), "nenhuma descoberta se perdeu")
	assert_eq(NxStateValidator.validate_state(after, defs).size(), 0, "o estado resultante é válido")
	assert_true(reopened.data["save_ok"])
	Fixtures.remove_dir(manager.dir)
	return true
