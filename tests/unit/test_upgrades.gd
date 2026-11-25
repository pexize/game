extends "res://tests/framework/suite.gd"
## Melhorias: validação, curva de custo, compra atômica e efeito no motor.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const DT := 1000


func _state(defs: NxDefinitions, features: Array = ["production_upgrades", "data_upgrades"]) -> NxGameState:
	var state := Fixtures.blank_state(defs)
	for feature: String in features:
		state.features[feature] = true
	return state


func _error_text(raw_upgrades: Array, discoveries: Array = [Fixtures.raw_feature_discovery()]) -> String:
	var defs := NxDefinitions.from_dicts(Fixtures.raw_resources(), Fixtures.raw_components(),
		Fixtures.raw_balance(), discoveries, raw_upgrades)
	return "\n".join(defs.errors)


func _upgrade(overrides: Dictionary = {}) -> Dictionary:
	var raw: Dictionary = Fixtures.raw_upgrades()[0].duplicate(true)
	raw.merge(overrides, true)
	return raw


# --- validação ---------------------------------------------------------------

func test_real_upgrades_are_valid() -> bool:
	var defs := NxDefinitions.load_from_dir("res://data")
	assert_eq("\n".join(defs.errors), "")
	assert_true(defs.upgrades.size() >= 5, "melhorias carregadas")
	return true


func test_fixture_upgrades_are_valid() -> bool:
	assert_eq("\n".join(Fixtures.defs_with_upgrades().errors), "")
	return true


func test_rejects_bad_references_and_fields() -> bool:
	var errors := _error_text([
		_upgrade({"id": "a", "target": "fantasma"}),
		_upgrade({"id": "b", "cost": {"plasma": 5}}),
		_upgrade({"id": "c", "prerequisites": ["nada"]}),
		_upgrade({"id": "d", "typo": 1}),
		_upgrade({"id": "e", "cost": {}}),
	])
	for fragment in ["fantasma", "plasma", "nada", "typo", "'cost' deve ser um objeto não vazio"]:
		assert_true(errors.contains(fragment), "deve apontar: %s" % fragment)
	return true


func test_rejects_out_of_range_numbers() -> bool:
	var errors := _error_text([
		_upgrade({"id": "a", "max_level": 0}),
		_upgrade({"id": "b", "max_level": 101}),
		_upgrade({"id": "c", "growth": 0.9}),
		_upgrade({"id": "d", "growth": 11}),
		_upgrade({"id": "e", "effect": {"type": "output_multiplier", "per_level": 0}}),
	])
	assert_true(errors.contains("'max_level'"), "nível máximo")
	assert_true(errors.contains("'growth'"), "crescimento")
	assert_true(errors.contains("per_level"), "efeito por nível")
	return true


func test_rejects_category_and_effect_mismatch() -> bool:
	var errors := _error_text([
		_upgrade({"id": "a", "category": "efficiency"}),   # output_multiplier é de production
		_upgrade({"id": "b", "effect": {"type": "magia", "per_level": 1}}),
	])
	assert_true(errors.contains("pertence à categoria"), errors)
	assert_true(errors.contains("'magia'"), errors)
	return true


func test_rejects_input_reduction_that_reaches_zero() -> bool:
	var errors := _error_text([_upgrade({"id": "a", "category": "efficiency", "target": "collector",
		"effect": {"type": "input_multiplier", "per_level": 0.25}, "max_level": 4})])
	assert_true(errors.contains("cairia abaixo"), "4 x 25% zeraria o consumo: " + errors)
	return true


func test_rejects_targets_that_cannot_be_affected() -> bool:
	var errors := _error_text([
		_upgrade({"id": "a", "category": "efficiency", "target": "generator",
			"effect": {"type": "input_multiplier", "per_level": 0.1}}),   # Generator não consome
		_upgrade({"id": "b", "target": "relay"}),                          # Relay não produz
	])
	assert_true(errors.contains("não consome nada"), errors)
	assert_true(errors.contains("não produz nada"), errors)
	return true


func test_rejects_prerequisite_cycles_and_duplicates() -> bool:
	var errors := _error_text([
		_upgrade({"id": "a", "prerequisites": ["b"]}),
		_upgrade({"id": "b", "prerequisites": ["a"]}),
		_upgrade({"id": "a"}),
	])
	assert_true(errors.contains("circulares"), errors)
	assert_true(errors.contains("duplicado"), errors)
	return true


func test_rejects_unreachable_features_and_resources() -> bool:
	var never_granted := _error_text([_upgrade({"id": "a", "requires_features": ["segredo"]})])
	assert_true(never_granted.contains("nunca é liberado"), never_granted)
	var unproducible := _error_text([_upgrade({"id": "b", "cost": {"data": 5}})], [])
	assert_true(unproducible.contains("nenhum componente liberado produz 'data'") or unproducible.contains("nunca é liberado"), unproducible)
	return true


# --- curva de custo ------------------------------------------------------------

func test_cost_curve_matches_base_times_growth() -> bool:
	var upgrade: Dictionary = Fixtures.defs_with_upgrades().upgrades["gen_up"]
	assert_eq(NxUpgrades.cost_at_level(upgrade, 0), {"matter": 20000}, "nível 0 = custo base")
	assert_eq(NxUpgrades.cost_at_level(upgrade, 1), {"matter": 32000})
	assert_eq(NxUpgrades.cost_at_level(upgrade, 2), {"matter": 51200})
	assert_eq(NxUpgrades.cost_at_level(upgrade, 3), {"matter": 81920})
	return true


func test_cost_rounds_up_but_ignores_float_noise() -> bool:
	var fractional := {"cost": {"matter": 1}, "growth": 1.5}
	assert_eq(NxUpgrades.cost_at_level(fractional, 1), {"matter": 2}, "1,5 sobe para 2")
	assert_eq(NxUpgrades.cost_at_level(fractional, 2), {"matter": 3}, "2,25 sobe para 3")
	assert_eq(NxUpgrades.cost_at_level(fractional, 3), {"matter": 4}, "3,375 sobe para 4")
	# 1.1 não é exato em binário: 3000 x 1,1 dá 3300.0000000000005 em ponto
	# flutuante e não pode custar 3301 (idem nos níveis seguintes).
	var noisy := {"cost": {"matter": 3000}, "growth": 1.1}
	assert_eq(NxUpgrades.cost_at_level(noisy, 1), {"matter": 3300})
	assert_eq(NxUpgrades.cost_at_level(noisy, 2), {"matter": 3630})
	assert_eq(NxUpgrades.cost_at_level(noisy, 3), {"matter": 3993})
	return true


func test_cost_saturates_instead_of_overflowing() -> bool:
	var extreme := {"cost": {"matter": 1000000000}, "growth": 10.0}
	var cost: Dictionary = NxUpgrades.cost_at_level(extreme, 100)
	assert_eq(cost["matter"], NxUpgrades.MAX_COST, "satura no teto")
	assert_true(cost["matter"] > 0, "nunca negativo")
	return true


func test_real_costs_never_decrease_with_level() -> bool:
	var defs := NxDefinitions.load_from_dir("res://data")
	for id: String in defs.upgrades:
		var upgrade: Dictionary = defs.upgrades[id]
		var previous: Dictionary = NxUpgrades.cost_at_level(upgrade, 0)
		for current_level in range(1, int(upgrade["max_level"]) + 1):
			var cost: Dictionary = NxUpgrades.cost_at_level(upgrade, current_level)
			for rid: String in cost:
				assert_true(cost[rid] >= previous[rid], "%s nível %d: custo de %s não decresce" % [id, current_level, rid])
			previous = cost
	return true


# --- compra --------------------------------------------------------------------

func test_purchase_debits_cost_and_raises_level() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.resources["matter"] = 100000
	var first := NxUpgradeService.purchase(state, defs, "gen_up")
	assert_true(first.ok)
	assert_eq(state.amount("matter"), 80000, "custo do nível 1")
	assert_eq(NxUpgrades.level(state, "gen_up"), 1)
	assert_eq(first.data["level"], 1)
	var second := NxUpgradeService.purchase(state, defs, "gen_up")
	assert_eq(state.amount("matter"), 48000, "custo do nível 2 é maior (32)")
	assert_eq(second.data["level"], 2)
	return true


func test_purchase_rejections_change_nothing() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs, ["production_upgrades"])
	state.resources["matter"] = 100000
	var before := state.state_hash()
	assert_eq(NxUpgradeService.purchase(state, defs, "fantasma").code, "unknown_upgrade")
	assert_eq(NxUpgradeService.purchase(state, defs, "col_eff").code, "locked", "falta o recurso data_upgrades")
	assert_eq(NxUpgradeService.purchase(state, defs, "global_up").code, "locked", "falta o recurso")
	state.features["data_upgrades"] = true
	before = state.state_hash()
	assert_eq(NxUpgradeService.purchase(state, defs, "global_up").code, "prerequisite_missing", "falta gen_up")
	assert_eq(state.state_hash(), before, "nada mudou")
	return true


func test_purchase_stops_at_max_level() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.resources["matter"] = 1000000000
	for i in range(4):
		assert_true(NxUpgradeService.purchase(state, defs, "gen_up").ok, "nível %d" % (i + 1))
	var before := state.state_hash()
	assert_eq(NxUpgradeService.purchase(state, defs, "gen_up").code, "max_level")
	assert_eq(state.state_hash(), before)
	return true


func test_purchase_without_funds_is_refused_without_side_effects() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.resources["matter"] = 19999                       # falta 0,001
	var before := state.state_hash()
	assert_eq(NxUpgradeService.purchase(state, defs, "gen_up").code, "insufficient_resources")
	assert_eq(state.state_hash(), before)
	state.resources["matter"] = 20000                       # exato: fica zerado
	assert_true(NxUpgradeService.purchase(state, defs, "gen_up").ok)
	assert_eq(state.amount("matter"), 0, "saldo zero é permitido, negativo não")
	return true


func test_multi_resource_purchase_is_atomic() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.upgrades["gen_up"] = 1
	state.resources["matter"] = 500000                      # sobra Matter...
	state.resources["data"] = 9999                          # ...mas falta Data (custa 10)
	var before := state.state_hash()
	assert_eq(NxUpgradeService.purchase(state, defs, "global_up").code, "insufficient_resources")
	assert_eq(state.state_hash(), before, "o Matter não pode ter sido cobrado")
	return true


func test_preview_reports_cost_effect_and_reason() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs, [])
	var locked := NxUpgradeService.preview(state, defs, "gen_up")
	assert_false(locked["available"])
	assert_eq(locked["reason"], "locked")
	state.features["production_upgrades"] = true
	state.resources["matter"] = 20000
	var ready := NxUpgradeService.preview(state, defs, "gen_up")
	assert_true(ready["available"] and ready["affordable"])
	assert_eq(ready["cost"], {"matter": 20000})
	assert_near(ready["effect_now"], 1.0, 0.0001)
	assert_near(ready["effect_next"], 1.25, 0.0001, "efeito do próximo nível, antes de comprar")
	NxUpgradeService.purchase(state, defs, "gen_up")
	var after := NxUpgradeService.preview(state, defs, "gen_up")
	assert_eq(after["cost"], {"matter": 32000}, "custo do nível seguinte")
	assert_false(after["affordable"], "saldo zerado")
	state.upgrades["gen_up"] = 4
	var maxed := NxUpgradeService.preview(state, defs, "gen_up")
	assert_eq(maxed["cost"], {}, "sem custo no nível máximo")
	assert_eq(maxed["reason"], "max_level")
	return true


# --- efeito no motor -------------------------------------------------------------

func test_output_upgrade_raises_production() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	Fixtures.add_connected(state, defs, "generator")
	state.upgrades["gen_up"] = 2                            # +50%
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 1000 + 2250, "Core 1,0 + gerador 1,5 x 1,5")
	return true


func test_upgrade_only_affects_its_target() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	Fixtures.add_connected(state, defs, "collector")
	state.resources["energy"] = 10000
	state.upgrades["gen_up"] = 4
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("matter"), 500, "o Collector não foi afetado")
	assert_eq(state.amount("energy"), 10000 + 1000 - 500, "o Core também não")
	return true


func test_global_upgrade_affects_every_producer_including_core() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	Fixtures.add_connected(state, defs, "generator")
	state.upgrades["gen_up"] = 1                            # x1,25 no gerador
	state.upgrades["global_up"] = 1                         # x1,10 em todos
	NxEconomyEngine.step(state, defs, DT)
	# Core 1000 x 1,1 = 1100; gerador 1500 x 1,25 x 1,1 = 2062,5 -> 2062.
	assert_eq(state.amount("energy"), 1100 + 2062)
	return true


func test_upgrade_stacks_with_the_processor_bonus() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	var processor := Fixtures.add_connected(state, defs, "processor")
	var generator := state.add_component("generator")
	NxNetwork.connect_components(state, defs, processor, generator)
	state.resources["energy"] = 10000
	state.upgrades["gen_up"] = 1
	NxEconomyEngine.step(state, defs, DT)
	# gerador: 1500 x 1,5 (Processor) x 1,25 (melhoria) = 2812,5 -> 2812.
	assert_eq(state.amount("energy"), 10000 + 1000 + 2812 - 800)
	return true


func test_efficiency_upgrade_reduces_consumption_not_output() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	Fixtures.add_connected(state, defs, "collector")
	state.resources["energy"] = 10000
	state.upgrades["col_eff"] = 2                           # consumo x0,8
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_eq(report.consumed["energy"], 400, "500 x 0,8")
	assert_eq(state.amount("matter"), 500, "a produção continua a mesma")
	return true


func test_efficiency_upgrade_relieves_a_shortage() -> bool:
	# Quatro Collectors pedem 2,0 com 1,0 disponível: 50%. Com consumo x0,5
	# a demanda cai para 1,0 e todos voltam a 100%.
	var defs := Fixtures.defs_with_upgrades()
	var starved := _state(defs)
	var relieved := _state(defs)
	for state in [starved, relieved]:
		for i in range(4):
			Fixtures.add_connected(state, defs, "collector")
	relieved.upgrades["col_eff"] = 5
	var before := NxEconomyEngine.step(starved, defs, DT)
	var after := NxEconomyEngine.step(relieved, defs, DT)
	assert_near(before.ratios["energy"], 0.5, 0.0001)
	assert_near(after.ratios["energy"], 1.0, 0.0001, "a falta de energia acabou")
	assert_true(relieved.amount("matter") > starved.amount("matter"), "mais Matter produzido")
	return true


func test_upgrades_do_not_break_conservation_or_negativity() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.resources["energy"] = 4000
	for kind in ["generator", "collector", "analyzer", "collector"]:
		Fixtures.add_connected(state, defs, kind)
	state.upgrades = {"gen_up": 3, "global_up": 2, "col_eff": 4}
	for step in range(200):
		var before := state.resources.duplicate()
		var report := NxEconomyEngine.step(state, defs, DT)
		for rid in defs.resource_ids:
			var expected: int = before[rid] + report.produced[rid] - report.consumed[rid] - report.lost[rid]
			assert_eq(state.amount(rid), expected, "conservação de %s no passo %d" % [rid, step])
			assert_true(state.amount(rid) >= 0, "%s nunca negativo" % rid)
	return true


func test_upgrade_state_round_trips() -> bool:
	var defs := Fixtures.defs_with_upgrades()
	var state := _state(defs)
	state.upgrades = {"gen_up": 3, "col_eff": 1}
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(state.to_dict())), OK)
	var copy := NxGameState.from_dict(json.data)
	assert_eq(copy.state_hash(), state.state_hash())
	assert_eq(NxUpgrades.level(copy, "gen_up"), 3)
	return true
