extends "res://tests/framework/suite.gd"
## Salvamento: formato, escrita atômica, backups, recuperação e migrações.

const Fixtures := preload("res://tests/helpers/fixtures.gd")
const GOLDEN_SAVE := "res://tests/fixtures/saves/v1_midgame.json"

const T1 := 1700000000
const T2 := 1700000100
const T3 := 1700000200


func _defs() -> NxDefinitions:
	return Fixtures.defs_with_upgrades()


## Estado novo cujo saldo de Matter identifica "qual save é este".
func _state_with_matter(defs: NxDefinitions, matter: int) -> NxGameState:
	var state := NxGameState.new_game(defs)
	state.resources["matter"] = matter
	return state


func _saved_at(manager: NxSaveManager, file_name: String) -> int:
	var read := manager._read_payload(manager.path_of(file_name))
	return int(read.data["payload"]["saved_at"]) if read.ok else -1


func _manager(test_name: String) -> NxSaveManager:
	return NxSaveManager.new(Fixtures.temp_dir(test_name))


func _done(manager: NxSaveManager) -> void:
	Fixtures.remove_dir(manager.dir)


# --- ida e volta -----------------------------------------------------------------

func test_save_and_load_round_trip() -> bool:
	var defs := _defs()
	var manager := _manager("roundtrip")
	var state := Fixtures.rich_state(defs)
	assert_true(manager.save(state, defs, T1).ok)
	var loaded := manager.load_latest(defs)
	assert_true(loaded.ok, loaded.message)
	assert_eq(loaded.data["state"].state_hash(), state.state_hash(), "estado idêntico")
	assert_eq(loaded.data["saved_at"], T1)
	assert_eq(loaded.data["source"], "main")
	assert_false(loaded.data["recovered"])
	assert_eq(loaded.data["skipped"], [])
	_done(manager)
	return true


func test_save_preserves_network_discoveries_upgrades_and_automation() -> bool:
	var defs := _defs()
	var manager := _manager("preserve")
	var state := Fixtures.rich_state(defs)
	manager.save(state, defs, T1)
	var copy: NxGameState = manager.load_latest(defs).data["state"]
	assert_eq(copy.components.size(), state.components.size(), "componentes")
	for instance_id: int in state.components:
		assert_eq(copy.components[instance_id], state.components[instance_id], "componente #%d" % instance_id)
	assert_eq(copy.discoveries, state.discoveries, "descobertas")
	assert_eq(copy.upgrades, state.upgrades, "melhorias")
	assert_eq(copy.automation, state.automation, "automação")
	assert_eq(copy.features, state.features, "recursos liberados")
	assert_eq(NxNetwork.active_ids(copy, defs).size(), NxNetwork.active_ids(state, defs).size(), "rede ativa")
	_done(manager)
	return true


func test_file_format_has_checksum_and_versions() -> bool:
	var defs := _defs()
	var manager := NxSaveManager.new(Fixtures.temp_dir("format"), "9.9.9")
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	var outer := JSON.new()
	assert_eq(outer.parse(Fixtures.read_file(manager.path_of("save.json"))), OK, "JSON válido")
	assert_eq(outer.data["checksum"], str(outer.data["payload_json"]).sha256_text(), "checksum do conteúdo")
	var payload: Dictionary = JSON.parse_string(outer.data["payload_json"])
	assert_eq(int(payload["schema_version"]), NxSaveManager.SCHEMA_VERSION)
	assert_eq(payload["game_version"], "9.9.9")
	assert_eq(int(payload["saved_at"]), T1)
	_done(manager)
	return true


func test_invalid_state_is_never_written() -> bool:
	var defs := _defs()
	var manager := _manager("invalid_state")
	var state := _state_with_matter(defs, 1000)
	state.resources["energy"] = 999999999               # acima do armazenamento
	var result := manager.save(state, defs, T1)
	assert_eq(result.code, "invalid_state")
	assert_false(FileAccess.file_exists(manager.path_of("save.json")), "nada foi gravado")
	_done(manager)
	return true


func test_load_without_any_file() -> bool:
	var manager := _manager("empty")
	assert_eq(manager.load_latest(_defs()).code, "no_save")
	_done(manager)
	return true


# --- corrupção e recuperação ------------------------------------------------------------

func _two_saves(manager: NxSaveManager, defs: NxDefinitions) -> void:
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	manager.save(_state_with_matter(defs, 2000), defs, T2)  # main = 2000, bak1 = 1000


func test_corrupt_main_recovers_from_backup() -> bool:
	var defs := _defs()
	var manager := _manager("corrupt_main")
	_two_saves(manager, defs)
	Fixtures.write_file(manager.path_of("save.json"), "isto não é json {{{")
	var loaded := manager.load_latest(defs)
	assert_true(loaded.ok)
	assert_true(loaded.data["recovered"])
	assert_eq(loaded.data["source"], "backup1")
	assert_eq(loaded.data["state"].amount("matter"), 1000, "o save anterior")
	assert_eq(loaded.data["skipped"][0]["file"], "save.json")
	assert_eq(loaded.data["skipped"][0]["code"], "bad_format")
	_done(manager)
	return true


func test_truncated_main_is_detected() -> bool:
	var defs := _defs()
	var manager := _manager("truncated")
	_two_saves(manager, defs)
	var text := Fixtures.read_file(manager.path_of("save.json"))
	Fixtures.write_file(manager.path_of("save.json"), text.substr(0, text.length() / 2))
	var loaded := manager.load_latest(defs)
	assert_true(loaded.data["recovered"], "metade do arquivo não vale")
	assert_eq(loaded.data["state"].amount("matter"), 1000)
	_done(manager)
	return true


func test_tampered_content_fails_the_checksum() -> bool:
	var defs := _defs()
	var manager := _manager("tampered")
	_two_saves(manager, defs)
	var text := Fixtures.read_file(manager.path_of("save.json"))
	Fixtures.write_file(manager.path_of("save.json"), text.replace("2000", "9000"))   # edição manual de saldo
	var loaded := manager.load_latest(defs)
	assert_eq(loaded.data["skipped"][0]["code"], "checksum")
	assert_eq(loaded.data["state"].amount("matter"), 1000, "usa o backup, não o valor editado")
	_done(manager)
	return true


func test_empty_main_file_is_skipped() -> bool:
	var defs := _defs()
	var manager := _manager("empty_main")
	_two_saves(manager, defs)
	Fixtures.write_file(manager.path_of("save.json"), "")
	var loaded := manager.load_latest(defs)
	assert_eq(loaded.data["skipped"][0]["code"], "unreadable")
	assert_true(loaded.data["recovered"])
	_done(manager)
	return true


func test_semantically_invalid_state_with_valid_checksum_is_rejected() -> bool:
	# Arquivo íntegro (checksum certo) mas com estado impossível: também cai no backup.
	var defs := _defs()
	var manager := _manager("bad_state")
	_two_saves(manager, defs)
	var state := _state_with_matter(defs, 3000)
	var bad := state.to_dict()
	bad["components"]["1"]["parent"] = 1                  # o Core como pai de si mesmo
	var payload := {"schema_version": 1, "game_version": "x", "saved_at": T3, "state": bad}
	Fixtures.write_file(manager.path_of("save.json"), NxSaveManager._encode(payload))
	var loaded := manager.load_latest(defs)
	assert_eq(loaded.data["skipped"][0]["code"], "invalid_state")
	assert_eq(loaded.data["state"].amount("matter"), 1000)
	_done(manager)
	return true


func test_all_files_invalid_reports_and_keeps_every_file() -> bool:
	var defs := _defs()
	var manager := _manager("all_invalid")
	_two_saves(manager, defs)
	manager.save(_state_with_matter(defs, 3000), defs, T3)
	var contents := {}
	for file_name in ["save.json", "save.bak1.json", "save.bak2.json"]:
		Fixtures.write_file(manager.path_of(file_name), "lixo " + file_name)
		contents[file_name] = Fixtures.read_file(manager.path_of(file_name))
	var result := manager.load_latest(defs)
	assert_eq(result.code, "all_invalid")
	assert_eq(result.data["skipped"].size(), 3)
	for file_name: String in contents:
		assert_eq(Fixtures.read_file(manager.path_of(file_name)), contents[file_name], "%s não foi alterado" % file_name)
	_done(manager)
	return true


func test_loading_never_modifies_or_deletes_files() -> bool:
	var defs := _defs()
	var manager := _manager("readonly")
	_two_saves(manager, defs)
	Fixtures.write_file(manager.path_of("save.json"), "corrompido")
	var before := [Fixtures.read_file(manager.path_of("save.json")), Fixtures.read_file(manager.path_of("save.bak1.json"))]
	manager.load_latest(defs)
	assert_eq(Fixtures.read_file(manager.path_of("save.json")), before[0], "main intacto (mesmo corrompido)")
	assert_eq(Fixtures.read_file(manager.path_of("save.bak1.json")), before[1], "backup intacto")
	_done(manager)
	return true


# --- escrita atômica e backups ------------------------------------------------------------------

func test_backups_rotate_and_are_limited_to_two() -> bool:
	var defs := _defs()
	var manager := _manager("rotation")
	for step in range(4):
		manager.save(_state_with_matter(defs, 1000 * (step + 1)), defs, T1 + step)
	assert_eq(_saved_at(manager, "save.json"), T1 + 3, "o mais novo")
	assert_eq(_saved_at(manager, "save.bak1.json"), T1 + 2)
	assert_eq(_saved_at(manager, "save.bak2.json"), T1 + 1)
	var files := DirAccess.get_files_at(manager.dir)
	files.sort()
	assert_eq(Array(files), ["save.bak1.json", "save.bak2.json", "save.json"], "sem tmp nem backup extra")
	_done(manager)
	return true


func test_saving_over_a_corrupt_main_keeps_valid_backups() -> bool:
	# "Save corrompido não elimina automaticamente o backup" (critério de aceitação).
	var defs := _defs()
	var manager := _manager("keep_backups")
	for step in range(3):
		manager.save(_state_with_matter(defs, 1000 * (step + 1)), defs, T1 + step)   # main T1+2, bak1 T1+1, bak2 T1
	Fixtures.write_file(manager.path_of("save.json"), "corrompido")
	assert_true(manager.save(_state_with_matter(defs, 9000), defs, T3).ok)
	assert_eq(_saved_at(manager, "save.json"), T3, "o novo save é o principal")
	assert_eq(_saved_at(manager, "save.bak1.json"), T1 + 1, "bak1 intocado")
	assert_eq(_saved_at(manager, "save.bak2.json"), T1, "bak2 intocado")
	assert_eq(Fixtures.read_file(manager.path_of("save.corrupt.json")), "corrompido", "o corrompido ficou guardado")
	_done(manager)
	return true


func test_an_invalid_backup_never_overwrites_a_valid_one() -> bool:
	var defs := _defs()
	var manager := _manager("invalid_backup")
	for step in range(3):
		manager.save(_state_with_matter(defs, 1000 * (step + 1)), defs, T1 + step)
	Fixtures.write_file(manager.path_of("save.bak1.json"), "lixo")              # bak1 estragou
	assert_true(manager.save(_state_with_matter(defs, 9000), defs, T3).ok)
	assert_eq(_saved_at(manager, "save.bak2.json"), T1, "o bak2 válido não foi trocado pelo lixo do bak1")
	assert_eq(_saved_at(manager, "save.bak1.json"), T1 + 2, "main anterior virou bak1")
	_done(manager)
	return true


func test_truncated_write_is_caught_before_publishing() -> bool:
	# Disco cheio: o arquivo temporário sai pela metade. O save anterior não pode
	# ser girado para backup nem substituído.
	var defs := _defs()
	var manager := _manager("short_write")
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	var main_before := Fixtures.read_file(manager.path_of("save.json"))
	manager.writer = func(path: String, text: String) -> bool:
		Fixtures.write_file(path, text.substr(0, text.length() / 2))
		return true
	var result := manager.save(_state_with_matter(defs, 2000), defs, T2)
	assert_eq(result.code, "write_failed")
	assert_eq(Fixtures.read_file(manager.path_of("save.json")), main_before, "o save bom continua no lugar")
	assert_false(FileAccess.file_exists(manager.path_of("save.bak1.json")), "nada foi girado")
	assert_false(FileAccess.file_exists(manager.path_of("save.tmp")), "o temporário ruim foi removido")
	assert_eq(manager.load_latest(defs).data["state"].amount("matter"), 1000)
	_done(manager)
	return true


func test_failed_writer_reports_write_failed() -> bool:
	var defs := _defs()
	var manager := _manager("no_write")
	manager.writer = func(_path: String, _text: String) -> bool: return false
	assert_eq(manager.save(_state_with_matter(defs, 1000), defs, T1).code, "write_failed")
	assert_false(FileAccess.file_exists(manager.path_of("save.json")))
	_done(manager)
	return true


func test_stale_tmp_from_a_crash_does_not_affect_loading_or_saving() -> bool:
	var defs := _defs()
	var manager := _manager("stale_tmp")
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	Fixtures.write_file(manager.path_of("save.tmp"), "metade de um save que nunca foi publicado")
	var loaded := manager.load_latest(defs)
	assert_eq(loaded.data["state"].amount("matter"), 1000, "o tmp é ignorado")
	assert_true(manager.save(_state_with_matter(defs, 2000), defs, T2).ok)
	assert_false(FileAccess.file_exists(manager.path_of("save.tmp")), "tmp consumido pelo novo save")
	assert_eq(manager.load_latest(defs).data["state"].amount("matter"), 2000)
	_done(manager)
	return true


func test_crash_after_rotation_before_publish_loses_nothing() -> bool:
	# Simula a queda entre "main → bak1" e "tmp → main": não há save.json.
	var defs := _defs()
	var manager := _manager("crash_window")
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	manager.save(_state_with_matter(defs, 2000), defs, T2)
	DirAccess.rename_absolute(manager.path_of("save.json"), manager.path_of("save.bak1.json"))
	var loaded := manager.load_latest(defs)
	assert_true(loaded.ok)
	assert_eq(loaded.data["state"].amount("matter"), 2000, "o último save bom está em bak1")
	assert_true(loaded.data["recovered"])
	_done(manager)
	return true


# --- versões e migrações ---------------------------------------------------------------------

func _write_payload(manager: NxSaveManager, file_name: String, version: int, state: NxGameState, saved_at: int) -> void:
	DirAccess.make_dir_recursive_absolute(manager.dir)
	var payload := {"schema_version": version, "game_version": "x", "saved_at": saved_at, "state": state.to_dict()}
	Fixtures.write_file(manager.path_of(file_name), NxSaveManager._encode(payload))


func test_newer_save_is_not_replaced_by_an_old_backup() -> bool:
	var defs := _defs()
	var manager := _manager("too_new")
	manager.save(_state_with_matter(defs, 1000), defs, T1)
	manager.save(_state_with_matter(defs, 2000), defs, T2)           # bak1 = 1000
	_write_payload(manager, "save.json", 99, _state_with_matter(defs, 7000), T3)
	var result := manager.load_latest(defs)
	assert_eq(result.code, "version_too_new", "não cai silenciosamente no backup antigo")
	var before := Fixtures.read_file(manager.path_of("save.json"))
	assert_eq(manager.save(_state_with_matter(defs, 1), defs, T3 + 1).code, "newer_save_present", "recusa sobrescrever")
	assert_eq(Fixtures.read_file(manager.path_of("save.json")), before, "o save novo continua intacto")
	_done(manager)
	return true


## Migração de teste: o efeito observável é o saldo de Matter.
func _matter_migration(payload: Dictionary) -> Dictionary:
	payload["state"]["resources"]["matter"] = 5000
	return payload


func test_old_save_is_migrated_on_load() -> bool:
	var defs := _defs()
	var manager := _manager("migrate")
	_write_payload(manager, "save.json", 1, _state_with_matter(defs, 1000), T1)
	manager.schema_version = 2
	manager.migrations = {1: _matter_migration}
	var loaded := manager.load_latest(defs)
	assert_true(loaded.ok, loaded.message)
	assert_eq(loaded.data["state"].amount("matter"), 5000, "a migração foi aplicada")
	assert_eq(loaded.data["schema_version_on_disk"], 1)
	assert_eq(JSON.parse_string(JSON.parse_string(Fixtures.read_file(manager.path_of("save.json")))["payload_json"])["schema_version"], 1.0, "o arquivo antigo não foi reescrito ao carregar")
	# Ao salvar, passa a ficar na versão nova e carrega sem migrar.
	assert_true(manager.save(loaded.data["state"], defs, T2).ok)
	manager.migrations = {}
	var reloaded := manager.load_latest(defs)
	assert_eq(reloaded.data["schema_version_on_disk"], 2)
	assert_eq(reloaded.data["state"].amount("matter"), 5000)
	_done(manager)
	return true


func test_migrations_chain_in_order() -> bool:
	var defs := _defs()
	var manager := _manager("chain")
	_write_payload(manager, "save.json", 1, _state_with_matter(defs, 1000), T1)
	manager.schema_version = 3
	manager.migrations = {
		1: func(p: Dictionary) -> Dictionary:
			p["state"]["resources"]["matter"] = float(p["state"]["resources"]["matter"]) + 1
			return p,
		2: func(p: Dictionary) -> Dictionary:
			p["state"]["resources"]["matter"] = float(p["state"]["resources"]["matter"]) * 10
			return p,
	}
	assert_eq(manager.load_latest(defs).data["state"].amount("matter"), 10010, "(1000 + 1) x 10, nessa ordem")
	_done(manager)
	return true


func test_missing_or_failing_migration_is_reported_not_guessed() -> bool:
	var defs := _defs()
	var manager := _manager("bad_migration")
	_write_payload(manager, "save.json", 1, _state_with_matter(defs, 1000), T1)
	manager.schema_version = 2
	assert_eq(manager.load_latest(defs).data["skipped"][0]["code"], "no_migration")
	manager.migrations = {1: func(_p: Dictionary) -> Dictionary: return {}}
	assert_eq(manager.load_latest(defs).data["skipped"][0]["code"], "migration_failed")
	_done(manager)
	return true


func test_migrated_state_is_still_validated() -> bool:
	var defs := _defs()
	var manager := _manager("migrate_invalid")
	_write_payload(manager, "save.json", 1, _state_with_matter(defs, 1000), T1)
	manager.schema_version = 2
	manager.migrations = {1: func(p: Dictionary) -> Dictionary:
		p["state"]["stage"] = 99
		return p}
	assert_eq(manager.load_latest(defs).data["skipped"][0]["code"], "invalid_state")
	_done(manager)
	return true


func test_reference_v1_save_still_loads() -> bool:
	# Regressão permanente: um save gravado pela versão 1 precisa continuar carregando.
	var defs := _defs()
	var manager := _manager("golden")
	DirAccess.copy_absolute(GOLDEN_SAVE, manager.path_of("save.json"))
	var loaded := manager.load_latest(defs)
	assert_true(loaded.ok, loaded.message if not loaded.ok else "")
	var state: NxGameState = loaded.data["state"]
	assert_eq(loaded.data["saved_at"], 1700000000)
	assert_eq(state.components.size(), 9)
	assert_eq(state.next_instance_id, 10)
	assert_eq(Array(state.discoveries.keys()), ["grants"])
	assert_eq(state.upgrades, {"gen_up": 2})
	assert_eq(state.automation, {"enabled": true, "target": "gen_up"})
	assert_eq(state.state_hash(), "5698d2edfa9a4f35b6bc7e979a501512467582df93393baa0851aed355847330")
	_done(manager)
	return true
