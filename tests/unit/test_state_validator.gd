extends "res://tests/framework/suite.gd"
## O validador não pode confiar no save: cada tipo de corrupção é detectado
## sem derrubar o jogo (nenhum teste aqui pode gerar SCRIPT ERROR).

const Fixtures := preload("res://tests/helpers/fixtures.gd")


func _defs() -> NxDefinitions:
	return Fixtures.defs_with_upgrades()


## Dicionário válido, já passado por JSON (tudo vira float), como no disco.
func _valid(defs: NxDefinitions) -> Dictionary:
	var json := JSON.new()
	json.parse(JSON.stringify(Fixtures.rich_state(defs).to_dict()))
	return json.data


func _problems(data: Variant, defs: NxDefinitions) -> String:
	return "\n".join(NxStateValidator.validate_dict(data, defs))


func _expect_problem(mutate: Callable, fragment: String) -> void:
	var defs := _defs()
	var data := _valid(defs)
	mutate.call(data)
	var text := _problems(data, defs)
	assert_true(text.contains(fragment), "esperava '%s', obtido: '%s'" % [fragment, text])


func test_a_real_state_is_valid_after_a_json_round_trip() -> bool:
	var defs := _defs()
	assert_eq(_problems(_valid(defs), defs), "")
	return true


func test_rejects_non_objects_and_missing_fields() -> bool:
	var defs := _defs()
	for garbage: Variant in [null, 5, "texto", [], true]:
		assert_ne(_problems(garbage, defs), "", "lixo: %s" % var_to_str(garbage))
	var data := _valid(defs)
	data.erase("components")
	assert_true(_problems(data, defs).contains("falta o campo 'components'"))
	return true


func test_resource_problems() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["resources"]["plasma"] = 5, "recurso desconhecido")
	_expect_problem(func(d: Dictionary) -> void: d["resources"]["matter"] = -1, "inteiro ≥ 0")
	_expect_problem(func(d: Dictionary) -> void: d["resources"]["matter"] = 5.5, "inteiro ≥ 0")
	_expect_problem(func(d: Dictionary) -> void: d["resources"]["matter"] = "muito", "inteiro ≥ 0")
	_expect_problem(func(d: Dictionary) -> void: d["resources"]["energy"] = 100001, "armazenamento máximo")
	_expect_problem(func(d: Dictionary) -> void: d["resources"].erase("data"), "falta o recurso 'data'")
	_expect_problem(func(d: Dictionary) -> void: d["time_ms"] = -5, "time_ms")
	return true


func test_component_problems() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["components"]["2"]["def"] = "fantasma", "definição desconhecida")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["2"]["enabled"] = "sim", "enabled")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["2"]["parent"] = -1, "parent")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["2"].erase("parent"), "parent")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["abc"] = d["components"]["2"], "id inválido")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["3"] = 7, "não é um objeto")
	_expect_problem(func(d: Dictionary) -> void: d["next_instance_id"] = 2, "next_instance_id")
	return true


func test_tree_problems() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["components"]["2"]["parent"] = 99, "não existe")
	_expect_problem(func(d: Dictionary) -> void: d["components"]["1"]["parent"] = 2, "Core")
	_expect_problem(func(d: Dictionary) -> void:
		d["components"]["2"]["parent"] = 3
		d["components"]["3"]["parent"] = 2, "ciclo")
	_expect_problem(func(d: Dictionary) -> void:
		d["components"].erase("1"), "exatamente um Core")
	_expect_problem(func(d: Dictionary) -> void:
		d["components"]["50"] = {"def": "core", "enabled": true, "parent": 0}
		d["next_instance_id"] = 51, "exatamente um Core")
	return true


func test_unlocked_and_features() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["unlocked"].append("fantasma"), "unlocked")
	_expect_problem(func(d: Dictionary) -> void: d["unlocked"] = "tudo", "'unlocked' deve ser uma lista")
	_expect_problem(func(d: Dictionary) -> void: d["features"].append("trapaca"), "recurso desconhecido")
	return true


func test_discovery_problems() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["discoveries"]["fantasma"] = {"order": 2, "time_ms": 0}, "descoberta desconhecida")
	_expect_problem(func(d: Dictionary) -> void: d["discoveries"]["grants"]["order"] = 5, "ordem das descobertas")
	_expect_problem(func(d: Dictionary) -> void: d["discoveries"]["grants"]["time_ms"] = -1, "inválidos")
	_expect_problem(func(d: Dictionary) -> void: d["condition_progress"]["grants"] = {"0": 5}, "já concedida")
	_expect_problem(func(d: Dictionary) -> void: d["stage"] = 99, "'stage'")
	_expect_problem(func(d: Dictionary) -> void: d["stage"] = 0, "'stage'")
	return true


func test_discovery_without_its_prerequisite_is_invalid() -> bool:
	var raw := [
		{"id": "a", "conditions": [{"type": "active_component_count", "min": 1}]},
		{"id": "b", "prerequisites": ["a"], "conditions": [{"type": "active_component_count", "min": 1}]},
	]
	var defs := NxDefinitions.from_dicts(Fixtures.raw_resources(), Fixtures.raw_components(), Fixtures.raw_balance(), raw)
	var state := NxGameState.new_game(defs)
	state.discoveries["b"] = {"order": 1, "time_ms": 0}      # b sem a
	assert_true("\n".join(NxStateValidator.validate_state(state, defs)).contains("pré-requisito"))
	return true


func test_sustained_counter_must_match_a_sustained_condition() -> bool:
	var raw := [{"id": "s", "conditions": [
		{"type": "active_component_count", "min": 99},
		{"type": "sustained", "seconds": 5, "condition": {"type": "active_component_count", "min": 1}},
	]}]
	var defs := NxDefinitions.from_dicts(Fixtures.raw_resources(), Fixtures.raw_components(), Fixtures.raw_balance(), raw)
	var state := NxGameState.new_game(defs)
	state.condition_progress["s"] = {"1": 3000}
	assert_eq("\n".join(NxStateValidator.validate_state(state, defs)), "", "contador da condição sustentada")
	state.condition_progress["s"] = {"0": 3000}               # a 0 não é sustentada
	assert_true("\n".join(NxStateValidator.validate_state(state, defs)).contains("não corresponde"))
	state.condition_progress["s"] = {"7": 3000}
	assert_true("\n".join(NxStateValidator.validate_state(state, defs)).contains("não corresponde"))
	return true


func test_upgrade_and_automation_problems() -> bool:
	_expect_problem(func(d: Dictionary) -> void: d["upgrades"]["fantasma"] = 1, "melhoria desconhecida")
	_expect_problem(func(d: Dictionary) -> void: d["upgrades"]["gen_up"] = 99, "nível fora")
	_expect_problem(func(d: Dictionary) -> void: d["upgrades"]["gen_up"] = 0, "nível fora")
	_expect_problem(func(d: Dictionary) -> void: d["automation"]["target"] = "fantasma", "automation")
	_expect_problem(func(d: Dictionary) -> void: d["automation"]["enabled"] = "sim", "automation")
	_expect_problem(func(d: Dictionary) -> void: d["automation"] = 7, "automation")
	return true


func test_validate_never_crashes_on_wrong_types() -> bool:
	# Todos os campos com o tipo errado: precisa devolver erros, nunca travar.
	var defs := _defs()
	for key in NxStateValidator.REQUIRED_KEYS:
		for wrong: Variant in [null, "x", 7, [], {}, true]:
			var data := _valid(defs)
			data[key] = wrong
			var problems := NxStateValidator.validate_dict(data, defs)
			if key in ["next_instance_id", "time_ms", "stage"] and wrong is int and wrong >= 1:
				continue
			assert_true(problems.size() > 0 or wrong is Array and key in ["unlocked", "features"] or wrong is Dictionary and wrong.is_empty() and key in ["upgrades", "discoveries", "condition_progress"],
				"campo '%s' com valor %s deveria ser recusado" % [key, var_to_str(wrong)])
	return true
