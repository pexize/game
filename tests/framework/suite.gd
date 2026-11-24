extends RefCounted
## Base de todas as suítes de teste do NEXUS.
##
## Uma suíte é um arquivo `tests/**/test_*.gd` que estende este script.
## Cada teste é um método `test_*` sem argumentos que termina com
## `return true`. Se o método morrer no meio (erro em tempo de execução),
## ele devolve `null` e o runner conta como falha.
##
## Não use `assert()` do GDScript: em build de debug ele interrompe o
## runner antes de `quit()` e o processo não termina.

var _case_name := ""
var _errors: PackedStringArray = PackedStringArray()


func _begin_case(case_name: String) -> void:
	_case_name = case_name
	_errors = PackedStringArray()


func _end_case() -> PackedStringArray:
	return _errors


func fail(message: String) -> void:
	_errors.append(message)


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		fail("esperado verdadeiro" + _suffix(message))


func assert_false(condition: bool, message := "") -> void:
	if condition:
		fail("esperado falso" + _suffix(message))


## Igualdade estrita: tipos diferentes (ex.: 1 e 1.0) contam como falha,
## o que importa para o determinismo da economia.
func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("esperado %s, obtido %s%s" % [
			var_to_str(expected), var_to_str(actual), _suffix(message)])


func assert_ne(actual: Variant, unexpected: Variant, message := "") -> void:
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		fail("não esperado %s%s" % [var_to_str(unexpected), _suffix(message)])


func assert_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if absf(actual - expected) > tolerance:
		fail("esperado %s ± %s, obtido %s%s" % [expected, tolerance, actual, _suffix(message)])


func assert_not_null(value: Variant, message := "") -> void:
	if value == null:
		fail("valor nulo" + _suffix(message))


func _suffix(message: String) -> String:
	return "" if message.is_empty() else " (%s)" % message
