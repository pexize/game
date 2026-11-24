extends SceneTree
## Runner headless dos testes do NEXUS.
##
## Uso:
##   godot --headless --path . --script res://tests/runner.gd -- [--filter=texto]
##
## Procura `tests/**/test_*.gd`, executa cada método `test_*` e termina com
## código 1 se qualquer teste falhar, morrer no meio ou se nenhum teste
## for executado. O código de saída do Godot reflete apenas o que é
## passado a `quit()`; erros de script não o alteram por conta própria.

const SUITE_ROOT := "res://tests"
const SUITE_PREFIX := "test_"
const CASE_PREFIX := "test_"

var _passed := 0
var _failed := 0
var _failures: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var filter := _parse_filter()
	var paths := _find_suites(SUITE_ROOT)
	paths.sort()
	for path in paths:
		_run_suite(path, filter)

	print("")
	print("Resultado: %d passaram, %d falharam" % [_passed, _failed])
	for failure in _failures:
		print("  FALHA: " + failure)
	if _passed + _failed == 0:
		print("Nenhum teste executado (filtro: '%s')." % filter)
	quit(1 if _failed > 0 or _passed == 0 else 0)


func _parse_filter() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			return arg.trim_prefix("--filter=")
	return ""


func _find_suites(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_record("%s: diretório não pôde ser aberto" % dir_path)
		return result
	for sub in dir.get_directories():
		result.append_array(_find_suites(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with(SUITE_PREFIX) and file.ends_with(".gd"):
			result.append(dir_path.path_join(file))
	return result


func _run_suite(path: String, filter: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_record("%s: script não carregou (erro de sintaxe?)" % path)
		return
	var suite: Object = script.new()
	if not suite.has_method("_begin_case"):
		_record("%s: não estende res://tests/framework/suite.gd" % path)
		return

	var suite_name := path.get_file().get_basename()
	for method in script.get_script_method_list():
		var case_name: String = method["name"]
		if not case_name.begins_with(CASE_PREFIX):
			continue
		var full_name := "%s::%s" % [suite_name, case_name]
		if not filter.is_empty() and not full_name.contains(filter):
			continue

		suite.call("_begin_case", full_name)
		var returned: Variant = suite.call(case_name)
		var errors: PackedStringArray = suite.call("_end_case")
		if not (returned is bool and returned):
			errors.append("o teste não terminou (erro em tempo de execução ou falta 'return true')")

		if errors.is_empty():
			_passed += 1
			print("  ok     " + full_name)
		else:
			_failed += 1
			print("  FALHA  " + full_name)
			for error in errors:
				_failures.append("%s: %s" % [full_name, error])


func _record(message: String) -> void:
	_failed += 1
	_failures.append(message)
	print("  FALHA  " + message)
