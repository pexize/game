extends "res://tests/framework/suite.gd"
## Verifica o próprio framework: um assert que não registra falha
## deixaria todos os outros testes passando em silêncio.

const Suite := preload("res://tests/framework/suite.gd")


func _probe() -> RefCounted:
	var probe := Suite.new()
	probe._begin_case("probe")
	return probe


func test_assert_eq_records_mismatch() -> bool:
	var probe := _probe()
	probe.assert_eq(1, 2)
	assert_eq(probe._end_case().size(), 1, "assert_eq(1, 2) deve registrar falha")
	return true


func test_assert_eq_accepts_match() -> bool:
	var probe := _probe()
	probe.assert_eq({"energy": 10}, {"energy": 10})
	assert_eq(probe._end_case().size(), 0, "valores iguais não devem falhar")
	return true


func test_assert_eq_is_strict_about_types() -> bool:
	var probe := _probe()
	probe.assert_eq(1, 1.0)
	assert_eq(probe._end_case().size(), 1, "int e float não devem ser iguais")
	return true


func test_assert_near_respects_tolerance() -> bool:
	var probe := _probe()
	probe.assert_near(1.0, 1.05, 0.1)
	probe.assert_near(1.0, 1.5, 0.1)
	assert_eq(probe._end_case().size(), 1, "só o segundo assert_near deve falhar")
	return true


func test_begin_case_clears_previous_errors() -> bool:
	var probe := _probe()
	probe.fail("anterior")
	probe._begin_case("novo")
	assert_eq(probe._end_case().size(), 0, "erros do caso anterior não devem vazar")
	return true
