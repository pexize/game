extends "res://tests/framework/suite.gd"
## Ledger (saldos) e BuildService (construção atômica).

const Fixtures := preload("res://tests/helpers/fixtures.gd")


func test_new_game_starts_valid() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	assert_eq(state.amount("energy"), 5000)
	assert_eq(state.amount("matter"), 10000)
	assert_eq(state.amount("data"), 0)
	assert_eq(state.count_of("core"), 1, "um Core")
	assert_true(state.is_unlocked("generator"))
	assert_false(state.is_unlocked("fantasma"), "desconhecido não está liberado")
	return true


func test_spend_is_atomic() -> bool:
	var state := NxGameState.new_game(Fixtures.defs())
	var before := state.state_hash()
	# energy basta (5000), matter não (pede 20000 e há 10000).
	var spent := NxLedger.try_spend(state, {"energy": 1000, "matter": 20000})
	assert_false(spent, "gasto parcial deve ser recusado")
	assert_eq(state.state_hash(), before, "nada deve mudar quando recusa")
	return true


func test_spend_debits_all_resources() -> bool:
	var state := NxGameState.new_game(Fixtures.defs())
	assert_true(NxLedger.try_spend(state, {"energy": 1000, "matter": 4000}))
	assert_eq(state.amount("energy"), 4000)
	assert_eq(state.amount("matter"), 6000)
	return true


func test_spend_exact_balance_to_zero() -> bool:
	var state := NxGameState.new_game(Fixtures.defs())
	assert_true(NxLedger.try_spend(state, {"energy": 5000}))
	assert_eq(state.amount("energy"), 0, "saldo zero é permitido, negativo não")
	assert_false(NxLedger.try_spend(state, {"energy": 1}), "não gasta de saldo zero")
	return true


func test_credit_respects_storage_cap() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 99500
	var lost := NxLedger.credit(state, defs, "energy", 1000)
	assert_eq(state.amount("energy"), 100000, "limitado ao máximo")
	assert_eq(lost, 500, "perda por excesso")
	assert_eq(NxLedger.credit(state, defs, "matter", 1000000), 0, "matter não tem limite")
	assert_eq(state.amount("matter"), 1010000)
	return true


func test_credit_ignores_non_positive_amounts() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	NxLedger.credit(state, defs, "energy", -500)
	assert_eq(state.amount("energy"), 5000, "crédito negativo não altera o saldo")
	return true


func test_build_rejects_locked_component() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.unlocked.erase("generator")
	state.resources["energy"] = 50000
	var result := NxBuildService.build(state, defs, "generator")
	assert_false(result.ok)
	assert_eq(result.code, "locked")
	assert_eq(state.amount("energy"), 50000, "nada cobrado")
	return true


func test_build_rejects_unknown_component() -> bool:
	var defs := Fixtures.defs()
	var result := NxBuildService.build(NxGameState.new_game(defs), defs, "fantasma")
	assert_eq(result.code, "unknown_component")
	return true


func test_build_rejects_insufficient_resources_without_side_effects() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)  # energy 5000, generator custa 10000
	var before := state.state_hash()
	var result := NxBuildService.build(state, defs, "generator")
	assert_eq(result.code, "insufficient_resources")
	assert_eq(state.state_hash(), before, "estado intacto")
	return true


func test_build_success_debits_and_creates_instance() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 12000
	var result := NxBuildService.build(state, defs, "generator")
	assert_true(result.ok)
	assert_eq(state.amount("energy"), 2000, "custo debitado")
	assert_eq(state.count_of("generator"), 1)
	assert_eq(result.data["instance_id"], 2, "Core é o 1; o novo é o 2")
	return true


func test_build_respects_limit() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.unlocked["core"] = true  # mesmo "desbloqueado", o limite 1 vale
	var result := NxBuildService.build(state, defs, "core")
	assert_eq(result.code, "limit_reached")
	assert_eq(state.count_of("core"), 1)
	return true


func test_state_round_trips_through_dict() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 12000
	NxBuildService.build(state, defs, "generator")
	NxEconomyEngine.step(state, defs, 1000)
	var copy := NxGameState.from_dict(state.to_dict())
	assert_eq(copy.state_hash(), state.state_hash(), "hash igual após ida e volta")
	assert_eq(copy.count_of("generator"), 1)
	return true


func test_state_round_trips_through_json_text() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 12000
	NxBuildService.build(state, defs, "generator")
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(state.to_dict())), OK, "JSON válido")
	var copy := NxGameState.from_dict(json.data)
	assert_eq(copy.state_hash(), state.state_hash(), "números inteiros sobrevivem ao JSON")
	return true
