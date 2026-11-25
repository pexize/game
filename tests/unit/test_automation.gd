extends "res://tests/framework/suite.gd"
## Automação: compra automática da melhoria escolhida.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const DT := 1000


func _ready_state(defs: NxDefinitions, matter: int = 100000) -> NxGameState:
	var state := Fixtures.blank_state(defs)
	for feature in ["production_upgrades", "data_upgrades", "automation"]:
		state.features[feature] = true
	state.resources["matter"] = matter
	return state


func test_configure_requires_the_automation_feature() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := Fixtures.blank_state(defs)
	var result := NxAutomation.configure(state, defs, true, "gen_up")
	assert_eq(result.code, "locked")
	assert_false(state.automation["enabled"], "nada foi ligado")
	return true


func test_configure_validates_the_target() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs)
	assert_eq(NxAutomation.configure(state, defs, true, "fantasma").code, "unknown_upgrade")
	assert_true(NxAutomation.configure(state, defs, true, "gen_up").ok)
	assert_eq(state.automation, {"enabled": true, "target": "gen_up"})
	assert_true(NxAutomation.configure(state, defs, false, "").ok, "desligar e limpar é permitido")
	assert_eq(state.automation, {"enabled": false, "target": ""})
	return true


func test_buys_the_selected_upgrade_when_affordable() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs)
	NxAutomation.configure(state, defs, true, "gen_up")
	var first := NxSimulation.tick(state, defs, DT)
	assert_eq(first.auto_purchases, [{"id": "gen_up", "level": 1}])
	assert_eq(state.amount("matter"), 80000, "custo debitado uma vez")
	var second := NxSimulation.tick(state, defs, DT)
	assert_eq(second.auto_purchases, [{"id": "gen_up", "level": 2}])
	assert_eq(state.amount("matter"), 48000, "o nível 2 custa mais")
	return true


func test_stops_when_it_can_no_longer_afford() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs)                         # 100 de Matter: níveis 1 e 2 cabem, o 3 não
	NxAutomation.configure(state, defs, true, "gen_up")
	NxSimulation.tick(state, defs, DT)
	NxSimulation.tick(state, defs, DT)
	var third := NxSimulation.tick(state, defs, DT)
	assert_eq(third.auto_purchases, [], "51,2 > 48")
	assert_eq(NxUpgrades.level(state, "gen_up"), 2)
	assert_eq(state.amount("matter"), 48000, "nada cobrado")
	return true


func test_resumes_when_resources_arrive() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs, 20000)
	NxAutomation.configure(state, defs, true, "gen_up")
	NxSimulation.tick(state, defs, DT)
	assert_eq(NxUpgrades.level(state, "gen_up"), 1)
	NxSimulation.tick(state, defs, DT)
	assert_eq(NxUpgrades.level(state, "gen_up"), 1, "sem Matter")
	state.resources["matter"] = 32000
	NxSimulation.tick(state, defs, DT)
	assert_eq(NxUpgrades.level(state, "gen_up"), 2, "voltou a comprar")
	return true


func test_at_most_one_purchase_per_tick() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs, 100000000)
	NxAutomation.configure(state, defs, true, "gen_up")
	var report := NxSimulation.tick(state, defs, DT)
	assert_eq(report.auto_purchases.size(), 1)
	assert_eq(NxUpgrades.level(state, "gen_up"), 1)
	return true


func test_does_nothing_when_disabled() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs)
	NxAutomation.configure(state, defs, false, "gen_up")
	var report := NxSimulation.tick(state, defs, DT)
	assert_eq(report.auto_purchases, [])
	assert_eq(NxUpgrades.level(state, "gen_up"), 0)
	return true


func test_does_nothing_without_the_feature_even_if_state_says_enabled() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := Fixtures.blank_state(defs)
	state.features["production_upgrades"] = true
	state.resources["matter"] = 100000
	state.automation = {"enabled": true, "target": "gen_up"}   # estado adulterado
	# Chamada direta: o tick completo concederia o recurso pela descoberta de teste.
	assert_false(state.has_feature("automation"))
	assert_eq(NxAutomation.run(state, defs), [])
	assert_eq(state.amount("matter"), 100000, "nada foi cobrado")
	assert_eq(NxUpgrades.level(state, "gen_up"), 0)
	return true


func test_stops_quietly_at_max_level() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs, 1000000000)
	state.upgrades["gen_up"] = 4
	NxAutomation.configure(state, defs, true, "gen_up")
	var before := state.amount("matter")
	var report := NxSimulation.tick(state, defs, DT)
	assert_eq(report.auto_purchases, [])
	assert_eq(state.amount("matter"), before)
	return true


func test_follows_the_same_rules_as_manual_purchase() -> bool:
	# global_up exige gen_up: a automação não pode pular o pré-requisito.
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs, 1000000)
	state.resources["data"] = 100000
	NxAutomation.configure(state, defs, true, "global_up")
	var report := NxSimulation.tick(state, defs, DT)
	assert_eq(report.auto_purchases, [], "falta o pré-requisito")
	assert_eq(NxUpgrades.level(state, "global_up"), 0)
	return true


func test_runs_after_discoveries_in_the_same_tick() -> bool:
	# A descoberta "grants" libera a automação e as melhorias neste mesmo
	# tick; como a automação roda depois, já compra nele (ordem do pipeline).
	var defs := Fixtures.defs_with_upgrades()
	var state := Fixtures.blank_state(defs)
	state.resources["matter"] = 100000
	state.automation = {"enabled": true, "target": "gen_up"}
	var report := NxSimulation.tick(state, defs, DT)
	assert_eq(report.granted, ["grants"])
	assert_eq(report.auto_purchases, [{"id": "gen_up", "level": 1}])
	return true


func test_automation_settings_round_trip() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _ready_state(defs)
	NxAutomation.configure(state, defs, true, "gen_up")
	var copy := NxGameState.from_dict(state.to_dict())
	assert_eq(copy.automation, {"enabled": true, "target": "gen_up"})
	assert_eq(copy.state_hash(), state.state_hash())
	return true


func test_automation_improves_the_economy_over_time() -> bool:
	# "Melhorias alteram efetivamente o sistema": com a automação o Core
	# acumula mais Energy do que sem ela, no mesmo tempo.
	var defs := Fixtures.defs_with_upgrades()
	var with_auto := _ready_state(defs, 1000000)
	var without := _ready_state(defs, 1000000)
	for state in [with_auto, without]:
		Fixtures.add_connected(state, defs, "generator")
	NxAutomation.configure(with_auto, defs, true, "gen_up")
	for i in range(30):
		NxSimulation.tick(with_auto, defs, DT)
		NxSimulation.tick(without, defs, DT)
	assert_eq(NxUpgrades.level(with_auto, "gen_up"), 4, "chegou ao nível máximo")
	assert_true(with_auto.lifetime_produced["energy"] > without.lifetime_produced["energy"], "produziu mais")
	return true
