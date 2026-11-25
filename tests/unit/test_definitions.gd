extends "res://tests/framework/suite.gd"
## Carregamento e validação das definições (recursos, componentes, balance).

const Fixtures := preload("res://tests/helpers/fixtures.gd")


func _errors_of(raw_resources: Array, raw_components: Array, raw_balance: Dictionary) -> PackedStringArray:
	return NxDefinitions.from_dicts(raw_resources, raw_components, raw_balance).errors


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false


func test_real_data_is_valid() -> bool:
	var defs := NxDefinitions.load_from_dir("res://data")
	assert_eq("\n".join(defs.errors), "", "data/ deve validar sem erros")
	assert_eq(defs.resource_ids, PackedStringArray(["energy", "matter", "data"]), "ordem por tier")
	assert_true(defs.components.has("core"), "tem o Core")
	return true


func test_fixture_defs_are_valid() -> bool:
	assert_eq("\n".join(Fixtures.defs().errors), "")
	return true


func test_amounts_are_converted_to_milli() -> bool:
	var defs := Fixtures.defs()
	assert_eq(defs.components["generator"]["cost"]["energy"], 10000, "custo 10 -> 10000")
	assert_eq(defs.components["collector"]["outputs"]["matter"], 500, "taxa 0.5/s -> 500")
	assert_eq(defs.max_storage("energy"), 100000, "armazenamento 100 -> 100000")
	assert_eq(defs.max_storage("matter"), NxDefinitions.UNLIMITED, "sem limite")
	assert_eq(defs.balance["start_resources"]["matter"], 10000, "reserva inicial")
	return true


func test_rejects_unknown_resource_reference() -> bool:
	var components := Fixtures.raw_components()
	components[1]["cost"] = {"plasma": 5}
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance()), "plasma"))
	return true


func test_rejects_resource_cycle() -> bool:
	# Consome matter (tier 1) e produz energy (tier 0): fecharia um ciclo.
	var components := Fixtures.raw_components()
	components[2]["inputs"] = {"matter": 1.0}
	components[2]["outputs"] = {"energy": 2.0}
	var errors := _errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance())
	assert_true(_has_error(errors, "cadeia de recursos"), "deve apontar a quebra da cadeia")
	return true


func test_rejects_component_consuming_its_own_output() -> bool:
	var components := Fixtures.raw_components()
	components[2]["inputs"] = {"matter": 1.0}
	components[2]["outputs"] = {"matter": 2.0}
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance()), "cadeia de recursos"))
	return true


func test_rejects_non_positive_amounts() -> bool:
	var components := Fixtures.raw_components()
	components[1]["cost"] = {"energy": -3}
	components[2]["outputs"] = {"matter": 0}
	var errors := _errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance())
	assert_true(_has_error(errors, "cost.energy"), "custo negativo")
	assert_true(_has_error(errors, "outputs.matter"), "taxa zero")
	return true


func test_rejects_unknown_field() -> bool:
	var components := Fixtures.raw_components()
	components[1]["outpus"] = {"energy": 1}
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance()), "outpus"))
	return true


func test_rejects_duplicate_ids() -> bool:
	var components := Fixtures.raw_components()
	components.append({"id": "generator", "outputs": {"energy": 1.0}})
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance()), "duplicado"))
	return true


func test_rejects_missing_or_removable_core() -> bool:
	var balance := Fixtures.raw_balance()
	balance["core_component"] = "nao_existe"
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), Fixtures.raw_components(), balance), "core_component"))
	var components := Fixtures.raw_components()
	components[0]["removable"] = true
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), components, Fixtures.raw_balance()), "removable"))
	return true


func test_rejects_unwinnable_start_d014() -> bool:
	# Collector custa 10 matter e a reserva é 5: ninguém produz matter sem ele.
	var balance := Fixtures.raw_balance()
	balance["start_resources"] = {"energy": 5, "matter": 5}
	var errors := _errors_of(Fixtures.raw_resources(), Fixtures.raw_components(), balance)
	assert_true(_has_error(errors, "D-014"), "deve apontar o risco de bloqueio")
	return true


func test_accepts_start_cost_in_core_resource() -> bool:
	# O Generator custa energy, que o Core produz: não exige reserva inicial.
	var balance := Fixtures.raw_balance()
	balance["start_resources"] = {"matter": 10}
	assert_eq("\n".join(_errors_of(Fixtures.raw_resources(), Fixtures.raw_components(), balance)), "")
	return true


func test_rejects_invalid_offline_parameters() -> bool:
	var balance := Fixtures.raw_balance()
	balance["offline_efficiency"] = 1.5
	balance["removal_refund"] = -0.1
	var errors := _errors_of(Fixtures.raw_resources(), Fixtures.raw_components(), balance)
	assert_true(_has_error(errors, "offline_efficiency"))
	assert_true(_has_error(errors, "removal_refund"))
	return true


func test_rejects_unknown_start_unlocked() -> bool:
	var balance := Fixtures.raw_balance()
	balance["start_unlocked"] = ["generator", "fantasma"]
	assert_true(_has_error(_errors_of(Fixtures.raw_resources(), Fixtures.raw_components(), balance), "fantasma"))
	return true


func test_missing_directory_is_reported_without_crashing() -> bool:
	var defs := NxDefinitions.load_from_dir("res://nao_existe")
	assert_false(defs.is_valid(), "diretório inexistente invalida")
	return true
