extends "res://tests/framework/suite.gd"
## Testes de fumaça da configuração do projeto (Fase 0).


func test_engine_version_is_pinned() -> bool:
	var info := Engine.get_version_info()
	assert_eq(info["major"], 4, "versão major")
	assert_eq(info["minor"], 7, "versão minor (D-023 fixa 4.7.x)")
	return true


func test_main_scene_instantiates() -> bool:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_eq(path, "res://scenes/main/main.tscn", "cena principal configurada")
	var packed := load(path) as PackedScene
	assert_not_null(packed, "cena principal carrega")
	var node := packed.instantiate()
	assert_not_null(node, "cena principal instancia")
	node.free()
	return true


func test_portrait_orientation() -> bool:
	var orientation: int = ProjectSettings.get_setting("display/window/handheld/orientation", -1)
	assert_eq(orientation, DisplayServer.SCREEN_PORTRAIT, "orientação retrato")
	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	assert_true(height > width, "viewport mais alto que largo")
	return true


func test_compatibility_renderer() -> bool:
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", ""),
		"gl_compatibility",
		"renderer de aparelhos móveis (D-026)")
	return true
