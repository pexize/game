class_name NxSession
extends RefCounted
## Ciclo de vida de uma partida: abrir (carregar + progresso offline + salvar)
## e fechar/suspender (salvar). A interface chama estas duas funções e não
## mexe em arquivos nem em saldos.


## Abre a partida. Sucesso: data = {state, new_game, offline (NxOfflineReport ou
## null), recovered, source, save_ok}. Falhas do carregamento (all_invalid,
## version_too_new) são devolvidas sem tocar nos arquivos: quem decide se
## começa um jogo novo é o jogador, via `new_game`.
static func start(manager: NxSaveManager, defs: NxDefinitions, now_unix: int) -> NxResult:
	var loaded := manager.load_latest(defs)
	if not loaded.ok:
		if loaded.code == "no_save":
			return new_game(manager, defs, now_unix)
		return loaded

	var state: NxGameState = loaded.data["state"]
	var report := NxOfflineCalculator.apply(state, defs, float(now_unix - int(loaded.data["saved_at"])))
	# Grava já com o progresso offline aplicado, para reabrir de novo não repeti-lo.
	var saved := manager.save(state, defs, now_unix)
	return NxResult.success({
		"state": state, "new_game": false, "offline": report,
		"recovered": loaded.data["recovered"], "source": loaded.data["source"],
		"save_ok": saved.ok,
	})


## Começa um jogo novo e o salva. Se havia um save inválido, ele é guardado em
## `save.corrupt.json` pelo próprio gerenciador, nunca apagado.
static func new_game(manager: NxSaveManager, defs: NxDefinitions, now_unix: int) -> NxResult:
	var state := NxGameState.new_game(defs)
	var saved := manager.save(state, defs, now_unix)
	return NxResult.success({
		"state": state, "new_game": true, "offline": null,
		"recovered": false, "source": "new", "save_ok": saved.ok,
	})


## Salva ao fechar, suspender ou no autosave.
static func suspend(manager: NxSaveManager, state: NxGameState, defs: NxDefinitions, now_unix: int) -> NxResult:
	return manager.save(state, defs, now_unix)
